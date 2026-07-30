--[[
	Simulation — the movement. No forces, no constraints, no rigid body.

	We own the state — position, forward, up, speed, vertical velocity —
	and integrate it ourselves each frame. Roblox never gets a vote on
	how the kart moves, which is what makes handling identical on every
	machine, every frame rate, and behind every art asset.

		forward = rotate(forward, up, turnRate * dt)  -- where the nose points
		travel  = lerp(travel, forward, grip * dt)    -- where it's GOING
		speed   = lerp(speed, target)                 -- how fast
		pos    += travel * speed * dt
		pos    += up * vertVel * dt                   -- gravity along -up

	THREE DIRECTIONS, DELIBERATELY DIFFERENT
	----------------------------------------
		forward  where the nose points
		travel   where the kart actually moves — chases forward, and the
		         lag is the entire feeling of weight
		visual   forward rotated by driftAngle — what you SEE, and the
		         reason a drift looks sideways

	Welding all three together is what made it feel weightless and on
	rails. `Grip` / `DriftGrip` control how far travel is allowed to lag.

	SURFACE GRAVITY
	---------------
	"Down" is the track's surface normal, not the world's. `up` chases
	whatever the ground probe reports, and gravity always pulls along
	`-up` — which on a loop means INTO the road. There is no falling off
	a loop: you leave the track by driving off an edge or jumping, never
	by running out of speed. Everything is measured as a distance ALONG
	up rather than as a world Y coordinate; that single change is what
	makes ceilings work.

	THE CONSISTENCY RULE
	--------------------
	Reads exactly two things off the kart: the Hitbox and the Seat.
	Never wheels, mass, or part sizes.

	Step() returns an events table so Effects and Audio can react without
	this module knowing they exist.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")

local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))
local WorldFilter = require(script.Parent.WorldFilter)

local H = Config.Handling
local N = Config.Nitro
local FX = Config.Effects
local RS = Config.Respawn

local STATE_GRIP = "grip"
local STATE_HOP = "hop"
local STATE_DRIFT = "drift"

local Simulation = {}
Simulation.__index = Simulation

Simulation.GRIP = STATE_GRIP
Simulation.HOP = STATE_HOP
Simulation.DRIFT = STATE_DRIFT

local function tierFor(t: number): number
	if t >= H.BoostTier3Time then
		return 3
	elseif t >= H.BoostTier2Time then
		return 2
	elseif t >= H.BoostTier1Time then
		return 1
	end
	return 0
end

function Simulation.new(model: Model, hitbox: BasePart, seat: VehicleSeat, _character: Model?)
	-- Shared, and maintained centrally: it excludes EVERY kart and
	-- character, not just ours, so other racers are never mistaken for
	-- walls or ground.
	local rayParams = WorldFilter.rayParams
	local overlapParams = WorldFilter.overlapParams

	local pivot = hitbox.CFrame

	return setmetatable({
		model = model,
		hitbox = hitbox,
		seat = seat,
		rayParams = rayParams,
		overlapParams = overlapParams,

		pos = pivot.Position,
		forward = pivot.LookVector,
		travel = pivot.LookVector, -- direction actually moved in; lags `forward`
		up = Vector3.yAxis,
		speed = 0,
		vertVel = 0,
		airTime = 0,
		grounded = false,
		wasGrounded = true,
		normal = Vector3.yAxis,
		visualNormal = Vector3.yAxis,

		steer = 0,
		state = STATE_GRIP,
		hopUntil = 0,
		driftDir = 0,
		driftStart = 0,
		driftAngle = 0,
		driftBlend = 0,
		releaseDir = 0,
		tier = 0,
		boostUntil = 0,
		boostSpeed = 0,

		-- Banked boost, spent on demand. Whole tanks plus progress on the
		-- next one; `burnStage` 0 = not burning.
		tanks = 0,
		fill = 0,
		burnStage = 0,
		burnUntil = 0,
		-- Tanks committed to the current burn but not yet visually spent.
		-- Purely for the readout: the mechanic already took them, this is
		-- what lets the bar drain instead of a cell vanishing.
		burnRemaining = 0,
		burnFrom = 0,
		burnSpan = 0,
		burnFromRemaining = 0,
		tanksGained = 0, -- filled during the current drift, for the cue

		-- read by Effects / Audio / Camera
		drifting = false,
		boosting = false,
		burning = false,
		speedFrac = 0,
		slip = 0, -- 0..1, how hard the kart is actually sliding
		-- 0..1, how hard the tyres are WORKING — slip plus steering
		-- effort. This is what the screech follows; see the block that
		-- computes it for why slip alone was wrong.
		tyreLoad = 0,

		spawnCF = pivot, -- last-resort respawn target
		frozenUntil = 0,
		-- Indefinite hold, distinct from frozenUntil's timed stun: the
		-- starting grid doesn't know how long it lasts, it ends when the
		-- lights go out. Kept separate so a stun expiring can never
		-- release a kart the match is still holding.
		held = false,
		spinUntil = 0,
		-- Scramble: steering inverted until this time. Kept apart from the
		-- spin/stun timers because it's the one effect that leaves you in
		-- full control and still ruins the corner.
		reverseUntil = 0,
		spinFrom = 0,
		shieldUntil = 0,

		lean = 0,
		pitch = 0,
		bob = 0,
		squash = 0,
	}, Simulation)
end

-- Put the kart back on the track. `cf` should already be lifted clear
-- of the surface; this doesn't second-guess where you want it.
--
-- Banked tanks deliberately survive: losing your nitro as well as your
-- position is a double punishment for one mistake.
function Simulation:RespawnAt(cf: CFrame)
	self.pos = cf.Position
	self.forward = cf.LookVector
	self.travel = cf.LookVector
	self.up = cf.UpVector -- checkpoint's own up, so loops respawn correctly
	self.forward, self.up = Util.orthonormal(self.forward, self.up)

	self.speed = 0
	self.vertVel = 0
	self.slip = 0
	self.tyreLoad = 0
	self.grounded = false
	self.airTime = 0
	self.normal, self.visualNormal = self.up, self.up

	-- Everything transient is cleared; anything earned is kept.
	self.state = STATE_GRIP
	self.driftDir, self.releaseDir = 0, 0
	self.driftBlend, self.driftAngle = 0, 0
	self.tier, self.tanksGained = 0, 0
	self.burnStage, self.boostUntil = 0, 0
	self.burnRemaining = 0
	if not RS.KeepTanks then
		self.tanks, self.fill = 0, 0
	end

	-- Controls locked briefly, so you don't drive straight back off the
	-- same edge before the camera has even caught up.
	self.frozenUntil = os.clock() + RS.FreezeTime
end

-- Pin the kart until told otherwise. Used by the starting grid and by
-- the results screen; both are "you are not driving right now" rather
-- than "you have been stunned for N seconds".
function Simulation:Hold(on: boolean)
	self.held = on
end

-- Back to an empty tank for a new round.
--
-- Deliberately NOT part of RespawnAt, which keeps banked nitro on
-- purpose — losing your tanks for one mistake mid-race is a double
-- punishment. Starting a fresh race with last race's boost is a
-- different thing entirely, and it isn't fair on whoever just joined.
function Simulation:ResetForRound()
	self.reverseUntil = 0
	self.tanks = 0
	self.fill = 0
	self.tanksGained = 0
	self.tier = 0
	self.burnStage = 0
	self.burnRemaining = 0
	self.burnUntil = 0
	self.boostUntil = 0
	self.shieldUntil = 0
end

-- Leave the drift state cleanly. Factored out because there are now TWO
-- ways out — letting go of the button, and spending nitro (see
-- Nitro.EndDriftOnBurn) — and they have to unwind identically or the
-- second one leaves the kart rotating with nothing driving it.
function Simulation:_endDrift(events)
	if self.state ~= STATE_DRIFT then
		return
	end
	self.tanksGained = 0
	self.state = STATE_GRIP
	self.tier = 0
	-- Remember which way we were going so the rotation can unwind over
	-- DriftExitTime instead of stopping dead.
	self.releaseDir = self.driftDir
	self.driftDir = 0
	events.driftEnded = true
end

-- Invert steering for a while. The victim keeps throttle, brakes and
-- everything else — taking control away is frustrating, whereas steering
-- badly is a problem you can actually fight.
function Simulation:Scramble(duration: number)
	-- Extends rather than replaces, so two Scrambles in a row don't let
	-- the second one shorten the first.
	self.reverseUntil = math.max(self.reverseUntil, os.clock() + duration)
end

function Simulation:IsScrambled(): boolean
	return os.clock() < self.reverseUntil
end

-- True if a shield ate the hit. Checked by the caller so it can play
-- "blocked" feedback instead of "hit" feedback.
function Simulation:HasShield(): boolean
	return os.clock() < self.shieldUntil
end

function Simulation:GrantShield(duration: number)
	self.shieldUntil = os.clock() + duration
end

function Simulation:FillNitro()
	self.tanks = Config.Nitro.MaxTanks
	self.fill = 0
end

-- Hit by an item. Kills most of the speed and spins the body, but
-- deliberately does NOT move the kart or take away control — being
-- teleported or frozen by something you couldn't see is the least fun
-- thing an item can do.
--
-- Returns false if a shield absorbed it, so the caller can play
-- "blocked" feedback rather than "hit".
function Simulation:Spinout(duration: number, keep: number, stun: number?): boolean
	-- One hit, one shield. Consumed whether or not another was incoming.
	if self:HasShield() then
		self.shieldUntil = 0
		return false
	end

	self.speed *= math.clamp(keep, 0, 1)
	self.spinUntil = os.clock() + duration
	self.spinFrom = os.clock()
	self.state = STATE_GRIP
	self.driftDir, self.driftBlend, self.tier = 0, 0, 0
	self.burnStage = 0
	self.burnRemaining = 0

	-- Optional, and short. Reuses the respawn freeze rather than a second
	-- mechanism, so there's one place that means "controls are dead".
	if stun and stun > 0 then
		self.frozenUntil = math.max(self.frozenUntil, os.clock() + stun)
	end
	return true
end

-- External boost source (pads, items, whatever comes later). Takes the
-- stronger of the two rather than overwriting, so driving onto a pad
-- mid-drift-boost can't downgrade you.
function Simulation:ApplyBoost(speed: number, duration: number)
	self.boostSpeed = math.max(speed, self.boostSpeed)
	self.boostUntil = math.max(os.clock() + duration, self.boostUntil)
end

function Simulation:Step(dt: number, input): { [string]: any }
	local events = {}
	dt = math.min(dt, H.MaxTimestep) -- never integrate a huge frame

	local now = os.clock()
	local frozen = self.held or now < self.frozenUntil

	-- A held kart is pinned, not merely uncontrollable: zeroing speed
	-- each frame stops a boost that was live when the hold began from
	-- carrying it off the line. Gravity is left alone so karts still
	-- settle onto the grid.
	if self.held then
		self.speed = 0
		self.slip = 0
		self.tyreLoad = 0
	end

	-- While frozen the kart ignores you completely, but taps are still
	-- drained so nothing fires the instant control returns.
	-- Seat plus touch, clamped. The seat is driven by the keyboard and
	-- gamepad; the touch values come from TouchHud and are 0 on desktop,
	-- so this reduces to exactly the old behaviour there.
	--
	-- Added rather than switched between, so a device with both works with
	-- either and there's no "which input wins" rule to get wrong.
	local throttle = if frozen then 0 else math.clamp(self.seat.ThrottleFloat + input.touchThrottle, -1, 1)
	local steerIn = if frozen then 0 else math.clamp(self.seat.SteerFloat + input.touchSteer, -1, 1)

	-- Applied to the RAW input, before smoothing, so the reversal feels
	-- like the wheel is wired backwards rather than like the kart is
	-- fighting you. Smoothing it afterwards would add a lurch at the
	-- moment it wears off.
	if now < self.reverseUntil then
		steerIn = -steerIn
	end
	local pressed = input.consumeDriftPress() and not frozen

	-- Heavier to load lock up than to unwind it. Releasing the stick is
	-- the only case that uses the fast rate; counter-steering still
	-- counts as loading, because that's work.
	local unwinding = math.abs(steerIn) < math.abs(self.steer)
	local steerRate = if unwinding then H.SteerReturn else H.SteerSmoothing
	self.steer = Util.approach(self.steer, steerIn, steerRate, dt)

	----------------------------------------------------------------
	-- 1. STATE
	----------------------------------------------------------------
	if self.state == STATE_GRIP then
		if pressed and self.grounded and math.abs(self.speed) > H.HopMinSpeed then
			self.vertVel = H.HopSpeed
			self.grounded = false
			self.state = STATE_HOP
			self.hopUntil = now + H.HopMinAir
		end
	elseif self.state == STATE_HOP then
		if self.grounded and now >= self.hopUntil then
			if input.driftHeld and math.abs(steerIn) >= H.DriftEngageSteer and self.speed > H.DriftMinSpeed then
				self.state = STATE_DRIFT
				self.driftDir = math.sign(steerIn)
				self.driftStart = now
				self.tier = 0
				events.driftStarted = true
			else
				self.state = STATE_GRIP
			end
			self.squash = FX.LandSquash
		end
	elseif self.state == STATE_DRIFT then
		local newTier = tierFor(now - self.driftStart)
		if newTier ~= self.tier then
			self.tier = newTier
			events.tierChanged = newTier
		end
		if not input.driftHeld or self.speed < H.DriftExitSpeed then
			self:_endDrift(events)
		end
	end

	local drifting = self.state == STATE_DRIFT
	local boosting = now < self.boostUntil
	self.drifting, self.boosting = drifting, boosting

	-- Fill AS YOU DRIFT, not on release. Watching a tank climb while you
	-- hold the slide is what makes a long drift feel worth committing
	-- to; paying only at the end left the whole drift feeling unrewarded
	-- until it was over.
	-- burnStage is from last frame, which is close enough — the point is
	-- that a drift during a burn earns nothing.
	-- One unbroken drift can only ever bank so much. Past the cap it earns
	-- nothing until you release and re-enter — otherwise a single long
	-- sweeper fills every tank on its own and there's no reason to ever
	-- stop sliding.
	local capped = N.MaxTanksPerDrift > 0 and self.tanksGained >= N.MaxTanksPerDrift
	local earning = drifting and not capped and (N.FillWhileBurning or self.burnStage == 0)
	if earning and self.tanks < N.MaxTanks then
		local bonus = N.TierFillBonus[self.tier] or 1
		self.fill += N.FillPerSecond * bonus * dt
		while self.fill >= 1 and self.tanks < N.MaxTanks do
			self.fill -= 1
			self.tanks += 1
			self.tanksGained += 1
			events.tankFilled = self.tanks
		end
		if self.tanks >= N.MaxTanks then
			-- All full. Spare progress is wasted rather than stored.
			self.fill = if N.AllowOverflow then self.fill else 0
		end
	end

	----------------------------------------------------------------
	-- 1b. NITRO
	--
	-- Tap escalates 1 -> 2 -> 3 -> off, and burning then runs
	-- hands-free until the tank empties. One key, no hold, no timing
	-- window, and the stage is on the HUD so you're never guessing.
	----------------------------------------------------------------
	-- A tap COMMITS a tank. The first lights stage 1; each further tap
	-- mid-burn spends another tank and steps up a stage, which is why
	-- "two shifts" literally means "two tanks".
	--
	-- Every queued tap is consumed whether or not it can be spent —
	-- leaving them queued means a tap on empty fires later, the instant
	-- a drift banks, as a burn the player never asked for.
	while input.consumeNitroTap() do
		local fast = math.abs(self.speed) >= N.MinBurnSpeed
		if self.tanks > 0 and fast and self.burnStage < #N.Stages then
			self.tanks -= 1
			self.burnStage += 1
			-- Escalating restarts the clock on the new stage's duration.
			self.burnSpan = N.Stages[self.burnStage].Duration
			self.burnUntil = now + self.burnSpan
			-- Carry whatever hasn't drained yet and add the new tank, so
			-- escalating never makes the bar jump back up.
			self.burnFromRemaining = self.burnRemaining + 1
			self.burnRemaining = self.burnFromRemaining
			self.burnFrom = now
			events.nitroStage = self.burnStage

			-- Cashing in ENDS the slide. Without this a player never has to
			-- leave the drift state at all: charge, tap, keep holding,
			-- charge, tap — a permanent boost loop that costs nothing. This
			-- forces the choice the mechanic is meant to be about, keep
			-- sliding to bank more or spend and go straight.
			if N.EndDriftOnBurn then
				self:_endDrift(events)
			end
		end
	end

	-- The tap above may have ended the drift, so everything downstream has
	-- to see the new state — grip especially, or the kart keeps drift grip
	-- for a frame after it has visibly straightened up.
	drifting = self.state == STATE_DRIFT
	self.drifting = drifting

	if self.burnStage > 0 then
		-- Linear from what we had when the stage was lit down to zero,
		-- landing exactly as the burn ends.
		local elapsed = (now - self.burnFrom) / math.max(self.burnSpan, 1e-3)
		self.burnRemaining = self.burnFromRemaining * math.max(1 - elapsed, 0)
		if now >= self.burnUntil then
			self.burnStage = 0
			self.burnRemaining = 0
			events.nitroSpent = true
		end
	end

	local stage = N.Stages[self.burnStage]
	self.burning = stage ~= nil

	----------------------------------------------------------------
	-- 2. SPEED  — a lerp toward a target. No engine, no torque.
	----------------------------------------------------------------
	-- Acceleration is curved, not constant. Weak off the line, strongest
	-- through the midrange, tapering at the top — that shape is what
	-- reads as mass. Braking and coasting stay linear; only power
	-- delivery is curved, same as a real drivetrain.
	local speedNow = math.abs(self.speed)
	local powerBand = Util.sampleCurve(H.AccelCurve, speedNow / H.MaxSpeed)

	local target, rate
	local burnTarget = if stage then H.MaxSpeed + stage.Speed else 0

	if boosting and self.boostSpeed >= burnTarget then
		-- A pad stronger than the burn wins; otherwise the burn does.
		target, rate = self.boostSpeed, H.BoostAccel
	elseif stage then
		target, rate = burnTarget, N.BurnAccel
	elseif throttle > 0.05 then
		target, rate = H.MaxSpeed, H.Accel * powerBand
	elseif throttle < -0.05 then
		if self.speed > 1 then
			target, rate = 0, H.BrakeRate
		else
			target, rate = -H.ReverseSpeed, H.Accel * powerBand
		end
	else
		target, rate = 0, H.CoastRate
	end
	self.speed = Util.approach(self.speed, target, rate, dt)

	if drifting then
		-- Scrub then recover across the life of the drift, so a long
		-- drift costs speed before it pays it back.
		local driftAge = (now - self.driftStart) / H.DriftScrubWindow
		self.speed *= H.DriftSpeedKeep * Util.sampleCurve(H.DriftScrubCurve, driftAge)
	end

	----------------------------------------------------------------
	-- 3. HEADING  — where the kart actually GOES.
	----------------------------------------------------------------
	local speedAbs = math.abs(self.speed)
	local authority = math.clamp(speedAbs / H.TurnRampSpeed, 0, 1)

	-- Ramp the blend linearly, then smoothstep it. Smoothstep has zero
	-- slope at 0 and 1, so the kart eases in and out of the drift
	-- instead of stepping into it.
	local blendTarget = if drifting then 1 else 0
	local blendStep = dt / (if drifting then H.DriftEnterTime else H.DriftExitTime)
	if self.driftBlend < blendTarget then
		self.driftBlend = math.min(self.driftBlend + blendStep, blendTarget)
	else
		self.driftBlend = math.max(self.driftBlend - blendStep, blendTarget)
	end

	-- The direction survives the release so the unwind curves the same
	-- way the drift did.
	local activeDir = if drifting then self.driftDir else self.releaseDir
	if self.driftBlend <= 0 then
		self.releaseDir = 0
		activeDir = 0
	end

	local eased = Util.smoothstep(self.driftBlend)

	-- Normal steering. Heading DECREASES to turn right, hence the minus.
	local ratio = math.clamp(speedAbs / H.MaxSpeed, 0, 1)
	local turn = H.TurnRate + (H.TurnRateTop - H.TurnRate) * ratio
	local reversing = if self.speed < 0 then -1 else 1
	local steerTurn = -self.steer * turn * reversing

	-- Drift rotation. Tighter than steering can manage — that's the reward.
	local trim = math.clamp(steerIn * activeDir, -1, 1)
	local driftTurn = -activeDir * (H.DriftTurnBase + trim * H.DriftTurnTrim)

	-- Crossfade rather than switch, then spin `forward` about the
	-- current `up`. On a loop `up` is the track normal, so steering
	-- stays correct sideways and upside-down without special cases.
	local yawDelta = (steerTurn * (1 - eased) + driftTurn * eased) * authority * dt
	self.forward = Util.rotateAbout(self.forward, self.up, yawDelta)
	self.forward, self.up = Util.orthonormal(self.forward, self.up)

	----------------------------------------------------------------
	-- 4. MOMENTUM
	--
	-- The kart moves along `travel`, which chases the nose instead of
	-- being welded to it. That lag is the entire feeling of weight:
	-- turn in and the kart carries on where it was going for a beat
	-- before the new heading takes over. Welding travel to forward is
	-- what made it feel like it was on rails.
	----------------------------------------------------------------
	local gripRate = if drifting then H.DriftGrip else H.Grip
	self.travel = self.travel:Lerp(self.forward, math.min(gripRate * dt, 1))
	self.travel = (Util.orthonormal(self.travel, self.up))

	-- Hard-cap the slip so momentum can never carry the kart sideways
	-- or backwards, however hard you saw at the wheel.
	local maxSlip = math.rad(H.MaxSlip)
	local slipDot = math.clamp(self.travel:Dot(self.forward), -1, 1)
	local slipAngle = math.acos(slipDot)
	if slipAngle > maxSlip then
		local axis = self.travel:Cross(self.forward)
		if axis.Magnitude > 1e-4 then
			self.travel = Util.rotateAbout(self.travel, axis.Unit, slipAngle - maxSlip)
		end
	end

	-- Parked or crawling, there's no momentum to carry. Snapping here
	-- stops a stale travel direction lurching the kart on pull-away.
	if math.abs(self.speed) < 1 then
		self.travel = self.forward
		slipAngle = 0
	end

	-- 0 = tracking true, 1 = at the slip cap. This is the real physical
	-- quantity a tyre screech should follow — how hard the kart is
	-- actually sliding — rather than a binary "is drifting" flag. A hard
	-- unsettled corner squeals a little; a committed drift howls.
	self.slip = math.clamp(slipAngle / maxSlip, 0, 1)

	----------------------------------------------------------------
	-- TYRE LOAD — what the screech actually follows.
	--
	-- Named `tyreLoad`, NOT scrub: `DriftScrubCurve` in Handling already
	-- means SPEED scrub, and one word meaning two things in one codebase
	-- is how the wrong constant gets tuned.
	--
	-- Slip angle is the wrong signal on its own, and the failure is
	-- counter-intuitive: catching a slide by counter-steering REDUCES the
	-- slip angle by definition, because you're pointing the nose at where
	-- the kart is already going. So the sound faded out at precisely the
	-- moment the driver was working hardest — hold a drift, stab the
	-- opposite way, silence.
	--
	-- Tyre load is "how hard are the tyres being asked to work", which is
	-- three things at once, whichever is greatest.
	----------------------------------------------------------------
	local effort = self.slip
	local speedFrac = math.clamp(math.abs(self.speed) / H.MaxSpeed, 0, 1)

	if self.state == STATE_DRIFT then
		-- A committed drift is never quiet. The rear is loose regardless of
		-- where the nose happens to be pointing.
		effort = math.max(effort, H.TyreDriftLoad)

		-- Actively fighting it is the loudest thing you can do. Scaled by
		-- how much lock is being used, so a nudge of correction is quieter
		-- than a full stab.
		if self.driftDir ~= 0 and math.sign(self.steer) == -self.driftDir then
			effort = math.max(effort, H.TyreCounterLoad * math.abs(self.steer))
		end
	end

	-- Hard cornering at speed loads the tyres even when fully gripped —
	-- that's the difference between a quiet turn and a loaded one.
	effort = math.max(effort, math.abs(self.steer) * speedFrac * H.TyreCornerLoad)

	self.tyreLoad = math.clamp(effort, 0, 1)

	----------------------------------------------------------------
	-- 5. INTEGRATE
	----------------------------------------------------------------
	-- `travel` is already perpendicular to `up`, so it follows the
	-- surface for free — no projection needed.
	local velocity = self.travel * self.speed

	-- Gravity pulls along -up, which on a loop means INTO the track.
	self.vertVel -= H.Gravity * dt
	velocity += self.up * self.vertVel

	----------------------------------------------------------------
	-- 6. COLLISION  — swept, and resolved by us. Deterministic.
	----------------------------------------------------------------
	-- Lift the bottom of the sweep box clear of anything shorter than
	-- StepHeight, so kerbs, ramp lips and the sharp apex of a wedge
	-- don't register as walls. The ground probe below climbs them.
	local size = self.hitbox.Size
	local floor = size.Y * 0.5 - H.RideHeight -- box bottom rel. to origin
	local lift = math.max(H.StepHeight + floor, 0)
	local castSize = Vector3.new(size.X, math.max(size.Y - lift, 0.4), size.Z)

	-- Box is oriented and lifted along OUR up, not the world's, so the
	-- step-over still works while sideways on a loop wall.
	local function sweepFrame(): CFrame
		return CFrame.fromMatrix(
			self.pos + self.up * (lift * 0.5),
			self.forward:Cross(self.up),
			self.up,
			-self.forward
		)
	end

	-- Push out of anything we're already overlapping. A Blockcast that
	-- begins inside geometry returns nothing, so a single frame of
	-- penetration would otherwise let the kart move through walls freely
	-- from then on. Drifting into a wall is the usual way in.
	local overlaps = workspace:GetPartBoundsInBox(sweepFrame(), castSize, self.overlapParams)
	for _, part in overlaps do
		local away = self.pos - part.Position
		away -= self.up * away:Dot(self.up) -- stay in the surface plane
		if away.Magnitude > 1e-3 then
			self.pos += away.Unit * H.Depenetrate * dt
		end
	end

	-- Swept slide. Each pass re-casts from the new position, so sliding
	-- along one wall can't shove us through the next.
	local remaining = velocity * dt
	for _ = 1, H.CollisionPasses do
		local travel = remaining.Magnitude
		if travel < 1e-4 then
			break
		end

		local hit = workspace:Blockcast(sweepFrame(), castSize, remaining, self.rayParams)
		-- "Wall" is measured against OUR up, so a loop's vertical
		-- section is drivable road rather than an obstacle.
		if not hit or hit.Normal:Dot(self.up) >= H.MaxSlopeDot then
			self.pos += remaining
			break
		end

		local dir = remaining.Unit
		local reached = math.clamp(hit.Distance, 0, travel)
		self.pos += dir * math.max(reached - H.SkinWidth, 0)
		self.speed *= 1 - H.WallScrub * math.abs(dir:Dot(hit.Normal))

		-- What's left, flattened onto the wall. Re-cast next pass.
		local leftover = remaining - dir * reached
		remaining = leftover - hit.Normal * leftover:Dot(hit.Normal)
	end

	----------------------------------------------------------------
	-- 7. GROUND
	----------------------------------------------------------------
	-- Five rays cast along -up, not world-down, so this works on a loop.
	local probeRight = self.forward:Cross(self.up)
	local reach = H.ProbeUp + H.RideHeight + H.GroundSnap
	local castDir = -self.up * reach
	local probeLift = self.up * H.ProbeUp

	-- SLOPE vs STEP
	--
	-- The centre probe governs height. Outer probes only raise it when
	-- they're higher than the CENTRE'S OWN SURFACE PLANE would put them —
	-- that's the difference between a ramp and a step, and getting it
	-- wrong is what made wedges lumpy.
	--
	-- On a slope the front probe is legitimately higher, and taking the
	-- highest lifted the kart to a point `spread × gradient` up the ramp,
	-- so it rode high and every transition jolted. Flat parts hid it
	-- because all five probes agree there.
	--
	-- `normalSum` is averaged for ORIENTATION regardless, which is what
	-- stops each stair riser reading as a wall.
	local offsets = {
		Vector3.zero, -- index 1 is the centre, and it's authoritative
		self.forward * H.ProbeSpread,
		-self.forward * H.ProbeSpread,
		probeRight * H.ProbeSpread,
		-probeRight * H.ProbeSpread,
	}

	local centreAlong, centreNormal = nil, nil
	local outer = {}
	local normalSum, hits = Vector3.zero, 0

	for i, offset in offsets do
		local probe = workspace:Raycast(self.pos + offset + probeLift, castDir, self.rayParams)
		if probe and probe.Normal:Dot(self.up) > H.MaxSlopeDot then
			local along = (probe.Position - self.pos):Dot(self.up)
			if i == 1 then
				centreAlong, centreNormal = along, probe.Normal
			else
				table.insert(outer, { along = along, offset = offset, normal = probe.Normal })
			end
			normalSum += probe.Normal
			hits += 1
		end
	end

	local highest, highestNormal = centreAlong, centreNormal

	if centreAlong and centreNormal then
		-- Where the centre's plane would put a probe at this offset. Any
		-- probe meaningfully above that is a genuine step up.
		local denom = centreNormal:Dot(self.up)
		for _, o in outer do
			local expected = centreAlong
			if math.abs(denom) > 1e-4 then
				expected += -o.offset:Dot(centreNormal) / denom
			end
			local step = o.along - expected
			if step > H.StepTolerance and o.along > highest and step <= H.StepHeight then
				highest, highestNormal = o.along, o.normal
			end
		end
	else
		-- Centre found nothing — we're over an edge. Fall back to the
		-- highest outer probe so a ledge still catches us.
		for _, o in outer do
			if not highest or o.along > highest then
				highest, highestNormal = o.along, o.normal
			end
		end
	end

	self.wasGrounded = self.grounded
	self.grounded = false

	if highest then
		local surfaceNormal = highestNormal
		if H.StairSmoothing and hits > 1 and normalSum.Magnitude > 1e-3 then
			surfaceNormal = normalSum.Unit
		end

		-- `highest` is negative when the ground is below us. Attach if
		-- we're within snapping range and not still rising off a hop.
		-- Climbing is allowed to be generous; falling isn't. One value for
		-- both meant a ramp taken at boost speed outran the snap and the
		-- kart ended up inside it.
		local gap = -highest - H.RideHeight
		local allowed = if gap < 0 then H.GroundSnapUp else H.GroundSnap
		if self.vertVel <= 0 and gap <= allowed then
			self.pos += self.up * (highest + H.RideHeight)
			self.vertVel = 0
			self.grounded = true
			self.normal = surfaceNormal
		end
	end

	----------------------------------------------------------------
	-- 6b. SURFACE GRAVITY — rotate our idea of "down" onto the track.
	----------------------------------------------------------------
	if self.grounded then
		self.airTime = 0
		-- Chase the surface briskly; a slow chase sheds the kart on a
		-- tight loop because gravity keeps pointing at the old normal.
		self.up = self.up:Lerp(self.normal, math.min(H.SurfaceAlignRate * dt, 1))
	else
		self.airTime += dt
		if self.airTime >= H.StickTime then
			-- Genuinely airborne. Settle back to world-up so you land level.
			self.up = self.up:Lerp(Vector3.yAxis, math.min(H.AirAlignRate * dt, 1))
		end
		-- Below StickTime we keep the old up untouched: that grace
		-- period carries the kart across seams, stair nosings and panel
		-- gaps without gravity flipping back to world-down for a frame.
	end
	self.forward, self.up = Util.orthonormal(self.forward, self.up)

	if self.grounded and not self.wasGrounded and self.state ~= STATE_HOP then
		self.squash = FX.LandSquash
		events.landed = true
	end

	----------------------------------------------------------------
	-- 8. PRESENTATION  — lies, all of it. None feeds back into movement.
	----------------------------------------------------------------
	-- Nose points INTO the turn while the kart keeps travelling along
	-- `forward`. Driven off the same eased blend as the rotation, so the
	-- body angle and the turn arrive together.
	self.driftAngle = -activeDir * math.rad(H.DriftVisualAngle) * eased

	-- Spinning out overrides the drift angle entirely. Several fast
	-- revolutions that decelerate, plus roll and pitch thrown around, so
	-- being hit reads as losing control rather than as a neat pirouette.
	--
	-- The kart still TRAVELS along `forward` throughout — only the body is
	-- thrashing. That's what keeps a spinout recoverable instead of
	-- disorienting: you never actually lose your line, just your dignity.
	local spinning = now < self.spinUntil
	if spinning then
		local span = math.max(self.spinUntil - self.spinFrom, 1e-3)
		local t = math.clamp((now - self.spinFrom) / span, 0, 1)
		local spun = 1 - (1 - t) ^ FX.SpinEase
		self.driftAngle = math.pi * 2 * FX.SpinRevolutions * spun

		-- Thrash decays with the spin, so it settles rather than stopping.
		local fade = 1 - t
		local wobble = math.sin(now * FX.SpinWobbleRate * math.pi * 2) * fade
		self.lean = math.rad(FX.SpinWobble) * wobble
		self.pitch = math.rad(FX.SpinPitch) * math.cos(now * FX.SpinWobbleRate * math.pi * 3) * fade
	end

	-- Skipped while spinning: the thrash above owns lean and pitch, and
	-- smoothing toward a steering target would fight it flat.
	if not spinning then
		local leanTarget = -self.steer * math.rad(FX.LeanAngle) + -activeDir * math.rad(FX.DriftLeanBonus) * eased
		self.lean = Util.approach(self.lean, leanTarget, FX.LeanRate, dt)

		local pitchTarget = math.rad(FX.PitchOnAccel) * (boosting and -1 or -throttle) * 0.5
		self.pitch = Util.approach(self.pitch, pitchTarget, FX.PitchRate, dt)
	end

	self.squash = Util.approach(self.squash, 0, FX.SquashRate, dt)
	self.speedFrac = math.clamp(speedAbs / H.MaxSpeed, 0, 1)
	self.bob = if self.grounded
		then math.sin(now * FX.BobSpeed) * FX.BobAmount * self.speedFrac
		else 0

	-- The body eases onto the surface a touch behind the simulation, so
	-- kerbs and seams don't jolt it. Purely visual lag.
	self.visualNormal = self.visualNormal:Lerp(self.up, math.min(FX.SlopeAlignRate * dt, 1))

	-- Cosmetic drift angle is a spin about our own up, so it stays
	-- correct sideways and upside-down.
	local look, up = Util.orthonormal(Util.rotateAbout(self.forward, self.up, self.driftAngle), self.visualNormal)
	local right = look:Cross(up).Unit
	look = up:Cross(right).Unit

	-- Bob and squash ride along up, not world-Y.
	local visualPos = self.pos + up * (self.bob - self.squash)
	local base = CFrame.fromMatrix(visualPos, right, up, -look)
	self.hitbox.CFrame = base * CFrame.Angles(self.pitch, 0, self.lean)
	self.hitbox.AssemblyLinearVelocity = velocity
	self.hitbox.AssemblyAngularVelocity = Vector3.zero

	if FX.ShowState then
		-- `tilt` is how far our up has rotated off world-up: 0 on flat
		-- road, 90 on a loop wall, 180 upside-down at the top.
		print(
			("%-5s | spd %6.1f | tilt %5.1f° | tier %d%s%s"):format(
				self.state,
				self.speed,
				math.deg(math.acos(math.clamp(self.up.Y, -1, 1))),
				self.tier,
				self.grounded and "" or " | AIR",
				boosting and " | BOOST" or ""
			)
		)
	end

	return events
end

return Simulation
