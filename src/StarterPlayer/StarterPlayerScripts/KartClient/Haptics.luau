--[[
	Haptics — controller rumble.

	WHAT A RACING GAME ACTUALLY DOES WITH RUMBLE
	--------------------------------------------
	The temptation is to buzz on every event. That reads as noise, and
	within a lap the player stops feeling any of it — a motor that is
	always on carries no information.

	So this is built as two separate things, and keeping them apart is
	the whole design:

	  CONTINUOUS   a low bed that tells you what the tyres are doing.
	               Always proportional to something physical: how hard
	               the tyres are working, how fast you're going. You stop
	               noticing it consciously, which is the point — you
	               notice when it CHANGES.

	  IMPACTS      short, sharp, and rare. A hit, a landing, a boost
	               lighting. These have to punch through the bed, which
	               they can only do if the bed is quiet.

	FOUR MOTORS, FOUR JOBS
	----------------------
	  Large        the body of the kart. Surface, speed, big impacts.
	  Small        detail. Tyre scrub and the whine of a boost.
	  Triggers     per-wheel feedback. This is the one that makes a
	               controller feel like a car rather than a gamepad:
	               the throttle trigger fights you when the rears are
	               spinning, and that is genuinely useful information.

	Trigger motors only exist on some controllers, so everything is
	guarded by IsMotorSupported and silently does nothing where it isn't.

	NOTHING HERE FEEDS BACK INTO MOVEMENT. It reads the simulation and
	writes to motors. A haptics module that could change how the kart
	drives would be a haptics module that desyncs the race.
--]]

local HapticService = game:GetService("HapticService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))

local HAP = Config.Haptics

local PAD = Enum.UserInputType.Gamepad1
local LARGE = Enum.VibrationMotor.Large
local SMALL = Enum.VibrationMotor.Small
local LTRIG = Enum.VibrationMotor.LeftTrigger
local RTRIG = Enum.VibrationMotor.RightTrigger

local Haptics = {}
Haptics.__index = Haptics

-- Cached once: IsMotorSupported is a call into the engine and this runs
-- every frame.
local function supports(motor): boolean
	local ok, yes = pcall(function()
		return HapticService:IsMotorSupported(PAD, motor)
	end)
	return ok and yes
end

function Haptics.new()
	local self = setmetatable({
		-- Impact energy per motor, decaying. Separate from the
		-- continuous bed so a punch can ride on top of it rather than
		-- replacing it — being hit while cornering should feel like both.
		punchLarge = 0,
		punchSmall = 0,
		hasLarge = false,
		hasSmall = false,
		hasTriggers = false,
		enabled = false,
		-- Last value written per motor, so a frame that wants the same
		-- number doesn't call into the engine again.
		lastLarge = -1,
		lastSmall = -1,
		lastLeft = -1,
		lastRight = -1,
	}, Haptics)

	self:Refresh()
	return self
end

-- Re-checks what the connected controller can do. Called at startup and
-- whenever a gamepad is connected, because a player who plugs a pad in
-- mid-race should get rumble without rejoining.
function Haptics:Refresh()
	local ok, vibrates = pcall(function()
		return HapticService:IsVibrationSupported(PAD)
	end)
	self.enabled = HAP.Enabled and ok and vibrates and UserInputService.GamepadEnabled
	if not self.enabled then
		return
	end
	self.hasLarge = supports(LARGE)
	self.hasSmall = supports(SMALL)
	-- Both, or neither: one-sided trigger rumble feels like a fault.
	self.hasTriggers = supports(LTRIG) and supports(RTRIG)
end

function Haptics:_set(motor, value: number, cacheKey: string)
	value = math.clamp(value, 0, 1)
	-- Below this the motor either won't spin or produces a whine rather
	-- than a rumble, so it's cheaper and nicer to send a clean zero.
	if value < HAP.MotorFloor then
		value = 0
	end
	if math.abs(value - self[cacheKey]) < 0.01 then
		return
	end
	self[cacheKey] = value
	pcall(function()
		HapticService:SetMotor(PAD, motor, value)
	end)
end

--=====================================================================
--  IMPACTS
--=====================================================================

-- A one-off jolt. `weight` 0..1 scales it; a missile should not feel the
-- same as clipping a kerb.
--
-- Added to whatever is already decaying rather than replacing it, so two
-- hits in quick succession stack instead of the second one resetting the
-- first and reading as weaker.
function Haptics:Punch(weight: number)
	weight = math.clamp(weight, 0, 1)
	self.punchLarge = math.min(self.punchLarge + weight, 1)
	self.punchSmall = math.min(self.punchSmall + weight * HAP.PunchSmallShare, 1)
end

--=====================================================================
--  FRAME
--=====================================================================
function Haptics:Update(dt: number, sim)
	if not self.enabled then
		return
	end

	-- Impacts decay first, so a punch fired this frame is still at full
	-- strength when it's written below.
	self.punchLarge = math.max(self.punchLarge - dt / HAP.PunchDecay, 0)
	self.punchSmall = math.max(self.punchSmall - dt / HAP.PunchDecay, 0)

	----------------------------------------------------------------
	-- THE BED — what the kart is doing, continuously.
	----------------------------------------------------------------
	local speed = sim.speedFrac or 0
	local load = sim.tyreLoad or 0
	local slip = sim.slip or 0

	-- Airborne is SILENT, and that silence is information: it's the only
	-- time a car has nothing to tell you through the tyres, and getting
	-- it back on landing is most of what a landing feels like.
	local grounded = sim.grounded and 1 or 0

	-- THRESHOLDED, so the motors are OFF unless something is happening.
	--
	-- This is the difference between a bed and a buzz. Scaling straight
	-- off tyreLoad meant the small motor spun the entire race, which
	-- wears a controller out, flattens its battery, and says nothing —
	-- a signal that is always present carries no information.
	--
	-- Rescaled above the threshold rather than clipped, so scrub still
	-- comes in from zero and rises. A hard step at the threshold would
	-- read as the motor faulting.
	local bedLarge = speed * HAP.SpeedRumble * grounded

	local bedSmall = 0
	if load > HAP.ScrubThreshold then
		local over = (load - HAP.ScrubThreshold) / math.max(1 - HAP.ScrubThreshold, 1e-3)
		bedSmall = over * HAP.ScrubRumble * grounded
	end

	-- Boost adds its own layer to the small motor, where a whine belongs.
	-- Unthresholded because it is already brief and self-limiting.
	if sim.burning or sim.boosting then
		bedSmall += HAP.BoostRumble
	end

	self:_set(LARGE, math.max(bedLarge, self.punchLarge), "lastLarge")
	self:_set(SMALL, math.max(bedSmall, self.punchSmall), "lastSmall")

	----------------------------------------------------------------
	-- TRIGGERS — the bit that feels like a car.
	--
	-- The throttle trigger pushes back when the rear tyres are past
	-- their grip: that is a traction warning you feel in the finger
	-- already holding the throttle, which is the fastest route into a
	-- driver there is.
	--
	-- The brake trigger carries the same signal while actually braking,
	-- which is what an ABS pedal does.
	----------------------------------------------------------------
	if self.hasTriggers then
		-- Same threshold logic. Gentle cornering is not a traction event,
		-- and a trigger buzzing through every mild bend is the fastest way
		-- to make somebody turn rumble off in the settings.
		local traction = 0
		if slip > HAP.TriggerThreshold then
			local over = (slip - HAP.TriggerThreshold) / math.max(1 - HAP.TriggerThreshold, 1e-3)
			traction = over * HAP.TriggerSlip * grounded
		end
		local throttle = sim.speed and sim.speed > 0
		self:_set(RTRIG, if throttle then traction else 0, "lastRight")
		self:_set(LTRIG, if throttle then 0 else traction, "lastLeft")
	end
end

-- Everything off. Called on death, on leaving the kart, and on teardown:
-- a motor left spinning after the thing driving it has gone is the one
-- haptics bug players actually complain about.
function Haptics:Stop()
	self.punchLarge, self.punchSmall = 0, 0
	if not self.enabled then
		return
	end
	self:_set(LARGE, 0, "lastLarge")
	self:_set(SMALL, 0, "lastSmall")
	if self.hasTriggers then
		self:_set(LTRIG, 0, "lastLeft")
		self:_set(RTRIG, 0, "lastRight")
	end
end

function Haptics:Destroy()
	self:Stop()
end

return Haptics
