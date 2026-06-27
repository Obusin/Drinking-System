-- HoverInteractionController
-- Handles highlighting, pickup, and pouring.
-- Highlights only real world bottles/glasses/shakers, NEVER the cloned bottle in-hand.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer

-- Global ignore list for cloned bottles created during pouring
_G.DS_IgnoreModels = _G.DS_IgnoreModels or {}

local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local SharedModules = DrinkSystem:WaitForChild("SharedModules")
local ConfigFolder = DrinkSystem:WaitForChild("Config")

local Settings = require(ConfigFolder:WaitForChild("Settings"))
if Settings.EnableHoverInteractionController ~= true then
	return
end
local Network = require(SharedModules:WaitForChild("Network"))
local Packets = Network.Packets

local RequestPickupItem = Packets.RequestPickupItem
local RequestPourIngredient = Packets.RequestPourIngredient
local RequestAddGarnish = Packets.RequestAddGarnish
local GuidanceUpdate = Packets.GuidanceUpdate
local RequestFinalizeMix = Packets.RequestFinalizeMix

---------------------------------------------------------------------
-- Helper: Is player holding a glass tool?
---------------------------------------------------------------------
local function playerIsHoldingGlass()
	local char = player.Character
	if not char then return false end

	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool then return false end

	return tool:GetAttribute("DS_GlassTool") == true and tool:GetAttribute("DS_Drink") ~= true
end

local function playerIsHoldingDrinkTool(): boolean
	local char = player.Character
	if not char then return false end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool then return false end
	return tool:GetAttribute("DS_Drink") == true or tool:GetAttribute("DS_DrinkTool") == true
end

---------------------------------------------------------------------
-- Helper: Get root model from a hit part
---------------------------------------------------------------------
local function getRootModel(part)
	if not part then return nil end
	return part:FindFirstAncestorOfClass("Model")
		or part:FindFirstAncestorOfClass("Tool")
		or part
end

---------------------------------------------------------------------
-- Detect interactable type (Bottle / Glass / Shaker / Garnish)
---------------------------------------------------------------------
local function detectType(model)
	if not model then return nil end

	local char = player.Character

	-- 1. Ignore character completely
	if char and (model == char or model:IsDescendantOf(char)) then
		return nil
	end

	-- 2. Ignore cloned bottle(s) in hand
	for _, ignoreModel in ipairs(_G.DS_IgnoreModels) do
		if ignoreModel and (model == ignoreModel or model:IsDescendantOf(ignoreModel)) then
			return nil
		end
	end

	-- 3. Detect via attributes on model
	local attrGlass = model:GetAttribute("DS_Glass")
	local attrGlass2 = model:GetAttribute("DS__Glass")
	if attrGlass == true or attrGlass2 == true or type(attrGlass) == "string" or type(attrGlass2) == "string" then
		return "Glass"
	end

	if model:GetAttribute("DS_Shaker") == true or model:GetAttribute("DS__Shaker") == true then
		return "Shaker"
	end

	if model:GetAttribute("DS_ShakerTool") == true then
		return "Shaker"
	end

	if type(model:GetAttribute("DS_Garnish")) == "string" then
		return "Garnish"
	end

	if model:GetAttribute("DS_Drinks") == true then
		return "Bottle"
	end
	if CollectionService:HasTag(model, "DS__Bottle") or CollectionService:HasTag(model, "DS_Bottle") then
		return "Bottle"
	end
	if CollectionService:HasTag(model, "DS__Glass") or CollectionService:HasTag(model, "DS_Glass") then
		return "Glass"
	end
	if CollectionService:HasTag(model, "DS__Shaker") or CollectionService:HasTag(model, "DS_Shaker") then
		return "Shaker"
	end

	if model:IsA("Tool") then
		if model:GetAttribute("DS_ShakerTool") == true then
			return "Shaker"
		end
		if model:GetAttribute("DS_GlassTool") == true then
			return "Glass"
		end
		local shakerName = Settings.ShakerToolName
		if shakerName and model.Name == shakerName then
			return "Shaker"
		end
	end

	-- 4. Detect via attributes on descendants
	for _, child in ipairs(model:GetDescendants()) do
		local garnish = child:GetAttribute("DS_Garnish")
		if type(garnish) == "string" then
			return "Garnish"
		end

		if child:IsA("BasePart") or child:IsA("MeshPart") or child:IsA("UnionOperation") then
			local glass  = child:GetAttribute("DS_Glass")
			local glass2 = child:GetAttribute("DS__Glass")
			local drinks = child:GetAttribute("DS_Drinks")
			local shaker = child:GetAttribute("DS_Shaker")
			local shaker2 = child:GetAttribute("DS__Shaker")
			local shakerTool = child:GetAttribute("DS_ShakerTool")

			if glass == true or glass2 == true or type(glass) == "string" or type(glass2) == "string" then
				return "Glass"
			end
			if drinks == true then
				return "Bottle"
			end
			if shaker == true or shaker2 == true then
				return "Shaker"
			end
			if shakerTool == true then
				return "Shaker"
			end
		end
	end

	return nil
end

local function getIngredientName(model: Model): string?
	if model:GetAttribute("DS_Drinks") == true then
		return model:GetAttribute("DS_IngredientName") or model.Name
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:GetAttribute("DS_Drinks") == true then
			return d:GetAttribute("DS_IngredientName") or model.Name
		end
	end
	return nil
end

---------------------------------------------------------------------
-- Guidance state + highlights
---------------------------------------------------------------------
local guidance = {
	RecommendedIngredients = {},
	RequiredItemType = nil,
}

local guidanceTargets = {
	Recommended = {},
	Required = nil,
}

local function isRecommended(model: Model): boolean
	local ing = getIngredientName(model)
	if not ing then return false end
	for _, name in ipairs(guidance.RecommendedIngredients or {}) do
		if name == ing then
			return true
		end
	end
	return false
end

local function isRequired(model: Model): boolean
	local itemType = detectType(model)
	if not itemType then return false end
	return guidance.RequiredItemType == itemType
end

local function collectNearestModels(predicate, maxCount: number): {Model}
	local char = player.Character
	if not char then return {} end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return {} end

	local candidates = {}
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Model") and predicate(inst) then
			local part = inst:FindFirstChildWhichIsA("BasePart", true)
			if part then
				table.insert(candidates, {
					Model = inst,
					Dist = (part.Position - root.Position).Magnitude,
				})
			end
		end
	end

	table.sort(candidates, function(a, b)
		return a.Dist < b.Dist
	end)

	local out = {}
	for i = 1, math.min(maxCount, #candidates) do
		table.insert(out, candidates[i].Model)
	end
	return out
end

local function findNearestModel(predicate)
	local list = collectNearestModels(predicate, 1)
	return list[1]
end

local GUIDANCE_MAX_RECOMMENDED_HIGHLIGHTS = 6

local requiredGuidanceHighlight = Instance.new("Highlight")
requiredGuidanceHighlight.Enabled = false
requiredGuidanceHighlight.FillTransparency = 0.5
requiredGuidanceHighlight.OutlineTransparency = 0
requiredGuidanceHighlight.FillColor = Color3.fromRGB(255, 180, 80)
requiredGuidanceHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
requiredGuidanceHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
requiredGuidanceHighlight.Parent = workspace

local recommendedGuidanceHighlights = {}
for i = 1, GUIDANCE_MAX_RECOMMENDED_HIGHLIGHTS do
	local h = Instance.new("Highlight")
	h.Name = "DS_GuidanceRecommended_" .. tostring(i)
	h.Enabled = false
	h.FillTransparency = 0.5
	h.OutlineTransparency = 0
	h.FillColor = Color3.fromRGB(120, 255, 120)
	h.OutlineColor = Color3.fromRGB(255, 255, 255)
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = workspace
	table.insert(recommendedGuidanceHighlights, h)
end

local function applyGuidanceHighlights()
	for i, h in ipairs(recommendedGuidanceHighlights) do
		local model = guidanceTargets.Recommended[i]
		if model and model:IsDescendantOf(workspace) then
			h.Adornee = model
			h.Enabled = true
		else
			h.Adornee = nil
			h.Enabled = false
		end
	end

	local requiredModel = guidanceTargets.Required
	if requiredModel and requiredModel:IsDescendantOf(workspace) then
		requiredGuidanceHighlight.Adornee = requiredModel
		requiredGuidanceHighlight.Enabled = true
	else
		requiredGuidanceHighlight.Adornee = nil
		requiredGuidanceHighlight.Enabled = false
	end
end

local function refreshGuidanceTargets()
	guidanceTargets.Recommended = collectNearestModels(isRecommended, GUIDANCE_MAX_RECOMMENDED_HIGHLIGHTS)
	guidanceTargets.Required = findNearestModel(isRequired)
	applyGuidanceHighlights()
end

GuidanceUpdate.listen(function(payload)
	guidance.RecommendedIngredients = payload.RecommendedIngredients or {}
	guidance.RequiredItemType = payload.RequiredItemType
	refreshGuidanceTargets()
end)

local function isGuidedClickAllowed(model: Model, itemType: string): boolean
	if guidance.RequiredItemType and itemType ~= guidance.RequiredItemType then
		return false
	end

	if itemType == "Bottle" and #(guidance.RecommendedIngredients or {}) > 0 then
		return isRecommended(model)
	end

	return true
end

---------------------------------------------------------------------
-- Highlight Setup — parent to Workspace, NOT to the model
---------------------------------------------------------------------
local hoverHighlight = Instance.new("Highlight")
hoverHighlight.Enabled = false
hoverHighlight.FillTransparency = 0.5
hoverHighlight.OutlineTransparency = 0
hoverHighlight.FillColor = Color3.fromRGB(255, 255, 0)
hoverHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
hoverHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
hoverHighlight.Parent = workspace  -- ✅ 3D object, so keep it in Workspace

local currentModel = nil
local lastGuidanceRefreshAt = 0

---------------------------------------------------------------------
-- Raycast ignoring player's character
---------------------------------------------------------------------
local function getRaycastTarget()
	local char = player.Character
	if not char then return nil end

	local cam = workspace.CurrentCamera
	if not cam then return nil end

	local mousePos = UIS:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mousePos.X, mousePos.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }

	local result = workspace:Raycast(ray.Origin, ray.Direction * 200, params)
	return result and result.Instance or nil
end

---------------------------------------------------------------------
-- Highlight logic
---------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	local now = os.clock()
	if now - lastGuidanceRefreshAt >= 0.25 then
		lastGuidanceRefreshAt = now
		refreshGuidanceTargets()
	end

	local target = getRaycastTarget()

	local hoveredModel = target and getRootModel(target) or nil
	local hoverType = hoveredModel and detectType(hoveredModel) or nil

	local function applyHighlight(model)
		if not model then
			hoverHighlight.Enabled = false
			currentModel = nil
			return
		end

		hoverHighlight.FillColor = Color3.fromRGB(255, 255, 0)
		hoverHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)

		if currentModel ~= model then
			currentModel = model
			hoverHighlight.Adornee = model
		end
		hoverHighlight.Enabled = true
	end

	if hoveredModel and hoverType then
		applyHighlight(hoveredModel)
	else
		hoverHighlight.Enabled = false
		currentModel = nil
	end
end)

---------------------------------------------------------------------
-- Interaction on click
---------------------------------------------------------------------
local function tryInteract()
	if not currentModel then return end

	local t = detectType(currentModel)
	if not t then return end
	if not isGuidedClickAllowed(currentModel, t) then
		return
	end

	-- Do not consume click input while the player is holding a drink
	-- unless the click is targeting a garnish station.
	if t ~= "Garnish" and playerIsHoldingDrinkTool() then
		return
	end

	-- Bottle pour
	if t == "Bottle" then
		if not playerIsHoldingGlass() then
			print("[DEBUG] Cannot pour — no glass equipped.")
			return
		end
		RequestPourIngredient.send({ BottleModel = currentModel })
		return
	end

	if t == "Garnish" then
		if not playerIsHoldingDrinkTool() then
			print("[DEBUG] Cannot garnish - no finished drink equipped.")
			return
		end
		RequestAddGarnish.send({ Model = currentModel })
		return
	end

	-- Shaker: pick up then finalize mix
	if t == "Shaker" then
		RequestPickupItem.send({ Model = currentModel })
		task.delay(0.12, function()
			RequestFinalizeMix.send({})
		end)
		return
	end

	-- Glass pickup
	if t == "Glass" then
		RequestPickupItem.send({ Model = currentModel })
		return
	end
end
UIS.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		tryInteract()
	end
end)
