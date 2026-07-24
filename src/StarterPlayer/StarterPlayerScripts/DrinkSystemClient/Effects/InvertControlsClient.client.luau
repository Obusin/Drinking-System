-- InvertControlsClient: Owner's Delight secret — inverts WASD for a while.
-- Roblox has no native "invert movement" toggle, so this uses the standard
-- trick: bind to RenderStepped at Enum.RenderPriority.Last (guaranteed to
-- run AFTER the default character control script that turn), read whatever
-- MoveDirection it just computed from input, and re-issue Humanoid:Move()
-- with that direction negated — our later call wins for the frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local SharedModules = DrinkSystem:WaitForChild("SharedModules")
local Network = require(SharedModules:WaitForChild("Network"))
local Packets = Network.Packets

local BIND_NAME = "DS_InvertControls"
local expiresAt = 0
local bound = false

local function update()
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if os.clock() >= expiresAt then
		RunService:UnbindFromRenderStep(BIND_NAME)
		bound = false
		return
	end
	local dir = humanoid.MoveDirection
	if dir.Magnitude > 0.05 then
		humanoid:Move(-dir, false) -- MoveDirection is already world-space
	end
end

Packets.InvertControls.listen(function(data)
	local duration = data.Duration or 10
	expiresAt = os.clock() + duration
	if not bound then
		bound = true
		RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Last.Value, update)
	end
end)

-- Respawning mid-effect would leave a stale bind fighting a fresh humanoid
player.CharacterRemoving:Connect(function()
	if bound then
		RunService:UnbindFromRenderStep(BIND_NAME)
		bound = false
	end
end)
