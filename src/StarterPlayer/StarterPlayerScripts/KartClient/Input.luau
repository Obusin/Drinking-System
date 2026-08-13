--[[
	Input — owns every button and the look-orbit offsets.

	Nothing else reads the keyboard. Other modules poll this one.
--]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local UserInputService = game:GetService("UserInputService")

local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))

local IN = Config.Input
local CAM = Config.Camera

local DRIFT_ACTION = "KartDrift"
local JUMPSINK_ACTION = "KartNoJump"
local EXIT_ACTION = "KartExit"
local LOOKBACK_ACTION = "KartLookBack"
local NITRO_ACTION = "KartNitro"
local RESET_ACTION = "KartReset"
local ITEM_ACTION = "KartItem"
local ITEM_BACK_ACTION = "KartItemBack"
local DRIVE_FORWARD_ACTION = "KartDriveForward"
local DRIVE_BACK_ACTION = "KartDriveBack"
local DRIVE_LEFT_ACTION = "KartDriveLeft"
local DRIVE_RIGHT_ACTION = "KartDriveRight"

local Input = {
	-- Touch steering / throttle. Added to whatever the VehicleSeat
	-- reports rather than replacing it, so a device with both a
	-- touchscreen and a keyboard works with either, and the desktop path
	-- is bit-for-bit unchanged when these stay 0.
	touchSteer = 0,
	touchThrottle = 0,
	-- Independent of VehicleSeat.ThrottleFloat/SteerFloat. See Config.Input:
	-- direct bindings make the custom kart controller work even if Roblox's
	-- stock vehicle module misses the initial seating handoff.
	driveSteer = 0,
	driveThrottle = 0,

	driftHeld = false,
	nitroTaps = 0, -- queued, consumed one per frame by Simulation
	resetRequested = false,
	itemRequested = false,
	itemBackRequested = false,
	-- 0..1, how long the throw button was held. Read alongside
	-- consumeItemUse; meaningless without it.
	itemCharge = 0,
	-- Live while the button is down, for the HUD to show the wind-up.
	itemCharging = 0,
	freeLooking = false,
	lookingBack = false,
	lookYaw = 0,
	lookPitch = 0,
	padLook = Vector2.zero,
}

local driftPressed = false
local camSnap = false
local getHumanoid: (() -> Humanoid?)? = nil
local driveForward, driveBack, driveLeft, driveRight = false, false, false, false
local padSteer = 0

local function refreshDrive()
	Input.driveThrottle = (if driveForward then 1 else 0) - (if driveBack then 1 else 0)
	Input.driveSteer = math.clamp((if driveRight then 1 else 0) - (if driveLeft then 1 else 0) + padSteer, -1, 1)
end

local function driveButton(which: string)
	return function(_, state: Enum.UserInputState)
		local down = state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change
		if state == Enum.UserInputState.Begin or state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			if which == "forward" then
				driveForward = down
			elseif which == "back" then
				driveBack = down
			elseif which == "left" then
				driveLeft = down
			else
				driveRight = down
			end
			refreshDrive()
		end
		-- The custom Simulation owns motion. Sinking these prevents Roblox's
		-- VehicleSeat controller from becoming a second, sometimes absent,
		-- source of the same inputs.
		return Enum.ContextActionResult.Sink
	end
end

--=====================================================================
--  ACTIONS
--
--  Space is the default jump binding, and jumping in a VehicleSeat
--  ejects you. BindAction pushes these to the top of the action stack,
--  so returning Sink swallows the input before the core jump action
--  ever sees it.
--=====================================================================
local function onDrift(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		Input.driftHeld = true
		driftPressed = true
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		Input.driftHeld = false
	end
	return Enum.ContextActionResult.Sink
end

-- Queued, not latched: a fast double-tap must escalate two stages
-- rather than being collapsed into one by whichever frame sampled it.
local function onNitro(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		Input.nitroTaps += 1
	end
	return Enum.ContextActionResult.Sink
end

local function onReset(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		Input.resetRequested = true
	end
	return Enum.ContextActionResult.Sink
end

-- HELD, then thrown on release. A tap lobs it at your feet, a full hold
-- throws it as far as it goes.
--
-- Only the forward throw charges. Dropping something behind you is a
-- defensive reflex — making that one wait for a wind-up would mean
-- being hit while holding the button that was meant to save you.
local itemDownAt = 0

local function onItem(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		itemDownAt = os.clock()
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		if itemDownAt > 0 then
			Input.itemCharge = math.clamp((os.clock() - itemDownAt) / Config.Items.ThrowChargeTime, 0, 1)
			Input.itemRequested = true
			itemDownAt = 0
		end
	end
	return Enum.ContextActionResult.Sink
end

local function onItemBack(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		Input.itemBackRequested = true
	end
	return Enum.ContextActionResult.Sink
end

local function sink()
	return Enum.ContextActionResult.Sink
end

local function onExit(_, state: Enum.UserInputState)
	-- Sit = false is the reliable unseat. Humanoid.Jump wouldn't work,
	-- because outside test mode the server disables the Jumping state.
	if state == Enum.UserInputState.Begin and getHumanoid then
		local h = getHumanoid()
		if h then
			h.Sit = false
		end
	end
	return Enum.ContextActionResult.Sink
end

local function onLookBack(_, state: Enum.UserInputState)
	Input.lookingBack = state == Enum.UserInputState.Begin
	-- Hard cut, both directions. The camera position has to snap too, or
	-- it sweeps lazily THROUGH the kart to reach the other side.
	Input.lookYaw = if Input.lookingBack then math.pi else 0
	Input.lookPitch = 0
	camSnap = true
	return Enum.ContextActionResult.Sink
end

--=====================================================================
--  TOUCH
--
--  The on-screen buttons funnel through here rather than poking module
--  state directly, so a touch drift and a Space drift are genuinely the
--  same event — including `driftPressed`, which is what the hop reads.
--  A parallel touch path is how the two silently diverge.
--=====================================================================
function Input.setDrift(down: boolean)
	if down and not Input.driftHeld then
		driftPressed = true
	end
	Input.driftHeld = down
end

function Input.tapNitro()
	Input.nitroTaps += 1
end

-- Touch: the pad has no press-and-hold, so a tap is a full throw.
function Input.tapItem()
	Input.itemCharge = 1
	Input.itemRequested = true
end

function Input.tapItemBack()
	Input.itemBackRequested = true
end

function Input.tapReset()
	Input.resetRequested = true
end

-- Same hard cut as the key: the camera has to snap or it sweeps lazily
-- THROUGH the kart to reach the other side.
function Input.setLookBack(on: boolean)
	Input.lookingBack = on
	Input.lookYaw = if on then math.pi else 0
	Input.lookPitch = 0
	camSnap = true
end

--=====================================================================
--  FREE LOOK  (connected once, harmless when not driving)
--=====================================================================
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.UserInputType == IN.FreeLookButton then
		Input.freeLooking = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == IN.FreeLookButton then
		Input.freeLooking = false
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		if Input.freeLooking and not processed then
			Input.lookYaw -= input.Delta.X * CAM.FreeLookSens
			Input.lookPitch = math.clamp(
				Input.lookPitch - input.Delta.Y * CAM.FreeLookSens,
				-math.rad(CAM.LookPitchLimit),
				math.rad(CAM.LookPitchLimit)
			)
		end
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		-- Held as state, not a delta — applied per-frame in update().
		local p = input.Position
		Input.padLook = if math.abs(p.X) > CAM.PadLookDeadzone or math.abs(p.Y) > CAM.PadLookDeadzone
			then Vector2.new(p.X, p.Y)
			else Vector2.zero
	elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
		local p = input.Position
		padSteer = if math.abs(p.X) > CAM.PadLookDeadzone then p.X else 0
		refreshDrive()
	end
end)

--=====================================================================
--  API
--=====================================================================

-- One-shot: true once per press, then cleared.
-- Nitro taps queue rather than latch. Simulation consumes them one per
-- frame, so a fast double-tap escalates two stages instead of being
-- swallowed by whichever frame happened to sample the key.
function Input.consumeItemUse(): boolean
	if Input.itemRequested then
		Input.itemRequested = false
		return true
	end
	return false
end

-- Returns whether an item was fired, and which way. Both keys are
-- drained either way so a queued press can't fire a frame later in the
-- wrong direction.
function Input.consumeItemBack(): boolean
	if Input.itemBackRequested then
		Input.itemBackRequested = false
		return true
	end
	return false
end

function Input.consumeReset(): boolean
	if Input.resetRequested then
		Input.resetRequested = false
		return true
	end
	return false
end

function Input.consumeNitroTap(): boolean
	if Input.nitroTaps > 0 then
		Input.nitroTaps -= 1
		return true
	end
	return false
end

function Input.consumeDriftPress(): boolean
	local pressed = driftPressed
	driftPressed = false
	return pressed
end

-- One-shot: true on the frame look-back toggled.
function Input.consumeCamSnap(): boolean
	local snap = camSnap
	camSnap = false
	return snap
end

-- Right stick orbits continuously; mouse accumulates deltas. Recentres
-- unless the player is actively looking, because a racing camera that
-- stays where you left it is a hazard.
function Input.update(dt: number)
	-- Live wind-up, for the HUD. Separate from itemCharge, which is
	-- latched at the moment of release and read once.
	Input.itemCharging = if itemDownAt > 0
		then math.clamp((os.clock() - itemDownAt) / Config.Items.ThrowChargeTime, 0, 1)
		else 0

	if Input.padLook.Magnitude > 0 then
		Input.lookYaw -= Input.padLook.X * CAM.PadLookSens * dt
		Input.lookPitch = math.clamp(
			Input.lookPitch + Input.padLook.Y * CAM.PadLookSens * dt,
			-math.rad(CAM.LookPitchLimit),
			math.rad(CAM.LookPitchLimit)
		)
	end

	if Input.lookingBack then
		-- Already pinned at pi by the handler; it just holds.
		return
	end
	if not Input.freeLooking and Input.padLook.Magnitude == 0 then
		Input.lookYaw = Util.approachAngle(Input.lookYaw, 0, CAM.LookRecenterRate, dt)
		Input.lookPitch = Util.approach(Input.lookPitch, 0, CAM.LookRecenterRate, dt)
	end
end

function Input.isOrbiting(): boolean
	return Input.freeLooking or Input.padLook.Magnitude > 0
end

function Input.bind(humanoidGetter: () -> Humanoid?)
	getHumanoid = humanoidGetter
	ContextActionService:BindAction(DRIVE_FORWARD_ACTION, driveButton("forward"), false, table.unpack(IN.DriveForwardKeys))
	ContextActionService:BindAction(DRIVE_BACK_ACTION, driveButton("back"), false, table.unpack(IN.DriveBackKeys))
	ContextActionService:BindAction(DRIVE_LEFT_ACTION, driveButton("left"), false, table.unpack(IN.DriveLeftKeys))
	ContextActionService:BindAction(DRIVE_RIGHT_ACTION, driveButton("right"), false, table.unpack(IN.DriveRightKeys))
	ContextActionService:BindAction(LOOKBACK_ACTION, onLookBack, false, table.unpack(IN.LookBackKeys))
	ContextActionService:BindAction(DRIFT_ACTION, onDrift, false, table.unpack(IN.DriftKeys))
	ContextActionService:BindAction(NITRO_ACTION, onNitro, false, table.unpack(IN.NitroKeys))
	ContextActionService:BindAction(RESET_ACTION, onReset, false, table.unpack(Config.Respawn.ResetKeys))
	ContextActionService:BindAction(ITEM_ACTION, onItem, false, table.unpack(Config.Items.UseKeys))
	ContextActionService:BindAction(ITEM_BACK_ACTION, onItemBack, false, table.unpack(Config.Items.UseBackKeys))
	ContextActionService:BindAction(JUMPSINK_ACTION, sink, false, IN.JumpSinkKey)
	if IN.AllowExit then
		ContextActionService:BindAction(EXIT_ACTION, onExit, false, table.unpack(IN.ExitKeys))
	end
end

function Input.unbind()
	ContextActionService:UnbindAction(DRIVE_FORWARD_ACTION)
	ContextActionService:UnbindAction(DRIVE_BACK_ACTION)
	ContextActionService:UnbindAction(DRIVE_LEFT_ACTION)
	ContextActionService:UnbindAction(DRIVE_RIGHT_ACTION)
	ContextActionService:UnbindAction(LOOKBACK_ACTION)
	ContextActionService:UnbindAction(DRIFT_ACTION)
	ContextActionService:UnbindAction(NITRO_ACTION)
	ContextActionService:UnbindAction(RESET_ACTION)
	ContextActionService:UnbindAction(ITEM_ACTION)
	ContextActionService:UnbindAction(ITEM_BACK_ACTION)
	ContextActionService:UnbindAction(JUMPSINK_ACTION)
	ContextActionService:UnbindAction(EXIT_ACTION)
	Input.driftHeld = false
	Input.nitroTaps = 0
	Input.resetRequested = false
	Input.itemRequested = false
	Input.itemBackRequested = false
	Input.itemCharge = 0
	Input.itemCharging = 0
	itemDownAt = 0
	Input.freeLooking = false
	Input.lookingBack = false
	Input.lookYaw, Input.lookPitch = 0, 0
	Input.padLook = Vector2.zero
	Input.touchSteer = 0
	Input.touchThrottle = 0
	Input.driveSteer = 0
	Input.driveThrottle = 0
	driveForward, driveBack, driveLeft, driveRight = false, false, false, false
	padSteer = 0
	driftPressed = false
	camSnap = false
	getHumanoid = nil
end

return Input
