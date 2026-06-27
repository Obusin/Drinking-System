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

local lastDrinkAt = 0
local currentCharacterConn: RBXScriptConnection? = nil
local currentDrinkTrack: AnimationTrack? = nil
local DEBUG_CONSUME = true
local backpackLocked = false

local function setBackpackLocked(locked: boolean)
	backpackLocked = locked
	local enabled = not locked
	for _ = 1, 5 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, enabled)
		end)
		if ok then
			return
		end
		task.wait()
	end
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

local function isPointerTargetingBottle(): boolean
	local char = player.Character
	if not char then
		return false
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end

	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }

	local result = workspace:Raycast(ray.Origin, ray.Direction * 200, params)
	if not result or not result.Instance then
		return false
	end

	return isBottleTarget(getRootTarget(result.Instance))
end

local function tryConsume(tool: Tool)
	if isPointerTargetingBottle() then
		if DEBUG_CONSUME then
			print("[DrinkSystem][ConsumeClient] Suppressed consume while targeting bottle")
		end
		return
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

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == getPlaceKey() then
		local tool = getEquippedPlaceableTool()
		if tool then
			PlaceDrink.send({ Tool = tool })
		end
	end
end)

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
