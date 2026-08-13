--[[
	ReturnService — after enough rounds, send everyone back to the lobby.

	RACE PLACES ONLY. The lobby is the front door; a track that never lets
	go stops being one stop on a night out and starts being where the
	night happens, which is the opposite of what a hub is for.

	Counts rounds via MatchService.onResults — the SAME hook BotService
	already uses. These hooks are single-subscriber (assigned, not
	appended), so init.server composes the two together rather than this
	module claiming the hook for itself. See Kart/SYSTEM.md §4b for the
	larger note on why there is no event bus yet.

	Config.Places.ReturnAfterRounds = 0 means never, and that is read
	literally: some players want to sit on one track all night, and nothing
	here should override that.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))
local MatchService = require(script.Parent.MatchService)
local Match = require(BloxKart:WaitForChild("Match"))

local PL = Config.Places

local ReturnService = {}
local transitionRemote: RemoteEvent
local returnRemote: RemoteEvent

-- Rounds completed since the last trip home, or since server start.
local sinceReturn = 0
-- Guards the window between "we decided to go" and "the teleport
-- fired" — onResults could in principle fire again inside that gap.
local returning = false
local returningPlayers: { [Player]: boolean } = {}

-- A player-selected return uses the same cover and failure handling as
-- the end-of-session return, but never accepts a client supplied place id.
local function returnPlayer(player: Player)
	if PL.LobbyPlaceId == 0
		or player.Parent ~= Players
		or returningPlayers[player]
		or MatchService.phase() ~= Match.Phase.Results
	then
		return
	end
	returningPlayers[player] = true
	transitionRemote:FireClient(player, "teleportOut", "lobby")
	task.delay(Config.Rewards.WipeTime + Config.Rewards.WipeImageHold, function()
		if player.Parent ~= Players then
			returningPlayers[player] = nil
			return
		end
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(PL.LobbyPlaceId, { player })
		end)
		if not ok then
			returningPlayers[player] = nil
			transitionRemote:FireClient(player, "release")
			warn("[Return] player return failed for " .. player.Name .. ": " .. tostring(err))
		end
	end)
end

-- Called from MatchService.onResults, composed with BotService's own
-- subscriber in init.server.
function ReturnService.onResults()
	-- Nowhere to send them, or told not to. Config.Places.LobbyPlaceId
	-- being 0 is the same "not set up yet" fallback every other Places
	-- read uses — silent, because it is the normal state until a lobby
	-- exists, not a misconfiguration.
	-- `nil` has historically meant "not configured" in place settings. Treat
	-- it exactly like zero; comparing it directly to zero throws during the
	-- Results transition and prevents the phase from ever replicating.
	local afterRounds = PL.ReturnAfterRounds
	if PL.LobbyPlaceId == 0 or type(afterRounds) ~= "number" or afterRounds <= 0 or returning then
		return
	end

	sinceReturn += 1
	if sinceReturn < afterRounds then
		return
	end

	returning = true

	-- Waits out ReturnDelay so the results board is actually seen before
	-- the screen changes again. Kept SHORT of Config.Match.ResultsTime in
	-- the config's own comment for exactly that reason — fire after
	-- Results has moved on and the teleport interrupts whatever round
	-- started next instead.
	task.delay(PL.ReturnDelay, function()
		local here = Players:GetPlayers()
		sinceReturn = 0
		returning = false

		if #here == 0 then
			-- Everyone already left on their own. An empty TeleportAsync
			-- call is a wasted request for nobody.
			return
		end

		transitionRemote:FireAllClients("teleportOut", "lobby")
		task.wait(Config.Rewards.WipeTime + Config.Rewards.WipeImageHold)

		local ok, err = pcall(function()
			TeleportService:TeleportAsync(PL.LobbyPlaceId, here)
		end)
		if not ok then
			transitionRemote:FireAllClients("release")
			-- FALLS BACK TO "KEEP RACING", not a retry loop. A failed
			-- batch teleport leaves everyone exactly where they were —
			-- mid-game, which is the honest state to be in rather than
			-- one this hammers TeleportAsync trying to leave.
			warn("[Return] teleport home failed: " .. tostring(err))
		end
	end)
end

function ReturnService.start()
	transitionRemote = Instance.new("RemoteEvent")
	transitionRemote.Name = Names.TRANSITION_REMOTE
	transitionRemote.Parent = BloxKart

	returnRemote = Instance.new("RemoteEvent")
	returnRemote.Name = Names.RETURN_REMOTE
	returnRemote.Parent = BloxKart
	returnRemote.OnServerEvent:Connect(function(player)
		returnPlayer(player)
	end)

	-- The async half of the same failure TeleportInitFailed exists for
	-- everywhere else in this codebase: TeleportAsync can return cleanly
	-- and still fail moments later. QueueService has its own connection
	-- to the same signal — Roblox signals are multi-subscriber, so the
	-- two do not conflict or overwrite each other.
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		returningPlayers[player] = nil
		if player.Parent == Players then
			transitionRemote:FireClient(player, "release")
		end
		warn(("[Return] teleport home failed for %s: %s (%s)"):format(player.Name, tostring(result), tostring(message)))
	end)
end

return ReturnService
