--[[
	ControlsHud — the key list, bottom left.

	Rows are built FROM Config.Input rather than typed out, so rebinding
	a key updates what's on screen. A hardcoded controls list is wrong
	the first time anyone changes a binding and nobody notices for weeks.

	Shows on entering a kart, fades after a few seconds, and comes back
	on the toggle key.
--]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")

local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))
local H = Config.Hud
local I = Config.Input

local TOGGLE_ACTION = "KartControlsToggle"

local ControlsHud = {}
ControlsHud.__index = ControlsHud

--=====================================================================
--  KEY NAMES
--=====================================================================

-- Gamepad codes are all prefixed. Used to pick the keyboard binding out
-- of a list that also contains controller equivalents.
local function isGamepad(key: EnumItem): boolean
	local n = key.Name
	return n:sub(1, 6) == "Button" or n:sub(1, 4) == "DPad" or n:sub(1, 10) == "Thumbstick"
end

local PRETTY = {
	Space = "SPACE",
	MouseButton2 = "RMB",
	MouseButton1 = "LMB",
	LeftShift = "SHIFT",
	LeftControl = "CTRL",
	-- Roblox normalises controller input to ButtonX/ButtonR1, but the
	-- plastic says Xbox RB, PlayStation R1, or something else.  Describe
	-- physical positions instead of pretending every pad has Xbox labels.
	ButtonR1 = "R1 / RB",
	ButtonL1 = "L1 / LB",
	ButtonR2 = "R2 / RT",
	ButtonL2 = "L2 / LT",
	ButtonX = "FACE ←",
	ButtonB = "FACE →",
	ButtonY = "FACE ↑",
	ButtonA = "FACE ↓",
	ButtonSelect = "VIEW / −",
	DPadUp = "D-PAD ↑",
	DPadDown = "D-PAD ↓",
}

local function keyName(key: EnumItem?): string
	if not key then
		return "—"
	end
	return PRETTY[key.Name] or key.Name:upper()
end

local function primary(keys: { EnumItem }?, wantGamepad: boolean): EnumItem?
	if not keys or #keys == 0 then
		return nil
	end
	for _, k in keys do
		if isGamepad(k) == wantGamepad then
			return k
		end
	end
	return keys[1]
end

local function isGamepadInput(inputType: Enum.UserInputType): boolean
	return inputType.Name:sub(1, 7) == "Gamepad"
end

local function usingGamepad(): boolean
	return isGamepadInput(UserInputService:GetLastInputType())
end

local FONT = Util.font(H.FontName, H.FontWeight)

local function text(parent: Instance, size: UDim2, pos: UDim2, textSize: number, colour: Color3, align)
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.FontFace = FONT
	l.TextSize = textSize
	l.TextColor3 = colour
	l.TextXAlignment = align
	l.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	l.TextStrokeTransparency = H.StrokeTransparency
	l.Text = ""
	l.Parent = parent
	return l
end

function ControlsHud.new()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartControls"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "Controls"
	panel.AnchorPoint = H.ControlsAnchor
	panel.Position = H.ControlsPosition
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.Parent = gui

	-- Each row keeps both device labels, rather than making a controller
	-- player mentally translate a keyboard overlay.  VehicleSeat owns the
	-- left stick's throttle/brake and steering just as it owns WASD.
	local rows = {
		{ keyboard = "W / S", gamepad = "TRIGGERS", action = "Gas / Brake" },
		{ keyboard = "A / D", gamepad = "LEFT STICK", action = "Steer" },
		{ keyboard = keyName(primary(I.DriftKeys, false)), gamepad = keyName(primary(I.DriftKeys, true)), action = "Hop-drift" },
		{ keyboard = keyName(primary(I.NitroKeys, false)), gamepad = keyName(primary(I.NitroKeys, true)), action = "Nitro — tap per tank" },
		{ keyboard = keyName(primary(Config.Items.UseKeys, false)), gamepad = keyName(primary(Config.Items.UseKeys, true)), action = "Use item — forward" },
		{ keyboard = keyName(primary(Config.Items.UseBackKeys, false)), gamepad = keyName(primary(Config.Items.UseBackKeys, true)), action = "Use item — backward" },
		{ keyboard = keyName(primary(I.LookBackKeys, false)), gamepad = keyName(primary(I.LookBackKeys, true)), action = "Look back (hold)" },
		{ keyboard = keyName(I.FreeLookButton), gamepad = "RIGHT STICK", action = "Free look" },
		{ keyboard = keyName(primary(Config.Respawn.ResetKeys, false)), gamepad = keyName(primary(Config.Respawn.ResetKeys, true)), action = "Reset checkpoint" },
	}
	if Config.Match.AllowReadySkip then
		table.insert(rows, { keyboard = keyName(Config.Match.ReadyKey), gamepad = keyName(Config.Match.ReadyKey), action = "Ready up" })
	end
	if I.AllowExit then
		table.insert(rows, { keyboard = keyName(primary(I.ExitKeys, false)), gamepad = keyName(primary(I.ExitKeys, true)), action = "Exit kart" })
	end
	table.insert(rows, { keyboard = keyName(H.ControlsToggleKey), gamepad = keyName(H.ControlsToggleGamepadKey), action = "Hide / show" })

	local labels = {}
	local keyLabels = {}
	local gamepad = usingGamepad()
	for i, row in rows do
		local y = (i - 1) * H.ControlsRowHeight
		table.insert(
			labels,
			text(
				panel,
				UDim2.fromOffset(H.ControlsKeyWidth, H.ControlsRowHeight),
				UDim2.fromOffset(0, y),
				H.ControlsKeySize,
				H.ControlsKeyColor,
				Enum.TextXAlignment.Left
			)
		)
		labels[#labels].Text = if gamepad then row.gamepad else row.keyboard
		keyLabels[i] = labels[#labels]

		table.insert(
			labels,
			text(
				panel,
				UDim2.fromOffset(190, H.ControlsRowHeight),
				UDim2.fromOffset(H.ControlsKeyWidth, y),
				H.ControlsLabelSize,
				H.ControlsTextColor,
				Enum.TextXAlignment.Left
			)
		)
		labels[#labels].Text = row.action
	end

	panel.Size = UDim2.fromOffset(H.ControlsKeyWidth + 190, #rows * H.ControlsRowHeight)

	local self = setmetatable({
		gui = gui,
		labels = labels,
		keyLabels = keyLabels,
		rows = rows,
		gamepad = gamepad,
		inputConnection = nil,
		visible = true,
		hideThread = nil,
	}, ControlsHud)

	ContextActionService:BindAction(TOGGLE_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			self:Toggle()
		end
		return Enum.ContextActionResult.Sink
	end, false, H.ControlsToggleKey, H.ControlsToggleGamepadKey)

	self.inputConnection = UserInputService.LastInputTypeChanged:Connect(function(inputType)
		-- Touch input should not swap the desktop/controller card while the
		-- mobile HUD has it hidden. Keyboard and mouse both restore keyboard
		-- labels; any Gamepad slot switches to the controller card.
		if inputType == Enum.UserInputType.Keyboard or inputType.Name:sub(1, 5) == "Mouse" or isGamepadInput(inputType) then
			self:_setGamepad(isGamepadInput(inputType))
		end
	end)

	self:_scheduleHide()
	return self
end

function ControlsHud:_setGamepad(gamepad: boolean)
	if self.gamepad == gamepad then
		return
	end
	self.gamepad = gamepad
	for i, row in self.rows do
		self.keyLabels[i].Text = if gamepad then row.gamepad else row.keyboard
	end
end

--=====================================================================
--  VISIBILITY
--=====================================================================
function ControlsHud:_fade(visible: boolean)
	self.visible = visible
	local info = TweenInfo.new(H.ControlsFadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, l in self.labels do
		TweenService:Create(l, info, {
			TextTransparency = if visible then 0 else 1,
			TextStrokeTransparency = if visible then H.StrokeTransparency else 1,
		}):Play()
	end
end

function ControlsHud:_scheduleHide()
	if self.hideThread then
		task.cancel(self.hideThread)
	end
	if H.ControlsShowSeconds <= 0 then
		return
	end
	self.hideThread = task.delay(H.ControlsShowSeconds, function()
		self.hideThread = nil
		self:_fade(false)
	end)
end

function ControlsHud:Toggle()
	-- Toggling on cancels the auto-hide: you asked for it, so it stays
	-- until you dismiss it.
	if self.hideThread then
		task.cancel(self.hideThread)
		self.hideThread = nil
	end
	self:_fade(not self.visible)
end

-- Call when entering a kart, so the list reappears for a beat.
function ControlsHud:Flash()
	self:_fade(true)
	self:_scheduleHide()
end

-- Off when there is no kart. Throttle, steer and hop-drift are not
-- things you can do standing up, and a control list you cannot act on
-- teaches the player that the list is wrong.
function ControlsHud:SetVisible(on: boolean)
	self.gui.Enabled = on
end

function ControlsHud:Destroy()
	if self.hideThread then
		task.cancel(self.hideThread)
		self.hideThread = nil
	end
	ContextActionService:UnbindAction(TOGGLE_ACTION)
	if self.inputConnection then
		self.inputConnection:Disconnect()
		self.inputConnection = nil
	end
	self.gui:Destroy()
end

return ControlsHud
