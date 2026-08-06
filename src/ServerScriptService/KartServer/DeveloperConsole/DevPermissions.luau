--[[
	DevPermissions — the ONE place that answers "may this player do this".

	Every console remote and every command handler calls this. Nothing
	re-implements a check, and nothing checks a UserId directly: a second
	copy of an authorisation rule is a rule that will eventually disagree
	with the first, and the disagreement will be discovered by whoever
	exploits it rather than by us.

	WHAT THIS TRUSTS
	----------------
	Exactly one thing: the `Player` object handed to it by a Roblox
	server event. `player.UserId` on the server is set by Roblox from the
	authenticated session and cannot be written by the client.

	It trusts NOTHING else. Not attributes, not the character, not a name,
	not anything in the payload, not whether the console UI exists on that
	client, not whether the request looks like it came from the UI.

	FAIL CLOSED
	-----------
	Every path that cannot positively establish a role returns false. A
	nil player, a player who has left, a malformed permission name, an
	unknown role — all no.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DevRoster = require(script.Parent.DevRoster)

local DevPermissions = {}

-- Server-only by construction. Requiring this on a client would give
-- that client the roster, which is the one thing DevRoster exists to
-- avoid — so it refuses rather than quietly working.
if not RunService:IsServer() then
	error("[DevPermissions] server-only module required from a client", 2)
end

-- The authenticated role for a live player, or nil.
--
-- Re-checks `player.Parent == Players` because a request can arrive in
-- the same frame someone disconnects, and acting on a departed player's
-- behalf is a small correctness bug that becomes a real one the moment
-- a command spawns something owned by them.
function DevPermissions.getRole(player: any): string?
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end
	if player.Parent ~= Players then
		return nil
	end
	return DevRoster.roleForUserId(player.UserId)
end

-- May this player use the console AT ALL? The coarse gate, used to
-- decide whether to even look at a request.
function DevPermissions.isAuthorized(player: any): boolean
	return DevPermissions.getRole(player) ~= nil
end

-- May this player perform this specific capability?
--
-- `permission` is a KEY from DevRoster.Permissions, not a role and not a
-- command name. An unregistered key returns false rather than defaulting
-- to something permissive, so a typo in a command's declaration denies
-- access instead of granting it.
function DevPermissions.can(player: any, permission: string?): boolean
	if type(permission) ~= "string" then
		return false
	end
	local required = DevRoster.Permissions[permission]
	if not required then
		-- Loud: this is a programming error in a command declaration, and
		-- it fails closed, so it would otherwise be invisible until
		-- somebody wondered why a command never worked.
		warn(("[DevPermissions] unknown permission %q — denying. Add it to DevRoster.Permissions."):format(permission))
		return false
	end
	return DevRoster.satisfies(DevPermissions.getRole(player), required)
end

-- For the audit log. Safe to call for ANY player, including
-- unauthorized ones, and returns nothing sensitive — it describes the
-- caller, not the roster.
function DevPermissions.describe(player: any): { userId: number, name: string, role: string }
	local ok = typeof(player) == "Instance" and player:IsA("Player")
	return {
		userId = if ok then player.UserId else -1,
		-- Recorded from the authenticated Player object, never from a
		-- client-supplied string. A caller cannot forge whose name goes
		-- in the log.
		name = if ok then player.Name else "<invalid>",
		role = DevPermissions.getRole(player) or "none",
	}
end

function DevPermissions.start()
	print(("[DevPermissions] roster loaded — %d authorized account(s)."):format(DevRoster.size()))
end

return DevPermissions
