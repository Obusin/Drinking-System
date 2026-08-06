--[[
	DevRateLimiter — per player, per command, sliding window.

	WHY PER COMMAND AND NOT PER PLAYER
	----------------------------------
	One shared budget means a developer reading snapshots at 1Hz cannot
	spawn AI, and someone spamming a cheap command locks themselves out
	of an expensive one they actually needed. Costs differ by orders of
	magnitude — a snapshot is a table read, spawning AI builds a kart —
	so the budgets are separate and each command declares its own.

	SLIDING, NOT FIXED BUCKETS. A fixed window lets 2x the limit through
	across a boundary (all of window N at the end, all of N+1 at the
	start), which is exactly the burst an expensive command must not
	allow.

	THIS IS NOT A SECURITY BOUNDARY ON ITS OWN. It bounds the damage an
	authorized-but-careless (or compromised) account can do, and it stops
	an unauthorized caller burning server CPU. Authorisation is what stops
	them acting at all.
--]]

local Players = game:GetService("Players")

local DevRateLimiter = {}

-- hits[userId][command] = { timestamps... }, newest last.
local hits: { [number]: { [string]: { number } } } = {}

-- Dropped wholesale on leave. Keyed by UserId rather than Player so a
-- rejoining player cannot inherit a stale allowance, and so nothing here
-- holds a reference that keeps a departed Player alive.
Players.PlayerRemoving:Connect(function(player)
	hits[player.UserId] = nil
end)

-- Returns ok, retryAfterSeconds.
--
-- `rate` is { burst = n, per = seconds }. A missing or malformed rate
-- DENIES: a command that forgot to declare one is a bug, and the safe
-- reading of "no limit specified" is not "unlimited".
function DevRateLimiter.check(userId: number, command: string, rate: any): (boolean, number)
	if type(rate) ~= "table" or type(rate.burst) ~= "number" or type(rate.per) ~= "number" then
		warn(("[DevRateLimiter] command %q has no valid rate — denying."):format(tostring(command)))
		return false, 0
	end
	if rate.burst < 1 or rate.per <= 0 then
		return false, 0
	end

	local now = os.clock()
	local cutoff = now - rate.per

	local perUser = hits[userId]
	if not perUser then
		perUser = {}
		hits[userId] = perUser
	end
	local stamps = perUser[command]
	if not stamps then
		stamps = {}
		perUser[command] = stamps
	end

	-- Drop anything that has aged out. Front of the list is oldest, so
	-- this is a prefix removal and the list stays bounded by `burst`
	-- rather than growing with attempts.
	local keep = 1
	while keep <= #stamps and stamps[keep] <= cutoff do
		keep += 1
	end
	if keep > 1 then
		table.move(stamps, keep, #stamps, 1)
		for i = #stamps - keep + 2, #stamps do
			stamps[i] = nil
		end
	end

	if #stamps >= rate.burst then
		-- The oldest hit is what has to expire before there is room.
		return false, math.max(stamps[1] + rate.per - now, 0)
	end

	-- RECORDED ON ACCEPT ONLY.
	--
	-- Counting rejected attempts would let a spammer extend their own
	-- lockout indefinitely, which sounds like a feature and is not: it
	-- turns a rate limit into a denial-of-service against a legitimate
	-- developer whose client has a bug.
	table.insert(stamps, now)
	return true, 0
end

-- For the audit trail and the console's own diagnostics.
function DevRateLimiter.usage(userId: number, command: string): number
	local perUser = hits[userId]
	local stamps = perUser and perUser[command]
	return if stamps then #stamps else 0
end

function DevRateLimiter.reset(userId: number)
	hits[userId] = nil
end

return DevRateLimiter
