-- ServerScriptService/DrinkSystem/DrinkCreationManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DrinkSystemFolder = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystemFolder:WaitForChild("Config")
local SharedModulesFolder = DrinkSystemFolder:WaitForChild("SharedModules")

local Settings = require(ConfigFolder:WaitForChild("Settings"))
local GlassPresentation = require(SharedModulesFolder:WaitForChild("GlassPresentation"))

local DrinkCreationManager = {}

-- Store drinks that are waiting for shaker to finish
local pendingDrinks: { [Player]: { Data: table, GlassTool: Tool? } } = {}

-- Find the currently equipped glass Tool for this player
local function findGlassTool(player: Player): Tool?
	local char = player.Character
	local backpack = player:FindFirstChild("Backpack")

	local glassNames = Settings.GlassToolNames or {}
	local function scan(container)
		if not container then return nil end
		for _, inst in ipairs(container:GetChildren()) do
			if inst:IsA("Tool") then
				for _, gName in ipairs(glassNames) do
					if inst.Name == gName or inst:GetAttribute("DS_GlassTool") == true then
						return inst :: Tool
					end
				end
			end
		end
	end

	-- Prefer the one in Character (equipped)
	local tool = scan(char)
	if tool then return tool end

	-- Fallback to backpack
	return scan(backpack)
end

-- Apply color + attributes to the glass
local function applyDrinkToGlassTool(glassTool: Tool, drinkData: table)
	-- Mark as a drink
	glassTool:SetAttribute("DS_Drink", true)
	glassTool:SetAttribute("DS_DrinkTool", true)
	glassTool:SetAttribute("DS_GlassTool", true)
	glassTool:SetAttribute("DS_DrinkName", drinkData.DisplayName or drinkData.RecipeName or "Custom Drink")
	glassTool:SetAttribute("DS_Strongness", drinkData.Strongness or 0)
	glassTool:SetAttribute("DS_IsRecipe", drinkData.IsRecipe == true)
	glassTool:SetAttribute("DS_RecipeName", drinkData.RecipeName or "")
	glassTool:SetAttribute("DS_Color", drinkData.Color or Color3.new(1,1,1))
	if drinkData.Outcome then
		glassTool:SetAttribute("DS_Outcome", drinkData.Outcome)
	end
	if drinkData.Score then
		glassTool:SetAttribute("DS_Score", drinkData.Score)
	end
	local baseIngredient = drinkData.BaseIngredient
	if type(baseIngredient) ~= "string" or baseIngredient == "" then
		if drinkData.Ingredients and #drinkData.Ingredients > 0 then
			baseIngredient = drinkData.Ingredients[1]
		else
			baseIngredient = nil
		end
	end
	if baseIngredient then
		glassTool:SetAttribute("DS_BaseIngredient", baseIngredient)
	end

	-- Sip configuration: recipe override first (e.g. Sin Obu = 1 sip), then glass
	local maxSips = drinkData.Sips
	if typeof(maxSips) ~= "number" or maxSips <= 0 then
		maxSips = glassTool:GetAttribute("DS_MaxSips")
	end
	if typeof(maxSips) ~= "number" or maxSips <= 0 then
		maxSips = glassTool:GetAttribute("MaxSips")
	end
	if typeof(maxSips) ~= "number" or maxSips <= 0 then
		maxSips = Settings.DefaultDrinkSips or 1
	end
	glassTool:SetAttribute("DS_MaxSips", maxSips)
	glassTool:SetAttribute("MaxSips", maxSips)
	glassTool:SetAttribute("DS_SipsMax", maxSips)
	glassTool:SetAttribute("DS_SipsRemaining", maxSips)

	-- Optional: ingredients list as a string
	if drinkData.Ingredients and #drinkData.Ingredients > 0 then
		if Settings.EnableDrunkDebug == true then
			print("[DrinkSystem][Glass] Ingredients:", table.concat(drinkData.Ingredients, ", "))
		end
		glassTool:SetAttribute("DS_IngredientsText", table.concat(drinkData.Ingredients, ", "))
		glassTool:SetAttribute("DS_IngredientListCsv", table.concat(drinkData.Ingredients, ","))
	end
	glassTool:SetAttribute("DS_FillStage", drinkData.FillStage or 1)
	glassTool:SetAttribute("DS_GarnishesCsv", table.concat(drinkData.Garnishes or {}, ","))

	-- Color and show liquid
	local liquid = glassTool:FindFirstChild("LiquidPart", true)
	if liquid and liquid:IsA("BasePart") then
		liquid.Color = drinkData.Color or Color3.new(1,1,1)
		liquid.Transparency = 0.1
	end
	GlassPresentation.applyFinalPresentation(
		glassTool,
		drinkData.FillStage or 1,
		drinkData.Color,
		drinkData.Garnishes or {}
	)

	-- Water looks like water: blue tint comes from the recipe color, and the
	-- liquid is extra transparent instead of an opaque fill.
	if drinkData.RecipeName == "Water" then
		GlassPresentation.setLiquidTransparency(glassTool, 0.5)
	elseif drinkData.RecipeName == "Solaire's Spit" then
		GlassPresentation.setLiquidTransparency(glassTool, 0.3)  -- milky white
	end

	-- Naming rule:
	-- - Valid recipe: recipe display name
	-- - Non-recipe/invalid: base ingredient (or payload display fallback, e.g. Toxication)
	if drinkData.IsRecipe == true and drinkData.DisplayName then
		glassTool.Name = drinkData.DisplayName
	elseif drinkData.DisplayName == "Toxication" then
		glassTool.Name = "Toxication"
	elseif baseIngredient then
		glassTool.Name = baseIngredient
	elseif drinkData.DisplayName then
		glassTool.Name = drinkData.DisplayName
	end
end

-- Build a standardized drinkData structure from MixingManager payload + optional ingredients
local function normalizeDrinkData(payload: table, ingredients: {string}?, isRecipe: boolean): table
	local data = {}

	data.DisplayName = payload.DisplayName or payload.RecipeName or "Custom Drink"
	data.RecipeName = payload.RecipeName -- may be nil for partials
	data.Color = payload.Color or Color3.new(1,1,1)
	data.Strongness = payload.Strongness or 0
	data.IsRecipe = isRecipe
	data.Ingredients = ingredients or payload.Ingredients or {}
	data.BaseIngredient = payload.BaseIngredient
	data.Garnishes = payload.Garnishes or {}
	data.Sips = payload.Sips
	if (type(data.BaseIngredient) ~= "string" or data.BaseIngredient == "") and #data.Ingredients > 0 then
		data.BaseIngredient = data.Ingredients[1]
	end
	-- Recipes can force a fill stage (e.g. Water fills the glass in one pour)
	data.FillStage = payload.FillStage or math.clamp(#data.Ingredients, 1, 3)

	return data
end

-- PUBLIC: prepare a drink that will be finalized after shaker animation
function DrinkCreationManager.preparePendingDrink(player: Player, payload: table, ingredients: {string}?, glassTool: Tool?)
	local drinkData = normalizeDrinkData(payload, ingredients, true)
	pendingDrinks[player] = {
		Data = drinkData,
		GlassTool = glassTool,
	}
end

-- PUBLIC: called when shaker animation finishes
function DrinkCreationManager.finalizePendingDrink(player: Player, glassTool: Tool?): boolean
	local pending = pendingDrinks[player]
	if not pending then
		return false
	end

	local targetTool = glassTool or pending.GlassTool or findGlassTool(player)
	if not targetTool then
		pendingDrinks[player] = nil
		return false
	end

	applyDrinkToGlassTool(targetTool, pending.Data)
	pendingDrinks[player] = nil
	return true
end

-- PUBLIC: finalize an immediate drink (no shaker required or partial mix)
function DrinkCreationManager.createImmediateDrink(player: Player, payload: table, ingredients: {string}?, isRecipe: boolean, glassTool: Tool?)
	local targetTool = glassTool or findGlassTool(player)
	if not targetTool then
		return false, "NoGlassTool"
	end

	local drinkData = normalizeDrinkData(payload, ingredients, isRecipe)
	applyDrinkToGlassTool(targetTool, drinkData)

	return true, drinkData
end

function DrinkCreationManager.onPlayerRemoving(player: Player)
	pendingDrinks[player] = nil
end

return DrinkCreationManager
