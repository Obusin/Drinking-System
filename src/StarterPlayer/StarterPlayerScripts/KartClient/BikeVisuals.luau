--[[
	BikeVisuals — everything that makes the motorcycle look like one.

	NONE OF THIS MOVES THE MOTORCYCLE.

	It returns a pose — roll, pitch, yaw, lift, dip, bar angle, a steering
	scale and a tuck amount — which `Rider` writes onto the body motor and
	the rider's joints. `Simulation` never sees any of it, so a bike laid
	over at forty degrees is going exactly where an upright one would.

	That is not a caveat, it is the design. The drama is free BECAUSE it is
	fake, and free drama is the only kind you can afford this much of.

	MAKE IT LOOK HARDER TO CONTROL THAN IT IS.
	------------------------------------------
	Read this way round, the rules fall out on their own:

	  the lean is a SPRING          so a chicane throws it side to side
	  the bars turn LESS at speed   so it turns by leaning, like a bike
	  wobble has ONE source         so it never happens unprompted
	  everything decays FAST        so nothing outlives the thing that
	                                caused it and costs you a corner

	The player should feel skilful while the game quietly does the hard
	part. Nothing here may ever be the reason a corner went wrong.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))

local BK = Config.Bike
local H = Config.Handling

local BikeVisuals = {}

-- 0..1, how fast we are going as a fraction of the vehicle's top speed.
--
-- THE BIKE'S OWN TOP SPEED, not the kart's. This read `H.MaxSpeed` (95)
-- while the bike does 102, so pace saturated at 93% of the way there and
-- the last 7 studs/s of the speed range produced no change in lean, tuck,
-- bar angle or shiver — every curve in this file is anchored on pace.
--
-- Resolved once at require time: this module only ever serves bikes, so
-- there is nothing per-kart to look up per frame.
local BIKE_TOP = (Config.Vehicles.Kinds.bike.handling or {}).MaxSpeed or H.MaxSpeed

local function paceOf(s): number
	return math.clamp((s.speedNow or 0) / math.max(BIKE_TOP, 1), 0, 1)
end

--=====================================================================
--  EVENTS. Called by Rider when something actually happens.
--
--  Wobble is ONE decaying channel with several sources, deliberately:
--  two independent wobble timers end up fighting over the same angle and
--  the loser is whichever ran second. Same reasoning as the camera's
--  single impact channel.
--=====================================================================
function BikeVisuals.wobble(s, amount: number)
	s.bikeWobble = math.min(math.max(s.bikeWobble or 0, amount), BK.WobbleMax)
end

function BikeVisuals.landed(s, impact: number, yawed: boolean)
	-- Scaled by how hard, so a drift hop is a nod and a real drop is a
	-- compression. The same impact number the kart's landing uses.
	s.bikeDipTo = math.max(s.bikeDipTo or 0, BK.LandDip * math.clamp(impact / 100, 0.15, 1))
	BikeVisuals.wobble(s, BK.WobbleOnLand * math.clamp(impact / 100, 0, 1))
	if yawed then
		-- LANDED CROOKED. A short fishtail and it is over — about a third
		-- of a second. Long enough to read as a save, too short to be a
		-- punishment, and the player keeps steering throughout.
		BikeVisuals.wobble(s, BK.WobbleOnBadLand)
	end
end

--=====================================================================
--  THE POSE
--
--  One call per frame. Everything is smoothed here rather than at the
--  point of use, so the values Rider writes are already the values it
--  should write — nothing downstream has to know what a spring is.
--=====================================================================
function BikeVisuals.update(s, dt: number, ctx): { [string]: number }
	local pace = paceOf(s)
	-- Published for the tyre smoke, which runs earlier in the frame.
	s.bikePace = pace
	local steer = math.clamp(ctx.steer or 0, -1, 1)
	local drift = ctx.drift or 0
	local throttle = math.clamp(ctx.throttle or 0, -1, 1)
	local boosting = ctx.boosting == true

	----------------------------------------------------------------
	-- LEAN
	--
	-- Scaled by steering AND speed. Leaning hard while crawling is what
	-- makes a bike look broken rather than fast, so below
	-- `LeanUprightBelow` it stays almost upright however hard you turn —
	-- which is also what keeps the lobby and the starting grid pleasant.
	----------------------------------------------------------------
	-- Interpolated between two anchor speeds and CLAMPED AT ZERO below
	-- the lower one, so a stationary bike is upright and a crawling one
	-- barely leans. Not multiplied by pace as well: doing both is how
	-- the first version ended up nearly upright at 60 studs/s.
	local t = (pace - BK.LeanLowAt) / math.max(BK.LeanHighAt - BK.LeanLowAt, 1e-3)
	local reach = math.clamp(BK.LeanLow + (BK.LeanHigh - BK.LeanLow) * t, 0, BK.LeanHigh)
	local target = -steer * reach

	--------------------------------------------------------------
	-- BANK ON THE TURN THAT IS HAPPENING, not only on the input.
	--
	-- Steering input alone banks the moment the key goes down, before
	-- the bike has actually started turning — so the lean leads the
	-- corner instead of belonging to it, and a stab of steering that
	-- changes nothing still throws the bike over.
	--
	-- The kart's own yaw rate is what is REALLY happening. Adding it
	-- means the bank builds as the bike comes round and holds while it
	-- is round, which is what makes a long corner feel carved rather
	-- than merely entered.
	--
	-- Normalised against the vehicle's own turn rate so it is a
	-- fraction of "as hard as this thing turns", not an absolute.
	--------------------------------------------------------------
	local turning = math.clamp((ctx.yawRate or 0) / math.max(BK.BankFullYaw, 1e-3), -1, 1)
	target += -turning * reach * BK.BankOnTurn

	-- TURN WITH YAW, STYLE IT WITH ROLL.
	--
	-- `sliding` is how far past ordinary cornering slip we are. With grip
	-- at 20 a normal corner holds about 4 degrees of slip and a real
	-- powerslide holds many times that, so this cleanly separates the two
	-- states without needing to be told which one we are in.
	--
	-- It gates the rear step-out AND the extra lean, so neither can fire
	-- during a grip corner — the visual must never make a planted turn
	-- look like a slide.
	local sliding = math.clamp((math.abs(drift) - BK.SlipIgnore) / math.max(BK.SlipFull - BK.SlipIgnore, 1e-3), 0, 1)
	-- The tyre smoke reads this rather than recomputing it. One definition
	-- of "is this a drift", so the smoke and the rear step-out can never
	-- disagree about it — the same reason the bar angle is published
	-- instead of being worked out twice.
	s.bikeSliding = sliding

	if sliding > 0 then
		target += -math.sign(drift) * BK.DriftLeanBonus * sliding * math.clamp(reach / BK.LeanHigh, 0, 1)
	end
	target = math.clamp(target, -BK.LeanMax, BK.LeanMax)

	--=============================================================
	--  THE SAME SPRING SIMULATION USES, AND THAT IS THE POINT.
	--
	--  `bikeLean` no longer rolls anything — the lean itself moved to
	--  the render write, which turns the whole machine. What is left
	--  reading this is everything that has to KNOW how far over the
	--  bike is: the rider's hips and head, and the knee.
	--
	--  So it has to be a faithful shadow of the real angle. On its own
	--  constants (k=260) it settled in 0.29s against the simulation's
	--  0.44s — half again as fast — and the knee would have been out
	--  before the bike got there, which is precisely the "rider moves
	--  first, machine follows" tell that made the old turning look
	--  wrong.
	--
	--  Matching by REFERENCE, not by copying the numbers across, so
	--  the two cannot drift apart the next time one is tuned.
	--=============================================================
	s.bikeLeanV = (s.bikeLeanV or 0)
		+ (-BK.WholeLeanSpring * ((s.bikeLean or 0) - target) - BK.WholeLeanDamp * (s.bikeLeanV or 0)) * dt
	s.bikeLean = (s.bikeLean or 0) + s.bikeLeanV * dt

	----------------------------------------------------------------
	-- WOBBLE AND FISHTAIL — only ever because something hit us.
	----------------------------------------------------------------
	local wob = 0
	if (s.bikeWobble or 0) > 0.01 then
		s.bikeWobblePhase = (s.bikeWobblePhase or 0) + dt * BK.WobbleSpeed
		wob = math.sin(s.bikeWobblePhase) * s.bikeWobble
		s.bikeWobble = s.bikeWobble * math.exp(-BK.WobbleDecay * dt)
	else
		s.bikeWobble = 0
	end

	----------------------------------------------------------------
	-- WEIGHT TRANSFER. Subtle: the player should see the weight move
	-- without the horizon doing anything they have to think about.
	----------------------------------------------------------------
	local pitchWant = 0
	if boosting then
		pitchWant -= BK.BoostPitch
	elseif throttle > 0.05 then
		pitchWant -= BK.PitchOnPower * throttle
	elseif throttle < -0.05 then
		pitchWant += BK.PitchOnBrake * -throttle
	end
	s.bikePitch = Util.approach(s.bikePitch or 0, pitchWant, BK.PitchRate, dt)

	-- Fork travel follows the pitch: nose down loads the front.
	local forkWant = math.clamp(s.bikePitch / math.max(BK.PitchOnBrake, 1), -1, 1) * BK.ForkDive
	s.bikeFork = Util.approach(s.bikeFork or 0, forkWant, BK.PitchRate, dt)

	----------------------------------------------------------------
	-- NITRO. A VISUAL front lift — the hitbox never moves, so this can
	-- never become a handling change or a way to clear something.
	----------------------------------------------------------------
	local tuckWant = (if boosting then 1 else 0)
	tuckWant = math.max(tuckWant, pace * BK.SpeedTuck)
	if math.abs(drift) > 0.01 then
		tuckWant = math.max(tuckWant, BK.DriftRiderTuck)
	end
	s.bikeTuck = Util.approach(s.bikeTuck or 0, tuckWant, BK.TuckRate, dt)
	s.bikeLift = Util.approach(s.bikeLift or 0, if boosting then BK.BoostLift else 0, BK.BoostLiftRate, dt)

	----------------------------------------------------------------
	-- DRIFT: THE REAR STEPS OUT, THE NOSE KEEPS POINTING AT THE EXIT.
	--
	-- A bike does not slide flat like a kart. Yawing the BODY while the
	-- front wheel carries on carving is what makes a powerslide read as
	-- controlled rather than as a crash already in progress.
	----------------------------------------------------------------
	-- THE REAR ONLY STEPS OUT WHEN IT ACTUALLY IS OUT.
	--
	-- This used to scale on the raw slip, so every corner yawed the body
	-- a little and the bike looked permanently sideways. Rotating the art
	-- further into a corner than the simulation has actually turned is
	-- exactly the thing that reads as drifting, and it is a lie the
	-- visuals have no business telling.
	local yawWant = -math.sign(drift) * BK.DriftRearYaw * sliding
	if (s.bikeWobble or 0) > 0.01 then
		yawWant += wob * BK.FishtailPerWobble
	end
	s.bikeYaw = Util.approach(s.bikeYaw or 0, yawWant, BK.DriftYawRate, dt)

	----------------------------------------------------------------
	-- LANDING DIP. In fast, out slow, so it reads as a compression and
	-- a rebound rather than as a bob.
	----------------------------------------------------------------
	local dipRate = if (s.bikeDipTo or 0) > (s.bikeDip or 0) then BK.LandDipRate else BK.LandRiseRate
	s.bikeDip = Util.approach(s.bikeDip or 0, s.bikeDipTo or 0, dipRate, dt)
	s.bikeDipTo = math.max((s.bikeDipTo or 0) - BK.LandRiseRate * dt, 0)

	----------------------------------------------------------------
	-- SPEED SHIVER. Deliberately almost invisible — this is the one
	-- effect that becomes motion sickness the moment it is loud enough
	-- to notice on purpose.
	----------------------------------------------------------------
	local shiver = 0
	if pace > BK.ShiverAt then
		local amt = (pace - BK.ShiverAt) / math.max(1 - BK.ShiverAt, 1e-3)
		s.bikeShiverPhase = (s.bikeShiverPhase or 0) + dt * BK.ShiverSpeed
		shiver = math.sin(s.bikeShiverPhase) * BK.Shiver * amt
	end

	-- IDLE. Alive, and never balancing: anything that reads as balancing
	-- reads as about to fall over.
	local idle = 0
	if pace < 0.02 then
		s.bikeIdlePhase = (s.bikeIdlePhase or 0) + dt * BK.IdleBobSpeed
		idle = math.sin(s.bikeIdlePhase) * BK.IdleBob
	end

	----------------------------------------------------------------
	-- BARS AND FRONT WHEEL: LESS ANGLE AT SPEED, NOT MORE.
	--
	-- A bike turns by leaning and the bars barely move. Showing full
	-- lock at speed reads as a bicycle being wrestled, so the visible
	-- angle SHRINKS as the lean takes the job over.
	----------------------------------------------------------------
	local barBase = steer * (BK.BarTurnLow + (BK.BarTurnHigh - BK.BarTurnLow) * pace)
	-- Counter-steering is an entry cue, not a permanent steering mode:
	-- when the rider sharply asks to lean left, the bars flick right for a
	-- moment, then settle into the visible steering angle. `steer` is the
	-- resolved input, so this stays smooth even when a key is tapped.
	local steerRate = (steer - (s.bikeLastSteer or steer)) / math.max(dt, 1e-3)
	s.bikeLastSteer = steer
	local counterKick = math.clamp(steerRate / math.max(BK.CounterSteerFullRate, 1e-3), -1, 1) * BK.CounterSteerKick
	local barWant = barBase - counterKick
	s.bikeBar = Util.approach(s.bikeBar or 0, barWant, BK.BarRate, dt)

	-- Published for updateRoadWheels, which runs before this and would
	-- otherwise need the pose it has not computed yet.
	s.bikeSteerScale = BK.WheelSteerLow + (BK.WheelSteerHigh - BK.WheelSteerLow) * pace

	return {
		--=============================================================
		--  TWO ROLLS, AND THEY GO TO DIFFERENT PLACES.
		--
		--  `roll` is the full angle, for anything that needs to KNOW
		--  how far over the bike is — rider posture, the knee, the
		--  camera. It is NOT for the body motor.
		--
		--  `shake` is what the BODYWORK does relative to its own
		--  wheels. The lean itself now lives on the render write in
		--  Simulation, which turns the whole assembly — hitbox, wheels,
		--  bodywork and rider together — so adding it here as well
		--  leaned the machine twice and folded it in half.
		--
		--  What genuinely belongs on the body motor is the part the
		--  tyres do NOT share: a wobble is the bodywork shaking while
		--  the rubber stays planted, and that is the honest reading of
		--  one anyway.
		--=============================================================
		roll = s.bikeLean + wob + shiver,
		shake = wob + shiver,
		pitch = s.bikePitch,
		yaw = s.bikeYaw,
		lift = s.bikeLift + idle - s.bikeDip,
		fork = s.bikeFork,
		bar = s.bikeBar,
		tuck = s.bikeTuck,
		-- Fraction of the kart's normal front-wheel throw.
		steerScale = BK.WheelSteerLow + (BK.WheelSteerHigh - BK.WheelSteerLow) * pace,
	}
end

return BikeVisuals
