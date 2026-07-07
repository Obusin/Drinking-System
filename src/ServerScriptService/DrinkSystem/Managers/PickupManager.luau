-- PickupManager.lua (Multi-Glass / No Despawn Version)
-- Supports: up to 5 glasses, per-glass OOP, shaker pickup, drink pickup

local PickupManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystem:WaitForChild("Config")
local Settings = require(ConfigFolder:WaitForChild("Settings"))
local SharedModules = DrinkSystem:WaitForChild("SharedModules")
local GlassPresentation = require(SharedModules:WaitForChild("GlassPresentation"))

-- Templates
local GlassTemplates = DrinkSystem:WaitForChild("GlassTemplates")
local ShakerTemplates = DrinkSystem:WaitForChild("ShakerTemplates")
local DrinkTemplates = DrinkSystem:FindFirstChild("DrinkTemplates")

-- OOP Glass Class
local GlassClass = require(SharedModules:WaitForChild("GlassClass"))

local MAX_GLASSES = Settings.MaxGlasses or 5
local PlayerShakerUnlocked = {} -- {player = true/false}
local CharacterAddedConnections = {} -- {player = RBXScriptConnection}

---------------------------------------------------------------------
-- PLAYER GLASS INVENTORY
---------------------------------------------------------------------
local PlayerGlassInventory = {} -- {player = {GlassClassObj1, GlassClassObj2, ...}}

local function removeGlassFromInventory(player, tool)
	local list = PlayerGlassInventory[player]
	if not list then
		return
	end

	for index = #list, 1, -1 do
		local glassObj = list[index]
		if not glassObj or glassObj.Tool == tool or glassObj.Tool == nil then
			table.remove(list, index)
		end
	end
end

local function bindGlassLifecycle(player, tool: Tool)
	tool.Destroying:Connect(function()
		removeGlassFromInventory(player, tool)
	end)
end

local function releasePlacementSlot(model: Model)
	local slotRef = model:FindFirstChild("DS_PlacementSlot")
	if slotRef and slotRef:IsA("ObjectValue") then
		local slot = slotRef.Value
		if slot and slot:IsA("Attachment") then
			slot:SetAttribute("Occupied", false)
		end
		slotRef:Destroy()
	end
end

Players.PlayerAdded:Connect(function(plr)
	PlayerGlassInventory[plr] = {}
	PlayerShakerUnlocked[plr] = false
end)

Players.PlayerRemoving:Connect(function(plr)
	PlayerGlassInventory[plr] = nil
	PlayerShakerUnlocked[plr] = nil
	local conn = CharacterAddedConnections[plr]
	if conn then
		conn:Disconnect()
		CharacterAddedConnections[plr] = nil
	end
end)

local function addGlassToInventory(player, tool, glassObj)
	if not PlayerGlassInventory[player] then
		PlayerGlassInventory[player] = {}
	end
	table.insert(PlayerGlassInventory[player], glassObj)
	bindGlassLifecycle(player, tool)
end

local function playerHasGlassRoom(player)
	local list = PlayerGlassInventory[player]
	if not list then return true end
	return #list < MAX_GLASSES
end

---------------------------------------------------------------------
-- Give tool to player + auto-equip
---------------------------------------------------------------------
local function giveTool(player, tool: Tool)
	local char = player.Character
	if not char then return false end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end

	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return false end

	tool.CanBeDropped = false
	tool.Parent = backpack

	task.defer(function()
		if humanoid and tool.Parent == backpack then
			humanoid:EquipTool(tool)
		end
	end)

	return true
end

local function ensureToolHandle(tool: Tool)
	if tool:FindFirstChild("Handle") then
		return
	end
	local part = Instance.new("Part")
	part.Name = "Handle"
	part.Size = Vector3.new(1, 1, 1)
	part.CanCollide = false
	part.Parent = tool
	tool.Handle = part
end

local function sanitizeGlassToolState(tool: Tool, glassName: string?, fillStage: number?)
	tool:SetAttribute("DS_GlassTool", true)
	tool:SetAttribute("DS_DrinkTool", false)
	tool:SetAttribute("DS_Drink", false)
	tool:SetAttribute("DS_DrinkName", glassName or "Glass")
	tool:SetAttribute("DS_Strongness", 0)
	tool:SetAttribute("DS_IsRecipe", false)
	tool:SetAttribute("DS_RecipeName", "")
	tool:SetAttribute("DS_BaseIngredient", nil)
	tool:SetAttribute("DS_Outcome", nil)
	tool:SetAttribute("DS_Score", nil)
	tool:SetAttribute("DS_SipsMax", nil)
	tool:SetAttribute("DS_SipsRemaining", nil)

	if type(glassName) == "string" and glassName ~= "" and (typeof(fillStage) ~= "number" or fillStage <= 0) then
		tool.Name = glassName
	end
end

local function toolFromWorldModel(model: Model): Tool
	local tool = Instance.new("Tool")
	tool.Name = model.Name
	tool.CanBeDropped = false

	local modelClone = model:Clone()
	for _, child in ipairs(modelClone:GetChildren()) do
		if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("ModuleScript") or child:IsA("ProximityPrompt") or child:IsA("ClickDetector") then
			child:Destroy()
		else
			child.Parent = tool
		end
	end
	modelClone:Destroy()

	local handleSource = tool:FindFirstChild("Handle", true) or tool:FindFirstChildWhichIsA("BasePart")
	if handleSource and handleSource:IsA("BasePart") then
		handleSource.Name = "Handle"
		handleSource.Anchored = false
		handleSource.CanCollide = false
		tool.Handle = handleSource
	end

	ensureToolHandle(tool)
	return tool
end

local function playerHasShakerTool(player): boolean
	local char = player.Character
	local backpack = player:FindFirstChild("Backpack")
	local shakerToolName = Settings.ShakerToolName

	local function scan(container)
		if not container then return false end
		for _, inst in ipairs(container:GetChildren()) do
			if inst:IsA("Tool") then
				if inst:GetAttribute("DS_ShakerTool") == true then
					return true
				end
				if shakerToolName and inst.Name == shakerToolName then
					return true
				end
			end
		end
		return false
	end

	return scan(char) or scan(backpack)
end

local function cloneShakerToolTemplate(): Tool?
	local template = nil
	if Settings.ShakerToolName then
		template = ShakerTemplates:FindFirstChild(Settings.ShakerToolName)
	end
	if not template then
		template = ShakerTemplates:FindFirstChildWhichIsA("Tool")
	end
	if template and template:IsA("Tool") then
		local tool = template:Clone()
		tool:SetAttribute("DS_ShakerTool", true)
		return tool
	end
	return nil
end

local function cloneGlassToolTemplate(glassType: string?): Tool?
	-- Try the exact glass type from the world model first
	if glassType then
		local template = GlassTemplates:FindFirstChild(glassType)
		if template and template:IsA("Tool") then
			return template:Clone()
		end
	end

	-- Fall back to first configured glass name
	local glassNames = Settings.GlassToolNames or {}
	for _, glassName in ipairs(glassNames) do
		local template = GlassTemplates:FindFirstChild(glassName)
		if template and template:IsA("Tool") then
			return template:Clone()
		end
	end

	local fallback = GlassTemplates:FindFirstChildWhichIsA("Tool")
	if fallback then
		return fallback:Clone()
	end

	return nil
end

local function ensureOwnedShakerIfMissing(player)
	if PlayerShakerUnlocked[player] ~= true then
		return
	end
	for attempt = 1, 6 do
		if playerHasShakerTool(player) then
			return
		end

		local tool = cloneShakerToolTemplate()
		if not tool then
			return
		end

		local given = giveTool(player, tool)
		if given then
			ensureToolHandle(tool)
			return
		end

		tool:Destroy()
		if attempt < 6 then
			task.wait(0.2)
		end
	end
end

local function bindPlayerLifecycle(player)
	local conn = player.CharacterAdded:Connect(function()
		task.delay(0.2, function()
			ensureOwnedShakerIfMissing(player)
		end)
	end)
	CharacterAddedConnections[player] = conn

	if player.Character then
		task.delay(0.2, function()
			ensureOwnedShakerIfMissing(player)
		end)
	end
end

for _, plr in ipairs(Players:GetPlayers()) do
	if PlayerGlassInventory[plr] == nil then
		PlayerGlassInventory[plr] = {}
	end
	if PlayerShakerUnlocked[plr] == nil then
		PlayerShakerUnlocked[plr] = false
	end
	if not CharacterAddedConnections[plr] then
		bindPlayerLifecycle(plr)
	end
end

Players.PlayerAdded:Connect(function(plr)
	if not CharacterAddedConnections[plr] then
		bindPlayerLifecycle(plr)
	end
end)

---------------------------------------------------------------------
-- Create tool for finished drinks placed on table
---------------------------------------------------------------------
local function createDrinkToolFromWorldModel(model)
	local drinkName = model:GetAttribute("DS_DrinkName") or "Drink"
	local baseIngredient = model:GetAttribute("DS_BaseIngredient")
	local strongness = model:GetAttribute("DS_Strongness") or 0
	local outcome = model:GetAttribute("DS_Outcome")
	local score = model:GetAttribute("DS_Score")
	local maxSips = model:GetAttribute("DS_MaxSips")
	if typeof(maxSips) ~= "number" or maxSips <= 0 then
		maxSips = model:GetAttribute("MaxSips")
	end
	local glassType = model:GetAttribute("DS_GlassType") or "Glass"
	local drinkColor = model:GetAttribute("DS_Color") :: Color3?
	local fillStage = model:GetAttribute("DS_FillStage") or 1
	local garnishesCsv = model:GetAttribute("DS_GarnishesCsv") or ""

	-- Clone the proper Glass template so the tool has the right Grip, Handle,
	-- GlassPart structure and hold position — not a bare Instance.new("Tool").
	local tool = cloneGlassToolTemplate(glassType)
	if not tool then
		-- Fallback: bare tool if no template found
		tool = Instance.new("Tool")
		tool.CanBeDropped = false
	end

	tool.Name = drinkName
	tool.CanBeDropped = false

	-- Apply drink state onto the cloned template
	tool:SetAttribute("DS_DrinkTool", true)
	tool:SetAttribute("DS_Drink", true)
	tool:SetAttribute("DS_GlassTool", nil)
	tool:SetAttribute("DS_DrinkName", drinkName)
	tool:SetAttribute("DS_Color", drinkColor)
	tool:SetAttribute("DS_IngredientListCsv", model:GetAttribute("DS_IngredientListCsv") or "")
	tool:SetAttribute("DS_IngredientsText", model:GetAttribute("DS_IngredientsText") or "")
	if type(baseIngredient) == "string" and baseIngredient ~= "" then
		tool:SetAttribute("DS_BaseIngredient", baseIngredient)
	end
	if typeof(maxSips) == "number" and maxSips > 0 then
		tool:SetAttribute("DS_MaxSips", maxSips)
		tool:SetAttribute("MaxSips", maxSips)
	end
	tool:SetAttribute("DS_Strongness", strongness)
	if outcome then tool:SetAttribute("DS_Outcome", outcome) end
	if score then tool:SetAttribute("DS_Score", score) end
	tool:SetAttribute("DS_FillStage", fillStage)
	tool:SetAttribute("DS_GarnishesCsv", garnishesCsv)

	-- Re-apply fill color and garnishes onto the template's glass parts
	local garnishes = {}
	for token in string.gmatch(garnishesCsv, "([^,]+)") do
		table.insert(garnishes, token)
	end
	-- Unanchor all parts — template parts may be anchored in Studio
	for _, desc in ipairs(tool:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			desc.CanCollide = false
		end
	end

	GlassPresentation.applyFinalPresentation(tool, fillStage, drinkColor, garnishes)

	return tool
end

---------------------------------------------------------------------
-- MAIN PICKUP HANDLER
---------------------------------------------------------------------
function PickupManager.pickup(player, model: Model)
	if not model or not model:IsA("Model") then
		return false, "NotAModel"
	end

	-----------------------------------------------------------------
	-- GLASS PICKUP (configured glass template, DOES NOT DESPAWN WORLD MODEL)
	-----------------------------------------------------------------
	local glassType = model:GetAttribute("DS_Glass")
	if type(glassType) == "string" then
		if not playerHasGlassRoom(player) then
			return false, "MaxGlassesReached"
		end

		local tool = cloneGlassToolTemplate(glassType)
		if not tool then
			warn("[PickupManager] Missing configured glass template in GlassTemplates. Using world model as tool.")
			tool = toolFromWorldModel(model)
		end

		-- DO NOT DELETE MODEL
		-- model stays on table
		local placedGlass = model:GetAttribute("DS_PlacedGlass") == true
		local maxSips = model:GetAttribute("MaxSips")
		if typeof(maxSips) ~= "number" or maxSips <= 0 then
			maxSips = model:GetAttribute("DS_MaxSips")
		end
		if typeof(maxSips) == "number" and maxSips > 0 then
			tool:SetAttribute("DS_MaxSips", maxSips)
			tool:SetAttribute("MaxSips", maxSips)
		end
		tool:SetAttribute("DS_Glass", glassType)
		tool:SetAttribute("DS_FillStage", model:GetAttribute("DS_FillStage") or 0)
		tool:SetAttribute("DS_GarnishesCsv", model:GetAttribute("DS_GarnishesCsv") or "")
		tool:SetAttribute("DS_Color", model:GetAttribute("DS_Color"))
		tool:SetAttribute("DS_IngredientListCsv", model:GetAttribute("DS_IngredientListCsv") or "")
		tool:SetAttribute("DS_IngredientsText", model:GetAttribute("DS_IngredientsText") or "")
		if model:GetAttribute("GlassType") ~= nil then
			tool:SetAttribute("GlassType", model:GetAttribute("GlassType"))
		end
		local fillStage = tool:GetAttribute("DS_FillStage") or 0
		sanitizeGlassToolState(tool, glassType, fillStage)
		local fillColor = tool:GetAttribute("DS_Color")
		if fillStage > 0 then
			GlassPresentation.applyFillState(tool, fillStage, fillColor)
		else
			GlassPresentation.reset(tool)
		end

		-- give tool
		giveTool(player, tool)
		ensureToolHandle(tool)

		-- make OOP glass object
		local glassObj = GlassClass.new(tool)
		addGlassToInventory(player, tool, glassObj)

		if placedGlass then
			releasePlacementSlot(model)
			model:Destroy()
		end

		return true, if placedGlass then "PlacedGlassPicked" else "GlassPicked"
	end

	-----------------------------------------------------------------
	-- SHAKER PICKUP
	-----------------------------------------------------------------
	if model:GetAttribute("DS_Shaker") == true then
		if PlayerShakerUnlocked[player] == true or playerHasShakerTool(player) then
			return false, "AlreadyHasShaker"
		end

		local tool = cloneShakerToolTemplate()
		if not tool then
			warn("[PickupManager] Missing shaker tool template. Using world model as tool.")
			tool = toolFromWorldModel(model)
			tool:SetAttribute("DS_ShakerTool", true)
		end

		giveTool(player, tool)
		ensureToolHandle(tool)
		PlayerShakerUnlocked[player] = true
		return true, "ShakerPicked"
	end

	-----------------------------------------------------------------
	-- PICKUP FINISHED DRINK (World drink → Tool)
	-----------------------------------------------------------------
	if model:GetAttribute("DS_Drink") == true then
		releasePlacementSlot(model)
		local drinkName = model:GetAttribute("DS_DrinkName")

		-- createDrinkToolFromWorldModel handles all attribute copying, Glass template
		-- cloning, unanchoring, and applyFinalPresentation in one place.
		local tool = createDrinkToolFromWorldModel(model)
		-- Apply remaining sips tracking (not stored by createDrinkToolFromWorldModel)
		local remainingSips = model:GetAttribute("DS_SipsRemaining")
		local maxSips = tool:GetAttribute("DS_MaxSips")
		if typeof(remainingSips) == "number" and remainingSips >= 0 then
			tool:SetAttribute("DS_SipsRemaining", remainingSips)
			tool:SetAttribute("DS_SipsMax", maxSips or remainingSips)
		end

		-- Finished drinks do despawn
		model:Destroy()

		giveTool(player, tool)
		ensureToolHandle(tool)
		return true, "WorldDrinkPicked"
	end

	return false, "NoPickupAttribute"
end

-- Called on respawn: destroy all glass/drink tools the player owns and reset the inventory count.
function PickupManager.clearPlayerGlasses(player: Player)
	local backpack = player:FindFirstChild("Backpack")
	local char = player.Character

	local function destroyGlassAndDrinkTools(container)
		if not container then return end
		for _, tool in ipairs(container:GetChildren()) do
			if tool:IsA("Tool") then
				local isGlass = tool:GetAttribute("DS_GlassTool") == true
				local isDrink = tool:GetAttribute("DS_Drink") == true
				local isDrinkTool = tool:GetAttribute("DS_DrinkTool") == true
				if isGlass or isDrink or isDrinkTool then
					tool:Destroy()
				end
			end
		end
	end

	destroyGlassAndDrinkTools(backpack)
	destroyGlassAndDrinkTools(char)

	PlayerGlassInventory[player] = {}
end

return PickupManager
