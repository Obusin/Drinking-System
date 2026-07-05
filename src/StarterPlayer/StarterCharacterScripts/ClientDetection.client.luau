local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local character = player.Character
local humanoid = character:WaitForChild("Humanoid")

local onClientCharDiedEvent = ReplicatedStorage:WaitForChild("onClientCharDied")
local function onClientDied()
	onClientCharDiedEvent:FireServer(player)
end

humanoid.Died:Connect(onClientDied)
