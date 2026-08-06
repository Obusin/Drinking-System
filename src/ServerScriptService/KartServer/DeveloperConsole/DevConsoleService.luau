--[[
	DevConsoleService — the remotes and the router. The ONLY entry point.

	THE ORDER OF CHECKS IS THE DESIGN
	---------------------------------
	  1. authorized at all?      before the command name is even read
	  2. command registered?
	  3. holds its permission?
	  4. requestId fresh?
	  5. within rate limit?
	  6. payload validates?
	  7. run

	Authorisation comes FIRST, before the command is looked up, so an
	unauthorized caller gets the same answer whatever they send. They
	cannot enumerate the command list by comparing "no such command"
	against "not allowed" — both are NOT_AUTHORIZED.

	NOTHING BYPASSES THIS. There is no second remote, no debug hook and
	no "if Studio" shortcut. A command is reachable only through here.

	FAIL CLOSED EVERYWHERE. A validator that errors, a handler that
	throws, an unknown permission, a missing rate — all reject.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Protocol = require(BloxKart.DeveloperConsole.Protocol)

local DevPermissions = require(script.Parent.DevPermissions)
local DevRateLimiter = require(script.Parent.DevRateLimiter)
local DevAudit = require(script.Parent.DevAudit)
local DevCommands = require(script.Parent.DevCommands)
local DevRegistry = require(script.Parent.DevRegistry)

local Code = Protocol.Code
local DevConsoleService = {}

-- PlayerRemoving fires for everyone, and there is no point walking the
-- registry for someone who could never have spawned anything.
local function hasSpawnedAnything(player: Player): boolean
	return DevRegistry.count(nil, player.UserId) > 0
end

local _callRemote: RemoteFunction? = nil
local pushRemote: RemoteEvent? = nil

--=====================================================================
--  REPLAY WINDOW
--
--  Recently seen request ids, per user. A replayed id is refused.
--
--  This is NOT a security boundary on its own — an attacker simply
--  generates a fresh id. It exists so a retrying or buggy client cannot
--  double-apply an action, which for "spawn AI" is the difference
--  between one kart and five.
--=====================================================================
local REPLAY_WINDOW = 120 -- seconds
local seen: { [number]: { [string]: number } } = {}

local function freshRequest(userId: number, requestId: string): boolean
	local now = os.clock()
	local mine = seen[userId]
	if not mine then
		mine = {}
		seen[userId] = mine
	end
	-- Swept opportunistically rather than on a timer. The table is
	-- bounded by the rate limiter: a user cannot create ids faster than
	-- they can make accepted requests.
	for id, at in mine do
		if now - at > REPLAY_WINDOW then
			mine[id] = nil
		end
	end
	if mine[requestId] then
		return false
	end
	mine[requestId] = now
	return true
end

Players.PlayerRemoving:Connect(function(player)
	seen[player.UserId] = nil
end)

--=====================================================================
--  THE ROUTER
--=====================================================================

local function route(player: Player, requestId: string, command: string, payload: any): Protocol.Response
	-- 1. AUTHORIZED AT ALL. First, and deliberately before the command
	-- name is examined. See the module note.
	local role = DevPermissions.getRole(player)
	if not role then
		DevAudit.record(DevPermissions.describe(player), tostring(command), false, Code.NOT_AUTHORIZED, payload)
		return Protocol.fail(requestId, Code.NOT_AUTHORIZED, "Permission denied.")
	end

	local who = DevPermissions.describe(player)
	local ctx = { player = player, userId = player.UserId, role = role }

	local function deny(code: string, message: string?): Protocol.Response
		DevAudit.record(who, command, false, code, payload, message)
		return Protocol.fail(requestId, code, message)
	end

	-- 2. REGISTERED. An unknown command reports NOT_AUTHORIZED, not
	-- NOT_FOUND, so the reply cannot be used to probe what exists.
	local entry = DevCommands[command]
	if not entry then
		return deny(Code.NOT_AUTHORIZED, "Permission denied.")
	end

	-- 3. HOLDS THE PERMISSION.
	if not DevPermissions.can(player, entry.permission) then
		return deny(Code.NOT_AUTHORIZED, "Permission denied.")
	end

	-- 4. FRESH REQUEST ID.
	if not freshRequest(player.UserId, requestId) then
		return deny(Code.DUPLICATE, "That request was already processed.")
	end

	-- 5. RATE LIMIT.
	local allowed, retry = DevRateLimiter.check(player.UserId, command, entry.rate)
	if not allowed then
		return deny(Code.RATE_LIMITED, ("Slow down — try again in %.1fs."):format(retry))
	end

	-- 6. VALIDATE. pcall because a validator is code and a thrown error
	-- inside one would otherwise surface as an unhandled exception in a
	-- remote handler, which the caller controls the timing of.
	local okValidate, validOrErr, clean = pcall(entry.validate, payload)
	if not okValidate then
		warn(("[DevConsole] validator for %q errored: %s"):format(command, tostring(validOrErr)))
		return deny(Code.BAD_PAYLOAD, "Invalid payload.")
	end
	if not validOrErr then
		-- The validator's message is safe to return: it describes the
		-- SHAPE the caller sent, never anything about the server.
		return deny(Code.BAD_PAYLOAD, tostring(clean))
	end
	local cleanPayload = clean

	-- 6b. ELEVATION. A field that widens the blast radius needs a higher
	-- permission than the command itself. Checked here so a handler is
	-- never trusted to check it.
	if entry.elevate then
		for field, required in entry.elevate do
			if cleanPayload[field] and not DevPermissions.can(player, required) then
				return deny(Code.NOT_AUTHORIZED, "Permission denied.")
			end
		end
	end

	-- 6c. MODERATION RANK. A command flagged `moderates` may only act on
	-- someone the caller outranks, and never on the caller.
	--
	-- Enforced HERE rather than in each handler for the same reason
	-- permissions are: a check written per command is a check that will
	-- eventually be forgotten in one of them, and this is the one where
	-- forgetting it means a developer can ban the owner.
	if entry.moderates then
		local mayModerate, why = DevPermissions.canModerate(player, cleanPayload.targetUserId)
		if not mayModerate then
			return deny(Code.NOT_AUTHORIZED, why)
		end
	end

	-- 7. RUN.
	local okRun, a, b, c, d = pcall(entry.run, ctx, cleanPayload)
	if not okRun then
		-- The real error goes to the server log, never to the caller: it
		-- can carry file paths and internal state.
		warn(("[DevConsole] %q errored: %s"):format(command, tostring(a)))
		return deny(Code.INTERNAL, "The command failed.")
	end

	local success, code, message, data = a, b or Code.OK, c, d
	DevAudit.record(who, command, success == true, code, cleanPayload, message)
	if not success then
		return Protocol.fail(requestId, code, message)
	end
	return Protocol.ok(requestId, message, data)
end

--=====================================================================
--  REMOTES
--=====================================================================

function DevConsoleService.start()
	DevPermissions.start()
	DevAudit.start()

	local existing = BloxKart:FindFirstChild(Protocol.CALL_REMOTE)
	if existing then
		existing:Destroy()
	end
	local call = Instance.new("RemoteFunction")
	call.Name = Protocol.CALL_REMOTE
	call.Parent = BloxKart
	_callRemote = call

	local push = Instance.new("RemoteEvent")
	push.Name = Protocol.PUSH_REMOTE
	push.Parent = BloxKart
	pushRemote = push

	call.OnServerInvoke = function(player, requestId, command, payload)
		-- ENVELOPE VALIDATION BEFORE ANYTHING ELSE. These are the only
		-- values the router itself uses, and a non-string here would
		-- otherwise reach string.format in the audit path.
		if type(requestId) ~= "string" or #requestId == 0 or #requestId > Protocol.Limits.MaxRequestIdLength then
			return Protocol.fail("invalid", Code.BAD_PAYLOAD, "Bad request id.")
		end
		if type(command) ~= "string" or #command == 0 or #command > Protocol.Limits.MaxCommandLength then
			return Protocol.fail(requestId, Code.BAD_PAYLOAD, "Bad command.")
		end

		local ok, result = pcall(route, player, requestId, command, payload)
		if not ok then
			warn("[DevConsole] router errored: " .. tostring(result))
			return Protocol.fail(requestId, Code.INTERNAL, "The command failed.")
		end
		return result
	end

	-- A DEVELOPER LEAVING TAKES THEIR TEST OBJECTS WITH THEM.
	--
	-- Otherwise a session's worth of spawned karts outlives whoever made
	-- them, and the next person to look at the server sees a crowd of
	-- bots nobody can account for.
	Players.PlayerRemoving:Connect(function(player)
		if not hasSpawnedAnything(player) then
			return
		end
		local AI = require(script.Parent.adapters.AI)
		local World = require(script.Parent.adapters.World)
		pcall(AI.remove, player.UserId)
		pcall(World.clearPickups, player.UserId)
	end)

	print("[DevConsole] ready — " .. Protocol.CALL_REMOTE)
end

-- Server -> client push, for future log streaming. Authorised at the
-- point of sending; the client cannot subscribe itself.
function DevConsoleService.push(player: Player, topic: string, data: any)
	if not pushRemote or not DevPermissions.isAuthorized(player) then
		return
	end
	pushRemote:FireClient(player, topic, data)
end

return DevConsoleService
