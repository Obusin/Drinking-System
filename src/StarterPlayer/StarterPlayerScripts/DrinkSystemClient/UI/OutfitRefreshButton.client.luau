-- OutfitRefreshButton: lets a player apply whatever avatar they've currently
-- saved (via the native Avatar Editor's "Save"/"Save for next respawn")
-- LIVE, without a full character respawn. Server-side guards (see
-- AvatarRefreshService) keep this from ever touching movement or gameplay
-- state — it's appearance-only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystem:WaitForChild("Config")
local SharedModules = DrinkSystem:WaitForChild("SharedModules")

local Settings = require(ConfigFolder:WaitForChild("Settings"))
local Network = require(SharedModules:WaitForChild("Network"))
local Packets = Network.Packets

if Settings.EnableOutfitRefresh ~= true then
	return
end

local gui = Instance.new("ScreenGui")
gui.Name = "DS_OutfitRefresh"
gui.ResetOnSpawn = false
gui.DisplayOrder = 58
gui.Parent = player:WaitForChild("PlayerGui")

local btn = Instance.new("TextButton")
btn.AnchorPoint = Vector2.new(1, 0.5)
btn.Position = UDim2.new(1, -10, 0.5, -48)
btn.Size = UDim2.new(0, 84, 0, 40)
btn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
btn.BackgroundTransparency = 0.15
btn.BorderSizePixel = 0
btn.Font = Enum.Font.Montserrat
btn.TextSize = 13
btn.TextColor3 = Color3.fromRGB(255, 255, 255)
btn.Text = "Refresh\nOutfit"
btn.TextWrapped = true
btn.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = btn

local statusLabel = Instance.new("TextLabel")
statusLabel.AnchorPoint = Vector2.new(1, 0.5)
statusLabel.Position = UDim2.new(1, -100, 0.5, -48)
statusLabel.Size = UDim2.new(0, 180, 0, 40)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Montserrat
statusLabel.TextSize = 12
statusLabel.TextXAlignment = Enum.TextXAlignment.Right
statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
statusLabel.Text = ""
statusLabel.TextTransparency = 1
statusLabel.Parent = gui

local function requestRefresh()
	Packets.RequestRefreshOutfit.send({})
end

btn.Activated:Connect(function()
	requestRefresh()
end)

Packets.RefreshOutfitResult.listen(function(data)
	statusLabel.Text = data.Message or ""
	statusLabel.TextColor3 = data.Ok and Color3.fromRGB(140, 230, 140) or Color3.fromRGB(240, 130, 120)
	statusLabel.TextTransparency = 0
	task.delay(2.5, function()
		statusLabel.TextTransparency = 1
	end)
end)

-- Best-effort: some Roblox clients expose AvatarEditorService with a
-- PromptSaveAvatarCompleted event that can fire from the native pause-menu
-- Avatar Editor, not just prompts we invoke ourselves. Wrapped entirely in
-- pcall — if it's unavailable or behaves differently, this silently no-ops
-- and the manual button above is the reliable path either way.
pcall(function()
	local AvatarEditorService = game:GetService("AvatarEditorService")
	AvatarEditorService.PromptSaveAvatarCompleted:Connect(function(status)
		if status == Enum.AvatarPromptResult.Success then
			requestRefresh()
		end
	end)
end)
