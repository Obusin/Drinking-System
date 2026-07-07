-- DrinkSystemController (SSA)
-- Single authoritative controller for drink state, validation, outcomes, and guidance.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local DrinkSystemFolder = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystemFolder:WaitForChild("Config")
local SharedModules = DrinkSystemFolder:WaitForChild("SharedModules")

local Settings = require(ConfigFolder:WaitForChild("Settings"))
local Recipes = require(ConfigFolder:WaitForChild("Recipes"))
local IngredientRegistry = require(SharedModules:WaitForChild("IngredientRegistry"))
local RecipeRegistry = require(SharedModules:WaitForChild("RecipeRegistry"))
local Utility = require(SharedModules:WaitForChild("Utility"))
local Network = require(SharedModules:WaitForChild("Network"))
local GlassPresentation = require(SharedModules:WaitForChild("GlassPresentation"))
local Packets = Network.Packets

local DEBUG_MIX = false
local AUTO_FINALIZE_ON_RECIPE = true
local AUTO_SHAKER_ON_RECIPE = true

local function debugPrint(...)
	if DEBUG_MIX then
		print("[DrinkSystem][Mix]", ...)
	end
end

local managersFolder = script.Parent:WaitForChild("Managers")
local servicesFolder = script.Parent:WaitForChild("Services")

local PickupManager = require(managersFolder:WaitForChild("PickupManager"))
local DrinkCreationManager = require(managersFolder:WaitForChild("DrinkCreationManager"))
local PlacementManager = require(managersFolder:WaitForChild("PlacementManager"))
local ConsumptionManager = require(managersFolder:WaitForChild("ConsumptionManager"))
local DrinkEffectsService = require(servicesFolder:WaitForChild("DrinkEffectsService"))
local GamepassManager = require(servicesFolder:WaitForChild("GamepassManager"))

local DrinkSystemController = {}
local initialized = false

type IngredientStep = {
	Ingredient: string,
	Amount: number?,
	Optional: boolean?,
	Alternatives: {string}?,
}

type ToolStep = {
	Tool: string,
	Optional: boolean?,
}

type MixState = {
	GlassTool: Tool,
	StartedAt: number,
	LastActionAt: number,
	Ingredients: { {Name: string, Time: number} },
	Garnishes: { string },
	ToolsUsed: { [string]: boolean },
	StepsPerformed: { string },
	PendingPayload: table?,
}

type DrinkSession = {
	Player: Player,
	StartedAt: number,
	LastActionAt: number,
	LastDrinkTick: number,
	LastGuidanceAt: number,
	SelectedRecipe: string?,
	SuggestedRecipe: string?,
	SuggestedRecipes: {string},
	GlassTool: Tool?,
	MixByTool: { [Tool]: MixState },
	PendingGlass: Tool?,
	DirtyGuidance: boolean,
	LastActionTick: number,
}

local sessions: { [Player]: DrinkSession } = {}

local function getSession(player: Player): DrinkSession
	local session = sessions[player]
	if not session then
		session = {
			Player = player,
			StartedAt = os.clock(),
			LastActionAt = os.clock(),
			LastDrinkTick = 0,
			LastGuidanceAt = 0,
			SelectedRecipe = nil,
			SuggestedRecipe = nil,
			SuggestedRecipes = {},
			GlassTool = nil,
			MixByTool = {},
			PendingGlass = nil,
			DirtyGuidance = true,
			LastActionTick = 0,
		}
		sessions[player] = session
	end
	return session
end

local function getMixState(session: DrinkSession, glassTool: Tool): MixState
	local state = session.MixByTool[glassTool]
	if not state then
		state = {
			GlassTool = glassTool,
			StartedAt = os.clock(),
			LastActionAt = os.clock(),
			Ingredients = {},
			Garnishes = {},
			ToolsUsed = {},
			StepsPerformed = {},
			PendingPayload = nil,
		}
		session.MixByTool[glassTool] = state

		local ingredientsCsv = glassTool:GetAttribute("DS_IngredientListCsv")
		if type(ingredientsCsv) == "string" and ingredientsCsv ~= "" then
			for token in string.gmatch(ingredientsCsv, "([^,]+)") do
				table.insert(state.Ingredients, {
					Name = token,
					Time = os.clock(),
				})
			end
		end

		local garnishesCsv = glassTool:GetAttribute("DS_GarnishesCsv")
		if type(garnishesCsv) == "string" and garnishesCsv ~= "" then
			for token in string.gmatch(garnishesCsv, "([^,]+)") do
				if not table.find(state.Garnishes, token) then
					table.insert(state.Garnishes, token)
				end
			end
		end
	end
	return state
end

local function clearMixState(session: DrinkSession, glassTool: Tool)
	session.MixByTool[glassTool] = nil
	if session.GlassTool == glassTool then
		session.GlassTool = nil
	end
	if session.PendingGlass == glassTool then
		session.PendingGlass = nil
	end
end

local function clearSession(player: Player)
	sessions[player] = nil
end

-- Ragdolled/collapsed players can't interact with the drink system at all.
local function playerIsCollapsed(player: Player): boolean
	local val = player:FindFirstChild("DrunkCollapsed")
	return val ~= nil and val:IsA("BoolValue") and val.Value == true
end

local function rateLimitOk(session: DrinkSession): boolean
	local now = os.clock()
	if now - session.LastActionTick < (Settings.ActionCooldown or 0.1) then
		return false
	end
	session.LastActionTick = now
	return true
end

local function findGlassTool(player: Player): Tool?
	local char = player.Character
	local backpack = player:FindFirstChild("Backpack")
	local allowedNames = Settings.GlassToolNames or {}

	local function scan(container)
		if not container then return nil end
		for _, tool in ipairs(container:GetChildren()) do
			-- Skip finalized drinks — DS_Drink=true means it's a completed drink, not a mixing glass
			if tool:IsA("Tool") and tool:GetAttribute("DS_Drink") ~= true then
				for _, name in ipairs(allowedNames) do
					if tool.Name == name or tool:GetAttribute("DS_GlassTool") == true then
						return tool
					end
				end
			end
		end
		return nil
	end

	return scan(char) or scan(backpack)
end

local function findHeldDrinkTool(player: Player): Tool?
	local char = player.Character
	if not char then
		return nil
	end

	for _, tool in ipairs(char:GetChildren()) do
		if tool:IsA("Tool") and (tool:GetAttribute("DS_Drink") == true or tool:GetAttribute("DS_DrinkTool") == true) then
			return tool
		end
	end

	return nil
end

local function modelDistanceOk(player: Player, model: Instance): boolean
	local maxDist = Settings.MaxInteractDistance or 12
	local char = player.Character
	if not char then return false end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return false end

	local part = model:IsA("BasePart") and model or model:FindFirstChildWhichIsA("BasePart", true)
	if not part then return false end

	return (part.Position - root.Position).Magnitude <= maxDist
end

local function getIngredientNameFromBottle(model: Instance): string?
	if not model then return nil end

	if model:GetAttribute("DS_Drinks") == true then
		return model:GetAttribute("DS_IngredientName") or model.Name
	end
	-- DS_IngredientName alone is enough (e.g. bare Water part — no DS_Drinks needed).
	-- Safe: onPour still validates the name against IngredientRegistry.
	local direct = model:GetAttribute("DS_IngredientName")
	if type(direct) == "string" then
		return direct
	end
	if model:IsA("Model") and (CollectionService:HasTag(model, "DS__Bottle") or CollectionService:HasTag(model, "DS_Bottle")) then
		return model:GetAttribute("DS_IngredientName") or model.Name
	end

	for _, d in ipairs(model:GetDescendants()) do
		if d:GetAttribute("DS_Drinks") == true then
			return d:GetAttribute("DS_IngredientName") or model.Name
		end
		local dName = d:GetAttribute("DS_IngredientName")
		if type(dName) == "string" then
			return dName
		end
	end

	return nil
end

local function canonicalizeGarnishName(name: string?): string?
	if type(name) ~= "string" then
		return nil
	end

	local trimmed = string.gsub(name, "^%s*(.-)%s*$", "%1")
	if trimmed == "" then
		return nil
	end

	local lowered = string.lower(trimmed)
	if lowered == "umbrella" or lowered == "shade umbrella" or lowered == "shadeumbrella" then
		return "ShadeUmbrella"
	end
	if lowered == "cherry" then
		return "Cherry"
	end
	if lowered == "lemon" then
		return "Lemon"
	end
	if lowered == "lime" then
		return "Lime"
	end
	if lowered == "orange" then
		return "Orange"
	end
	if lowered == "ice" then
		return "Ice"
	end

	return trimmed
end

local function getGarnishNameFromModel(model: Instance): string?
	if not model then
		return nil
	end

	local direct = canonicalizeGarnishName(model:GetAttribute("DS_Garnish"))
	if direct then
		return direct
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		local garnish = canonicalizeGarnishName(descendant:GetAttribute("DS_Garnish"))
		if garnish then
			return garnish
		end
	end

	return nil
end

local function parseCsvList(csv: string?): {string}
	local out = {}
	if type(csv) ~= "string" or csv == "" then
		return out
	end
	for token in string.gmatch(csv, "([^,]+)") do
		table.insert(out, token)
	end
	return out
end

local function pushUnique(list: {string}, value: string)
	if not table.find(list, value) then
		table.insert(list, value)
	end
end

local CITRUS_GARNISHES = {
	Lemon = true,
	Lime = true,
	Orange = true,
}

local function applyGarnishRules(list: {string}, garnishName: string)
	if CITRUS_GARNISHES[garnishName] then
		for index = #list, 1, -1 do
			if CITRUS_GARNISHES[list[index]] then
				table.remove(list, index)
			end
		end
	end
	pushUnique(list, garnishName)
end

local function mergeGarnishLists(...)
	local merged = {}
	for _, list in ipairs({ ... }) do
		if type(list) == "table" then
			for _, garnishName in ipairs(list) do
				if type(garnishName) == "string" and garnishName ~= "" then
					applyGarnishRules(merged, garnishName)
				end
			end
		end
	end
	return merged
end

local function recordStep(mix: MixState, session: DrinkSession, step: string)
	table.insert(mix.StepsPerformed, step)
	mix.LastActionAt = os.clock()
	session.DirtyGuidance = true
end

local function addIngredient(mix: MixState, session: DrinkSession, ingredientName: string)
	for _, item in ipairs(mix.Ingredients) do
		if item.Name == ingredientName then
			return
		end
	end
	table.insert(mix.Ingredients, { Name = ingredientName, Time = os.clock() })
	recordStep(mix, session, "Ingredient:" .. ingredientName)
end

local function ingredientSetMatchesRecipe(ingredients: {string}, recipeDef: table?): boolean
	if not recipeDef then
		return false
	end
	local required = recipeDef.Ingredients or {}
	if #required ~= #ingredients then
		return false
	end
	for _, ing in ipairs(required) do
		if not table.find(ingredients, ing) then
			return false
		end
	end
	return true
end

local function hasShakerTool(player: Player): boolean
	local char = player.Character
	local backpack = player:FindFirstChild("Backpack")
	local shakerName = Settings.ShakerToolName

	local function scan(container)
		if not container then return false end
		for _, tool in ipairs(container:GetChildren()) do
			if tool:IsA("Tool") then
				if tool:GetAttribute("DS_ShakerTool") == true then
					return true
				end
				if shakerName and tool.Name == shakerName then
					return true
				end
			end
		end
		return false
	end

	return scan(char) or scan(backpack)
end

local function buildDrinkPayload(recipeName: string?, recipeDef: table?, ingredients: {string}, isRecipe: boolean): table
	local payload = {
		RecipeName = recipeName,
		DisplayName = recipeDef and (recipeDef.DisplayName or recipeName) or (table.concat(ingredients, "-Mix ")),
		BaseIngredient = ingredients[1],
		Color = recipeDef and recipeDef.OutputColor or Utility.averageColors(ingredients),
		Strongness = recipeDef and recipeDef.StrongnessOverride or 0,
		RequiresShaker = recipeDef and recipeDef.RequireShaker == true or false,
		FillStage = recipeDef and recipeDef.FillStageOverride or nil,
		Ingredients = ingredients,
		IsRecipe = isRecipe,
		Garnishes = {},  -- starts empty; player physically applies garnishes after mixing
	}
	return payload
end

local function toWireDrinkPayload(payload: table): table
	return {
		RecipeName = payload.RecipeName,
		DisplayName = payload.DisplayName,
		Color = Network.color3ToVec3(payload.Color),
		Strongness = payload.Strongness or 0,
		RequiresShaker = payload.RequiresShaker == true,
		Ingredients = payload.Ingredients or {},
		IsRecipe = payload.IsRecipe == true,
	}
end

local function ingredientsToList(mix: MixState): {string}
	local out = {}
	for _, item in ipairs(mix.Ingredients) do
		table.insert(out, item.Name)
	end
	return out
end

local function updateGlassMixPreview(glassTool: Tool, ingredients: {string})
	if not glassTool then
		return
	end

	local maxIngredients = Settings.MaxIngredientsPerMix or 5
	local previewName = "Glass"
	if #ingredients > 0 then
		previewName = (#ingredients > maxIngredients) and "Toxication" or table.concat(ingredients, ", ")
	end

	glassTool.Name = previewName
	glassTool:SetAttribute("DS_Drink", false)
	glassTool:SetAttribute("DS_DrinkTool", false)
	glassTool:SetAttribute("DS_DrinkName", previewName)
	glassTool:SetAttribute("DS_Strongness", 0)
	glassTool:SetAttribute("DS_IsRecipe", false)
	glassTool:SetAttribute("DS_RecipeName", "")
	glassTool:SetAttribute("DS_BaseIngredient", ingredients[1])
	glassTool:SetAttribute("DS_SipsMax", nil)
	glassTool:SetAttribute("DS_SipsRemaining", nil)
	glassTool:SetAttribute("DS_IngredientsText", table.concat(ingredients, ", "))
	glassTool:SetAttribute("DS_IngredientListCsv", table.concat(ingredients, ","))
	if #ingredients == 0 then
		glassTool:SetAttribute("DS_Color", nil)
	end
end

local function setBackpackLocked(player: Player, locked: boolean)
	Packets.SetBackpackLocked.sendTo({
		Locked = locked == true,
	}, player)
end

local resetMixForNewDrink

local function finalizeDrinkNow(player: Player, session: DrinkSession, mix: MixState, payload: table, ingredients: {string}, isRecipe: boolean, glassTool: Tool)
	setBackpackLocked(player, true)
	local ok, result = pcall(function()
		return DrinkCreationManager.createImmediateDrink(player, payload, ingredients, isRecipe, glassTool)
	end)
	setBackpackLocked(player, false)
	if not ok then
		error(result)
	end
	if payload.Outcome and payload.Score then
		Packets.DrinkOutcome.sendTo({
			DrinkName = payload.DisplayName or payload.RecipeName or "Drink",
			Outcome = payload.Outcome,
			Score = math.clamp(math.floor(payload.Score), 0, 255),
		}, player)
	end
	resetMixForNewDrink(session, glassTool)
	return result
end

local function findMatchingRecipesForSession(mix: MixState, maxCount: number?): { { Name: string, Def: table, Missing: number } }
	local ingredients = ingredientsToList(mix)
	local ranked = {}

	for name, def in pairs(Recipes) do
		local required = def.Ingredients or {}
		local fits = true
		for _, ing in ipairs(ingredients) do
			if not table.find(required, ing) then
				fits = false
				break
			end
		end

		if fits then
			local missing = math.max(#required - #ingredients, 0)
			table.insert(ranked, {
				Name = name,
				Def = def,
				Missing = missing,
			})
		end
	end

	table.sort(ranked, function(a, b)
		if a.Missing ~= b.Missing then
			return a.Missing < b.Missing
		end
		return a.Name < b.Name
	end)

	local limit = maxCount or 3
	local top = {}
	for i = 1, math.min(limit, #ranked) do
		table.insert(top, ranked[i])
	end
	return top
end

local function getRankedNextIngredientsFromMatches(matchingRecipes: { { Name: string, Def: table, Missing: number } }, mixIngredients: {string}): {string}
	local counts: { [string]: number } = {}
	for _, item in ipairs(matchingRecipes) do
		local required = item.Def.Ingredients or {}
		for _, ing in ipairs(required) do
			if not table.find(mixIngredients, ing) then
				counts[ing] = (counts[ing] or 0) + 1
			end
		end
	end

	local ranked = {}
	for ing, count in pairs(counts) do
		table.insert(ranked, { Name = ing, Count = count })
	end

	table.sort(ranked, function(a, b)
		if a.Count ~= b.Count then
			return a.Count > b.Count
		end
		return a.Name < b.Name
	end)

	-- Return ALL valid next ingredients (union of missing ingredients across
	-- matching recipes). This must mirror the pour-validity check in onPour —
	-- everything highlighted is pourable, everything pourable is highlighted.
	local out = {}
	for i = 1, #ranked do
		table.insert(out, ranked[i].Name)
	end
	return out
end

local function computeOutcome(mix: MixState, recipeName: string?, recipeDef: table?): (string, number)
	local ingredients = ingredientsToList(mix)
	if not recipeDef then
		return "Experimental", 45
	end

	local required = recipeDef.Ingredients or {}
	local steps = recipeDef.Steps or {}

	local correct = 0
	for _, ing in ipairs(ingredients) do
		if table.find(required, ing) then
			correct += 1
		end
	end

	local missing = math.max(#required - correct, 0)
	local extras = math.max(#ingredients - correct, 0)

	local orderCorrect = 0
	for i, step in ipairs(steps) do
		if step.Ingredient and ingredients[i] == step.Ingredient then
			orderCorrect += 1
		end
	end

	local accuracyScore = 50 * (correct / math.max(#required, 1))
	local orderScore = 25 * (orderCorrect / math.max(#required, 1))
	local toolScore = 15

	if recipeDef.RequireShaker == true and not mix.ToolsUsed.Shaker then
		toolScore = 0
	end

	local penalty = (missing * 7) + (extras * 8)
	local timeTaken = os.clock() - mix.StartedAt
	local timeScore = 10
	if timeTaken > (Settings.MaxDrinkTime or 60) then
		timeScore = 4
	end

	local score = math.clamp(math.floor(accuracyScore + orderScore + toolScore + timeScore - penalty), 0, 100)

	if score >= 90 then
		return "Perfect", score
	elseif score >= 75 then
		return "Good", score
	elseif score >= 55 then
		return "Weak", score
	elseif score >= 35 then
		return "Experimental", score
	else
		return "Ruined", score
	end
end

local function findHeldDrinkForGarnish(player: Player): Tool?
	local char = player.Character
	if not char then return nil end
	for _, tool in ipairs(char:GetChildren()) do
		if tool:IsA("Tool") and tool:GetAttribute("DS_Drink") == true then
			return tool
		end
	end
	return nil
end

local function updateGuidance(session: DrinkSession, glassTool: Tool?)
	local guidance = {
		Instruction = "",
		RecommendedIngredients = {},
		DisplayIngredients = {},  -- highlighted subset; empty = highlight all recommended
		RequiredItemType = nil,
		SelectedRecipe = session.SelectedRecipe,
		SuggestedRecipe = session.SuggestedRecipe,
		SuggestedRecipes = session.SuggestedRecipes,
	}

	session.GlassTool = glassTool

	if Settings.RequireGamepassForGlass and not GamepassManager.playerHasBartenderPass(session.Player) then
		guidance.Instruction = "Unlock bartender pass to use glass."
		guidance.RequiredItemType = "Glass"
		return guidance
	end

	if not glassTool then
		-- Check if the player is holding a finalized drink that still needs a garnish
		local drinkTool = findHeldDrinkForGarnish(session.Player)
		if drinkTool then
			local recipeName = drinkTool:GetAttribute("DS_DrinkName")
			local recipeDef = recipeName and Recipes[recipeName] or nil
			local requiredGarnishes = recipeDef and recipeDef.Presentation and recipeDef.Presentation.Garnishes or {}
			local currentGarnishesCsv = drinkTool:GetAttribute("DS_GarnishesCsv") or ""
			local currentGarnishes = {}
			for token in string.gmatch(currentGarnishesCsv, "([^,]+)") do
				table.insert(currentGarnishes, token)
			end
			-- Find first missing garnish
			local missing = nil
			for _, g in ipairs(requiredGarnishes) do
				if not table.find(currentGarnishes, g) then
					missing = g
					break
				end
			end
			if missing then
				-- Garnish is optional — suggest but don't block anything
				guidance.Instruction = "Tip: Add " .. missing .. " garnish, or place the drink."
				return guidance
			end
			guidance.Instruction = "Click a table to place the drink."
			return guidance
		end
		guidance.Instruction = "Pick up a glass."
		guidance.RequiredItemType = "Glass"
		return guidance
	end

	local mix = getMixState(session, glassTool)
	local mixIngredients = ingredientsToList(mix)

	-- Mixing requires a shaker (onPour enforces it) — guide the player to the
	-- shaker BEFORE recommending ingredients, or the highlighted bottles would
	-- reject every click and the guide would feel broken.
	if not hasShakerTool(session.Player) then
		guidance.RequiredItemType = "Shaker"
		guidance.Instruction = "Pick up the shaker."
		return guidance
	end

	-- When glass is empty, highlight EVERY registered ingredient so all bottles
	-- glow and the player can freely start with anything. Once they pour one,
	-- guidance narrows down to only compatible next ingredients.
	if not session.SelectedRecipe and #mixIngredients == 0 then
		local topRecipes = findMatchingRecipesForSession(mix, 6)
		local suggestedNames = {}
		for _, item in ipairs(topRecipes) do
			table.insert(suggestedNames, item.Name)
		end
		session.SuggestedRecipes = suggestedNames
		session.SuggestedRecipe = suggestedNames[1]
		guidance.SuggestedRecipes = suggestedNames
		guidance.SuggestedRecipe = suggestedNames[1]
		-- Only ingredients that appear in at least one recipe — anything else
		-- would highlight but get rejected by the pour-validity check.
		local recipeIngredients = {}
		local seen = {}
		for _, def in pairs(Recipes) do
			for _, ing in ipairs(def.Ingredients or {}) do
				if not seen[ing] then
					seen[ing] = true
					table.insert(recipeIngredients, ing)
				end
			end
		end
		guidance.RecommendedIngredients = recipeIngredients
		guidance.Instruction = "Pick any ingredient to start."
		return guidance
	end

	local recipeName = session.SelectedRecipe
	local recipeDef = recipeName and Recipes[recipeName] or nil

	if not recipeDef then
		-- All fitting recipes (not just top 6) so the recommended set covers
		-- every valid pour; suggestion list shown to the player stays capped.
		local allFitting = findMatchingRecipesForSession(mix, 50)
		local suggestedNames = {}
		for i = 1, math.min(6, #allFitting) do
			table.insert(suggestedNames, allFitting[i].Name)
		end
		session.SuggestedRecipes = suggestedNames
		session.SuggestedRecipe = suggestedNames[1]
		guidance.SuggestedRecipes = suggestedNames
		guidance.SuggestedRecipe = suggestedNames[1]

		local suggestedNextIngredients = getRankedNextIngredientsFromMatches(allFitting, mixIngredients)

		if #suggestedNextIngredients > 0 then
			guidance.RecommendedIngredients = suggestedNextIngredients
			-- Highlight only the top few so the bar doesn't light up like a
			-- Christmas tree mid-mix; the full list still gates clicks.
			local display = {}
			for i = 1, math.min(4, #suggestedNextIngredients) do
				table.insert(display, suggestedNextIngredients[i])
			end
			guidance.DisplayIngredients = display
			guidance.Instruction = "Try one of the suggested mixes."
			return guidance
		end

		recipeName = session.SuggestedRecipe
		recipeDef = recipeName and Recipes[recipeName] or nil
	else
		session.SuggestedRecipes = {}
		session.SuggestedRecipe = nil
		guidance.SuggestedRecipes = {}
		guidance.SuggestedRecipe = nil
	end

	if recipeDef and recipeDef.Steps then
		local nextIngredient = nil
		for _, step in ipairs(recipeDef.Steps) do
			if step.Ingredient and not table.find(ingredientsToList(mix), step.Ingredient) then
				nextIngredient = step.Ingredient
				break
			end
			if step.Tool == "Shaker" and not mix.ToolsUsed.Shaker then
				guidance.RequiredItemType = "Shaker"
				guidance.Instruction = "Use the shaker."
				return guidance
			end
		end

		if nextIngredient then
			table.insert(guidance.RecommendedIngredients, nextIngredient)
			guidance.Instruction = "Add " .. nextIngredient .. "."
		else
			guidance.Instruction = "Finalize the mix."
		end
	else
		local compatibleAll = RecipeRegistry.getCompatibleNextIngredients(mixIngredients)
		local compatibleCapped = {}
		for i = 1, math.min(4, #compatibleAll) do
			table.insert(compatibleCapped, compatibleAll[i])
		end
		guidance.RecommendedIngredients = compatibleCapped
		if #guidance.RecommendedIngredients > 0 then
			guidance.Instruction = "Try: " .. guidance.RecommendedIngredients[1]
		else
			guidance.Instruction = "Add any ingredient."
		end
	end

	return guidance
end

local GUIDANCE_HEARTBEAT_INTERVAL = 3 -- force-resend every 3s even if not dirty

local function sendGuidanceIfNeeded(session: DrinkSession, glassTool: Tool?)
	if Settings.EnableGuidance ~= true then
		return
	end
	local now = os.clock()
	local interval = Settings.GuidanceUpdateInterval or 0.25

	-- Force-resend periodically so clients auto-recover if they missed an update
	local heartbeatDue = (now - session.LastGuidanceAt) >= GUIDANCE_HEARTBEAT_INTERVAL
	if not session.DirtyGuidance and not heartbeatDue then return end
	if now - session.LastGuidanceAt < interval then return end

	local payload = updateGuidance(session, glassTool)
	Packets.GuidanceUpdate.sendTo({
		Instruction = payload.Instruction or "",
		RecommendedIngredients = payload.RecommendedIngredients or {},
		DisplayIngredients = payload.DisplayIngredients or {},
		RequiredItemType = payload.RequiredItemType,
		SelectedRecipe = payload.SelectedRecipe,
		SuggestedRecipe = payload.SuggestedRecipe,
		SuggestedRecipes = payload.SuggestedRecipes or {},
	}, session.Player)
	session.LastGuidanceAt = now
	session.DirtyGuidance = false
end

resetMixForNewDrink = function(session: DrinkSession, glassTool: Tool)
	clearMixState(session, glassTool)
	session.SelectedRecipe = nil
	session.SuggestedRecipe = nil
	session.SuggestedRecipes = {}
	session.DirtyGuidance = true
end

function DrinkSystemController.onPickup(player: Player, model: Model)
	if playerIsCollapsed(player) then return end
	local session = getSession(player)
	if not rateLimitOk(session) then return end
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	if not modelDistanceOk(player, model) then return end
	-- No pickups while a drink is mid-shake — equipping a new tool would
	-- interrupt the shaker sequence and strand the backpack lock.
	if session.PendingGlass then
		debugPrint(player.Name, "pickup blocked: drink is finalizing")
		return
	end
	local ok, status, payload = PickupManager.pickup(player, model)
	if ok and (status == "GlassPicked" or status == "PlacedGlassPicked") then
		session.GlassTool = findGlassTool(player)
		if session.GlassTool then
			local mix = getMixState(session, session.GlassTool)
			recordStep(mix, session, "PickupGlass")
		end
	elseif ok and status == "ShakerPicked" then
		local glassTool = findGlassTool(player)
		if glassTool then
			local mix = getMixState(session, glassTool)
			recordStep(mix, session, "PickupShaker")
		end
	end

	return ok, status, payload
end

function DrinkSystemController.onPour(player: Player, bottleModel: Instance)
	if playerIsCollapsed(player) then return end
	local session = getSession(player)
	if not rateLimitOk(session) then return end
	if typeof(bottleModel) ~= "Instance" then return end
	if not modelDistanceOk(player, bottleModel) then return end

	if Settings.RequireGamepassForMixing and not GamepassManager.playerHasBartenderPass(player) then
		return
	end

	local ingredientName = getIngredientNameFromBottle(bottleModel)
	if not ingredientName or not IngredientRegistry.exists(ingredientName) then return end

	local glassTool = findGlassTool(player)

	-- Water with NO glass: drink straight from the source — sober up on the spot.
	-- Water WITH a glass falls through to the normal pour (fills + renames the
	-- glass, auto-finalizes to the Water recipe). Neither path needs a shaker.
	if ingredientName == "Water" and not glassTool then
		local soberAmount = Settings.WaterSoberAmount or -35
		DrinkEffectsService.applyDrink(player, soberAmount)
		session.DirtyGuidance = true
		DrinkEffectsService.playCharacterSound(player, Settings.PourSoundId, Settings.PourSoundVolume or 0.4)
		-- Pour visual on the client (it special-cases Water: anim, no bottle clone)
		Packets.StartBottlePour.sendTo({
			IngredientName = ingredientName,
			BottleModel = bottleModel,
		}, player)
		debugPrint(player.Name, "drank water directly, sober amount:", soberAmount)
		return
	end

	if not glassTool then
		session.DirtyGuidance = true
		return
	end
	if glassTool:GetAttribute("DS_Drink") == true then
		debugPrint("Cannot mix; current glass is already a drink:", glassTool.Name)
		return
	end

	local mix = getMixState(session, glassTool)
	if mix.PendingPayload then
		debugPrint("Cannot mix; glass is already finalizing:", glassTool.Name)
		return
	end

	-- Mixing requires owning a shaker — no shaker, no pours. Water is exempt.
	if ingredientName ~= "Water" and not hasShakerTool(player) then
		Packets.MissingShakerNotify.sendTo({}, player)
		return
	end

	-- Only recipe-valid pours: the mix plus this ingredient must still fit at
	-- least one recipe. Keeps clients honest (guidance highlights this same set).
	do
		local hypothetical = ingredientsToList(mix)
		table.insert(hypothetical, ingredientName)
		local fitsAnyRecipe = false
		for _, def in pairs(Recipes) do
			local required = def.Ingredients or {}
			local fits = true
			for _, ing in ipairs(hypothetical) do
				if not table.find(required, ing) then
					fits = false
					break
				end
			end
			if fits then
				fitsAnyRecipe = true
				break
			end
		end
		if not fitsAnyRecipe then
			debugPrint("Rejected pour (no recipe fits):", ingredientName, "onto", table.concat(ingredientsToList(mix), ", "))
			return
		end
	end

	addIngredient(mix, session, ingredientName)
	local ingredients = ingredientsToList(mix)
	updateGlassMixPreview(glassTool, ingredients)
	local previewColor = Utility.averageColors(ingredients)
	glassTool:SetAttribute("DS_Color", previewColor)
	-- Pure water fills the glass in one pour — it's just water, no 1/2/3 stages
	local fillStage = (ingredientName == "Water" and #ingredients == 1) and 3
		or math.clamp(#ingredients, 0, 3)
	GlassPresentation.applyFillState(glassTool, fillStage, previewColor)
	glassTool:SetAttribute("DS_FillStage", fillStage)
	glassTool:SetAttribute("DS_GarnishesCsv", "")
	GlassPresentation.setGarnishes(glassTool, {})
	debugPrint("Glass:", glassTool.Name, "Added ingredient:", ingredientName)
	-- Pour sound on the character — server-played so nearby players hear it
	DrinkEffectsService.playCharacterSound(player, Settings.PourSoundId, Settings.PourSoundVolume or 0.4)
	-- Force guidance out immediately so client narrows highlights without waiting for loop tick
	session.LastGuidanceAt = 0
	sendGuidanceIfNeeded(session, glassTool)
	Packets.StartBottlePour.sendTo({
		IngredientName = ingredientName,
		BottleModel = bottleModel,
	}, player)

	if not AUTO_FINALIZE_ON_RECIPE then
		return
	end

	local recipeDef, recipeName = RecipeRegistry.getRecipeByIngredients(ingredients)
	if not recipeDef then
		debugPrint("No recipe match yet:", table.concat(ingredients, ", "))
		return
	end

	debugPrint("Recipe complete:", recipeName, "Ingredients:", table.concat(ingredients, ", "))

	local needsShaker = (recipeDef.RequireShaker == true or AUTO_SHAKER_ON_RECIPE == true)
		and recipeDef.SkipShaker ~= true
	if needsShaker then
		if not hasShakerTool(player) then
			if recipeDef.RequireShaker == true then
				debugPrint("Missing shaker for recipe:", recipeName)
				Packets.MissingShakerNotify.sendTo({}, player)
				return
			end
			debugPrint("No shaker tool; finalizing without shaker:", recipeName)
		else
			session.PendingGlass = glassTool
			mix.PendingPayload = buildDrinkPayload(recipeName, recipeDef, ingredients, true)
			mix.PendingPayload.Garnishes = mergeGarnishLists(mix.PendingPayload.Garnishes, mix.Garnishes)
			setBackpackLocked(player, true)
			DrinkCreationManager.preparePendingDrink(player, mix.PendingPayload, ingredients, glassTool)
			recordStep(mix, session, "StartShaker")
			task.delay(0.9, function()
				Packets.StartShakerSequence.sendTo(toWireDrinkPayload(mix.PendingPayload), player)
			end)
			-- Watchdog: if ShakerFinished never arrives (interrupted client),
			-- force-finalize so the backpack lock can't get stuck.
			task.delay(8, function()
				if session.PendingGlass == glassTool then
					DrinkSystemController.onShakerFinished(player)
				end
			end)
			return
		end
	end

	local payload = buildDrinkPayload(recipeName, recipeDef, ingredients, true)
	payload.Garnishes = mergeGarnishLists(payload.Garnishes, mix.Garnishes)
	local outcome, score = computeOutcome(mix, recipeName, recipeDef)
	payload.Outcome = outcome
	payload.Score = score
	finalizeDrinkNow(player, session, mix, payload, ingredients, true, glassTool)
end

function DrinkSystemController.onFinalize(player: Player)
	if playerIsCollapsed(player) then return end
	local session = getSession(player)
	if not rateLimitOk(session) then return end

	local glassTool = findGlassTool(player)
	if not glassTool then return end

	local mix = getMixState(session, glassTool)
	if #mix.Ingredients == 0 then return end

	local ingredients = ingredientsToList(mix)
	local recipeName = session.SelectedRecipe
	local recipeDef = recipeName and Recipes[recipeName] or nil

	-- Never force a selected recipe if current ingredients do not exactly match it.
	if recipeDef and not ingredientSetMatchesRecipe(ingredients, recipeDef) then
		recipeDef = nil
		recipeName = nil
		session.SelectedRecipe = nil
	end

	if not recipeDef then
		recipeDef, recipeName = RecipeRegistry.getRecipeByIngredients(ingredients)
		if recipeDef then
			session.SelectedRecipe = recipeName
		end
	end

	if not recipeDef and #ingredients > (Settings.MaxIngredientsPerMix or 5) then
		local payload = buildDrinkPayload(nil, nil, ingredients, false)
		payload.DisplayName = "Toxication"
		payload.Strongness = 0
		payload.Outcome = "Ruined"
		payload.Score = 0
		DrinkCreationManager.createImmediateDrink(player, payload, ingredients, false, glassTool)
		resetMixForNewDrink(session, glassTool)
		return
	end

	if recipeDef and (recipeDef.RequireShaker == true or AUTO_SHAKER_ON_RECIPE == true)
		and recipeDef.SkipShaker ~= true then
		if not hasShakerTool(player) then
			if recipeDef.RequireShaker == true then
				Packets.MissingShakerNotify.sendTo({}, player)
				return
			end
		else
			session.PendingGlass = glassTool
			mix.PendingPayload = buildDrinkPayload(recipeName, recipeDef, ingredients, true)
			mix.PendingPayload.Garnishes = mergeGarnishLists(mix.PendingPayload.Garnishes, mix.Garnishes)
			setBackpackLocked(player, true)
			DrinkCreationManager.preparePendingDrink(player, mix.PendingPayload, ingredients, glassTool)
			recordStep(mix, session, "StartShaker")
			task.delay(0.9, function()
				Packets.StartShakerSequence.sendTo(toWireDrinkPayload(mix.PendingPayload), player)
			end)
			-- Watchdog: if ShakerFinished never arrives (interrupted client),
			-- force-finalize so the backpack lock can't get stuck.
			task.delay(8, function()
				if session.PendingGlass == glassTool then
					DrinkSystemController.onShakerFinished(player)
				end
			end)
			return
		end
	end

	local isRecipe = recipeDef ~= nil
	local payload = buildDrinkPayload(recipeName, recipeDef, ingredients, isRecipe)
	payload.Garnishes = mergeGarnishLists(payload.Garnishes, mix.Garnishes)
	local outcome, score = computeOutcome(mix, recipeName, recipeDef)
	payload.Outcome = outcome
	payload.Score = score

	finalizeDrinkNow(player, session, mix, payload, ingredients, isRecipe, glassTool)
end

function DrinkSystemController.onAddGarnish(player: Player, model: Instance)
	if playerIsCollapsed(player) then return end
	local session = getSession(player)
	if not rateLimitOk(session) then return end
	if typeof(model) ~= "Instance" then return end
	if not modelDistanceOk(player, model) then return end

	local garnishName = getGarnishNameFromModel(model)
	if not garnishName then
		return
	end

	local drinkTool = findHeldDrinkTool(player)
	if not drinkTool then
		return
	end

	if drinkTool:GetAttribute("DS_Drink") ~= true then
		return
	end

	local existing = parseCsvList(drinkTool:GetAttribute("DS_GarnishesCsv"))
	applyGarnishRules(existing, garnishName)
	drinkTool:SetAttribute("DS_GarnishesCsv", table.concat(existing, ","))
	GlassPresentation.setGarnishes(drinkTool, existing)
end

function DrinkSystemController.onShakerFinished(player: Player)
	local session = getSession(player)
	-- Deliberately NOT rate-limited: this must always unlock the backpack.
	-- A click just before it (same shared cooldown) used to drop this packet
	-- and leave the core UI locked forever. Safe: PendingPayload gates it.

	local glassTool = session.PendingGlass or findGlassTool(player)
	if not glassTool then
		setBackpackLocked(player, false)  -- always safe to unlock
		return
	end

	local mix = getMixState(session, glassTool)
	-- Idempotence: no pending payload = already finalized (watchdog + packet can
	-- both fire). Just make sure the backpack is unlocked and leave the mix alone.
	if not mix.PendingPayload then
		setBackpackLocked(player, false)
		return
	end
	mix.ToolsUsed.Shaker = true
	recordStep(mix, session, "ShakerFinished")

	local payload = mix.PendingPayload
	if payload then
		local outcome, score = computeOutcome(mix, payload.RecipeName, Recipes[payload.RecipeName])
		payload.Outcome = outcome
		payload.Score = score
	end

	DrinkCreationManager.finalizePendingDrink(player, glassTool)
	setBackpackLocked(player, false)
	if payload and payload.Outcome and payload.Score then
		Packets.DrinkOutcome.sendTo({
			DrinkName = payload.DisplayName or payload.RecipeName or "Drink",
			Outcome = payload.Outcome,
			Score = math.clamp(math.floor(payload.Score), 0, 255),
		}, player)
	end
	resetMixForNewDrink(session, glassTool)
end

function DrinkSystemController.onPlaceDrink(player: Player, tool: Tool, clientPosition: Vector3?)
	if playerIsCollapsed(player) then return end
	local session = getSession(player)
	if not rateLimitOk(session) then return end
	local ok, status = PlacementManager.placeDrinkFromTool(player, tool, clientPosition)
	if not ok then
		return
	end
	local glassTool = findGlassTool(player)
	if glassTool then
		local mix = getMixState(session, glassTool)
		recordStep(mix, session, status or "PlaceDrink")
	end
end

function DrinkSystemController.onConsumeDrink(player: Player, tool: Tool)
	local session = getSession(player)
	local now = os.clock()
	local drinkCooldown = Settings.DrinkConsumeCooldown or Settings.ActionCooldown or 0.3
	if now - session.LastDrinkTick < drinkCooldown then
		if DEBUG_MIX then
			print("[DrinkSystem][Consume]", player.Name, "BlockedByDrinkCooldown")
		end
		return
	end
	local ok, status, perSip, remaining = ConsumptionManager.consume(player, tool)
	if DEBUG_MIX then
		print(
			"[DrinkSystem][Consume]",
			player.Name,
			"OK=", ok,
			"Status=", status,
			"PerSip=", perSip,
			"Remaining=", remaining
		)
	end
	if not ok then
		return
	end
	session.LastDrinkTick = now
	-- Drink sound on the character — server-played so nearby players hear it
	DrinkEffectsService.playCharacterSound(player, Settings.DrinkSoundId, Settings.DrinkSoundVolume or 0.55)
	local glassTool = findGlassTool(player)
	if glassTool then
		local mix = getMixState(session, glassTool)
		recordStep(mix, session, "ConsumeDrink")
	end
end

function DrinkSystemController.onSelectRecipe(player: Player, recipeName: string?)
	if playerIsCollapsed(player) then return end
	local session = getSession(player)
	if not rateLimitOk(session) then return end
	if not hasShakerTool(player) then
		session.SelectedRecipe = nil
		session.SuggestedRecipe = nil
		session.SuggestedRecipes = {}
		session.DirtyGuidance = true
		return
	end

	if recipeName and Recipes[recipeName] then
		session.SelectedRecipe = recipeName
		session.SuggestedRecipe = nil
		session.SuggestedRecipes = {}
		session.DirtyGuidance = true
		local glassTool = findGlassTool(player)
		if glassTool then
			local mix = getMixState(session, glassTool)
			recordStep(mix, session, "SelectRecipe:" .. recipeName)
		end
	else
		session.SelectedRecipe = nil
		session.SuggestedRecipe = nil
		session.SuggestedRecipes = {}
		session.DirtyGuidance = true
		local glassTool = findGlassTool(player)
		if glassTool then
			local mix = getMixState(session, glassTool)
			recordStep(mix, session, "SelectRecipe:None")
		end
	end
end

local function wirePackets()
	Packets.RequestPickupItem.listen(function(data, player)
		DrinkSystemController.onPickup(player, data.Model)
	end)

	Packets.RequestPourIngredient.listen(function(data, player)
		DrinkSystemController.onPour(player, data.BottleModel)
	end)

	Packets.RequestAddGarnish.listen(function(data, player)
		DrinkSystemController.onAddGarnish(player, data.Model)
	end)

	Packets.RequestFinalizeMix.listen(function(_, player)
		DrinkSystemController.onFinalize(player)
	end)

	Packets.ShakerFinished.listen(function(_, player)
		DrinkSystemController.onShakerFinished(player)
	end)

	Packets.PlaceDrink.listen(function(data, player)
		DrinkSystemController.onPlaceDrink(player, data.Tool, data.Position)
	end)

	Packets.ConsumeDrink.listen(function(data, player)
		DrinkSystemController.onConsumeDrink(player, data.Tool)
	end)

	Packets.RequestSelectRecipe.listen(function(data, player)
		DrinkSystemController.onSelectRecipe(player, data.RecipeName)
	end)
end

local function startGuidanceLoop()
	if Settings.EnableGuidance ~= true then
		return
	end
	local interval = Settings.GuidanceUpdateInterval or 0.25
	task.spawn(function()
		while true do
			for _, session in pairs(sessions) do
				-- pcall per session: one bad session must not kill the loop
				-- (and guidance for every player) until server restart.
				local ok, err = pcall(function()
					local glassTool = findGlassTool(session.Player)

					-- Sticky glass: with multiple glasses owned, unequipping the
					-- mixing glass (e.g. to hold the shaker) makes findGlassTool
					-- return some OTHER backpack glass — which wiped the recipe
					-- context and flashed the all-bottles state. Only treat it as
					-- a switch when a different glass is actually EQUIPPED, or
					-- the old one is gone/finalized.
					local prev = session.GlassTool
					if glassTool ~= prev and prev then
						local char = session.Player.Character
						local backpack = session.Player:FindFirstChild("Backpack")
						local prevStillOwned = prev.Parent ~= nil
							and prev:GetAttribute("DS_Drink") ~= true
							and ((char and prev:IsDescendantOf(char)) or (backpack and prev:IsDescendantOf(backpack)))
						local newIsEquipped = glassTool ~= nil and char ~= nil and glassTool.Parent == char
						if prevStillOwned and not newIsEquipped then
							glassTool = prev
						end
					end

					-- Player switched to a different glass — force guidance refresh and clear recipe context
					if glassTool ~= session.GlassTool then
						session.GlassTool = glassTool
						session.DirtyGuidance = true
						session.LastGuidanceAt = 0  -- bypass rate limit so new guidance sends this tick
						session.SelectedRecipe = nil
						session.SuggestedRecipe = nil
						session.SuggestedRecipes = {}
					end
					-- Also mark dirty when the player picks up or puts down a finalized drink
					-- so garnish guidance fires immediately after finalization
					local heldDrink = findHeldDrinkForGarnish(session.Player)
					if heldDrink ~= session._lastHeldDrink then
						session._lastHeldDrink = heldDrink
						session.DirtyGuidance = true
					end
					sendGuidanceIfNeeded(session, glassTool)
				end)
				if not ok then
					warn("[DrinkSystem][Guidance] loop error for", session.Player and session.Player.Name, err)
				end
			end
			task.wait(interval)
		end
	end)
end

function DrinkSystemController.init()
	if initialized then return end
	initialized = true

	DrinkEffectsService.configure(Settings)
	DrinkEffectsService.start()
	wirePackets()
	startGuidanceLoop()

	local function onPlayerRespawn(player: Player)
		-- Wipe glass/drink tools and inventory count
		PickupManager.clearPlayerGlasses(player)
		-- Reset drunkness and stage to sober
		local effects = DrinkEffectsService.get(player)
		effects.DrunknessValue.Value = 0
		effects.CollapsedValue.Value = false
		effects.CollapsedUntil = 0
		effects.LastCollapseAt = -math.huge
		effects.LastStumbleAt = -math.huge
		effects.IsStumble = false
		-- Clear mix state so stale recipes don't carry over
		local session = sessions[player]
		if session then
			session.MixByTool = {}
			session.SelectedRecipe = nil
			session.SuggestedRecipe = nil
			session.SuggestedRecipes = {}
			session.GlassTool = nil
			session.DirtyGuidance = true
		end
	end

	local function setupPlayer(player: Player)
		getSession(player)
		player.CharacterAdded:Connect(function()
			task.defer(function()
				onPlayerRespawn(player)
			end)
		end)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayer(player)
	end
	Players.PlayerAdded:Connect(setupPlayer)

	Players.PlayerRemoving:Connect(function(player)
		GamepassManager.clearCacheForPlayer(player)
		DrinkCreationManager.onPlayerRemoving(player)
		clearSession(player)
	end)
end

return DrinkSystemController
