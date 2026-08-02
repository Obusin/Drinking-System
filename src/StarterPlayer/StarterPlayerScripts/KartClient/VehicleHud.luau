--[[
	VehicleHud — calling your kart, in the lobby.

	Drawing is KeyPrompt's job; this owns the conversation with the
	server and the one piece of state that comes out of it.

	IT HOLDS NO AUTHORITY. It sends "spawn" or "despawn" and waits to be
	told what happened — the server decides, including whether there is
	room where the player is standing. The label follows the server's
	answer rather than flipping on click, so a blocked spawn cannot leave
	the prompt offering to put away a kart that was never built.

	Only built in a lobby. A race place hands you a kart because a round
	is starting; there is nothing to ask for.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))
local KeyPrompt = require(script.Parent.KeyPrompt)

local LOBBY = Config.Lobby

local VehicleHud = {}
VehicleHud.__index = VehicleHud

function VehicleHud.new()
	local remote = BloxKart:WaitForChild(Names.VEHICLE_REMOTE, 10) :: RemoteEvent?

	local self = setmetatable({
		remote = remote,
		-- What the SERVER last told us, never what we hoped.
		hasKart = false,
	}, VehicleHud)

	self.prompt = KeyPrompt.new({
		name = "CallKart",
		keys = LOBBY.ToggleKeys,
		position = LOBBY.KartPosition,
		onActivate = function()
			self:Toggle()
		end,
	})
	self.prompt:SetLabel(LOBBY.SpawnText)

	if remote then
		remote.OnClientEvent:Connect(function(result)
			self:_result(result)
		end)
	else
		warn("[VehicleHud] no vehicle remote — is PlayerVehicleService running?")
	end

	return self
end

function VehicleHud:Toggle()
	if not self.remote then
		return
	end
	self.remote:FireServer(if self.hasKart then "despawn" else "spawn")
end

function VehicleHud:_result(result: unknown)
	if result == "spawned" then
		self.hasKart = true
		self.prompt:SetLabel(LOBBY.DespawnText)
	elseif result == "despawned" then
		self.hasKart = false
		self.prompt:SetLabel(LOBBY.SpawnText)
	elseif result == "blocked" then
		self.prompt:Note(LOBBY.BlockedMessage)
	elseif result == "failed" then
		self.prompt:Note("COULD NOT BUILD YOUR KART — TRY AGAIN")
	end
end

function VehicleHud:Update(dt: number)
	self.prompt:Update(dt)
end

function VehicleHud:Destroy()
	self.prompt:Destroy()
end

return VehicleHud
