local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local DrinkSystem  = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystem:WaitForChild("Config")
local Settings     = require(ConfigFolder:WaitForChild("Settings"))

local VISUAL_MAX      = math.max(Settings.DrunknessVisualMax or Settings.DrunknessMax or 100, 1)
local RISE_PER_SECOND = Settings.DrunknessVisualRisePerSecond or 4.5
local FALL_PER_SECOND = Settings.DrunknessVisualFallPerSecond or 1.5

-- Wire to the Studio UI
local playerGui    = player:WaitForChild("PlayerGui")
local screenGui    = playerGui:WaitForChild("DrunknessLevel")
local canvasGroup  = screenGui:WaitForChild("CanvasGroup")
local barContainer = canvasGroup:WaitForChild("Bar")
local fillBar      = barContainer:WaitForChild("Bar") :: Frame

local function getDrunknessValue(): NumberValue
	return player:WaitForChild("Drunkness") :: NumberValue
end

local function updateBar(drunkness: number)
	local normalized = math.clamp(drunkness / VISUAL_MAX, 0, 1)
	fillBar.Size = UDim2.new(normalized, 0, 1, 0)
end

-- Anchor left so the bar grows rightward
fillBar.AnchorPoint = Vector2.new(0, 0)
fillBar.Position    = UDim2.new(0, 0, 0, 0)

local drunknessValue     = getDrunknessValue()
local targetDrunkness    = drunknessValue.Value
local displayedDrunkness = drunknessValue.Value

updateBar(drunknessValue.Value)

drunknessValue:GetPropertyChangedSignal("Value"):Connect(function()
	targetDrunkness = drunknessValue.Value
end)

RunService.RenderStepped:Connect(function(dt)
	if displayedDrunkness < targetDrunkness then
		displayedDrunkness = math.min(targetDrunkness, displayedDrunkness + RISE_PER_SECOND * dt)
	else
		displayedDrunkness = math.max(targetDrunkness, displayedDrunkness - FALL_PER_SECOND * dt)
	end
	updateBar(displayedDrunkness)
end)
