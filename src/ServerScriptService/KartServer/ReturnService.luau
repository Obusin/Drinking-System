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

local PL = Config.Places

local ReturnService = {}
local transitionRemote: RemoteEvent

-- Rounds completed since the last trip home, or since server start.
local sinceReturn = 0
-- Guards the window between "we decided to go" and "the teleport
-- fired" — onResults could in principle fire again inside that gap.
local returning = false

-- Called from MatchService.onResults, composed with BotService's own
-- subscriber in init.server.
function ReturnService.onResults()
	-- Nowhere to send them, or told not to. Config.Places.LobbyPlaceId
	-- being 0 is the same "not set up yet" fallback every other Places
	-- read uses — silent, because it is the normal state until a lobby
	-- exists, not a misconfiguration.
	if PL.LobbyPlaceId == 0 or PL.ReturnAfterRounds <= 0 or returning then
		return
	end

	sinceReturn += 1
	if sinceReturn < PL.ReturnAfterRounds then
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

	-- The async half of the same failure TeleportInitFailed exists for
	-- everywhere else in this codebase: TeleportAsync can return cleanly
	-- and still fail moments later. QueueService has its own connection
	-- to the same signal — Roblox signals are multi-subscriber, so the
	-- two do not conflict or overwrite each other.
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		if player.Parent == Players then
			transitionRemote:FireClient(player, "release")
		end
		warn(("[Return] teleport home failed for %s: %s (%s)"):format(player.Name, tostring(result), tostring(message)))
	end)
end

return ReturnService
