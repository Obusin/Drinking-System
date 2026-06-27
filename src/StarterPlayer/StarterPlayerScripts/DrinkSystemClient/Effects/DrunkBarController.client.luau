local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystem:WaitForChild("Config")
local Settings = require(ConfigFolder:WaitForChild("Settings"))

local BAR_GUI_NAME = "DrunknessDebugUI"
local BAR_FRAME_NAME = "DrunknessFill"
local LABEL_NAME = "DrunknessValue"
local VISUAL_MAX = math.max(Settings.DrunknessVisualMax or Settings.DrunknessMax or 100, 1)
local RISE_PER_SECOND = Settings.DrunknessVisualRisePerSecond or 4.5
local FALL_PER_SECOND = Settings.DrunknessVisualFallPerSecond or 1.5

local function createRounded(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function createStroke(instance: Instance, color: Color3, transparency: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Thickness = 1
	stroke.Parent = instance
end

local function createGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild(BAR_GUI_NAME)
	if existing and existing:IsA("ScreenGui") then
		return existing
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = BAR_GUI_NAME
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(0, 1)
	root.Position = UDim2.new(0, 18, 1, -24)
	root.Size = UDim2.new(0, 240, 0, 70)
	root.BackgroundColor3 = Color3.fromRGB(12, 16, 27)
	root.BackgroundTransparency = 0.2
	root.BorderSizePixel = 0
	root.Parent = screenGui
	createRounded(root, 14)
	createStroke(root, Color3.fromRGB(255, 184, 77), 0.45)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 14, 0, 8)
	title.Size = UDim2.new(1, -28, 0, 18)
	title.Font = Enum.Font.GothamBold
	title.Text = "DRUNKNESS"
	title.TextColor3 = Color3.fromRGB(255, 228, 180)
	title.TextSize = 13
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = root

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = LABEL_NAME
	valueLabel.BackgroundTransparency = 1
	valueLabel.AnchorPoint = Vector2.new(1, 0)
	valueLabel.Position = UDim2.new(1, -14, 0, 8)
	valueLabel.Size = UDim2.new(0, 90, 0, 18)
	valueLabel.Font = Enum.Font.GothamMedium
	valueLabel.Text = "0%"
	valueLabel.TextColor3 = Color3.fromRGB(255, 228, 180)
	valueLabel.TextSize = 12
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Parent = root

	local barBack = Instance.new("Frame")
	barBack.Name = "BarBack"
	barBack.Position = UDim2.new(0, 14, 0, 34)
	barBack.Size = UDim2.new(1, -28, 0, 18)
	barBack.BackgroundColor3 = Color3.fromRGB(35, 42, 59)
	barBack.BorderSizePixel = 0
	barBack.Parent = root
	createRounded(barBack, 9)

	local barFill = Instance.new("Frame")
	barFill.Name = BAR_FRAME_NAME
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(255, 170, 74)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBack
	createRounded(barFill, 9)

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 225, 127)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 152, 85)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 87, 87)),
	})
	gradient.Rotation = 0
	gradient.Parent = barFill

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "Hint"
	subLabel.BackgroundTransparency = 1
	subLabel.Position = UDim2.new(0, 14, 0, 55)
	subLabel.Size = UDim2.new(1, -28, 0, 12)
	subLabel.Font = Enum.Font.Gotham
	subLabel.Text = "Temporary debug meter"
	subLabel.TextColor3 = Color3.fromRGB(149, 159, 182)
	subLabel.TextSize = 10
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.Parent = root

	screenGui.Parent = playerGui
	return screenGui
end

local function getDrunknessValue(): NumberValue
	local drunknessValue = player:FindFirstChild("Drunkness")
	if drunknessValue and drunknessValue:IsA("NumberValue") then
		return drunknessValue
	end

	drunknessValue = player:WaitForChild("Drunkness")
	return drunknessValue :: NumberValue
end

local function getStageValue(): string
	local stageValue = player:FindFirstChild("DrunkStage")
	if stageValue and stageValue:IsA("StringValue") then
		return stageValue.Value
	end
	return "Sober"
end

local function updateBar(fillBar: Frame, valueLabel: TextLabel, drunkness: number)
	local normalized = math.clamp(drunkness / VISUAL_MAX, 0, 1)
	local displayPercent = math.floor(normalized * 100 + 0.5)
	local displayValue = string.format("%d/%d", math.floor(drunkness + 0.5), VISUAL_MAX)
	local stage = getStageValue()
	fillBar.Size = UDim2.new(normalized, 0, 1, 0)
	valueLabel.Text = string.format("%s  %d%%  %s", displayValue, displayPercent, string.upper(stage))

	if normalized >= 0.85 then
		fillBar.BackgroundColor3 = Color3.fromRGB(255, 78, 78)
	elseif normalized >= 0.55 then
		fillBar.BackgroundColor3 = Color3.fromRGB(255, 134, 72)
	else
		fillBar.BackgroundColor3 = Color3.fromRGB(255, 180, 76)
	end
end

local screenGui = createGui()
local fillBar = screenGui.Root.BarBack:WaitForChild(BAR_FRAME_NAME) :: Frame
local valueLabel = screenGui.Root:WaitForChild(LABEL_NAME) :: TextLabel
local drunknessValue = getDrunknessValue()
local targetDrunkness = drunknessValue.Value
local displayedDrunkness = drunknessValue.Value

updateBar(fillBar, valueLabel, drunknessValue.Value)
drunknessValue:GetPropertyChangedSignal("Value"):Connect(function()
	targetDrunkness = drunknessValue.Value
end)

RunService.RenderStepped:Connect(function(dt)
	if displayedDrunkness < targetDrunkness then
		displayedDrunkness = math.min(targetDrunkness, displayedDrunkness + (RISE_PER_SECOND * dt))
	else
		displayedDrunkness = math.max(targetDrunkness, displayedDrunkness - (FALL_PER_SECOND * dt))
	end

	updateBar(fillBar, valueLabel, displayedDrunkness)
end)
