-- CustomDrinkController: "Drink Lab" composer for paid player-created drinks.
-- Toggle with the N key or the Drink Lab button (under the Recipes toggle).
-- Left column: build your drink (name, ingredients, color, duration tier).
-- Right column: every custom drink currently live — mix order + time left,
-- so anyone can learn and pour them.
-- Server validates everything; this UI is just a nice way to build the request.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer

local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystem:WaitForChild("Config")
local SharedModules = DrinkSystem:WaitForChild("SharedModules")

local Settings = require(ConfigFolder:WaitForChild("Settings"))
local IngredientRegistry = require(SharedModules:WaitForChild("IngredientRegistry"))
local Network = require(SharedModules:WaitForChild("Network"))
local Packets = Network.Packets

local MAX_PICKS = 4
local MIN_PICKS = 2
local DURATION_OPTIONS = { 4, 8, 12, 24 }

local COLOR_SWATCHES = {
	Color3.fromRGB(235, 80, 70),
	Color3.fromRGB(255, 146, 76),
	Color3.fromRGB(255, 205, 80),
	Color3.fromRGB(140, 220, 140),
	Color3.fromRGB(60, 170, 110),
	Color3.fromRGB(100, 180, 255),
	Color3.fromRGB(91, 120, 255),
	Color3.fromRGB(170, 110, 240),
	Color3.fromRGB(230, 120, 200),
	Color3.fromRGB(150, 102, 79),
	Color3.fromRGB(40, 40, 50),
	Color3.fromRGB(235, 215, 180),
}

local tokenHours: { number } = {}
local activeName: string? = nil
local picks: { string } = {}
local chosenColor = COLOR_SWATCHES[3]
local chosenHours = 24

---------------------------------------------------------------------
-- UI scaffold (matches RecipeMenu styling)
---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "DS_DrinkLab"
gui.ResetOnSpawn = false
gui.DisplayOrder = 59
gui.Parent = player:WaitForChild("PlayerGui")

local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "Toggle"
toggleBtn.AnchorPoint = Vector2.new(1, 0.5)
toggleBtn.Position = UDim2.new(1, -10, 0.5, 48)
toggleBtn.Size = UDim2.new(0, 84, 0, 40)
toggleBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
toggleBtn.BackgroundTransparency = 0.15
toggleBtn.BorderSizePixel = 0
toggleBtn.Text = "Drink Lab"
toggleBtn.TextSize = 14
toggleBtn.Font = Enum.Font.Montserrat
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Parent = gui
local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 12)
toggleCorner.Parent = toggleBtn

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.new(0, 660, 0, 560)
panel.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
panel.BackgroundTransparency = 0.06
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 14)
panelCorner.Parent = panel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(70, 70, 70)
panelStroke.Thickness = 1
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 40)
title.BackgroundTransparency = 1
title.Font = Enum.Font.MontserratBold
title.Text = "Drink Lab"
title.TextSize = 19
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Parent = panel

-- ── Left column: composer ────────────────────────────────────────
local composer = Instance.new("Frame")
composer.Position = UDim2.new(0, 14, 0, 40)
composer.Size = UDim2.new(0, 370, 1, -54)
composer.BackgroundTransparency = 1
composer.Parent = panel

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 18)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Montserrat
statusLabel.TextSize = 12
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
statusLabel.Text = ""
statusLabel.Parent = composer

local nameBox = Instance.new("TextBox")
nameBox.Position = UDim2.new(0, 0, 0, 24)
nameBox.Size = UDim2.new(1, 0, 0, 34)
nameBox.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
nameBox.BorderSizePixel = 0
nameBox.Font = Enum.Font.Montserrat
nameBox.PlaceholderText = "Name your drink…"
nameBox.Text = ""
nameBox.TextSize = 15
nameBox.TextColor3 = Color3.fromRGB(255, 255, 255)
nameBox.ClearTextOnFocus = false
nameBox.Parent = composer
local nameCorner = Instance.new("UICorner")
nameCorner.CornerRadius = UDim.new(0, 10)
nameCorner.Parent = nameBox

local picksLabel = Instance.new("TextLabel")
picksLabel.Position = UDim2.new(0, 0, 0, 64)
picksLabel.Size = UDim2.new(1, 0, 0, 30)
picksLabel.BackgroundColor3 = Color3.fromRGB(26, 26, 26)
picksLabel.BorderSizePixel = 0
picksLabel.Font = Enum.Font.Montserrat
picksLabel.TextSize = 13
picksLabel.TextColor3 = Color3.fromRGB(230, 210, 150)
picksLabel.Text = ""
picksLabel.TextWrapped = true
picksLabel.Parent = composer
local picksCorner = Instance.new("UICorner")
picksCorner.CornerRadius = UDim.new(0, 8)
picksCorner.Parent = picksLabel

local grid = Instance.new("ScrollingFrame")
grid.Position = UDim2.new(0, 0, 0, 100)
grid.Size = UDim2.new(1, 0, 0, 190)
grid.BackgroundTransparency = 1
grid.BorderSizePixel = 0
grid.ScrollBarThickness = 4
grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
grid.CanvasSize = UDim2.new(0, 0, 0, 0)
grid.Parent = composer
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0, 116, 0, 28)
gridLayout.CellPadding = UDim2.new(0, 6, 0, 6)
gridLayout.SortOrder = Enum.SortOrder.Name
gridLayout.Parent = grid

-- Color swatch row
local swatchRow = Instance.new("Frame")
swatchRow.Position = UDim2.new(0, 0, 0, 298)
swatchRow.Size = UDim2.new(1, 0, 0, 26)
swatchRow.BackgroundTransparency = 1
swatchRow.Parent = composer
local swatchLayout = Instance.new("UIListLayout")
swatchLayout.FillDirection = Enum.FillDirection.Horizontal
swatchLayout.Padding = UDim.new(0, 5)
swatchLayout.Parent = swatchRow

-- Drunkness slider (5 → dynamic ceiling based on picked ingredients)
local STRONGNESS_MIN = 5
local STRONGNESS_HARD_CAP = 75
local STRONGNESS_PER_ALCOHOL = 22 -- mirror of the server ceiling formula
local chosenStrongness = 40

local sliderRow = Instance.new("Frame")
sliderRow.Position = UDim2.new(0, 0, 0, 332)
sliderRow.Size = UDim2.new(1, 0, 0, 34)
sliderRow.BackgroundTransparency = 1
sliderRow.Parent = composer

local sliderLabel = Instance.new("TextLabel")
sliderLabel.Size = UDim2.new(0, 118, 1, 0)
sliderLabel.BackgroundTransparency = 1
sliderLabel.Font = Enum.Font.Montserrat
sliderLabel.TextSize = 12
sliderLabel.TextXAlignment = Enum.TextXAlignment.Left
sliderLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
sliderLabel.Text = ""
sliderLabel.Parent = sliderRow

local track = Instance.new("Frame")
track.AnchorPoint = Vector2.new(0, 0.5)
track.Position = UDim2.new(0, 122, 0.5, 0)
track.Size = UDim2.new(1, -122, 0, 6)
track.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
track.BorderSizePixel = 0
track.Parent = sliderRow
local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(1, 0)
trackCorner.Parent = track

local fill = Instance.new("Frame")
fill.Size = UDim2.new(0, 0, 1, 0)
fill.BackgroundColor3 = Color3.fromRGB(235, 200, 90)
fill.BorderSizePixel = 0
fill.Parent = track
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = fill

local knob = Instance.new("TextButton")
knob.AnchorPoint = Vector2.new(0.5, 0.5)
knob.Position = UDim2.new(0, 0, 0.5, 0)
knob.Size = UDim2.new(0, 18, 0, 18)
knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
knob.BorderSizePixel = 0
knob.Text = ""
knob.ZIndex = 2
knob.Parent = track
local knobCorner = Instance.new("UICorner")
knobCorner.CornerRadius = UDim.new(1, 0)
knobCorner.Parent = knob

local function strengthBand(v: number): (string, Color3)
	if v <= 25 then
		return "Light", Color3.fromRGB(140, 220, 140)
	elseif v <= 48 then
		return "Medium", Color3.fromRGB(235, 200, 90)
	elseif v <= 75 then
		return "Strong", Color3.fromRGB(240, 140, 70)
	else
		return "Nuclear", Color3.fromRGB(235, 80, 70)
	end
end

-- Ceiling mirrors the server: alcoholic picks raise it, mixers barely do.
-- (Server re-derives and clamps — this is just honest UI.)
local function strongnessCeiling(): number
	local ceiling = 0
	for _, ingName in ipairs(picks) do
		local def = IngredientRegistry.get(ingName)
		if def and (def.Strongness or 0) > 0 then
			ceiling += STRONGNESS_PER_ALCOHOL
		else
			ceiling += 4
		end
	end
	return math.clamp(ceiling, STRONGNESS_MIN, STRONGNESS_HARD_CAP)
end

local function refreshSlider()
	local ceiling = strongnessCeiling()
	chosenStrongness = math.clamp(chosenStrongness, STRONGNESS_MIN, ceiling)
	local alpha = (chosenStrongness - STRONGNESS_MIN) / math.max(STRONGNESS_HARD_CAP - STRONGNESS_MIN, 1)
	knob.Position = UDim2.new(alpha, 0, 0.5, 0)
	fill.Size = UDim2.new(alpha, 0, 1, 0)
	local bandName, bandColor = strengthBand(chosenStrongness)
	fill.BackgroundColor3 = bandColor
	sliderLabel.Text = ("Drunkness: %d  %s"):format(chosenStrongness, bandName)
	sliderLabel.TextColor3 = bandColor
end

local draggingSlider = false
local function setFromX(x: number)
	local alpha = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
	chosenStrongness = math.floor(STRONGNESS_MIN + alpha * (STRONGNESS_HARD_CAP - STRONGNESS_MIN) + 0.5)
	refreshSlider()
end

local function beginDrag(input: InputObject)
	draggingSlider = true
	setFromX(input.Position.X)
end
knob.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		beginDrag(input)
	end
end)
track.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		beginDrag(input)
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		setFromX(input.Position.X)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		draggingSlider = false
	end
end)

-- Duration tier row (4h / 8h / 12h / 24h)
local durationRow = Instance.new("Frame")
durationRow.Position = UDim2.new(0, 0, 0, 372)
durationRow.Size = UDim2.new(1, 0, 0, 30)
durationRow.BackgroundTransparency = 1
durationRow.Parent = composer
local durationLayout = Instance.new("UIListLayout")
durationLayout.FillDirection = Enum.FillDirection.Horizontal
durationLayout.Padding = UDim.new(0, 6)
durationLayout.Parent = durationRow

local resultLabel = Instance.new("TextLabel")
resultLabel.Position = UDim2.new(0, 0, 1, -86)
resultLabel.Size = UDim2.new(1, 0, 0, 32)
resultLabel.BackgroundTransparency = 1
resultLabel.Font = Enum.Font.Montserrat
resultLabel.TextSize = 13
resultLabel.TextWrapped = true
resultLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
resultLabel.Text = ""
resultLabel.Parent = composer

local submitBtn = Instance.new("TextButton")
submitBtn.AnchorPoint = Vector2.new(0, 1)
submitBtn.Position = UDim2.new(0, 0, 1, -8)
submitBtn.Size = UDim2.new(1, 0, 0, 38)
submitBtn.BackgroundColor3 = Color3.fromRGB(30, 120, 60)
submitBtn.BorderSizePixel = 0
submitBtn.Font = Enum.Font.MontserratBold
submitBtn.TextSize = 15
submitBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
submitBtn.Text = "Create Drink"
submitBtn.Parent = composer
local submitCorner = Instance.new("UICorner")
submitCorner.CornerRadius = UDim.new(0, 10)
submitCorner.Parent = submitBtn

-- ── Right column: live custom drinks ("On the Menu") ─────────────
local liveColumn = Instance.new("Frame")
liveColumn.Position = UDim2.new(0, 398, 0, 40)
liveColumn.Size = UDim2.new(0, 248, 1, -54)
liveColumn.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
liveColumn.BorderSizePixel = 0
liveColumn.Parent = panel
local liveCorner = Instance.new("UICorner")
liveCorner.CornerRadius = UDim.new(0, 10)
liveCorner.Parent = liveColumn

local liveTitle = Instance.new("TextLabel")
liveTitle.Size = UDim2.new(1, 0, 0, 30)
liveTitle.BackgroundTransparency = 1
liveTitle.Font = Enum.Font.MontserratBold
liveTitle.Text = "On the Menu"
liveTitle.TextSize = 14
liveTitle.TextColor3 = Color3.fromRGB(230, 210, 150)
liveTitle.Parent = liveColumn

local liveScroll = Instance.new("ScrollingFrame")
liveScroll.Position = UDim2.new(0, 8, 0, 32)
liveScroll.Size = UDim2.new(1, -16, 1, -40)
liveScroll.BackgroundTransparency = 1
liveScroll.BorderSizePixel = 0
liveScroll.ScrollBarThickness = 4
liveScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
liveScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
liveScroll.Parent = liveColumn
local liveLayout = Instance.new("UIListLayout")
liveLayout.Padding = UDim.new(0, 6)
liveLayout.SortOrder = Enum.SortOrder.LayoutOrder
liveLayout.Parent = liveScroll

local function formatTimeLeft(expiresAt: number): string
	local remaining = math.max(expiresAt - os.time(), 0)
	local hours = math.floor(remaining / 3600)
	local minutes = math.floor((remaining % 3600) / 60)
	if hours > 0 then
		return ("%dh %dm left"):format(hours, minutes)
	end
	return ("%dm left"):format(math.max(minutes, 1))
end

local function rebuildLiveList()
	for _, child in ipairs(liveScroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local dynamicFolder = DrinkSystem:FindFirstChild("DynamicRecipes")
	local entries = dynamicFolder and dynamicFolder:GetChildren() or {}
	if #entries == 0 then
		local empty = Instance.new("Frame")
		empty.Size = UDim2.new(1, 0, 0, 60)
		empty.BackgroundTransparency = 1
		empty.Parent = liveScroll
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.Montserrat
		lbl.TextSize = 12
		lbl.TextWrapped = true
		lbl.TextColor3 = Color3.fromRGB(150, 150, 150)
		lbl.Text = "No custom drinks live right now.\nYours could be first!"
		lbl.Parent = empty
		return
	end
	for i, entry in ipairs(entries) do
		local csv = entry:GetAttribute("IngredientsCsv") or ""
		local steps = {}
		local n = 0
		for token in string.gmatch(csv, "([^,]+)") do
			n += 1
			table.insert(steps, ("%d. %s"):format(n, token))
		end
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
		card.BorderSizePixel = 0
		card.LayoutOrder = i
		card.Parent = liveScroll
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0, 8)
		cc.Parent = card
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 6)
		pad.PaddingBottom = UDim.new(0, 6)
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.Parent = card

		local header = Instance.new("TextLabel")
		header.Size = UDim2.new(1, 0, 0, 16)
		header.BackgroundTransparency = 1
		header.Font = Enum.Font.MontserratBold
		header.TextSize = 13
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.TextColor3 = entry:GetAttribute("Color") or Color3.fromRGB(255, 255, 255)
		header.Text = entry:GetAttribute("DisplayName") or entry.Name
		header.Parent = card

		local expiresAt = tonumber(entry:GetAttribute("ExpiresAt")) or 0
		local body = Instance.new("TextLabel")
		body.Position = UDim2.new(0, 0, 0, 18)
		body.Size = UDim2.new(1, 0, 0, 0)
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.BackgroundTransparency = 1
		body.Font = Enum.Font.Montserrat
		body.TextSize = 11
		body.TextWrapped = true
		body.TextXAlignment = Enum.TextXAlignment.Left
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.TextColor3 = Color3.fromRGB(205, 205, 205)
		body.Text = table.concat(steps, "\n")
			.. ("\nby %s   •   %s"):format(entry:GetAttribute("CreatorName") or "?", formatTimeLeft(expiresAt))
		body.Parent = card
	end
end

---------------------------------------------------------------------
-- State + refresh
---------------------------------------------------------------------
local function refreshPicksLabel()
	if #picks == 0 then
		picksLabel.Text = ("  Pick %d-%d ingredients"):format(MIN_PICKS, MAX_PICKS)
	else
		picksLabel.Text = "  " .. table.concat(picks, "  •  ")
	end
end

local function ownsHours(hours: number): boolean
	for _, h in ipairs(tokenHours) do
		if h == hours then
			return true
		end
	end
	return false
end

local function refreshStatus()
	local freeTesting = Settings.CustomDrinkFreeTesting == true
	if activeName then
		statusLabel.Text = ('Your drink "%s" is live on the menu!'):format(activeName)
		submitBtn.Text = "Drink already active"
		submitBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	elseif freeTesting or ownsHours(chosenHours) then
		if freeTesting then
			statusLabel.Text = "Free testing mode — create away!"
		else
			statusLabel.Text = ("Slots owned: %d"):format(#tokenHours)
		end
		submitBtn.Text = ("Create Drink (%dh)"):format(chosenHours)
		submitBtn.BackgroundColor3 = Color3.fromRGB(30, 120, 60)
	else
		statusLabel.Text = "Pick a duration, then buy the slot to go live"
		submitBtn.Text = ("Buy %dh Slot"):format(chosenHours)
		submitBtn.BackgroundColor3 = Color3.fromRGB(120, 90, 20)
	end
end

-- Duration buttons
local durationButtons: { [number]: TextButton } = {}
local function refreshDurationSelection()
	for hours, btn in pairs(durationButtons) do
		local selected = hours == chosenHours
		btn.BackgroundColor3 = selected and Color3.fromRGB(60, 90, 140) or Color3.fromRGB(34, 34, 34)
		local stroke = btn:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = selected and 0 or 1
		end
	end
	refreshStatus()
end
for _, hours in ipairs(DURATION_OPTIONS) do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 62, 1, 0)
	btn.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.MontserratBold
	btn.TextSize = 13
	btn.TextColor3 = Color3.fromRGB(235, 235, 235)
	btn.Text = hours .. "h"
	btn.Parent = durationRow
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = btn
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(140, 180, 255)
	stroke.Thickness = 1.5
	stroke.Transparency = 1
	stroke.Parent = btn
	durationButtons[hours] = btn
	btn.Activated:Connect(function()
		chosenHours = hours
		refreshDurationSelection()
	end)
end

-- Ingredient buttons (Water excluded — server rejects it anyway)
local names = IngredientRegistry.listNames()
table.sort(names)
for _, ingName in ipairs(names) do
	if ingName ~= "Water" then
		local btn = Instance.new("TextButton")
		btn.Name = ingName
		btn.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
		btn.BorderSizePixel = 0
		btn.Font = Enum.Font.Montserrat
		btn.TextSize = 12
		btn.TextColor3 = Color3.fromRGB(235, 235, 235)
		btn.Text = ingName
		btn.Parent = grid
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = btn
		btn.Activated:Connect(function()
			-- Tap to add (duplicates allowed — doubles make it stronger),
			-- tap while at cap removes the last copy of that ingredient
			local existingAt = nil
			for i = #picks, 1, -1 do
				if picks[i] == ingName then
					existingAt = i
					break
				end
			end
			if #picks >= MAX_PICKS then
				if existingAt then
					table.remove(picks, existingAt)
				end
			else
				table.insert(picks, ingName)
			end
			refreshPicksLabel()
		end)
	end
end

-- Clear picks by tapping the picks row
local picksClear = Instance.new("TextButton")
picksClear.Size = UDim2.fromScale(1, 1)
picksClear.BackgroundTransparency = 1
picksClear.Text = ""
picksClear.Parent = picksLabel
picksClear.Activated:Connect(function()
	picks = {}
	refreshPicksLabel()
end)

-- Swatches
local swatchButtons: { TextButton } = {}
local function refreshSwatchSelection()
	for _, b in ipairs(swatchButtons) do
		local stroke = b:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = (b.BackgroundColor3 == chosenColor) and 0 or 1
		end
	end
end
for _, color in ipairs(COLOR_SWATCHES) do
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 24, 0, 24)
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Text = ""
	b.Parent = swatchRow
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 2
	stroke.Transparency = 1
	stroke.Parent = b
	table.insert(swatchButtons, b)
	b.Activated:Connect(function()
		chosenColor = color
		refreshSwatchSelection()
	end)
end
refreshSwatchSelection()
refreshPicksLabel()
refreshDurationSelection()
refreshSlider()

---------------------------------------------------------------------
-- Networking
---------------------------------------------------------------------
Packets.CustomDrinkState.listen(function(data)
	tokenHours = data.TokenHours or {}
	activeName = data.ActiveName
	refreshStatus()
end)

Packets.CustomDrinkResult.listen(function(data)
	resultLabel.Text = data.Message or ""
	resultLabel.TextColor3 = data.Ok and Color3.fromRGB(140, 230, 140) or Color3.fromRGB(240, 130, 120)
	if data.Ok then
		picks = {}
		nameBox.Text = ""
		refreshPicksLabel()
	end
end)

submitBtn.Activated:Connect(function()
	if activeName then return end
	local freeTesting = Settings.CustomDrinkFreeTesting == true
	if not freeTesting and not ownsHours(chosenHours) then
		local products = Settings.CustomDrinkProducts or {}
		local productId = products[chosenHours]
		if productId and productId ~= 0 then
			MarketplaceService:PromptProductPurchase(player, productId)
		else
			resultLabel.Text = "Purchases aren't set up yet"
			resultLabel.TextColor3 = Color3.fromRGB(240, 130, 120)
		end
		return
	end
	if #picks < MIN_PICKS then
		resultLabel.Text = ("Pick at least %d ingredients"):format(MIN_PICKS)
		resultLabel.TextColor3 = Color3.fromRGB(240, 130, 120)
		return
	end
	Packets.SubmitCustomDrink.send({
		Name = nameBox.Text,
		Ingredients = picks,
		ColorR = math.floor(chosenColor.R * 255),
		ColorG = math.floor(chosenColor.G * 255),
		ColorB = math.floor(chosenColor.B * 255),
		Hours = chosenHours,
		Strongness = chosenStrongness,
	})
	resultLabel.Text = "Mixing it up…"
	resultLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
end)

---------------------------------------------------------------------
-- Live list wiring: rebuild on folder changes + tick the countdowns
---------------------------------------------------------------------
task.spawn(function()
	local dynamicFolder = DrinkSystem:WaitForChild("DynamicRecipes", 60)
	if dynamicFolder then
		dynamicFolder.ChildAdded:Connect(function()
			task.defer(rebuildLiveList)
		end)
		dynamicFolder.ChildRemoved:Connect(function()
			task.defer(rebuildLiveList)
		end)
	end
	while true do
		if panel.Visible then
			rebuildLiveList()
		end
		task.wait(30)
	end
end)

---------------------------------------------------------------------
-- Toggle
---------------------------------------------------------------------
local function setOpen(open: boolean)
	panel.Visible = open
	if open then
		resultLabel.Text = ""
		Packets.RequestCustomDrinkState.send({})
		rebuildLiveList()
	end
end

toggleBtn.Activated:Connect(function()
	setOpen(not panel.Visible)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.N then
		setOpen(not panel.Visible)
	end
end)
