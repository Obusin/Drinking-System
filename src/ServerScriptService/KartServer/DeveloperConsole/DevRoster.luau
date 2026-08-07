--[[
	DevRoster — WHO is a developer. The single source of truth.

	SERVER-ONLY, AND THAT IS A DELIBERATE DEPARTURE FROM THE BRIEF.
	---------------------------------------------------------------
	The spec suggested a shared `DevConsolePermissions` under
	ReplicatedStorage. Anything in ReplicatedStorage is readable by every
	client, including one running an exploit, so that would publish the
	list of privileged accounts to anybody who asked.

	That is not a hole on its own — knowing who an admin is does not make
	you one, because the server checks every request regardless. But it is
	free reconnaissance handed to an attacker: it names exactly whose
	account is worth stealing, and it is avoidable at zero cost. So the
	roster lives here, the client is never told who is on it, and a
	permitted client learns only one bit about ITSELF: may I open the UI.

	IDENTITY IS THE USERID, NEVER THE NAME.
	---------------------------------------
	Usernames are mutable and re-registerable. A name check is an account
	takeover waiting for someone to change their name to yours. Names
	below are comments for human readability and are never compared.

	FAIL CLOSED.
	------------
	A malformed entry, a missing table or a UserId that is not a positive
	integer resolves to NO role rather than a default one. There is no
	path through this module that grants access by accident.
--]]

local DevRoster = {}

-- ROLES, most privileged first. `Can` is driven by this ordering, so a
-- role implicitly holds every permission of the roles beneath it.
export type Role = "owner" | "developer" | "viewer"

DevRoster.Roles = table.freeze({ "owner", "developer", "viewer" })

--=====================================================================
--  THE ALLOWLIST
--
--  Add a UserId to exactly one table. An id appearing in more than one
--  resolves to the most privileged, so a promotion cannot be silently
--  undone by a stale lower entry.
--=====================================================================
local ROSTER: { [Role]: { number } } = {
	-- Obus1n (displayName "ObuTP"). Resolved from the Roblox users API
	-- on 2026-08-06 and verified against the displayName shown in-game.
	owner = {
		5217557356,
	},

	-- Full console access, minus roster-level and destructive-cleanup
	-- powers. Add trusted collaborators here.
	developer = {},

	-- Read-only: may open the console and request snapshots, may not
	-- change anything. Useful for QA without handing over item granting.
	viewer = {},
}

--=====================================================================
--  PERMISSIONS
--
--  Named capabilities, not command names. Commands declare which
--  permission they need, so adding a command never means editing this
--  table and a typo in a command cannot invent a new privilege.
--=====================================================================
DevRoster.Permissions = table.freeze({
	-- Read
	VIEW_CONSOLE = "viewer",
	VIEW_SERVER = "viewer",
	VIEW_PLAYERS = "viewer",
	VIEW_LOGS = "viewer",

	-- DEVELOPER, not viewer. Currency, ownership and progression are the
	-- closest thing in this game to real player value, and a QA account
	-- that only needs to watch a race has no business reading balances.
	VIEW_PROFILE = "developer",

	-- Write
	GRANT_ITEM = "developer",
	CLEAR_ITEMS = "developer",
	SPAWN_PICKUP = "developer",
	SPAWN_AI = "developer",
	MODIFY_PLAYER = "developer", -- respawn, reset kart
	CLEANUP_OWN = "developer", -- remove entities you spawned

	-- MODERATION. Kick is developer-level: it is annoying, reversible by
	-- rejoining, and useful during a playtest.
	KICK_PLAYER = "developer",

	-- Owner only. Destructive or server-wide.
	CLEANUP_ALL = "owner", -- remove EVERY developer entity, not just yours
	ANNOUNCE = "owner",
	MODIFY_CONFIG = "owner",

	-- BAN IS OWNER-ONLY AND SEPARATE FROM EVERYTHING ELSE.
	--
	-- It is the only action here that persists beyond the server, reaches
	-- accounts that are not present, and cannot be undone by the person
	-- it happened to. A compromised developer account should be able to
	-- waste your afternoon, not your player base.
	BAN_PLAYER = "owner",
	UNBAN_PLAYER = "owner",
})

-- Rank, higher is more privileged. Kept private so nothing outside can
-- invent a role by passing a number.
local RANK: { [string]: number } = { viewer = 1, developer = 2, owner = 3 }

-- A UserId must be a positive integer. Roblox ids are integral and
-- above zero; anything else is malformed config or a spoofed value that
-- reached here by mistake, and both mean "no".
local function validId(id: any): boolean
	return type(id) == "number" and id > 0 and id % 1 == 0
end

-- Built once at require time so the hot path is a hash lookup rather
-- than three linear scans per check.
--
-- Deliberately NOT wrapped in pcall: a malformed roster should be a hard
-- error at server start, when someone is looking, rather than a silent
-- empty allowlist that locks everybody out at 3am with no explanation.
local byId: { [number]: string } = {}
do
	for role, ids in ROSTER do
		if RANK[role] and type(ids) == "table" then
			for _, id in ids do
				if validId(id) then
					-- Most privileged wins, so a duplicate cannot demote.
					local held = byId[id]
					if not held or RANK[role] > RANK[held] then
						byId[id] = role
					end
				else
					warn(("[DevRoster] ignoring malformed UserId in %q: %s"):format(role, tostring(id)))
				end
			end
		end
	end
end

-- The role for a UserId, or nil. Takes an ID rather than a Player so it
-- is callable from anywhere and impossible to feed a spoofed object.
function DevRoster.roleForUserId(userId: any): string?
	if not validId(userId) then
		return nil
	end
	return byId[userId]
end

-- Does `role` satisfy `required`? Higher rank satisfies lower.
--
-- An unknown role on either side is FALSE, not an error: this is called
-- on the request path, and the safe answer to a question it cannot
-- parse is no.
function DevRoster.satisfies(role: string?, required: string?): boolean
	local have = role and RANK[role]
	local need = required and RANK[required]
	if not have or not need then
		return false
	end
	return have >= need
end

-- Numeric rank of a role, or 0 for none. Exposed so moderation can ask
-- "does the actor outrank the target" — see DevPermissions.canModerate.
function DevRoster.rankOf(role: string?): number
	return (role and RANK[role]) or 0
end

-- Count, for the boot log. Never exposes the ids themselves.
function DevRoster.size(): number
	local n = 0
	for _ in byId do
		n += 1
	end
	return n
end

return DevRoster
