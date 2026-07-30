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
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")

local Config = require(BloxKart:WaitForChild("Config"))
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
}

local function keyName(key: EnumItem?): string
	if not key then
		return "—"
	end
	return PRETTY[key.Name] or key.Name:upper()
end

-- First keyboard binding in a list, falling back to whatever's there.
local function primary(keys: { EnumItem }?): EnumItem?
	if not keys or #keys == 0 then
		return nil
	end
	for _, k in keys do
		if not isGamepad(k) then
			return k
		end
	end
	return keys[1]
end

--=====================================================================
--  BUILD
--=====================================================================
local function resolveFont(): Font
	local ok, font = pcall(function()
		return Font.fromName(H.FontName, H.FontWeight)
	end)
	if ok and font then
		return font
	end
	return Font.fromEnum(Enum.Font.GothamBold)
end

local FONT = resolveFont()

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

	-- Built from the real bindings. Throttle and steer are the seat's
	-- own WASD and aren't rebindable, so those two are literal.
	local rows: { { string } } = {
		{ "W / S", "Throttle / Brake" },
		{ "A / D", "Steer" },
		{ keyName(primary(I.DriftKeys)), "Hop-drift" },
		{ keyName(primary(I.NitroKeys)), "Nitro — tap per tank" },
		{ keyName(primary(Config.Items.UseKeys)), "Use item" },
		{ keyName(primary(I.LookBackKeys)), "Look back" },
		{ keyName(I.FreeLookButton), "Free look" },
	}
	if Config.Match.AllowReadySkip then
		table.insert(rows, { keyName(Config.Match.ReadyKey), "Ready up" })
	end
	if I.AllowExit then
		table.insert(rows, { keyName(primary(I.ExitKeys)), "Exit kart" })
	end
	table.insert(rows, { keyName(H.ControlsToggleKey), "Hide / show" })

	local labels = {}
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
		labels[#labels].Text = row[1]

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
		labels[#labels].Text = row[2]
	end

	panel.Size = UDim2.fromOffset(H.ControlsKeyWidth + 190, #rows * H.ControlsRowHeight)

	local self = setmetatable({
		gui = gui,
		labels = labels,
		visible = true,
		hideThread = nil,
	}, ControlsHud)

	ContextActionService:BindAction(TOGGLE_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			self:Toggle()
		end
		return Enum.ContextActionResult.Sink
	end, false, H.ControlsToggleKey)

	self:_scheduleHide()
	return self
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

function ControlsHud:Destroy()
	if self.hideThread then
		task.cancel(self.hideThread)
		self.hideThread = nil
	end
	ContextActionService:UnbindAction(TOGGLE_ACTION)
	self.gui:Destroy()
end

return ControlsHud
