-- IceCubeTestButton: QA-only button to trigger the Ice Cube secret instantly,
-- no need to brew a Water + Ice drink first. Gated by
-- Settings.EnableIceCubeTestButton — flip that off before launch and this
-- script no-ops entirely.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystem:WaitForChild("Config")
local SharedModules = DrinkSystem:WaitForChild("SharedModules")

local Settings = require(ConfigFolder:WaitForChild("Settings"))
local Network = require(SharedModules:WaitForChild("Network"))
local Packets = Network.Packets

if Settings.EnableIceCubeTestButton ~= true then
	return
end

local gui = Instance.new("ScreenGui")
gui.Name = "DS_IceCubeTest"
gui.ResetOnSpawn = false
gui.DisplayOrder = 61
gui.Parent = player:WaitForChild("PlayerGui")

local btn = Instance.new("TextButton")
btn.AnchorPoint = Vector2.new(1, 0.5)
btn.Position = UDim2.new(1, -10, 0.5, 96)
btn.Size = UDim2.new(0, 84, 0, 40)
btn.BackgroundColor3 = Color3.fromRGB(60, 140, 210)
btn.BackgroundTransparency = 0.1
btn.BorderSizePixel = 0
btn.Font = Enum.Font.MontserratBold
btn.TextSize = 12
btn.TextColor3 = Color3.fromRGB(255, 255, 255)
btn.Text = "Test Ice Cube"
btn.TextWrapped = true
btn.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = btn

btn.Activated:Connect(function()
	Packets.RequestTestIceCube.send({})
end)
