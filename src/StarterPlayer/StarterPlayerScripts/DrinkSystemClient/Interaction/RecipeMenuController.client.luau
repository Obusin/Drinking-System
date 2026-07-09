-- RecipeMenuController: in-game recipe book. Toggle button opens a scrolling
-- list of every NON-SECRET recipe — ingredients in pour order (order matters
-- for the grade!), shaker requirement, garnish, and a strength band.
-- Pure client display; recipes are read straight from the shared config.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystem:WaitForChild("Config")
local Settings = require(ConfigFolder:WaitForChild("Settings"))
local Recipes = require(ConfigFolder:WaitForChild("Recipes"))

if Settings.EnableRecipeMenu == false then
	return
end

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function strengthBand(strongness: number): (string, Color3)
	if strongness < 0 then
		return "Sober-up", Color3.fromRGB(120, 200, 255)
	elseif strongness <= 25 then
		return "Light", Color3.fromRGB(140, 220, 140)
	elseif strongness <= 48 then
		return "Medium", Color3.fromRGB(235, 200, 90)
	elseif strongness <= 75 then
		return "Strong", Color3.fromRGB(240, 140, 70)
	else
		return "Nuclear", Color3.fromRGB(235, 80, 70)
	end
end

local function orderedIngredients(def): {string}
	-- Steps carry the pour ORDER; fall back to the Ingredients list
	local out = {}
	for _, step in ipairs(def.Steps or {}) do
		if step.Ingredient then
			table.insert(out, step.Ingredient)
		end
	end
	if #out == 0 then
		for _, ing in ipairs(def.Ingredients or {}) do
			table.insert(out, ing)
		end
	end
	return out
end

---------------------------------------------------------------------
-- UI scaffold
---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "DS_RecipeMenu"
gui.ResetOnSpawn = false
gui.DisplayOrder = 58
gui.Parent = player:WaitForChild("PlayerGui")

-- Toggle button (right edge, vertically centered)
local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "Toggle"
toggleBtn.AnchorPoint = Vector2.new(1, 0.5)
toggleBtn.Position = UDim2.new(1, -10, 0.5, 0)
toggleBtn.Size = UDim2.new(0, 84, 0, 40)
toggleBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
toggleBtn.BackgroundTransparency = 0.15
toggleBtn.BorderSizePixel = 0
toggleBtn.Text = "Recipes"
toggleBtn.TextSize = 15
toggleBtn.Font = Enum.Font.Montserrat
toggleBtn.Parent = gui
local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 12)
toggleCorner.Parent = toggleBtn

-- Panel
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -62, 0.5, 0)
panel.Size = UDim2.new(0, 300, 0.7, 0)
panel.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
panel.BackgroundTransparency = 0.08
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
title.Size = UDim2.new(1, 0, 0, 42)
title.BackgroundTransparency = 1
title.Font = Enum.Font.MontserratBold
title.Text = "Recipe Book"
title.TextSize = 19
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Parent = panel

local scroll = Instance.new("ScrollingFrame")
scroll.AnchorPoint = Vector2.new(0.5, 1)
scroll.Position = UDim2.new(0.5, 0, 1, -8)
scroll.Size = UDim2.new(1, -16, 1, -54)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.Parent = panel

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 8)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scroll

---------------------------------------------------------------------
-- Recipe cards
---------------------------------------------------------------------
local function buildCard(name: string, def, layoutOrder: number)
	local strongness = def.StrongnessOverride or 0
	local bandName, bandColor = strengthBand(strongness)
	local ingredients = orderedIngredients(def)
	local garnish = def.Presentation and def.Presentation.Garnishes and def.Presentation.Garnishes[1]

	local card = Instance.new("Frame")
	card.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	card.BackgroundTransparency = 0.1
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.LayoutOrder = layoutOrder
	card.Parent = scroll
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 10)
	cardCorner.Parent = card
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = card

	local header = Instance.new("TextLabel")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 20)
	header.Font = Enum.Font.MontserratBold
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextSize = 15
	header.TextColor3 = Color3.fromRGB(255, 255, 255)
	header.Text = def.DisplayName or name
	header.Parent = card

	local band = Instance.new("TextLabel")
	band.BackgroundTransparency = 1
	band.AnchorPoint = Vector2.new(1, 0)
	band.Position = UDim2.new(1, 0, 0, 0)
	band.Size = UDim2.new(0, 90, 0, 20)
	band.Font = Enum.Font.MontserratBold
	band.TextXAlignment = Enum.TextXAlignment.Right
	band.TextSize = 13
	band.TextColor3 = bandColor
	band.Text = bandName
	band.Parent = card

	-- Ingredients in pour order (order affects the grade!)
	local lines = {}
	for i, ing in ipairs(ingredients) do
		table.insert(lines, string.format("%d. %s", i, ing))
	end
	local extras = {}
	if def.RequireShaker then
		table.insert(extras, "Shake to finish")
	end
	if garnish then
		table.insert(extras, "Garnish: " .. garnish .. " (+5)")
	end
	local bodyText = table.concat(lines, "\n")
	if #extras > 0 then
		bodyText ..= "\n" .. table.concat(extras, "   ")
	end

	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.Position = UDim2.new(0, 0, 0, 22)
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Font = Enum.Font.Montserrat
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextSize = 13
	body.TextWrapped = true
	body.TextColor3 = Color3.fromRGB(210, 210, 210)
	body.Text = bodyText
	body.Parent = card
end

-- Sort: lightest first, sober-ups last; secrets never shown
local sorted = {}
for name, def in pairs(Recipes) do
	if def.Secret ~= true then
		table.insert(sorted, { Name = name, Def = def })
	end
end
table.sort(sorted, function(a, b)
	local sa = a.Def.StrongnessOverride or 0
	local sb = b.Def.StrongnessOverride or 0
	if (sa < 0) ~= (sb < 0) then
		return sb < 0  -- sober-ups sort to the bottom
	end
	if sa ~= sb then
		return sa < sb
	end
	return a.Name < b.Name
end)
for i, entry in ipairs(sorted) do
	buildCard(entry.Name, entry.Def, i)
end

---------------------------------------------------------------------
-- Toggle
---------------------------------------------------------------------
local function setOpen(open: boolean)
	panel.Visible = open
	toggleBtn.Text = open and "Close" or "Recipes"
end

toggleBtn.Activated:Connect(function()
	setOpen(not panel.Visible)
end)

-- B key toggles on keyboard
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.B then
		setOpen(not panel.Visible)
	end
end)
