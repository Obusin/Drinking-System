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

local Input = {
	-- Touch steering / throttle. Added to whatever the VehicleSeat
	-- reports rather than replacing it, so a device with both a
	-- touchscreen and a keyboard works with either, and the desktop path
	-- is bit-for-bit unchanged when these stay 0.
	touchSteer = 0,
	touchThrottle = 0,

	driftHeld = false,
	nitroTaps = 0, -- queued, consumed one per frame by Simulation
	resetRequested = false,
	itemRequested = false,
	itemBackRequested = false,
	freeLooking = false,
	lookingBack = false,
	lookYaw = 0,
	lookPitch = 0,
	padLook = Vector2.zero,
}

local driftPressed = false
local camSnap = false
local getHumanoid: (() -> Humanoid?)? = nil

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

local function onItem(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		Input.itemRequested = true
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

function Input.tapItem()
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
	Input.freeLooking = false
	Input.lookingBack = false
	Input.lookYaw, Input.lookPitch = 0, 0
	Input.padLook = Vector2.zero
	Input.touchSteer = 0
	Input.touchThrottle = 0
	driftPressed = false
	camSnap = false
	getHumanoid = nil
end

return Input
