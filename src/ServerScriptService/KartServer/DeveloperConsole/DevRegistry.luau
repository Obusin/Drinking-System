--[[
	DevRegistry — everything the console has spawned, and nothing else.

	THIS IS WHAT MAKES CLEANUP SAFE.
	--------------------------------
	"Remove all developer AI" iterates this registry. A legitimate match
	bot was never added to it, so it cannot be removed by that command —
	not because the command is careful, but because the bot is not in the
	list it walks. That is a structural guarantee rather than a check
	somebody has to remember to write.

	THE CLIENT NEVER SENDS AN INSTANCE.
	-----------------------------------
	It sends an id from here. The server resolves it, confirms it is
	registered, and confirms it still exists. An Instance from a client is
	an arbitrary reference into the DataModel and there is no validator
	that makes that safe.
--]]

local DevRegistry = {}

export type Kind = "pickup" | "ai"

type Entry = {
	id: string,
	kind: Kind,
	instance: Instance?,
	racer: any?, -- the bot's racer table, for AI
	spawnedBy: number,
	spawnedAt: number,
	meta: { [string]: any },
}

local entries: { [string]: Entry } = {}
local counter = 0

-- Ids are server-generated and include the JobId prefix, so an id from
-- one server is meaningless in another. A replayed id from a different
-- session resolves to nothing rather than to whatever happens to occupy
-- that slot here.
local function newId(kind: string): string
	counter += 1
	return ("%s_%s_%d"):format(kind, tostring(game.JobId):sub(1, 8), counter)
end

function DevRegistry.add(kind: Kind, instance: Instance?, spawnedBy: number, meta: { [string]: any }?, racer: any?): string
	local id = newId(kind)
	entries[id] = {
		id = id,
		kind = kind,
		instance = instance,
		racer = racer,
		spawnedBy = spawnedBy,
		spawnedAt = os.time(),
		meta = meta or {},
	}
	return id
end

-- Resolve, with the kind checked.
--
-- The kind check matters: without it, "remove this pickup" would accept
-- an AI's id and destroy a bot. Ids are opaque to the client, so the
-- only thing stopping that is the server insisting the id is the kind
-- the command expects.
function DevRegistry.get(id: any, kind: Kind?): Entry?
	if type(id) ~= "string" then
		return nil
	end
	local entry = entries[id]
	if not entry then
		return nil
	end
	if kind and entry.kind ~= kind then
		return nil
	end
	-- A destroyed instance is a stale record. Cleaned lazily here rather
	-- than by a sweep, so nothing has to run on a timer.
	if entry.instance and not entry.instance.Parent then
		entries[id] = nil
		return nil
	end
	return entry
end

function DevRegistry.remove(id: string)
	entries[id] = nil
end

-- Everything of a kind, optionally filtered to one spawner.
--
-- `spawnedBy` is what separates CLEANUP_OWN from CLEANUP_ALL: a
-- developer can always clear their own mess, while clearing somebody
-- else's is an owner-level action.
function DevRegistry.list(kind: Kind?, spawnedBy: number?): { Entry }
	local out = {}
	for id, entry in entries do
		if entry.instance and not entry.instance.Parent then
			entries[id] = nil
			continue
		end
		if kind and entry.kind ~= kind then
			continue
		end
		if spawnedBy and entry.spawnedBy ~= spawnedBy then
			continue
		end
		table.insert(out, entry)
	end
	table.sort(out, function(a, b)
		return a.spawnedAt < b.spawnedAt
	end)
	return out
end

function DevRegistry.count(kind: Kind?, spawnedBy: number?): number
	return #DevRegistry.list(kind, spawnedBy)
end

return DevRegistry
