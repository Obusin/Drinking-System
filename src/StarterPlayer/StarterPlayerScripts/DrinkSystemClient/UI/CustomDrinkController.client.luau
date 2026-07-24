-- CustomDrinkController — Drink Lab UI
-- Amber bar-theme: ingredient chips, color preview, animated open.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystem:WaitForChild("Config")
local SharedModules = DrinkSystem:WaitForChild("SharedModules")

local Settings = require(ConfigFolder:WaitForChild("Settings"))
local IngredientRegistry = require(SharedModules:WaitForChild("IngredientRegistry"))
local Network = require(SharedModules:WaitForChild("Network"))
local Packets = Network.Packets

-- ── Constants ─────────────────────────────────────────────────────────────

local MAX_PICKS           = 6
local MIN_PICKS           = 4
local STRONGNESS_MIN      = 5
local STRONGNESS_HARD_CAP = 75
local DURATION_OPTIONS    = { 4, 8, 12, 24 }
local MAX_ACTIVE          = 5

local COLOR_SWATCHES = {
	Color3.fromRGB(235, 80,  70),
	Color3.fromRGB(255, 146, 76),
	Color3.fromRGB(255, 205, 80),
	Color3.fromRGB(140, 220, 140),
	Color3.fromRGB(60,  170, 110),
	Color3.fromRGB(100, 180, 255),
	Color3.fromRGB(91,  120, 255),
	Color3.fromRGB(170, 110, 240),
	Color3.fromRGB(230, 120, 200),
	Color3.fromRGB(150, 102, 79),
	Color3.fromRGB(40,  40,  50),
	Color3.fromRGB(235, 215, 180),
}

-- ── Palette ───────────────────────────────────────────────────────────────

local C = {
	BG         = Color3.fromRGB(10,  10,  14),
	Surface    = Color3.fromRGB(18,  17,  24),
	Surface2   = Color3.fromRGB(26,  25,  36),
	Header     = Color3.fromRGB(14,  13,  20),
	Accent     = Color3.fromRGB(196, 158, 58),   -- brass amber
	AccentDim  = Color3.fromRGB(44,  36,  13),   -- dark amber bg for chips
	AccentBdr  = Color3.fromRGB(88,  70,  22),   -- amber border
	Success    = Color3.fromRGB(52,  156, 82),
	Warn       = Color3.fromRGB(200, 140, 30),
	Danger     = Color3.fromRGB(205, 65,  55),
	Buy        = Color3.fromRGB(130, 100, 20),
	Text       = Color3.fromRGB(236, 232, 220),  -- warm off-white
	TextSub    = Color3.fromRGB(148, 144, 158),
	TextMute   = Color3.fromRGB(72,  70,  86),
	Divider    = Color3.fromRGB(40,  38,  55),
}

-- ── State ─────────────────────────────────────────────────────────────────

local tokenHours: { number } = {}
local activeCount      = 0
local picks: { string } = {}
local chosenColor      = COLOR_SWATCHES[3]
local chosenHours      = 24
local chosenStrongness = 40

-- forward declaration so closures inside rebuildChips / swatch buttons can
-- reference refreshViewport before its real body is assigned below
local refreshViewport: () -> () = function() end

-- ── UI helpers ────────────────────────────────────────────────────────────

local function addCorner(inst: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end

local function addStroke(inst: GuiObject, col: Color3, t: number, tr: number?)
	local s = Instance.new("UIStroke")
	s.Color = col
	s.Thickness = t
	s.Transparency = tr or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

local function mkLabel(
	parent: GuiObject,
	text: string,
	size: number,
	bold: boolean,
	col: Color3?
): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = bold and Enum.Font.MontserratBold or Enum.Font.Montserrat
	l.TextSize = size
	l.TextColor3 = col or C.Text
	l.Text = text
	l.Parent = parent
	return l
end

local function mkSectionLabel(parent: GuiObject, text: string, y: number): TextLabel
	local l = mkLabel(parent, text, 9, true, C.TextMute)
	l.Position = UDim2.new(0, 2, 0, y)
	l.Size = UDim2.new(1, 0, 0, 13)
	l.TextXAlignment = Enum.TextXAlignment.Left
	return l
end

-- ── Root GUI ──────────────────────────────────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name = "DS_DrinkLab"
gui.ResetOnSpawn = false
gui.DisplayOrder = 59
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

-- ── Toggle button ─────────────────────────────────────────────────────────

local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "Toggle"
toggleBtn.AnchorPoint = Vector2.new(1, 0.5)
toggleBtn.Position = UDim2.new(1, -12, 0.5, 54)
toggleBtn.Size = UDim2.new(0, 88, 0, 44)
toggleBtn.BackgroundColor3 = C.AccentDim
toggleBtn.BorderSizePixel = 0
toggleBtn.Font = Enum.Font.MontserratBold
toggleBtn.TextSize = 13
toggleBtn.TextColor3 = C.Accent
toggleBtn.Text = "Drink Lab"
toggleBtn.TextWrapped = true
toggleBtn.Parent = gui
addCorner(toggleBtn, 12)
addStroke(toggleBtn, C.Accent, 1.5)

-- ── Panel ─────────────────────────────────────────────────────────────────

local PW, PH = 700, 580
local HDR_H  = 48
local PAD    = 12
local LW     = 384   -- left column width
local RW     = 276   -- right column width
-- LW + RW + 3×PAD = 384 + 276 + 3×12 = 696 ≈ 700 ✓
local RX     = PAD + LW + PAD   -- right column x offset = 408

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.new(0, PW, 0, PH)
panel.BackgroundColor3 = C.BG
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
addCorner(panel, 16)
addStroke(panel, C.Divider, 1)

-- Header bar
local hdr = Instance.new("Frame")
hdr.Size = UDim2.new(1, 0, 0, HDR_H)
hdr.BackgroundColor3 = C.Header
hdr.BorderSizePixel = 0
hdr.ZIndex = 4
hdr.Parent = panel
addCorner(hdr, 16)
-- Mask bottom two corners of header so it merges into panel
local hdrMask = Instance.new("Frame")
hdrMask.AnchorPoint = Vector2.new(0, 1)
hdrMask.Position = UDim2.new(0, 0, 1, 0)
hdrMask.Size = UDim2.new(1, 0, 0, 16)
hdrMask.BackgroundColor3 = C.Header
hdrMask.BorderSizePixel = 0
hdrMask.ZIndex = 4
hdrMask.Parent = hdr
-- Amber rule under header
local hdrLine = Instance.new("Frame")
hdrLine.AnchorPoint = Vector2.new(0, 1)
hdrLine.Position = UDim2.new(0, 0, 1, 0)
hdrLine.Size = UDim2.new(1, 0, 0, 1)
hdrLine.BackgroundColor3 = C.Accent
hdrLine.BackgroundTransparency = 0.45
hdrLine.BorderSizePixel = 0
hdrLine.ZIndex = 5
hdrLine.Parent = hdr

local hdrTitle = mkLabel(hdr, "Drink Lab", 17, true, C.Accent)
hdrTitle.AnchorPoint = Vector2.new(0, 0.5)
hdrTitle.Position = UDim2.new(0, 18, 0.5, 0)
hdrTitle.Size = UDim2.new(0, 200, 1, 0)
hdrTitle.TextXAlignment = Enum.TextXAlignment.Left
hdrTitle.ZIndex = 5

local hdrSlotCount = mkLabel(hdr, "", 11, false, C.TextMute)
hdrSlotCount.AnchorPoint = Vector2.new(1, 0.5)
hdrSlotCount.Position = UDim2.new(1, -50, 0.5, 0)
hdrSlotCount.Size = UDim2.new(0, 150, 1, 0)
hdrSlotCount.TextXAlignment = Enum.TextXAlignment.Right
hdrSlotCount.ZIndex = 5

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -10, 0.5, 0)
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.BackgroundColor3 = Color3.fromRGB(32, 28, 34)
closeBtn.BorderSizePixel = 0
closeBtn.Font = Enum.Font.MontserratBold
closeBtn.TextSize = 13
closeBtn.TextColor3 = C.TextSub
closeBtn.Text = "✕"
closeBtn.ZIndex = 6
closeBtn.Parent = hdr
addCorner(closeBtn, 7)

-- ── Composer — left column ────────────────────────────────────────────────

local composer = Instance.new("Frame")
composer.Position = UDim2.new(0, PAD, 0, HDR_H + PAD)
composer.Size = UDim2.new(0, LW, 1, -(HDR_H + PAD * 2))
composer.BackgroundTransparency = 1
composer.Parent = panel

-- Name input
local nameBox = Instance.new("TextBox")
nameBox.Size = UDim2.new(1, 0, 0, 36)
nameBox.BackgroundColor3 = C.Surface2
nameBox.BorderSizePixel = 0
nameBox.Font = Enum.Font.Montserrat
nameBox.PlaceholderText = "Name your drink…"
nameBox.PlaceholderColor3 = C.TextMute
nameBox.Text = ""
nameBox.TextSize = 15
nameBox.TextColor3 = C.Text
nameBox.ClearTextOnFocus = false
nameBox.Parent = composer
addCorner(nameBox, 10)
addStroke(nameBox, C.Divider, 1)
local namePad = Instance.new("UIPadding")
namePad.PaddingLeft = UDim.new(0, 12)
namePad.PaddingRight = UDim.new(0, 12)
namePad.Parent = nameBox

-- Picks chips row
local chipsOuter = Instance.new("Frame")
chipsOuter.Position = UDim2.new(0, 0, 0, 44)
chipsOuter.Size = UDim2.new(1, 0, 0, 38)
chipsOuter.BackgroundColor3 = C.Surface
chipsOuter.BorderSizePixel = 0
chipsOuter.ClipsDescendants = true
chipsOuter.Parent = composer
addCorner(chipsOuter, 9)
addStroke(chipsOuter, C.Divider, 1)

local chipsScroll = Instance.new("ScrollingFrame")
chipsScroll.Size = UDim2.fromScale(1, 1)
chipsScroll.BackgroundTransparency = 1
chipsScroll.BorderSizePixel = 0
chipsScroll.ScrollBarThickness = 0
chipsScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
chipsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
chipsScroll.ScrollingDirection = Enum.ScrollingDirection.X
chipsScroll.Parent = chipsOuter
local chipsLayout = Instance.new("UIListLayout")
chipsLayout.FillDirection = Enum.FillDirection.Horizontal
chipsLayout.Padding = UDim.new(0, 5)
chipsLayout.SortOrder = Enum.SortOrder.LayoutOrder
chipsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
chipsLayout.Parent = chipsScroll
local chipsPad = Instance.new("UIPadding")
chipsPad.PaddingLeft = UDim.new(0, 10)
chipsPad.PaddingRight = UDim.new(0, 10)
chipsPad.Parent = chipsScroll

local chipsEmpty = mkLabel(chipsScroll, "Pick 4–6 ingredients below", 12, false, C.TextMute)
chipsEmpty.Name = "_empty"
chipsEmpty.Size = UDim2.new(0, 240, 1, 0)
chipsEmpty.LayoutOrder = 0

-- Ingredient grid
mkSectionLabel(composer, "INGREDIENTS", 89)

local grid = Instance.new("ScrollingFrame")
grid.Position = UDim2.new(0, 0, 0, 105)
grid.Size = UDim2.new(1, 0, 0, 172)
grid.BackgroundTransparency = 1
grid.BorderSizePixel = 0
grid.ScrollBarThickness = 3
grid.ScrollBarImageColor3 = C.Divider
grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
grid.CanvasSize = UDim2.new(0, 0, 0, 0)
grid.Parent = composer
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0, 88, 0, 25)
gridLayout.CellPadding = UDim2.new(0, 5, 0, 5)
gridLayout.SortOrder = Enum.SortOrder.Name
gridLayout.Parent = grid

-- Color section
local COLOR_Y = 283
mkSectionLabel(composer, "DRINK COLOR", COLOR_Y)

-- Preview circle (tracks chosenColor live)
local colorPreview = Instance.new("Frame")
colorPreview.AnchorPoint = Vector2.new(1, 0)
colorPreview.Position = UDim2.new(1, 0, 0, COLOR_Y - 2)
colorPreview.Size = UDim2.new(0, 22, 0, 22)
colorPreview.BackgroundColor3 = chosenColor
colorPreview.BorderSizePixel = 0
colorPreview.Parent = composer
addCorner(colorPreview, 11)
addStroke(colorPreview, Color3.fromRGB(180, 180, 180), 1.5, 0.5)

local swatchRow = Instance.new("Frame")
swatchRow.Position = UDim2.new(0, 0, 0, COLOR_Y + 17)
swatchRow.Size = UDim2.new(1, 0, 0, 28)
swatchRow.BackgroundTransparency = 1
swatchRow.Parent = composer
local swatchLayout = Instance.new("UIListLayout")
swatchLayout.FillDirection = Enum.FillDirection.Horizontal
swatchLayout.Padding = UDim.new(0, 5)
swatchLayout.VerticalAlignment = Enum.VerticalAlignment.Center
swatchLayout.Parent = swatchRow

-- Drunkness / strength slider
local SLIDER_Y = COLOR_Y + 52
mkSectionLabel(composer, "DRUNKNESS", SLIDER_Y)

local sliderVal = mkLabel(composer, "", 11, false, C.TextSub)
sliderVal.AnchorPoint = Vector2.new(1, 0)
sliderVal.Position = UDim2.new(1, 0, 0, SLIDER_Y - 1)
sliderVal.Size = UDim2.new(0, 160, 0, 13)
sliderVal.TextXAlignment = Enum.TextXAlignment.Right

local track = Instance.new("Frame")
track.Position = UDim2.new(0, 0, 0, SLIDER_Y + 18)
track.Size = UDim2.new(1, 0, 0, 8)
track.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
track.BorderSizePixel = 0
track.Parent = composer
addCorner(track, 4)

local fill = Instance.new("Frame")
fill.Size = UDim2.new(0, 0, 1, 0)
fill.BackgroundColor3 = C.Success
fill.BorderSizePixel = 0
fill.Parent = track
addCorner(fill, 4)

local knob = Instance.new("TextButton")
knob.AnchorPoint = Vector2.new(0.5, 0.5)
knob.Position = UDim2.new(0, 0, 0.5, 0)
knob.Size = UDim2.new(0, 18, 0, 18)
knob.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
knob.BorderSizePixel = 0
knob.Text = ""
knob.ZIndex = 3
knob.Parent = track
addCorner(knob, 9)

-- Duration
local DUR_Y = SLIDER_Y + 38
mkSectionLabel(composer, "DURATION", DUR_Y)

local durationRow = Instance.new("Frame")
durationRow.Position = UDim2.new(0, 0, 0, DUR_Y + 17)
durationRow.Size = UDim2.new(1, 0, 0, 33)
durationRow.BackgroundTransparency = 1
durationRow.Parent = composer
local durLayout = Instance.new("UIListLayout")
durLayout.FillDirection = Enum.FillDirection.Horizontal
durLayout.Padding = UDim.new(0, 6)
durLayout.Parent = durationRow

-- Result / status / submit
local resultLabel = mkLabel(composer, "", 12, false, C.TextSub)
resultLabel.AnchorPoint = Vector2.new(0, 1)
resultLabel.Position = UDim2.new(0, 0, 1, -54)
resultLabel.Size = UDim2.new(1, 0, 0, 24)
resultLabel.TextWrapped = true
resultLabel.TextXAlignment = Enum.TextXAlignment.Left

local statusLabel = mkLabel(composer, "", 11, false, C.TextMute)
statusLabel.AnchorPoint = Vector2.new(0, 1)
statusLabel.Position = UDim2.new(0, 0, 1, -32)
statusLabel.Size = UDim2.new(1, 0, 0, 18)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left

local submitBtn = Instance.new("TextButton")
submitBtn.AnchorPoint = Vector2.new(0, 1)
submitBtn.Position = UDim2.new(0, 0, 1, -2)
submitBtn.Size = UDim2.new(1, 0, 0, 40)
submitBtn.BackgroundColor3 = C.Success
submitBtn.BorderSizePixel = 0
submitBtn.Font = Enum.Font.MontserratBold
submitBtn.TextSize = 14
submitBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
submitBtn.Text = "Create Drink"
submitBtn.Parent = composer
addCorner(submitBtn, 10)

-- ── On the Menu — right column ─────────────────────────────────────────────

local VP_H = 238  -- height of the 3-D drink preview viewport

local liveCol = Instance.new("Frame")
liveCol.Position = UDim2.new(0, RX, 0, HDR_H + PAD)
liveCol.Size = UDim2.new(0, RW, 1, -(HDR_H + PAD * 2))
liveCol.BackgroundColor3 = C.Surface
liveCol.BorderSizePixel = 0
liveCol.Parent = panel
addCorner(liveCol, 12)
addStroke(liveCol, C.Divider, 1)

-- Right column mini-header
local liveHdr = Instance.new("Frame")
liveHdr.Size = UDim2.new(1, 0, 0, 40)
liveHdr.BackgroundColor3 = C.Header
liveHdr.BorderSizePixel = 0
liveHdr.ZIndex = 2
liveHdr.Parent = liveCol
addCorner(liveHdr, 12)
local liveHdrMask = Instance.new("Frame")
liveHdrMask.AnchorPoint = Vector2.new(0, 1)
liveHdrMask.Position = UDim2.new(0, 0, 1, 0)
liveHdrMask.Size = UDim2.new(1, 0, 0, 12)
liveHdrMask.BackgroundColor3 = C.Header
liveHdrMask.BorderSizePixel = 0
liveHdrMask.ZIndex = 2
liveHdrMask.Parent = liveHdr
local liveTitleLine = Instance.new("Frame")
liveTitleLine.AnchorPoint = Vector2.new(0, 1)
liveTitleLine.Position = UDim2.new(0, 0, 1, 0)
liveTitleLine.Size = UDim2.new(1, 0, 0, 1)
liveTitleLine.BackgroundColor3 = C.Accent
liveTitleLine.BackgroundTransparency = 0.55
liveTitleLine.BorderSizePixel = 0
liveTitleLine.ZIndex = 3
liveTitleLine.Parent = liveHdr
local liveTitle = mkLabel(liveHdr, "On the Menu", 13, true, C.Accent)
liveTitle.AnchorPoint = Vector2.new(0, 0.5)
liveTitle.Position = UDim2.new(0, 14, 0.5, 0)
liveTitle.Size = UDim2.new(1, -16, 1, 0)
liveTitle.TextXAlignment = Enum.TextXAlignment.Left
liveTitle.ZIndex = 3

-- ── 3-D drink preview ─────────────────────────────────────────────────────

local viewport = Instance.new("ViewportFrame")
viewport.Position = UDim2.new(0, 0, 0, 40)
viewport.Size = UDim2.new(1, 0, 0, VP_H)
viewport.BackgroundColor3 = Color3.fromRGB(7, 6, 11)
viewport.BorderSizePixel = 0
viewport.LightColor = Color3.fromRGB(245, 232, 210)
viewport.LightDirection = Vector3.new(-1, -2, -0.8)
viewport.Ambient = Color3.fromRGB(48, 44, 60)
viewport.ZIndex = 1
viewport.Parent = liveCol

local vpWorldModel = Instance.new("WorldModel")
vpWorldModel.Parent = viewport

local vpCamera = Instance.new("Camera")
vpCamera.FieldOfView = 42
vpCamera.Parent = viewport
viewport.CurrentCamera = vpCamera

-- Bottom-fade label overlay (drink name + count)
local vpOverlay = Instance.new("Frame")
vpOverlay.AnchorPoint = Vector2.new(0, 1)
vpOverlay.Position = UDim2.new(0, 0, 1, 0)
vpOverlay.Size = UDim2.new(1, 0, 0, 52)
vpOverlay.BackgroundColor3 = C.Surface
vpOverlay.BackgroundTransparency = 1
vpOverlay.BorderSizePixel = 0
vpOverlay.ZIndex = 2
vpOverlay.Parent = viewport
local vpGrad = Instance.new("UIGradient")
vpGrad.Rotation = 90
vpGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.05),
	NumberSequenceKeypoint.new(1, 1),
})
vpGrad.Parent = vpOverlay

local vpLabel = mkLabel(vpOverlay, "Design your drink →", 11, false, C.TextMute)
vpLabel.AnchorPoint = Vector2.new(0, 1)
vpLabel.Position = UDim2.new(0, 12, 1, -9)
vpLabel.Size = UDim2.new(1, -16, 0, 14)
vpLabel.TextXAlignment = Enum.TextXAlignment.Left
vpLabel.ZIndex = 3

-- Amber rule between viewport and live list
local vpRule = Instance.new("Frame")
vpRule.Position = UDim2.new(0, 0, 0, 40 + VP_H)
vpRule.Size = UDim2.new(1, 0, 0, 1)
vpRule.BackgroundColor3 = C.Accent
vpRule.BackgroundTransparency = 0.65
vpRule.BorderSizePixel = 0
vpRule.Parent = liveCol

local liveScroll = Instance.new("ScrollingFrame")
liveScroll.Position = UDim2.new(0, 7, 0, 40 + VP_H + 6)
liveScroll.Size = UDim2.new(1, -14, 1, -(40 + VP_H + 12))
liveScroll.BackgroundTransparency = 1
liveScroll.BorderSizePixel = 0
liveScroll.ScrollBarThickness = 3
liveScroll.ScrollBarImageColor3 = C.Divider
liveScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
liveScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
liveScroll.Parent = liveCol
local liveLayout = Instance.new("UIListLayout")
liveLayout.Padding = UDim.new(0, 6)
liveLayout.SortOrder = Enum.SortOrder.LayoutOrder
liveLayout.Parent = liveScroll
local livePad = Instance.new("UIPadding")
livePad.PaddingTop = UDim.new(0, 4)
livePad.PaddingBottom = UDim.new(0, 4)
livePad.Parent = liveScroll

-- ── Viewport glass setup ──────────────────────────────────────────────────

local vpGlassLiquid: BasePart? = nil
local vpCenter      = Vector3.zero
local vpRadius      = 4.0
local vpBias        = 0.2
local vpAngle       = 0
local vpIsProcedural  = false
local vpTargetFillH   = 0.1   -- driven by refreshViewport
local vpCurrentFillH  = 0.1   -- lerped toward target each Heartbeat

-- Procedural glass geometry constants (cylinder rotated 90° around Z)
local VP_LIQ_ROT   = CFrame.Angles(0, 0, math.rad(90))
local VP_LIQ_DIAM  = 0.78   -- diameter of liquid cylinder
local VP_LIQ_BOT   = -1.02  -- Y of liquid centre when height ≈ 0
local VP_LIQ_MAX_H = 1.82   -- height at level 3 (full)

local function buildFallbackGlass(): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "DS_VPGlass"
	local function mk(): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CastShadow = false
		return p
	end
	-- upright cylinder: Roblox cylinders extend along local X,
	-- so rotate 90° around Z to make them stand upright
	local rot = CFrame.Angles(0, 0, math.rad(90))
	-- SmoothPlastic (not Glass) — Glass material is reflective in ViewportFrame
	-- and hides anything inside it.
	local body = mk()
	body.Name = "Body"
	body.Shape = Enum.PartType.Cylinder
	body.Size = Vector3.new(2.2, 1.0, 1.0)
	body.CFrame = rot
	body.Material = Enum.Material.SmoothPlastic
	body.Color = Color3.fromRGB(195, 222, 255)
	body.Transparency = 0.80
	body.Parent = model
	local base = mk()
	base.Shape = Enum.PartType.Cylinder
	base.Size = Vector3.new(0.12, 1.2, 1.2)
	base.CFrame = CFrame.new(0, -1.16, 0) * rot
	base.Material = Enum.Material.SmoothPlastic
	base.Color = Color3.fromRGB(195, 222, 255)
	base.Transparency = 0.65
	base.Parent = model
	local liquid = mk()
	liquid.Name = "Liquid"
	liquid.Shape = Enum.PartType.Cylinder
	liquid.Size = Vector3.new(vpCurrentFillH, VP_LIQ_DIAM, VP_LIQ_DIAM)
	liquid.CFrame = CFrame.new(0, VP_LIQ_BOT + vpCurrentFillH / 2, 0) * rot
	liquid.Material = Enum.Material.Neon
	liquid.Color = chosenColor
	liquid.Transparency = 0.12
	liquid.Parent = model
	model.PrimaryPart = body
	return model, liquid
end

local function setupViewportGlass()
	for _, c in ipairs(vpWorldModel:GetChildren()) do c:Destroy() end
	vpGlassLiquid = nil

	local model: Model
	local liquid: BasePart?

	local templates = DrinkSystem:FindFirstChild("GlassTemplates")
	local template = templates and (
		templates:FindFirstChildWhichIsA("Tool") or
		templates:FindFirstChildWhichIsA("Model")
	)

	if template then
		vpIsProcedural = false
		if template:IsA("Tool") then
			model = Instance.new("Model")
			model.Name = "DS_VPGlass"
			for _, child in ipairs(template:GetChildren()) do
				if child:IsA("BasePart") or child:IsA("MeshPart") or child:IsA("UnionOperation") then
					child:Clone().Parent = model
				end
			end
		else
			model = template:Clone()
		end
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				local n = p.Name:lower()
				if n == "liquid" or n == "fill" or n == "water" or n == "drink" or n == "content" then
					liquid = p; break
				end
			end
		end
	else
		vpIsProcedural = true
		model, liquid = buildFallbackGlass()
	end

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	model.Parent = vpWorldModel

	local ok, cf, sz = pcall(function() return model:GetBoundingBox() end)
	vpCenter = ok and cf.Position or Vector3.zero
	local tallest = ok and math.max(sz.X, sz.Y, sz.Z) or 2.5
	vpRadius = math.max(tallest, 1.5) * 2.2
	vpBias   = ok and (sz.Y * 0.1) or 0.2

	vpGlassLiquid = liquid
	if liquid then liquid.Color = chosenColor end
end

setupViewportGlass()

RunService.Heartbeat:Connect(function(dt)
	if not panel.Visible then return end

	-- orbit camera
	vpAngle += dt * 0.5
	local lookAt = vpCenter + Vector3.new(0, vpBias, 0)
	vpCamera.CFrame = CFrame.new(
		lookAt + Vector3.new(
			math.sin(vpAngle) * vpRadius,
			vpRadius * 0.38,
			math.cos(vpAngle) * vpRadius
		),
		lookAt
	)

	-- lerp liquid fill height toward target (avoids TweenService quirks in WorldModel)
	if vpIsProcedural and vpGlassLiquid then
		local diff = vpTargetFillH - vpCurrentFillH
		if math.abs(diff) > 0.001 then
			vpCurrentFillH += diff * math.min(dt * 10, 1)
			local cy = VP_LIQ_BOT + vpCurrentFillH / 2
			vpGlassLiquid.Size   = Vector3.new(vpCurrentFillH, VP_LIQ_DIAM, VP_LIQ_DIAM)
			vpGlassLiquid.CFrame = CFrame.new(0, cy, 0) * VP_LIQ_ROT
		end
	end
end)

-- assign the real body; forward declaration above lets rebuildChips / swatch
-- Activated handlers call this safely before we reach this point at runtime
refreshViewport = function()
	local n = #picks

	-- Color: always sync to chosenColor
	if vpGlassLiquid then
		vpGlassLiquid.Color = chosenColor
	end

	-- Fill level: set target; Heartbeat lerps the liquid up/down smoothly
	if vpIsProcedural then
		local fraction = n / MAX_PICKS
		vpTargetFillH = math.max(0.1, VP_LIQ_MAX_H * fraction)
	end

	-- Overlay label: name · Level N · color chip
	local level = math.ceil(n / 2)  -- 0 picks=0, 1-2=1, 3-4=2, 5-6=3
	local name = nameBox.Text
	if n == 0 then
		vpLabel.Text = "Design your drink →"
		vpLabel.TextColor3 = C.TextMute
	else
		local levelTag = level > 0 and ("Lv." .. level .. "  ") or ""
		local nameTag  = name ~= "" and (name .. "  ·  ") or ""
		vpLabel.Text      = nameTag .. levelTag .. n .. " ing."
		vpLabel.TextColor3 = C.TextSub
	end
end

-- ── Ingredient buttons ────────────────────────────────────────────────────

local ingBtns: { [string]: TextButton } = {}

local function pickCountOf(name: string): number
	local n = 0
	for _, p in ipairs(picks) do if p == name then n += 1 end end
	return n
end

local function refreshIngBtn(name: string)
	local btn = ingBtns[name]
	if not btn then return end
	local n = pickCountOf(name)
	local atCap = #picks >= MAX_PICKS
	if n > 0 then
		btn.BackgroundColor3 = C.AccentDim
		btn.TextColor3 = C.Accent
		btn.Text = n > 1 and (name .. " ×" .. n) or name
		local s = btn:FindFirstChildOfClass("UIStroke")
		if s then s.Transparency = 0 end
	else
		btn.BackgroundColor3 = atCap and Color3.fromRGB(15, 14, 20) or C.Surface2
		btn.TextColor3 = atCap and C.TextMute or C.TextSub
		btn.Text = name
		local s = btn:FindFirstChildOfClass("UIStroke")
		if s then s.Transparency = 1 end
	end
end

local function refreshAllIngBtns()
	for name in pairs(ingBtns) do refreshIngBtn(name) end
end

-- ── Picks chips ───────────────────────────────────────────────────────────

local function rebuildChips()
	for _, c in ipairs(chipsScroll:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	local empty = chipsScroll:FindFirstChild("_empty")
	if #picks == 0 then
		if empty then empty.Visible = true end
		return
	end
	if empty then empty.Visible = false end

	-- deduplicate while preserving order
	local seen: { [string]: number } = {}
	local order: { string } = {}
	for _, p in ipairs(picks) do
		if not seen[p] then seen[p] = 0; table.insert(order, p) end
		seen[p] += 1
	end

	for i, name in ipairs(order) do
		local chip = Instance.new("Frame")
		chip.Size = UDim2.new(0, 0, 0, 28)
		chip.AutomaticSize = Enum.AutomaticSize.X
		chip.BackgroundColor3 = C.AccentDim
		chip.BorderSizePixel = 0
		chip.LayoutOrder = i
		chip.Parent = chipsScroll
		addCorner(chip, 6)
		addStroke(chip, C.AccentBdr, 1)
		local cp = Instance.new("UIPadding")
		cp.PaddingLeft = UDim.new(0, 8)
		cp.PaddingRight = UDim.new(0, 6)
		cp.Parent = chip
		local cl = Instance.new("UIListLayout")
		cl.FillDirection = Enum.FillDirection.Horizontal
		cl.Padding = UDim.new(0, 4)
		cl.VerticalAlignment = Enum.VerticalAlignment.Center
		cl.Parent = chip

		local label = mkLabel(chip, seen[name] > 1 and (name .. " ×" .. seen[name]) or name, 11, false, C.Accent)
		label.Size = UDim2.new(0, 0, 1, 0)
		label.AutomaticSize = Enum.AutomaticSize.X

		local removeBtn = Instance.new("TextButton")
		removeBtn.Size = UDim2.new(0, 14, 1, 0)
		removeBtn.BackgroundTransparency = 1
		removeBtn.Font = Enum.Font.MontserratBold
		removeBtn.TextSize = 10
		removeBtn.TextColor3 = C.AccentBdr
		removeBtn.Text = "×"
		removeBtn.Parent = chip
		local cn = name
		removeBtn.Activated:Connect(function()
			for idx = #picks, 1, -1 do
				if picks[idx] == cn then table.remove(picks, idx); break end
			end
			rebuildChips()
			refreshAllIngBtns()
			refreshViewport()
		end)
	end
end

-- ── Swatch buttons ────────────────────────────────────────────────────────

local swatchBtns: { TextButton } = {}

local function refreshSwatches()
	for _, b in ipairs(swatchBtns) do
		local s = b:FindFirstChildOfClass("UIStroke")
		if s then s.Transparency = (b.BackgroundColor3 == chosenColor) and 0 or 1 end
	end
	colorPreview.BackgroundColor3 = chosenColor
end

for _, col in ipairs(COLOR_SWATCHES) do
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 26, 0, 26)
	b.BackgroundColor3 = col
	b.BorderSizePixel = 0
	b.Text = ""
	b.Parent = swatchRow
	addCorner(b, 13)
	addStroke(b, Color3.fromRGB(255, 255, 255), 2, 1)
	table.insert(swatchBtns, b)
	b.Activated:Connect(function() chosenColor = col; refreshSwatches(); refreshViewport() end)
end

-- ── Drunkness slider ──────────────────────────────────────────────────────

local function strengthBand(v: number): (string, Color3)
	if v <= 25 then
		return "Light", Color3.fromRGB(100, 195, 120)
	elseif v <= 48 then
		return "Medium", Color3.fromRGB(215, 185, 65)
	elseif v <= 75 then
		return "Strong", Color3.fromRGB(230, 125, 55)
	else
		return "Nuclear", Color3.fromRGB(215, 58, 50)
	end
end

local function refreshSlider()
	chosenStrongness = math.clamp(chosenStrongness, STRONGNESS_MIN, STRONGNESS_HARD_CAP)
	local alpha = (chosenStrongness - STRONGNESS_MIN) / (STRONGNESS_HARD_CAP - STRONGNESS_MIN)
	knob.Position = UDim2.new(alpha, 0, 0.5, 0)
	fill.Size = UDim2.new(alpha, 0, 1, 0)
	local bandName, bandColor = strengthBand(chosenStrongness)
	fill.BackgroundColor3 = bandColor
	knob.BackgroundColor3 = bandColor
	sliderVal.Text = ("%d  %s"):format(chosenStrongness, bandName)
	sliderVal.TextColor3 = bandColor
end

local dragging = false
local function setFromX(x: number)
	local alpha = math.clamp(
		(x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1
	)
	chosenStrongness = math.floor(STRONGNESS_MIN + alpha * (STRONGNESS_HARD_CAP - STRONGNESS_MIN) + 0.5)
	refreshSlider()
end

knob.InputBegan:Connect(function(inp)
	if inp.UserInputType == Enum.UserInputType.MouseButton1
		or inp.UserInputType == Enum.UserInputType.Touch then
		dragging = true; setFromX(inp.Position.X)
	end
end)
track.InputBegan:Connect(function(inp)
	if inp.UserInputType == Enum.UserInputType.MouseButton1
		or inp.UserInputType == Enum.UserInputType.Touch then
		dragging = true; setFromX(inp.Position.X)
	end
end)
UserInputService.InputChanged:Connect(function(inp)
	if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement
		or inp.UserInputType == Enum.UserInputType.Touch) then
		setFromX(inp.Position.X)
	end
end)
UserInputService.InputEnded:Connect(function(inp)
	if inp.UserInputType == Enum.UserInputType.MouseButton1
		or inp.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

-- ── Duration buttons ──────────────────────────────────────────────────────

local durBtns: { [number]: TextButton } = {}

local function ownsHours(h: number): boolean
	for _, t in ipairs(tokenHours) do if t == h then return true end end
	return false
end

local function refreshDuration()
	for hours, btn in pairs(durBtns) do
		local sel = hours == chosenHours
		local owned = ownsHours(hours)
		if sel then
			btn.BackgroundColor3 = Color3.fromRGB(40, 65, 120)
			btn.TextColor3 = Color3.fromRGB(195, 220, 255)
			local s = btn:FindFirstChildOfClass("UIStroke")
			if s then s.Transparency = 0 end
		else
			btn.BackgroundColor3 = C.Surface2
			btn.TextColor3 = owned and C.Accent or C.TextSub
			local s = btn:FindFirstChildOfClass("UIStroke")
			if s then s.Transparency = 1 end
		end
		-- owned dot indicator
		local dot = btn:FindFirstChild("_dot")
		if dot then
			dot.BackgroundColor3 = owned and C.Accent or Color3.fromRGB(40, 38, 54)
		end
	end
end

for _, hours in ipairs(DURATION_OPTIONS) do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 80, 1, 0)
	btn.BackgroundColor3 = C.Surface2
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.MontserratBold
	btn.TextSize = 13
	btn.TextColor3 = C.TextSub
	btn.Text = hours .. "h"
	btn.Parent = durationRow
	addCorner(btn, 9)
	addStroke(btn, Color3.fromRGB(100, 150, 230), 1.5, 1)
	-- small dot top-right = "owned" state
	local dot = Instance.new("Frame")
	dot.Name = "_dot"
	dot.AnchorPoint = Vector2.new(1, 0)
	dot.Position = UDim2.new(1, -5, 0, 5)
	dot.Size = UDim2.new(0, 6, 0, 6)
	dot.BackgroundColor3 = Color3.fromRGB(40, 38, 54)
	dot.BorderSizePixel = 0
	dot.ZIndex = 3
	dot.Parent = btn
	addCorner(dot, 3)
	durBtns[hours] = btn
	btn.Activated:Connect(function()
		chosenHours = hours
		refreshDuration()
		refreshStatus()
	end)
end

-- ── Status helpers ────────────────────────────────────────────────────────

function refreshStatus()
	local free = Settings.CustomDrinkFreeTesting == true
	hdrSlotCount.Text = ("%d / %d live"):format(activeCount, MAX_ACTIVE)
	if activeCount >= MAX_ACTIVE then
		statusLabel.Text = "You've hit the live cap (" .. MAX_ACTIVE .. ")"
		submitBtn.Text = "Menu full"
		submitBtn.BackgroundColor3 = Color3.fromRGB(44, 42, 52)
	elseif free or ownsHours(chosenHours) then
		statusLabel.Text = free and "Free testing — create away!" or ("Slot owned • " .. chosenHours .. "h duration")
		submitBtn.Text = ("Post for %dh"):format(chosenHours)
		submitBtn.BackgroundColor3 = C.Success
	else
		statusLabel.Text = "Buy a " .. chosenHours .. "h slot to go live"
		submitBtn.Text = ("Buy %dh Slot"):format(chosenHours)
		submitBtn.BackgroundColor3 = C.Buy
	end
end

-- ── Live drinks list ──────────────────────────────────────────────────────

local function fmtTime(expiresAt: number): string
	local rem = math.max(expiresAt - os.time(), 0)
	local h = math.floor(rem / 3600)
	local m = math.floor((rem % 3600) / 60)
	return h > 0 and ("%dh %dm left"):format(h, m) or ("%dm left"):format(math.max(m, 1))
end

local function rebuildLiveList()
	for _, child in ipairs(liveScroll:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	local dynFolder = DrinkSystem:FindFirstChild("DynamicRecipes")
	local entries = dynFolder and dynFolder:GetChildren() or {}
	if #entries == 0 then
		local empty = Instance.new("Frame")
		empty.Size = UDim2.new(1, 0, 0, 72)
		empty.BackgroundTransparency = 1
		empty.Parent = liveScroll
		local el = mkLabel(empty, "No custom drinks live yet.\nYours could be first.", 12, false, C.TextMute)
		el.Size = UDim2.fromScale(1, 1)
		el.TextWrapped = true
		return
	end
	for i, entry in ipairs(entries) do
		local rawCol = entry:GetAttribute("Color")
		local accentCol: Color3 = (typeof(rawCol) == "Color3") and rawCol or C.Accent

		local csv = entry:GetAttribute("IngredientsCsv") or ""
		local steps: { string } = {}
		local n = 0
		for token in string.gmatch(csv, "([^,]+)") do
			n += 1; table.insert(steps, n .. ".  " .. token)
		end
		local expiresAt = tonumber(entry:GetAttribute("ExpiresAt")) or 0

		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.BackgroundColor3 = C.Surface2
		card.BorderSizePixel = 0
		card.LayoutOrder = i
		card.Parent = liveScroll
		addCorner(card, 8)

		-- color-accent left stripe
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 3, 1, 0)
		stripe.BackgroundColor3 = accentCol
		stripe.BorderSizePixel = 0
		stripe.ZIndex = 2
		stripe.Parent = card
		addCorner(stripe, 2)

		local cp = Instance.new("UIPadding")
		cp.PaddingLeft = UDim.new(0, 11)
		cp.PaddingRight = UDim.new(0, 8)
		cp.PaddingTop = UDim.new(0, 7)
		cp.PaddingBottom = UDim.new(0, 7)
		cp.Parent = card
		local cl = Instance.new("UIListLayout")
		cl.Padding = UDim.new(0, 2)
		cl.SortOrder = Enum.SortOrder.LayoutOrder
		cl.Parent = card

		local drinkName = mkLabel(card, entry:GetAttribute("DisplayName") or entry.Name, 13, true, accentCol)
		drinkName.Size = UDim2.new(1, 0, 0, 17)
		drinkName.TextXAlignment = Enum.TextXAlignment.Left
		drinkName.LayoutOrder = 1

		local ingText = mkLabel(card, table.concat(steps, "\n"), 10, false, C.TextSub)
		ingText.Size = UDim2.new(1, 0, 0, 0)
		ingText.AutomaticSize = Enum.AutomaticSize.Y
		ingText.TextWrapped = true
		ingText.TextXAlignment = Enum.TextXAlignment.Left
		ingText.LayoutOrder = 2

		local footer = mkLabel(card,
			("by %s  •  %s"):format(entry:GetAttribute("CreatorName") or "?", fmtTime(expiresAt)),
			10, false, C.TextMute
		)
		footer.Size = UDim2.new(1, 0, 0, 14)
		footer.TextXAlignment = Enum.TextXAlignment.Left
		footer.LayoutOrder = 3
	end
end

-- ── Build ingredient buttons ──────────────────────────────────────────────

local ingNames = IngredientRegistry.listNames()
table.sort(ingNames)
for _, name in ipairs(ingNames) do
	if name ~= "Water" then
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.BackgroundColor3 = C.Surface2
		btn.BorderSizePixel = 0
		btn.Font = Enum.Font.Montserrat
		btn.TextSize = 11
		btn.TextColor3 = C.TextSub
		btn.Text = name
		btn.Parent = grid
		addCorner(btn, 7)
		addStroke(btn, C.Accent, 1.5, 1)
		ingBtns[name] = btn
		btn.Activated:Connect(function()
			local count = pickCountOf(name)
			if count > 0 and #picks >= MAX_PICKS then
				-- at cap: tap again removes last copy
				for i = #picks, 1, -1 do
					if picks[i] == name then table.remove(picks, i); break end
				end
			elseif #picks < MAX_PICKS then
				table.insert(picks, name)
			end
			rebuildChips()
			refreshAllIngBtns()
			refreshViewport()
		end)
	end
end

-- ── Init ──────────────────────────────────────────────────────────────────

refreshSwatches()
rebuildChips()
refreshSlider()
refreshDuration()
refreshStatus()
refreshViewport()
nameBox:GetPropertyChangedSignal("Text"):Connect(refreshViewport)

-- ── Networking ────────────────────────────────────────────────────────────

Packets.CustomDrinkState.listen(function(data)
	tokenHours = data.TokenHours or {}
	activeCount = data.ActiveCount or 0
	refreshDuration()
	refreshStatus()
end)

Packets.CustomDrinkResult.listen(function(data)
	resultLabel.Text = data.Message or ""
	resultLabel.TextColor3 = data.Ok
		and Color3.fromRGB(100, 210, 130)
		or Color3.fromRGB(225, 105, 95)
	if data.Ok then
		picks = {}
		nameBox.Text = ""
		rebuildChips()
		refreshAllIngBtns()
	end
end)

submitBtn.Activated:Connect(function()
	if activeCount >= MAX_ACTIVE then return end
	local free = Settings.CustomDrinkFreeTesting == true
	if not free and not ownsHours(chosenHours) then
		local products = Settings.CustomDrinkProducts or {}
		local productId = products[chosenHours]
		if productId and productId ~= 0 then
			MarketplaceService:PromptProductPurchase(player, productId)
		else
			resultLabel.Text = "Purchases aren't set up yet"
			resultLabel.TextColor3 = Color3.fromRGB(225, 105, 95)
		end
		return
	end
	if #picks < MIN_PICKS then
		resultLabel.Text = ("Pick at least %d ingredients first"):format(MIN_PICKS)
		resultLabel.TextColor3 = Color3.fromRGB(225, 105, 95)
		return
	end
	Packets.SubmitCustomDrink.send({
		Name       = nameBox.Text,
		Ingredients = picks,
		ColorR     = math.floor(chosenColor.R * 255),
		ColorG     = math.floor(chosenColor.G * 255),
		ColorB     = math.floor(chosenColor.B * 255),
		Hours      = chosenHours,
		Strongness = chosenStrongness,
	})
	resultLabel.Text = "Posting…"
	resultLabel.TextColor3 = Color3.fromRGB(160, 160, 170)
end)

-- ── Live list wiring ──────────────────────────────────────────────────────

task.spawn(function()
	local dynFolder = DrinkSystem:WaitForChild("DynamicRecipes", 60)
	if dynFolder then
		dynFolder.ChildAdded:Connect(function() task.defer(rebuildLiveList) end)
		dynFolder.ChildRemoved:Connect(function() task.defer(rebuildLiveList) end)
	end
	while true do
		if panel.Visible then rebuildLiveList() end
		task.wait(30)
	end
end)

-- ── Toggle: pop-in animation ──────────────────────────────────────────────

local openTween: Tween? = nil

local function setOpen(open: boolean)
	if openTween then openTween:Cancel(); openTween = nil end
	if open then
		-- pop-in: start slightly smaller, spring to full size
		panel.Size = UDim2.new(0, math.floor(PW * 0.93), 0, math.floor(PH * 0.93))
		panel.Visible = true
		openTween = TweenService:Create(panel,
			TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 1, false, 0),
			{ Size = UDim2.new(0, PW, 0, PH) }
		)
		openTween:Play()
		resultLabel.Text = ""
		Packets.RequestCustomDrinkState.send({})
		rebuildLiveList()
	else
		openTween = TweenService:Create(panel,
			TweenInfo.new(0.14, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
			{ Size = UDim2.new(0, math.floor(PW * 0.93), 0, math.floor(PH * 0.93)) }
		)
		openTween.Completed:Connect(function()
			panel.Visible = false
			panel.Size = UDim2.new(0, PW, 0, PH) -- reset for next open
		end)
		openTween:Play()
	end
end

toggleBtn.Activated:Connect(function() setOpen(not panel.Visible) end)
closeBtn.Activated:Connect(function() setOpen(false) end)

UserInputService.InputBegan:Connect(function(inp, processed)
	if processed then return end
	if inp.KeyCode == Enum.KeyCode.N then setOpen(not panel.Visible) end
end)
