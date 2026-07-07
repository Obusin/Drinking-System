local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local DrinkSystem  = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystem:WaitForChild("Config")
local Settings     = require(ConfigFolder:WaitForChild("Settings"))

-- Bar spans the TRUE drunkness range (0..100), not the visual-effects max,
-- so the stage checkpoints line up with where things actually happen.
local BAR_MAX         = math.max(Settings.DrunknessMax or 100, 1)
local RISE_PER_SECOND = Settings.DrunknessVisualRisePerSecond or 4.5
local FALL_PER_SECOND = Settings.DrunknessVisualFallPerSecond or 1.5

-- Fill color ramp: sober green → warning amber → collapse red
local COLOR_LOW  = Color3.fromRGB(95, 200, 110)
local COLOR_MID  = Color3.fromRGB(235, 185, 60)
local COLOR_HIGH = Color3.fromRGB(220, 60, 50)

-- Wire to the Studio UI
local playerGui    = player:WaitForChild("PlayerGui")
local screenGui    = playerGui:WaitForChild("DrunknessLevel")
-- Keep the SAME gui instance across respawns — this controller wires
-- references once, so a ResetOnSpawn re-clone would leave the bar dead.
screenGui.ResetOnSpawn = false
local canvasGroup  = screenGui:WaitForChild("CanvasGroup")
local barContainer = canvasGroup:WaitForChild("Bar")
local fillBar      = barContainer:WaitForChild("Bar") :: Frame

-- Checkpoint ticks in Design are named by their X position (".125", ".25",
-- ".5" ...). Snap each frame to the position its name declares so the marks
-- stay exact even if nudged in the editor. Unparseable names are left alone.
local designFolder = canvasGroup:FindFirstChild("Design")
if designFolder then
	for _, child in ipairs(designFolder:GetChildren()) do
		if child:IsA("Frame") then
			local pos = tonumber(child.Name)
			if pos and pos > 0 and pos < 1 then
				child.AnchorPoint = Vector2.new(0.5, child.AnchorPoint.Y)
				child.Position = UDim2.new(pos, 0, child.Position.Y.Scale, child.Position.Y.Offset)
			end
		end
	end
end

local function fillColorFor(alpha: number): Color3
	if alpha < 0.5 then
		return COLOR_LOW:Lerp(COLOR_MID, alpha / 0.5)
	end
	return COLOR_MID:Lerp(COLOR_HIGH, (alpha - 0.5) / 0.5)
end

local function updateBar(drunkness: number)
	local alpha = math.clamp(drunkness / BAR_MAX, 0, 1)
	fillBar.Size = UDim2.new(alpha, 0, 1, 0)
	fillBar.BackgroundColor3 = fillColorFor(alpha)
end

-- Anchor left so the bar grows rightward
fillBar.AnchorPoint = Vector2.new(0, 0)
fillBar.Position    = UDim2.new(0, 0, 0, 0)

local drunknessValue     = player:WaitForChild("Drunkness") :: NumberValue
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
		-- Fall rate scales with the gap so big drops (death reset, Water)
		-- catch up in ~2s instead of crawling at natural-recovery pace.
		local gap = displayedDrunkness - targetDrunkness
		local fallRate = math.max(FALL_PER_SECOND, gap * 0.6)
		displayedDrunkness = math.max(targetDrunkness, displayedDrunkness - fallRate * dt)
	end
	updateBar(displayedDrunkness)
end)
