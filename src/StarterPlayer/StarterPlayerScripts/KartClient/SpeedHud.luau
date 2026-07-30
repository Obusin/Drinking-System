--[[
	SpeedHud — the instrument cluster, bottom right: an analog
	speedometer with a nitro bar under it.

	DRAWN, NOT IMAGED
	-----------------
	Roblox UI has no arc primitive, so the dial is built from rotated
	frames: ticks placed radially around a centre, and a needle swung by
	a symmetrical container. Nothing to author or upload, and it stays
	sharp at any resolution.

	Screen maths note: UI Y grows DOWNWARD, so a standard maths angle
	maps to a position with the sine negated, and a frame's Rotation is
	`90 - angle` because an unrotated tall frame already points "up"
	(maths angle 90).

	Speed and nitro live together because they're one readout — how fast
	am I and how much boost have I banked — and grouping them leaves the
	rest of the screen for the race itself.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")

local Config = require(BloxKart:WaitForChild("Config"))
local Device = require(BloxKart:WaitForChild("Device"))
local Util = require(BloxKart:WaitForChild("Util"))

local H = Config.Hud
local HANDLING = Config.Handling
local NITRO = Config.Nitro

local SpeedHud = {}
SpeedHud.__index = SpeedHud

local FONT = Util.font(H.FontName, H.FontWeight)

local function rampColor(t: number): Color3
	if t < 0.5 then
		return H.SpeedRampLow:Lerp(H.SpeedRampMid, t * 2)
	end
	return H.SpeedRampMid:Lerp(H.SpeedRampHigh, (t - 0.5) * 2)
end

-- Fastest the kart can actually go, so the needle scales to reality
-- rather than pinning. Boost tiers no longer fire on drift release, so
-- the top end is the best burn stage, unless a pad beats it.
local function topSpeed(): number
	local best = HANDLING.MaxSpeed
	local stage = NITRO.Stages[#NITRO.Stages]
	if stage then
		best = math.max(best, HANDLING.MaxSpeed + stage.Speed)
	end
	for _, pad in Config.Boosters.Pads or {} do
		if typeof(pad) == "table" and tonumber(pad.Speed) then
			best = math.max(best, pad.Speed)
		end
	end
	return best
end

-- Fraction along the gauge (0..1) -> standard maths degrees.
local function angleAt(t: number): number
	return H.DialStartAngle - t * H.DialSweep
end

function SpeedHud.new()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- On a phone the bottom-right corner belongs to the DRIFT button, so
	-- the whole cluster moves to bottom centre and the analog dial goes
	-- away. Decided once, here, from the same Device check TouchHud uses —
	-- the two disagreeing is what put the button on top of the dial.
	local mobile = Device.touchLayout()
	local speedPos = if mobile then H.MobileSpeedPosition else H.SpeedPosition
	local speedAnchor = if mobile then H.MobileSpeedAnchor else H.SpeedAnchor
	local nitroPos = if mobile then H.MobileNitroPosition else H.NitroPosition
	local nitroAnchor = if mobile then H.MobileNitroAnchor else H.NitroAnchor
	local nitroSize = if mobile then H.MobileNitroSize else H.NitroSize

	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartSpeed"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	--=============================================================
	--  DIAL
	--=============================================================
	local size = H.DialSize
	local dial = Instance.new("Frame")
	dial.Name = "Dial"
	dial.AnchorPoint = speedAnchor
	dial.Position = speedPos
	dial.Size = UDim2.fromOffset(size, size)
	dial.BackgroundColor3 = H.DialFaceColor
	dial.BackgroundTransparency = H.DialFaceTransparency
	dial.BorderSizePixel = 0
	dial.Parent = gui

	-- CornerRadius at half the width is how you get a circle.
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = dial

	local rim = Instance.new("UIStroke")
	rim.Color = H.DialRimColor
	rim.Thickness = H.DialRimThickness
	rim.Transparency = H.DialRimTransparency
	rim.Parent = dial

	-- Inner bezel ring. Costs one frame and gives the face some depth
	-- instead of reading as a flat coloured circle.
	local bezel = Instance.new("Frame")
	bezel.Name = "Bezel"
	bezel.AnchorPoint = Vector2.new(0.5, 0.5)
	bezel.Position = UDim2.fromScale(0.5, 0.5)
	bezel.Size = UDim2.fromOffset(size - H.DialBezelInset * 2, size - H.DialBezelInset * 2)
	bezel.BackgroundTransparency = 1
	bezel.BorderSizePixel = 0
	bezel.Parent = dial
	local bezelRound = Instance.new("UICorner")
	bezelRound.CornerRadius = UDim.new(0.5, 0)
	bezelRound.Parent = bezel
	local bezelStroke = Instance.new("UIStroke")
	bezelStroke.Color = H.DialBezelColor
	bezelStroke.Thickness = 1
	bezelStroke.Transparency = 0.7
	bezelStroke.Parent = bezel

	-- Ticks. Every DialMajorEvery-th is longer and thicker, and those
	-- majors are where the numerals sit — the rhythm is what makes it
	-- scannable rather than a ring of identical marks.
	local ticks = {}
	local radius = size * H.DialTickRadius
	local numeralRadius = size * H.DialNumeralRadius
	local ceilingDisplay = topSpeed() * H.SpeedScale

	for i = 1, H.DialTicks do
		local t = (i - 1) / (H.DialTicks - 1)
		local deg = angleAt(t)
		local rad = math.rad(deg)
		local major = (i - 1) % H.DialMajorEvery == 0
		local redline = t >= H.DialRedlineFrom

		local tick = Instance.new("Frame")
		tick.Name = (if major then "Major" else "Tick") .. i
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Size = UDim2.fromOffset(
			if major then H.DialMajorWidth else H.DialTickWidth,
			if major then H.DialMajorLength else H.DialTickLength
		)
		-- Negated sine: screen Y grows downward.
		tick.Position = UDim2.new(0.5, math.cos(rad) * radius, 0.5, -math.sin(rad) * radius)
		tick.Rotation = 90 - deg
		tick.BackgroundColor3 = if redline then H.DialRedlineColor else H.SpeedSegmentOff
		tick.BackgroundTransparency = H.SpeedSegmentOffTransparency
		tick.BorderSizePixel = 0
		tick.Parent = dial
		-- Remembered so Update doesn't recompute what's redline or major.
		tick:SetAttribute("Redline", redline)
		table.insert(ticks, tick)

		if major and H.DialNumerals > 0 then
			local n = Instance.new("TextLabel")
			n.Name = "Numeral" .. i
			n.AnchorPoint = Vector2.new(0.5, 0.5)
			n.Position = UDim2.new(0.5, math.cos(rad) * numeralRadius, 0.5, -math.sin(rad) * numeralRadius)
			n.Size = UDim2.fromOffset(30, 14)
			n.BackgroundTransparency = 1
			n.FontFace = FONT
			n.TextSize = H.DialNumeralSize
			n.TextColor3 = H.DialNumeralColor
			-- Upright, never rotated: a numeral you have to tilt your head
			-- for is decoration, not information.
			n.Text = tostring(math.floor(t * ceilingDisplay / 10 + 0.5) * 10)
			n.Parent = dial
		end
	end

	-- The needle hangs inside a container that is CENTRED on the dial and
	-- symmetrical about it, and that container is what rotates.
	--
	-- Rotating the needle itself and relying on AnchorPoint to move the
	-- pivot to its base is the obvious approach and it pivots from the
	-- middle of the needle instead — which reads as broken. A symmetrical
	-- container can only ever pivot at its own centre, which is exactly
	-- where a needle's pivot belongs, so the geometry does the work
	-- rather than the anchor semantics.
	--
	-- Twice the needle's length, with the needle occupying the top half.
	local pivot = Instance.new("Frame")
	pivot.Name = "NeedlePivot"
	pivot.AnchorPoint = Vector2.new(0.5, 0.5)
	pivot.Position = UDim2.fromScale(0.5, 0.5)
	pivot.Size = UDim2.fromOffset(H.NeedleWidth, H.NeedleLength * 2)
	pivot.BackgroundTransparency = 1
	pivot.BorderSizePixel = 0
	pivot.ZIndex = 3
	pivot.Parent = dial

	local needle = Instance.new("Frame")
	needle.Name = "Needle"
	needle.Size = UDim2.new(1, 0, 0.5, 0) -- top half: centre outward
	needle.Position = UDim2.fromScale(0, 0)
	needle.BackgroundColor3 = H.NeedleColor
	needle.BorderSizePixel = 0
	needle.ZIndex = 3
	needle.Parent = pivot

	local needleRound = Instance.new("UICorner")
	needleRound.CornerRadius = UDim.new(0.5, 0)
	needleRound.Parent = needle

	-- Counterweight tail, poking out the far side of the hub. Every real
	-- needle has one and its absence is quietly obvious — a bare stick
	-- rotating about one end is the giveaway.
	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0)
	tail.Position = UDim2.fromScale(0.5, 0.5)
	tail.Size = UDim2.fromOffset(H.NeedleWidth + 2, H.NeedleTail)
	tail.BackgroundColor3 = H.NeedleTailColor
	tail.BorderSizePixel = 0
	tail.ZIndex = 3
	tail.Parent = pivot
	local tailRound = Instance.new("UICorner")
	tailRound.CornerRadius = UDim.new(0.5, 0)
	tailRound.Parent = tail

	local hub = Instance.new("Frame")
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(9, 9)
	hub.BackgroundColor3 = H.NeedleColor
	hub.BorderSizePixel = 0
	hub.ZIndex = 4
	hub.Parent = dial
	local hubRound = Instance.new("UICorner")
	hubRound.CornerRadius = UDim.new(0.5, 0)
	hubRound.Parent = hub

	local function text(parent, name, sizePx, colour, pos, height)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.Size = UDim2.new(1, 0, 0, height)
		l.Position = pos
		l.BackgroundTransparency = 1
		l.FontFace = FONT
		l.TextSize = sizePx
		l.TextColor3 = colour
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		l.TextStrokeTransparency = H.StrokeTransparency
		l.ZIndex = 5
		l.Text = ""
		l.Parent = parent
		return l
	end

	-- Digital readout sits low inside the dial, clear of the needle's
	-- sweep, exactly as the reference does it.
	local readout = text(dial, "Readout", H.SpeedTextSize, H.SpeedTextColor, UDim2.new(0, 0, 0.52, 0), H.SpeedTextSize + 4)
	local unit = text(dial, "Unit", H.SpeedUnitSize, H.SpeedUnitColor, UDim2.new(0, 0, 0.52, H.SpeedTextSize), H.SpeedUnitSize + 4)
	unit.Text = H.SpeedUnit

	-- MOBILE: strip the dial back to just the number.
	--
	-- Hidden rather than never-created, so the desktop build path is
	-- untouched and Update can keep rotating a needle nobody can see
	-- rather than needing a nil check every frame.
	if mobile then
		dial.Size = UDim2.fromOffset(H.MobileSpeedWidth, H.MobileSpeedHeight)
		readout.Position = UDim2.fromOffset(0, 0)
		unit.Position = UDim2.fromOffset(0, H.SpeedTextSize)
		for _, child in dial:GetChildren() do
			if child:IsA("UIStroke") then
				child.Enabled = false -- the rim; Visible does nothing to these
			elseif child:IsA("GuiObject") and child ~= readout and child ~= unit then
				child.Visible = false -- ticks, numerals, bezel, needle pivot
			end
		end
	end

	--=============================================================
	--  NITRO BAR
	--
	--  A CanvasGroup so the whole bar fades on ONE property
	--  (GroupTransparency) instead of tweening every cell, stroke and
	--  label separately — which is what the canister version did.
	--
	--  Cells are laid out by UIListLayout with UIFlexItem Fill, so they
	--  divide the width between themselves. Changing NitroSegments needs
	--  no other edit and no arithmetic.
	--=============================================================
	local barW, barH = nitroSize.X, nitroSize.Y

	local bar = Instance.new("CanvasGroup")
	bar.Name = "Nitro"
	bar.AnchorPoint = nitroAnchor
	bar.Position = nitroPos
	bar.Size = UDim2.fromOffset(barW, barH)
	bar.BackgroundTransparency = 1
	bar.BorderSizePixel = 0
	bar.GroupTransparency = 1 -- hidden until you're in a kart
	bar.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, H.NitroSegmentGap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = bar

	local cells = {}
	for i = 1, H.NitroSegments do
		local cell = Instance.new("Frame")
		cell.Name = "Cell" .. i
		cell.LayoutOrder = i
		cell.Size = UDim2.new(0, 0, 1, 0) -- width comes from the flex below
		cell.BackgroundTransparency = 1
		cell.BorderSizePixel = 0
		cell.Parent = bar

		-- The flex feature doing the work: every cell claims an equal
		-- share of whatever width the bar has.
		local flex = Instance.new("UIFlexItem")
		flex.FlexMode = Enum.UIFlexMode.Fill
		flex.Parent = cell

		local cellRound = Instance.new("UICorner")
		cellRound.CornerRadius = UDim.new(0, H.NitroCornerRadius)
		cellRound.Parent = cell

		local stroke = Instance.new("UIStroke")
		stroke.Color = H.NitroEmptyColor
		stroke.Thickness = H.NitroCellStroke
		stroke.Transparency = H.NitroEmptyTransparency
		stroke.Parent = cell

		-- Fill grows left to right inside its cell, so a partly-earned
		-- bar shows progress rather than snapping full.
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.AnchorPoint = Vector2.new(0, 0.5)
		fill.Position = UDim2.fromScale(0, 0.5)
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = H.NitroFillTop
		fill.BackgroundTransparency = 1
		fill.BorderSizePixel = 0
		fill.Parent = cell

		local fillRound = Instance.new("UICorner")
		fillRound.CornerRadius = UDim.new(0, H.NitroCornerRadius)
		fillRound.Parent = fill

		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new(H.NitroFillTop, H.NitroFillBottom)
		grad.Parent = fill

		table.insert(cells, { cell = cell, stroke = stroke, fill = fill, grad = grad })
	end

	local nitroLabel = Instance.new("TextLabel")
	nitroLabel.Name = "Label"
	nitroLabel.AnchorPoint = Vector2.new(1, 1)
	nitroLabel.Position = UDim2.new(1, 0, 0, -2)
	nitroLabel.Size = UDim2.fromOffset(60, 14)
	nitroLabel.BackgroundTransparency = 1
	nitroLabel.FontFace = FONT
	nitroLabel.TextSize = H.NitroLabelSize
	nitroLabel.TextXAlignment = Enum.TextXAlignment.Right
	nitroLabel.TextColor3 = H.SpeedUnitColor
	nitroLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nitroLabel.TextStrokeTransparency = H.StrokeTransparency
	nitroLabel.Text = H.NitroLabel
	-- Outside the CanvasGroup: a label inside it would fade with the bar
	-- AND get clipped by it.
	nitroLabel.Parent = gui
	nitroLabel.Position = UDim2.new(1, -20, 1, -190)
	nitroLabel.AnchorPoint = Vector2.new(1, 1)

	return setmetatable({
		gui = gui,
		dial = dial,
		rim = rim,
		ticks = ticks,
		pivot = pivot, -- rotated; the needle is its top half
		needle = needle,
		tail = tail,
		hub = hub,
		readout = readout,
		unit = unit,
		bar = bar,
		cells = cells,
		nitroLabel = nitroLabel,
		shown = 0, -- smoothed speed
		needleAngle = H.DialStartAngle,
		charged = 0,
		active = false,
	}, SpeedHud)
end

function SpeedHud:SetActive(active: boolean)
	if self.active == active then
		return
	end
	self.active = active
	self.gui.Enabled = true

	local info = TweenInfo.new(H.SpeedFadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local hide = not active

	local function fade(inst, props)
		TweenService:Create(inst, info, props):Play()
	end

	fade(self.dial, { BackgroundTransparency = if hide then 1 else H.DialFaceTransparency })
	fade(self.rim, { Transparency = if hide then 1 else H.DialRimTransparency })
	fade(self.needle, { BackgroundTransparency = if hide then 1 else 0 })
	fade(self.tail, { BackgroundTransparency = if hide then 1 else 0 })
	fade(self.hub, { BackgroundTransparency = if hide then 1 else 0 })
	-- The entire bar on one property. This is what the CanvasGroup buys:
	-- the canister version had to tween every cell, stroke and trim piece
	-- individually and stay in sync with itself.
	fade(self.bar, { GroupTransparency = if hide then 1 else 0 })

	-- The dial's numerals aren't held as fields, so they're swept by
	-- class instead of individually.
	for _, d in self.dial:GetDescendants() do
		if d:IsA("TextLabel") and d.Name:match("^Numeral") then
			fade(d, { TextTransparency = if hide then 1 else 0 })
		end
	end
	for _, l in { self.readout, self.unit, self.nitroLabel } do
		fade(l, {
			TextTransparency = if hide then 1 else 0,
			TextStrokeTransparency = if hide then 1 else H.StrokeTransparency,
		})
	end
	for _, tick in self.ticks do
		fade(tick, { BackgroundTransparency = if hide then 1 else H.SpeedSegmentOffTransparency })
	end
	-- No per-cell fading: the bar is a CanvasGroup, so the single
	-- GroupTransparency tween above already covers every cell, stroke and
	-- fill inside it. That's the whole reason for the CanvasGroup.

	if not active then
		self.shown = 0
		self.charged = 0
	end
end

function SpeedHud:Update(dt: number, sim)
	----------------------------------------------------------------
	-- Dial
	----------------------------------------------------------------
	self.shown = Util.approach(self.shown, math.abs(sim.speed), H.SpeedSmoothing, dt)
	self.readout.Text = ("%03d"):format(math.floor(self.shown * H.SpeedScale + 0.5))

	local boosting = sim.boosting
	self.readout.TextColor3 = if boosting then H.SpeedBoostColor else H.SpeedTextColor

	-- Scaled to the fastest boost, not MaxSpeed: otherwise the needle
	-- pins exactly when the speed matters most.
	local ceiling = topSpeed()
	local frac = math.clamp(self.shown / ceiling, 0, 1)

	-- The needle chases its target rather than snapping, which is both
	-- how a real one behaves and what stops it twitching at 60fps.
	self.needleAngle = Util.approach(self.needleAngle, angleAt(frac), H.NeedleSmoothing, dt)
	-- The container rotates, not the needle: see the note where it's built.
	self.pivot.Rotation = 90 - self.needleAngle

	local lit = frac * #self.ticks
	for i, tick in self.ticks do
		if i <= lit then
			local t = (i - 1) / math.max(#self.ticks - 1, 1)
			tick.BackgroundColor3 = if boosting then H.SpeedBoostColor else rampColor(t)
			tick.BackgroundTransparency = 0
		else
			-- Unlit redline ticks stay red rather than going grey, so the
			-- top of the gauge always looks like somewhere you earn.
			tick.BackgroundColor3 = if tick:GetAttribute("Redline")
				then H.DialRedlineColor
				else H.SpeedSegmentOff
			tick.BackgroundTransparency = H.SpeedSegmentOffTransparency
		end
	end

	----------------------------------------------------------------
	-- Nitro bar — a persistent reserve, not a drift meter. It shows what
	-- you have banked, so it only moves when you bank or burn.
	----------------------------------------------------------------
	-- Reserve INCLUDES whatever's still draining out of the current burn,
	-- so committing a tank shows it emptying rather than a cell blinking
	-- out of existence.
	local reserve = math.clamp(sim.tanks + sim.fill + sim.burnRemaining, 0, NITRO.MaxTanks)
	self.charged = Util.approach(self.charged, reserve / NITRO.MaxTanks, H.NitroFillRate, dt)

	-- While burning it wears the STAGE colour so you can see what you
	-- committed; otherwise the tier you last banked, matching the sparks.
	local shade = if sim.burning then sim.burnStage else sim.tier
	local tint = H.NitroFillTop
	if shade >= 3 then
		tint = Config.Effects.TierColors[3]
	elseif shade == 2 then
		tint = Config.Effects.TierColors[2]
	elseif shade == 1 then
		tint = Config.Effects.TierColors[1]
	end

	-- One smoothed total drives every cell: cell i shows whatever of the
	-- reserve spills past i-1. Filling and draining then use the same
	-- path, so a burn empties the bar the way drifting fills it.
	local shown = self.charged * NITRO.MaxTanks
	for i, entry in self.cells do
		local amount = math.clamp(shown - (i - 1), 0, 1)

		entry.fill.Size = UDim2.fromScale(amount, 1)
		entry.fill.BackgroundTransparency = if amount > 0.01 then 0 else 1
		entry.grad.Color = ColorSequence.new(tint, tint:Lerp(H.NitroFillBottom, 0.55))

		entry.stroke.Color = if amount > 0.99 then tint else H.NitroEmptyColor
		entry.stroke.Transparency = if amount > 0.99 then 0 else H.NitroEmptyTransparency
	end

	-- Pulses when every bar is full (spend me) and throughout a burn,
	-- faster at higher stages. Brightness, not hue.
	local full = shown >= NITRO.MaxTanks - 0.01
	if full or sim.burning then
		local rate = H.NitroFullPulse * (1 + (if sim.burning then sim.burnStage * 0.5 else 0))
		local pulse = (math.sin(os.clock() * rate * math.pi * 2) + 1) * 0.5
		self.bar.GroupTransparency = 0.05 + pulse * 0.25
	elseif self.active then
		self.bar.GroupTransparency = 0
	end

	-- Label doubles as the stage readout. No extra widget needed.
	self.nitroLabel.Text = if sim.burning then ("N2O %d"):format(sim.burnStage) else H.NitroLabel
end

function SpeedHud:Destroy()
	self.gui:Destroy()
end

return SpeedHud
