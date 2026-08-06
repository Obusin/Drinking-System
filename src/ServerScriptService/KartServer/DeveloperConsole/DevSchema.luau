--[[
	DevSchema — payload validators, composed per command.

	A command declares a SHAPE. Anything the shape does not name is
	rejected rather than ignored: a payload with an unexpected key is
	either a client bug or someone probing, and silently dropping it hides
	both. Rejecting unknown fields is also what stops a future command
	quietly inheriting a field it never validated.

	Every validator returns `ok, errOrValue`. They never throw, because
	they run on the request path and a throw there is an unhandled error
	in a remote handler — which is a crash the caller controls.
--]]

local Protocol = require(game:GetService("ReplicatedStorage").BloxKart.DeveloperConsole.Protocol)

local L = Protocol.Limits

local DevSchema = {}

--=====================================================================
--  SCALARS
--=====================================================================

function DevSchema.string(maxLen: number?)
	local cap = math.min(maxLen or L.MaxStringLength, L.MaxStringLength)
	return function(v: any): (boolean, any)
		if type(v) ~= "string" then
			return false, "expected a string"
		end
		if #v == 0 then
			return false, "must not be empty"
		end
		if #v > cap then
			return false, ("must be at most %d characters"):format(cap)
		end
		return true, v
	end
end

function DevSchema.boolean()
	return function(v: any): (boolean, any)
		if type(v) ~= "boolean" then
			return false, "expected a boolean"
		end
		return true, v
	end
end

-- Integers only, and NaN/inf are rejected explicitly.
--
-- `v ~= v` is the NaN test: NaN fails every comparison, so a range check
-- alone would pass it straight through and hand a nonsense number to a
-- handler that then does arithmetic with it.
function DevSchema.intRange(min: number, max: number)
	return function(v: any): (boolean, any)
		if type(v) ~= "number" or v ~= v then
			return false, "expected a number"
		end
		if v % 1 ~= 0 then
			return false, "expected a whole number"
		end
		if v < min or v > max then
			return false, ("must be between %d and %d"):format(min, max)
		end
		return true, v
	end
end

function DevSchema.numberRange(min: number, max: number)
	return function(v: any): (boolean, any)
		if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
			return false, "expected a finite number"
		end
		if v < min or v > max then
			return false, ("must be between %s and %s"):format(tostring(min), tostring(max))
		end
		return true, v
	end
end

-- A Roblox UserId. Bounded above as a sanity check — ids are integral,
-- positive, and nowhere near 2^53, so a huge value is malformed input
-- rather than a real account.
function DevSchema.userId()
	return function(v: any): (boolean, any)
		if type(v) ~= "number" or v ~= v or v % 1 ~= 0 then
			return false, "expected a UserId"
		end
		if v <= 0 or v > 1e12 then
			return false, "not a plausible UserId"
		end
		return true, v
	end
end

-- One of a fixed set of strings.
function DevSchema.oneOf(allowed: { string })
	local set = {}
	for _, s in allowed do
		set[s] = true
	end
	return function(v: any): (boolean, any)
		if type(v) ~= "string" or not set[v] then
			return false, "not an allowed value"
		end
		return true, v
	end
end

-- An id that must exist in a live registry, checked at CALL time rather
-- than captured at build time — so a registry that gains an entry does
-- not need this validator rebuilding, and one that loses an entry starts
-- rejecting it immediately.
function DevSchema.inRegistry(lookup: (string) -> any?)
	return function(v: any): (boolean, any)
		if type(v) ~= "string" or #v == 0 or #v > 64 then
			return false, "expected an id"
		end
		if not lookup(v) then
			return false, "unknown id"
		end
		return true, v
	end
end

-- Present or absent, but if present it must satisfy `inner`.
function DevSchema.optional(inner: (any) -> (boolean, any))
	return function(v: any): (boolean, any)
		if v == nil then
			return true, nil
		end
		return inner(v)
	end
end

--=====================================================================
--  SHAPES
--=====================================================================

-- Depth and breadth are capped BEFORE any field validator runs.
--
-- A validator is cheap; walking an adversarial payload is not. A deeply
-- nested or very wide table would burn server CPU inside validation
-- itself, which is a denial of service that never reaches a handler and
-- so would never be rate-limited by anything downstream.
local function withinLimits(value: any, depth: number): (boolean, string?)
	if type(value) ~= "table" then
		return true, nil
	end
	if depth > L.MaxPayloadDepth then
		return false, "payload nested too deeply"
	end
	local n = 0
	for _, v in value do
		n += 1
		if n > L.MaxPayloadKeys then
			return false, "payload has too many fields"
		end
		local ok, err = withinLimits(v, depth + 1)
		if not ok then
			return false, err
		end
	end
	return true, nil
end

-- `fields` maps name -> validator. Returns ok, cleanOrError.
--
-- The returned table is REBUILT from validated values rather than being
-- the caller's table with extra keys deleted. A handler therefore cannot
-- be handed anything a validator did not explicitly pass, even by
-- accident — including a metatable.
function DevSchema.shape(payload: any, fields: { [string]: (any) -> (boolean, any) }): (boolean, any)
	if payload == nil then
		payload = {}
	end
	if type(payload) ~= "table" then
		return false, "payload must be a table"
	end

	local ok, err = withinLimits(payload, 1)
	if not ok then
		return false, err
	end

	-- Unknown fields are an error, not noise. See the module note.
	for key in payload do
		if type(key) ~= "string" then
			return false, "payload keys must be strings"
		end
		if not fields[key] then
			return false, ("unexpected field %q"):format(key:sub(1, 24))
		end
	end

	local clean = {}
	for name, validator in fields do
		local good, result = validator(payload[name])
		if not good then
			return false, ("%s: %s"):format(name, tostring(result))
		end
		clean[name] = result
	end
	return true, clean
end

return DevSchema
