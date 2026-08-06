--[[
	Protocol — the shared contract between the console client and server.

	WHAT IS SAFE TO PUT HERE, AND WHAT IS NOT
	-----------------------------------------
	This module is in ReplicatedStorage, so treat every line of it as
	PUBLISHED. An exploiter reads it as easily as we do.

	That is fine for what it holds: remote names, response codes and the
	envelope shape. Knowing the remote's name is not a capability —
	firing it still lands in the router, which asks DevPermissions before
	it looks at anything else.

	What must NEVER move here:
	  - the roster (see DevRoster's note on free reconnaissance)
	  - the permission map
	  - the command registry, its validators or its rate limits
	  - anything an adapter knows about the game's internals

	A command list would be the tempting one, so: it is not here on
	purpose. The client is TOLD which commands it may see, per role, in a
	snapshot — it does not read them from a shared table, because a
	shared table tells an unauthorized reader exactly what to try.
--]]

local Protocol = {}

-- Two remotes, and the split is deliberate.
--
-- A RemoteFunction gives request/response for free, which is what a
-- console wants — every action returns a structured result. The event is
-- for server->client PUSH only (log lines, snapshot invalidation), and
-- the client never fires it, so there is no second inbound surface to
-- secure.
Protocol.CALL_REMOTE = "KartDevCall" -- RemoteFunction, client -> server
Protocol.PUSH_REMOTE = "KartDevPush" -- RemoteEvent, server -> client only

-- Response codes. Stable strings, because the UI switches on them and a
-- reworded message must not change behaviour.
--
-- DELIBERATELY COARSE. `NOT_AUTHORIZED` covers "you are not on the
-- roster" AND "that command exists but is above your role" AND "no such
-- command" — three different truths behind one answer, so a caller
-- cannot probe the command list by reading which error comes back.
Protocol.Code = table.freeze({
	OK = "OK",
	NOT_AUTHORIZED = "NOT_AUTHORIZED",
	RATE_LIMITED = "RATE_LIMITED",
	DUPLICATE = "DUPLICATE", -- replayed requestId
	BAD_PAYLOAD = "BAD_PAYLOAD",
	NOT_FOUND = "NOT_FOUND", -- target resolved to nothing
	WRONG_PLACE = "WRONG_PLACE", -- e.g. driving AI in the lobby
	UNAVAILABLE = "UNAVAILABLE", -- the game cannot do this right now
	INTERNAL = "INTERNAL", -- handler errored; details go to the log only
})

-- Envelope limits, enforced on the SERVER. Declared here so the client
-- can avoid sending something it knows will be refused, which is a
-- convenience and never a check.
Protocol.Limits = table.freeze({
	MaxCommandLength = 48,
	MaxRequestIdLength = 64,
	-- Payloads are shallow by design: a console command takes ids and
	-- numbers, never a nested structure. Capping depth and breadth stops
	-- a malicious client burning server CPU in the VALIDATOR, before any
	-- command-specific check has run.
	MaxPayloadKeys = 16,
	MaxPayloadDepth = 3,
	MaxStringLength = 200,
})

-- Failures carry a code the UI can branch on and a message a human can
-- read. `data` is only ever present on success.
export type Response = {
	requestId: string,
	success: boolean,
	code: string,
	message: string,
	data: { [string]: any }?,
}

function Protocol.ok(requestId: string, message: string?, data: { [string]: any }?): Response
	return {
		requestId = requestId,
		success = true,
		code = Protocol.Code.OK,
		message = message or "OK",
		data = data,
	}
end

function Protocol.fail(requestId: string, code: string, message: string?): Response
	return {
		requestId = requestId,
		success = false,
		code = code,
		-- Falls back to the code rather than to a description of what
		-- went wrong internally. Nothing here should ever hand an
		-- unauthorized caller a hint about why.
		message = message or code,
	}
end

return Protocol
