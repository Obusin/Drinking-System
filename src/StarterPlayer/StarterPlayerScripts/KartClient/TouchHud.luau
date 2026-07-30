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
local function disableDefaultControls()
	-- Wrapped: PlayerModule is Roblox's own script and its shape has
	-- changed before. Losing our buttons is bad; throwing here would lose
	-- the whole client script.
	local ok, err = pcall(function()
		local scripts = Players.LocalPlayer:WaitForChild("PlayerScripts", 10)
		local module = scripts and scripts:WaitForChild("PlayerModule", 10)
		if not module then
			return
		end
		require(module):GetControls():Disable()
	end)
	if not ok then
		warn("[TouchHud] could not disable the default controls: " .. tostring(err))
	end
end

--=====================================================================
--  ACTIONS
--
--  What each Config.Touch button does. `down` is true on press, false on
--  release; tap buttons are only ever called with true.
--=====================================================================
local ACTIONS: { [string]: (self: any, down: boolean) -> () } = {
	SteerLeft = function(self, down)
		self.steerLeft = down
	end,
	SteerRight = function(self, down)
		self.steerRight = down
	end,
	Brake = function(self, down)
		self.braking = down
	end,
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
	Reset = function(_, down)
		if down then
			Input.tapReset()
		end
	end,
}

local FONT = Util.font(H.FontName, H.FontWeight)

function TouchHud.new()
	-- Before anything else: the default stick has to stop driving the seat
	-- or it fights our paddles for the same throttle/steer values.
	disableDefaultControls()

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
		steerLeft = false,
		steerRight = false,
		braking = false,
		steer = 0,
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
	self.steerLeft, self.steerRight, self.braking = false, false, false
	self.steer = 0
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

	-- Both paddles held cancels out, which is the intuitive result and
	-- also what stops a stuck paddle locking you into a circle.
	local wantSteer = (if self.steerRight then 1 else 0) - (if self.steerLeft then 1 else 0)
	local rate = if wantSteer == 0 then T.SteerReturn else T.SteerRamp
	self.steer = Util.approach(self.steer, wantSteer, rate, dt)
	Input.touchSteer = self.steer

	-- Auto throttle: you're always accelerating unless you're braking.
	-- See Config.Touch for why there's no accelerator button.
	if T.AutoThrottle then
		Input.touchThrottle = if self.braking then T.BrakeStrength else 1
	else
		Input.touchThrottle = if self.braking then T.BrakeStrength else 0
	end
end

function TouchHud:Destroy()
	self:_releaseAll()
	self.gui:Destroy()
end

return TouchHud
