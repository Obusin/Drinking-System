-- ServerScriptService/DrinkSystem/ConsumptionManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DrinkSystemFolder = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystemFolder:WaitForChild("Config")

local Settings = require(ConfigFolder:WaitForChild("Settings"))

local DrinkEffectsService = require(script.Parent.Parent:WaitForChild("Services"):WaitForChild("DrinkEffectsService"))

local ConsumptionManager = {}

local function playerOwnsTool(player: Player, drinkTool: Tool): boolean
	if not drinkTool or not drinkTool:IsA("Tool") then
		return false
	end

	local backpack = player:FindFirstChild("Backpack")
	if backpack and drinkTool:IsDescendantOf(backpack) then
		return true
	end

	local character = player.Character
	if character and drinkTool:IsDescendantOf(character) then
		return true
	end

	return false
end

local function getSipValues(drinkTool: Tool): (number, number)
	local maxSips = drinkTool:GetAttribute("DS_SipsMax")
	local remaining = drinkTool:GetAttribute("DS_SipsRemaining")
	if typeof(maxSips) ~= "number" or maxSips <= 0 then
		maxSips = drinkTool:GetAttribute("DS_MaxSips")
		if typeof(maxSips) ~= "number" or maxSips <= 0 then
			maxSips = Settings.DefaultDrinkSips or 1
		end
	end
	if typeof(remaining) ~= "number" then
		remaining = maxSips
	end
	return maxSips, remaining
end

local function drinkHasContents(drinkTool: Tool): boolean
	local fillStage = drinkTool:GetAttribute("DS_FillStage")
	if typeof(fillStage) == "number" and fillStage <= 0 then
		return false
	end

	local ingredientCsv = drinkTool:GetAttribute("DS_IngredientListCsv")
	local drinkName = drinkTool:GetAttribute("DS_DrinkName")
	local strongness = drinkTool:GetAttribute("DS_Strongness") or 0

	if type(ingredientCsv) == "string" and ingredientCsv ~= "" then
		return true
	end
	if strongness > 0 then
		return true
	end
	if type(drinkName) == "string" and drinkName ~= "" and drinkName ~= "Glass" then
		return true
	end

	return false
end

function ConsumptionManager.consume(player: Player, drinkTool: Tool)
	if not playerOwnsTool(player, drinkTool) then
		return false, "ToolNotOwned"
	end

	if not drinkTool:GetAttribute("DS_Drink") then
		return false, "NotADrinkTool"
	end
	if not drinkHasContents(drinkTool) then
		return false, "DrinkEmpty"
	end

	local strongness = drinkTool:GetAttribute("DS_Strongness") or 0
	local maxSips, remaining = getSipValues(drinkTool)
	if remaining <= 0 then
		return false, "DrinkEmpty"
	end
	local perSip = strongness / math.max(1, maxSips)

	DrinkEffectsService.applyDrink(player, perSip)
	local drunknessValue = player:FindFirstChild("Drunkness")
	local drunknessNow = drunknessValue and drunknessValue.Value or 0

	remaining -= 1
	if remaining <= 0 then
		drinkTool:Destroy()
	else
		drinkTool:SetAttribute("DS_SipsMax", maxSips)
		drinkTool:SetAttribute("DS_SipsRemaining", remaining)
	end

	if Settings.EnableDrunkDebug == true then
		local drinkName = tostring(drinkTool:GetAttribute("DS_DrinkName") or drinkTool.Name)
		print(
			"[DrinkSystem][Drunkness]",
			player.Name,
			"Drink=", drinkName,
			"PerSip=", perSip,
			"Strongness=", strongness,
			"SipsRemaining=", remaining,
			"DrunknessNow=", drunknessNow
		)
	end

	return true, "Consumed", perSip, remaining
end

return ConsumptionManager
