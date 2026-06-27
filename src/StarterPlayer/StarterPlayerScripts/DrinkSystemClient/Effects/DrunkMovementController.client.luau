local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local drinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local configFolder = drinkSystem:WaitForChild("Config")
local Settings = require(configFolder:WaitForChild("Settings"))

local currentYawBias = 0
local currentSideBias = 0
local targetYawBias = 0
local targetSideBias = 0
local nextShuffleAt = 0

local function getCharacterParts()
	local character = player.Character
	if not character then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return nil, nil, nil
	end

	return character, humanoid, root
end

local function getNumberValue(name: string): NumberValue?
	local value = player:FindFirstChild(name)
	if value and value:IsA("NumberValue") then
		return value
	end
	return nil
end

local function getBoolValue(name: string): BoolValue?
	local value = player:FindFirstChild(name)
	if value and value:IsA("BoolValue") then
		return value
	end
	return nil
end

local function rotateVectorAroundY(vector: Vector3, radians: number): Vector3
	local cf = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), radians)
	return cf:VectorToWorldSpace(vector)
end

local function randomSigned(scale: number): number
	return ((math.random() * 2) - 1) * scale
end

local function chooseNewBias(alpha: number)
	local maxDegrees = Settings.DrunkControlSkewMaxDegrees or 16
	local maxSideways = Settings.DrunkSidewaysSwayMax or 0.38
	local yawScale = math.rad(maxDegrees) * alpha
	local sideScale = maxSideways * alpha

	if math.random() < (0.35 + (0.35 * alpha)) then
		targetYawBias = randomSigned(yawScale)
	else
		targetYawBias = randomSigned(yawScale * 0.45)
	end

	targetSideBias = randomSigned(sideScale)
	nextShuffleAt = os.clock() + 0.32 + math.random() * (0.9 - (0.38 * alpha))
end

RunService:BindToRenderStep("DS_DrunkMovement", Enum.RenderPriority.Character.Value + 1, function(dt)
	local _, humanoid, root = getCharacterParts()
	if not humanoid or not root then
		return
	end

	local collapsedValue = getBoolValue("DrunkCollapsed")
	if collapsedValue and collapsedValue.Value == true then
		currentYawBias = 0
		currentSideBias = 0
		targetYawBias = 0
		targetSideBias = 0
		return
	end

	local moveAlphaValue = getNumberValue("DrunkMoveAlpha")
	local alpha = moveAlphaValue and moveAlphaValue.Value or 0
	if alpha <= 0.01 then
		currentYawBias = 0
		currentSideBias = 0
		targetYawBias = 0
		targetSideBias = 0
		return
	end

	local moveDirection = humanoid.MoveDirection
	if moveDirection.Magnitude <= 0.05 then
		return
	end

	local now = os.clock()
	if now >= nextShuffleAt then
		chooseNewBias(alpha)
	end

	local lerpSpeed = math.clamp(2.6 + (4.2 * alpha), 0, 1 / math.max(dt, 1 / 240))
	local lerpAlpha = math.clamp(dt * lerpSpeed, 0, 1)
	currentYawBias = currentYawBias + ((targetYawBias - currentYawBias) * lerpAlpha)
	currentSideBias = currentSideBias + ((targetSideBias - currentSideBias) * lerpAlpha)

	local bobSide = math.sin(now * (3 + alpha * 3.4)) * (0.18 + (0.24 * alpha))
	local skewed = rotateVectorAroundY(moveDirection, currentYawBias)
	local desired = skewed + (root.CFrame.RightVector * (currentSideBias + bobSide))

	if desired.Magnitude > 0 then
		humanoid:Move(desired.Unit, false)
	end
end)
