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

local LARGE = Enum.VibrationMotor.Large
local SMALL = Enum.VibrationMotor.Small
local LTRIG = Enum.VibrationMotor.LeftTrigger
local RTRIG = Enum.VibrationMotor.RightTrigger

local Haptics = {}
Haptics.__index = Haptics

local function isGamepad(inputType: Enum.UserInputType?): boolean
	return inputType ~= nil and inputType.Name:sub(1, 7) == "Gamepad"
end

local function connectedGamepads(): { Enum.UserInputType }
	local ok, pads = pcall(function()
		return UserInputService:GetConnectedGamepads()
	end)
	return if ok then pads else {}
end

local function contains(pads: { Enum.UserInputType }, wanted: Enum.UserInputType): boolean
	for _, pad in pads do
		if pad == wanted then
			return true
		end
	end
	return false
end

-- Ask the engine which pad can actually vibrate.  Gamepad1 is usually
-- correct, but a wireless pad reconnected after another device can land in a
-- different Gamepad slot; hardcoding slot 1 silently drops rumble there.
local function supports(pad: Enum.UserInputType, motor): boolean
	local ok, yes = pcall(function()
		return HapticService:IsMotorSupported(pad, motor)
	end)
	return ok and yes
end

local function stopPad(pad: Enum.UserInputType)
	for _, motor in { LARGE, SMALL, LTRIG, RTRIG } do
		pcall(function()
			HapticService:SetMotor(pad, motor, 0)
		end)
	end
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
		pad = nil :: Enum.UserInputType?,
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

function Haptics:Refresh(preferred: Enum.UserInputType?)
	local pads = connectedGamepads()
	local last = UserInputService:GetLastInputType()
	local pad = if isGamepad(preferred) and contains(pads, preferred) then preferred
		elseif isGamepad(last) and contains(pads, last) then last
		else pads[1]

	local oldPad = self.pad
	if oldPad and oldPad ~= pad then
		-- Caches belong to a physical controller, not the feature. Without
		-- this, the old pad can keep rumbling and a new pad can be skipped
		-- because its desired value happens to equal the old cached value.
		stopPad(oldPad)
		self.lastLarge, self.lastSmall = -1, -1
		self.lastLeft, self.lastRight = -1, -1
	end

	if not pad then
		self.enabled = false
		self.hasLarge, self.hasSmall, self.hasTriggers = false, false, false
		self.pad = nil
		return
	end

	local ok, vibrates = pcall(function()
		return HapticService:IsVibrationSupported(pad)
	end)
	self.pad = pad
	self.enabled = HAP.Enabled and ok and vibrates
	if not self.enabled then
		self.hasLarge, self.hasSmall, self.hasTriggers = false, false, false
		return
	end
	self.hasLarge = supports(pad, LARGE)
	self.hasSmall = supports(pad, SMALL)
	-- Both, or neither: one-sided trigger rumble feels like a fault.
	self.hasTriggers = supports(pad, LTRIG) and supports(pad, RTRIG)
end

-- Called when a player actively uses a different connected controller. Input
-- remains Roblox's normalised KeyCode mapping; only the optional feedback has
-- to follow the physical device.
function Haptics:UseGamepad(inputType: Enum.UserInputType)
	if isGamepad(inputType) then
		self:Refresh(inputType)
	end
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
	local pad = self.pad
	if not pad then
		return
	end
	pcall(function()
		HapticService:SetMotor(pad, motor, value)
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
		-- Speed says nothing about the driver's intent: a kart can be moving
		-- quickly while braking.  Read the seat input so tyre feedback goes
		-- to the trigger the player is actually using.
		local braking = sim.seat and sim.seat.ThrottleFloat < -0.1
		self:_set(RTRIG, if braking then 0 else traction, "lastRight")
		self:_set(LTRIG, if braking then traction else 0, "lastLeft")
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
