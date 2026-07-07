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

-- Count-aware pour validity: current mix + the new ingredient must fit as a
-- sub-multiset of at least one recipe's ingredient list. Duplicates count —
-- {Vodqa, Vodqa} only fits recipes listing Vodqa twice or more (secret drinks
-- like Obu's Juice). Secret recipes DO count here (pours work, guidance hides).
function RecipeRegistry.canAddIngredient(currentIngredients: {string}, ingredientName: string): boolean
	local counts = {}
	for _, ing in ipairs(currentIngredients) do
		counts[ing] = (counts[ing] or 0) + 1
	end
	counts[ingredientName] = (counts[ingredientName] or 0) + 1

	for _, def in pairs(Recipes) do
		local required = def.Ingredients or {}
		local fits = true
		for name, needed in pairs(counts) do
			local available = 0
			for _, r in ipairs(required) do
				if r == name then
					available += 1
				end
			end
			if needed > available then
				fits = false
				break
			end
		end
		if fits then
			return true
		end
	end
	return false
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
