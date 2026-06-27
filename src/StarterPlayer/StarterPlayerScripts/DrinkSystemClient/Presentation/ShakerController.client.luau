-- StarterPlayerScripts/DrinkSystemClient/ShakerController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local DrinkSystemFolder = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystemFolder:WaitForChild("Config")
local SharedModules = DrinkSystemFolder:WaitForChild("SharedModules")

local Settings = require(ConfigFolder:WaitForChild("Settings"))
local Network = require(SharedModules:WaitForChild("Network"))
local Packets = Network.Packets

local StartShakerSequence = Packets.StartShakerSequence
local ShakerFinished = Packets.ShakerFinished

if Settings.EnableShakerController ~= true then
	return
end

local SHAKER_ANIMATION_ID = 116267838442811
local SHAKER_ANIMATION = nil
do
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(SHAKER_ANIMATION_ID)
	SHAKER_ANIMATION = anim
end

local currentShakerClone: Model? = nil

local function getAnimator()
	local char = player.Character or player.CharacterAdded:Wait()
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = char:WaitForChild("Humanoid")
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return char, humanoid, animator
end

local function getLeftHand(character: Model): BasePart?
	return character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
end

local function cleanupShakerClone()
	if currentShakerClone then
		currentShakerClone:Destroy()
		currentShakerClone = nil
	end
end

local function attachShakerToLeftHand(cloneModel: Model, character: Model)
	local primary = cloneModel.PrimaryPart
	if not primary then
		primary = cloneModel:FindFirstChildWhichIsA("BasePart")
		if primary then
			cloneModel.PrimaryPart = primary
		else
			return
		end
	end

	local leftHand = getLeftHand(character)
	if not leftHand then return end

	for _, p in ipairs(cloneModel:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
		end
	end

	cloneModel:SetPrimaryPartCFrame(leftHand.CFrame)

	local weld = Instance.new("Weld")
	weld.Part0 = leftHand
	weld.Part1 = primary
	weld.C0 = CFrame.new()
	weld.Parent = leftHand
end

StartShakerSequence.listen(function(payload: table)
	print("[ShakerController] StartShakerSequence received", payload and payload.RecipeName or "")
	cleanupShakerClone()

	local char, humanoid, animator = getAnimator()

	local shakerTemplateFolder = DrinkSystemFolder:WaitForChild("ShakerTemplates")
	local shakerToolTemplate = shakerTemplateFolder:FindFirstChildWhichIsA("Tool")
	if not shakerToolTemplate and Settings.ShakerToolName then
		shakerToolTemplate = shakerTemplateFolder:FindFirstChild(Settings.ShakerToolName)
	end

	if not SHAKER_ANIMATION then
		warn("[ShakerController] Missing shaker animation; finishing immediately")
		ShakerFinished.send({})
		return
	end

	if not shakerToolTemplate then
		warn("[ShakerController] Missing ShakerTool template; playing animation only")
		local track = animator:LoadAnimation(SHAKER_ANIMATION)
		track:Play()
		track.Stopped:Connect(function()
			ShakerFinished.send({})
		end)
		return
	end

	local visualModel: Model
	if shakerToolTemplate:IsA("Tool") then
		visualModel = Instance.new("Model")
		visualModel.Name = "Shaker_HandClone"
		for _, child in ipairs(shakerToolTemplate:GetChildren()) do
			if child:IsA("BasePart") or child:IsA("MeshPart") or child:IsA("UnionOperation") then
				local c = child:Clone()
				c.Parent = visualModel
			end
		end
	else
		visualModel = shakerToolTemplate:Clone()
		visualModel.Name = shakerToolTemplate.Name .. "_HandClone"
	end

	visualModel.Parent = char
	currentShakerClone = visualModel
	attachShakerToLeftHand(visualModel, char)

	local track = animator:LoadAnimation(SHAKER_ANIMATION)
	track:Play()

	track.Stopped:Connect(function()
		cleanupShakerClone()
		-- Tell server shaker is done
		ShakerFinished.send({})
	end)
end)
