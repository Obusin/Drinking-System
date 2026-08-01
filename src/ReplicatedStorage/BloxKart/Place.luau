--[[
	Place — am I the lobby or a race server?

	Shared, and asked on both sides: the server decides which services to
	start, the client decides which HUD to build. Two copies of "which
	place is this" would eventually disagree, and the failure would be a
	race HUD in the hub, which looks like a bug in the HUD.

	The answer is derived ONCE, at require time, from a number that is
	known before anything loads. It cannot change during a session — a
	server does not become a different place — so nothing here needs to
	be recomputed and nothing needs to listen.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("BloxKart"):WaitForChild("Config"))

local PL = Config.Places

local Place = {}

export type Role = "lobby" | "race"

export type Track = {
	id: string,
	name: string,
	placeId: number,
	laps: number?,
}

--=====================================================================
--  THE ROLE
--=====================================================================

-- Worked out once. See the note above: this is a constant for the life
-- of the server.
local function resolve(): Role
	-- THE TEST OVERRIDE, first, because its whole point is to win.
	-- Studio only — see the note in Config/Places.
	local forced = PL.ForceRoleInStudio
	if RunService:IsStudio() and (forced == "lobby" or forced == "race") then
		warn(("[Place] FORCED to %s by Config.Places.ForceRoleInStudio. Studio only."):format(forced:upper()))
		return forced :: Role
	end

	local lobby = PL.LobbyPlaceId

	-- NOT SET UP YET. Every place is a race place, which is what the
	-- game did before this file existed. Deliberately silent: this is
	-- the normal state until the lobby exists, and a warning every
	-- session for a thing that is not wrong is a warning people learn
	-- to skip past.
	if lobby == 0 then
		return "race"
	end

	-- An unpublished place has no id. Studio's play-solo on a saved-
	-- but-never-published file lands here. Race, so the track still
	-- works — a hub with nothing to do is the more confusing default.
	if game.PlaceId == 0 then
		if RunService:IsStudio() then
			warn("[Place] PlaceId is 0 — this place has never been published. Running as a RACE place.")
		end
		return "race"
	end

	return if game.PlaceId == lobby then "lobby" else "race"
end

local role: Role = resolve()

function Place.role(): Role
	return role
end

function Place.isLobby(): boolean
	return role == "lobby"
end

function Place.isRace(): boolean
	return role == "race"
end

--=====================================================================
--  TRACKS
--=====================================================================

-- The row for a place id, or nil if it is not listed.
--
-- NIL IS NORMAL and callers must handle it. A race place that is not in
-- the table still runs perfectly — it just has no name and no per-track
-- overrides, because the table exists so the LOBBY can find its way in,
-- not so a track can find itself.
function Place.trackFor(placeId: number): Track?
	for _, track in PL.Tracks do
		if track.placeId == placeId then
			return track
		end
	end
	return nil
end

-- This server's track row, if it has one.
function Place.track(): Track?
	return Place.trackFor(game.PlaceId)
end

-- Every track the lobby can actually send somebody to, in display
-- order. A row with placeId 0 is a placeholder that has not been filled
-- in and is skipped rather than offered — a portal to place 0 is a
-- teleport that fails in front of the player.
function Place.playableTracks(): { Track }
	local out = {}
	for _, track in PL.Tracks do
		if track.placeId ~= 0 and track.placeId ~= PL.LobbyPlaceId then
			table.insert(out, track)
		end
	end
	return out
end

-- How many laps here. The track row wins, Config.Race is the default,
-- so a track only carries the number if it differs.
function Place.laps(): number
	local track = Place.track()
	return (track and track.laps) or Config.Race.TotalLaps
end

--=====================================================================
--  DID THEY COME THROUGH THE LOBBY?
--=====================================================================

-- A reserved server is one the lobby asked for. Public servers of a
-- race place are the ones a player reaches by clicking the place on the
-- website, which is the route `RequireLobbyEntry` exists to close.
function Place.isReserved(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

return Place
