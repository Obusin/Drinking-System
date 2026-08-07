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
local Util = require(BloxKart:WaitForChild("Util"))
local WorldFilter = require(BloxKart:WaitForChild("WorldFilter"))

local R = Config.Rider
local H = Config.Handling
local GLD = Config.Glide
local RIG = Config.Rig
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
	local nitro = kart:GetAttribute(Names.NITRO_ON) == true

	-- Above the floor, ramped to full. Below it the centre stays dark, so
	-- rolling around the lobby does not spend the effect before the race.
	local frac = math.clamp((s.speedNow or 0) / math.max(H.MaxSpeed, 1), 0, 1)
	local lit = math.clamp((frac - RIG.ThrusterFloor) / math.max(1 - RIG.ThrusterFloor, 0.01), 0, 1)

	-- Boost pins the centre on regardless of speed — you boost hardest
	-- from slow, and a thruster that stayed dark through the shove would
	-- be reading the wrong thing.
	if boosting then
		lit = 1
	end

	local base = if nitro then RIG.ThrusterNitro else RIG.ThrusterCentre
	local centre = RIG.ThrusterOff:Lerp(base, lit)
	local side = if boosting then RIG.ThrusterBoost else RIG.ThrusterOff

	-- Chased rather than assigned, so a boost fades up instead of
	-- snapping. One shared blend for both, since they never need to
	-- disagree about how fast they react.
	local blend = math.min(RIG.ThrusterRate * dt, 1)
	s.centreLit = (s.centreLit or RIG.ThrusterOff):Lerp(centre, blend)
	s.sideLit = (s.sideLit or RIG.ThrusterOff):Lerp(side, blend)

	-- MATCHES A PART **OR** A CONTAINER, for the same reason the wheels
	-- had to. `Thruster2` may be a bare MeshPart today and a Model or
	-- Folder holding two meshes tomorrow — art gets reorganised, and a
	-- lighting rig that silently stops working when somebody groups two
	-- meshes is a rig nobody trusts.
	local function named(inst: Instance, tag: string, names: { string }): boolean
		return CollectionService:HasTag(inst, tag) or table.find(names, inst.Name) ~= nil
	end

	local litCentre, litSide = 0, 0
	local function paint(inst: Instance, colour: Color3): number
		local n = 0
		if inst:IsA("BasePart") then
			inst.Color = colour
			n += 1
		end
		for _, d in inst:GetDescendants() do
			if d:IsA("BasePart") then
				d.Color = colour
				n += 1
			end
		end
		return n
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
	if not s.thrusterChecked then
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

	local sound = Instance.new("Sound")
	sound.Name = "GlideWind"
	sound.SoundId = GLD.WindSoundId
	sound.Looped = true
	sound.Volume = 0
	sound.RollOffMaxDistance = 220
	sound.Parent = hitbox
	s.wind = sound

	s.trails = {}
	for _, inst in kart:GetDescendants() do
		if inst:IsA("BasePart") and table.find(RIG.WingNames, inst.Name) then
			-- BOTH ENDS OF THE WING, NOT JUST THE POSITIVE ONE.
			--
			-- The first version placed one attachment at +half along the
			-- long axis, which is one wing TIP. On a combined mesh that
			-- spans both sides — which is what this rig has — that is the
			-- right tip only, and the left had no ribbon at all.
			--
			-- Emitting at both ends covers the combined case AND the case
			-- where the wings are separate parts whose meshes are mirrored,
			-- since a mirrored part's "positive" end points inboard.
			local size = inst.Size
			local wide = size.X >= size.Z
			local axis = if wide then Vector3.xAxis else Vector3.zAxis
			local half = (if wide then size.X else size.Z) * 0.5

			for _, side in { 1, -1 } do
				local tip = axis * (half * side)
				local a0 = Instance.new("Attachment")
				a0.Name = "GlideTrailTop"
				a0.Position = tip + Vector3.new(0, 0.15, 0)
				a0.Parent = inst
				local a1 = Instance.new("Attachment")
				a1.Name = "GlideTrailBottom"
				a1.Position = tip - Vector3.new(0, 0.15, 0)
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
				table.insert(s.trails, trail)
			end
		end
	end
end

local function updateGliderFx(kart: Model, s, gliding: boolean, dt: number)
	ensureGliderFx(kart, s)
	if not s.wind then
		return
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

	for _, trail in s.trails or {} do
		trail.Enabled = gliding
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

	-- WINGS OUT ONLY IN THE AIR, AND RE-ASSERTED EVERY FRAME.
	--
	-- LocalTransparencyModifier is render-only and client-local, which is
	-- what makes it the right tool — it never touches the Transparency
	-- the server replicates.
	--
	-- But Roblox RESETS it to 0 whenever the part's Transparency is
	-- written, and KartService writes Transparency across every part
	-- during the spawn fade-in. Setting it once on a state change meant
	-- the wings quietly popped visible on the next spawn and stayed that
	-- way, because nothing ever set it again.
	--
	-- So the parts are found ONCE and the modifier is re-applied every
	-- frame. Three parts on eight karts is twenty-four property writes —
	-- far cheaper than a bug that only shows up after a respawn.
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
				table.insert(s.gliderParts, inst)
			end
		end
	end

	local hidden = if gliding then 0 else 1
	for _, inst in s.gliderParts do
		if inst.LocalTransparencyModifier ~= hidden then
			inst.LocalTransparencyModifier = hidden
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
	local spin = -moved / math.max(RIG.RoadWheelRadius, 0.1)
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
	lock += (s.counter or 0) * maxLock

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
			motor.Transform = CFrame.new(steerAxis * travel)
				* turn
				* CFrame.fromAxisAngle(rollAxis, s.roll)
		end
	end
end

local function updateKart(kart: Model, dt: number)
	local seat = kart:FindFirstChild("Seat")
	local hub = kart:FindFirstChild("SteeringWheel", true)
	if not (seat and seat:IsA("VehicleSeat") and hub and hub:IsA("BasePart")) then
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
	local shown = math.clamp(s.steer + s.counter * R.WheelCounterSteer, -1, 1)
	local spin = -shown * math.rad(R.MaxWheelAngle)
	motor.Transform = CFrame.Angles(0, 0, if R.InvertWheel then -spin else spin)

	updateRoadWheels(kart, s, dt)
	updateGlider(kart, s, dt)
	updateThrusters(kart, s, dt)

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
