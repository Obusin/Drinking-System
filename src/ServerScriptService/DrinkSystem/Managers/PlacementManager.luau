-- ServerScriptService/DrinkSystem/PlacementManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local DrinkSystemFolder = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystemFolder:WaitForChild("Config")
local Settings = require(ConfigFolder:WaitForChild("Settings"))
local SharedModules = DrinkSystemFolder:WaitForChild("SharedModules")
local GlassPresentation = require(SharedModules:WaitForChild("GlassPresentation"))

local PlacementManager = {}

local function parseCsv(csv: string?): {string}
	local out = {}
	if type(csv) ~= "string" or csv == "" then
		return out
	end
	for token in string.gmatch(csv, "([^,]+)") do
		table.insert(out, token)
	end
	return out
end

local function isSurfacePart(part: BasePart): boolean
	if part:GetAttribute("DS_Surface") == true then
		return true
	end
	if CollectionService:HasTag(part, "DS_Surface") or CollectionService:HasTag(part, "DS__Surface") then
		return true
	end
	return false
end

-- Returns true if this part (or any ancestor model) is tagged DS_Table.
local function isTablePart(part: BasePart): boolean
	if part:GetAttribute("DS_Table") == true or CollectionService:HasTag(part, "DS_Table") then
		return true
	end
	-- Walk ancestors: designers often tag the top-level Model, not individual parts
	local ancestor = part.Parent
	while ancestor and ancestor ~= workspace do
		if ancestor:GetAttribute("DS_Table") == true or CollectionService:HasTag(ancestor, "DS_Table") then
			return true
		end
		ancestor = ancestor.Parent
	end
	return false
end

-- Among all BaseParts in a DS_Table model, pick the one with the highest top face (Y).
-- This is the surface the player stands drinks on.
local function getTopSurfacePart(part: BasePart): BasePart
	local best = part
	local bestTopY = part.Position.Y + part.Size.Y * 0.5

	local model = part.Parent
	if model and model:IsA("Model") then
		for _, child in ipairs(model:GetDescendants()) do
			if child:IsA("BasePart") then
				local topY = child.Position.Y + child.Size.Y * 0.5
				if topY > bestTopY then
					bestTopY = topY
					best = child
				end
			end
		end
	end

	return best
end

local function findNearestSurface(player: Player): BasePart?
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local maxDist = Settings.MaxInteractDistance or 12
	local nearest, nearestDist = nil, maxDist

	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") then
			local candidate: BasePart?
			if isSurfacePart(obj) then
				candidate = obj
			elseif isTablePart(obj) then
				candidate = getTopSurfacePart(obj)
			end
			if candidate then
				-- Use closest point on the surface's bounding box so large parts
				-- (long bar counters etc.) are reachable from the edge, not just the center.
				local localPoint = candidate.CFrame:PointToObjectSpace(root.Position)
				local half = candidate.Size * 0.5
				local clamped = Vector3.new(
					math.clamp(localPoint.X, -half.X, half.X),
					math.clamp(localPoint.Y, -half.Y, half.Y),
					math.clamp(localPoint.Z, -half.Z, half.Z)
				)
				local closest = candidate.CFrame:PointToWorldSpace(clamped)
				local dist = (closest - root.Position).Magnitude
				if dist <= maxDist and dist < nearestDist then
					nearest = candidate
					nearestDist = dist
				end
			end
		end
	end

	return nearest
end

local function findEmptySlot(surface: BasePart)
	for _, child in ipairs(surface:GetChildren()) do
		if child:IsA("Attachment") and not child:GetAttribute("Occupied") then
			return child
		end
	end
end

local function getDrinkHalfHeight(worldModel: Model): number
	local _, size = worldModel:GetBoundingBox()
	return math.max(size.Y * 0.5, 0.35)
end

local function surfaceTopY(surface: BasePart): number
	return surface.Position.Y + (surface.Size.Y * 0.5)
end

local function getLookForward(root: BasePart): Vector3
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return look.Unit
end

local function clampPointToSurfaceXZ(surface: BasePart, worldPoint: Vector3): Vector3
	local localPoint = surface.CFrame:PointToObjectSpace(worldPoint)
	local halfX = surface.Size.X * 0.5
	local halfZ = surface.Size.Z * 0.5
	local clampedLocal = Vector3.new(
		math.clamp(localPoint.X, -halfX + 0.3, halfX - 0.3),
		localPoint.Y,
		math.clamp(localPoint.Z, -halfZ + 0.3, halfZ - 0.3)
	)
	return surface.CFrame:PointToWorldSpace(clampedLocal)
end

local function computeTablePlacementCFrame(player: Player, surface: BasePart, worldModel: Model): CFrame
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local halfH = getDrinkHalfHeight(worldModel)

	local targetPos
	if root then
		local forward = getLookForward(root)
		local preferred = root.Position + (forward * 3)
		targetPos = clampPointToSurfaceXZ(surface, preferred)
	else
		targetPos = surface.Position
	end

	targetPos = Vector3.new(targetPos.X, surfaceTopY(surface) + halfH, targetPos.Z)

	local yaw = 0
	if root then
		yaw = math.atan2(root.CFrame.LookVector.X, root.CFrame.LookVector.Z)
	end

	-- Keep drinks upright in world-space so they never flip with rotated surfaces.
	return CFrame.new(targetPos) * CFrame.Angles(0, yaw, 0)
end

-- Clone glass visual from Tool to world model
local function createWorldDrinkFromTool(tool: Tool, drinkName: string, color: Color3?)
	local worldModel = Instance.new("Model")
	worldModel.Name = drinkName or "Drink"

	local toolClone = tool:Clone()
	for _, child in ipairs(toolClone:GetChildren()) do
		if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("ModuleScript") then
			child:Destroy()
		else
			child.Parent = worldModel
		end
	end
	toolClone:Destroy()

	for _, descendant in ipairs(worldModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end

	local handle = worldModel:FindFirstChild("Handle", true)
	if handle and handle:IsA("BasePart") then
		worldModel.PrimaryPart = handle
	else
		local fallback = worldModel:FindFirstChildWhichIsA("BasePart", true)
		if fallback then
			worldModel.PrimaryPart = fallback
		end
	end

	if color then
		GlassPresentation.setFillColor(worldModel, color)
	end

	return worldModel
end

local function bindPlacementSlot(worldModel: Model, slot: Attachment?)
	if not slot then
		return
	end

	local ref = Instance.new("ObjectValue")
	ref.Name = "DS_PlacementSlot"
	ref.Value = slot
	ref.Parent = worldModel
end

function PlacementManager.placeDrinkFromTool(player: Player, drinkTool: Tool, clientPosition: Vector3?)
	local char = player.Character
	local ownedByPlayer = drinkTool and (drinkTool:IsDescendantOf(player) or (char and drinkTool:IsDescendantOf(char)))
	if not ownedByPlayer then
		return false, "ToolNotOwned"
	end

	local isDrink = drinkTool:GetAttribute("DS_Drink") == true
	local isGlass = drinkTool:GetAttribute("DS_GlassTool") == true
	if not isDrink and not isGlass then
		return false, "NotAPlaceableTool"
	end

	local surface = findNearestSurface(player)
	if not surface then
		warn("[PlacementManager] No surface found near", player.Name, "— is the table tagged DS_Table or DS_Surface in Studio?")
		return false, "NoSurfaceFound"
	end

	local slot = findEmptySlot(surface)

	local drinkName = drinkTool:GetAttribute("DS_DrinkName") or drinkTool.Name
	local drinkColor = drinkTool:GetAttribute("DS_Color") :: Color3?

	local worldModel = createWorldDrinkFromTool(drinkTool, drinkName, drinkColor)

	local root = char and char:FindFirstChild("HumanoidRootPart")
	local yaw = 0
	if root then
		yaw = math.atan2(root.CFrame.LookVector.X, root.CFrame.LookVector.Z)
	end
	local halfH = getDrinkHalfHeight(worldModel)

	if clientPosition then
		-- Use the position the client previewed. Sanity-check: must be within MaxInteractDistance+2 of the player.
		local maxDist = (Settings.MaxInteractDistance or 12) + 2
		local rootPos = root and root.Position or surface.Position
		if (clientPosition - rootPos).Magnitude <= maxDist then
			-- Clamp to the surface top Y so it sits on top, not inside
			local topY = surfaceTopY(surface) + halfH
			local clamped = clampPointToSurfaceXZ(surface, clientPosition)
			worldModel:PivotTo(CFrame.new(clamped.X, topY, clamped.Z) * CFrame.Angles(0, yaw, 0))
		else
			worldModel:PivotTo(computeTablePlacementCFrame(player, surface, worldModel))
		end
	elseif slot then
		slot:SetAttribute("Occupied", true)
		bindPlacementSlot(worldModel, slot)
		local slotPos = slot.WorldPosition
		worldModel:PivotTo(CFrame.new(slotPos.X, slotPos.Y + halfH, slotPos.Z) * CFrame.Angles(0, yaw, 0))
	else
		worldModel:PivotTo(computeTablePlacementCFrame(player, surface, worldModel))
	end
	worldModel.Parent = workspace

	-- Optionally copy some attributes onto the world model
	worldModel:SetAttribute("DS_Drink", isDrink)
	worldModel:SetAttribute("DS_DrinkName", drinkName)
	-- Recipe identity MUST survive placement — special drinks (Solaire's Spit
	-- sound, Sin Obu effects) and stats key off DS_RecipeName after re-pickup.
	worldModel:SetAttribute("DS_RecipeName", drinkTool:GetAttribute("DS_RecipeName") or "")
	worldModel:SetAttribute("DS_MakerUserId", drinkTool:GetAttribute("DS_MakerUserId"))
	worldModel:SetAttribute("DS_IsRecipe", drinkTool:GetAttribute("DS_IsRecipe") == true)
	worldModel:SetAttribute("DS_BaseIngredient", drinkTool:GetAttribute("DS_BaseIngredient"))
	worldModel:SetAttribute("DS_MaxSips", drinkTool:GetAttribute("DS_MaxSips") or drinkTool:GetAttribute("MaxSips"))
	worldModel:SetAttribute("MaxSips", drinkTool:GetAttribute("DS_MaxSips") or drinkTool:GetAttribute("MaxSips"))
	worldModel:SetAttribute("DS_SipsRemaining", drinkTool:GetAttribute("DS_SipsRemaining"))
	worldModel:SetAttribute("DS_Strongness", drinkTool:GetAttribute("DS_Strongness") or 0)
	worldModel:SetAttribute("DS_Outcome", drinkTool:GetAttribute("DS_Outcome"))
	worldModel:SetAttribute("DS_Score", drinkTool:GetAttribute("DS_Score"))
	worldModel:SetAttribute("DS_FillStage", drinkTool:GetAttribute("DS_FillStage") or 1)
	worldModel:SetAttribute("DS_GarnishesCsv", drinkTool:GetAttribute("DS_GarnishesCsv") or "")
	worldModel:SetAttribute("DS_Color", drinkColor)
	worldModel:SetAttribute("DS_IngredientListCsv", drinkTool:GetAttribute("DS_IngredientListCsv") or "")
	worldModel:SetAttribute("DS_IngredientsText", drinkTool:GetAttribute("DS_IngredientsText") or "")
	-- DS_Glass only on empty placed glasses (triggers glass-template pickup path in PickupManager).
	-- DS_GlassType stores the template name for finished drinks so pickup can rebuild from
	-- the correct Glass template without conflicting with the DS_Glass pickup check.
	if isGlass and not isDrink then
		worldModel:SetAttribute("DS_Glass", drinkTool:GetAttribute("DS_Glass") or drinkTool:GetAttribute("GlassType") or "Glass")
	end
	worldModel:SetAttribute("DS_GlassType", drinkTool:GetAttribute("DS_Glass") or drinkTool:GetAttribute("GlassType") or "Glass")
	worldModel:SetAttribute("DS_PlacedGlass", isGlass)
	local garnishes = parseCsv(worldModel:GetAttribute("DS_GarnishesCsv"))
	if isDrink then
		GlassPresentation.applyFinalPresentation(
			worldModel,
			worldModel:GetAttribute("DS_FillStage") or 1,
			drinkColor,
			garnishes
		)
		-- Watery drinks keep their see-through look when placed
		local recipeName = worldModel:GetAttribute("DS_RecipeName")
		if recipeName == "Water" then
			GlassPresentation.setLiquidTransparency(worldModel, 0.5)
		elseif recipeName == "Solaire's Spit" then
			GlassPresentation.setLiquidTransparency(worldModel, 0.3)
		end
	else
		GlassPresentation.applyFillState(
			worldModel,
			worldModel:GetAttribute("DS_FillStage") or 0,
			drinkColor
		)
	end

	-- Remove the tool from player
	drinkTool:Destroy()

	return true, if isDrink then "PlacedDrink" else "PlacedGlass", worldModel
end

return PlacementManager
