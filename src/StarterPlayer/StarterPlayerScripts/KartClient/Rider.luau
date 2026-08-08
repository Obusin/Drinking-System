--[[
	Rider — turns the steering wheel and puts the driver's hands on it.

	Runs for EVERY kart in the world, not just the one we're driving, so
	you see other players steering too. It keys off
	`VehicleSeat.SteerFloat`, which Roblox replicates from the driver, so
	no custom networking is needed. Purely cosmetic; never touches
	movement.

	TWO DIFFERENT JOINT PROBLEMS, TWO DIFFERENT TOOLS
	-------------------------------------------------
	The steering wheel is a Motor6D on the kart. Nothing else touches it,
	so writing `Transform` directly is fine.

	The driver's arms are Motor6Ds on a CHARACTER, and there the Animator
	owns `Transform` — it recomposes those joints every frame from the
	playing animation, so anything a script writes is discarded. The
	obvious workarounds both fail:

	  - write `C0` instead: read-only from a client script on character
	    joints, the engine rejects it outright
	  - stop the animation so nothing overwrites us: the Animator then
	    stops flushing joints at all, our writes go nowhere AND the
	    driver stands bolt upright instead of sitting

	So the arms use `IKControl`, which the animation system applies
	itself. It layers over the sit pose rather than fighting it, and it
	costs one instance per arm instead of a per-frame solve.
--]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local RunService = game:GetService("RunService")

local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))
local Simulation = require(BloxKart:WaitForChild("Simulation"))
local Util = require(BloxKart:WaitForChild("Util"))
local WorldFilter = require(BloxKart:WaitForChild("WorldFilter"))

local R = Config.Rider
local H = Config.Handling
local GLD = Config.Glide
local FX = Config.Effects
local RIG = Config.Rig
local SW = Config.Swim
local SUS = Config.Suspension
local KART_TAG = "Kart"

local Rider = {}

--=====================================================================
--  RIG LOOKUP
--=====================================================================
local function findRig(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	-- R15
	local upperTorso = character:FindFirstChild("UpperTorso")
	local lHand = character:FindFirstChild("LeftHand")
	local rHand = character:FindFirstChild("RightHand")
	if upperTorso and lHand and rHand then
		return {
			humanoid = humanoid,
			torso = upperTorso,
			lRoot = if R.IKChainFromTorso then upperTorso else character:FindFirstChild("LeftUpperArm"),
			rRoot = if R.IKChainFromTorso then upperTorso else character:FindFirstChild("RightUpperArm"),
			lHand = lHand,
			rHand = rHand,
		}
	end

	-- R6: one bone per arm, so the chain can only ever be torso -> arm.
	local torso = character:FindFirstChild("Torso")
	local lArm = character:FindFirstChild("Left Arm")
	local rArm = character:FindFirstChild("Right Arm")
	if torso and lArm and rArm then
		return {
			humanoid = humanoid,
			torso = torso,
			lRoot = torso,
			rRoot = torso,
			lHand = lArm,
			rHand = rArm,
		}
	end

	return nil
end

--=====================================================================
--  IK CONTROLS
--
--  Parented to the Humanoid, which is what makes the animation system
--  apply them. Created once and left alone; the Target is a live
--  reference, so as the wheel turns the hands follow with no per-frame
--  work from us.
--=====================================================================
-- Elbow hint. Lives on the hitbox so it rides with the kart, and is
-- client-local like everything else here.
local function makePole(hitbox: BasePart, name: string, offset: Vector3): Attachment
	local att = Instance.new("Attachment")
	att.Name = name
	att.Position = offset
	att.Parent = hitbox
	return att
end

local function makeControl(
	name: string,
	rig,
	root: Instance?,
	endEffector: Instance,
	target: Instance,
	pole: Attachment?,
	priority: number
)
	if not root then
		return nil
	end
	local ik = Instance.new("IKControl")
	ik.Name = name
	ik.Type = Enum.IKControlType.Position
	ik.ChainRoot = root
	ik.EndEffector = endEffector
	ik.Target = target
	-- Without this the solver puts the elbow wherever it likes on the
	-- circle around the shoulder-hand axis, which is always straight out
	-- sideways.
	if pole then
		ik.Pole = pole
	end
	ik.Weight = R.IKWeight
	ik.SmoothTime = R.IKSmoothTime
	-- Distinct priorities so the solve order is deterministic rather
	-- than whichever control happened to be created first. Only bites
	-- when the chains overlap (IKChainFromTorso), but a stable order is
	-- worth having either way.
	ik.Priority = priority
	ik.Enabled = true
	ik.Parent = rig.humanoid
	return ik
end

local function clearControls(s)
	for _, key in { "ikL", "ikR", "poleL", "poleR" } do
		if s[key] then
			s[key]:Destroy()
			s[key] = nil
		end
	end
end

--=====================================================================
--  PER-KART STATE
--=====================================================================
local state: { [Model]: any } = {}

local function stateFor(kart: Model)
	local s = state[kart]
	if not s then
		s = {
			steer = 0,
			wheelSteer = 0,
			roll = 0,
			lastPos = nil,
			counter = 0,
			lastDrift = nil,
			driftRate = 0,
			saw = 0,
			rig = nil,
			ikL = nil,
			ikR = nil,
			boundTo = nil,
		}
		state[kart] = s
	end
	return s
end

-- Rate-limited so a per-frame failure doesn't flood Output. Prints only
-- when the reason changes, or once a second.
local lastReason, lastReasonAt = nil, 0
local function report(reason: string?)
	if not R.Debug then
		return
	end
	local now = os.clock()
	if reason ~= lastReason or now - lastReasonAt > 1 then
		lastReason, lastReasonAt = reason, now
		print("[Rider] " .. (reason or "hands on the wheel"))
	end
end

--=====================================================================
--  COUNTER-STEER
--
--  What a drift driver is actually DOING, expressed as an equivalent
--  steering input (-1..1) so the steering wheel and the road wheels can
--  both use it.
--
--  A fixed offset proportional to the slide angle is not what
--  counter-steering looks like. A driver holding a drift is never still:
--  they catch the slide as it develops, ease off as it settles, and saw
--  at the wheel the whole way through. Three terms, and the middle one
--  is the one that sells it:
--
--    HOLD   proportional to the slide — points the wheels down the road
--    CATCH  proportional to how fast the slide is CHANGING — cranks hard
--           while the rear is stepping out, unwinds as it hooks up. This
--           is the correction itself rather than its result, and it's why
--           the wheels move during a steady drift instead of sitting
--           parked at an angle
--    SAW    a small oscillation scaled by how sideways you are — the
--           constant micro-corrections nobody makes deliberately
--=====================================================================
local function counterSteer(kart: Model, s, dt: number): number
	local drift = kart:GetAttribute(Names.DRIFT)
	drift = if typeof(drift) == "number" then drift else 0

	-- Rate of change, smoothed — a raw frame-to-frame difference is pure
	-- jitter and would make the wheels buzz rather than correct.
	local raw = (drift - (s.lastDrift or drift)) / math.max(dt, 1e-3)
	s.lastDrift = drift
	s.driftRate = Util.approach(s.driftRate or 0, raw, RIG.RoadWheelCatchSmoothing, dt)

	local maxLock = math.rad(RIG.RoadWheelSteer)
	local hold = drift * RIG.RoadWheelCounterSteer
	local catch = s.driftRate * RIG.RoadWheelCatch

	-- Only while actually sideways, and faded in with the slide so it
	-- doesn't twitch on a straight.
	local sideways = math.clamp(math.abs(drift) / maxLock, 0, 1)
	-- Shared with the road wheels: how far through the crossfade from
	-- "following the stick" to "catching the slide" we are.
	s.slide = sideways
	s.saw = (s.saw or 0) + dt * RIG.RoadWheelSawRate
	local saw = math.sin(s.saw * math.pi * 2) * RIG.RoadWheelSaw * sideways

	-- Negated: the wheels point AGAINST the way the body has swung.
	return math.clamp(-(hold + catch + saw) / maxLock, -1, 1)
end

--=====================================================================
--  ROAD WHEELS
--
--  Cosmetic only — the hitbox decides how the kart moves, and these just
--  have to look like they belong to it. Fronts steer and roll, rears
--  roll.
--
--  Roll comes from how far the kart actually MOVED, not from a speed
--  value: this runs for every kart including other people's, and their
--  speed isn't replicated. Distance between frames is, because their
--  position is.
--=====================================================================
--=====================================================================
--  SUSPENSION — visual only, and that is load-bearing.
--
--  Each wheel asks its OWN patch of ground how far away it is, and its
--  visual height chases that through a damped spring. Nothing here is
--  read by Simulation: the kart's path is decided by the Hitbox exactly
--  as before, and these rays only decide where the art sits on it.
--
--  WHY A SPRING RATHER THAN A CHASE. Util.approach reaches the target
--  and stops, which reads as the wheel being dragged into place. A
--  spring overshoots and settles, and that overshoot IS the bounce.
--
--  ONE RAY PER WHEEL PER FRAME. Eight karts is 32 rays, which is
--  nothing next to the sweep the controller already does every step.
--=====================================================================

local function suspensionFor(kart: Model, motor: Motor6D, hitbox: BasePart, s, dt: number, up: Vector3): number
	if not SUS.Enabled then
		return 0
	end

	local key = motor
	s.ride = s.ride or {}
	s.rideVel = s.rideVel or {}
	local current = s.ride[key] or 0
	local vel = s.rideVel[key] or 0

	-- The joint origin is the wheel's axle, in world space, with no
	-- transform applied — its RESTING place. Everything below is measured
	-- from there, so the spring cannot wander: there is no accumulated
	-- position to drift, only an offset from a point recomputed each frame.
	local rest = (hitbox.CFrame * motor.C0).Position

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- The kart cannot be its own ground. Every kart is excluded, not just
	-- this one, for the same reason the controller's sweep excludes them:
	-- another racer's bodywork is not a road surface.
	params.FilterDescendantsInstances = WorldFilter.rayParams.FilterDescendantsInstances
	params.IgnoreWater = true

	local radius = math.max(RIG.RoadWheelRadius + SUS.RadiusTrim, 0.05)
	local hit = workspace:Raycast(rest, -up * (radius + SUS.RayLength), params)

	-- Positive compresses the wheel up into the arch; negative droops it.
	local target = -SUS.Droop
	if hit then
		target = math.clamp(radius - hit.Distance, -SUS.Droop, SUS.Travel)
	end

	-- LANDING. A spring alone barely notices a hard arrival, because the
	-- wheel only ever has Travel studs to give. Extra compression scaled
	-- by how fast we were actually falling is the difference between
	-- touching down and ARRIVING.
	local fall = s.fallSpeed or 0
	if hit and fall > SUS.LandingSpeed and not s.wasGrounded then
		target += math.min(fall * SUS.LandingKick, SUS.LandingMax)
	end
	s.wasGrounded = hit ~= nil

	-- Damped spring, integrated per second so it is framerate independent
	-- — the same rule the drift scrub had to learn.
	vel += (target - current) * SUS.Stiffness * dt
	-- exp(-rate * dt), which is the framerate-independent form of "lose
	-- this much velocity per second". `Damping ^ dt` reads like the same
	-- thing and is not: it treats Damping as a FRACTION KEPT, and at 60fps
	-- 0.82^(1/60) is 0.9967 — so the wheel oscillated more or less
	-- forever. Same shape of units bug the drift scrub had.
	vel *= math.exp(-SUS.Damping * dt)
	current += vel * dt
	-- Clamped AFTER integrating, so a violent landing cannot push the
	-- wheel through the bodywork and back out.
	current = math.clamp(current, -SUS.Droop, SUS.Travel)

	s.ride[key] = current
	s.rideVel[key] = vel
	return current
end

--=====================================================================
--  THE SEA
--
--  h(x, z, t) as a sum of directional waves. Sampled at the kart's
--  POSITION rather than driven by time alone, which is the whole
--  difference between water and a vibrating kart: the swell exists in
--  the world, so you drive through it, you take it at an angle, and two
--  karts side by side are on different parts of the same wave.
--=====================================================================
-- ONE FIELD, SHARED WITH THE SIMULATION. The hull's motion and the
-- impulses that actually throw the kart must agree about where the water
-- is, and the only way to guarantee that is for there to be one copy.
local waveAt = Simulation.waveAt

--=====================================================================
--  BODY ROLL — the payoff for four separate wheels.
--
--  Read entirely off the suspension that already exists, so the body
--  cannot disagree with what the wheels are doing. A kart leaning left
--  while its left wheels are extended is the uncanny version of this,
--  and deriving both from one source makes it impossible rather than
--  merely unlikely.
--
--  SIGNS, worked out once so nobody has to do it again:
--    CFrame.Angles(0, 0, r) turns about +Z, which is BACKWARD (LookVector
--    is -Z), so +X goes to +Y — positive roll lifts the RIGHT side.
--    CFrame.Angles(p, 0, 0) turns about +X (right), so +Y goes to +Z —
--    positive pitch lifts the NOSE.
--
--  Compression is positive: the wheel has been pushed UP into the arch,
--  which means the ground is higher there and that side of the body
--  should rise with it.
--=====================================================================
-- THE FLIP, READ ONCE PER FRAME AND APPLIED TO EVERYTHING.
--
-- A flip that turns only the bodywork leaves the wheels hanging level in
-- mid-air while the shell rotates around them, which reads as the kart
-- coming apart. The whole thing has to turn, so both the body motor and
-- every wheel motor get the same rotation.
--
-- Nothing here touches the simulation: the kart flies an ordinary arc
-- and lands level whatever the art did.
local function updateBody(kart: Model, s, dt: number)
	local motor = kart:FindFirstChild("BodyMotor", true)
	if not (motor and motor:IsA("Motor6D")) then
		return
	end

	-- Gather the four corners. Front/rear comes off the attribute the
	-- factory set; left/right off the sign of the joint's own X, which is
	-- already in the hitbox's frame and therefore already means "left".
	local fl, fr, rl, rr, n = 0, 0, 0, 0, 0
	for _, m in kart:GetDescendants() do
		if m:IsA("Motor6D") and m.Name == "RoadWheelMotor" then
			local ride = (s.ride and s.ride[m]) or 0
			local front = m:GetAttribute(Names.WHEEL_FRONT) == true
			local left = m.C0.Position.X < 0
			if front and left then
				fl = ride
			elseif front then
				fr = ride
			elseif left then
				rl = ride
			else
				rr = ride
			end
			n += 1
		end
	end
	if n == 0 then
		return
	end

	local leftSide, rightSide = (fl + rl) * 0.5, (fr + rr) * 0.5
	local frontAxle, rearAxle = (fl + fr) * 0.5, (rl + rr) * 0.5

	-- Right side compressed -> right side rises -> positive roll.
	local roll = (rightSide - leftSide) * RIG.BodyRollPerStud
	-- Front compressed -> nose rises -> positive pitch.
	local pitch = (frontAxle - rearAxle) * RIG.BodyPitchPerStud

	-- AUTHORED LEAN ON TOP. Suspension alone gives you bumps; this gives
	-- you cornering, which is the part players actually read as weight.
	-- Outward, away from the turn — leaning into it reads as a motorbike.
	local rawSteer: any = kart:GetAttribute(Names.STEER)
	local steer = if type(rawSteer) == "number" then math.clamp(rawSteer, -1, 1) else 0
	local rawDrift: any = kart:GetAttribute(Names.DRIFT)
	local drift = if type(rawDrift) == "number" then math.clamp(rawDrift / 40, -1, 1) else 0
	roll += steer * RIG.BodyRollPerSteer + drift * RIG.BodyRollPerDrift

	roll = math.clamp(roll, -RIG.BodyRollMax, RIG.BodyRollMax)
	pitch = math.clamp(pitch, -RIG.BodyPitchMax, RIG.BodyPitchMax)

	-- SQUASH. The body drops toward the wheels as they compress, which is
	-- what makes a landing land rather than merely stop.
	local dip = (leftSide + rightSide) * 0.5 * RIG.BodySquash

	-- Chased. The suspension is already sprung; this is the bodywork's own
	-- softness on top of it, and it is what stops a sharp bump snapping
	-- the whole shell sideways.
	local blend = math.min(RIG.BodyRate * dt, 1)
	s.bodyRoll = (s.bodyRoll or 0) + (roll - (s.bodyRoll or 0)) * blend
	s.bodyPitch = (s.bodyPitch or 0) + (pitch - (s.bodyPitch or 0)) * blend
	s.bodyDip = (s.bodyDip or 0) + (dip - (s.bodyDip or 0)) * blend

	-- FLOATING RIDES THE SAME MOTOR as roll and squash, so it composes
	-- with them rather than fighting: a kart landing in water still dips,
	-- it just dips while bobbing.
	--
	-- Two sines at unrelated rates. One reads as a machine; two reads as
	-- water, and it costs a single extra term.
	local wet = s.wet or 0
	local bob = 0
	if wet > 0.001 then
		local hitbox = kart.PrimaryPart
		local pos = if hitbox then hitbox.Position else Vector3.zero
		local cf = if hitbox then hitbox.CFrame else CFrame.new()
		-- THE SIMULATION'S CLOCK, not a second one. Rider used to advance
		-- its own, and two clocks stepped by dt from different starting
		-- moments drift — putting the visual crest and the burst meant to
		-- accompany it on different waves.
		local shared = kart:GetAttribute(Names.SEA_CLOCK)
		s.seaT = if typeof(shared) == "number" then shared else (s.seaT or 0) + dt

		-- Driving fast into a swell hits harder than drifting over it, so
		-- the whole sea scales with speed. A moored kart wallows.
		local pace = math.clamp((s.speedNow or 0) / math.max(H.MaxSpeed, 1), 0, 1)
		local amp = wet * (1 + SW.SlamAtSpeed * pace)

		local here = waveAt(pos, s.seaT) * amp

		-- SPRUNG AGAINST THE SURFACE, not welded to it. Following the
		-- water rigidly is the difference between floating and being
		-- parented to a moving plane; the overshoot is the bounce.
		s.heaveV = (s.heaveV or 0) + (here - (s.heave or 0)) * SW.HeaveStiffness * dt
		s.heaveV *= math.exp(-SW.HeaveDamping * dt)
		s.heave = (s.heave or 0) + s.heaveV * dt
		bob = s.heave

		-- PITCH AND ROLL ARE THE SLOPE OF THE WATER. Sampling the field
		-- fore/aft and left/right and taking the difference means the hull
		-- always lies along the wave it is actually on — heave and tilt
		-- are the same field, so they can never disagree.
		local d = SW.WaveSample
		-- WITHOUT `amp`. Speed scales how hard the hull HEAVES over a wave,
		-- not how steeply it lies against one — a fast boat does not tilt
		-- more on the same water. Scaling both kept the tilt pinned at its
		-- ceiling however low the coefficient went.
		local fore = waveAt(pos + cf.LookVector * d, s.seaT)
		local aft = waveAt(pos - cf.LookVector * d, s.seaT)
		local right = waveAt(pos + cf.RightVector * d, s.seaT)
		local left = waveAt(pos - cf.RightVector * d, s.seaT)

		local wavePitch = math.clamp((fore - aft) * SW.WaveTilt, -SW.WaveTiltMax, SW.WaveTiltMax)
		local waveRoll = math.clamp((right - left) * SW.WaveTilt, -SW.WaveTiltMax, SW.WaveTiltMax)

		-- SMOOTHED SEPARATELY, AND NEVER WRITTEN BACK INTO THE BODY STATE.
		--
		-- These used to be added straight onto s.bodyPitch / s.bodyRoll —
		-- which are PERSISTENT smoothed values. So every frame the wave
		-- was added to a number that already contained last frame's wave,
		-- and then multiplied by RollScale on top:
		--
		--     bodyRoll = (bodyRoll + wave) * 1.6     every frame
		--
		-- which compounds. One degree became sixty inside ten frames, the
		-- blend yanked it back, and it climbed again. That oscillation was
		-- the snapping — not the wave field, which was fine.
		--
		-- Own state, own rate, combined only at the point of use.
		local wRate = math.min(SW.WaveTiltRate * dt, 1)
		s.waveP = (s.waveP or 0) + (wavePitch * wet - (s.waveP or 0)) * wRate
		s.waveR = (s.waveR or 0) + (waveRoll * wet - (s.waveR or 0)) * wRate

		--=============================================================
		--  BURSTS — the kick over a crest, and they are VISUAL.
		--
		--  The kart never leaves the floor. Real impulses were tried and
		--  are a dead end: under GroundSnap they are swallowed and do
		--  nothing, over it they are a literal jump, and a boat does
		--  neither. What a hull actually does over a crest is lift AND
		--  pitch back, and the pitch is the part the eye reads.
		--
		--  Decays rather than tracking, so each crest is an EVENT with a
		--  shape rather than a value being followed.
		--=============================================================
		if SW.Bursts then
			local rise = kart:GetAttribute(Names.WAVE_RISE)
			rise = if typeof(rise) == "number" then rise else 0
			if rise > SW.BurstMinRise then
				local over = rise - SW.BurstMinRise
				s.burstLift = math.max(s.burstLift or 0, math.min(over * SW.BurstLift, SW.BurstLiftMax))
				s.burstPitch = math.max(s.burstPitch or 0, math.min(over * SW.BurstPitch, SW.BurstPitchMax))
			end
			local fade = math.exp(-SW.BurstDecay * dt)
			s.burstLift = (s.burstLift or 0) * fade
			s.burstPitch = (s.burstPitch or 0) * fade
		end

		-- YAW WANDER. A kart's nose never moves on its own; a hull's does
		-- constantly. This is the clearest "not tarmac" cue there is, and
		-- it is purely the bodywork slewing — the kart still goes exactly
		-- where the simulation says.
		s.waveYaw = math.sin(s.seaT * math.pi * 2 * SW.YawRate) * SW.YawWander * wet
	elseif (s.waveP or 0) ~= 0 or (s.waveR or 0) ~= 0 then
		-- Eased out on leaving the water rather than dropped, or the hull
		-- levels with a jolt the moment you touch land.
		local wRate = math.min(SW.WaveTiltRate * dt, 1)
		s.waveP = (s.waveP or 0) * (1 - wRate)
		s.waveR = (s.waveR or 0) * (1 - wRate)
		s.waveYaw = (s.waveYaw or 0) * (1 - wRate)
		s.burstLift = (s.burstLift or 0) * (1 - wRate)
		s.burstPitch = (s.burstPitch or 0) * (1 - wRate)
	end

	-- A hull rolls more than a chassis does. Applied to the OUTPUT, not
	-- to the stored state, so it scales the roll instead of compounding it.
	local hullRoll = s.bodyRoll * (1 + (SW.RollScale - 1) * wet) + (s.waveR or 0)
	local hullPitch = s.bodyPitch + (s.waveP or 0) + (s.burstPitch or 0)

	-- Yaw is applied about the kart's own up, between the lift and the
	-- pitch/roll, so the hull slews without tipping the axis it slews on.
	-- The flip goes OUTSIDE the hull's own lean, so a kart mid-barrel-roll
	-- still carries whatever roll the suspension and the sea were giving
	-- it. Inside, the lean would be spun around with the kart and end up
	-- pointing sideways.
	motor.Transform = CFrame.new(0, bob + (s.burstLift or 0) - s.bodyDip, 0)
		* CFrame.Angles(0, math.rad(s.waveYaw or 0), 0)
		* CFrame.Angles(math.rad(hullPitch), 0, math.rad(hullRoll))
end

--=====================================================================
--  THRUSTERS
--
--  Centre reads SPEED, sides read BOOST, and that split is the point:
--  if everything glowed with speed there would be nothing left to change
--  when you actually boosted.
--
--  SPEED IS MEASURED, NOT ASKED FOR. updateRoadWheels already works out
--  how far the kart moved this frame to roll the wheels, so the same
--  number lights the thrusters — no attribute, and it works for every
--  kart including bots and other players for free.
--=====================================================================
local function updateThrusters(kart: Model, s, dt: number)
	local boosting = kart:GetAttribute(Names.BOOSTING) == true

	-- THE TIER PICKS THE COLOUR, from the palette the drift trails and the
	-- nitro tank already use. Tier 1 blue, 2 orange, 3 purple — so the
	-- thrusters say the same thing the tank the player was watching fill
	-- has been saying, and there is no second copy to drift.
	local rawTier: any = kart:GetAttribute(Names.BOOST_TIER)
	local tier = if type(rawTier) == "number" then math.floor(rawTier) else 0
	local tierColour = if tier > 0 then FX.TierColors[math.clamp(tier, 1, #FX.TierColors)] else nil

	-- Above the floor, ramped to full. Below it the centre stays dark, so
	-- rolling around the lobby does not spend the effect before the race.
	local frac = math.clamp((s.speedNow or 0) / math.max(H.MaxSpeed, 1), 0, 1)
	local lit = math.clamp((frac - RIG.ThrusterFloor) / math.max(1 - RIG.ThrusterFloor, 0.01), 0, 1)

	-- TWO SEPARATE THINGS CAN BE BOOSTING, and the sides were only
	-- watching one of them.
	--
	--   burnStage   the NITRO tank burning, which is the main boost in
	--               the game and does NOT set boostUntil
	--   boostUntil  ApplyBoost — pads, items, the glide launch, the
	--               trick landing
	--
	-- `Boosting` is the second only, so through an entire nitro burn it
	-- stays false and the sides never lit. Either counts.
	local firing = tier > 0 or boosting

	-- Boost pins the centre on regardless of speed — you boost hardest
	-- from slow, and a thruster that stayed dark through the shove would
	-- be reading the wrong thing.
	if firing then
		lit = 1
	end

	-- Centre: its own colour at speed, the tier's while burning. "Going
	-- fast" is not a tier and should not borrow a tier's identity.
	local base = tierColour or RIG.ThrusterCentre
	local centre = RIG.ThrusterOff:Lerp(base, lit)

	-- Sides: lit whenever ANYTHING is boosting. They exist to say "a boost
	-- is happening", so with no boost there is nothing for them to say —
	-- but a nitro burn is very much a boost.
	local side = if firing then (tierColour or RIG.ThrusterCentre) else RIG.ThrusterOff

	-- Chased rather than assigned, so a boost fades up instead of
	-- snapping. One shared blend for both, since they never need to
	-- disagree about how fast they react.
	local blend = math.min(RIG.ThrusterRate * dt, 1)
	s.centreLit = (s.centreLit or RIG.ThrusterOff):Lerp(centre, blend)
	s.sideLit = (s.sideLit or RIG.ThrusterOff):Lerp(side, blend)

	-- BASEPARTS ONLY, AND THAT IS NOT A SIMPLIFICATION — IT IS THE FIX.
	--
	-- This used to accept a container too, so a Model or Folder sharing
	-- the name would have its descendants painted. The rig has exactly
	-- that: a FOLDER called `Thruster` holding CenterMesh,
	-- SideThrustMesh, Thruster and Thruster2. The folder matched, and
	-- painting its descendants recoloured all four — including both
	-- housings, which is precisely what it was supposed to leave alone.
	--
	-- A glow is one part. Matching containers was written for a
	-- hypothetical reorganisation and cost the actual rig its housings,
	-- so a name now only counts when it is on something that can hold a
	-- colour.
	local function named(inst: Instance, tag: string, names: { string }): boolean
		if not inst:IsA("BasePart") then
			return false
		end
		return CollectionService:HasTag(inst, tag) or table.find(names, inst.Name) ~= nil
	end

	local litCentre, litSide, stripped, notNeon = 0, 0, 0, 0

	-- PREPARED ONCE PER PART, not every frame. Both of these are the
	-- reasons a driven Color silently does nothing, and both are cheap to
	-- fix and impossible to see.
	s.thrusterReady = s.thrusterReady or setmetatable({}, { __mode = "k" })
	local function prepare(part: BasePart)
		if s.thrusterReady[part] then
			return
		end
		s.thrusterReady[part] = true
		if RIG.ThrusterStripAppearance then
			for _, d in part:GetChildren() do
				if d:IsA("SurfaceAppearance") then
					d:Destroy()
					stripped += 1
				end
			end
		end
		if RIG.ThrusterForceNeon and part.Material ~= Enum.Material.Neon then
			notNeon += 1
			part.Material = Enum.Material.Neon
		end
	end

	-- ONE PART, NEVER A SUBTREE. Walking descendants is what let a
	-- matching folder repaint everything inside it.
	local function paint(part: BasePart, colour: Color3): number
		prepare(part)
		part.Color = colour
		return 1
	end

	for _, inst in kart:GetDescendants() do
		if named(inst, RIG.ThrusterCenterTag, RIG.ThrusterCenterNames) then
			litCentre += paint(inst, s.centreLit)
		elseif named(inst, RIG.ThrusterSideTag, RIG.ThrusterSideNames) then
			litSide += paint(inst, s.sideLit)
		end
	end

	-- SAYS SO WHEN IT FINDS NOTHING, once per kart.
	--
	-- "The thruster is not lighting up" has at least four causes that look
	-- identical from the driver's seat: the part is named something else,
	-- it is not a BasePart, the attribute never arrived, or the mesh has a
	-- SurfaceAppearance — which makes Roblox ignore Color entirely, and is
	-- invisible in the Explorer unless you go looking.
	--
	-- This separates the first two from the rest in one line of Output.
	-- RETRIED UNTIL IT FINDS SOMETHING, rather than reported on the first
	-- frame. Rider sees a kart before it has finished assembling and
	-- being dressed, so a first-frame count of zero says nothing about
	-- the rig — it just says "not built yet", which is the least useful
	-- moment to ask.
	if stripped > 0 or notNeon > 0 then
		print(("[Rider] %s thrusters: removed %d SurfaceAppearance, forced %d part(s) to Neon."):format(
			kart.Name,
			stripped,
			notNeon
		))
	end
	if not s.thrusterChecked and (litCentre > 0 or litSide > 0 or (s.thrusterTries or 0) > 180) then
		s.thrusterChecked = true
		if litCentre == 0 or litSide == 0 then
			warn(("[Rider] %s: lit %d centre part(s) named %q and %d side part(s) named %q. A zero means the name does not match. If both are non-zero and it still does not glow, the mesh has a SurfaceAppearance — that overrides Color, and it has to be removed or the glow has to be a separate untextured part."):format(
				kart:GetFullName(),
				litCentre,
				table.concat(RIG.ThrusterCenterNames, "/"),
				litSide,
				table.concat(RIG.ThrusterSideNames, "/")
			))
		end
	end
	s.thrusterTries = (s.thrusterTries or 0) + 1
end

--=====================================================================
--  THE GLIDER
--
--  One flap and two fixed wings. The flap is the control surface and
--  follows the pitch input; the wings only flutter, because a wing that
--  never moves reads as a decal stuck to the side of the kart.
--
--  READS AN ATTRIBUTE, NOT THE SIM. Rider runs for EVERY kart in the
--  world, and only the driver's own client has a Simulation for its own
--  kart. The glide state is published as an attribute so other people's
--  gliders animate too — the same route STEER and DRIFT already take.
--=====================================================================
local function named2(inst: Instance, tag: string, name: string): boolean
	return CollectionService:HasTag(inst, tag) or inst.Name == name
end

-- WIND AND WING RIBBONS.
--
-- Built once per kart, on the first glide rather than at spawn: most
-- karts never touch a ramp, and a Trail plus a Sound on every kart in
-- the field is a cost paid by everybody for something few of them use.
-- SAYS WHETHER ROBLOX ACTUALLY ACCEPTED THE ASSET.
--
-- A Sound with a SoundId it is not allowed to play stays silent and
-- reports nothing — since the audio privacy change, an id you do not own
-- simply never loads. That is indistinguishable from a wiring bug from
-- the driver's seat, and it has exactly the opposite fix.
--
-- Loaded is not instant, so this waits for the event rather than reading
-- the property once and drawing a conclusion from a value that was
-- always going to be false at that moment.
local announced: { [string]: boolean } = {}
local function checkSound(sound: Sound, label: string)
	if sound.SoundId == "" or announced[sound.SoundId] then
		return
	end
	announced[sound.SoundId] = true
	task.delay(5, function()
		if sound.Parent and not sound.IsLoaded then
			warn(
				("[Rider] %s (%s) never loaded. Roblox will not play audio you do not own — re-upload it to this account, or check the id is a Sound and not a different asset type."):format(
					label,
					sound.SoundId
				)
			)
		end
	end)
end

local function ensureGliderFx(kart: Model, s)
	if s.gliderFx then
		return
	end
	s.gliderFx = true
	local hitbox = kart.PrimaryPart
	if not hitbox then
		s.gliderFx = nil -- try again next frame; the kart is still assembling
		return
	end

	-- One-shot, played on the rising edge of the glide. Separate from the
	-- looping wind because they say different things: this is "the wings
	-- are out", the wind is "and here is how fast you are going".
	local deploy = Instance.new("Sound")
	deploy.Name = "GlideDeploy"
	deploy.SoundId = GLD.DeploySoundId
	deploy.Volume = GLD.DeployVolume
	deploy.RollOffMaxDistance = 200
	deploy.Parent = hitbox
	s.deploy = deploy
	checkSound(deploy, "glide deploy")

	-- The hull through the water. Volume follows SPEED, not the state:
	-- a moored boat is nearly silent and a moving one is not, so the
	-- sound is a readout for how fast you are going rather than a flag
	-- saying "you are in water". Same reasoning as the glide wind.
	local cruise = Instance.new("Sound")
	cruise.Name = "SwimCruise"
	cruise.SoundId = SW.CruiseSoundId
	cruise.Looped = true
	cruise.Volume = 0
	cruise.RollOffMaxDistance = 200
	cruise.Parent = hitbox
	s.cruise = cruise
	checkSound(cruise, "water cruise")

	local sound = Instance.new("Sound")
	sound.Name = "GlideWind"
	sound.SoundId = GLD.WindSoundId
	sound.Looped = true
	sound.Volume = 0
	sound.RollOffMaxDistance = 220
	sound.Parent = hitbox
	s.wind = sound
	checkSound(sound, "glide wind")

	s.trails = {}
	for _, inst in kart:GetDescendants() do
		if inst:IsA("BasePart") and table.find(RIG.WingNames, inst.Name) then
			-- THE OUTER EDGE, WORKED OUT RATHER THAN ASSUMED.
			--
			-- First version emitted from BOTH ends of the wing's long axis.
			-- That is right for a single mesh spanning the whole kart, and
			-- wrong for separate left and right panels — on those, one of
			-- the two ends is INBOARD, so half the ribbons streamed out of
			-- the middle of the bodywork.
			--
			-- Which case a rig is cannot be assumed, so it is measured: put
			-- a candidate at each end, see how far each lands from the
			-- kart's centreline, and keep the far one. A panel has a clear
			-- winner; a full-width mesh has two ends that tie, and a tie
			-- means both are outer edges and both should trail.
			local size = inst.Size
			local wide = size.X >= size.Z
			local axis = if wide then Vector3.xAxis else Vector3.zAxis
			local half = (if wide then size.X else size.Z) * 0.5

			local centre = kart.PrimaryPart and kart.PrimaryPart.Position or inst.Position
			local reach = {}
			for _, side in { 1, -1 } do
				local world = inst.CFrame:PointToWorldSpace(axis * (half * side))
				table.insert(reach, { side = side, dist = (world - centre).Magnitude })
			end

			local ends = {}
			local spread = math.abs(reach[1].dist - reach[2].dist)
			if spread < half * 0.5 then
				-- A tie: one mesh spanning both sides. Both ends are tips.
				ends = { 1, -1 }
			else
				-- A side panel. Only the end that reaches further out.
				ends = { if reach[1].dist > reach[2].dist then reach[1].side else reach[2].side }
			end

			-- The gap between the two attachments IS the ribbon's width, so
			-- it comes off the wing's own thickness rather than a constant.
			local thickness = math.min(size.X, math.min(size.Y, size.Z))
			local halfSpread = math.max(thickness * GLD.TrailSpreadScale, GLD.TrailSpreadMin) * 0.5

			-- And it starts at the TRAILING edge. Emitting from the leading
			-- edge makes the ribbon appear to pass through the wing.
			local depth = if wide then size.Z else size.X
			local backAxis = if wide then Vector3.zAxis else Vector3.xAxis
			local backset = backAxis * (depth * GLD.TrailBackset)

			for _, side in ends do
				local tip = axis * (half * side) + backset
				local a0 = Instance.new("Attachment")
				a0.Name = "GlideTrailTop"
				a0.Position = tip + Vector3.new(0, halfSpread, 0)
				a0.Parent = inst
				local a1 = Instance.new("Attachment")
				a1.Name = "GlideTrailBottom"
				a1.Position = tip - Vector3.new(0, halfSpread, 0)
				a1.Parent = inst

				local trail = Instance.new("Trail")
				trail.Attachment0, trail.Attachment1 = a0, a1
				trail.Lifetime = GLD.TrailLife
				trail.WidthScale = NumberSequence.new(GLD.TrailWidth)
				trail.Color = ColorSequence.new(GLD.TrailColor)
				-- Fades out along its own length, so the ribbon has an end
				-- rather than being chopped off.
				trail.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, GLD.TrailTransparency),
					NumberSequenceKeypoint.new(1, 1),
				})
				trail.Enabled = false
				trail.Parent = inst
				-- The offsets are kept so they can be scaled with the wing.
				-- Attachment.Position is in LOCAL STUDS and does not follow
				-- Size, so a wing scaled to 0.01 leaves its attachments at
				-- the full-size tip — several studs outside a part that is
				-- currently a speck.
				table.insert(s.trails, { trail = trail, a0 = a0, a1 = a1, p0 = a0.Position, p1 = a1.Position })
			end
		end
	end
end

local function updateGliderFx(kart: Model, s, gliding: boolean, dt: number)
	ensureGliderFx(kart, s)
	if not s.wind then
		return
	end

	-- THE MOMENT THE WINGS COME OUT. Edge-triggered, so it fires once per
	-- glide rather than every frame of one.
	if gliding and not s.deployed then
		s.deployed = true
		if s.deploy and s.deploy.SoundId ~= "" then
			s.deploy:Play()
		end
	elseif not gliding then
		s.deployed = false
	end

	-- Volume follows SPEED, not just the state. A glide that has bled off
	-- most of its speed should sound like it — the wind is the readout
	-- for how much energy is left, which is the thing the pitch input is
	-- actually trading.
	local frac = math.clamp(((s.speedNow or 0) - GLD.WindMinSpeed) / math.max(H.MaxSpeed - GLD.WindMinSpeed, 1), 0, 1)
	local want = if gliding then GLD.WindVolume * frac else 0
	s.wind.Volume = Util.approach(s.wind.Volume, want, GLD.WindFade, dt)
	s.wind.PlaybackSpeed = GLD.WindPitchMin + (GLD.WindPitchMax - GLD.WindPitchMin) * frac

	-- Stopped rather than left looping at zero: a silent Sound still costs
	-- a voice, and there are eight karts.
	if s.wind.Volume > 0.005 then
		if not s.wind.IsPlaying then
			s.wind:Play()
		end
	elseif s.wind.IsPlaying then
		s.wind:Stop()
	end

	-- TIPS FOLLOW THE SCALE, AND THE RIBBON WAITS FOR THE WING TO SETTLE.
	--
	-- A Trail draws whatever its attachments do, so streaming while the
	-- wing is growing smears the deploy itself into a ribbon. Enabled only
	-- once the deploy animation has finished, which is also the only time
	-- the tips are where the art says they are.
	local scale = s.wingScale or 0
	local settled = gliding and (s.deployT or 0) >= 1
	for _, t in s.trails or {} do
		t.a0.Position = t.p0 * scale
		t.a1.Position = t.p1 * scale
		t.trail.Enabled = settled
	end
end

local function updateGlider(kart: Model, s, dt: number)
	local gliding = kart:GetAttribute(Names.GLIDING) == true
	local pitch = kart:GetAttribute(Names.GLIDE_PITCH)
	pitch = if typeof(pitch) == "number" then math.clamp(pitch, -1, 1) else 0

	-- Eased so the flap does not snap on a stick flick. A control surface
	-- has mass.
	s.flap = Util.approach(s.flap or 0, if gliding then pitch else 0, RIG.AeroRate, dt)

	-- One phase for both wings, so they beat together rather than looking
	-- like two independent broken things.
	s.flutter = (s.flutter or 0) + dt * RIG.WingFlutterRate
	local amount = if gliding then RIG.WingFlutter else RIG.WingFlutterGround
	local wobble = math.sin(s.flutter * math.pi * 2) * math.rad(amount)

	-- THE WINGS SNAP OUT, THEY DO NOT FADE IN.
	--
	-- Scaling reads as DEPLOYING; fading reads as the engine being slow
	-- to draw something that was always there. The overshoot is what
	-- turns "appearing" into "being thrown open".
	--
	-- Parts are found ONCE and their authored Size cached with them. The
	-- cache is not an optimisation — it is the only record of full size,
	-- since the live Size is whatever this animation last set it to, and
	-- reading that back would ratchet the wings smaller every deploy.
	if not s.gliderParts then
		s.gliderParts = {}
		for _, inst in kart:GetDescendants() do
			if
				inst:IsA("BasePart")
				and (
					named2(inst, RIG.AeroTag, RIG.AeroName)
					or CollectionService:HasTag(inst, RIG.WingTag)
					or table.find(RIG.WingNames, inst.Name) ~= nil
					or (inst.Parent and inst.Parent.Name == "Glider")
				)
			then
				table.insert(s.gliderParts, { part = inst, size = inst.Size })
			end
		end
	end

	-- Progress toward open, 0..1. Retract is faster and has no bounce:
	-- putting something away is not an event.
	local rate = if gliding then 1 / GLD.DeployTime else -1 / GLD.RetractTime
	s.deployT = math.clamp((s.deployT or 0) + rate * dt, 0, 1)

	local scale
	if s.deployT >= 1 then
		scale = 1
	elseif s.deployT <= 0 then
		scale = 0
	elseif gliding then
		-- easeOutBack. Overshoots past 1 and settles back.
		local c1 = GLD.DeployBounce
		local c3 = c1 + 1
		local u = s.deployT - 1
		scale = 1 + c3 * u * u * u + c1 * u * u
	else
		scale = s.deployT
	end

	-- A part scaled to nearly nothing is still a visible speck, so the
	-- transparency is still doing a job — just a much smaller one.
	-- Shared with the trails, whose attachment offsets have to track it.
	s.wingScale = scale

	local hidden = if scale < GLD.DeployHideBelow then 1 else 0
	for _, entry in s.gliderParts do
		-- Roblox refuses a zero dimension; the floor keeps the write legal
		-- without being visible.
		entry.part.Size = entry.size * math.max(scale, 0.01)
		if entry.part.LocalTransparencyModifier ~= hidden then
			entry.part.LocalTransparencyModifier = hidden
		end
	end

	updateGliderFx(kart, s, gliding, dt)

	local throw = math.rad(RIG.AeroThrow)
	for _, motor in kart:GetDescendants() do
		if motor:IsA("Motor6D") then
			local axis = motor:GetAttribute(Names.ROLL_AXIS) or Vector3.xAxis
			if motor.Name == "AeroMotor" then
				motor.Transform = CFrame.fromAxisAngle(axis, s.flap * throw)
			elseif motor.Name == "WingMotor" then
				motor.Transform = CFrame.fromAxisAngle(axis, wobble)
			end
		end
	end
end

local function updateRoadWheels(kart: Model, s, dt: number)
	local hitbox = kart.PrimaryPart
	if not hitbox then
		return
	end

	-- How fast the kart is dropping, measured against the kart's own up
	-- rather than world Y — the track can be banked, looped or upside
	-- down, and "falling" means toward the road either way.
	local up = hitbox.CFrame.UpVector
	if s.lastPos then
		local drop = (s.lastPos - hitbox.Position):Dot(up)
		s.fallSpeed = if dt > 0 then math.max(drop / dt, 0) else 0
	end

	-- Metres rolled since last frame -> radians, via the wheel's
	-- circumference. Signed, so reversing spins them backwards.
	local pos = hitbox.Position
	local moved = 0
	if s.lastPos then
		local delta = pos - s.lastPos
		moved = delta.Magnitude * math.sign(delta:Dot(hitbox.CFrame.LookVector))
	end
	s.lastPos = pos
	-- Shared with the thrusters, which want the same number.
	s.speedNow = if dt > 0 then math.abs(moved) / dt else 0
	-- Capped, not just scaled. Past a couple of revolutions per frame the
	-- spin aliases into a strobe and any steering angle disappears inside
	-- it; real footage sells that speed with motion blur, which we don't
	-- have.
	--
	-- NEGATED, and that is the right-hand rule rather than a fudge.
	--
	-- The axle is the kart's RIGHT vector (+X). A positive rotation about
	-- +X carries +Y toward +Z — so the TOP of the wheel travels toward
	-- +Z, and Roblox's forward is -Z. Driving forward is therefore a
	-- NEGATIVE rotation about the axle.
	--
	-- Without the sign the wheels spin backwards at exactly the correct
	-- speed, which is the most convincing possible way to be wrong: it
	-- tracks acceleration, braking and reverse perfectly and is still
	-- inside out.
	-- PADDLES, NOT TYRES. A wheel turning at road speed while the kart is
	-- clearly on water reads as the animation not knowing where it is.
	local rawWet: any = kart:GetAttribute(Names.SWIMMING)
	local wet = if type(rawWet) == "number" then math.clamp(rawWet, 0, 1) else 0
	s.wet = wet

	-- One line, once, the first time this kart touches water. Says which
	-- link of the chain is live: the attribute arriving here proves the
	-- zone was detected AND that Simulation published it AND that this is
	-- the same Instance, which is three separate things that can fail.
	-- REPORTS THE SUSTAINED VALUES, not the first frame.
	--
	-- The first version printed the moment `swim` crossed 0.05, which is
	-- the very start of a two-second ramp — so it always said about 0.07
	-- and told you nothing about what the visuals were actually doing. A
	-- diagnostic that fires at the least informative instant is worse
	-- than none, because it looks like an answer.
	if SW.Debug and wet > 0.05 then
		s.saidAt = s.saidAt or 0
		if os.clock() - s.saidAt > 2 then
			s.saidAt = os.clock()
			print(
				("[Rider] %s  swim=%.2f  wheelLay=%.0f deg  bob=%+.2f  pitch=%+.1f  roll=%+.1f  yaw=%+.1f  burst=%+.2f"):format(
					kart.Name,
					wet,
					(s.wheelLay or 0) * SW.WheelTilt,
					s.heave or 0,
					(s.waveP or 0) + (s.burstPitch or 0),
					s.waveR or 0,
					s.waveYaw or 0,
					s.burstLift or 0
				)
			)
		end
	end

	local spin = -moved / math.max(RIG.RoadWheelRadius, 0.1)
	spin *= 1 - (1 - SW.WheelSpinScale) * wet
	local maxSpin = RIG.RoadWheelMaxSpin * dt
	s.roll = (s.roll or 0) + math.clamp(spin, -maxSpin, maxSpin)

	-- Fronts lag the input a touch, like the steering wheel does.
	local maxLock = math.rad(RIG.RoadWheelSteer)
	s.wheelSteer = Util.approach(s.wheelSteer or 0, s.steer, RIG.RoadWheelSteerRate, dt)
	local lock = s.wheelSteer * maxLock

	-- Counter-steer. Mid-drift the body is yawed sideways while the kart
	-- still travels roughly forwards, so cancelling that angle points the
	-- fronts back down the ROAD instead of down the bodywork. It's the
	-- detail that makes a drift look deliberate rather than like the kart
	-- is simply facing the wrong way.
	--
	-- Local kart only: driftAngle isn't replicated, so other people's
	-- wheels just follow their steering. Worth it for the driver's own
	-- view, which is the one that has to feel good.
	-- Counter-steer, worked out once per frame and shared with the
	-- steering wheel so the driver's hands and the front tyres agree.
	-- CROSSFADE, NOT SUM. See RoadWheelCounterBlend.
	--
	-- Adding the counter term to the player's steering meant the two
	-- cancelled at full slip and the wheels sat dead straight through the
	-- deepest part of the drift. Blending hands the front wheels over to
	-- the slide as it develops, so they cross the centre and point the
	-- other way — which is what opposite lock looks like from outside.
	local slide = (s.slide or 0) * RIG.RoadWheelCounterBlend
	lock = lock * (1 - slide) + (s.counter or 0) * maxLock * slide

	-- Lock stop, which real steering has and which matters here for a
	-- specific reason: a SPINOUT drives driftAngle through several whole
	-- revolutions, and without this the front wheels would whirl round
	-- like a fan while the kart span.
	lock = math.clamp(lock, -maxLock, maxLock)

	for _, motor in kart:GetDescendants() do
		if motor:IsA("Motor6D") and motor.Name == "RoadWheelMotor" then
			-- Yaw THEN pitch: steering turns the whole wheel, and the wheel
			-- rolls about its own axle afterwards. The other order would
			-- swing the axle around instead.
			-- Axes are per wheel and were measured at build time; see
			-- KartFactory. Falling back to the old assumption keeps a kart
			-- built before this change from breaking outright.
			local rollAxis = motor:GetAttribute(Names.ROLL_AXIS) or Vector3.xAxis
			local steerAxis = motor:GetAttribute(Names.STEER_AXIS) or Vector3.yAxis

			-- Steer THEN roll: steering swings the whole wheel about the
			-- kart's up, and the wheel spins on its axle within that. The
			-- other order would carry the axle around with the spin.
			local turn = if motor:GetAttribute(Names.WHEEL_FRONT)
				then CFrame.fromAxisAngle(steerAxis, -lock)
				else CFrame.new()

			-- SUSPENSION IS A TRANSLATION, APPLIED OUTSIDE THE ROTATIONS.
			--
			-- `CFrame.new(v) * R` rotates in place and then offsets, which
			-- is what a wheel does: it spins on its axle while the axle
			-- moves up and down. Multiplying the other way round would
			-- carry the offset through the spin and make the wheel orbit a
			-- point above itself.
			--
			-- Along steerAxis, which is the kart's own up in this joint's
			-- frame — so it stays correct upside down in a loop, where
			-- world Y would send the wheels through the floor.
			local travel = suspensionFor(kart, motor, hitbox, s, dt, up)
			-- LYING OVER IS THE MODE SIGNAL. It changes the kart's
			-- silhouette, which reads from further away and faster than
			-- any particle effect can.
			--
			-- About the wheel's FORWARD axis — the cross of its own roll
			-- and steer axes — so the wheel lies down without disturbing
			-- either. Both keep working underneath, which is why it can
			-- still spin and steer while flat.
			-- MIRRORED, SO BOTH SIDES LEAN INWARD.
			--
			-- One shared angle tilted every wheel the same way, so the left
			-- pair leaned in and the right pair leaned out — the kart looked
			-- like it was falling over rather than like a hull.
			--
			-- The sign, derived once so nobody has to again:
			--   fwdAxis = rollAxis x steerAxis = (kart +X) x (kart +Y) = +Z
			--   a rotation about +Z sends +Y toward -X, i.e. leans the top
			--   of the wheel LEFT
			-- so the RIGHT wheel wants a positive angle to lean inward and
			-- the LEFT wheel a negative one.
			--
			-- Read off the joint's own X, which is already in the hitbox's
			-- frame and therefore already means "left".
			local lay = CFrame.new()
			s.wheelLay = Util.approach(s.wheelLay or 0, s.wet or 0, SW.WheelTiltRate, dt)
			if s.wheelLay > 0.001 then
				local fwdAxis = rollAxis:Cross(steerAxis)
				if fwdAxis.Magnitude > 1e-3 then
					local inward = if motor.C0.Position.X < 0 then -1 else 1
					lay = CFrame.fromAxisAngle(fwdAxis.Unit, math.rad(SW.WheelTilt) * s.wheelLay * inward)
				end
			end

			-- Same rotation as the body, applied first, so the wheels go
			-- round WITH the kart instead of hanging level while the shell
			-- turns around them.
			motor.Transform = CFrame.new(steerAxis * travel)
				* turn
				* lay
				* CFrame.fromAxisAngle(rollAxis, s.roll)
		end
	end
end

-- Reported once per kart, because this one gate silently disables
-- EVERYTHING Rider does — wheel spin, body roll, the glider, the
-- thrusters, the swim visuals and both water sounds all live past it.
-- A kart whose SteeringWheel is a Model rather than a Part looks exactly
-- like "none of the visuals are wired up".
local scolded: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function updateKart(kart: Model, dt: number)
	local seat = kart:FindFirstChild("Seat")
	local hub = kart:FindFirstChild("SteeringWheel", true)
	if not (seat and seat:IsA("VehicleSeat") and hub and hub:IsA("BasePart")) then
		if not scolded[kart] then
			scolded[kart] = true
			warn(
				("[Rider] %s is doing NOTHING — no wheels, no body roll, no glider, no thrusters, no water. Seat=%s SteeringWheel=%s. Both are required: the Seat must be a VehicleSeat and SteeringWheel must be a BasePart (a MeshPart is fine, a Model is not)."):format(
					kart:GetFullName(),
					if seat then seat.ClassName else "MISSING",
					if hub then hub.ClassName else "MISSING"
				)
			)
		end
		return
	end
	local motor = hub:FindFirstChild("WheelMotor")
	if not (motor and motor:IsA("Motor6D")) then
		return
	end

	local s = stateFor(kart)
	local occupant = seat.Occupant

	-- Before anything uses it: the steering wheel and the road wheels both
	-- read this, and they have to agree or the driver's hands contradict
	-- the tyres.
	s.counter = counterSteer(kart, s, dt)

	----------------------------------------------------------------
	-- Wheel. SteerFloat is replicated from the driver, so this works
	-- for other people's karts as well as our own. No Animator is
	-- involved here, so Transform is the right tool.
	----------------------------------------------------------------
	-- The kart's own attribute first, then the seat.
	--
	-- On a touch device the pad feeds Simulation directly and the
	-- VehicleSeat never sees a steer value at all, so SteerFloat alone
	-- would leave a mobile player's wheel dead straight while they corner.
	-- The driver's client writes its real steer onto its own kart; that
	-- doesn't replicate, so remote karts fall through to SteerFloat, which
	-- is right for anyone on a keyboard.
	-- The published steer wins, occupant or not.
	--
	-- This used to be gated on someone sitting there, which quietly tied
	-- two unrelated things together: a bot whose rig failed to seat also
	-- had a dead steering wheel, so one missing model looked like two
	-- separate bugs. A kart that says which way it's steering should show
	-- it regardless of who is or isn't aboard.
	--
	-- SteerFloat is the fallback and genuinely does need an occupant —
	-- it's the seat reading a driver's input.
	local own = kart:GetAttribute(Names.STEER)
	local targetSteer = 0
	if typeof(own) == "number" then
		targetSteer = own
	elseif occupant then
		targetSteer = seat.SteerFloat
	end
	s.steer = Util.approach(s.steer, targetSteer, R.WheelSmoothing, dt)

	-- The hands saw at the wheel through a drift, and the IK follows them
	-- for free. Scaled separately because a driver's arms don't move as
	-- far as the tyres do — R.WheelCounterSteer = 0 keeps the wheel showing
	-- pure input if you'd rather it matched the keys.
	-- CROSSFADED, exactly like the road wheels, or the driver's hands hold
	-- one way while the tyres point the other — which is the contradiction
	-- the note above is about. Summing cancelled at full slip and left the
	-- wheel centred through the deepest part of the drift.
	--
	-- WheelCounterSteer still scales how far the ARMS follow the tyres: a
	-- driver's hands do not travel as far as the front wheels do, and 0
	-- keeps the wheel showing pure input if you prefer that.
	-- WheelCounterSteer damps HOW FAR the hands go, not WHETHER they cross
	-- over. Folding it into the blend instead stalled the wheel at +8
	-- degrees while the tyres were at -18 — hands and tyres disagreeing,
	-- which is the thing this is supposed to prevent. A real drifter's
	-- hands do cross to opposite lock; they simply travel less than the
	-- front wheels do.
	local handSlide = (s.slide or 0) * RIG.RoadWheelCounterBlend
	local shown = math.clamp(s.steer * (1 - handSlide) + s.counter * R.WheelCounterSteer * handSlide, -1, 1)
	local spin = -shown * math.rad(R.MaxWheelAngle)
	motor.Transform = CFrame.Angles(0, 0, if R.InvertWheel then -spin else spin)

	updateRoadWheels(kart, s, dt)
	updateGlider(kart, s, dt)
	updateThrusters(kart, s, dt)
	updateBody(kart, s, dt)

	----------------------------------------------------------------
	-- Hands
	----------------------------------------------------------------
	local character = occupant and occupant.Parent
	if not (R.IKEnabled and character) then
		if s.boundTo then
			clearControls(s)
			s.rig, s.boundTo = nil, nil
		end
		return
	end

	-- Rebuild when the driver changes or respawns.
	if s.boundTo ~= character or (s.ikL and not s.ikL.Parent) then
		clearControls(s)
		s.rig = findRig(character)
		s.boundTo = character

		if not s.rig then
			report("no arm rig on " .. character.Name .. " (neither R15 nor R6)")
			return
		end

		local gripL = hub:FindFirstChild("GripL")
		local gripR = hub:FindFirstChild("GripR")
		if not (gripL and gripR) then
			report("SteeringWheel has no GripL/GripR attachments")
			return
		end

		-- Elbow hints, mirrored across the kart's centreline.
		local hitbox = kart.PrimaryPart
		if hitbox then
			local p = R.ElbowPole
			s.poleL = makePole(hitbox, "_ElbowPoleL", Vector3.new(-p.X, p.Y, p.Z))
			s.poleR = makePole(hitbox, "_ElbowPoleR", p)
		end

		s.ikL = makeControl("KartIK_L", s.rig, s.rig.lRoot, s.rig.lHand, gripL, s.poleL, 1)
		s.ikR = makeControl("KartIK_R", s.rig, s.rig.rRoot, s.rig.rHand, gripR, s.poleR, 2)
		if not (s.ikL and s.ikR) then
			report("could not build IKControls — chain root missing")
			return
		end
		report(nil)
	end
end

--=====================================================================
--  START
--=====================================================================
function Rider.start()
	CollectionService:GetInstanceRemovedSignal(KART_TAG):Connect(function(kart)
		local s = state[kart]
		if s then
			clearControls(s)
		end
		state[kart] = nil
	end)

	-- The wheel still needs a per-frame nudge; the hands do not, because
	-- IKControl.Target is a live reference the engine follows.
	RunService:BindToRenderStep("KartRider", Enum.RenderPriority.Character.Value + 1, function(dt)
		for _, kart in CollectionService:GetTagged(KART_TAG) do
			if kart:IsA("Model") and kart.Parent then
				local ok, err = pcall(updateKart, kart, dt)
				if not ok then
					warn("[Rider] " .. tostring(err))
				end
			end
		end
	end)
end

return Rider
