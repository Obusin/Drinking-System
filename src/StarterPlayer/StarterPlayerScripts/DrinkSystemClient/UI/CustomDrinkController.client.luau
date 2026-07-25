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
-- Layout: LEFT=glass preview+chips+swatches, RIGHT=ingredient grid, BOTTOM=controls

local PW, PH   = 780, 560
local HDR_H    = 48
local PAD      = 12
local LW       = 252   -- left column width (glass preview)
local GX       = PAD + LW + PAD   -- grid x = 276
local GW       = PW - GX - PAD    -- grid width = 492
local VP_H     = 226   -- glass preview height
local BTM_Y    = 424   -- bottom controls start y

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.new(0, PW, 0, PH)
panel.BackgroundColor3 = C.BG
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
addCorner(panel, 14)
addStroke(panel, C.Divider, 1)

-- Header bar
local hdr = Instance.new("Frame")
hdr.Size = UDim2.new(1, 0, 0, HDR_H)
hdr.BackgroundColor3 = C.Header
hdr.BorderSizePixel = 0
hdr.ZIndex = 4
hdr.Parent = panel
addCorner(hdr, 14)
local hdrMask = Instance.new("Frame")
hdrMask.AnchorPoint = Vector2.new(0, 1)
hdrMask.Position = UDim2.new(0, 0, 1, 0)
hdrMask.Size = UDim2.new(1, 0, 0, 14)
hdrMask.BackgroundColor3 = C.Header
hdrMask.BorderSizePixel = 0
hdrMask.ZIndex = 4
hdrMask.Parent = hdr
local hdrLine = Instance.new("Frame")
hdrLine.AnchorPoint = Vector2.new(0, 1)
hdrLine.Position = UDim2.new(0, 0, 1, 0)
hdrLine.Size = UDim2.new(1, 0, 0, 1)
hdrLine.BackgroundColor3 = C.Divider
hdrLine.BorderSizePixel = 0
hdrLine.ZIndex = 5
hdrLine.Parent = hdr

local hdrTitle = mkLabel(hdr, "Drink Lab", 16, true, C.Text)
hdrTitle.AnchorPoint = Vector2.new(0, 0.5)
hdrTitle.Position = UDim2.new(0, 18, 0.5, 0)
hdrTitle.Size = UDim2.new(0, 200, 1, 0)
hdrTitle.TextXAlignment = Enum.TextXAlignment.Left
hdrTitle.ZIndex = 5

local hdrSlotCount = mkLabel(hdr, "", 11, false, C.TextMute)
hdrSlotCount.AnchorPoint = Vector2.new(1, 0.5)
hdrSlotCount.Position = UDim2.new(1, -52, 0.5, 0)
hdrSlotCount.Size = UDim2.new(0, 160, 1, 0)
hdrSlotCount.TextXAlignment = Enum.TextXAlignment.Right
hdrSlotCount.ZIndex = 5

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -10, 0.5, 0)
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.BackgroundColor3 = C.Surface2
closeBtn.BorderSizePixel = 0
closeBtn.Font = Enum.Font.MontserratBold
closeBtn.TextSize = 14
closeBtn.TextColor3 = C.TextSub
closeBtn.Text = "✕"
closeBtn.ZIndex = 6
closeBtn.Parent = hdr
addCorner(closeBtn, 7)

-- ── Vertical divider between left and right sections ───────────────────────

local colDiv = Instance.new("Frame")
colDiv.Position = UDim2.new(0, GX - PAD, 0, HDR_H)
colDiv.Size = UDim2.new(0, 1, 0, BTM_Y - HDR_H)
colDiv.BackgroundColor3 = C.Divider
colDiv.BorderSizePixel = 0
colDiv.Parent = panel

-- ── LEFT — 2-D glass preview ───────────────────────────────────────────────

local previewBg = Instance.new("Frame")
previewBg.Name = "DrinkPreview"
previewBg.Position = UDim2.new(0, PAD, 0, HDR_H + PAD)
previewBg.Size = UDim2.new(0, LW, 0, VP_H)
previewBg.BackgroundColor3 = C.Surface
previewBg.BorderSizePixel = 0
previewBg.ClipsDescendants = true
previewBg.Parent = panel
addCorner(previewBg, 10)
addStroke(previewBg, C.Divider, 1)

local previewGrad = Instance.new("UIGradient")
previewGrad.Rotation = 90
previewGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(22, 20, 30)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(12, 11, 18)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(6, 5, 10)),
})
previewGrad.Parent = previewBg

local fillFrame = Instance.new("Frame")
fillFrame.Name = "_Fill"
fillFrame.AnchorPoint = Vector2.new(0, 1)
fillFrame.Position = UDim2.new(0, 0, 1, 0)
fillFrame.Size = UDim2.new(1, 0, 0, 0)
fillFrame.BackgroundColor3 = chosenColor
fillFrame.BorderSizePixel = 0
fillFrame.Parent = previewBg

local glassOverlay = Instance.new("Frame")
glassOverlay.Size = UDim2.fromScale(1, 1)
glassOverlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
glassOverlay.BackgroundTransparency = 0.87
glassOverlay.BorderSizePixel = 0
glassOverlay.ZIndex = 2
glassOverlay.Parent = previewBg
local glassGrad = Instance.new("UIGradient")
glassGrad.Rotation = 90
glassGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.24, 0.72),
	NumberSequenceKeypoint.new(1, 1),
})
glassGrad.Parent = glassOverlay

local shineStrip = Instance.new("Frame")
shineStrip.Size = UDim2.new(0, 3, 1, 0)
shineStrip.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
shineStrip.BorderSizePixel = 0
shineStrip.ZIndex = 3
shineStrip.Parent = previewBg
local shineGrad = Instance.new("UIGradient")
shineGrad.Rotation = 90
shineGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.18, 0.52),
	NumberSequenceKeypoint.new(0.82, 0.52),
	NumberSequenceKeypoint.new(1, 1),
})
shineGrad.Parent = shineStrip

local vpOverlay = Instance.new("Frame")
vpOverlay.AnchorPoint = Vector2.new(0, 1)
vpOverlay.Position = UDim2.new(0, 0, 1, 0)
vpOverlay.Size = UDim2.new(1, 0, 0, 52)
vpOverlay.BackgroundColor3 = Color3.fromRGB(6, 5, 10)
vpOverlay.BackgroundTransparency = 1
vpOverlay.BorderSizePixel = 0
vpOverlay.ZIndex = 4
vpOverlay.Parent = previewBg
local vpGrad = Instance.new("UIGradient")
vpGrad.Rotation = 90
vpGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.06),
	NumberSequenceKeypoint.new(1, 1),
})
vpGrad.Parent = vpOverlay

local vpLabel = mkLabel(vpOverlay, "Design your drink →", 11, false, C.TextMute)
vpLabel.AnchorPoint = Vector2.new(0, 1)
vpLabel.Position = UDim2.new(0, 10, 1, -9)
vpLabel.Size = UDim2.new(1, -14, 0, 14)
vpLabel.TextXAlignment = Enum.TextXAlignment.Left
vpLabel.ZIndex = 5

-- ── LEFT — Picks chips ─────────────────────────────────────────────────────

local chipsOuter = Instance.new("Frame")
chipsOuter.Position = UDim2.new(0, PAD, 0, HDR_H + PAD + VP_H + 8)
chipsOuter.Size = UDim2.new(0, LW, 0, 36)
chipsOuter.BackgroundColor3 = C.Surface
chipsOuter.BorderSizePixel = 0
chipsOuter.ClipsDescendants = true
chipsOuter.Parent = panel
addCorner(chipsOuter, 8)
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
chipsPad.PaddingLeft = UDim.new(0, 8)
chipsPad.PaddingRight = UDim.new(0, 8)
chipsPad.Parent = chipsScroll

local chipsEmpty = mkLabel(chipsScroll, "Pick 4–6 ingredients →", 11, false, C.TextMute)
chipsEmpty.Name = "_empty"
chipsEmpty.Size = UDim2.new(0, 220, 1, 0)
chipsEmpty.LayoutOrder = 0

-- ── LEFT — Color swatches ──────────────────────────────────────────────────
-- UIGridLayout wraps into 2 rows automatically (6 per row × 26px = 181px < LW)

local SWATCH_Y = HDR_H + PAD + VP_H + 8 + 36 + 10

local colorPreview = Instance.new("Frame")
colorPreview.Position = UDim2.new(0, PAD, 0, SWATCH_Y)
colorPreview.Size = UDim2.new(0, 26, 0, 26)
colorPreview.BackgroundColor3 = chosenColor
colorPreview.BorderSizePixel = 0
colorPreview.Parent = panel
addCorner(colorPreview, 13)
addStroke(colorPreview, Color3.fromRGB(200, 200, 200), 1.5, 0.4)

local swatchRow = Instance.new("Frame")
swatchRow.Position = UDim2.new(0, PAD + 32, 0, SWATCH_Y)
swatchRow.Size = UDim2.new(0, LW - 32, 0, 57)
swatchRow.BackgroundTransparency = 1
swatchRow.Parent = panel
local swatchGrid = Instance.new("UIGridLayout")
swatchGrid.CellSize = UDim2.new(0, 26, 0, 26)
swatchGrid.CellPadding = UDim2.new(0, 5, 0, 5)
swatchGrid.SortOrder = Enum.SortOrder.LayoutOrder
swatchGrid.Parent = swatchRow

-- ── RIGHT — Ingredient grid ────────────────────────────────────────────────

local ingLabel = mkLabel(panel, "INGREDIENTS", 10, true, C.TextMute)
ingLabel.Position = UDim2.new(0, GX + 2, 0, HDR_H + PAD + 2)
ingLabel.Size = UDim2.new(0, GW, 0, 14)
ingLabel.TextXAlignment = Enum.TextXAlignment.Left

local grid = Instance.new("ScrollingFrame")
grid.Position = UDim2.new(0, GX, 0, HDR_H + PAD + 18)
grid.Size = UDim2.new(0, GW, 0, BTM_Y - (HDR_H + PAD + 18) - PAD)
grid.BackgroundTransparency = 1
grid.BorderSizePixel = 0
grid.ScrollBarThickness = 3
grid.ScrollBarImageColor3 = C.Divider
grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
grid.CanvasSize = UDim2.new(0, 0, 0, 0)
grid.Parent = panel
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0, 92, 0, 34)
gridLayout.CellPadding = UDim2.new(0, 5, 0, 5)
gridLayout.SortOrder = Enum.SortOrder.Name
gridLayout.Parent = grid

-- ── BOTTOM — thin divider + controls ──────────────────────────────────────

local btmDiv = Instance.new("Frame")
btmDiv.Position = UDim2.new(0, 0, 0, BTM_Y)
btmDiv.Size = UDim2.new(1, 0, 0, 1)
btmDiv.BackgroundColor3 = C.Divider
btmDiv.BorderSizePixel = 0
btmDiv.Parent = panel

-- Name input (spans most of bottom width, color circle on right)
local nameBox = Instance.new("TextBox")
nameBox.Position = UDim2.new(0, PAD, 0, BTM_Y + 10)
nameBox.Size = UDim2.new(0, PW - PAD * 2, 0, 34)
nameBox.BackgroundColor3 = C.Surface2
nameBox.BorderSizePixel = 0
nameBox.Font = Enum.Font.Montserrat
nameBox.PlaceholderText = "Name your drink…"
nameBox.PlaceholderColor3 = C.TextMute
nameBox.Text = ""
nameBox.TextSize = 14
nameBox.TextColor3 = C.Text
nameBox.ClearTextOnFocus = false
nameBox.Parent = panel
addCorner(nameBox, 8)
addStroke(nameBox, C.Divider, 1)
local namePad = Instance.new("UIPadding")
namePad.PaddingLeft = UDim.new(0, 10)
namePad.PaddingRight = UDim.new(0, 10)
namePad.Parent = nameBox

-- Drunkness section (left half of bottom row 2)
local BL_W = math.floor((PW - PAD * 3) / 2)  -- left half width ≈ 378
local BR_X = PAD + BL_W + PAD                  -- right half x ≈ 402
local BR_W = PW - BR_X - PAD                   -- right half width ≈ 366

local lblDrunk = mkLabel(panel, "DRUNKNESS", 9, true, C.TextMute)
lblDrunk.Position = UDim2.new(0, PAD, 0, BTM_Y + 52)
lblDrunk.Size = UDim2.new(0, BL_W - 80, 0, 12)
lblDrunk.TextXAlignment = Enum.TextXAlignment.Left

local sliderVal = mkLabel(panel, "", 10, false, C.TextSub)
sliderVal.AnchorPoint = Vector2.new(1, 0)
sliderVal.Position = UDim2.new(0, PAD + BL_W, 0, BTM_Y + 51)
sliderVal.Size = UDim2.new(0, 76, 0, 13)
sliderVal.TextXAlignment = Enum.TextXAlignment.Right

local track = Instance.new("Frame")
track.Position = UDim2.new(0, PAD, 0, BTM_Y + 68)
track.Size = UDim2.new(0, BL_W, 0, 8)
track.BackgroundColor3 = C.Surface2
track.BorderSizePixel = 0
track.Parent = panel
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
knob.BackgroundColor3 = Color3.fromRGB(220, 220, 220)
knob.BorderSizePixel = 0
knob.Text = ""
knob.ZIndex = 3
knob.Parent = track
addCorner(knob, 9)

-- Duration section (right half of bottom row 2)
local lblDur = mkLabel(panel, "DURATION", 9, true, C.TextMute)
lblDur.Position = UDim2.new(0, BR_X, 0, BTM_Y + 52)
lblDur.Size = UDim2.new(0, BR_W, 0, 12)
lblDur.TextXAlignment = Enum.TextXAlignment.Left

local durationRow = Instance.new("Frame")
durationRow.Position = UDim2.new(0, BR_X, 0, BTM_Y + 66)
durationRow.Size = UDim2.new(0, BR_W, 0, 30)
durationRow.BackgroundTransparency = 1
durationRow.Parent = panel
local durLayout = Instance.new("UIListLayout")
durLayout.FillDirection = Enum.FillDirection.Horizontal
durLayout.Padding = UDim.new(0, 6)
durLayout.Parent = durationRow

-- Result / status / submit
local resultLabel = mkLabel(panel, "", 11, false, C.TextSub)
resultLabel.Position = UDim2.new(0, PAD, 0, BTM_Y + 104)
resultLabel.Size = UDim2.new(0, PW - PAD * 2 - 200, 0, 14)
resultLabel.TextXAlignment = Enum.TextXAlignment.Left

local statusLabel = mkLabel(panel, "", 10, false, C.TextMute)
statusLabel.Position = UDim2.new(0, PAD, 0, BTM_Y + 120)
statusLabel.Size = UDim2.new(0, PW - PAD * 2 - 200, 0, 14)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left

local submitBtn = Instance.new("TextButton")
submitBtn.AnchorPoint = Vector2.new(1, 1)
submitBtn.Position = UDim2.new(1, -PAD, 1, -PAD)
submitBtn.Size = UDim2.new(0, 190, 0, 38)
submitBtn.BackgroundColor3 = C.Success
submitBtn.BorderSizePixel = 0
submitBtn.Font = Enum.Font.MontserratBold
submitBtn.TextSize = 14
submitBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
submitBtn.Text = "Create Drink"
submitBtn.ZIndex = 2
submitBtn.Parent = panel
addCorner(submitBtn, 9)

-- ── Menu panel — default view: live drink list ────────────────────────────

local MW, MH   = 540, 480
local MHDR_H   = 52

local menuPanel = Instance.new("Frame")
menuPanel.Name = "MenuPanel"
menuPanel.AnchorPoint = Vector2.new(0.5, 0.5)
menuPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
menuPanel.Size = UDim2.new(0, MW, 0, MH)
menuPanel.BackgroundColor3 = C.BG
menuPanel.BorderSizePixel = 0
menuPanel.Visible = false
menuPanel.Parent = gui
addCorner(menuPanel, 14)
addStroke(menuPanel, C.Divider, 1)

local mHdr = Instance.new("Frame")
mHdr.Size = UDim2.new(1, 0, 0, MHDR_H)
mHdr.BackgroundColor3 = C.Header
mHdr.BorderSizePixel = 0
mHdr.ZIndex = 4
mHdr.Parent = menuPanel
addCorner(mHdr, 14)
local mHdrMask = Instance.new("Frame")
mHdrMask.AnchorPoint = Vector2.new(0, 1)
mHdrMask.Position = UDim2.new(0, 0, 1, 0)
mHdrMask.Size = UDim2.new(1, 0, 0, 14)
mHdrMask.BackgroundColor3 = C.Header
mHdrMask.BorderSizePixel = 0
mHdrMask.ZIndex = 4
mHdrMask.Parent = mHdr
local mHdrLine = Instance.new("Frame")
mHdrLine.AnchorPoint = Vector2.new(0, 1)
mHdrLine.Position = UDim2.new(0, 0, 1, 0)
mHdrLine.Size = UDim2.new(1, 0, 0, 1)
mHdrLine.BackgroundColor3 = C.Divider
mHdrLine.BorderSizePixel = 0
mHdrLine.ZIndex = 5
mHdrLine.Parent = mHdr

local mTitle = mkLabel(mHdr, "On the Menu", 16, true, C.Text)
mTitle.AnchorPoint = Vector2.new(0, 0.5)
mTitle.Position = UDim2.new(0, 18, 0.5, 0)
mTitle.Size = UDim2.new(0, 200, 1, 0)
mTitle.TextXAlignment = Enum.TextXAlignment.Left
mTitle.ZIndex = 5

local mCloseBtn = Instance.new("TextButton")
mCloseBtn.AnchorPoint = Vector2.new(1, 0.5)
mCloseBtn.Position = UDim2.new(1, -10, 0.5, 0)
mCloseBtn.Size = UDim2.new(0, 30, 0, 30)
mCloseBtn.BackgroundColor3 = C.Surface2
mCloseBtn.BorderSizePixel = 0
mCloseBtn.Font = Enum.Font.MontserratBold
mCloseBtn.TextSize = 14
mCloseBtn.TextColor3 = C.TextSub
mCloseBtn.Text = "✕"
mCloseBtn.ZIndex = 6
mCloseBtn.Parent = mHdr
addCorner(mCloseBtn, 7)

local createDrinkBtn = Instance.new("TextButton")
createDrinkBtn.AnchorPoint = Vector2.new(1, 0.5)
createDrinkBtn.Position = UDim2.new(1, -50, 0.5, 0)
createDrinkBtn.Size = UDim2.new(0, 118, 0, 30)
createDrinkBtn.BackgroundColor3 = C.AccentDim
createDrinkBtn.BorderSizePixel = 0
createDrinkBtn.Font = Enum.Font.MontserratBold
createDrinkBtn.TextSize = 12
createDrinkBtn.TextColor3 = C.Accent
createDrinkBtn.Text = "+ Create Drink"
createDrinkBtn.ZIndex = 6
createDrinkBtn.Parent = mHdr
addCorner(createDrinkBtn, 8)
addStroke(createDrinkBtn, C.AccentBdr, 1.5)

local liveScroll = Instance.new("ScrollingFrame")
liveScroll.Position = UDim2.new(0, 8, 0, MHDR_H + 6)
liveScroll.Size = UDim2.new(1, -16, 1, -(MHDR_H + 12))
liveScroll.BackgroundTransparency = 1
liveScroll.BorderSizePixel = 0
liveScroll.ScrollBarThickness = 3
liveScroll.ScrollBarImageColor3 = C.Divider
liveScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
liveScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
liveScroll.Parent = menuPanel
local liveLayout = Instance.new("UIListLayout")
liveLayout.Padding = UDim.new(0, 6)
liveLayout.SortOrder = Enum.SortOrder.LayoutOrder
liveLayout.Parent = liveScroll
local livePad = Instance.new("UIPadding")
livePad.PaddingTop = UDim.new(0, 6)
livePad.PaddingBottom = UDim.new(0, 6)
livePad.PaddingLeft = UDim.new(0, 2)
livePad.PaddingRight = UDim.new(0, 2)
livePad.Parent = liveScroll

-- ── 2-D fill state ────────────────────────────────────────────────────────

local vpTargetFrac  = 0
local vpCurrentFrac = 0

RunService.Heartbeat:Connect(function(dt)
	if not panel.Visible then return end
	local diff = vpTargetFrac - vpCurrentFrac
	if math.abs(diff) > 0.001 then
		vpCurrentFrac = vpCurrentFrac + diff * math.min(dt * 8, 1)
		fillFrame.Size = UDim2.new(1, 0, 0, math.round(VP_H * vpCurrentFrac))
	end
end)

refreshViewport = function()
	local n = #picks
	fillFrame.BackgroundColor3 = chosenColor
	vpTargetFrac = n / MAX_PICKS
	colorPreview.BackgroundColor3 = chosenColor
	local level = math.ceil(n / 2)
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
		local el = mkLabel(empty, "No custom drinks on the menu yet.", 12, false, C.TextMute)
		el.AnchorPoint = Vector2.new(0.5, 0.5)
		el.Position = UDim2.fromScale(0.5, 0.5)
		el.Size = UDim2.new(1, -20, 0, 32)
		el.TextWrapped = true
		el.TextXAlignment = Enum.TextXAlignment.Center
		return
	end

	local CARD_H  = 80
	local THUMB_W = 58

	for i, entry in ipairs(entries) do
		local rawCol      = entry:GetAttribute("Color")
		local accentCol   = (typeof(rawCol) == "Color3") and rawCol or C.Accent
		local expiresAt   = tonumber(entry:GetAttribute("ExpiresAt")) or 0
		local displayName = entry:GetAttribute("DisplayName") or entry.Name
		local creatorName = entry:GetAttribute("CreatorName") or "?"
		local strongness  = tonumber(entry:GetAttribute("Strongness")) or 0
		local csv         = entry:GetAttribute("IngredientsCsv") or ""
		local bandName, bandColor = strengthBand(strongness)

		local ingredients: { string } = {}
		for token in string.gmatch(csv, "([^,]+)") do
			table.insert(ingredients, token)
		end

		-- Card
		local card = Instance.new("Frame")
		card.Size         = UDim2.new(1, 0, 0, CARD_H)
		card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		card.BorderSizePixel = 0
		card.LayoutOrder  = i
		card.ClipsDescendants = true
		card.Parent = liveScroll
		addCorner(card, 10)
		local cardGrad = Instance.new("UIGradient")
		cardGrad.Rotation = 130
		cardGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 23, 34)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 14, 21)),
		})
		cardGrad.Parent = card

		-- Drink-color left stripe
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 2, 1, 0)
		stripe.BackgroundColor3 = accentCol
		stripe.BorderSizePixel = 0
		stripe.ZIndex = 2
		stripe.Parent = card

		-- ── Mini 2D glass thumbnail ────────────────────────────────────
		local thumb = Instance.new("Frame")
		thumb.Position  = UDim2.new(0, 7, 0, 8)
		thumb.Size      = UDim2.new(0, THUMB_W, 0, CARD_H - 16)
		thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		thumb.BorderSizePixel = 0
		thumb.ClipsDescendants = true
		thumb.ZIndex = 2
		thumb.Parent = card
		addCorner(thumb, 7)
		local thumbGrad = Instance.new("UIGradient")
		thumbGrad.Rotation = 90
		thumbGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(22, 20, 29)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 4, 8)),
		})
		thumbGrad.Parent = thumb

		local thumbFill = Instance.new("Frame")
		thumbFill.AnchorPoint    = Vector2.new(0, 1)
		thumbFill.Position       = UDim2.new(0, 0, 1, 0)
		thumbFill.Size           = UDim2.new(1, 0, 0.68, 0)
		thumbFill.BackgroundColor3 = accentCol
		thumbFill.BorderSizePixel  = 0
		thumbFill.ZIndex = 2
		thumbFill.Parent = thumb

		local thumbGloss = Instance.new("Frame")
		thumbGloss.Size = UDim2.fromScale(1, 1)
		thumbGloss.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		thumbGloss.BackgroundTransparency = 0.87
		thumbGloss.BorderSizePixel = 0
		thumbGloss.ZIndex = 3
		thumbGloss.Parent = thumb
		local glossGrad = Instance.new("UIGradient")
		glossGrad.Rotation = 90
		glossGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.26, 0.72),
			NumberSequenceKeypoint.new(1, 1),
		})
		glossGrad.Parent = thumbGloss

		local timeLabel = Instance.new("TextLabel")
		timeLabel.AnchorPoint = Vector2.new(0.5, 1)
		timeLabel.Position    = UDim2.new(0.5, 0, 1, -4)
		timeLabel.Size        = UDim2.new(1, -4, 0, 11)
		timeLabel.BackgroundTransparency = 1
		timeLabel.Font        = Enum.Font.Montserrat
		timeLabel.TextSize    = 8
		timeLabel.TextColor3  = Color3.fromRGB(190, 186, 204)
		timeLabel.Text        = fmtTime(expiresAt)
		timeLabel.TextXAlignment = Enum.TextXAlignment.Center
		timeLabel.ZIndex      = 4
		timeLabel.Parent      = thumb

		-- ── Right content ──────────────────────────────────────────────
		local content = Instance.new("Frame")
		content.Position = UDim2.new(0, THUMB_W + 16, 0, 8)
		content.Size     = UDim2.new(1, -(THUMB_W + 22), 0, CARD_H - 16)
		content.BackgroundTransparency = 1
		content.ZIndex = 2
		content.Parent = card
		local cLayout = Instance.new("UIListLayout")
		cLayout.Padding = UDim.new(0, 3)
		cLayout.SortOrder = Enum.SortOrder.LayoutOrder
		cLayout.FillDirection = Enum.FillDirection.Vertical
		cLayout.Parent = content

		local nameLabel = mkLabel(content, displayName, 13, true, accentCol)
		nameLabel.Size = UDim2.new(1, 0, 0, 16)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.LayoutOrder = 1
		nameLabel.ZIndex = 2

		local creatorLabel = mkLabel(content, "by @" .. creatorName, 10, false, C.TextMute)
		creatorLabel.Size = UDim2.new(1, 0, 0, 12)
		creatorLabel.TextXAlignment = Enum.TextXAlignment.Left
		creatorLabel.LayoutOrder = 2
		creatorLabel.ZIndex = 2

		-- Strength badge
		local tagRow = Instance.new("Frame")
		tagRow.Size = UDim2.new(1, 0, 0, 16)
		tagRow.BackgroundTransparency = 1
		tagRow.LayoutOrder = 3
		tagRow.ZIndex = 2
		tagRow.Parent = content
		local tagLayout = Instance.new("UIListLayout")
		tagLayout.FillDirection = Enum.FillDirection.Horizontal
		tagLayout.Padding = UDim.new(0, 5)
		tagLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		tagLayout.Parent = tagRow

		local badge = Instance.new("TextLabel")
		badge.Size = UDim2.new(0, 0, 0, 14)
		badge.AutomaticSize = Enum.AutomaticSize.X
		badge.BackgroundColor3 = bandColor
		badge.BackgroundTransparency = 0.72
		badge.BorderSizePixel = 0
		badge.Font = Enum.Font.MontserratBold
		badge.TextSize = 9
		badge.TextColor3 = bandColor
		badge.Text = "  " .. bandName .. "  "
		badge.ZIndex = 2
		badge.Parent = tagRow
		addCorner(badge, 3)

		-- Ingredient chips (first 3 + "+N more")
		local ingRow = Instance.new("Frame")
		ingRow.Size = UDim2.new(1, 0, 0, 14)
		ingRow.BackgroundTransparency = 1
		ingRow.LayoutOrder = 4
		ingRow.ClipsDescendants = true
		ingRow.ZIndex = 2
		ingRow.Parent = content
		local ingLayout = Instance.new("UIListLayout")
		ingLayout.FillDirection = Enum.FillDirection.Horizontal
		ingLayout.Padding = UDim.new(0, 3)
		ingLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		ingLayout.SortOrder = Enum.SortOrder.LayoutOrder
		ingLayout.Parent = ingRow

		local MAX_CHIPS = 3
		for j, ing in ipairs(ingredients) do
			if j > MAX_CHIPS then
				local more = mkLabel(ingRow, "+" .. (#ingredients - MAX_CHIPS), 9, false, C.TextMute)
				more.Size = UDim2.new(0, 20, 0, 12)
				more.LayoutOrder = j
				more.ZIndex = 2
				break
			end
			local chip = Instance.new("TextLabel")
			chip.Size = UDim2.new(0, 0, 0, 12)
			chip.AutomaticSize = Enum.AutomaticSize.X
			chip.BackgroundColor3 = Color3.fromRGB(35, 33, 46)
			chip.BorderSizePixel = 0
			chip.Font = Enum.Font.Montserrat
			chip.TextSize = 8
			chip.TextColor3 = C.TextSub
			chip.Text = "  " .. ing .. "  "
			chip.LayoutOrder = j
			chip.ZIndex = 2
			chip.Parent = ingRow
			addCorner(chip, 3)
		end
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
		if menuPanel.Visible then rebuildLiveList() end
		task.wait(30)
	end
end)

-- ── Panel animations ──────────────────────────────────────────────────────

local menuTween: Tween?    = nil
local creatorTween: Tween? = nil

local function openMenu()
	if menuTween then menuTween:Cancel(); menuTween = nil end
	menuPanel.Size = UDim2.new(0, math.floor(MW * 0.93), 0, math.floor(MH * 0.93))
	menuPanel.Visible = true
	menuTween = TweenService:Create(menuPanel,
		TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, MW, 0, MH) }
	)
	menuTween:Play()
	rebuildLiveList()
	Packets.RequestCustomDrinkState.send({})
end

local function closeMenu()
	if menuTween then menuTween:Cancel(); menuTween = nil end
	menuTween = TweenService:Create(menuPanel,
		TweenInfo.new(0.14, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
		{ Size = UDim2.new(0, math.floor(MW * 0.93), 0, math.floor(MH * 0.93)) }
	)
	menuTween.Completed:Connect(function()
		menuPanel.Visible = false
		menuPanel.Size = UDim2.new(0, MW, 0, MH)
	end)
	menuTween:Play()
end

local function openCreator()
	if creatorTween then creatorTween:Cancel(); creatorTween = nil end
	panel.Size = UDim2.new(0, math.floor(PW * 0.93), 0, math.floor(PH * 0.93))
	panel.Visible = true
	creatorTween = TweenService:Create(panel,
		TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, PW, 0, PH) }
	)
	creatorTween:Play()
	resultLabel.Text = ""
	Packets.RequestCustomDrinkState.send({})
end

local function closeCreator()
	if creatorTween then creatorTween:Cancel(); creatorTween = nil end
	creatorTween = TweenService:Create(panel,
		TweenInfo.new(0.14, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
		{ Size = UDim2.new(0, math.floor(PW * 0.93), 0, math.floor(PH * 0.93)) }
	)
	creatorTween.Completed:Connect(function()
		panel.Visible = false
		panel.Size = UDim2.new(0, PW, 0, PH)
	end)
	creatorTween:Play()
end

-- ── Wiring ────────────────────────────────────────────────────────────────

toggleBtn.Activated:Connect(function()
	if panel.Visible then
		closeCreator(); openMenu()
	elseif menuPanel.Visible then
		closeMenu()
	else
		openMenu()
	end
end)

-- Back from creator → menu: instant-hide creator, spring-open menu
closeBtn.Activated:Connect(function()
	if creatorTween then creatorTween:Cancel(); creatorTween = nil end
	panel.Visible = false
	panel.Size = UDim2.new(0, PW, 0, PH)
	openMenu()
end)

-- Open creator from menu: instant-hide menu, spring-open creator
createDrinkBtn.Activated:Connect(function()
	if menuTween then menuTween:Cancel(); menuTween = nil end
	menuPanel.Visible = false
	menuPanel.Size = UDim2.new(0, MW, 0, MH)
	openCreator()
end)

mCloseBtn.Activated:Connect(closeMenu)

UserInputService.InputBegan:Connect(function(inp, processed)
	if processed then return end
	if inp.KeyCode == Enum.KeyCode.N then
		if panel.Visible then
			if creatorTween then creatorTween:Cancel(); creatorTween = nil end
			panel.Visible = false
			panel.Size = UDim2.new(0, PW, 0, PH)
			openMenu()
		elseif menuPanel.Visible then
			closeMenu()
		else
			openMenu()
		end
	end
end)
