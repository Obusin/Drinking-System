--[[
	Moderation — kick, ban, unban.

	THE ONE PART OF THIS CONSOLE THAT REACHES BEYOND THE SERVER.
	------------------------------------------------------------
	Everything else here spawns a test object or nudges a live session,
	and the worst case is a messy server that a restart fixes. A ban
	persists, applies to accounts that are not present, and cannot be
	undone by the person it happened to. It is treated accordingly:
	owner-only, confirmation-gated, rank-checked, bounded and audited.

	USES ROBLOX'S NATIVE BAN API, NOT A HOME-GROWN LIST.
	----------------------------------------------------
	`Players:BanAsync` is enforced by Roblox at join, survives without a
	DataStore of our own, and can optionally cover known alt accounts —
	none of which a custom ban table gets without writing and securing a
	join-time check as well. A hand-rolled list is also one more
	persistent store reachable, indirectly, from a remote.

	IT DOES NOT WORK IN STUDIO. BanAsync requires a published, running
	experience; in Studio it throws. That is reported as UNAVAILABLE
	rather than swallowed, so a test does not silently look successful.

	REASONS ARE BOUNDED AND SANITISED, NOT FILTERED.
	------------------------------------------------
	`DisplayReason` is shown to the banned player. It is authored by an
	owner, not by a player, so text filtering would mostly serve to mangle
	a legitimate moderator's wording. Control characters are stripped and
	length is capped — enough to stop a malformed payload reaching the
	API, without editorialising.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Protocol = require(BloxKart.DeveloperConsole.Protocol)

local Moderation = {}

local Code = Protocol.Code

-- Roblox caps DisplayReason at 400 characters. Kept well under, because
-- a reason is a sentence and anything longer is a mistake.
local MAX_REASON = 200

-- Permanent is -1 to the API. Exposed as a named bound so the validator
-- and the UI agree on what "forever" is.
Moderation.MAX_DURATION_DAYS = 365
Moderation.PERMANENT = -1

-- Newlines and control characters out. They serve no purpose in a
-- one-line reason and are the usual way to make a log entry or a UI
-- label render as something it is not.
local function clean(text: string?): string
	local value = tostring(text or "")
	value = value:gsub("[%c]", " ")
	value = value:gsub("%s+", " ")
	value = value:match("^%s*(.-)%s*$") or ""
	if #value > MAX_REASON then
		value = value:sub(1, MAX_REASON)
	end
	if value == "" then
		value = "No reason given."
	end
	return value
end

-- KICK. Present-server only, immediately reversible by rejoining.
function Moderation.kick(targetUserId: number, reason: string?, byName: string): (boolean, string, string)
	local player = Players:GetPlayerByUserId(targetUserId)
	if not player then
		return false, Code.NOT_FOUND, "That player is not in this server."
	end
	local text = clean(reason)
	-- The moderator's name comes from the authenticated Player object on
	-- the server, never from the payload — a caller cannot sign somebody
	-- else's name to a kick.
	player:Kick(("%s\n— %s"):format(text, byName))
	return true, Code.OK, ("Kicked %s."):format(player.Name)
end

-- BAN. `durationDays` of 0 or less means permanent.
--
-- `excludeAlts = false` (the API default is to include them) is passed
-- explicitly rather than left implicit: whether a ban reaches alt
-- accounts is a policy decision and it should be visible in the code
-- that makes it, not inherited from a default that could change.
function Moderation.ban(
	targetUserId: number,
	durationDays: number,
	reason: string?,
	privateNote: string?,
	includeAlts: boolean
): (boolean, string, string)
	local display = clean(reason)
	-- The private reason is for the audit trail and the Roblox dashboard;
	-- the banned player never sees it.
	local private = clean(privateNote or reason)

	local seconds = if durationDays and durationDays > 0
		then math.floor(durationDays * 86400)
		else Moderation.PERMANENT

	local ok, err = pcall(function()
		Players:BanAsync({
			UserIds = { targetUserId },
			Duration = seconds,
			DisplayReason = display,
			PrivateReason = private,
			ExcludeAltAccounts = not includeAlts,
			-- This experience only. A universe-wide ban from a debug
			-- console is a bigger blast radius than this tool should
			-- have; set it deliberately elsewhere if it is ever wanted.
			ApplyToUniverse = false,
		})
	end)

	if not ok then
		-- Studio, or no API access, or a malformed id. Reported rather
		-- than swallowed: a ban that silently did nothing is worse than
		-- one that failed loudly.
		return false,
			Code.UNAVAILABLE,
			"BanAsync failed (Studio or no API access?): " .. tostring(err):sub(1, 120)
	end

	return true,
		Code.OK,
		if seconds == Moderation.PERMANENT
			then ("Banned %d permanently."):format(targetUserId)
			else ("Banned %d for %d day(s)."):format(targetUserId, durationDays)
end

function Moderation.unban(targetUserId: number): (boolean, string, string)
	local ok, err = pcall(function()
		Players:UnbanAsync({ UserIds = { targetUserId }, ApplyToUniverse = false })
	end)
	if not ok then
		return false, Code.UNAVAILABLE, "UnbanAsync failed: " .. tostring(err):sub(1, 120)
	end
	return true, Code.OK, ("Unbanned %d."):format(targetUserId)
end

return Moderation
