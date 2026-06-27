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

-- Canonical placement surfaces are tracked with the CollectionService tag "DS_Surface".
-- Legacy surfaces only marked via the DS_Surface attribute or the old "DS__Surface" tag
-- get migrated onto the canonical tag once (on join + at runtime) so every later lookup
-- is a cheap CollectionService:GetTagged() instead of a full workspace:GetDescendants() scan.
local SURFACE_TAG = "DS_Surface"
local LEGACY_SURFACE_TAG = "DS__Surface"

local function migrateSurfaceTag(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	if CollectionService:HasTag(part, SURFACE_TAG) then
		return
	end
	if part:GetAttribute("DS_Surface") == true or CollectionService:HasTag(part, LEGACY_SURFACE_TAG) then
		CollectionService:AddTag(part, SURFACE_TAG)
	end
end

for _, part in ipairs(workspace:GetDescendants()) do
	migrateSurfaceTag(part)
end
workspace.DescendantAdded:Connect(migrateSurfaceTag)

local function findNearestSurface(player: Player): BasePart?
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local maxDist = Settings.MaxInteractDistance or 12
	local nearest, nearestDist = nil, maxDist

	for _, obj in ipairs(CollectionService:GetTagged(SURFACE_TAG)) do
		if obj:IsA("BasePart") then
			local dist = (obj.Position - root.Position).Magnitude
			if dist <= maxDist and dist < nearestDist then
				nearest = obj
				nearestDist = dist
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

function PlacementManager.placeDrinkFromTool(player: Player, drinkTool: Tool)
	if not drinkTool or not drinkTool:IsDescendantOf(player) then
		return false, "ToolNotOwned"
	end

	local isDrink = drinkTool:GetAttribute("DS_Drink") == true
	local isGlass = drinkTool:GetAttribute("DS_GlassTool") == true
	if not isDrink and not isGlass then
		return false, "NotAPlaceableTool"
	end

	local surface = findNearestSurface(player)
	if not surface then
		return false, "NoSurfaceFound"
	end

	local slot = findEmptySlot(surface)

	local drinkName = drinkTool:GetAttribute("DS_DrinkName") or drinkTool.Name
	local drinkColor = drinkTool:GetAttribute("DS_Color") :: Color3?

	local worldModel = createWorldDrinkFromTool(drinkTool, drinkName, drinkColor)
	if slot then
		slot:SetAttribute("Occupied", true)
		bindPlacementSlot(worldModel, slot)
		-- Keep slot placement but force upright orientation.
		local slotPos = slot.WorldPosition
		local halfH = getDrinkHalfHeight(worldModel)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local yaw = 0
		if root then
			yaw = math.atan2(root.CFrame.LookVector.X, root.CFrame.LookVector.Z)
		end
		worldModel:PivotTo(CFrame.new(slotPos.X, slotPos.Y + halfH, slotPos.Z) * CFrame.Angles(0, yaw, 0))
	else
		worldModel:PivotTo(computeTablePlacementCFrame(player, surface, worldModel))
	end
	worldModel.Parent = workspace

	-- Optionally copy some attributes onto the world model
	worldModel:SetAttribute("DS_Drink", isDrink)
	worldModel:SetAttribute("DS_DrinkName", drinkName)
	worldModel:SetAttribute("DS_BaseIngredient", drinkTool:GetAttribute("DS_BaseIngredient"))
	worldModel:SetAttribute("DS_MaxSips", drinkTool:GetAttribute("DS_MaxSips") or drinkTool:GetAttribute("MaxSips"))
	worldModel:SetAttribute("MaxSips", drinkTool:GetAttribute("DS_MaxSips") or drinkTool:GetAttribute("MaxSips"))
	worldModel:SetAttribute("DS_Strongness", drinkTool:GetAttribute("DS_Strongness") or 0)
	worldModel:SetAttribute("DS_Outcome", drinkTool:GetAttribute("DS_Outcome"))
	worldModel:SetAttribute("DS_Score", drinkTool:GetAttribute("DS_Score"))
	worldModel:SetAttribute("DS_FillStage", drinkTool:GetAttribute("DS_FillStage") or 1)
	worldModel:SetAttribute("DS_GarnishesCsv", drinkTool:GetAttribute("DS_GarnishesCsv") or "")
	worldModel:SetAttribute("DS_Color", drinkColor)
	worldModel:SetAttribute("DS_IngredientListCsv", drinkTool:GetAttribute("DS_IngredientListCsv") or "")
	worldModel:SetAttribute("DS_IngredientsText", drinkTool:GetAttribute("DS_IngredientsText") or "")
	worldModel:SetAttribute("DS_Glass", drinkTool:GetAttribute("DS_Glass") or drinkTool:GetAttribute("GlassType") or "Glass")
	worldModel:SetAttribute("DS_PlacedGlass", isGlass)
	local garnishes = parseCsv(worldModel:GetAttribute("DS_GarnishesCsv"))
	if isDrink then
		GlassPresentation.applyFinalPresentation(
			worldModel,
			worldModel:GetAttribute("DS_FillStage") or 1,
			drinkColor,
			garnishes
		)
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
