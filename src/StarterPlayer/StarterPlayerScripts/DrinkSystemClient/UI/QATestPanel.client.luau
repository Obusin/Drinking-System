-- QATestPanel: single consolidated debug drawer for every secret-drink QA
-- trigger (replaces the old separate Ice Cube / Bee Swarm / secret-effects
-- buttons that used to clutter the screen). Collapsed by default — click the
-- "QA" tab to expand. Each entry only appears if its own Settings flag is on,
-- and if EVERY flag is off, this script builds nothing at all.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystem:WaitForChild("Config")
local SharedModules = DrinkSystem:WaitForChild("SharedModules")

local Settings = require(ConfigFolder:WaitForChild("Settings"))
local Network = require(SharedModules:WaitForChild("Network"))
local Packets = Network.Packets

-- { Label, Fire } — Fire sends whatever packet that entry needs
local entries = {}

if Settings.EnableIceCubeTestButton == true then
	table.insert(entries, {
		Label = "Ice Cube",
		Fire = function()
			Packets.RequestTestIceCube.send({})
		end,
	})
end

if Settings.EnableBeeSwarmTestButton == true then
	table.insert(entries, {
		Label = "Bee Swarm",
		Fire = function()
			Packets.RequestTestBeeSwarm.send({})
		end,
	})
end

if Settings.EnableSecretEffectTestButtons == true then
	local SECRET_EFFECTS = {
		{ Label = "Chicken Dinner", Name = "ChickenDinner" },
		{ Label = "Owner's Delight", Name = "OwnersDelight" },
		{ Label = "Hotdog Smoke", Name = "HotdogBreadDrink" },
		{ Label = "Birthday Party", Name = "BirthdayParty" },
		{ Label = "Relapse Drink", Name = "RelapseDrink" },
		{ Label = "Olkab's Hair", Name = "OlkabsHair" },
		{ Label = "Instant Death", Name = "InstantDeath" },
	}
	for _, effect in ipairs(SECRET_EFFECTS) do
		table.insert(entries, {
			Label = effect.Label,
			Fire = function()
				Packets.RequestTestSecretEffect.send({ EffectName = effect.Name })
			end,
		})
	end
end

if #entries == 0 then
	return -- every QA flag is off — nothing to build
end

local gui = Instance.new("ScreenGui")
gui.Name = "DS_QATestPanel"
gui.ResetOnSpawn = false
gui.DisplayOrder = 61
gui.Parent = player:WaitForChild("PlayerGui")

local tab = Instance.new("TextButton")
tab.AnchorPoint = Vector2.new(0, 0.5)
tab.Position = UDim2.new(0, 0, 0.5, 0)
tab.Size = UDim2.new(0, 34, 0, 74)
tab.BackgroundColor3 = Color3.fromRGB(80, 60, 140)
tab.BackgroundTransparency = 0.1
tab.BorderSizePixel = 0
tab.Font = Enum.Font.MontserratBold
tab.TextSize = 13
tab.TextColor3 = Color3.fromRGB(255, 255, 255)
tab.Text = "QA"
tab.ZIndex = 2
tab.Parent = gui
local tabCorner = Instance.new("UICorner")
tabCorner.CornerRadius = UDim.new(0, 8)
tabCorner.Parent = tab

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0, 0.5)
panel.Position = UDim2.new(0, 40, 0.5, 0)
panel.Size = UDim2.new(0, 140, 0, (#entries * 36) + 12)
panel.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 6)
pad.PaddingLeft = UDim.new(0, 6)
pad.PaddingRight = UDim.new(0, 6)
pad.Parent = panel

for i, entry in ipairs(entries) do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 32)
	btn.LayoutOrder = i
	btn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
	btn.BackgroundTransparency = 0.05
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.Montserrat
	btn.TextSize = 12
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Text = entry.Label
	btn.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn

	btn.Activated:Connect(function()
		entry.Fire()
	end)
end

tab.Activated:Connect(function()
	panel.Visible = not panel.Visible
end)
