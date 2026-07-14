-- CustomDrinkController: "Drink Lab" composer for paid player-created drinks.
-- Toggle with the N key or the Drink Lab button (under the Recipes toggle).
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

local tokens = 0
local activeName: string? = nil
local picks: { string } = {}
local chosenColor = COLOR_SWATCHES[3]

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
panel.Size = UDim2.new(0, 380, 0, 470)
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

local statusLabel = Instance.new("TextLabel")
statusLabel.Position = UDim2.new(0, 14, 0, 38)
statusLabel.Size = UDim2.new(1, -28, 0, 18)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Montserrat
statusLabel.TextSize = 12
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
statusLabel.Text = ""
statusLabel.Parent = panel

-- Name box
local nameBox = Instance.new("TextBox")
nameBox.Position = UDim2.new(0, 14, 0, 62)
nameBox.Size = UDim2.new(1, -28, 0, 34)
nameBox.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
nameBox.BorderSizePixel = 0
nameBox.Font = Enum.Font.Montserrat
nameBox.PlaceholderText = "Name your drink…"
nameBox.Text = ""
nameBox.TextSize = 15
nameBox.TextColor3 = Color3.fromRGB(255, 255, 255)
nameBox.ClearTextOnFocus = false
nameBox.Parent = panel
local nameCorner = Instance.new("UICorner")
nameCorner.CornerRadius = UDim.new(0, 10)
nameCorner.Parent = nameBox

-- Picked ingredients row
local picksLabel = Instance.new("TextLabel")
picksLabel.Position = UDim2.new(0, 14, 0, 102)
picksLabel.Size = UDim2.new(1, -28, 0, 30)
picksLabel.BackgroundColor3 = Color3.fromRGB(26, 26, 26)
picksLabel.BorderSizePixel = 0
picksLabel.Font = Enum.Font.Montserrat
picksLabel.TextSize = 13
picksLabel.TextColor3 = Color3.fromRGB(230, 210, 150)
picksLabel.Text = ""
picksLabel.TextWrapped = true
picksLabel.Parent = panel
local picksCorner = Instance.new("UICorner")
picksCorner.CornerRadius = UDim.new(0, 8)
picksCorner.Parent = picksLabel

-- Ingredient grid
local grid = Instance.new("ScrollingFrame")
grid.Position = UDim2.new(0, 14, 0, 140)
grid.Size = UDim2.new(1, -28, 0, 200)
grid.BackgroundTransparency = 1
grid.BorderSizePixel = 0
grid.ScrollBarThickness = 4
grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
grid.CanvasSize = UDim2.new(0, 0, 0, 0)
grid.Parent = panel
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0, 110, 0, 30)
gridLayout.CellPadding = UDim2.new(0, 6, 0, 6)
gridLayout.SortOrder = Enum.SortOrder.Name
gridLayout.Parent = grid

-- Color swatch row
local swatchRow = Instance.new("Frame")
swatchRow.Position = UDim2.new(0, 14, 0, 348)
swatchRow.Size = UDim2.new(1, -28, 0, 26)
swatchRow.BackgroundTransparency = 1
swatchRow.Parent = panel
local swatchLayout = Instance.new("UIListLayout")
swatchLayout.FillDirection = Enum.FillDirection.Horizontal
swatchLayout.Padding = UDim.new(0, 5)
swatchLayout.Parent = swatchRow

-- Result message
local resultLabel = Instance.new("TextLabel")
resultLabel.Position = UDim2.new(0, 14, 1, -78)
resultLabel.Size = UDim2.new(1, -28, 0, 30)
resultLabel.BackgroundTransparency = 1
resultLabel.Font = Enum.Font.Montserrat
resultLabel.TextSize = 13
resultLabel.TextWrapped = true
resultLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
resultLabel.Text = ""
resultLabel.Parent = panel

-- Submit button
local submitBtn = Instance.new("TextButton")
submitBtn.AnchorPoint = Vector2.new(0.5, 1)
submitBtn.Position = UDim2.new(0.5, 0, 1, -12)
submitBtn.Size = UDim2.new(1, -28, 0, 38)
submitBtn.BackgroundColor3 = Color3.fromRGB(30, 120, 60)
submitBtn.BorderSizePixel = 0
submitBtn.Font = Enum.Font.MontserratBold
submitBtn.TextSize = 15
submitBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
submitBtn.Text = "Create Drink"
submitBtn.Parent = panel
local submitCorner = Instance.new("UICorner")
submitCorner.CornerRadius = UDim.new(0, 10)
submitCorner.Parent = submitBtn

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

local function refreshStatus()
	if activeName then
		statusLabel.Text = ('Your drink "%s" is live on the menu!'):format(activeName)
		submitBtn.Text = "Drink already active"
		submitBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	elseif tokens > 0 then
		statusLabel.Text = ("Creation slots: %d"):format(tokens)
		submitBtn.Text = "Create Drink"
		submitBtn.BackgroundColor3 = Color3.fromRGB(30, 120, 60)
	else
		statusLabel.Text = "No creation slot — purchase one to put YOUR drink on the menu"
		submitBtn.Text = "Buy a Drink Slot"
		submitBtn.BackgroundColor3 = Color3.fromRGB(120, 90, 20)
	end
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
refreshStatus()

---------------------------------------------------------------------
-- Networking
---------------------------------------------------------------------
Packets.CustomDrinkState.listen(function(data)
	tokens = data.Tokens or 0
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
	if tokens <= 0 then
		local productId = Settings.CustomDrinkProductId
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
	local r = math.floor(chosenColor.R * 255)
	local g = math.floor(chosenColor.G * 255)
	local b = math.floor(chosenColor.B * 255)
	Packets.SubmitCustomDrink.send({
		Name = nameBox.Text,
		Ingredients = picks,
		ColorR = r,
		ColorG = g,
		ColorB = b,
	})
	resultLabel.Text = "Mixing it up…"
	resultLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
end)

---------------------------------------------------------------------
-- Toggle
---------------------------------------------------------------------
local function setOpen(open: boolean)
	panel.Visible = open
	if open then
		resultLabel.Text = ""
		Packets.RequestCustomDrinkState.send({})
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
