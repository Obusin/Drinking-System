--[[
	DevAudit — an in-memory record of every sensitive request.

	ACCEPTED AND REJECTED BOTH. A log of only successful actions answers
	"what did we change" and not "who tried". The second question is the
	one that matters when an account is compromised, and a rejection burst
	from a non-roster UserId is the earliest signal there is.

	CURRENT SERVER ONLY, IN MEMORY. A ring buffer, dropped on shutdown.
	Persisting it means a DataStore write path reachable from a remote,
	which is a larger attack surface than the log is worth today. When it
	IS wanted, it belongs behind a server-side batch writer that no remote
	can reach — not a write per request.

	NOTHING SENSITIVE GOES IN. Payloads are summarised, not stored: a
	command's payload is developer input and could be long, and a log that
	can be grown without bound by the thing it is logging is a memory
	exhaustion bug wearing a security feature's clothes.
--]]

local RunService = game:GetService("RunService")

local DevAudit = {}

-- Ring buffer. Sized so a busy session is fully visible without the log
-- itself becoming the largest thing on the server.
local MAX_ENTRIES = 300

local entries: { any } = {}
local nextIndex = 1
local total = 0 -- lifetime count, including entries already overwritten

-- Truncated hard. A developer can send a 200-character string per the
-- protocol limit, and 20 of those in a payload would be 4KB per log line.
local function short(value: any, limit: number): string
	local text = tostring(value)
	if #text <= limit then
		return text
	end
	return text:sub(1, limit) .. "…"
end

-- A ONE-LINE SUMMARY, never the payload itself.
--
-- Keys are listed with scalar values only; a nested table becomes
-- "{...}". That is enough to reconstruct what was attempted and cannot
-- be inflated by the caller.
local function summarise(payload: any): string
	if type(payload) ~= "table" then
		return if payload == nil then "-" else short(payload, 40)
	end
	local parts = {}
	local n = 0
	for k, v in payload do
		n += 1
		if n > 8 then
			table.insert(parts, "…")
			break
		end
		local shown = if type(v) == "table" then "{...}" else short(v, 40)
		table.insert(parts, ("%s=%s"):format(short(k, 24), shown))
	end
	table.sort(parts) -- stable, so two logs of the same call read alike
	return table.concat(parts, " ")
end

-- `who` comes from DevPermissions.describe — derived from the
-- authenticated Player, never from anything the caller sent.
function DevAudit.record(who: { userId: number, name: string, role: string }, command: string, ok: boolean, code: string, payload: any, note: string?)
	local entry = {
		at = os.time(),
		clock = os.clock(),
		userId = who.userId,
		name = who.name,
		role = who.role,
		command = short(command, 48),
		success = ok,
		code = code,
		summary = summarise(payload),
		note = if note then short(note, 120) else nil,
		jobId = game.JobId,
		placeId = game.PlaceId,
	}

	entries[nextIndex] = entry
	nextIndex = nextIndex % MAX_ENTRIES + 1
	total += 1

	-- REJECTIONS GO TO OUTPUT AS WELL.
	--
	-- The in-memory log is only readable by someone who can already open
	-- the console. A denied request from an account that is NOT on the
	-- roster is exactly the event nobody will be watching the console
	-- for, so it also goes where server logs are kept.
	if not ok and who.role == "none" then
		warn(
			("[DevAudit] DENIED %s from %s (%d) — %s"):format(
				entry.command,
				entry.name,
				entry.userId,
				code
			)
		)
	end
end

-- Newest first, capped. Reading is itself a privileged action — the
-- caller is checked by the router before this is reached.
function DevAudit.recent(limit: number?): { any }
	local want = math.clamp(limit or 100, 1, MAX_ENTRIES)
	local out = {}
	-- Walk backwards from the most recently written slot.
	local i = (nextIndex - 2) % MAX_ENTRIES + 1
	for _ = 1, MAX_ENTRIES do
		local entry = entries[i]
		if entry then
			table.insert(out, entry)
			if #out >= want then
				break
			end
		end
		i = (i - 2) % MAX_ENTRIES + 1
	end
	return out
end

function DevAudit.stats(): { total: number, held: number }
	local held = 0
	for _ in entries do
		held += 1
	end
	return { total = total, held = held }
end

function DevAudit.start()
	if RunService:IsStudio() then
		print("[DevAudit] in-memory audit log ready (Studio).")
	end
end

return DevAudit
