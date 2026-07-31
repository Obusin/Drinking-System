--[[
	TouchHud — the mobile controls. Built from Config.Touch.Buttons, so
	moving a button is a config edit and adding one is a config row plus a
	line in ACTIONS.

	ROBLOX'S OWN CONTROLS ARE TURNED OFF
	------------------------------------
	Not hidden — disabled, via PlayerModule's Controls object. The default
	thumbstick drives a Humanoid's MoveDirection, which a VehicleSeat then
	reads as throttle and steer. That's a stick you hold at an angle to
	take a corner, which is a much worse shape for a kart than two paddles
	you can slam and let go of.

	Only done on touch devices. On desktop the default controls ARE the
	driving input (the seat reads WASD through them), so disabling them
	there would stop the kart dead.

	EVERY BUTTON GOES THROUGH Input
	-------------------------------
	Nothing here touches Simulation. A touch drift and a Space drift are
	the same event because both call Input.setDrift — including the
	one-shot press flag the hop reads. A parallel touch path is how the
	two quietly diverge and the hop stops working on phones.

	MULTITOUCH
	----------
	Each button is its own GuiButton with its own InputBegan/InputEnded,
	which Roblox tracks per touch point. Steering and drifting at the same
	time works without any coordination here.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Device = require(BloxKart:WaitForChild("Device"))
local Util = require(BloxKart:WaitForChild("Util"))
local Input = require(script.Parent.Input)

local T = Config.Touch
local H = Config.Hud

local TouchHud = {}
TouchHud.__index = TouchHud

--=====================================================================
--  SHOULD WE?
--
--  Shared with every HUD that has to move out of a thumb's way. If this
--  answered differently from SpeedHud's copy, the drift button would land
--  on top of the speedometer — which is precisely what happened when
--  there were two copies.
--=====================================================================
TouchHud.wanted = Device.touchLayout

--=====================================================================
--  DEFAULT CONTROLS
--=====================================================================
-- ROBLOX'S OWN CONTROLS ARE LEFT ALONE, DELIBERATELY.
--
-- This used to disable them and drive the seat from custom paddles plus
-- an auto-throttle. Both were wrong for the same reason: a button can
-- only say "all of it" or "none of it", so steering was full lock or
-- straight, and throttle was pinned open unless you were braking.
--
-- Roblox's touch controller already drives a VehicleSeat with a proper
-- analog stick — throttle, brake and steering, all proportional, all
-- familiar to anyone who has driven anything else on the platform.
-- Writing our own was strictly worse, and deleting it is the fix.
--
-- Simulation adds touchSteer/touchThrottle to what the seat reports, so
-- the stick lands in exactly the same place our paddles did and nothing
-- downstream changes.
--
-- What stays is the half a stick cannot do: drift, nitro, items, reset.

--=====================================================================
--  ACTIONS
--
--  What each Config.Touch button does. `down` is true on press, false on
--  release; tap buttons are only ever called with true.
--=====================================================================
local ACTIONS: { [string]: (self: any, down: boolean) -> () } = {
	Drift = function(_, down)
		Input.setDrift(down)
	end,
	LookBack = function(_, down)
		Input.setLookBack(down)
	end,
	Nitro = function(_, down)
		if down then
			Input.tapNitro()
		end
	end,
	Item = function(_, down)
		if down then
			Input.tapItem()
		end
	end,
	ItemBack = function(_, down)
		if down then
			Input.tapItemBack()
		end
	end,
	Reset = function(_, down)
		if down then
			Input.tapReset()
		end
	end,
}

local FONT = Util.font(H.FontName, H.FontWeight)

function TouchHud.new()
	-- Roblox's own touch controls are left running on purpose; see the
	-- note above the actions. They drive the seat, and these buttons only
	-- add what a stick cannot do.

	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartTouch"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 8 -- above the instruments; you have to be able to
	-- hit these even while the results board is up
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- One CanvasGroup so the whole pad fades on a single property rather
	-- than tweening every button — same trick as the nitro bar.
	local root = Instance.new("CanvasGroup")
	root.Name = "Pad"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.GroupTransparency = 1 -- starts hidden; SetActive fades it in
	root.Visible = false
	root.Parent = gui

	local self = setmetatable({
		gui = gui,
		root = root,
		buttons = {},
		alpha = 0,
		active = false,
	}, TouchHud)

	for _, spec in T.Buttons do
		local action = ACTIONS[spec.Action]
		if not action then
			warn(("[TouchHud] no handler for action %q — button skipped."):format(tostring(spec.Action)))
			continue
		end

		local button = Instance.new("ImageButton")
		button.Name = spec.Action
		button.Size = UDim2.fromOffset(spec.Size.X, spec.Size.Y)
		button.Position = spec.Position
		button.AnchorPoint = spec.Anchor
		button.BackgroundColor3 = if spec.Accent then T.Accent else T.Fill
		button.BackgroundTransparency = if spec.Accent then T.AccentTransparency else T.FillTransparency
		button.AutoButtonColor = false -- we do our own press state, so it
		-- can't fight the accent colour
		button.BorderSizePixel = 0
		button.Image = ""
		button.Parent = root

		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0, spec.Round or 16)
		round.Parent = button

		local stroke = Instance.new("UIStroke")
		stroke.Color = T.Stroke
		stroke.Thickness = T.StrokeThickness
		stroke.Transparency = T.StrokeTransparency
		stroke.Parent = button

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.FontFace = FONT
		label.TextSize = if #tostring(spec.Label) > 2 then T.LabelSize else T.LabelSize * 1.9
		label.TextColor3 = T.LabelColor
		label.Text = spec.Label
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.TextStrokeTransparency = H.StrokeTransparency
		label.Parent = button

		local entry = { button = button, spec = spec }
		table.insert(self.buttons, entry)

		local function press(down: boolean)
			-- Held buttons must always be released. A tap button releasing
			-- would fire twice, so those only ever see `true`.
			if spec.Hold or down then
				action(self, down)
			end
			button.BackgroundColor3 = if down
				then T.FillPressed
				elseif spec.Accent then T.Accent
				else T.Fill
			button.BackgroundTransparency = if down
				then T.FillPressedTransparency
				elseif spec.Accent then T.AccentTransparency
				else T.FillTransparency
		end
		entry.press = press

		button.InputBegan:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
				press(true)
			end
		end)
		-- Both, because a thumb that slides off the button fires Ended
		-- somewhere else entirely — without InputEnded on the button AND a
		-- release on deactivate, a paddle can stick on full lock.
		button.InputEnded:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
				press(false)
			end
		end)
	end

	return self
end

--=====================================================================
--  FRAME
--=====================================================================

-- Releases everything. Called when the pad hides, so a button held at
-- the moment you leave the kart can't leave steering latched over.
function TouchHud:_releaseAll()
	for _, entry in self.buttons do
		if entry.spec.Hold then
			entry.press(false)
		end
	end
	Input.touchSteer = 0
	Input.touchThrottle = 0
end

function TouchHud:SetActive(on: boolean)
	if self.active == on then
		return
	end
	self.active = on
	self.root.Visible = true -- kept visible while fading out
	if not on then
		self:_releaseAll()
	end
end

function TouchHud:Update(dt: number)
	-- Fade, and stop rendering entirely once fully hidden.
	local target = if self.active then 0 else 1
	self.alpha = Util.approach(self.alpha, target, 1 / math.max(T.FadeTime, 0.01), dt)
	self.root.GroupTransparency = self.alpha
	if not self.active and self.alpha > 0.99 then
		self.root.Visible = false
	end

	if not self.active then
		return
	end

	-- STEERING AND THROTTLE COME FROM THE SEAT NOW.
	--
	-- Roblox's touch controller writes SteerFloat and ThrottleFloat
	-- directly, and Simulation already reads those. Adding anything here
	-- would double up on the stick rather than help it.
	Input.touchSteer = 0
	Input.touchThrottle = 0
end

function TouchHud:Destroy()
	self:_releaseAll()
	self.gui:Destroy()
end

return TouchHud
