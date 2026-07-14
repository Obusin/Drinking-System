-- RecipeRegistry: Handles recipe lookups by ingredient sets

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystem:WaitForChild("Config")

local Recipes = require(ConfigFolder:WaitForChild("Recipes"))

local RecipeRegistry = {}

---------------------------------------------------------------------
-- Dynamic recipes (paid custom drinks). The server publishes each one as a
-- Folder under ReplicatedStorage.DrinkSystem.DynamicRecipes with attributes:
--   DisplayName, IngredientsCsv, Color, Strongness, CreatorName, CreatorUserId
-- Folders replicate, so this shared module gives client AND server the same
-- merged recipe view. Static Recipes.luau entries always win name conflicts.
---------------------------------------------------------------------
local dynamicCache: { [string]: any }? = nil
local dynamicFolder: Folder? = DrinkSystem:FindFirstChild("DynamicRecipes")

local function invalidateDynamic()
	dynamicCache = nil
end

local function hookFolder(folder: Folder)
	dynamicFolder = folder
	folder.ChildAdded:Connect(invalidateDynamic)
	folder.ChildRemoved:Connect(invalidateDynamic)
end

if dynamicFolder then
	hookFolder(dynamicFolder)
else
	DrinkSystem.ChildAdded:Connect(function(child)
		if child.Name == "DynamicRecipes" and child:IsA("Folder") and not dynamicFolder then
			hookFolder(child)
			invalidateDynamic()
		end
	end)
end

local function defFromEntry(entry: Instance): any?
	local csv = entry:GetAttribute("IngredientsCsv")
	if type(csv) ~= "string" or csv == "" then return nil end
	local ingredients = {}
	local steps = {}
	for token in string.gmatch(csv, "([^,]+)") do
		table.insert(ingredients, token)
		table.insert(steps, { Ingredient = token })
	end
	return {
		DisplayName = entry:GetAttribute("DisplayName") or entry.Name,
		Ingredients = ingredients,
		Steps = steps,
		OutputColor = entry:GetAttribute("Color"),
		RequireShaker = false,
		StrongnessOverride = entry:GetAttribute("Strongness") or 0,
		Presentation = { Garnishes = {} },
		Custom = true,
		CreatorName = entry:GetAttribute("CreatorName"),
		CreatorUserId = entry:GetAttribute("CreatorUserId"),
	}
end

local function getDynamic(): { [string]: any }
	if dynamicCache then return dynamicCache end
	local out = {}
	if dynamicFolder then
		for _, entry in ipairs(dynamicFolder:GetChildren()) do
			local def = defFromEntry(entry)
			-- Static recipes always shadow dynamic ones with the same name
			if def and Recipes[entry.Name] == nil then
				out[entry.Name] = def
			end
		end
	end
	dynamicCache = out
	return out
end

-- Merged accessor: static recipe or dynamic custom drink
function RecipeRegistry.get(recipeName: string?): any?
	if recipeName == nil then return nil end
	return Recipes[recipeName] or getDynamic()[recipeName]
end

-- Merged view of every active recipe. Do not mutate the returned defs.
function RecipeRegistry.getAll(): { [string]: any }
	local dynamic = getDynamic()
	if next(dynamic) == nil then
		return Recipes
	end
	local merged = table.clone(dynamic)
	for name, def in pairs(Recipes) do
		merged[name] = def
	end
	return merged
end

-- COUNT-AWARE multiset equality. The old any-match version made
-- {Vodqa, Vodqa, Vodqa} "equal" to {Vodqa, Coolnag, Soda Water} — each Vodqa
-- entry individually found the one Vodqa — so mixes containing Vodqa could
-- randomly finalize as Sin Obu depending on recipe iteration order.
local function setsMatch(a, b)
	if #a ~= #b then return false end

	local counts = {}
	for _, ingredient in ipairs(a) do
		counts[ingredient] = (counts[ingredient] or 0) + 1
	end
	for _, ingredient in ipairs(b) do
		local remaining = counts[ingredient]
		if not remaining then
			return false
		end
		if remaining == 1 then
			counts[ingredient] = nil
		else
			counts[ingredient] = remaining - 1
		end
	end
	return next(counts) == nil
end

function RecipeRegistry.getRecipeByIngredients(ingredientList)
	for recipeName, def in pairs(RecipeRegistry.getAll()) do
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

	for _, def in pairs(RecipeRegistry.getAll()) do
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

	for _, def in pairs(RecipeRegistry.getAll()) do
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
