-- ClientStateController: handles consume requests + local drink effects

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local Config = DrinkSystem:WaitForChild("Config")
local SharedModules = DrinkSystem:WaitForChild("SharedModules")

local Settings = require(Config:WaitForChild("Settings"))
local Network = require(SharedModules:WaitForChild("Network"))
local Packets = Network.Packets

local effectsFolder = script.Parent.Parent:WaitForChild("Effects")
local DrinkEffectsClient = require(effectsFolder:WaitForChild("DrinkEffectsClient"))

local ConsumeDrink = Packets.ConsumeDrink
local PlaceDrink = Packets.PlaceDrink
local SetBackpackLocked = Packets.SetBackpackLocked

local effects = DrinkEffectsClient.new(player, Settings.DrunknessMax or 100)
effects:Start()

local DRINK_ANIMATION_ID = 137780885800100
local DRINK_SOUND_ID = 130281744609769

local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local lastDrinkAt = 0
local currentCharacterConn: RBXScriptConnection? = nil
local currentDrinkTrack: AnimationTrack? = nil
local DEBUG_CONSUME = false
local backpackLocked = false
local drinkAnimLocked = false  -- true while drink animation is playing
local ragdollLocked = false    -- true while player is fully knocked out

-- Applies the actual CoreGui state based on all three lock sources.
-- backpackLocked = server-driven (shaker phase etc.)
-- drinkAnimLocked = client-driven (sip animation)
-- ragdollLocked   = client-driven (full knockout ragdoll)
local function applyBackpackLock()
	local shouldLock = backpackLocked or drinkAnimLocked or ragdollLocked
	for _ = 1, 5 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, not shouldLock)
		end)
		if ok then return end
		task.wait()
	end
end

local function setBackpackLocked(locked: boolean)
	backpackLocked = locked
	applyBackpackLock()
end

local function getAnimator(): Animator?
	local char = player.Character
	if not char then return nil end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

local function playDrinkAnimationAndSound()
	local animator = getAnimator()
	if animator then
		if currentDrinkTrack then
			currentDrinkTrack:Stop(0.05)
			currentDrinkTrack = nil
		end

		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. tostring(DRINK_ANIMATION_ID)
		local track = animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
		track:Play()
		currentDrinkTrack = track
	end

	local char = player.Character
	local parentPart = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head"))
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. tostring(DRINK_SOUND_ID)
	sound.Volume = 1
	sound.PlayOnRemove = false
	sound.Parent = parentPart or SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

local function getRootTarget(target: Instance?): Instance?
	if not target then
		return nil
	end

	return target:FindFirstAncestorOfClass("Model")
		or target:FindFirstAncestorOfClass("Tool")
		or target
end

local function isBottleTarget(target: Instance?): boolean
	if not target then
		return false
	end

	if target:GetAttribute("DS_Drinks") == true then
		return true
	end
	if CollectionService:HasTag(target, "DS__Bottle") or CollectionService:HasTag(target, "DS_Bottle") then
		return true
	end

	for _, descendant in ipairs(target:GetDescendants()) do
		if descendant:GetAttribute("DS_Drinks") == true then
			return true
		end
	end

	return false
end

local function raycastFromCursor(char: Model): RaycastResult?
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- Exclude player character AND any placement ghost so the raycast hits the actual surface
	local excluded = { char }
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj.Name == "DS_PlacementGhost" then
			table.insert(excluded, obj)
		end
	end
	params.FilterDescendantsInstances = excluded
	return workspace:Raycast(ray.Origin, ray.Direction * 200, params)
end

local function isPointerTargetingBottle(): boolean
	local char = player.Character
	if not char then return false end
	local result = raycastFromCursor(char)
	if not result then return false end
	return isBottleTarget(getRootTarget(result.Instance))
end

local function isPointerTargetingGarnish(): boolean
	local char = player.Character
	if not char then return false end
	local result = raycastFromCursor(char)
	if not result or not result.Instance then return false end
	local root = getRootTarget(result.Instance)
	if not root then return false end
	if type(root:GetAttribute("DS_Garnish")) == "string" then return true end
	for _, desc in ipairs(root:GetDescendants()) do
		if type(desc:GetAttribute("DS_Garnish")) == "string" then return true end
	end
	return false
end

-- Returns true when cursor is on a valid placement surface (DS_Surface or DS_Table).
-- Used to intercept clicks on tables so a completed drink is placed, not consumed.
-- Raycasts from the cursor and returns the hit surface part + world position if
-- the click lands on a valid placement surface (DS_Surface / DS_Table ancestry).
-- Also validates the surface normal is facing up so walls don't count.
local function getPlacementTarget(): (BasePart?, Vector3?)
	local char = player.Character
	if not char then return nil, nil end
	local result = raycastFromCursor(char)
	if not result or not result.Instance then return nil, nil end

	local hit = result.Instance
	if not hit:IsA("BasePart") then return nil, nil end

	-- Reject walls / ceilings — must be an upward-facing surface
	if result.Normal:Dot(Vector3.new(0, 1, 0)) < 0.7 then return nil, nil end

	-- Direct DS_Surface tag/attribute on the hit part
	if hit:GetAttribute("DS_Surface") == true
		or CollectionService:HasTag(hit, "DS_Surface")
		or CollectionService:HasTag(hit, "DS__Surface") then
		return hit, result.Position
	end

	-- DS_Table on the part itself or any ancestor model
	if hit:GetAttribute("DS_Table") == true or CollectionService:HasTag(hit, "DS_Table") then
		return hit, result.Position
	end
	local ancestor = hit.Parent
	while ancestor and ancestor ~= workspace do
		if ancestor:GetAttribute("DS_Table") == true or CollectionService:HasTag(ancestor, "DS_Table") then
			return hit, result.Position
		end
		ancestor = ancestor.Parent
	end

	return nil, nil
end

local function tryConsume(tool: Tool)
	if drinkAnimLocked then return end
	if ragdollLocked then return end

	-- On mobile, cursor-based checks are unreliable (GetMouseLocation is stale after touch).
	-- Placement is handled by the TouchTap confirm flow — skip it here entirely.
	if not IS_MOBILE then
		if isPointerTargetingBottle() then return end
		if isPointerTargetingGarnish() then return end

		-- Completed drink: if the click lands on a valid surface → place it, don't sip
		if tool:GetAttribute("DS_Drink") == true then
			local surface, hitPos = getPlacementTarget()
			if surface then
				if DEBUG_CONSUME then
					print("[DrinkSystem][ConsumeClient] Placing drink on surface:", surface.Name, hitPos)
				end
				PlaceDrink.send({ Tool = tool, Position = hitPos })
				return
			end
		end
	end

	local now = os.clock()
	local cooldown = Settings.DrinkConsumeCooldown or Settings.ActionCooldown or 0.3
	if now - lastDrinkAt < cooldown then
		if DEBUG_CONSUME then
			print("[DrinkSystem][ConsumeClient] Blocked by cooldown")
		end
		return
	end
	lastDrinkAt = now

	if tool:GetAttribute("DS_Drink") ~= true and tool:GetAttribute("DS_DrinkTool") ~= true then
		if DEBUG_CONSUME then
			print(
				"[DrinkSystem][ConsumeClient] Not drinkable tool:",
				tool.Name,
				"DS_Drink=", tool:GetAttribute("DS_Drink"),
				"DS_DrinkTool=", tool:GetAttribute("DS_DrinkTool")
			)
		end
		return
	end

	if DEBUG_CONSUME then
		print(
			"[DrinkSystem][ConsumeClient] Sending consume:",
			tool.Name,
			"DrinkName=", tool:GetAttribute("DS_DrinkName"),
			"Strongness=", tool:GetAttribute("DS_Strongness"),
			"SipsRemaining=", tool:GetAttribute("DS_SipsRemaining")
		)
	end
	playDrinkAnimationAndSound()
	ConsumeDrink.send({ Tool = tool })

	-- Lock hotbar for the duration of the sip animation so the player
	-- can't swap tools mid-drink or spam-consume back-to-back.
	task.spawn(function()
		drinkAnimLocked = true
		applyBackpackLock()
		-- Wait for animation to finish; fallback 1.8s if track is unavailable
		local track = currentDrinkTrack
		if track then
			track.Stopped:Wait()
		else
			task.wait(1.8)
		end
		drinkAnimLocked = false
		applyBackpackLock()  -- re-evaluate; server lock (backpackLocked) stays untouched
	end)
end

local function getEquippedPlaceableTool(): Tool?
	local char = player.Character
	if not char then return nil end
	for _, inst in ipairs(char:GetChildren()) do
		if inst:IsA("Tool") and (
			inst:GetAttribute("DS_Drink") == true
			or inst:GetAttribute("DS_DrinkTool") == true
			or inst:GetAttribute("DS_GlassTool") == true
		) then
			return inst
		end
	end
	return nil
end

-- Watch DrunkCollapsed BoolValue (set by server DrinkEffectsService).
-- When true: lock hotbar + unequip tools so ragdolled player can't interact.
local function onCollapsedChanged(isCollapsed: boolean)
	ragdollLocked = isCollapsed
	applyBackpackLock()
	if isCollapsed then
		local char = player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:UnequipTools()
		end
	end
end

local function watchCollapsedValue(val: BoolValue)
	val.Changed:Connect(onCollapsedChanged)
	onCollapsedChanged(val.Value)
end

local existingCollapsed = player:FindFirstChild("DrunkCollapsed")
if existingCollapsed and existingCollapsed:IsA("BoolValue") then
	watchCollapsedValue(existingCollapsed)
else
	player.ChildAdded:Connect(function(child)
		if child.Name == "DrunkCollapsed" and child:IsA("BoolValue") then
			watchCollapsedValue(child)
		end
	end)
end

SetBackpackLocked.listen(function(payload)
	setBackpackLocked(payload.Locked == true)
end)

local function getPlaceKey(): Enum.KeyCode
	if typeof(Settings.PlaceKey) == "string" then
		local key = Enum.KeyCode[Settings.PlaceKey]
		if key then
			return key
		end
	end
	return Enum.KeyCode.G
end

local function hookTool(tool: Tool)
	if tool:GetAttribute("DS_ConsumeHooked") == true then
		return
	end
	tool:SetAttribute("DS_ConsumeHooked", true)
	if DEBUG_CONSUME then
		print("[DrinkSystem][ConsumeClient] Hooked tool:", tool.Name)
	end
	tool.Activated:Connect(function()
		tryConsume(tool)
	end)
end

---------------------------------------------------------------------
-- Placement preview — ghost clone follows cursor (PC) or projects
-- forward (mobile). Powered by PlacementPreviewClient module.
---------------------------------------------------------------------
local placementFolder = script.Parent.Parent:WaitForChild("Placement")
local PlacementPreviewClient = require(placementFolder:WaitForChild("PlacementPreviewClient"))

local function isSurfacePart(part: BasePart): boolean
	if part:GetAttribute("DS_Surface") == true then return true end
	if CollectionService:HasTag(part, "DS_Surface") or CollectionService:HasTag(part, "DS__Surface") then return true end
	if part:GetAttribute("DS_Table") == true or CollectionService:HasTag(part, "DS_Table") then return true end
	local ancestor = part.Parent
	while ancestor and ancestor ~= workspace do
		if ancestor:GetAttribute("DS_Table") == true or CollectionService:HasTag(ancestor, "DS_Table") then return true end
		ancestor = ancestor.Parent
	end
	return false
end

local function getTopSurfacePart(part: BasePart): BasePart
	local best, bestTopY = part, part.Position.Y + part.Size.Y * 0.5
	local model = part.Parent
	if model and model:IsA("Model") then
		for _, child in ipairs(model:GetDescendants()) do
			if child:IsA("BasePart") then
				local topY = child.Position.Y + child.Size.Y * 0.5
				if topY > bestTopY then bestTopY = topY; best = child end
			end
		end
	end
	return best
end

local function findNearestSurface(p: Player): BasePart?
	local char = p.Character
	if not char then return nil end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end
	local maxDist = Settings.MaxInteractDistance or 12
	local nearest, nearestDist = nil, maxDist
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") then
			local candidate: BasePart?
			if obj:GetAttribute("DS_Surface") == true
				or CollectionService:HasTag(obj, "DS_Surface")
				or CollectionService:HasTag(obj, "DS__Surface") then
				candidate = obj
			elseif obj:GetAttribute("DS_Table") == true or CollectionService:HasTag(obj, "DS_Table") then
				candidate = getTopSurfacePart(obj)
			else
				-- check ancestor models for DS_Table
				local anc = obj.Parent
				while anc and anc ~= workspace do
					if anc:GetAttribute("DS_Table") == true or CollectionService:HasTag(anc, "DS_Table") then
						candidate = getTopSurfacePart(obj)
						break
					end
					anc = anc.Parent
				end
			end
			if candidate then
				local localPoint = candidate.CFrame:PointToObjectSpace(root.Position)
				local half = candidate.Size * 0.5
				local clamped = Vector3.new(
					math.clamp(localPoint.X, -half.X, half.X),
					math.clamp(localPoint.Y, -half.Y, half.Y),
					math.clamp(localPoint.Z, -half.Z, half.Z)
				)
				local dist = (candidate.CFrame:PointToWorldSpace(clamped) - root.Position).Magnitude
				if dist <= maxDist and dist < nearestDist then
					nearest = candidate
					nearestDist = dist
				end
			end
		end
	end
	return nearest
end

local placementPreview = PlacementPreviewClient.new({
	player             = player,
	isPlaceable        = function(tool: Tool)
		-- Only completed drinks show the ghost preview.
		-- Empty/in-progress glasses are excluded.
		return tool:GetAttribute("DS_Drink") == true
	end,
	isSurface          = isSurfacePart,
	findNearestSurface = findNearestSurface,
	activationRange    = Settings.MaxInteractDistance or 12,
})
placementPreview:Start()

-- Mobile: tap surface to preview, tap confirm button to place.
if IS_MOBILE then
	-- ── Confirm button UI ────────────────────────────────────────────
	local confirmGui = Instance.new("ScreenGui")
	confirmGui.Name = "DS_PlaceConfirm"
	confirmGui.ResetOnSpawn = false
	confirmGui.IgnoreGuiInset = true
	confirmGui.DisplayOrder = 60
	confirmGui.Parent = player:WaitForChild("PlayerGui")

	local confirmBtn = Instance.new("TextButton")
	confirmBtn.Size = UDim2.new(0, 110, 0, 44)
	confirmBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	confirmBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	confirmBtn.BackgroundTransparency = 0.15
	confirmBtn.BorderSizePixel = 0
	confirmBtn.Text = "Place"
	confirmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	confirmBtn.TextSize = 16
	confirmBtn.Font = Enum.Font.GothamBold
	confirmBtn.Visible = false
	confirmBtn.Parent = confirmGui

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 10)
	btnCorner.Parent = confirmBtn

	-- State
	local pendingPosition: Vector3? = nil
	local pendingTool: Tool? = nil

	local function hideConfirm()
		confirmBtn.Visible = false
		pendingPosition = nil
		pendingTool = nil
	end

	local function getEquippedDrink(): Tool?
		local char = player.Character
		if not char then return nil end
		for _, inst in ipairs(char:GetChildren()) do
			if inst:IsA("Tool") and inst:GetAttribute("DS_Drink") == true then
				return inst
			end
		end
		return nil
	end

	local function isSurfaceHit(hit: BasePart): boolean
		if hit:GetAttribute("DS_Surface") == true or CollectionService:HasTag(hit, "DS_Surface") then return true end
		if hit:GetAttribute("DS_Table") == true or CollectionService:HasTag(hit, "DS_Table") then return true end
		local anc = hit.Parent
		while anc and anc ~= workspace do
			if anc:GetAttribute("DS_Table") == true or CollectionService:HasTag(anc, "DS_Table") then return true end
			anc = anc.Parent
		end
		return false
	end

	-- Confirm button → place
	confirmBtn.Activated:Connect(function()
		if pendingPosition and pendingTool then
			PlaceDrink.send({ Tool = pendingTool, Position = pendingPosition })
		end
		hideConfirm()
	end)

	-- First tap: preview position, show confirm button
	UserInputService.TouchTap:Connect(function(touchPositions)
		-- If confirm button is visible and tap isn't on it, cancel
		if confirmBtn.Visible then
			hideConfirm()
			return
		end

		local drinkTool = getEquippedDrink()
		if not drinkTool then return end

		local camera = workspace.CurrentCamera
		if not camera or not touchPositions[1] then return end
		local tapPos = touchPositions[1]
		local ray = camera:ViewportPointToRay(tapPos.X, tapPos.Y)

		local char = player.Character
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local excluded = { char }
		for _, obj in ipairs(workspace:GetChildren()) do
			if obj.Name == "DS_PlacementGhost" then table.insert(excluded, obj) end
		end
		params.FilterDescendantsInstances = excluded

		local result = workspace:Raycast(ray.Origin, ray.Direction * 200, params)
		if not result or not result.Instance then return end
		if not result.Instance:IsA("BasePart") then return end
		if result.Normal:Dot(Vector3.new(0, 1, 0)) < 0.7 then return end
		if not isSurfaceHit(result.Instance) then return end

		-- Store position and show confirm button near the tap
		pendingPosition = result.Position
		pendingTool = drinkTool
		confirmBtn.Position = UDim2.new(0, tapPos.X, 0, tapPos.Y - 60)
		confirmBtn.Visible = true
	end)

	-- Hide confirm if drink is unequipped
	player.CharacterAdded:Connect(hideConfirm)
	player.Character and player.Character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("DS_Drink") == true then
			hideConfirm()
		end
	end)
end

local function hookExistingTools()
	local char = player.Character
	if not char then return end
	for _, inst in ipairs(char:GetChildren()) do
		if inst:IsA("Tool") then
			hookTool(inst)
		end
	end
end

local function bindCharacter(char: Model)
	if currentDrinkTrack then
		currentDrinkTrack:Stop(0.05)
		currentDrinkTrack = nil
	end

	if currentCharacterConn then
		currentCharacterConn:Disconnect()
		currentCharacterConn = nil
	end

	currentCharacterConn = char.ChildAdded:Connect(function(inst)
		if inst:IsA("Tool") then
			hookTool(inst)
		end
	end)

	for _, inst in ipairs(char:GetChildren()) do
		if inst:IsA("Tool") then
			hookTool(inst)
		end
	end
end

player.CharacterAdded:Connect(function(char)
	bindCharacter(char)
	if backpackLocked then
		task.defer(function()
			setBackpackLocked(true)
		end)
	end
end)

if player.Character then
	bindCharacter(player.Character)
else
	hookExistingTools()
end
