--[[
	QueueHud — the RACE prompt, in the lobby.

	Same shape as VehicleHud and for the same reasons: KeyPrompt draws
	it, this owns the conversation with the server, and it holds no
	authority — it sends "play" and never names a place.

	The one thing it does hold is a LOCAL cooldown, and that is not
	security. A teleport takes a few seconds and gives no feedback of its
	own, so the honest failure is a player pressing the key, seeing
	nothing happen, and pressing it again. The server refuses the second
	request anyway; this is so the player is told why rather than being
	ignored.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))
local KeyPrompt = require(script.Parent.KeyPrompt)

local LOBBY = Config.Lobby

local QueueHud = {}
QueueHud.__index = QueueHud

function QueueHud.new()
	local remote = BloxKart:WaitForChild(Names.QUEUE_REMOTE, 10) :: RemoteEvent?

	local self = setmetatable({
		remote = remote,
		quietUntil = 0,
		onResult = nil,
	}, QueueHud)

	self.prompt = KeyPrompt.new({
		name = "Race",
		keys = LOBBY.PlayKeys,
		position = LOBBY.PlayPosition,
		accent = LOBBY.PlayColor,
		onActivate = function()
			self:Play()
		end,
	})
	self.prompt:SetLabel(LOBBY.PlayText)

	if remote then
		remote.OnClientEvent:Connect(function(result, trackName)
			self:_result(result, trackName)
		end)
	else
		warn("[QueueHud] no queue remote — is QueueService running?")
	end

	return self
end

function QueueHud:Play()
	if not self.remote or os.clock() < self.quietUntil then
		return
	end
	self.quietUntil = os.clock() + LOBBY.PlayRetry
	self.remote:FireServer("play")
end

function QueueHud:_result(result: unknown, trackName: unknown)
	if self.onResult then
		self.onResult(result, trackName)
	end
	if result == "pending" then
		self.prompt:Note(LOBBY.PlayPending)
		if typeof(trackName) == "string" then
			self.prompt:SetLabel(trackName:upper())
		end
	elseif result == "notrack" then
		-- Let them try again immediately: nothing is in flight, and the
		-- answer will not change until the config does, but making them
		-- wait for a refusal teaches nothing.
		self.quietUntil = 0
		self.prompt:Note(LOBBY.NoTrackMessage)
	elseif result == "failed" then
		self.quietUntil = 0
		self.prompt:SetLabel(LOBBY.PlayText)
		self.prompt:Note(LOBBY.PlayFailed)
	end
end

function QueueHud:SetResultHandler(fn: ((unknown, unknown) -> ())?)
	self.onResult = fn
end

function QueueHud:Update(dt: number)
	self.prompt:Update(dt)
end

function QueueHud:SetVisible(on: boolean)
	self.prompt:SetVisible(on)
end

-- Hide the bottom prompt but keep the key working — RACE now lives as the PLAY
-- tab in the lobby top bar. See KeyPrompt:SetShown.
function QueueHud:SetPromptShown(on: boolean)
	self.prompt:SetShown(on)
end

function QueueHud:Destroy()
	self.prompt:Destroy()
end

return QueueHud
