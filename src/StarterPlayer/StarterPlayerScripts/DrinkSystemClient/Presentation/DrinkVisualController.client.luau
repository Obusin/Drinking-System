-- DrinkVisualController.client.lua
-- Plays local pour presentation and updates the held glass visuals.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local Config = DrinkSystem:WaitForChild("Config")
local SharedModules = DrinkSystem:WaitForChild("SharedModules")

local Network = require(SharedModules:WaitForChild("Network"))
local GlassPresentation = require(SharedModules:WaitForChild("GlassPresentation"))
local IngredientRegistry = require(SharedModules:WaitForChild("IngredientRegistry"))

local Packets = Network.Packets
local StartBottlePour = Packets.StartBottlePour
local StartShakerSequence = Packets.StartShakerSequence

local Settings = require(Config:WaitForChild("Settings"))

if Settings.EnableDrinkVisualController ~= true then
	return
end

local POUR_ANIMATION_ID = Settings.Animations and Settings.Animations.Pour and ("rbxassetid://" .. tostring(Settings.Animations.Pour))
if not POUR_ANIMATION_ID then
	POUR_ANIMATION_ID = "rbxassetid://138176167772150"
end

local POUR_SOUND_ID = "rbxassetid://96961332439928"
local POUR_VOLUME = 1
local POUR_TIME = 0.7
local MAX_INGREDIENTS = Settings.MaxIngredientsPerMix or 4

local currentFillStep = 0
local currentColor = nil
local activeBottleClone = nil

_G.DS_IgnoreModels = _G.DS_IgnoreModels or {}

local function isPartInsideModel(part: BasePart?, model: Model): boolean
	return part ~= nil and part:IsDescendantOf(model)
end

local function removeExternalJoints(clone: Model)
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("Weld") or descendant:IsA("WeldConstraint") then
			local part0 = descendant.Part0
			local part1 = descendant.Part1
			if not isPartInsideModel(part0, clone) or not isPartInsideModel(part1, clone) then
				descendant:Destroy()
			end
		elseif descendant:IsA("Motor6D") then
			local part0 = descendant.Part0
			local part1 = descendant.Part1
			if not isPartInsideModel(part0, clone) or not isPartInsideModel(part1, clone) then
				descendant:Destroy()
			end
		end
	end
end

local function ensureClonePrimaryPart(clone: Model): BasePart?
	if clone.PrimaryPart then
		return clone.PrimaryPart
	end

	local handle = clone:FindFirstChild("Handle", true)
	if handle and handle:IsA("BasePart") then
		clone.PrimaryPart = handle
		return handle
	end

	local fallback = clone:FindFirstChildWhichIsA("BasePart")
	if fallback then
		clone.PrimaryPart = fallback
		return fallback
	end

	return nil
end

local function weldLoosePartsToPrimary(clone: Model, primary: BasePart)
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= primary then
			local alreadyConnected = false

			for _, joint in ipairs(descendant:GetChildren()) do
				if joint:IsA("Weld") or joint:IsA("WeldConstraint") or joint:IsA("Motor6D") then
					local part0 = joint.Part0
					local part1 = joint.Part1
					if isPartInsideModel(part0, clone) and isPartInsideModel(part1, clone) then
						alreadyConnected = true
						break
					end
				end
			end

			if not alreadyConnected then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = primary
				weld.Part1 = descendant
				weld.Parent = primary
			end
		end
	end
end

local function prepareBottleClone(clone: Model)
	removeExternalJoints(clone)

	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part:SetAttribute("DS_Drinks", nil)
			part:SetAttribute("DS_Glass", nil)
			part:SetAttribute("DS_Shaker", nil)
			part:SetAttribute("DS_IngredientName", nil)
		end
	end

	local primary = ensureClonePrimaryPart(clone)
	if primary then
		weldLoosePartsToPrimary(clone, primary)
	end

	return primary
end

local function getCharacter()
	return player.Character or player.CharacterAdded:Wait()
end

local function getLeftHand(char)
	return char:FindFirstChild("LeftHand")
		or char:FindFirstChild("Left Arm")
		or char:FindFirstChild("LeftHandRigAttachment")
end

local function getGlassTool()
	local char = getCharacter()
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("DS_GlassTool") == true then
			return child
		end
	end
	return nil
end

local function blendColor(oldColor, newColor, step)
	if not oldColor or step <= 1 then
		return newColor
	end

	return Color3.new(
		(oldColor.R * (step - 1) + newColor.R) / step,
		(oldColor.G * (step - 1) + newColor.G) / step,
		(oldColor.B * (step - 1) + newColor.B) / step
	)
end

local function createPourParticles(parent: BasePart)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxassetid://2418769692"
	emitter.Rate = 80
	emitter.Speed = NumberRange.new(6, 12)
	emitter.Lifetime = NumberRange.new(0.3, 0.5)
	emitter.Acceleration = Vector3.new(0, -40, 0)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Parent = parent
	return emitter
end

local function attachBottleToHand(clone: Model, hand: BasePart)
	local primary = ensureClonePrimaryPart(clone)
	if not primary then
		return
	end

	for _, joint in ipairs(primary:GetChildren()) do
		if joint:IsA("Weld") or joint:IsA("WeldConstraint") then
			local otherPart = if joint.Part0 == primary then joint.Part1 else joint.Part0
			if otherPart == hand then
				joint:Destroy()
			end
		end
	end

	local offset = CFrame.new(0, -0.45, -0.15) * CFrame.Angles(0, math.rad(-25), math.rad(-90))
	clone:SetPrimaryPartCFrame(hand.CFrame * offset)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = primary
	weld.Part1 = hand
	weld.Parent = primary
end

local function clearActiveBottleClone()
	if not activeBottleClone then
		return
	end

	for i, model in ipairs(_G.DS_IgnoreModels) do
		if model == activeBottleClone then
			table.remove(_G.DS_IgnoreModels, i)
			break
		end
	end

	activeBottleClone:Destroy()
	activeBottleClone = nil
end

local function playPourAnimation(worldBottle: Model?)
	local char = getCharacter()
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = POUR_ANIMATION_ID

	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	track:Play()

	task.spawn(function()
		track.Stopped:Wait()
		animation:Destroy()
	end)

	clearActiveBottleClone()

	if worldBottle and worldBottle:IsA("Model") then
		local clone = worldBottle:Clone()
		clone.Name = "TempPourBottle"
		clone.Parent = char

		table.insert(_G.DS_IgnoreModels, clone)
		local primary = prepareBottleClone(clone)

		local hand = getLeftHand(char)
		if hand and primary then
			attachBottleToHand(clone, hand)
		end

		activeBottleClone = clone

		task.spawn(function()
			track.Stopped:Wait()
			if activeBottleClone == clone then
				clearActiveBottleClone()
			end
		end)
	end

	-- Pour SOUND is played server-side (DrinkEffectsService.playCharacterSound)
	-- so nearby players hear it spatially — only the animation/clone is local.
end

local function animateFill(ingredientName: string)
	local glass = getGlassTool()
	if not glass then
		return
	end

	local ingredientData = IngredientRegistry.get(ingredientName)
	local ingredientColor = ingredientData and ingredientData.Color or Color3.new(1, 1, 1)

	local replicatedStage = glass:GetAttribute("DS_FillStage")
	if typeof(replicatedStage) == "number" then
		currentFillStep = math.max(currentFillStep, replicatedStage)
	end

	if ingredientName == "Water" then
		-- Water fills the glass in one pour — jump straight to full
		currentFillStep = math.max(currentFillStep, 3)
	else
		currentFillStep = math.clamp(currentFillStep + 1, 1, MAX_INGREDIENTS)
	end
	currentColor = blendColor(currentColor, ingredientColor, currentFillStep)

	GlassPresentation.applyFillState(glass, math.min(currentFillStep, 3), currentColor)
end

local function simulatePour(ingredientName: string, bottleModel: Model?)
	local glass = getGlassTool()
	if not glass then
		return
	end

	local particleParent = glass:FindFirstChild("GlassPart", true) or glass:FindFirstChild("Handle", true)
	if not particleParent or not particleParent:IsA("BasePart") then
		return
	end

	playPourAnimation(bottleModel)

	local emitter = createPourParticles(particleParent)
	animateFill(ingredientName)

	task.delay(POUR_TIME, function()
		if emitter then
			emitter.Enabled = false
			task.delay(0.4, function()
				if emitter then
					emitter:Destroy()
				end
			end)
		end
	end)
end

StartBottlePour.listen(function(payload)
	local ingredientName = payload.IngredientName
	local bottleModel = payload.BottleModel
	if typeof(ingredientName) ~= "string" then
		return
	end
	-- Water: never clone a bottle into the hand. With a glass equipped run the
	-- normal pour visuals (fill + particles); without one just play the anim.
	if ingredientName == "Water" then
		if getGlassTool() then
			simulatePour(ingredientName, nil)
		else
			playPourAnimation(nil)
		end
		return
	end
	simulatePour(ingredientName, bottleModel)
end)

StartShakerSequence.listen(function(_payload)
	-- Reserved for future shaker VFX.
end)

player.CharacterAdded:Connect(function()
	currentFillStep = 0
	currentColor = nil
	activeBottleClone = nil
end)
