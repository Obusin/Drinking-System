-- RecipeRegistry: Handles recipe lookups by ingredient sets

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystem:WaitForChild("Config")

local Recipes = require(ConfigFolder:WaitForChild("Recipes"))

local RecipeRegistry = {}

local function setsMatch(a, b)
	if #a ~= #b then return false end

	for _, ingredient in ipairs(a) do
		if not table.find(b, ingredient) then
			return false
		end
	end

	return true
end

function RecipeRegistry.getRecipeByIngredients(ingredientList)
	for recipeName, def in pairs(Recipes) do
		if setsMatch(def.Ingredients or {}, ingredientList) then
			return def, recipeName
		end
	end

	return nil, nil
end

function RecipeRegistry.getCompatibleNextIngredients(currentIngredients)
	local compatible = {}

	for _, def in pairs(Recipes) do
		for _, ingredient in ipairs(def.Ingredients or {}) do
			if not table.find(currentIngredients, ingredient) then
				local fits = true
				for _, existing in ipairs(currentIngredients) do
					if not table.find(def.Ingredients, existing) then
						fits = false
						break
					end
				end

				if fits then
					table.insert(compatible, ingredient)
				end
			end
		end
	end

	return compatible
end

return RecipeRegistry
