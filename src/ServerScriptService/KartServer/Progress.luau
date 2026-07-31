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
local Ledger = require(script.Parent.Ledger)

local L = Config.Level

local Progress = {}

-- userId -> { xp, bolt, hits, takedowns, eliminations, races, stats }
local state: { [number]: any } = {}

local function blank()
	return { xp = 0, bolt = 0, crystals = 0, hits = 0, takedowns = 0, eliminations = 0, races = 0, stats = {} }
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

	Ledger.record(player, "xp", amount, e.xp, reason, Progress.matchId)
	if bolt > 0 then
		Ledger.record(player, "bolt", bolt, e.bolt, "levelup", Progress.matchId)
	end

	if Progress.onAward then
		Progress.onAward(player, {
			amount = amount,
			kind = "xp",
			reason = reason,
			level = after,
			leveledUp = gained > 0,
			bolt = bolt,
		})
	end
end

-- Anything that changes a total calls this. Quests use it to know when
-- a bar has moved without polling every player every second for an
-- answer that is usually "no change".
function Progress.touch(player: Player?)
	if player and Progress.onChanged then
		Progress.onChanged(player)
	end
end

Progress.onChanged = nil :: ((Player) -> ())?

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
	Progress.count(player, "hits")
	if takedown then
		e.takedowns += 1
		Progress.count(player, "takedowns")
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
	Progress.count(player, "eliminations")
	Progress.award(player, L.XpPerElimination, "elimination")
end

-- Everything about a finish the SERVER can see for itself. Counted here
-- rather than accepted from the client precisely because it can be: a
-- place, a win, a podium and a grid gain are all things the server
-- assigned, so there is no reason for any of them to be reported.
function Progress.finished(player: Player?, place: number, gridSlot: number?)
	if not player then
		return
	end
	local e = entry(player.UserId)
	e.races += 1
	Progress.count(player, "finishes")
	if place == 1 then
		Progress.count(player, "wins")
	end
	if place <= 3 then
		Progress.count(player, "podiums")
	end
	if gridSlot and gridSlot > place then
		Progress.count(player, "gridGain", gridSlot - place)
	end
	Progress.award(player, L.XpForPlace[place] or L.XpFloor, "finish P" .. tostring(place))
end

-- CURRENCY IN. The counterpart to spend, and the only way a balance
-- goes up — quests, races and events all ask through here rather than
-- touching a field, so the ledger row and the cap have one home.
--
-- Separate from `award`, which is XP: XP has a level curve behind it and
-- currency does not, and folding them together would mean one function
-- with two unrelated jobs.
function Progress.grant(player: Player?, kind: string, amount: number, reason: string)
	if not player or amount <= 0 then
		return
	end
	local e = entry(player.UserId)
	if kind == "bolt" then
		e.bolt += amount
	elseif kind == "crystals" then
		e.crystals += amount
	else
		return
	end
	local after = if kind == "bolt" then e.bolt else e.crystals
	Ledger.record(player, kind, amount, after, reason, Progress.matchId)

	-- ANNOUNCED, like XP is. Claiming a quest used to pay in silence —
	-- the row said CLAIMED and nothing else moved, which is
	-- indistinguishable from a reward that did not arrive.
	if Progress.onAward then
		Progress.onAward(player, {
			amount = amount,
			kind = kind,
			reason = reason,
			balance = after,
		})
	end
	Progress.touch(player)
end

-- THE OTHER HALF OF THE SINGLE PATH.
--
-- Checks and deducts in ONE operation. A separate "can they afford it"
-- followed by a deduct is a race, and a race is a dupe — two purchases
-- can both pass the check before either takes the money.
--
-- Returns false rather than going negative. A balance that can go below
-- zero is a balance that has already been spent twice.
function Progress.spend(player: Player?, kind: string, cost: number, reason: string): boolean
	if not player or cost <= 0 then
		return false
	end
	local e = entry(player.UserId)
	local have = if kind == "bolt" then e.bolt elseif kind == "crystals" then e.crystals else nil
	if not have or have < cost then
		return false
	end
	if kind == "bolt" then
		e.bolt -= cost
	else
		e.crystals -= cost
	end
	Ledger.record(player, kind, -cost, if kind == "bolt" then e.bolt else e.crystals, reason, Progress.matchId)
	return true
end

-- Stamped by MatchService so every row can be traced to a race. Nil
-- outside one, which is correct — a shop purchase belongs to no match.
Progress.matchId = nil :: string?

--=====================================================================
--  COUNTERS
--
--  Everything a quest can read that is not XP. Deliberately a generic
--  bag rather than a named field per stat: the quest pools are content
--  and will keep growing, and a schema that needs editing every time
--  somebody writes a quest is a schema that stops being edited.
--=====================================================================

function Progress.count(player: Player?, metric: string, n: number?)
	if not player or metric == "" then
		return
	end
	local by = n or 1
	if by <= 0 then
		return
	end
	local e = entry(player.UserId)
	e.stats[metric] = (e.stats[metric] or 0) + by
	Progress.touch(player)
end

-- A whole race's worth of client-reported driving counters, clamped.
--
-- CLAMPED HERE AND NOWHERE ELSE, so there is one place to look when the
-- numbers are wrong and one place to change when the caps are. See
-- Config.Level.StatCaps for why a cap rather than a proof.
-- The cap for a metric, or nil if we do not know it.
--
-- ITERATING THE CAP TABLE WAS WRONG. Per-item counters are
-- `itemsUsed_<Id>` and are generated from the catalogue, so they can
-- never appear in a hand-written table — every per-item quest would have
-- been silently dropped, which is indistinguishable from a quest nobody
-- plays. Same failure shape as the skin probe that reported nothing.
--
-- An unknown key is refused rather than trusted, and said out loud once
-- so a new counter with no cap is a warning instead of a dead quest.
local warnedMetrics = {}

local function capFor(metric: string): number?
	local cap = L.StatCaps[metric]
	if cap then
		return cap
	end
	if string.match(metric, "^itemsUsed_") then
		return L.StatCaps.itemsUsed
	end
	if not warnedMetrics[metric] then
		warnedMetrics[metric] = true
		warn(("[Progress] no StatCap for %q — refusing it. Add one to Config.Level.StatCaps."):format(metric))
	end
	return nil
end

function Progress.report(player: Player?, batch)
	if not player or typeof(batch) ~= "table" then
		return
	end
	for metric, raw in batch do
		if typeof(metric) == "string" then
			local cap = capFor(metric)
			local n = tonumber(raw)
			if cap and n and n > 0 then
				Progress.count(player, metric, math.min(math.floor(n), cap))
			end
		end
	end
end

function Progress.statsOf(player: Player)
	return entry(player.UserId).stats
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
		crystals = e.crystals,
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
