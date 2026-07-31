--[[
	Progress — the single grant path.

	EVERY award in the game goes through `Progress.award`. Not because
	one function is tidier, but because this project's most expensive
	recurring bug is one question answered in two places, and the
	question here is "how much has this player earned". Two answers to
	that is not a drift, it is a dupe.

	So: `RaceService` asks. `MatchService` asks. Nothing writes a total
	itself, and when currency and `DataService` arrive they arrive
	INSIDE this file — every caller already routes through it, and the
	audit line, the caps and the idempotency have exactly one place to
	live.

	SESSION ONLY, AND IT SAYS SO
	----------------------------
	There is no persistence yet. XP lives in this table until the server
	shuts down and then it is gone. That is deliberate rather than
	unfinished: the two client-authoritative seams (finish time, upward
	progress) are still open, so anything saved today would be saved
	from numbers a modified client can choose. Storing it first and
	securing it later means the first thing the store contains is the
	exploit.

	`Rewards.Preview` drives the "not saved yet" line on the results
	panel. Keep them honest together.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))

local L = Config.Level

local Progress = {}

-- userId -> { xp, bolt, hits, takedowns, eliminations, races }
local state: { [number]: any } = {}

local function blank()
	return { xp = 0, bolt = 0, hits = 0, takedowns = 0, eliminations = 0, races = 0 }
end

local function entry(userId: number)
	local e = state[userId]
	if not e then
		e = blank()
		state[userId] = e
	end
	return e
end

--=====================================================================
--  CURVE
--=====================================================================

-- XP to get from `level` to the next one.
function Progress.costOf(level: number): number
	return L.Base + L.Step * math.max(level - 1, 0)
end

-- Total XP -> level, and how far into it. Walked rather than solved
-- with a closed form, because the curve is meant to stay editable and
-- twenty iterations of arithmetic is nothing.
function Progress.levelOf(xp: number): (number, number, number)
	local level = 1
	local left = xp
	while level < L.MaxLevel do
		local cost = Progress.costOf(level)
		if left < cost then
			return level, left, cost
		end
		left -= cost
		level += 1
	end
	-- Capped. Progress reads full rather than empty, which is the
	-- truthful rendering of "there is nothing left to earn".
	return L.MaxLevel, 1, 1
end

--=====================================================================
--  THE GRANT PATH
--=====================================================================

-- The ONLY function that increases a total. `reason` is not decoration:
-- it is the audit line, and the first time somebody has an impossible
-- amount of XP it is the difference between a mystery and a query.
function Progress.award(player: Player?, amount: number, reason: string)
	if not player or amount <= 0 then
		return
	end
	local e = entry(player.UserId)
	local before = Progress.levelOf(e.xp)
	e.xp += amount
	local after = Progress.levelOf(e.xp)

	-- Bots never reach here — they have no Player — which is correct
	-- and also the shape of bug this project keeps finding. Stated so
	-- the next person does not "fix" it.
	local gained = after - before
	local bolt = 0
	if gained > 0 then
		-- PAID PER LEVEL CROSSED, not per award. One finish can carry
		-- someone through two levels, and paying once would quietly
		-- swallow the second.
		bolt = L.BoltPerLevel * gained
		e.bolt += bolt
	end

	if Progress.onAward then
		Progress.onAward(player, {
			amount = amount,
			reason = reason,
			level = after,
			leveledUp = gained > 0,
			bolt = bolt,
		})
	end
end

-- Told about every award, so the client can show it as it happens.
-- A hook rather than a remote in here: this module is the grant path
-- and has no business owning replication. Set by init.server.
Progress.onAward = nil :: ((Player, any) -> ())?

function Progress.hit(player: Player?, takedown: boolean)
	if not player then
		return
	end
	local e = entry(player.UserId)
	e.hits += 1
	if takedown then
		e.takedowns += 1
		Progress.award(player, L.XpPerTakedown, "takedown")
	else
		Progress.award(player, L.XpPerHit, "hit")
	end
end

-- Knocked somebody into the void. A tally and an award — the victim is
-- respawning at their last checkpoint while this is being counted.
function Progress.eliminated(player: Player?)
	if not player then
		return
	end
	entry(player.UserId).eliminations += 1
	Progress.award(player, L.XpPerElimination, "elimination")
end

function Progress.finished(player: Player?, place: number)
	if not player then
		return
	end
	entry(player.UserId).races += 1
	Progress.award(player, L.XpForPlace[place] or L.XpFloor, "finish P" .. tostring(place))
end

--=====================================================================
--  READ
--=====================================================================

-- What the results panel needs, in the shape it renders.
function Progress.summary(player: Player)
	local e = entry(player.UserId)
	local level, into, cost = Progress.levelOf(e.xp)
	return {
		n = level,
		max = L.MaxLevel,
		progress = into / math.max(cost, 1),
		xp = e.xp,
		hits = e.hits,
		takedowns = e.takedowns,
		eliminations = e.eliminations,
		bolt = e.bolt,
	}
end

-- XP earned in one race, for the "+N XP" line. Snapshotted at the grid
-- and diffed at the flag rather than accumulated separately, because a
-- second running total is a second thing to get wrong.
local marks: { [number]: number } = {}

function Progress.mark(player: Player)
	marks[player.UserId] = entry(player.UserId).xp
end

function Progress.since(player: Player): number
	return entry(player.UserId).xp - (marks[player.UserId] or 0)
end

Players.PlayerRemoving:Connect(function(player)
	state[player.UserId] = nil
	marks[player.UserId] = nil
end)

return Progress
