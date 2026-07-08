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
local DRINK_SOUND_ID = 82098479361178

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

	-- Drink SOUND is played server-side (DrinkEffectsService.playCharacterSound)
	-- so nearby players hear it spatially — only the animation is local.
end

-- Shared with HoverInteractionController so drinking Water from a world
-- source plays the same animation as sipping a held drink.
_G.DS_PlayDrinkAnim = playDrinkAnimationAndSound

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

-- True when the cursor is over any world interactable owned by the hover
-- controller (glass, placed drink, shaker, water/ingredient source). Clicking
-- those must never count as a sip of the held drink.
local function isPointerTargetingWorldItem(): boolean
	local char = player.Character
	if not char then return false end
	local result = raycastFromCursor(char)
	if not result or not result.Instance then return false end
	local root = getRootTarget(result.Instance)
	if not root then return false end

	local function matches(inst: Instance): boolean
		local glass = inst:GetAttribute("DS_Glass")
		if glass == true or type(glass) == "string" then return true end
		if inst:GetAttribute("DS_Drink") == true then return true end
		if inst:GetAttribute("DS_Shaker") == true then return true end
		if inst:GetAttribute("DS_Sink") == true then return true end
		if type(inst:GetAttribute("DS_IngredientName")) == "string" then return true end
		return false
	end

	if matches(root) then return true end
	for _, desc in ipairs(root:GetDescendants()) do
		if matches(desc) then return true end
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

local function tryConsume(tool: Tool, fromMobileTap: boolean?)
	if drinkAnimLocked then return end
	if ragdollLocked then return end

	-- On mobile, Activated fires before TouchTap so the flag approach is unreliable.
	-- Block Activated for drink tools on mobile — the TouchTap handler owns place+drink
	-- and calls tryConsume with fromMobileTap=true to get past this gate.
	if IS_MOBILE and not fromMobileTap and tool:GetAttribute("DS_Drink") == true then return end

	if not IS_MOBILE then
		if isPointerTargetingBottle() then return end
		if isPointerTargetingGarnish() then return end
		if isPointerTargetingWorldItem() then return end

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

---------------------------------------------------------------------
-- Drink outcome toast — "Blue Screen — Perfect! (92)" when a drink
-- finalizes. Server has always sent DrinkOutcome; nobody displayed it.
---------------------------------------------------------------------
local outcomeGui = Instance.new("ScreenGui")
outcomeGui.Name = "DS_DrinkOutcome"
outcomeGui.ResetOnSpawn = false
outcomeGui.DisplayOrder = 56
outcomeGui.Parent = player:WaitForChild("PlayerGui")

local outcomeLabel = Instance.new("TextLabel")
outcomeLabel.AnchorPoint = Vector2.new(0.5, 0)
outcomeLabel.Position = UDim2.new(0.5, 0, 0.16, 0)
outcomeLabel.AutomaticSize = Enum.AutomaticSize.XY
outcomeLabel.BackgroundTransparency = 1
outcomeLabel.Font = Enum.Font.MontserratBold
outcomeLabel.Text = ""
outcomeLabel.TextSize = 24
outcomeLabel.Visible = false
outcomeLabel.Parent = outcomeGui

local outcomeStroke = Instance.new("UIStroke")
outcomeStroke.Color = Color3.fromRGB(0, 0, 0)
outcomeStroke.Thickness = 1.5
outcomeStroke.Parent = outcomeLabel

local OUTCOME_COLORS = {
	Perfect      = Color3.fromRGB(120, 230, 120),
	Good         = Color3.fromRGB(190, 230, 110),
	Weak         = Color3.fromRGB(235, 190, 90),
	Experimental = Color3.fromRGB(200, 200, 200),
	Ruined       = Color3.fromRGB(235, 90, 80),
}

local function playOutcomeSound(outcome: string)
	local isHigh = outcome == "Perfect" or outcome == "Good"
	local soundId = isHigh and Settings.OutcomeHighSoundId or Settings.OutcomeLowSoundId
	if not soundId then return end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. tostring(soundId)
	sound.Volume = Settings.OutcomeSoundVolume or 0.5
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function() sound:Destroy() end)
end

local outcomeToken = 0
Packets.DrinkOutcome.listen(function(payload)
	outcomeToken += 1
	local token = outcomeToken
	local outcome = payload.Outcome or ""
	playOutcomeSound(outcome)
	outcomeLabel.Text = string.format("%s — %s! (%d)", payload.DrinkName or "Drink", outcome, payload.Score or 0)
	outcomeLabel.TextColor3 = OUTCOME_COLORS[outcome] or Color3.fromRGB(255, 255, 255)
	outcomeLabel.TextTransparency = 0
	outcomeStroke.Transparency = 0
	outcomeLabel.Visible = true
	task.delay(2.2, function()
		if outcomeToken ~= token then return end
		local TweenService = game:GetService("TweenService")
		local info = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(outcomeLabel, info, { TextTransparency = 1 }):Play()
		TweenService:Create(outcomeStroke, info, { Transparency = 1 }):Play()
		task.delay(0.4, function()
			if outcomeToken == token then
				outcomeLabel.Visible = false
			end
		end)
	end)
end)

Packets.SpecialDrinkEffect.listen(function(payload)
	if payload.Effect == "CameraSpin" then
		effects:StartCameraSpin(payload.Duration or 10)
	end
end)

-- Respawn: clear one-shot effects and stuck locks immediately. Drunkness
-- visuals/bar are NOT snapped — they slide down as the server resets to 0.
player.CharacterAdded:Connect(function()
	effects:OnRespawn()
	drinkAnimLocked = false
	currentDrinkTrack = nil
	applyBackpackLock()
end)

---------------------------------------------------------------------
-- "Shaker required" popup — shown when trying to mix without a shaker.
-- Sits above the hotbar, out of the way.
---------------------------------------------------------------------
local shakerNoticeGui = Instance.new("ScreenGui")
shakerNoticeGui.Name = "DS_ShakerNotice"
shakerNoticeGui.ResetOnSpawn = false
shakerNoticeGui.DisplayOrder = 55
shakerNoticeGui.Parent = player:WaitForChild("PlayerGui")

local shakerNoticeLabel = Instance.new("TextLabel")
shakerNoticeLabel.AnchorPoint = Vector2.new(0.5, 1)
shakerNoticeLabel.Position = UDim2.new(0.5, 0, 1, -95)  -- just above the hotbar
shakerNoticeLabel.AutomaticSize = Enum.AutomaticSize.XY
shakerNoticeLabel.BackgroundTransparency = 1
shakerNoticeLabel.Font = Enum.Font.Montserrat
shakerNoticeLabel.Text = "Shaker required"
shakerNoticeLabel.TextSize = 22
shakerNoticeLabel.TextColor3 = Color3.fromRGB(255, 60, 60)
shakerNoticeLabel.Visible = false
shakerNoticeLabel.Parent = shakerNoticeGui

local shakerNoticeStroke = Instance.new("UIStroke")
shakerNoticeStroke.Color = Color3.fromRGB(0, 0, 0)
shakerNoticeStroke.Thickness = 1.5
shakerNoticeStroke.Parent = shakerNoticeLabel

local shakerNoticeToken = 0
local function showShakerNotice()
	shakerNoticeToken += 1
	local token = shakerNoticeToken
	shakerNoticeLabel.TextTransparency = 0
	shakerNoticeStroke.Transparency = 0
	shakerNoticeLabel.Visible = true
	task.delay(1.4, function()
		if shakerNoticeToken ~= token then return end
		local TweenService = game:GetService("TweenService")
		local info = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(shakerNoticeLabel, info, { TextTransparency = 1 }):Play()
		TweenService:Create(shakerNoticeStroke, info, { Transparency = 1 }):Play()
		task.delay(0.35, function()
			if shakerNoticeToken == token then
				shakerNoticeLabel.Visible = false
			end
		end)
	end)
end

Packets.MissingShakerNotify.listen(function()
	showShakerNotice()
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

-- Mobile: hold drink near surface → surface glows. Tap surface → ghost preview + Place/Cancel.
if IS_MOBILE then
	local confirmGui = Instance.new("ScreenGui")
	confirmGui.Name = "DS_PlaceConfirm"
	confirmGui.ResetOnSpawn = false
	confirmGui.IgnoreGuiInset = true
	confirmGui.DisplayOrder = 60
	confirmGui.Parent = player:WaitForChild("PlayerGui")

	-- Row frame to hold Place + Cancel side by side
	local btnFrame = Instance.new("Frame")
	btnFrame.Size = UDim2.new(0, 260, 0, 52)
	btnFrame.AnchorPoint = Vector2.new(0.5, 1)
	btnFrame.BackgroundTransparency = 1
	btnFrame.Visible = false
	btnFrame.Parent = confirmGui
	local btnLayout = Instance.new("UIListLayout")
	btnLayout.FillDirection = Enum.FillDirection.Horizontal
	btnLayout.Padding = UDim.new(0, 10)
	btnLayout.Parent = btnFrame

	local function makeBtn(text, bg)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 125, 1, 0)
		btn.BackgroundColor3 = bg
		btn.BackgroundTransparency = 0.1
		btn.BorderSizePixel = 0
		btn.Text = text
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.TextSize = 16
		btn.Font = Enum.Font.GothamBold
		btn.Parent = btnFrame
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 12)
		c.Parent = btn
		return btn
	end

	local placeBtn  = makeBtn("Place",  Color3.fromRGB(30, 120, 60))
	local cancelBtn = makeBtn("Cancel", Color3.fromRGB(120, 30, 30))

	local pendingPosition: Vector3? = nil
	local pendingTool: Tool? = nil

	local function hideConfirm()
		btnFrame.Visible = false
		pendingPosition = nil
		pendingTool = nil
		placementPreview:hideGhost()
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

	placeBtn.Activated:Connect(function()
		if pendingPosition and pendingTool then
			PlaceDrink.send({ Tool = pendingTool, Position = pendingPosition })
		end
		hideConfirm()
	end)

	cancelBtn.Activated:Connect(function()
		hideConfirm()
	end)

	UserInputService.TouchTap:Connect(function(touchPositions)
		if not touchPositions[1] then return end

		-- Any tap while buttons are showing: dismiss (Place/Cancel handle their own Activated)
		if btnFrame.Visible then
			hideConfirm()
			return
		end

		local drinkTool = getEquippedDrink()
		if not drinkTool then return end

		local camera = workspace.CurrentCamera
		if not camera then return end
		local tapPos = touchPositions[1]
		-- TouchTap positions are in GUI space (top inset subtracted);
		-- ScreenPointToRay accounts for the inset, ViewportPointToRay does not.
		local ray = camera:ScreenPointToRay(tapPos.X, tapPos.Y)

		local char = player.Character
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local excluded = { char }
		for _, obj in ipairs(workspace:GetChildren()) do
			if obj.Name == "DS_PlacementGhost" then table.insert(excluded, obj) end
		end
		params.FilterDescendantsInstances = excluded

		local result = workspace:Raycast(ray.Origin, ray.Direction * 200, params)

		-- Only proceed if the ray directly hit a tagged surface part.
		local surfacePart = result
			and result.Instance
			and result.Instance:IsA("BasePart")
			and isSurfaceHit(result.Instance)
			and result.Instance or nil

		if surfacePart then
			local topY = surfacePart.Position.Y + surfacePart.Size.Y * 0.5
			local hitPos = result.Position

			-- If the ray hit a side face (normal mostly horizontal), the hit XZ is on
			-- the front wall of the counter. Continue the ray to where it crosses the
			-- tabletop plane (Y = topY) — that's where the player was actually aiming.
			-- Falls back to a fixed inward push if the ray runs parallel to the plane.
			local normal = result.Normal
			if normal:Dot(Vector3.new(0, 1, 0)) < 0.7 then
				local t = ray.Direction.Y ~= 0 and ((topY - ray.Origin.Y) / ray.Direction.Y) or nil
				if t and t > 0 then
					hitPos = ray.Origin + ray.Direction * t
				else
					local horizontalN = Vector3.new(normal.X, 0, normal.Z)
					if horizontalN.Magnitude > 0.01 then
						hitPos = hitPos - horizontalN.Unit * 1.5
					end
				end
			end

			-- Snap Y to top of the part, clamp inward so drink never sits on the very edge.
			local local_ = surfacePart.CFrame:PointToObjectSpace(
				Vector3.new(hitPos.X, topY, hitPos.Z)
			)
			local inset = 0.8
			local hx = math.max(0, surfacePart.Size.X * 0.5 - inset)
			local hz = math.max(0, surfacePart.Size.Z * 0.5 - inset)
			local clamped = surfacePart.CFrame:PointToWorldSpace(
				Vector3.new(math.clamp(local_.X, -hx, hx), 0, math.clamp(local_.Z, -hz, hz))
			)
			local placePos = Vector3.new(clamped.X, topY, clamped.Z)
			pendingPosition = placePos
			pendingTool = drinkTool
			placementPreview:showAtPosition(placePos, surfacePart)
			btnFrame.Position = UDim2.new(0, tapPos.X, 0, tapPos.Y - 16)
			btnFrame.Visible = true
		else
			-- Tap on the sink: let the hover controller handle the dump —
			-- must NOT count as a sip.
			local hitInst = result and result.Instance
			while hitInst and hitInst ~= workspace do
				if hitInst:GetAttribute("DS_Sink") == true then
					return
				end
				hitInst = hitInst.Parent
			end
			-- Ray missed a surface — treat as drink tap.
			tryConsume(drinkTool, true)
		end
	end)

	-- Hide when drink is unequipped
	local function watchChar(char)
		char.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") and child:GetAttribute("DS_Drink") == true then
				hideConfirm()
			end
		end)
	end
	player.CharacterAdded:Connect(hideConfirm)
	player.CharacterAdded:Connect(watchChar)
	if player.Character then watchChar(player.Character) end
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
