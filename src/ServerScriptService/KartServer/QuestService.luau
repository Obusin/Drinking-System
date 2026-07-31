--[[
	QuestService — assigning, tracking and claiming.

	Design lives in the vault at "BloxKart Quest Design"; the pools are
	Config.Quests. This is the machinery between them.

	THE LIST IS NOT STORED
	----------------------
	Which quests you have is `hash(userId, period, slot)` — a pure
	function of who you are and what day it is. So the profile holds
	three integers and a claim flag per layer, never the quests
	themselves. That keeps the record small, and it means the pools can
	be edited between days without migrating anybody.

	PROGRESS IS A DIFF, NOT A COUNTER
	---------------------------------
	`Progress` counts for all time; a quest asks about one period. So a
	baseline is snapshotted when the period rolls over and progress is
	`now - baseline`. A second set of per-period counters would be a
	second thing to keep in step, and this project has paid for that
	mistake more than once.

	IT WORKS WITHOUT PERSISTENCE
	----------------------------
	`DataService.get` returns nil while the flag is off, so this falls
	back to a session table of the same shape. Flipping the flag changes
	where the table lives and nothing else.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))
local DataService = require(script.Parent.DataService)
local Progress = require(script.Parent.Progress)

local Q = Config.Quests
local LEVEL = Config.Level

local QuestService = {}

local remote: RemoteEvent

-- Session fallback, used while persistence is off. Same shape as the
-- profile's `quests` field so nothing downstream can tell the
-- difference.
local session: { [number]: any } = {}

--=====================================================================
--  PERIODS
--
--  UTC, and derived from the clock rather than tracked with a timer. A
--  timer has to survive a server restart; a number derived from the
--  time simply is what it is.
--=====================================================================
local DAY = 86400

local function dayNumber(): number
	return math.floor(os.time() / DAY)
end

local function weekNumber(): number
	-- Weeks anchored to the epoch, which was a Thursday. Monday is the
	-- reset the design asks for, so shift by 4 days.
	return math.floor((os.time() - 4 * DAY) / (7 * DAY))
end

local function monthNumber(): number
	local d = os.date("!*t")
	return d.year * 12 + d.month
end

QuestService.periods = { Daily = dayNumber, Weekly = weekNumber, Monthly = monthNumber }

--=====================================================================
--  ASSIGNMENT
--=====================================================================

-- Deterministic, and stable for the whole period. Not `math.random`:
-- that would hand a player different quests every time the server
-- restarted, which is the same as not having quests.
local function pick(pool, userId: number, period: number, slot: number, salt: number)
	if #pool == 0 then
		return nil
	end
	-- bit32, not `~`: Luau has no bitwise XOR operator. Constants are the
	-- usual spatial-hash primes — they only need to mix well, not mean
	-- anything.
	local h = bit32.bxor(
		bit32.band(userId * 73856093, 0x7FFFFFFF),
		bit32.band(period * 19349663, 0x7FFFFFFF),
		bit32.band((slot + salt) * 83492791, 0x7FFFFFFF)
	)
	return pool[h % #pool + 1]
end

-- A quest nobody can complete is worse than no quest. See the header of
-- Config.Quests for the three states a metric can be in.
local function isLive(metric: string): boolean
	if Q.ServerMetrics[metric] then
		return true
	end
	if LEVEL.StatCaps[metric] then
		return true
	end
	return string.match(metric, "^itemsUsed_") ~= nil
end

local function livePool(pool)
	local out = {}
	for _, quest in pool do
		if isLive(quest.metric) then
			table.insert(out, quest)
		end
	end
	return out
end

-- Built once at start rather than filtered per assignment: the pools do
-- not change at runtime, and re-filtering for every player every day is
-- work with a constant answer.
local pools: { [string]: { any } } = {}

local function buildPools()
	pools.Daily = {
		livePool(Q.Daily.Guaranteed),
		livePool(Q.Daily.Verb),
		livePool(Q.Daily.Stretch),
	}
	pools.Weekly = {
		livePool(Q.Weekly.General),
		livePool(Q.Weekly.General),
		livePool(Q.Weekly.General),
		livePool(Q.Weekly.Social),
		livePool(Q.Weekly.Collection),
	}
	pools.Monthly = { livePool(Q.Monthly), livePool(Q.Monthly), livePool(Q.Monthly) }

	for layer, slots in pools do
		local empty = 0
		for _, pool in slots do
			if #pool == 0 then
				empty += 1
			end
		end
		if empty > 0 then
			warn(
				("[QuestService] %s has %d slot(s) with no reachable quest — every metric in that pool is still blocked."):format(
					layer,
					empty
				)
			)
		end
	end
end

-- The quests for one layer, right now. Slot order is stable, so slot 1
-- is always the guaranteed one.
function QuestService.assign(userId: number, layer: string)
	local period = QuestService.periods[layer]()
	local slots = pools[layer]
	local out = {}
	for i, pool in slots do
		-- The salt makes two slots drawing from the SAME pool (weekly
		-- General x3) pick different quests instead of three copies.
		local quest = pick(pool, userId, period, i, i * 1013)
		-- Duplicates across slots are still possible on a small pool.
		-- Walk forward rather than reroll, so the result stays
		-- deterministic.
		local tries = 0
		while quest and #pool > 1 and tries < #pool do
			local clash = false
			for _, taken in out do
				if taken and taken.id == quest.id then
					clash = true
					break
				end
			end
			if not clash then
				break
			end
			tries += 1
			quest = pick(pool, userId, period, i, i * 1013 + tries * 7919)
		end
		out[i] = quest
	end
	return out, period
end

--=====================================================================
--  STATE
--=====================================================================
local function blankLayer(count: number)
	local base = {}
	local claimed = {}
	for i = 1, count do
		base[i] = 0
		claimed[i] = false
	end
	return { period = -1, base = base, claimed = claimed, reroll = false }
end

local function stateFor(player: Player)
	local data = DataService.get(player)
	local bag
	if data then
		data.questState = data.questState or {}
		bag = data.questState
	else
		session[player.UserId] = session[player.UserId] or {}
		bag = session[player.UserId]
	end
	for layer, count in Q.Slots do
		bag[layer] = bag[layer] or blankLayer(count)
	end
	return bag
end

-- Snapshots the counters the current quests read, so progress can be a
-- diff. Called when the period turns over, and once on first sight.
local function rollOver(player: Player, layer: string, bag)
	local quests, period = QuestService.assign(player.UserId, layer)
	local stats = Progress.statsOf(player)
	local entry = bag[layer]
	entry.period = period
	for i, quest in quests do
		entry.base[i] = if quest then (stats[quest.metric] or 0) else 0
		entry.claimed[i] = false
	end
	entry.reroll = false
	return quests
end

-- Everything the client needs to draw the panel.
function QuestService.snapshot(player: Player)
	local bag = stateFor(player)
	local stats = Progress.statsOf(player)
	local out = {}

	for layer in Q.Slots do
		local quests, period = QuestService.assign(player.UserId, layer)
		local entry = bag[layer]
		if entry.period ~= period then
			quests = rollOver(player, layer, bag)
		end

		local rows = {}
		for i, quest in quests do
			if quest then
				local have = (stats[quest.metric] or 0) - (entry.base[i] or 0)
				have = math.clamp(have, 0, quest.target)
				table.insert(rows, {
					slot = i,
					id = quest.id,
					text = quest.text,
					-- Sent so the client can add what it has counted but
					-- not yet reported. Not a secret: the client is the
					-- thing producing most of these numbers.
					metric = quest.metric,
					target = quest.target,
					have = have,
					done = have >= quest.target,
					claimed = entry.claimed[i] == true,
					bolt = quest.bolt,
					crystals = quest.crystals,
					xp = quest.xp,
				})
			end
		end
		out[layer] = { rows = rows, endsAt = QuestService.endsAt(layer), reroll = entry.reroll }
	end
	return out
end

-- When this layer's period rolls over, as a unix timestamp. The client
-- renders a countdown from it rather than being sent one every second.
function QuestService.endsAt(layer: string): number
	local now = os.time()
	if layer == "Daily" then
		return (math.floor(now / DAY) + 1) * DAY
	elseif layer == "Weekly" then
		return (weekNumber() + 1) * 7 * DAY + 4 * DAY
	end
	local d = os.date("!*t")
	local y, m = d.year, d.month + 1
	if m > 12 then
		y, m = y + 1, 1
	end
	return os.time({ year = y, month = m, day = 1, hour = 0, min = 0, sec = 0 })
end

--=====================================================================
--  CLAIM
--=====================================================================
function QuestService.claim(player: Player, layer: string, slot: number): boolean
	if not Q.Slots[layer] then
		return false
	end
	local bag = stateFor(player)
	local entry = bag[layer]
	local quests, period = QuestService.assign(player.UserId, layer)
	if entry.period ~= period then
		return false -- rolled over under them; nothing to claim
	end

	local quest = quests[slot]
	if not quest then
		return false
	end

	-- CHECKED AND MARKED IN ONE PLACE, before anything is granted. A
	-- claim that pays first and marks second pays twice on a double
	-- click, which is the idempotency rule from the data plan applied to
	-- the one path a client can reach.
	if entry.claimed[slot] then
		return false
	end

	local stats = Progress.statsOf(player)
	local have = (stats[quest.metric] or 0) - (entry.base[slot] or 0)
	if have < quest.target then
		return false
	end

	entry.claimed[slot] = true

	-- Through the single grant path, like everything else. The amounts
	-- come from config and never from the client.
	if quest.xp and quest.xp > 0 then
		Progress.award(player, quest.xp, "quest:" .. quest.id)
	end
	if quest.bolt and quest.bolt > 0 then
		Progress.grant(player, "bolt", quest.bolt, "quest:" .. quest.id)
	end
	if quest.crystals and quest.crystals > 0 then
		Progress.grant(player, "crystals", quest.crystals, "quest:" .. quest.id)
	end

	QuestService.push(player)
	return true
end

--=====================================================================
--  PUSH
--=====================================================================
function QuestService.push(player: Player)
	if remote then
		remote:FireClient(player, QuestService.snapshot(player))
	end
end

-- Players whose totals moved since the last push.
--
-- DEBOUNCED, not immediate: a single race fires hundreds of counter
-- changes and a push per change would be a snapshot rebuilt hundreds of
-- times for a panel that updates once a second at most.
local dirty: { [Player]: boolean } = {}

function QuestService.markDirty(player: Player)
	dirty[player] = true
end

function QuestService.start()
	buildPools()

	-- Progress tells us when a total moved. Without this the panel only
	-- ever refreshed on join and on claim, so a whole race of progress
	-- was invisible until the player rejoined — which reads exactly like
	-- quests not being wired up at all.
	Progress.onChanged = QuestService.markDirty

	task.spawn(function()
		while true do
			task.wait(1)
			for player in dirty do
				dirty[player] = nil
				if player.Parent == Players then
					QuestService.push(player)
				end
			end
		end
	end)

	remote = Instance.new("RemoteEvent")
	remote.Name = Names.QUEST_REMOTE
	remote.Parent = BloxKart
	QuestService.remote = remote

	remote.OnServerEvent:Connect(function(player, action, layer, slot)
		-- Intent only. The client says "claim daily 2" and never how much
		-- that is worth.
		if action == "claim" and typeof(layer) == "string" and typeof(slot) == "number" then
			QuestService.claim(player, layer, math.floor(slot))
		elseif action == "refresh" then
			QuestService.push(player)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		-- Delayed so the profile has a chance to load first; the snapshot
		-- falls back to the session table if it has not.
		task.delay(3, function()
			if player.Parent == Players then
				QuestService.push(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		session[player.UserId] = nil
		dirty[player] = nil
	end)
end

return QuestService
