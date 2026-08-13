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
local UserInputService = game:GetService("UserInputService")

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
--  MOBILE DRIVING
--=====================================================================
	-- The stock thumbstick is hidden only while seated and replaced with two
	-- kart-only steering buttons. They cannot silently add throttle, drift, or
	-- item input. The right thumb gets deliberate GAS and BRAKE pedals rather
	-- than implicit acceleration.

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
	Gas = function(self, down)
		self.throttling = down
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

local function getPlayerControls()
	local scripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if not (module and module:IsA("ModuleScript")) then
		return nil
	end

	local ok, playerModule = pcall(require, module)
	if ok and playerModule and playerModule.GetControls then
		return playerModule:GetControls()
	end
	warn("[TouchHud] could not obtain PlayerModule controls; Roblox's stock touch controls may stay active.")
	return nil
end

local function restingColour(spec)
	if spec.Color then
		return spec.Color
	end
	if spec.Accent then
		return T.Accent
	end
	if spec.Steer then
		return T.SteerFill
	end
	return T.Fill
end

local function restingTransparency(spec)
	if spec.Transparency ~= nil then
		return spec.Transparency
	end
	return if spec.Accent then T.AccentTransparency else T.FillTransparency
end

function TouchHud.new()
	-- The PlayerModule is disabled only while the mobile kart pad is active.
	-- Leaving it on would add the stock analog stick's VehicleSeat input to our
	-- arrows; disabling it permanently would strand a player on foot in a hub.
	local controls = nil
	-- `wanted()` also covers Studio's mobile layout preview. The emulator can
	-- advertise a keyboard even while rendering an iPhone, so TouchEnabled is
	-- not a reliable gate for obtaining the PlayerModule there.
	if TouchHud.wanted() then
		controls = getPlayerControls()
	end

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
		controls = controls,
		customDriving = true,
		steerLeft = false,
		steerRight = false,
		braking = false,
		throttling = false,
		controlRetryAt = 0,
		alpha = 0,
		active = false,
	}, TouchHud)

	local usingLever = T.Throttle == "lever"

	for _, spec in T.Buttons do
		-- THE LEVER REPLACES THE PEDALS, it does not sit beside them.
		-- Leaving GAS and BRAKE up alongside it would give two controls
		-- writing the same value with no rule for which wins, and put
		-- them under the same thumb the lever needs.
		if usingLever and (spec.Action == "Gas" or spec.Action == "Brake") then
			continue
		end
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
		button.BackgroundColor3 = restingColour(spec)
		button.BackgroundTransparency = restingTransparency(spec)
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
		label.TextSize = if spec.Steer then T.LabelSize * 2.2 elseif spec.Primary then T.LabelSize * 1.5 elseif #tostring(spec.Label) > 2 then T.LabelSize else T.LabelSize * 1.9
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
			button.BackgroundColor3 = if down then (spec.PressedColor or T.FillPressed) else restingColour(spec)
			button.BackgroundTransparency = if down
				then T.FillPressedTransparency
				else restingTransparency(spec)
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

	if usingLever then
		self:_buildLever(root)
	end

	task.defer(function()
		if self.gui.Parent and not self.controls then
			self.controls = getPlayerControls()
			if self.active and self.controls then
				self.controls:Disable()
			end
		end
	end)

	return self
end

--=====================================================================
--  THE THROTTLE LEVER
--
--  One vertical control: forward is gas, centre is neutral, back is
--  brake and then reverse. It replaces the GAS and BRAKE pedals.
--
--  WHY A LEVER RATHER THAN TWO PEDALS. A pedal is held or it is not, so
--  the right thumb is committed to it for the whole race and every item
--  or drift press costs you the power. A lever can be PARKED — set a
--  throttle, take the thumb off, and the kart holds it — which hands
--  that thumb back.
--
--  THE THUMB IS TRACKED THROUGH UserInputService, NOT THE BUTTON.
--
--  A GuiButton only reports motion while the pointer is still over it,
--  and a thumb dragging a lever slides off constantly — especially at
--  the ends of the travel, which is exactly where full gas and full
--  brake live. Capturing the InputObject on press and following THAT
--  until it ends is what makes the ends of the track reachable.
--=====================================================================
function TouchHud:_buildLever(root: Instance)
	local L = T.Lever

	local track = Instance.new("Frame")
	track.Name = "ThrottleLever"
	track.Size = UDim2.fromOffset(L.Size.X, L.Size.Y)
	track.Position = L.Position
	track.AnchorPoint = L.Anchor
	track.BackgroundColor3 = L.TrackFill
	track.BackgroundTransparency = L.TrackTransparency
	track.BorderSizePixel = 0
	track.Parent = root

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, L.Round)
	round.Parent = track

	local stroke = Instance.new("UIStroke")
	stroke.Color = T.Stroke
	stroke.Thickness = T.StrokeThickness
	stroke.Transparency = T.StrokeTransparency
	stroke.Parent = track

	-- Tinted halves, so neutral is findable by eye and not only by feel.
	--
	-- NAMED FIELDS, NOT POSITIONAL. This was written as
	--
	--     for name, tint, y in { { "GasHalf", L.GasTint, 0 }, ... }
	--
	-- which is not the loop it looks like: generalized iteration over an
	-- array yields (index, value), so `name` got 1, `tint` got the inner
	-- TABLE and `y` got nil. It read perfectly and assigned a table to a
	-- Color3. Destructuring in the loop head is the trap; naming the
	-- fields removes it.
	local halves = {
		{ name = "GasHalf", tint = L.GasTint, y = 0 },
		{ name = "BrakeHalf", tint = L.BrakeTint, y = 0.5 },
	}
	for _, spec in halves do
		local half = Instance.new("Frame")
		half.Name = spec.name
		half.Size = UDim2.new(1, 0, 0.5, 0)
		half.Position = UDim2.fromScale(0, spec.y)
		half.BackgroundColor3 = spec.tint
		half.BackgroundTransparency = L.HalfTransparency
		half.BorderSizePixel = 0
		half.ZIndex = 0
		half.Parent = track
	end

	local notch = Instance.new("Frame")
	notch.Name = "Neutral"
	notch.Size = UDim2.new(1, -18, 0, L.NotchThickness)
	notch.Position = UDim2.fromScale(0.5, 0.5)
	notch.AnchorPoint = Vector2.new(0.5, 0.5)
	notch.BackgroundColor3 = L.NotchColor
	notch.BackgroundTransparency = L.NotchTransparency
	notch.BorderSizePixel = 0
	notch.Parent = track

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.Size = UDim2.fromOffset(L.KnobSize.X, L.KnobSize.Y)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.BackgroundColor3 = L.KnobFill
	knob.BackgroundTransparency = L.KnobTransparency
	knob.BorderSizePixel = 0
	knob.ZIndex = 3
	knob.Parent = track

	local knobRound = Instance.new("UICorner")
	knobRound.CornerRadius = UDim.new(0, L.KnobRound)
	knobRound.Parent = knob

	local knobLabel = Instance.new("TextLabel")
	knobLabel.Size = UDim2.fromScale(1, 1)
	knobLabel.BackgroundTransparency = 1
	knobLabel.FontFace = FONT
	knobLabel.TextSize = L.LabelSize
	knobLabel.TextColor3 = Color3.fromRGB(20, 26, 38)
	knobLabel.Text = "N"
	knobLabel.ZIndex = 4
	knobLabel.Parent = knob

	self.lever = {
		track = track,
		knob = knob,
		label = knobLabel,
		-- `value` is where the lever IS, `want` is where the thumb has
		-- asked it to be. Separating them is what lets the knob be
		-- smoothed without the smoothing eating the input.
		value = 0,
		want = 0,
		touch = nil :: InputObject?,
	}

	-- Convert a screen Y into lever travel, +1 at the top, -1 at the
	-- bottom. AbsolutePosition already accounts for the GUI inset.
	local function valueAt(y: number): number
		local top = track.AbsolutePosition.Y
		local height = math.max(track.AbsoluteSize.Y - L.KnobSize.Y, 1)
		local rel = (y - top - L.KnobSize.Y * 0.5) / height
		return math.clamp(1 - rel * 2, -1, 1)
	end

	track.InputBegan:Connect(function(io)
		if io.UserInputType ~= Enum.UserInputType.Touch and io.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		self.lever.touch = io
		self.lever.want = valueAt(io.Position.Y)
		knob.BackgroundColor3 = L.KnobPressed
	end)

	-- Followed globally: a thumb at full brake is usually PAST the
	-- bottom of the track, where the Frame no longer sees it.
	UserInputService.InputChanged:Connect(function(io)
		if self.lever.touch == io then
			self.lever.want = valueAt(io.Position.Y)
		end
	end)

	local function release(io)
		if self.lever.touch == io then
			self.lever.touch = nil
			knob.BackgroundColor3 = L.KnobFill
		end
	end
	UserInputService.InputEnded:Connect(release)
	-- A touch that Roblox cancels (a call, a notification) never fires
	-- InputEnded. Without this the lever would stay latched to a finger
	-- that no longer exists.
	track.InputEnded:Connect(release)
end

--=====================================================================
--  THE LEVER, PER FRAME
--
--  Three positions, and the DETENT is what the thumb aims at, not the
--  raw position. Past a third of the travel the lever commits to that
--  end and snaps there — so full gas and reverse are found by slamming
--  a thumb roughly in the right direction rather than by holding an
--  angle on glass while also steering.
--
--  The snap happens to the TARGET; the knob still eases onto it at
--  FollowRate, which is what makes it read as a switch throwing over
--  rather than teleporting.
--=====================================================================
function TouchHud:_updateLever(dt: number)
	local L = T.Lever
	local lever = self.lever

	-- SNAPPED WHERE THE THUMB IS, so the knob is already travelling to
	-- the detent while the thumb is still moving — the lever leads, the
	-- way a real sprung switch does once it is past centre.
	local detent = 0
	if lever.want >= L.DetentAt then
		detent = 1
	elseif lever.want <= -L.DetentAt then
		detent = -1
	end

	-- Parked levers stay put; a positive ReturnRate springs them back.
	if not lever.touch and L.ReturnRate > 0 then
		lever.want = Util.approach(lever.want, 0, L.ReturnRate, dt)
	end
	lever.value = Util.approach(lever.value, detent, L.FollowRate, dt)

	if detent == 0 then
		-- NEUTRAL. Coasting, not braking — the kart slows on CoastRate,
		-- which is what letting off the gas should do.
		Input.touchThrottle = 0
		lever.label.Text = "N"
	else
		Input.touchThrottle = if detent > 0 then T.GasThrottle else T.BrakeThrottle
		-- One control, and Simulation already decides which of the two
		-- the bottom detent means: it brakes while there is speed to
		-- scrub and reverses once there is not. So the label follows the
		-- kart rather than claiming one of them.
		lever.label.Text = if detent > 0 then "GAS" else "REV"
	end

	-- The knob rides the track. Mapped over the travel MINUS the knob,
	-- so the knob's edges stop at the track's edges instead of half of
	-- it hanging off each end.
	local span = math.max(lever.track.AbsoluteSize.Y - L.KnobSize.Y, 1)
	local pixels = -lever.value * 0.5 * span
	lever.knob.Position = UDim2.new(0.5, 0, 0.5, math.floor(pixels + 0.5))
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
	self.steerLeft = false
	self.steerRight = false
	self.braking = false
	self.throttling = false
	-- THE LEVER GOES BACK TO NEUTRAL. It is deliberately sticky while
	-- driving, which means it would otherwise survive a respawn or a
	-- race end and hand the player a kart already accelerating — the one
	-- way a parked throttle can genuinely hurt.
	if self.lever then
		self.lever.value, self.lever.want, self.lever.touch = 0, 0, nil
		self.lever.label.Text = "N"
		self.lever.knob.Position = UDim2.fromScale(0.5, 0.5)
		self.lever.knob.BackgroundColor3 = T.Lever.KnobFill
	end
end

function TouchHud:SetActive(on: boolean)
	if self.active == on then
		return
	end
	if on and not self.controls then
		self.controls = getPlayerControls()
		if not self.controls then
			self.controlRetryAt = os.clock() + 0.5
			warn("[TouchHud] custom pad shown, but PlayerModule controls are not ready; stock analog may overlap briefly.")
		end
	end
	self.active = on
	self.root.Visible = true -- kept visible while fading out
	if self.controls then
		if on then
			self.controls:Disable()
		else
			self.controls:Enable()
		end
	end
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

	if not self.controls and os.clock() >= (self.controlRetryAt or 0) then
		self.controlRetryAt = os.clock() + 0.5
		self.controls = getPlayerControls()
		if self.controls then
			self.controls:Disable()
		end
	end

	if self.customDriving then
		local targetSteer = if self.steerLeft == self.steerRight then 0 elseif self.steerLeft then -1 else 1
		local rate = if targetSteer == 0 then T.SteerRelease else T.SteerRamp
		Input.touchSteer = Util.approach(Input.touchSteer, targetSteer, rate, dt)
		if self.lever then
			self:_updateLever(dt)
		else
			-- Brake wins if both pedals are touched. That is the safe outcome for
			-- overlapping thumbs and makes reverse/braking an intentional input.
			Input.touchThrottle = if self.braking
				then T.BrakeThrottle
				elseif self.throttling then T.GasThrottle
				else 0
		end
	else
		-- A desktop forced into touch-layout mode is visual testing only; do
		-- not inject a second driving source over keyboard VehicleSeat input.
		Input.touchSteer = 0
		Input.touchThrottle = 0
	end
end

function TouchHud:Destroy()
	self:_releaseAll()
	if self.controls then
		self.controls:Enable()
	end
	self.gui:Destroy()
end

return TouchHud
