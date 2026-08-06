--[[
	QueueService — getting a player from the hub onto a track.

	Today this is a teleport and nothing more: press RACE, arrive at the
	track, the round loop there does the rest. There is no queue, no
	party, no reserved server and no waiting room.

	It is named for what it becomes rather than what it does, because
	everything that IS coming — grouping players, holding them until
	there are enough, keeping a party together, picking a mode — belongs
	on this seam and nowhere else. A module called TeleportService would
	have to be renamed or worked around the moment any of that arrives.

	THE CLIENT NEVER NAMES A DESTINATION.

	It sends "play". The server picks the track. That is not politeness —
	a remote that accepts a place id is a remote that will teleport your
	players into somebody else's experience, and it is the kind of thing
	that reads as harmless right up until it is not. See Kart/SECURITY.md:
	send an intent, never a value the server can look up itself.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Names = require(BloxKart:WaitForChild("Names"))
local Place = require(BloxKart:WaitForChild("Place"))
local Config = require(BloxKart:WaitForChild("Config"))

local QueueService = {}

local remote: RemoteEvent
local transitionRemote: RemoteEvent
-- Who is already on their way. A teleport takes seconds and the player
-- stays in the server for all of them, so without this a second press
-- starts a second teleport for someone who is already leaving.
local inFlight: { [Player]: boolean } = {}

--=====================================================================
--  WHICH TRACK?
--
--  One track, chosen at random from the ones that have a real place id.
--  Random rather than first, so a second track starts being used the
--  moment it is filled in rather than the day something is written to
--  choose between them.
--
--  This is the function that grows into matchmaking. When there is a
--  queue it stops being "pick a track" and becomes "pick a track and
--  the people to send with you" — and nothing outside this file has to
--  know that happened.
--=====================================================================
local function pickTrack()
	local playable = Place.playableTracks()
	if #playable == 0 then
		return nil
	end
	return playable[math.random(#playable)]
end

--=====================================================================
--  THE REQUEST
--=====================================================================
local function onRequest(player: Player, action: unknown)
	-- A track does not send you racing; you are already there.
	if not Place.isLobby() then
		return
	end
	if action ~= "play" then
		return
	end
	if inFlight[player] then
		return
	end

	local track = pickTrack()
	if not track then
		-- Config.Places.Tracks has no real place id yet. Say so rather
		-- than doing nothing: a prompt that silently ignores you is
		-- indistinguishable from one that is broken.
		remote:FireClient(player, "notrack")
		warn("[Queue] nobody can race — no entry in Config.Places.Tracks has a real placeId.")
		return
	end

	inFlight[player] = true
	remote:FireClient(player, "pending", track.name)
	transitionRemote:FireClient(player, "teleportOut", "race", track.name)

	-- Give the client-side wipe time to reach full cover before Roblox
	-- starts tearing the place down. If the remote is delayed, the
	-- teleport still wins; this is polish, not authority.
	task.wait(Config.Rewards.WipeTime + Config.Rewards.WipeImageHold)

	-- The mode travels with the player rather than living in the track's
	-- own config, because a track is a MAP and casual/ranked/time-trial
	-- are rules. One place per map, mode as data — see SYSTEM.md.
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({
		fromLobby = true,
		mode = "casual",
		trackId = track.id,
	})

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(track.placeId, { player }, options)
	end)

	if not ok then
		inFlight[player] = nil
		transitionRemote:FireClient(player, "release")
		remote:FireClient(player, "failed")
		warn(("[Queue] teleport to %s (%d) failed: %s"):format(track.name, track.placeId, tostring(err)))
	end
end

--=====================================================================
--  START
--=====================================================================
function QueueService.start()
	remote = Instance.new("RemoteEvent")
	remote.Name = Names.QUEUE_REMOTE
	remote.Parent = BloxKart

	transitionRemote = Instance.new("RemoteEvent")
	transitionRemote.Name = Names.TRANSITION_REMOTE
	transitionRemote.Parent = BloxKart

	remote.OnServerEvent:Connect(onRequest)

	-- ASYNC FAILURE. TeleportAsync can return cleanly and still fail
	-- afterwards — the place is full, or not part of this experience, or
	-- Roblox is having a moment. Without this the player is left with a
	-- prompt saying FINDING YOU A RACE forever, which is the worst of
	-- the possible outcomes because it looks like it is still working.
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		inFlight[player] = nil
		if player.Parent == Players then
			transitionRemote:FireClient(player, "release")
			remote:FireClient(player, "failed")
		end
		warn(("[Queue] teleport failed for %s: %s (%s)"):format(player.Name, tostring(result), tostring(message)))
	end)

	Players.PlayerRemoving:Connect(function(player)
		inFlight[player] = nil
	end)

	if #Place.playableTracks() == 0 then
		warn("[Queue] started, but no track has a real placeId — RACE will refuse until Config.Places.Tracks is filled in.")
	end
end

return QueueService
