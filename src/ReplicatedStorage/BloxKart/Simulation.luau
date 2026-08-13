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

	SHARED, NOT CLIENT-ONLY
	-----------------------
	Lives here rather than under KartClient because the SERVER runs it
	too, for bots. It touches no client-only API — no LocalPlayer, no
	camera, no input service — and reads its controls off a plain table,
	so a bot is simply another thing filling that table in.

	Which also means a bot drives the identical kart with identical
	handling. There is no separate AI physics to drift out of sync with
	this one, and that is usually why bot racers feel fake.

	Step() returns an events table so Effects and Audio can react without
	this module knowing they exist.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")

local CollectionService = game:GetService("CollectionService")

local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))
local TagZones = require(script.Parent.TagZones)
local Util = require(BloxKart:WaitForChild("Util"))
local WorldFilter = require(BloxKart:WaitForChild("WorldFilter"))

local H = Config.Handling
local GL = Config.Glide
local SW = Config.Swim
local TR = Config.Trick
local N = Config.Nitro
local FX = Config.Effects
local RS = Config.Respawn
local BK = Config.Bike

local STATE_GRIP = "grip"
local STATE_HOP = "hop"
local STATE_DRIFT = "drift"
-- Wings out. A state rather than a flag because it changes gravity,
-- steering authority and what the throttle means all at once — three
-- booleans that can never legally disagree are one state.
local STATE_GLIDE = "glide"

local Simulation = {}
Simulation.__index = Simulation

Simulation.GRIP = STATE_GRIP
Simulation.HOP = STATE_HOP
Simulation.DRIFT = STATE_DRIFT

-- Takes the vehicle's handling table: drift tiers are a per-vehicle
-- figure, and this is module scope so there is no `self` to read.
local function tierFor(H, t: number): number
	if t >= H.BoostTier3Time then
		return 3
	elseif t >= H.BoostTier2Time then
		return 2
	elseif t >= H.BoostTier1Time then
		return 1
	end
	return 0
end

local warnedNoFilter = false

--=====================================================================
--  ONE HANDLING TABLE PER VEHICLE, ONE SOURCE OF TRUTH.
--
--  Every dial was read from `Config.Handling` directly, which is fine
--  for one vehicle and impossible for two. A motorcycle wants a
--  different turn rate and a different lean and the SAME meaning for
--  everything else.
--
--  `self.H` is a small override table with `Config.Handling` behind it
--  on a metatable. A vehicle lists only what it differs on; anything it
--  does not mention resolves to the shared value; a default still lives
--  in exactly one place. Adding a dial to Config.Handling reaches every
--  vehicle for free — the property that copying the table per vehicle
--  would quietly destroy.
--
--  `config-keys.py` still validates every key, because they are still
--  Config.Handling's keys.
--=====================================================================
function Simulation.new(
	model: Model,
	hitbox: BasePart,
	seat: VehicleSeat,
	_character: Model?,
	handling: { [string]: any }?
)
	-- Resolved once here so the constructor's own reads see the vehicle's
	-- values too, not just the methods'.
	local vehicleH = setmetatable(handling or {}, { __index = H })
	-- The exclusion list IS the collision rule here — movement is
	-- query-based, so an unstarted filter means this kart treats every
	-- other kart and every trigger volume as solid wall.
	--
	-- Worth a warning because it fails SILENTLY: the kart drives, it just
	-- bumps into things nothing should bump into, which reads as a physics
	-- problem rather than a missing call. It cost a full debugging round
	-- on the server, where nothing had started it.
	if not WorldFilter.isStarted() and not warnedNoFilter then
		warnedNoFilter = true
		warn("[Simulation] WorldFilter.start() has not been called here — karts will collide with each other and with trigger volumes.")
	end
	-- Shared, and maintained centrally: it excludes EVERY kart and
	-- character, not just ours, so other racers are never mistaken for
	-- walls or ground.
	local rayParams = WorldFilter.rayParams
	local overlapParams = WorldFilter.overlapParams

	local pivot = hitbox.CFrame

	return setmetatable({
		-- Vehicle overrides in front, Config.Handling behind.
		H = vehicleH,
		-- A bike's banking belongs on the final hitbox render pose. Every
		-- visual piece, the seat and the seated character are connected to
		-- this part, so this is the one place a lean can move the complete
		-- motorcycle together.
		isBike = model:GetAttribute(Names.VEHICLE_KIND) == "bike",
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
		-- Grip is chased rather than switched, so the hop and the drift
		-- release stop stepping it. See Handling.GripBlendRate.
		gripNow = vehicleH.Grip,
		state = STATE_GRIP,
		hopUntil = 0,
		bounceUntil = 0,
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
		reverseSpan = 0,
		spinFrom = 0,
		shieldUntil = 0,

		lean = 0,
		bikeLeanVelocity = 0,
		pitch = 0,
		bob = 0,
		squash = 0,
		squashVel = 0, -- the suspension spring's velocity term
		guide = nil, -- temporary presentation/movement takeover (Rainbow)
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
	-- Full grip, not whatever the drift or hop we died in had left it on.
	self.gripNow = self.H.Grip
	self.squash, self.squashVel = 0, 0
	self.catch = 0

	-- Everything transient is cleared; anything earned is kept.
	self.state = STATE_GRIP
	self.glideFrom = nil
	self.glideTo = nil
	self.glideUntil = 0
	self.bounceUntil = 0
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

-- A guided item supplies its final pose here rather than fighting the
-- normal ground/render pass from outside Simulation. Nil restores normal
-- driving on the next frame.
function Simulation:SetGuide(guide: any?)
	self.guide = guide
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
	-- REPORTED BEFORE IT IS CLEARED. The tier a drift reached is the
	-- only measure of whether it was a good one, and it was being thrown
	-- away one line later — so nothing downstream could tell a committed
	-- slide from a twitch.
	events.driftTier = self.tier
	self.tanksGained = 0
	self.state = STATE_GRIP
	self.glideFrom = nil
	self.glideTo = nil
	self.glideUntil = 0
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
	-- Remembered so the warning can show a FRACTION rather than raw
	-- seconds. Taken from the actual hit rather than from config,
	-- because two scrambles overlapping make the real span longer than
	-- any single item's duration.
	self.reverseSpan = math.max(self.reverseUntil - os.clock(), 0.01)
end

function Simulation:IsScrambled(): boolean
	return os.clock() < self.reverseUntil
end

-- Seconds of inverted steering left, or 0. Exposed so the warning can
-- say how long you have rather than only that it is happening — a
-- blinking alert that never changes tells you nothing about when it
-- ends, which is the one thing you want to know while it is on.
function Simulation:ScrambleLeft(): number
	return math.max(self.reverseUntil - os.clock(), 0)
end

-- How much of the scramble is LEFT, 0..1. 1 the instant it lands, 0 as
-- it releases. Self-contained: the caller does not have to know which
-- item caused it or how long that item lasts.
function Simulation:ScrambleFrac(): number
	local span = self.reverseSpan or 0
	if span <= 0 then
		return 0
	end
	return math.clamp(self:ScrambleLeft() / span, 0, 1)
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
-- `real` makes the spin turn the kart for ACTUAL — see the note where it
-- is applied. An item spinout stays visual; a wall does not.
function Simulation:Spinout(duration: number, keep: number, stun: number?, revs: number?, real: boolean?): boolean
	-- One hit, one shield. Consumed whether or not another was incoming.
	if self:HasShield() then
		self.shieldUntil = 0
		return false
	end

	self.speed *= math.clamp(keep, 0, 1)
	self.spinUntil = os.clock() + duration
	self.spinFrom = os.clock()
	-- Nil means the item spinout's full count. A wall passes a smaller
	-- one: shortening the duration alone would spin the SAME distance in
	-- less time, which is faster rather than gentler.
	self.spinRevs = revs
	self.spinReal = real == true
	self.spinApplied = 0
	self.spinDir = if math.random() < 0.5 then -1 else 1

	-- KNOCKED OFF LINE, not just slowed.
	--
	-- A spinout used to be purely cosmetic plus a speed penalty: the body
	-- thrashed, but `forward` never moved, so you came out of it pointing
	-- exactly where you went in. Recovery was holding the throttle and
	-- waiting — nothing to actually do.
	--
	-- Now the heading is knocked round and the kart shoved sideways, so
	-- you finish the spin off your line and pointing slightly wrong, and
	-- getting back on it is a real correction.
	--
	-- Deliberately small. The reason the spin was recoverable in the
	-- first place is that you never lost your bearings, and a big enough
	-- rotation turns "reposition" into "which way am I facing" — which is
	-- disorienting rather than difficult. This is meant to cost you a
	-- corner, not a lap.
	--
	-- Rotated about OUR up and shoved along OUR right, so it behaves the
	-- same upside-down on a loop as it does on the flat.
	-- Only for something that actually SPINS you. Scramble comes through
	-- here with a zero duration — it inverts your steering rather than
	-- spinning the kart — and knocking it off line as well would be a
	-- second, unrelated punishment nobody asked that item for.
	if duration > 0 then
		local dir = if math.random() < 0.5 then -1 else 1
		local yaw = math.rad(self.H.SpinYaw) * dir
		self.forward = Util.rotateAbout(self.forward, self.up, yaw)
		-- `travel` comes with it. Leaving it behind would launch the kart
		-- sideways at full speed, which is a crash rather than a spin.
		self.travel = Util.rotateAbout(self.travel, self.up, yaw)
		self.forward, self.up = Util.orthonormal(self.forward, self.up)

		local right = self.forward:Cross(self.up)
		if right.Magnitude > 1e-4 then
			self.pos += right.Unit * self.H.SpinShove * dir
		end
	end
	self.state = STATE_GRIP
	self.glideFrom = nil
	self.glideTo = nil
	self.glideUntil = 0
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

--=====================================================================
--  GLIDE
--=====================================================================

-- The landing zone this ramp is pointing at, or nil for free flight.
--
-- NEAREST ONE IN FRONT, not nearest overall: a track that loops back on
-- itself can easily have a landing zone closer behind you than the one
-- you are being thrown at, and aiming the corridor backwards would fly
-- you into the wall you just left.
local function landingFor(from: Vector3, heading: Vector3): Vector3?
	local best, bestDist = nil, math.huge
	for _, part in CollectionService:GetTagged(GL.LandTag) do
		if part:IsA("BasePart") then
			-- THE TOP FACE, not the centre. A pad is a slab, and aiming at
			-- its middle aims half its thickness underground — on a thick
			-- marker that is the difference between landing on it and
			-- landing in it.
			local top = part.Position + part.CFrame.UpVector * (part.Size.Y * 0.5)
			local to = top - from
			if to:Dot(heading) > 0 then
				local d = to.Magnitude
				if d < bestDist then
					best, bestDist = top, d
				end
			end
		end
	end
	return best
end

-- Called when the kart crosses a ramp. Public so a power-up or the dev
-- console can throw one too.
function Simulation:StartGlide(launchCF: CFrame?)
	if not GL.Enabled or self.state == STATE_GLIDE then
		return false
	end
	if math.abs(self.speed) < GL.MinSpeed then
		return false
	end

	-- The RAMP decides which way is up, not the world. A ramp on a banked
	-- section throws you along the bank, which is the whole reason the
	-- launch reads the part's own orientation.
	local up = if launchCF then launchCF.UpVector else self.up

	self.state = STATE_GLIDE
	if self.model then
		self.model:SetAttribute(Names.GLIDING, true)
	end
	self.glideUntil = os.clock() + GL.MaxTime
	self.speed = math.abs(self.speed) * GL.LaunchSpeedScale
	self.vertVel = GL.LaunchUp
	-- OFF THE GROUND, SAID OUT LOUD. The hop does this too: a kick alone
	-- does not clear GroundSnap within a frame, so without it the very
	-- next ground probe still reports contact.
	self.grounded = false
	self.glideMinUntil = os.clock() + GL.MinAirTime
	self.up = up
	self.forward, self.up = Util.orthonormal(self.forward, self.up)

	-- The corridor is fixed AT LAUNCH and never recomputed. Re-aiming it
	-- mid-flight would let a player who has drifted wide drag the target
	-- with them, which is precisely the failure the corridor exists to
	-- prevent.
	-- A REAL BOOST, through the same door everything else uses. The sound,
	-- the effects and the thruster flare all key off this rather than off
	-- anything glide-specific.
	self:ApplyBoost(GL.LaunchBoostSpeed, GL.LaunchBoostTime)

	self.glideFrom = self.pos
	self.glideTo = landingFor(self.pos, self.forward)

	-- Drift cannot survive a launch: the blend and the release direction
	-- are ground concepts and would unwind into the glide as a phantom
	-- steering input.
	self.driftBlend = 0
	self.releaseDir = 0
	self.driftDir = 0
	return true
end

function Simulation:EndGlide()
	-- THE FLAG IS CLEARED FIRST AND UNCONDITIONALLY. Guarding the whole
	-- function on the state meant that anything else moving the kart out
	-- of STATE_GLIDE — a respawn, a reset — left `Gliding` true forever,
	-- and the wings with it. Cheap to always clear; expensive to miss.
	if self.model then
		self.model:SetAttribute(Names.GLIDING, false)
		self.model:SetAttribute(Names.GLIDE_PITCH, 0)
	end
	if self.state ~= STATE_GLIDE then
		return
	end
	self.state = STATE_GRIP
	self.glideFrom = nil
	self.glideTo = nil
	self.glideUntil = 0
	self.glideFrom = nil
	self.glideTo = nil
	self.speed *= GL.LandSpeedKeep
end

-- How far off the ramp-to-landing line we are, signed, and the axis to
-- correct about. Zero when there is no corridor.
local function corridorPush(self, dt: number): number
	local from, to = self.glideFrom, self.glideTo
	if not from or not to then
		return 0
	end
	local line = to - from
	if line.Magnitude < 1 then
		return 0
	end
	local dir = line.Unit
	local offset = self.pos - from
	-- Component across the line, in the plane we are flying in.
	local across = offset - dir * offset:Dot(dir)
	local side = across:Dot(self.up:Cross(dir))
	local wide = math.abs(side) - GL.CorridorHalf
	if wide <= 0 then
		return 0
	end

	-- Ramped, not switched. A step change in yaw the instant you cross a
	-- line is exactly what makes a correction feel like glass.
	local strength = math.clamp(wide / math.max(GL.CorridorRamp, 0.01), 0, 1)
	return -math.sign(side) * strength * GL.CorridorPull * dt
end

--=====================================================================
--  SWIM
--
--  A CONTINUOUS 0..1, NOT A BOOLEAN. Crossing a shoreline is a step
--  change in top speed, and a step change in top speed reads as hitting
--  something. Easing it means the kart slows into the water and picks up
--  as it leaves, which is both what water does and what feels like a
--  transition rather than a wall.
--
--  Overlapping() rather than Touch(): Touch answers "which trigger did I
--  just enter", which is right for a boost pad and wrong here — being in
--  water is a state you are continuously in, not an event.
--=====================================================================
local swimZones: any = nil

-- The same field Rider draws the hull's motion from. Exported so the two
-- CANNOT disagree about where the water is — a kart pitching over a
-- crest the simulation does not believe in is the whole failure this
-- avoids.
function Simulation.waveAt(pos: Vector3, t: number?): number
	-- DEFENSIVE ON THE CLOCK ONLY, because a missing one is a wiring
	-- mistake that otherwise throws sixty times a second and buries every
	-- other message in Output — which is exactly what it did.
	local clock = if type(t) == "number" then t else 0
	local h = 0
	for _, w in SW.Waves do
		local rad = math.rad(w.heading)
		local along = pos.X * math.cos(rad) + pos.Z * math.sin(rad)
		h += math.sin(along / w.length * math.pi * 2 + clock * w.speed) * w.amp
	end
	return h
end

function Simulation:_updateSwim(dt: number)
	if not SW.Enabled then
		self.swim = 0
		-- CLEARED, not left standing. It is a ONE-FRAME flag, and a flag
		-- that is only ever set is a flag that latches: switching swimming
		-- off mid-session would leave the last `true` in place and fire a
		-- splash on every subsequent frame forever.
		self.enteredWaterThisFrame = false
		self.wasWet = false
		return
	end

	if not swimZones then
		swimZones = TagZones.new(SW.ZoneTag, { cooldown = 0, forceQueryable = true })
	end

	local wet = #swimZones:Overlapping(CFrame.new(self.pos), self.hitbox.Size) > 0

	-- THE TRANSITION, not the state. The splash is an EVENT — it belongs
	-- to the moment of entry, so it is measured as an edge and consumed
	-- once. Driving along in water is not entering it.
	self.enteredWaterThisFrame = wet and not (self.wasWet == true)
	self.wasWet = wet

	self.swim = Util.approach(self.swim or 0, if wet then 1 else 0, SW.BlendRate, dt)

	if self.model then
		self.model:SetAttribute(Names.SWIMMING, self.swim)
	end

	-- THE SEA'S CLOCK. Advanced here and nowhere else.
	--
	-- Never reset to zero on leaving the water: restarting it would make
	-- the swell jump to a different phase every time you touch land, so
	-- the sea would visibly lurch as you re-enter it.
	self.seaClock = (self.seaClock or 0) + dt

	-- The hull's motion is drawn from this on the client; nothing here
	-- pushes the kart any more.
	--
	-- Real vertical impulses came out: under GroundSnap they were
	-- swallowed and did nothing, over it they were a literal jump, and a
	-- boat does neither. The ride is orientation, and orientation is
	-- visual.
	local now = Simulation.waveAt(self.pos, self.seaClock)
	self.waveRise = (now - (self.lastWave or now)) / math.max(dt, 1e-3)
	self.lastWave = now
	if self.model then
		self.model:SetAttribute(Names.WAVE_RISE, self.waveRise)
		-- PUBLISHED, so the hull is drawn from the same clock the rise was
		-- measured with. Two clocks advancing by dt from different start
		-- moments drift apart, and then the visual crest and the hop
		-- that is supposed to accompany it are on different waves.
		self.model:SetAttribute(Names.SEA_CLOCK, self.seaClock)
	end

	--== THE WATER HOP ================================================
	-- The kart skips over the swell. It is the hop you get from spamming
	-- jump across water, run automatically off the wave field.
	--
	-- IT LIVES HERE BECAUSE IT MUST MOVE THE WHOLE KART.
	-- --------------------------------------------------
	-- The first version drove the body motor from Rider, and it was
	-- invisible for the same reason the flip's first two versions were:
	-- a joint moves the things BELOW it and nothing else. The bodywork
	-- rose; the wheels, the seat and the driver did not. A kart whose
	-- shell lifts a stud off its own stationary wheels does not read as
	-- skipping, it reads as nothing at all.
	--
	-- `Motor6D.Transform` is also client-local, so none of it ever
	-- reached another player.
	--
	-- The render write moves everything jointed to the hitbox at once and
	-- replicates by itself. Same lesson the flip paid for twice: move the
	-- thing they are all attached to, not a list.
	--
	-- STILL PURELY VISUAL. `swimHop` is added to `visualPos` only, beside
	-- `bob`, `squash` and `catch`. It never touches `pos`, `vertVel`,
	-- `grounded`, the sweep or the ground probe — the kart drives dead
	-- flat on the invisible floor the whole time.
	-- THE WAVE DECIDES HOW BIG, NEVER WHETHER.
	--
	-- This used to launch only when the field was rising past a
	-- threshold, and that is what made the rhythm wrong: hop, hop, gap,
	-- hop, gap, hop, hop. The gaps were every moment the wave happened to
	-- be falling. Spamming jump has no gaps, and the whole point of this
	-- feature is to look like spamming jump.
	--
	-- So the launch is now unconditional while moving in water, and the
	-- wave field sets the SIZE instead. The motion stays constant, the
	-- variation stays, and nothing ever stops.
	-- IT IS A PHASE, NOT AN INTEGRATION, AND THAT IS WHAT KILLED THE SNAP.
	--
	-- It was a real ballistic arc: an impulse at launch, gravity, a hard
	-- stop at zero. That arc has a VELOCITY DISCONTINUITY at both ends —
	-- 0 to +v when it launches and -v to 0 when it lands — and those two
	-- corners are the snap. They cannot be tuned out, because they are
	-- what a ballistic arc IS. A single jump gets away with it; two and a
	-- half a second does not.
	--
	-- Driving the height from a phase lets the SHAPE be chosen instead of
	-- inherited, and `sin^2` has zero slope at both ends: it eases out of
	-- the water and settles back without a corner anywhere. `WaveHopSmooth`
	-- blends between the two, so the ballistic feel is still available.
	local driving = math.abs(self.speed) >= SW.WaveHopMinSpeed
	if SW.WaveHopEnabled and (self.swim or 0) >= SW.WaveHopMinSwim and driving then
		local pace = math.clamp(math.abs(self.speed) / math.max(self.H.MaxSpeed, 1), 0, 1)
		local k = 1 + SW.WaveHopPaceArc * pace

		-- The dials still describe an arc — `airtime = 2v/g`, `apex =
		-- v*airtime/4` — because that is how the height and the rhythm
		-- were solved and it keeps every earlier measurement meaningful.
		-- Only the CURVE between those endpoints has changed.
		local air = (2 * SW.WaveHopVelocity / SW.WaveHopGravity) / k
		local rest = SW.WaveHopCooldown * (1 - SW.WaveHopPaceRest * pace)
		local cycle = math.max(air + rest, 1e-3)
		self.swimHopAir = air / cycle
		-- Kept so an arc still running after the kart leaves the water
		-- finishes at the speed it started at.
		self.swimHopCycle = cycle

		local phase = (self.swimHopPhase or 1) + dt / cycle
		if phase >= 1 then
			phase -= math.floor(phase)
			-- A NEW CYCLE. Size is sampled once, here, so the hop cannot
			-- change shape underneath itself — the same reason gravity
			-- used to be captured at launch.
			--
			-- SYMMETRIC ABOUT ZERO: -FullRise..+FullRise maps to 0..1, so
			-- a crest gives the biggest skip and a trough the smallest,
			-- and the AVERAGE sits mid-range. Clamping at zero instead
			-- looked reasonable and was not: the field falls half the
			-- time, so half of all hops pinned to the floor scale.
			local rise = (self.waveRise or 0) / SW.WaveHopFullRise
			local strength = math.clamp((rise + 1) * 0.5, 0, 1)
			local scale = SW.WaveHopMinScale + (1 - SW.WaveHopMinScale) * strength
			-- Scaled by `swim` so the shoreline eases in rather than the
			-- kart popping the moment one wheel is wet.
			local peak = SW.WaveHopVelocity * air * 0.25 * k * scale * self.swim
			self.swimHopPeak = peak
			-- Same one-frame flag pattern as the splash.
			self.swimHopLaunched = scale * self.swim
		end
		self.swimHopPhase = phase
	elseif (self.swimHopPhase or 1) < (self.swimHopAir or 0) then
		-- Left the water or slowed down mid-arc. Run the phase out to the
		-- end of the airborne portion rather than dropping the kart,
		-- which would be a corner in exactly the place we removed one.
		self.swimHopPhase = (self.swimHopPhase or 1) + dt / math.max(self.swimHopCycle or 0.4, 1e-3)
	else
		self.swimHopPhase = 1
	end

	--== THE CURVE ====================================================
	-- `para` is the ballistic parabola, `smooth` is sin^2. They have the
	-- same apex and the same duration; they differ only at the ends:
	--
	--   para   slope +4 at launch, -4 at landing   -> two corners
	--   smooth slope  0 at launch,  0 at landing   -> none
	--
	-- The landing squash falls out of the same maths. Its impulse is the
	-- arrival slope, which the blend drives to zero as it smooths — so a
	-- fully smooth hop lands with no thump WITHOUT a second dial to keep
	-- in step.
	do
		local p = self.swimHopPhase or 1
		local a = self.swimHopAir or 0
		if a > 0 and p < a then
			local u = p / a
			local s = math.clamp(SW.WaveHopSmooth, 0, 1)
			local para = 4 * u * (1 - u)
			local smooth = math.sin(math.pi * u) ^ 2
			self.swimHop = (self.swimHopPeak or 0) * (para + (smooth - para) * s)

			-- PITCH FROM THE SLOPE OF THE CURVE, which is the same thing
			-- velocity was before — nose up while climbing, through
			-- neutral at the apex because that is where the slope is
			-- zero, down on the way in.
			local dPara = 4 - 8 * u
			local dSmooth = math.pi * math.sin(2 * math.pi * u)
			local slope = dPara + (dSmooth - dPara) * s
			local slopeMax = 4 + (math.pi - 4) * s
			self.swimHopSlope = slope / math.max(slopeMax, 1e-3)
		else
			self.swimHop = 0
			self.swimHopSlope = 0
		end
	end

	-- THE LANDING, THROUGH THE SQUASH SPRING THAT ALREADY EXISTS.
	-- Impulsed on the frame the arc ends, never assigned — assigning it
	-- is exactly how the kart's own landing bounce ended up snapping.
	--
	-- Its size is the ARRIVAL SLOPE, so `WaveHopSmooth` drives it to zero
	-- as it smooths the curve. A fully smooth hop lands with no thump and
	-- there is no second dial to keep in step.
	if (self.swimHopWasUp == true) and (self.swimHop or 0) <= 0 then
		local arrival = (1 - math.clamp(SW.WaveHopSmooth, 0, 1)) * (self.swimHopPeak or 0)
		local push = arrival * SW.WaveHopLandSquash
		if push > self.squashVel then
			self.squashVel = push
		end
	end
	self.swimHopWasUp = (self.swimHop or 0) > 0

	-- PITCH FROM THE SLOPE OF THE CURVE, so it passes through neutral
	-- exactly at the apex — that is where the slope is zero. NEGATIVE IS
	-- NOSE-UP here, matching the real hop's own air pitch, which is
	-- `-AirPitch * (vertVel / HopSpeed)`.
	local vFrac = math.clamp(self.swimHopSlope or 0, -1, 1)
	local deg = if vFrac >= 0 then vFrac * SW.WaveHopPitchUp else vFrac * SW.WaveHopPitchDown
	self.swimHopPitch = -math.rad(deg)
end

--=====================================================================
--  TRICKS — flip ramps.
--
--  The kart flies an ordinary ballistic arc. Only the ART rotates, and
--  it rotates a WHOLE NUMBER OF TURNS across the expected airtime, so
--  the end pose is the start pose and it cannot land crooked. Same
--  guarantee the props timeline gets, for the same reason.
--=====================================================================
function Simulation:StartTrick(rampCF: CFrame)
	if not TR.Enabled or (self.trickUntil or 0) > os.clock() then
		return false
	end
	if math.abs(self.speed) < TR.MinSpeed then
		return false
	end

	local up = rampCF.UpVector
	self.vertVel = TR.LaunchUp
	-- A kick alone does not clear GroundSnap within a frame. The glide
	-- ramp learned this by re-triggering every other frame.
	self.grounded = false
	self.up = up
	self.forward, self.up = Util.orthonormal(self.forward, self.up)

	-- AIRTIME FROM THE ARC, not a fixed duration. A tall ramp and a low
	-- one need different pacing, and gravity already knows the answer:
	-- up and back down is 2v/g.
	local airtime = 2 * TR.LaunchUp / math.max(self.H.Gravity, 1)
	self.trickStart = os.clock()
	self.trickUntil = self.trickStart + airtime * TR.Window
	self.trickAirtime = airtime * TR.Window

	-- The ramp may name a trick; otherwise pick one. Authored where it
	-- matters, varied where it does not.
	local named = self.trickWanted
	local pick = nil
	if named then
		for _, tr in TR.Tricks do
			if tr.id == named then
				pick = tr
				break
			end
		end
	end
	pick = pick or TR.Tricks[math.random(1, #TR.Tricks)]

	self.trickAxis = if pick.axis == "X"
		then Vector3.xAxis
		elseif pick.axis == "Z" then Vector3.zAxis
		else Vector3.yAxis
	self.trickTurns = pick.turns
	self.trickId = pick.id
	self.trickLanded = false
	-- Cleared per trick, or a bail on one ramp would silently cancel the
	-- boost on the next one.
	self.trickBailed = false
	self.trickDone = false
	return true
end

function Simulation:Step(dt: number, input): { [string]: any }
	local events = {}
	dt = math.min(dt, self.H.MaxTimestep)

	local now = os.clock()
	self:_updateSwim(dt)

	if self.enteredWaterThisFrame then
		events.splashed = 25
	end
	-- Consumed here and cleared, so a skip is heard once however many
	-- sub-steps the frame ran.
	if (self.swimHopLaunched or 0) > 0 then
		events.leaped = self.swimHopLaunched
		self.swimHopLaunched = 0
	end

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
	local throttle = if frozen
		then 0
		else math.clamp(self.seat.ThrottleFloat + input.touchThrottle + (input.driveThrottle or 0), -1, 1)
	local steerIn = if frozen
		then 0
		else math.clamp(self.seat.SteerFloat + input.touchSteer + (input.driveSteer or 0), -1, 1)

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
	local steerRate = if unwinding then self.H.SteerReturn else self.H.SteerSmoothing
	-- A HULL LEANS ON THE RUDDER AND COMES ROUND A MOMENT LATER. This lag
	-- is the single biggest cue that the vehicle has changed — your hands
	-- read it long before any visual does.
	if (self.swim or 0) > 0 then
		steerRate *= 1 - (1 - SW.SteerRateScale) * self.swim
	end
	-- THE RAW INTENT, kept alongside the smoothed value.
	--
	-- `self.steer` is deliberately heavy — it is what the kart turns on,
	-- and a wheel that snaps to full lock feels weightless. But anything
	-- that wants to ANTICIPATE the turn needs the input, not the result:
	-- the motorcycle's lean chases this, because a bike leans BEFORE it
	-- changes direction and chasing the smoothed value made it lean
	-- afterwards.
	self.steerInput = steerIn
	self.steer = Util.approach(self.steer, steerIn, steerRate, dt)

	----------------------------------------------------------------
	-- 1. STATE
	----------------------------------------------------------------
	if self.state == STATE_GRIP then
		if pressed and self.grounded and math.abs(self.speed) > self.H.HopMinSpeed then
			self.vertVel = self.H.HopSpeed
			self.grounded = false
			self.state = STATE_HOP
			self.hopUntil = now + self.H.HopMinAir
		end
	elseif self.state == STATE_HOP then
		if self.grounded and now >= self.hopUntil then
			-- NOTHING TO BREAK TRACTION AGAINST. A hull is already sliding,
			-- so a drift on water should do nothing rather than something
			-- odd.
			local mayDrift = SW.AllowDrift or (self.swim or 0) < 0.5
			if
				mayDrift
				and input.driftHeld
				and math.abs(steerIn) >= self.H.DriftEngageSteer
				and self.speed > self.H.DriftMinSpeed
			then
				self.state = STATE_DRIFT
				self.driftDir = math.sign(steerIn)
				self.driftStart = now
				self.tier = 0
				events.driftStarted = true
			else
				self.state = STATE_GRIP
			end
			-- The landing dip is no longer set here. Section 7 owns it for
			-- every landing there is, and it fires on the frame the wheels
			-- actually touch rather than the frame after — which is also
			-- the only place the descent speed still exists to scale it by.
		end
	elseif self.state == STATE_DRIFT then
		local newTier = tierFor(self.H, now - self.driftStart)
		if newTier ~= self.tier then
			self.tier = newTier
			events.tierChanged = newTier
		end
		if not input.driftHeld or self.speed < self.H.DriftExitSpeed then
			self:_endDrift(events)
		end
	end

	local drifting = self.state == STATE_DRIFT
	local boosting = now < self.boostUntil
	-- PUBLISHED, because Rider lights the thrusters for every kart in the
	-- world and only the driver's own client has a Simulation to ask.
	-- Same route STEER and DRIFT already take.
	if self.model then
		self.model:SetAttribute(Names.BOOSTING, boosting)
		-- The TIER, not just "am I boosting". The thrusters colour
		-- themselves from the same palette the trails and the tank use, and
		-- a boolean cannot say which of the three is burning.
		self.model:SetAttribute(Names.BOOST_TIER, self.burnStage or 0)
	end
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
	-- DEVELOPER SPEED OVERRIDE.
	--
	-- Scaled ONCE here and used for every derived quantity below, because
	-- almost everything in this module is measured as a FRACTION of top
	-- speed — the accel curve, the turn-rate falloff, speedFrac. Scaling
	-- only the target would leave those curves sampling against the old
	-- number, so the kart would go faster while accelerating and turning
	-- as though it had not. Config.Handling says exactly this about
	-- MaxSpeed; the override has to respect it.
	--
	-- Clamped, and absent means 1. A deliberate exception to the
	-- Consistency Rule: it is not derived from art, it is only ever
	-- written by the developer console, and it dies with the kart.
	local maxSpeed = self.H.MaxSpeed
	-- WATER IS THICKER THAN AIR, and that is the entire handling change.
	-- A scalar on a figure that already exists, so retuning the kart
	-- retunes the boat and the two can never drift apart.
	if (self.swim or 0) > 0 then
		maxSpeed *= 1 - (1 - SW.SpeedScale) * self.swim
	end
	do
		local scale = self.model and self.model:GetAttribute(Names.DEV_SPEED_SCALE)
		if type(scale) == "number" and scale == scale then
			maxSpeed = self.H.MaxSpeed * math.clamp(scale, 0.1, 5)
		end
	end

	local speedNow = math.abs(self.speed)
	local powerBand = Util.sampleCurve(self.H.AccelCurve, speedNow / maxSpeed)

	local target, rate
	local burnTarget = if stage then maxSpeed + stage.Speed else 0

	if boosting and self.boostSpeed >= burnTarget then
		-- A pad stronger than the burn wins; otherwise the burn does.
		target, rate = self.boostSpeed, self.H.BoostAccel
	elseif stage then
		target, rate = burnTarget, N.BurnAccel
	elseif throttle > 0.05 then
		target, rate = maxSpeed, self.H.Accel * powerBand
	elseif throttle < -0.05 then
		if self.speed > 1 then
			target, rate = 0, self.H.BrakeRate
		else
			target, rate = -self.H.ReverseSpeed, self.H.Accel * powerBand
		end
	else
		target, rate = 0, self.H.CoastRate
	end
	self.speed = Util.approach(self.speed, target, rate, dt)

	if drifting then
		-- Scrub then recover across the life of the drift, so a long
		-- drift costs speed before it pays it back.
		--
		-- ^dt, AND THAT IS NOT A DETAIL. These are retention rates PER
		-- SECOND; raising them to dt is what turns a rate into this
		-- frame's share of it.
		--
		-- Applied straight, as a per-FRAME multiplier, this compounded
		-- with the frame rate — the one thing this whole module exists to
		-- prevent. 0.995 * 0.980 looks like a 2% trim and is 0.9751^60 =
		-- **22% of your speed per second** at 60fps. Measured, a drift
		-- fell to 68% of top speed at 60fps, 79% at 30, and 49% at 144:
		-- a drift on a 144Hz monitor cost you half your speed, and the
		-- fast line was the slow line on better hardware.
		--
		-- The symptom was "it goes slow really quick then goes fast",
		-- which is this curve's dip and recovery with a 20x magnifier on
		-- it, not the shape being wrong.
		local driftAge = (now - self.driftStart) / self.H.DriftScrubWindow
		local retain = self.H.DriftSpeedKeep * Util.sampleCurve(self.H.DriftScrubCurve, driftAge)
		self.speed *= retain ^ dt
	end

	----------------------------------------------------------------
	-- 3. HEADING  — where the kart actually GOES.
	----------------------------------------------------------------
	local speedAbs = math.abs(self.speed)
	local authority = math.clamp(speedAbs / self.H.TurnRampSpeed, 0, 1)

	-- BRIEFLY A PASSENGER after a square impact. This is what makes a
	-- bounce read as being HIT rather than as the kart deciding to go the
	-- other way. Short by design — see BounceLockout.
	if now < (self.bounceUntil or 0) then
		authority *= self.H.BounceLockSteer
	end

	-- Ramp the blend linearly, then smoothstep it. Smoothstep has zero
	-- slope at 0 and 1, so the kart eases in and out of the drift
	-- instead of stepping into it.
	local blendTarget = if drifting then 1 else 0
	local blendStep = dt / (if drifting then self.H.DriftEnterTime else self.H.DriftExitTime)
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
	local ratio = math.clamp(speedAbs / maxSpeed, 0, 1)
	local turn = self.H.TurnRate + (self.H.TurnRateTop - self.H.TurnRate) * ratio
	-- Boats come round wide. Same scalar shape as everything else here.
	if (self.swim or 0) > 0 then
		turn *= 1 - (1 - SW.TurnScale) * self.swim
	end
	local reversing = if self.speed < 0 then -1 else 1
	local steerTurn = -self.steer * turn * reversing

	-- Drift rotation. Tighter than steering can manage — that's the reward.
	local trim = math.clamp(steerIn * activeDir, -1, 1)
	local driftTurn = -activeDir * (self.H.DriftTurnBase + trim * self.H.DriftTurnTrim)

	-- Crossfade rather than switch, then spin `forward` about the
	-- current `up`. On a loop `up` is the track normal, so steering
	-- stays correct sideways and upside-down without special cases.
	local yawDelta = (steerTurn * (1 - eased) + driftTurn * eased) * authority * dt

	-- IN THE AIR THE WHEELS ARE NOT DOING ANYTHING, so ground steering is
	-- replaced outright rather than scaled. Wings turn a quarter as fast
	-- as tyres — see the drift table in Config.Glide for why it cannot be
	-- much more than that.
	if self.state == STATE_GLIDE then
		yawDelta = -self.steer * GL.TurnRate * dt
		-- Added ON TOP of the player's input, never instead of it: you can
		-- fight the corridor, you just cannot out-fly it forever. A
		-- correction that seizes the controls is the thing that reads as
		-- an invisible wall.
		yawDelta += corridorPush(self, dt)
	end

	-- A REAL SPIN TURNS THE KART, NOT THE PICTURE OF IT.
	--
	-- The item spinout rotates `driftAngle`, which is cosmetic — so when
	-- it ends the kart snaps back to the heading it never actually left.
	-- Fine for a shell, where being flung back onto your original line is
	-- the mercy. Wrong for a wall, where you should end up facing wherever
	-- the impact left you, and where the snap-back was the thing that
	-- looked broken.
	--
	-- Driven off the same eased curve the visual uses, applied as the
	-- DIFFERENCE since last frame, so the total lands exactly on the
	-- revolution count however the framerate wobbles.
	if self.spinReal and now < (self.spinUntil or 0) then
		local span = math.max(self.spinUntil - self.spinFrom, 1e-3)
		local t = math.clamp((now - self.spinFrom) / span, 0, 1)
		local swept = (1 - (1 - t) ^ FX.SpinEase) * (self.spinRevs or FX.SpinRevolutions) * math.pi * 2
		yawDelta += (swept - (self.spinApplied or 0)) * self.spinDir
		self.spinApplied = swept
	end

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
	-- GRIP IS CHASED, NOT SWITCHED.
	--
	-- Taken from the STATE, not from the drift blend, and then approached.
	-- Both halves matter:
	--
	--   Reading the state means landing a hop into a drift goes 1.5 -> 2.9
	--   and only ever rises. Reading the blend instead would aim at the
	--   full 9 for the first frames of the drift — because `eased` is
	--   still near zero there — and the kart would hook up hard at the
	--   exact moment it is supposed to be letting go.
	--
	--   Approaching it means nothing steps. A hop used to drop the kart
	--   from 9 to nothing and back inside a fifth of a second, and a drift
	--   release used to snap 2.9 -> 9 in one frame while the body was
	--   still visibly sideways, unwinding over the next 0.45s with no grip
	--   left to explain it.
	--
	-- The unwind out of a drift follows the same eased blend that drives
	-- the body angle and the turn rate, so all three arrive together.
	local gripTarget
	if self.state == STATE_HOP then
		gripTarget = self.H.HopGrip
	elseif drifting then
		gripTarget = self.H.DriftGrip
	else
		gripTarget = self.H.Grip + (self.H.DriftGrip - self.H.Grip) * eased
	end
	self.gripNow = Util.approach(self.gripNow, gripTarget, self.H.GripBlendRate, dt)

	local gripRate = self.gripNow
	self.travel = self.travel:Lerp(self.forward, math.min(gripRate * dt, 1))
	self.travel = (Util.orthonormal(self.travel, self.up))

	-- Hard-cap the slip so momentum can never carry the kart sideways
	-- or backwards, however hard you saw at the wheel.
	local maxSlip = math.rad(self.H.MaxSlip)
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
	local speedFrac = math.clamp(math.abs(self.speed) / maxSpeed, 0, 1)

	if self.state == STATE_DRIFT then
		-- A committed drift is never quiet. The rear is loose regardless of
		-- where the nose happens to be pointing.
		effort = math.max(effort, self.H.TyreDriftLoad)

		-- Actively fighting it is the loudest thing you can do. Scaled by
		-- how much lock is being used, so a nudge of correction is quieter
		-- than a full stab.
		if self.driftDir ~= 0 and math.sign(self.steer) == -self.driftDir then
			effort = math.max(effort, self.H.TyreCounterLoad * math.abs(self.steer))
		end
	end

	-- Hard cornering at speed loads the tyres even when fully gripped —
	-- that's the difference between a quiet turn and a loaded one.
	effort = math.max(effort, math.abs(self.steer) * speedFrac * self.H.TyreCornerLoad)

	self.tyreLoad = math.clamp(effort, 0, 1)

	----------------------------------------------------------------
	-- 5. INTEGRATE
	----------------------------------------------------------------
	-- `travel` is already perpendicular to `up`, so it follows the
	-- surface for free — no projection needed.
	local velocity = self.travel * self.speed

	-- Gravity pulls along -up, which on a loop means INTO the track.
	--
	-- GLIDING SUBSTITUTES ITS OWN, and then steers the sink rate with the
	-- throttle rather than letting it free-fall: a glider's one real skill
	-- is trading height for speed, so the pitch input has to beat gravity
	-- rather than merely lean on it.
	if self.state == STATE_GLIDE then
		local pitch = math.clamp(throttle, -1, 1)
		-- Published for Rider, which animates the flap for EVERY kart and
		-- has no Simulation of its own to ask.
		if self.model then
			self.model:SetAttribute(Names.GLIDE_PITCH, pitch)
		end
		-- Forward dives, back floats. Two half-ranges around neutral so
		-- hands-off is a defined sink rather than the midpoint of two
		-- numbers that happen to bracket it.
		local sink = if pitch >= 0
			then GL.SinkNeutral + (GL.SinkDive - GL.SinkNeutral) * pitch
			else GL.SinkNeutral + (GL.SinkNeutral - GL.SinkFloat) * pitch

		-- THE FLARE, MEASURED OFF THE GROUND.
		--
		-- One ray straight down. Inside FlareHeight the descent eases to
		-- FlareSink, so the kart levels out and settles instead of driving
		-- into the floor at whatever rate it happened to be falling.
		--
		-- Off the GROUND rather than off a landing marker, deliberately:
		-- it then works over any surface, with or without a pad, and it
		-- cannot be aimed at the wrong thing. It is also the one piece of
		-- the old forced approach that was actually about feel rather than
		-- about hitting a target.
		local look = workspace:Raycast(self.pos, -self.up * (GL.FlareHeight + 4), self.rayParams)
		if look then
			local f = math.clamp(look.Distance / GL.FlareHeight, 0, 1)
			local flared = GL.FlareSink + (sink - GL.FlareSink) * f
			sink = sink + (flared - sink) * math.min(GL.FlareRate * dt, 1)
		end

		-- GRAVITY STILL DOES THE ARC; the wings only set a FLOOR on how
		-- fast you may fall.
		--
		-- Chasing vertVel straight to -sink was wrong and measurably so:
		-- it erased the launch kick within about half a second, so the
		-- kart barely rose at all and a "glide" was a 0.5s hop. Letting
		-- reduced gravity decelerate the launch gives the rise, the arc
		-- over the top, and then the long steady descent — which is the
		-- shape of an actual glide.
		self.vertVel -= GL.Gravity * dt
		if self.vertVel < -sink then
			self.vertVel = -sink
		end

		-- No active pull is needed any more. `sink` is a CAP on descent,
		-- and the flare LOWERS it — which the clamp above applies on the
		-- very next frame. Slowing down is free; it was only speeding up
		-- that ever needed help, and nothing asks for that now.

		-- The trade. Sinking faster than neutral buys speed; floating
		-- costs it. That exchange IS the glider minigame.
		local extraSink = sink - GL.SinkNeutral
		self.speed = math.min(self.speed + extraSink * GL.DiveToSpeed * dt, GL.DiveSpeedCap)
		self.speed *= GL.SpeedKeep ^ dt
		-- The floor. Floating is a trade, never a way to arrive stopped.
		self.speed = math.max(self.speed, GL.MinFlightSpeed)
	else
		self.vertVel -= self.H.Gravity * dt
	end
	velocity += self.up * self.vertVel

	----------------------------------------------------------------
	-- 6. COLLISION  — swept, and resolved by us. Deterministic.
	----------------------------------------------------------------
	-- Lift the bottom of the sweep box clear of anything shorter than
	-- StepHeight, so kerbs, ramp lips and the sharp apex of a wedge
	-- don't register as walls. The ground probe below climbs them.
	local size = self.hitbox.Size
	local floor = size.Y * 0.5 - self.H.RideHeight -- box bottom rel. to origin
	local lift = math.max(self.H.StepHeight + floor, 0)
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

	-- Push out of anything we're already INSIDE. A Blockcast that begins
	-- inside geometry returns nothing, so a single frame of penetration
	-- would otherwise let the kart move through walls freely from then
	-- on. Drifting into a wall is the usual way in.
	--
	-- BOUNDS SAY "MAYBE". GEOMETRY HAS TO SAY "YES".
	--
	-- GetPartBoundsInBox is BROAD-phase: it returns anything whose
	-- BOUNDING BOX overlaps, which is not the same as touching. Treating
	-- that answer as final was survivable only while every road was a
	-- small part — the part under the kart had its centre directly
	-- below, so `away` came out near-parallel to `up`, flattened to
	-- nothing, and no push happened. That was luck, not design, and two
	-- kinds of authored geometry break it:
	--
	--   A ONE-PIECE MESHED ROAD. A track exported whole from Blender is
	--   one MeshPart whose bounding box spans the entire circuit, so it
	--   overlaps every frame wherever the kart is. Pushing away from its
	--   `Position` — the centre of that box, a point in mid-air inside
	--   the layout — shoved the kart outward at Depenetrate (55 studs/s)
	--   for as long as it was on the road. "It literally slides off."
	--
	--   AN ARCH, A TUNNEL, A GATEWAY. Anything you drive THROUGH has a
	--   bounding box covering its opening, so the kart is "overlapping"
	--   the whole time it is passing under, while touching nothing at
	--   all. Any push here is a shove out of thin air.
	--
	-- Neither has anything to do with normals, CollisionFidelity or the
	-- mesh itself. Both are this block believing a bounds test.
	--
	-- So the bounds query is now only a FILTER, and the real question is
	-- asked of the geometry: how far is the nearest actual surface? Past
	-- our own radius and we are inside nothing — an arch's opening, or
	-- the vast empty middle of a track's bounding box — and there is
	-- nothing to push out of.
	-- INSIDE, OR NOT AT ALL.
	--
	-- Being NEAR a surface is not being stuck in one. An earlier version
	-- pushed whenever the nearest surface was within the kart's own hull
	-- radius, which sounds conservative and is not: a decomposed road is
	-- a chain of hulls, so on any bend there is a hull seam a couple of
	-- studs to the side of the kart, and its nearest face is a lateral
	-- one. That fired the 55 studs/s push sideways while driving along
	-- perfectly good road.
	--
	-- The only state this block exists to escape is the kart's own
	-- centre ending up INSIDE geometry, where a Blockcast starts
	-- overlapping and returns nothing, and the kart would otherwise pass
	-- through walls forever. Roblox returns the input point unchanged
	-- from GetClosestPointOnSurface in exactly that case, which makes it
	-- a precise test rather than a distance guess.
	local overlaps = workspace:GetPartBoundsInBox(sweepFrame(), castSize, self.overlapParams)
	for _, part in overlaps do
		local surface = part:GetClosestPointOnSurface(self.pos)
		local inside = (surface - self.pos).Magnitude < 1e-3

		if inside then
			-- No surface point to push from, so the centre is the best
			-- available guess at "which way is out".
			local away = self.pos - part.Position
			away -= self.up * away:Dot(self.up) -- stay in the surface plane
			if away.Magnitude > 1e-3 then
				self.pos += away.Unit * self.H.Depenetrate * dt
			end
		end
	end

	-- Swept slide. Each pass re-casts from the new position, so sliding
	-- along one wall can't shove us through the next.
	local remaining = velocity * dt
	for _ = 1, self.H.CollisionPasses do
		local travel = remaining.Magnitude
		if travel < 1e-4 then
			break
		end

		local hit = workspace:Blockcast(sweepFrame(), castSize, remaining, self.rayParams)
		-- "Wall" is measured against OUR up, so a loop's vertical
		-- section is drivable road rather than an obstacle.
		if not hit or hit.Normal:Dot(self.up) >= self.H.MaxSlopeDot then
			self.pos += remaining
			break
		end

		local dir = remaining.Unit
		local reached = math.clamp(hit.Distance, 0, travel)
		self.pos += dir * math.max(reached - self.H.SkinWidth, 0)

		-- HOW SQUARE WAS THE HIT? 1 is dead-on, 0 is a graze.
		local square = math.abs(dir:Dot(hit.Normal))

		if square >= self.H.BounceMinDot and math.abs(self.speed) >= self.H.BounceMinSpeed then
			-- RECOIL, NOT REFLECT. The kart backs off the wall while
			-- still FACING it, the way a car actually rebounds.
			--
			-- The first version reflected `travel` about the surface
			-- normal and turned the nose to match. That is a mirror, not
			-- a bounce: hit a wall head-on and the kart spun a full 180
			-- and drove away, which is nothing like being stopped by it.
			--
			-- Reflecting travel WITHOUT the nose does not work either,
			-- and the reason is MaxSlip: travel may only lag forward by
			-- 38 degrees, so a travel vector pointing backwards is
			-- clamped straight back into the wall on the same frame.
			--
			-- So neither direction moves. `speed` goes NEGATIVE, and the
			-- kart moves backwards along the direction it is already
			-- pointing — away from the wall — with forward and travel
			-- still aligned, so the clamp has nothing to argue with.
			--
			-- Recovery is free: holding the throttle lerps speed back up
			-- through zero and you drive off again. Steering inverts
			-- while reversing, which is correct and makes the recoil feel
			-- like a car rather than a slider.
			-- Harder the faster you were going, and never softer than
			-- BounceMinPush — so a slow nudge still separates the kart
			-- from the wall rather than leaving it resting against it.
			local hitSpeed = math.abs(self.speed)
			local frac = math.clamp(hitSpeed / maxSpeed, 0, 1)
			local keep = self.H.BounceKeepSlow + (self.H.BounceKeepFast - self.H.BounceKeepSlow) * frac
			self.speed = -math.max(hitSpeed * keep, self.H.BounceMinPush)

			-- Pushed clear along the surface normal as well. Without it
			-- the kart can rest a hair inside the wall, re-trigger next
			-- frame, and buzz against it.
			self.pos += hit.Normal * self.H.SkinWidth

			self.bounceUntil = now + self.H.BounceLockout
			events.bounced = square

			-- A HARD, SQUARE HIT TAKES THE KART OFF YOU.
			--
			-- Below WallStunSpeed a wall is the recoil above and nothing
			-- more, which is right for clipping a barrier mid-race. Above
			-- it, the mistake costs control rather than just speed — the
			-- Mario Kart rule, and what stops walls being a free way to
			-- scrub speed into a corner.
			--
			-- Goes through Spinout, so it respects a shield exactly like
			-- every other hit in the game. A player holding one should not
			-- discover that walls are the exception.
			if hitSpeed >= self.H.WallStunSpeed then
				-- Scaled between the threshold and top speed, so a hit that
				-- barely qualifies slews you and a flat-out one turns you
				-- most of the way round.
				local over = math.clamp(
					(hitSpeed - self.H.WallStunSpeed) / math.max(maxSpeed - self.H.WallStunSpeed, 1),
					0,
					1
				)
				local revs = self.H.WallStunRevsMin + (self.H.WallStunRevsMax - self.H.WallStunRevsMin) * over
				if self:Spinout(self.H.WallStunTime, self.H.WallStunKeep, self.H.WallStunFreeze, revs, true) then
					events.wallStunned = hitSpeed
				end
			end

			-- Nothing left to slide with: this frame's movement was spent
			-- on the impact.
			break
		end

		-- GRAZE: the original slide. Wall-riding a corner has to stay
		-- smooth, so anything short of a square hit keeps the old
		-- behaviour exactly.
		self.speed *= 1 - self.H.WallScrub * square

		-- What's left, flattened onto the wall. Re-cast next pass.
		local leftover = remaining - dir * reached
		remaining = leftover - hit.Normal * leftover:Dot(hit.Normal)
	end

	----------------------------------------------------------------
	-- 7. GROUND
	----------------------------------------------------------------
	-- Five rays cast along -up, not world-down, so this works on a loop.
	local probeRight = self.forward:Cross(self.up)
	local reach = self.H.ProbeUp + self.H.RideHeight + self.H.GroundSnap
	local castDir = -self.up * reach
	local probeLift = self.up * self.H.ProbeUp

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
		self.forward * self.H.ProbeSpread,
		-self.forward * self.H.ProbeSpread,
		probeRight * self.H.ProbeSpread,
		-probeRight * self.H.ProbeSpread,
	}

	local centreAlong, centreNormal = nil, nil
	local outer = {}
	local normalSum, hits = Vector3.zero, 0

	for i, offset in offsets do
		local probe = workspace:Raycast(self.pos + offset + probeLift, castDir, self.rayParams)
		local accepted = probe and probe.Normal:Dot(self.up) > self.H.MaxSlopeDot

		-- See Config.Handling.GroundDebug. Centre probe only — it is
		-- authoritative, and one line per failure is plenty.
		if i == 1 and self.H.GroundDebug and not accepted then
			-- Reuses Step's own `now` rather than a second os.clock() call
			-- a few lines from the first one.
			if now - (self.lastGroundLog or 0) > 0.5 then
				self.lastGroundLog = now
				if not probe then
					warn(
						"[Ground] centre probe: NO HIT under the kart. The surface either has "
							.. "CanQuery off, carries a CollectionService tag WorldFilter excludes "
							.. "(a trigger tag with no TrackSurface), or simply isn't there."
					)
				else
					warn(
						("[Ground] centre probe hit %s but REJECTED — normal . up = %.2f, needs > %.2f. "):format(
							probe.Instance:GetFullName(),
							probe.Normal:Dot(self.up),
							self.H.MaxSlopeDot
						) .. "Likely an imported mesh with inverted/backward triangle normals."
					)
				end
			end
		end

		if accepted then
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
			-- ONLY CLIMB WHAT WE ARE DRIVING INTO.
			--
			-- A step ahead is a step: the front probe sees the riser
			-- before the kart reaches it, which is how stairs and ramp
			-- lips get climbed. A probe to the SIDE reading higher is
			-- not something we are climbing — it is a kerb we are
			-- passing, or a lump in the collision geometry.
			--
			-- That distinction never mattered on parts, where the ground
			-- under all five probes was the same flat slab. It matters a
			-- great deal on a meshed road: convex decomposition bulges
			-- above the real surface at pinch points and forks, and a
			-- single bulging hull under one side probe used to yank the
			-- whole kart up onto it for a frame, then drop it again.
			--
			-- Measured against `travel`, not `forward`, so this still
			-- works in reverse and mid-drift, when the nose and the
			-- direction of movement disagree.
			local ahead = o.offset:Dot(self.travel) > 0

			if ahead and step > self.H.StepTolerance and o.along > highest and step <= self.H.StepHeight then
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
		if self.H.StairSmoothing and hits > 1 and normalSum.Magnitude > 1e-3 then
			surfaceNormal = normalSum.Unit
		end

		-- `highest` is negative when the ground is below us. Attach if
		-- we're within snapping range and not still rising off a hop.
		-- Climbing is allowed to be generous; falling isn't. One value for
		-- both meant a ramp taken at boost speed outran the snap and the
		-- kart ended up inside it.
		local gap = -highest - self.H.RideHeight
		local allowed = if gap < 0 then self.H.GroundSnapUp else self.H.GroundSnap

		-- A HOP IS NOT A DIP IN THE ROAD.
		--
		-- The snap refuses to act while the kart is rising, so with a
		-- 1.08-stud apex sitting well inside a 3.0-stud GroundSnap the
		-- very first frame vertVel crossed zero — the apex itself — the
		-- ground reclaimed the kart and put it back down in one step. The
		-- hop had a rise and no fall at all.
		--
		-- GroundSnap exists to follow the road across dips, seams and
		-- kerbs. A jump the player deliberately asked for is not one of
		-- those, so while the hop is live only a genuine touchdown counts
		-- and the arc gets to finish.
		if self.state == STATE_HOP then
			allowed = math.min(allowed, self.H.HopSnap)
		end

		if self.vertVel <= 0 and gap <= allowed then
			-- EASE SMALL CORRECTIONS, SNAP BIG ONES.
			--
			-- Flat parts report the same height every frame, so snapping
			-- straight to it is invisible. A curved MeshPart does not: its
			-- collision geometry is a chain of convex facets, so
			-- consecutive frames land on different facets and read heights
			-- a few tenths apart. Snapping to that is a jolt per facet
			-- boundary — the "bendy surfaces are buggy" symptom.
			--
			-- Only the small stuff is eased. Landing and genuine steps
			-- stay immediate, and so does anything while airborne, or the
			-- kart would sink through the road on touchdown.
			-- UP IS EASED. DOWN IS NEVER EASED.
			--
			-- Easing both ways was wrong and made downhills worse than
			-- doing nothing. On any descent the ground drops away a
			-- little every frame, so the correction is permanently
			-- NEGATIVE — easing it leaves the kart hovering, the gap
			-- grows until it exceeds GroundSmooth, then it snaps. Hover,
			-- snap, hover, snap. At 95 studs/s even a 5° slope drops
			-- 0.14 studs a frame, comfortably inside the easing window,
			-- so every downhill in the game oscillated.
			--
			-- Only spurious LIFT needs filtering: a facet edge or a hull
			-- seam that reads high for a frame. Following the road
			-- downward is not noise, it is the road, and gravity should
			-- never be argued with.
			local correction = highest + self.H.RideHeight
			if self.wasGrounded and correction > 0 and correction <= self.H.GroundSmooth then
				correction *= math.min(self.H.GroundSmoothRate * dt, 1)
			end

			-- How hard we actually arrived. Read before the line below
			-- throws it away — this is the only frame it exists on, and
			-- it is the difference between a drift hop and a fall off a
			-- bridge producing the same cosmetic dip.
			local impact = math.max(-self.vertVel, 0)

			-- THE VISUAL DOES NOT FOLLOW THE CORRECTION.
			--
			-- `correction` un-buries the kart from however far it sank
			-- into the ground between frames, and applying it moves the
			-- kart. `squash` is subtracted from the drawn position, so
			-- adding the correction there cancels the jump: the true
			-- position is right immediately, the drawn one does not move,
			-- and the spring resolves the difference over a few frames.
			--
			-- Only on a real landing — mid-drive the ground probe is
			-- correcting by fractions every frame and feeding those into
			-- the suspension would make the kart hum along the road.
			if not self.wasGrounded and correction > 0 then
				self.catch = (self.catch or 0) + correction * FX.LandCatchCorrection
			end

			self.pos += self.up * correction
			self.vertVel = 0
			self.grounded = true
			self.normal = surfaceNormal

			-- BOUNCE, EARNED BY THE DROP.
			--
			-- Landing perfectly flat reads as the kart being absorbed by
			-- the floor. Above LandBounceMinDrop it comes back up, scaled
			-- by how hard it arrived — so a drift hop is still dead flat
			-- and a fall off a bridge kicks.
			--
			-- The threshold is set so the smallest possible bounce already
			-- clears GroundSnap, because a bounce under about 30 studs/s
			-- is not a small bounce — the ground probe re-catches it and
			-- it is no bounce at all. Same trap the wave launches fell
			-- into.
			--
			-- Each bounce is a fresh landing next time round, so they
			-- decay on their own: 34% of a smaller impact is smaller
			-- still, and it drops under the threshold within two or three.
			-- ABSORBED NOW, RELEASED IN A MOMENT. See LandBounceDelay:
			-- reversing the velocity on the contact frame is a direction
			-- change, not a bounce. The kart squats here and leaves below.
			if not self.wasGrounded and impact >= self.H.LandBounceMinDrop then
				-- Floored, because a gentle landing cannot produce enough
				-- speed to escape GroundSnap on its own and would otherwise
				-- be eaten by the probe. Safe to floor only because the
				-- floor sits BELOW the threshold — see the config note.
				self.bouncePending = math.min(
					math.max(impact * self.H.LandBounceKeep, self.H.LandBounceMin),
					self.H.LandBounceMax
				)
				self.bounceAt = now + self.H.LandBounceDelay
				events.bouncedLanding = impact
			end

			-- Touchdown. Compresses the suspension by an amount the drop
			-- earned; the spring in section 8 rings it back out.
			--
			-- `max` rather than assignment so a second, softer landing a
			-- frame later can never cut a big compression short.
			if not self.wasGrounded then
				local hardness = math.clamp(impact / FX.LandSquashSpeed, 0, 1)
				local dip = FX.LandSquash + (FX.LandSquashMax - FX.LandSquash) * hardness
				-- A PUSH, NOT A PLACEMENT. `squash` moves the kart's visual
				-- position, so assigning it teleported the kart downward on
				-- the contact frame. Handing the spring a velocity lets it
				-- compress over about five frames instead — which is the
				-- suspension doing the job it was already modelled for.
				local push = dip * math.sqrt(FX.SquashSpring) * FX.LandSquashImpulse
				if push > self.squashVel then
					self.squashVel = push
				end
			end
		end
	end

	-- THE REBOUND. Fired a beat after touchdown, and only if we are still
	-- on the ground — driving off a ledge inside the window should not
	-- launch the kart out of thin air.
	if self.bouncePending and now >= (self.bounceAt or 0) then
		if self.grounded then
			self.vertVel = self.bouncePending
			self.grounded = false
		end
		self.bouncePending = nil
	end

	----------------------------------------------------------------
	-- 6b. SURFACE GRAVITY — rotate our idea of "down" onto the track.
	----------------------------------------------------------------
	--================================================================
	--  GLIDE: STARTING AND ENDING
	--
	--  Detection is an explicit INCLUDE query against ramp parts, not a
	--  sweep result. Ramps are in Triggers.TAGS so the movement sweep
	--  cannot see them at all — which is what stops a ramp being a wall —
	--  and that means the only way to know we crossed one is to ask.
	--================================================================
	--================================================================
	--  TRICKS. Detected the same way glide ramps are — an explicit
	--  include query, because ramps are in Triggers.TAGS and the
	--  movement sweep cannot see them at all.
	--================================================================
	if TR.Enabled then
		local spinning = (self.trickUntil or 0) > now
		if spinning then
			-- A WHOLE NUMBER OF TURNS ACROSS THE WINDOW, eased. At t=1 the
			-- angle is turns*2pi, which is the pose it started in — so it
			-- cannot finish crooked however it is interrupted.
			local t = math.clamp((now - self.trickStart) / math.max(self.trickAirtime, 1e-3), 0, 1)
			-- AN S-CURVE, BIASED LATE — NOT A POWER CURVE.
			--
			-- It was `t ^ Ease`, which put peak angular velocity AT t=1:
			-- 3.2 revs/sec on a single flip, 6.5 on a double, and then
			-- zero on the very next frame. The flip was spinning fastest
			-- at the exact instant it stopped dead, and that hard stop is
			-- why it never felt satisfying however the numbers moved. The
			-- same velocity discontinuity the water hop had, one layer up.
			--
			-- `smoothstep(t^bias)` keeps the late bias — peak speed lands
			-- around t=0.69, so it still winds up into the landing — but
			-- its derivative goes to ZERO at both ends. The kart eases out
			-- of the ramp, whips through the middle, and SETTLES into the
			-- final pose instead of being switched off in it.
			--
			-- At t=1 it is still exactly 1, so the whole-number-of-turns
			-- guarantee is untouched: it cannot land crooked.
			local s = t ^ TR.Ease
			local swept = s * s * (3 - 2 * s)
			self.trickAngle = self.trickTurns * math.pi * 2 * swept

			-- BAILED OUT. Wheels down while still rotating is the case
			-- RequireLanding is actually about, and it has to be caught
			-- HERE, while it is happening — by the time the window closes
			-- the kart is grounded either way and the two are
			-- indistinguishable.
			if self.grounded and (now - (self.trickStart or 0)) > TR.MinAirTime then
				self.trickBailed = true
			end
		else
			if (self.trickAngle or 0) ~= 0 then
				-- Finished. Snapped to exactly zero rather than left at a
				-- rounding error, since the point is that it ends level.
				self.trickAngle = 0
				self.trickAxis = nil
				self.trickDone = true
			end

			-- THE REWARD FIRES ON TOUCHDOWN, NOT ON THE FRAME THE
			-- ROTATION ENDS — and that distinction was a real bug.
			--
			-- `Window` is 0.82 deliberately, so the flip finishes BEFORE
			-- the wheels arrive: 0.678s of rotation against 0.827s of
			-- airtime, nine frames early. This used to test `grounded` in
			-- the single frame the rotation ended, when the kart is by
			-- construction still in the air — so the test failed, the
			-- angle was zeroed, and the branch never ran again.
			--
			-- The boost was therefore lost on every clean jump and paid
			-- out only when the actual airtime came in UNDER 0.678s —
			-- i.e. exactly when you landed early, which is the one case
			-- it was written to refuse. Precisely backwards.
			--
			-- Held as a pending flag and spent on the next grounded frame
			-- instead. Bailing out mid-rotation is caught above, where it
			-- can still be told apart from a clean landing.
			if self.trickDone and self.trickLanded == false and (not TR.RequireLanding or self.grounded) then
				self.trickDone = false
				self.trickLanded = true
				if not self.trickBailed then
					self:ApplyBoost(TR.BoostSpeed, TR.BoostTime)
					events.boostFired = TR.BoostTier
					events.trickLanded = self.trickId
				end
				self.trickBailed = false
			end
		end

		if not spinning and self.grounded and (now - (self.trickStart or -99)) > TR.MinAirTime then
			local ramps = CollectionService:GetTagged(TR.RampTag)
			if #ramps > 0 then
				local params = OverlapParams.new()
				params.FilterType = Enum.RaycastFilterType.Include
				params.FilterDescendantsInstances = ramps
				local touching =
					workspace:GetPartBoundsInBox(CFrame.new(self.pos, self.pos + self.forward), self.hitbox.Size, params)
				local ramp = touching[1]
				if ramp then
					-- A ramp may name the trick it throws.
					local named = ramp:GetAttribute("Trick")
					self.trickWanted = if type(named) == "string" then named else nil
					if self:StartTrick(ramp.CFrame) then
						events.trickStarted = self.trickId
					end
				end
			end
		end
	end

	if GL.Enabled then
		if self.state == STATE_GLIDE then
			-- Touching down ends it, whatever the corridor thought. The
			-- ground is the authority here: a landing zone is where we
			-- AIMED, not a promise about where the road actually is.
			-- THE WHEELS DECIDE WHEN THE GLIDE IS OVER, not the pad.
			--
			-- Reaching the pad used to end it, which meant a kart that
			-- arrived above a lower landing area dropped the rest of the
			-- way under FULL gravity with its wings already gone. Landing
			-- and falling are the same thing here: keep gliding, keep the
			-- wings out, and touch down on whatever is actually there.
			--
			-- The marker says where to AIM. It was never the floor, and it
			-- is not the finish line either — GlideLand is in Triggers.TAGS
			-- and invisible to the ground probe by design.
			local timedOut = os.clock() > (self.glideUntil or 0)
			-- Landing is only believed after the minimum air time. See
			-- MinAirTime: the first frames off a ramp still read as
			-- grounded, and trusting them relaunches on the spot.
			local canLand = os.clock() >= (self.glideMinUntil or 0)
			if (self.grounded and canLand) or timedOut then
				if timedOut and not self.grounded then
					warn("[Simulation] glide timed out in mid-air — a GlideRamp is aimed at nothing.")
				end
				self:EndGlide()
				events.glideEnded = true
			end
		elseif self.grounded then
			local ramps = CollectionService:GetTagged(GL.RampTag)
			if #ramps > 0 then
				local params = OverlapParams.new()
				params.FilterType = Enum.RaycastFilterType.Include
				params.FilterDescendantsInstances = ramps
				local touching = workspace:GetPartBoundsInBox(
					CFrame.new(self.pos, self.pos + self.forward) ,
					self.hitbox.Size,
					params
				)
				local ramp = touching[1]
				if ramp and self:StartGlide(ramp.CFrame) then
					events.glideStarted = true
					-- Reported as a boost so Audio and Effects react without
					-- either of them needing to know gliding exists.
					events.boostFired = GL.LaunchBoostTier
				end
			end
		end
	end

	if self.grounded then
		self.airTime = 0
		-- Chase the surface briskly; a slow chase sheds the kart on a
		-- tight loop because gravity keeps pointing at the old normal.
		self.up = self.up:Lerp(self.normal, math.min(self.H.SurfaceAlignRate * dt, 1))
	else
		self.airTime += dt
		if self.airTime >= self.H.StickTime then
			-- Genuinely airborne — but airborne over WHAT?
			--
			-- This used to settle straight back to world-up so you land
			-- level off a ramp. On an inverted section that is exactly
			-- wrong: your up points downward in world terms, so blending to
			-- world-up rotates gravity 180 degrees and drops you off the
			-- ceiling. Hopping repeatedly kept re-entering this branch and
			-- accumulated the error until the kart let go.
			--
			-- So look before settling. Track still under us along our own
			-- down means we're hopping ON a surface, however that surface
			-- is oriented, and its normal stays our up. Only genuine open
			-- air falls back to world-up, which is the case the original
			-- rule was actually written for.
			local probe = workspace:Raycast(self.pos, -self.up * self.H.AirSurfaceProbe, self.rayParams)
			local settleTo = if probe then probe.Normal else Vector3.yAxis
			self.up = self.up:Lerp(settleTo, math.min(self.H.AirAlignRate * dt, 1))
		end
		-- Below StickTime we keep the old up untouched: that grace
		-- period carries the kart across seams, stair nosings and panel
		-- gaps without gravity flipping back to world-down for a frame.
	end
	self.forward, self.up = Util.orthonormal(self.forward, self.up)

	-- The dip itself is applied above, for every landing including the
	-- hop's. This is only the EVENT, and it still deliberately excludes
	-- the hop: `landed` drives a haptic punch and a quest tally, and
	-- firing one on every drift entry would buzz the controller through
	-- every corner and turn "land 50 jumps" into "drift 50 times".
	if self.grounded and not self.wasGrounded and self.state ~= STATE_HOP then
		events.landed = true
	end

	----------------------------------------------------------------
	-- 8. PRESENTATION  — lies, all of it. None feeds back into movement.
	----------------------------------------------------------------
	-- Nose points INTO the turn while the kart keeps travelling along
	-- `forward`. Driven off the same eased blend as the rotation, so the
	-- body angle and the turn arrive together.
	--
	-- The angle also ANSWERS THE STICK. A fixed number meant the body
	-- struck one pose on turn-in and held it for the whole corner, whether
	-- you were feathering the slide or leaning on the stop — the drift
	-- looked the same however hard you were working, which is most of what
	-- made it read as locked-off.
	--
	-- Off the SMOOTHED steer, not the raw input, so the body swings with
	-- the stick instead of snapping to it. Still cosmetic: `travel` and
	-- `forward` never hear about any of this.
	local visualTrim = math.clamp(self.steer * activeDir, -1, 1)
	local visualAngle = self.H.DriftVisualAngle + visualTrim * self.H.DriftVisualAngleTrim
	self.driftAngle = -activeDir * math.rad(visualAngle) * eased

	-- Spinning out overrides the drift angle entirely. Several fast
	-- revolutions that decelerate, plus roll and pitch thrown around, so
	-- being hit reads as losing control rather than as a neat pirouette.
	--
	-- The kart still TRAVELS along `forward` throughout — only the body is
	-- thrashing. That's what keeps a spinout recoverable instead of
	-- disorienting: you never actually lose your line, just your dignity.
	-- A REAL SPIN has already turned the kart, so there is nothing
	-- cosmetic left to add — driftAngle staying 0 is exactly why it does
	-- not snap back when the spin ends.
	local spinning = now < self.spinUntil and not self.spinReal
	if spinning then
		local span = math.max(self.spinUntil - self.spinFrom, 1e-3)
		local t = math.clamp((now - self.spinFrom) / span, 0, 1)
		local spun = 1 - (1 - t) ^ FX.SpinEase
		self.driftAngle = math.pi * 2 * (self.spinRevs or FX.SpinRevolutions) * spun

		-- Thrash decays with the spin, so it settles rather than stopping.
		local fade = 1 - t
		local wobble = math.sin(now * FX.SpinWobbleRate * math.pi * 2) * fade
		self.lean = math.rad(FX.SpinWobble) * wobble
		self.bikeLeanVelocity = 0
		self.pitch = math.rad(FX.SpinPitch) * math.cos(now * FX.SpinWobbleRate * math.pi * 3) * fade
	end

	-- Skipped while spinning: the thrash above owns lean and pitch, and
	-- smoothing toward a steering target would fight it flat.
	if not spinning then
		local leanTarget = -self.steer * math.rad(FX.LeanAngle) + -activeDir * math.rad(FX.DriftLeanBonus) * eased
		if self.isBike then
			-- This is deliberately on `self.lean`, which is applied to the
			-- hitbox at the final render write below. Applying it to the body
			-- motor only was the reason the rider and wheels could bank while
			-- the rest of the motorcycle appeared to stay behind.
			local pace = math.clamp(math.abs(self.speed) / math.max(self.H.MaxSpeed, 1), 0, 1)
			local t = (pace - BK.LeanLowAt) / math.max(BK.LeanHighAt - BK.LeanLowAt, 1e-3)
			local leanReach = math.clamp(BK.LeanLow + (BK.LeanHigh - BK.LeanLow) * t, 0, BK.LeanHigh)
			leanTarget = -self.steer * math.rad(leanReach)

			--=====================================================
			--  A DRIFTING BIKE BANKS HARDER THAN A TURNING ONE.
			--
			--  The kart's `leanTarget` above carries a drift term and
			--  this branch was overwriting it outright, so a
			--  motorcycle in a full powerslide leaned exactly as far
			--  as one merely steering — which is why the drift had no
			--  bank of its own to see.
			--
			--  `activeDir` and `eased` are the drift's own direction
			--  and ramp, already computed for the kart, so this is the
			--  same drift the rest of the machine agrees it is in.
			--  Scaled by reach so a crawling bike still cannot throw
			--  itself over, which is the rule the whole lean obeys.
			--=====================================================
			leanTarget += -activeDir
				* math.rad(BK.DriftLeanBonus)
				* eased
				* math.clamp(leanReach / math.max(BK.LeanHigh, 1e-3), 0, 1)
		end

		-- Loading up for a drift that does not exist yet. The hop is the
		-- only moment the player has already committed and the kart has
		-- nothing to show for it, so the body rolls the way they are
		-- steering — which is the way the drift is about to go. Turn-in on
		-- landing then continues a movement instead of beginning one.
		--
		-- Same sign as DriftLeanBonus by construction: both follow the
		-- steer that decides driftDir, so the roll never has to reverse
		-- across the landing.
		if self.state == STATE_HOP then
			leanTarget += -self.steer * math.rad(FX.HopLean)
		end
		if self.isBike then
			-- A spring gives the motorcycle a little weight: it flows into
			-- the bank, carries a trace of momentum through turn-in, then
			-- settles itself on exit. This remains cosmetic because `lean`
			-- is consumed only by the final render CFrame.
			self.bikeLeanVelocity += (-BK.WholeLeanSpring * (self.lean - leanTarget) - BK.WholeLeanDamp * self.bikeLeanVelocity) * dt
			self.lean += self.bikeLeanVelocity * dt
			self.lean = math.clamp(self.lean, -math.rad(BK.LeanMax), math.rad(BK.LeanMax))
		else
			self.lean = Util.approach(self.lean, leanTarget, FX.LeanRate, dt)
		end

		local pitchTarget = math.rad(FX.PitchOnAccel) * (boosting and -1 or -throttle) * 0.5

		-- Nose up climbing, nose down falling. Negative is nose-up here,
		-- same convention as the squat above. Scaled by vertical speed so
		-- it passes through zero at the apex and unwinds itself on
		-- touchdown — no state to clear, and a ramp jump gets it free.
		if not self.grounded then
			local rise = math.clamp(self.vertVel / self.H.HopSpeed, -1, 1)
			pitchTarget += -math.rad(FX.AirPitch) * rise
		end

		-- A HULL TRIMS BOW-UP, and it does it for a real reason: below
		-- planing speed a boat is climbing its own bow wave, so the nose
		-- sits high and the stern squats. It is worst while ACCELERATING
		-- through that hump and settles once the hull is up and planing.
		--
		-- Hence two terms rather than one. Throttle gives the big lift
		-- while you are getting up to speed; the speed term is the
		-- smaller trim it keeps once it is there. A single speed-based
		-- lean would be wrong in the exact moment the player is looking
		-- for it — pinning the throttle from rest would do nothing until
		-- the speed had already arrived.
		--
		-- Reverse deliberately does NOT lift the bow: `math.max` drops
		-- negative throttle, because a boat backing up settles by the
		-- stern rather than rearing.
		--
		-- Negative is nose-up here, the same convention as the squat and
		-- the air pitch above, so this SUBTRACTS. It also inherits
		-- `FX.PitchRate` smoothing and the render write for free, which
		-- is why it belongs here rather than in a system of its own.
		if (self.swim or 0) > 0.001 then
			local pace = math.clamp(math.abs(self.speed) / math.max(self.H.MaxSpeed, 1), 0, 1)
			local drive = math.max(throttle, 0)
			-- THE THROTTLE TERM FADES AS THE HULL GETS UP. That `1 - pace`
			-- is the whole physical story: the lift comes from climbing
			-- the bow wave, and once you are planing you are ON it, not
			-- climbing it. Holding full bow-up at top speed would be a
			-- boat permanently stuck at its hump — nose to the sky on a
			-- flat-out straight, which is the one place a real hull is
			-- flattest.
			local bowUp = SW.TrimOnThrottle * drive * (1 - pace) + SW.TrimAtSpeed * pace
			pitchTarget -= math.rad(bowUp) * self.swim
		end

		self.pitch = Util.approach(self.pitch, pitchTarget, FX.PitchRate, dt)
	end

	-- SUSPENSION, AS ARITHMETIC. Still no constraint, still no physics —
	-- a number the controller integrates and hands to a visual offset.
	--
	-- A lerp toward zero can only sag back to rest, which reads as the
	-- kart giving up rather than absorbing. A damped spring overshoots
	-- once and settles, and that single rebound is the whole difference
	-- between landing and stopping.
	--
	-- Explicit Euler is stable here because dt is capped at MaxTimestep
	-- (1/20) and the spring's period is a comfortable ~0.45s.
	self.squashVel += (-FX.SquashSpring * self.squash - FX.SquashDamp * self.squashVel) * dt
	self.squash += self.squashVel * dt
	self.squash = math.clamp(self.squash, -FX.LandSquashMax, FX.LandSquashMax)

	-- The collision error still being hidden, easing back to zero. Kept
	-- out of `squash` because that is clamped to a cosmetic range and a
	-- hard landing needs to absorb several studs.
	self.catch = Util.approach(self.catch or 0, 0, FX.LandCatchRecover, dt)
	-- Guide is applied at the LAST possible point: collision/ground logic
	-- may still run normally while the item is starting or ending, but it
	-- can no longer overwrite a deliberate hover pose before rendering.
	if self.guide then
		local guide = self.guide
		self.pos = guide.position
		self.forward = guide.forward
		self.travel = guide.forward
		self.up = guide.up
		self.speed = guide.speed
		self.vertVel = 0
		self.grounded = false
		self.visualNormal = guide.up
		self.driftAngle = 0
		-- A guide may leave these nil to preserve the real FlipRamp trick
		-- animation it deliberately launched on entry.
		if guide.flipAngle ~= nil then
			self.trickAngle = guide.flipAngle
			self.trickAxis = guide.flipAxis
		end
		velocity = guide.forward * guide.speed
		speedAbs = math.abs(guide.speed)
	end
	self.speedFrac = math.clamp(speedAbs / maxSpeed, 0, 1)
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

	-- Bob, squash and the water hop all ride along up, not world-Y.
	local visualPos = self.pos + up * (self.bob - self.squash - (self.catch or 0) + (self.swimHop or 0))
	local base = CFrame.fromMatrix(visualPos, right, up, -look)
	-- THE FLIP GOES HERE, ON THE WHOLE ASSEMBLY.
	--
	-- One rotation on the render write turns the hitbox, the seat, the
	-- driver, the bodywork and every wheel together — because they are
	-- all jointed to it. The first attempt rotated individual Motor6Ds
	-- instead, and missed a different part each time: the body when there
	-- was no body root, then the seat and the player, because the seat
	-- hung off its own weld.
	--
	-- Rotating a LIST of things means the list can be wrong. Rotating the
	-- thing they are all attached to cannot be.
	--
	-- Safe here because this line is already the cosmetic write: pitch,
	-- lean, bob and squash are all visual offsets on top of the true
	-- pos/forward/up, and the simulation reads none of them back. The
	-- sweep and the ground probe build their own frames, so collision is
	-- untouched however far upside down the art is.
	--=================================================================
	--  THE WHEELIE. Rotated about the REAR AXLE, not the centre.
	--
	--  A vehicle pivoting on its middle drives its back wheel down
	--  through the road while the nose comes up. The rear axle is the
	--  point a real one turns about, and using it means the back tyre
	--  stays exactly where it was — it simply spins in place, which a
	--  circle does invisibly.
	--
	--  The standard conjugation for rotating about a line through a
	--  point, the same one Arc uses:
	--
	--      translate(pivot) . rotate . translate(-pivot)
	--
	--  ENTIRELY VISUAL, like everything else on this line. `pos`,
	--  `forward`, `up`, the sweep and the ground probe are untouched, so
	--  a bike stood on its back wheel is driving exactly as a flat one
	--  would and cannot clear anything by doing it.
	--
	--  Tier-driven and asymmetric: up fast, down slow. Slamming back
	--  level reads as the effect being switched off rather than ending.
	local tiers = self.H.WheelieByTier
	local wantWheelie = 0
	if typeof(tiers) == "table" then
		local burn = math.floor(self.burnStage or 0)
		if burn > 0 then
			wantWheelie = tiers[math.min(burn, #tiers)] or 0
		end
	end
	local wheelieRate = if wantWheelie > (self.wheelie or 0) then self.H.WheelieRise else self.H.WheelieFall
	self.wheelie = Util.approach(self.wheelie or 0, wantWheelie, wheelieRate, dt)

	--=================================================================
	--  THE STOPPIE. Brake hard and the rear comes up over the front.
	--
	--  BRAKING INPUT, NOT MEASURED DECELERATION. Both stop the bike
	--  fast, but only one of them is the rider's doing — decelerating
	--  into a wall would throw the tail up as if it had been a
	--  beautifully judged stop, which is the opposite of what a crash
	--  should look like. Walls get the wobble; brakes get this.
	--
	--  IT FADES OUT WITH SPEED, and that fall-off is the whole effect.
	--  The tail rises while there is still speed to scrub and settles
	--  as that runs out, so the bike comes down onto both wheels at
	--  exactly the moment it stops — "elevates, then stops" with no
	--  state to clear and nothing anywhere that has to detect having
	--  stopped.
	--
	--  NOT WHILE A WHEELIE IS UP. They pivot about opposite ends and
	--  fight over the same axis, and you cannot brake out of a boost
	--  hard enough to deserve both. The wheelie wins because it is the
	--  one the player earned.
	--
	--  GROUNDED ONLY: in mid-air there is no front tyre loaded for the
	--  bike to pivot on, and the trick rotation already owns the air.
	--=================================================================
	local wantStoppie = 0
	if self.H.StoppieAngle > 0 and self.grounded and (self.wheelie or 0) < 0.5 and throttle < -0.05 then
		local pace = math.clamp(math.abs(self.speed) / math.max(self.H.MaxSpeed, 1), 0, 1)
		local bite = math.clamp(
			(pace - self.H.StoppieAt) / math.max(1 - self.H.StoppieAt, 1e-3),
			0,
			1
		)
		wantStoppie = self.H.StoppieAngle * bite * -throttle
	end
	local stoppieRate = if wantStoppie > (self.stoppie or 0) then self.H.StoppieRise else self.H.StoppieFall
	self.stoppie = Util.approach(self.stoppie or 0, wantStoppie, stoppieRate, dt)

	--=================================================================
	--  A MOTORCYCLE LEANS ABOUT ITS CONTACT PATCH.
	--
	--  Rolling about the hitbox CENTRE swings the machine sideways out
	--  of its own wheels. At the 20 degrees this used to reach that is
	--  invisible; at GP angles the tyres leave the road on one side and
	--  it reads as the model being tipped over rather than as a rider
	--  leaning, which is why raising the angle alone was never going to
	--  be enough.
	--
	--  The patch is exactly RideHeight below the hitbox centre — that is
	--  what RideHeight MEANS — so this needs no second number to keep in
	--  step, and it stays correct for any vehicle that sets one.
	--
	--  Same conjugation as the wheelie below: translate, rotate, undo.
	--=================================================================
	local render
	if self.isBike then
		local patch = Vector3.new(0, -self.H.RideHeight, 0)
		render = base
			* CFrame.Angles(self.pitch + (self.swimHopPitch or 0), 0, 0)
			* CFrame.new(patch)
			* CFrame.Angles(0, 0, self.lean)
			* CFrame.new(-patch)
	else
		render = base * CFrame.Angles(self.pitch + (self.swimHopPitch or 0), 0, self.lean)
	end
	if (self.wheelie or 0) > 0.05 and self.H.WheelieAxle > 0 then
		local pivot = Vector3.new(0, 0, self.H.WheelieAxle)
		-- POSITIVE is nose-UP here. A right-hand rotation about +X tilts the
		-- up vector toward +Z, and forward is -Z, so the nose rises. The
		-- first version negated this and gave a stoppie: the bike rotated
		-- nose-DOWN about its own rear axle and drove its front into the
		-- road. `self.pitch` on the line above uses the opposite sign
		-- because it is measured as an attitude, not applied as a lift.
		render *= CFrame.new(pivot) * CFrame.Angles(math.rad(self.wheelie), 0, 0) * CFrame.new(-pivot)
	end
	-- THE STOPPIE, and it is the wheelie with both signs flipped: the
	-- pivot moves to the FRONT axle (-Z is forward) and the rotation goes
	-- negative, which is tail-up by the same right-hand rule that makes
	-- positive nose-up above.
	if (self.stoppie or 0) > 0.05 and self.H.StoppieAxle > 0 then
		local pivot = Vector3.new(0, 0, -self.H.StoppieAxle)
		render *= CFrame.new(pivot) * CFrame.Angles(-math.rad(self.stoppie), 0, 0) * CFrame.new(-pivot)
	end
	if (self.trickAngle or 0) ~= 0 and self.trickAxis then
		render *= CFrame.fromAxisAngle(self.trickAxis, self.trickAngle)
	end
	self.hitbox.CFrame = render
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
