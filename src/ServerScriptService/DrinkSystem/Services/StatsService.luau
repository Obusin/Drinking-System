-- StatsService: bartender XP + leveling.
--   Making drinks awards XP scaled by the grade (Perfect pays ~5x a Ruined),
--   finishing drinks awards a little. "Level" shows in the player list;
--   raw progress is exposed as player attributes for UI:
--     BartenderXP      — XP into the current level
--     BartenderXPGoal  — XP needed for the next level
-- Persisted via DataStore. Legacy Made/Drunk records migrate to XP once.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local StatsService = {}

-- v2: fresh ledger for the XP/level economy (v1 held raw Made/Drunk counters;
-- migrating them gave testers unearned head starts on the new curve)
local STORE_NAME = "DS_PlayerStats_v2"
local store = nil
pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
end)

-- Level cap + curve. Soft start, prestige-length tail:
--   L2 after 1 perfect · L10 ≈ 17 perfects · L50 ≈ 380 · L100 ≈ 1,570 ·
--   L250 (MAX) ≈ 10,500 perfect drinks (~420k XP lifetime).
local MAX_LEVEL = 250

local function xpGoalFor(level: number): number
	return math.floor(30 + 8 * math.max(level, 1) ^ 1.1)
end

type PlayerStats = {
	LevelValue: IntValue,
	XP: number,       -- XP into current level
	Made: number,     -- lifetime counters (kept in the save for future use)
	Drunk: number,
	Secrets: { [string]: boolean },  -- secret recipes discovered (one-time XP)
}

local statsByPlayer: { [Player]: PlayerStats } = {}
local onLevelUp: ((player: Player, newLevel: number) -> ())? = nil

local function pushAttributes(player: Player, stats: PlayerStats)
	if stats.LevelValue.Value >= MAX_LEVEL then
		-- Max level: bar reads full
		local goal = xpGoalFor(MAX_LEVEL)
		player:SetAttribute("BartenderXP", goal)
		player:SetAttribute("BartenderXPGoal", goal)
		return
	end
	player:SetAttribute("BartenderXP", math.floor(stats.XP))
	player:SetAttribute("BartenderXPGoal", xpGoalFor(stats.LevelValue.Value))
end

local function setupPlayer(player: Player)
	if statsByPlayer[player] then return end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local levelValue = Instance.new("IntValue")
	levelValue.Name = "Level"
	levelValue.Value = 1
	levelValue.Parent = leaderstats

	local stats: PlayerStats = {
		LevelValue = levelValue,
		XP = 0,
		Made = 0,
		Drunk = 0,
		Secrets = {},
	}
	statsByPlayer[player] = stats
	pushAttributes(player, stats)

	if store then
		task.spawn(function()
			local ok, data = pcall(function()
				return store:GetAsync("p" .. player.UserId)
			end)
			if not ok or type(data) ~= "table" then return end
			if not statsByPlayer[player] then return end -- left while loading

			if data.Level then
				levelValue.Value = tonumber(data.Level) or 1
				stats.XP = tonumber(data.XP) or 0
				stats.Made = tonumber(data.Made) or 0
				stats.Drunk = tonumber(data.Drunk) or 0
				stats.Secrets = type(data.Secrets) == "table" and data.Secrets or {}
			else
				-- Legacy record (Made/Drunk counters only): convert to XP once
				stats.Made = tonumber(data.Made) or 0
				stats.Drunk = tonumber(data.Drunk) or 0
				local totalXP = stats.Made * 15 + stats.Drunk * 5
				local level = 1
				while totalXP >= xpGoalFor(level) do
					totalXP -= xpGoalFor(level)
					level += 1
				end
				levelValue.Value = level
				stats.XP = totalXP
			end
			pushAttributes(player, stats)
		end)
	end
end

local function savePlayer(player: Player)
	local stats = statsByPlayer[player]
	if not stats or not store then return end
	local payload = {
		Level = stats.LevelValue.Value,
		XP = math.floor(stats.XP),
		Made = stats.Made,
		Drunk = stats.Drunk,
		Secrets = stats.Secrets,
	}
	pcall(function()
		store:SetAsync("p" .. player.UserId, payload)
	end)
end

local function grantXP(player: Player, amount: number)
	local stats = statsByPlayer[player]
	if not stats or amount <= 0 then return end
	if stats.LevelValue.Value >= MAX_LEVEL then return end
	stats.XP += amount
	local leveled = false
	while stats.LevelValue.Value < MAX_LEVEL and stats.XP >= xpGoalFor(stats.LevelValue.Value) do
		stats.XP -= xpGoalFor(stats.LevelValue.Value)
		stats.LevelValue.Value += 1
		leveled = true
	end
	if stats.LevelValue.Value >= MAX_LEVEL then
		stats.XP = 0
	end
	pushAttributes(player, stats)
	if leveled and onLevelUp then
		onLevelUp(player, stats.LevelValue.Value)
	end
end

---------------------------------------------------------------------
-- Anti-grind layers. Normal play never notices these; farming does.
--   1. VARIETY: repeating the same recipe decays its XP (resets over time —
--      mixing other recipes keeps you at full pay)
--   2. RATE: more than ~4 drinks a minute soft-caps further made-XP
--   3. SERVE PAIRS: the same friend finishing your drinks only pays the
--      serve bonus once per cooldown window
---------------------------------------------------------------------
local VARIETY_WINDOW = 240      -- seconds a repeat is remembered
local VARIETY_MULTS = { [0] = 1.0, [1] = 0.6, [2] = 0.35 }  -- ≥3 repeats → 0.2
local RATE_WINDOW = 60          -- seconds
local RATE_FREE = 4             -- drinks per window at full XP
local SERVE_PAIR_COOLDOWN = 180 -- seconds per maker↔drinker pair

local function pruneTimes(list: { number }, window: number, now: number)
	for i = #list, 1, -1 do
		if now - list[i] > window then
			table.remove(list, i)
		end
	end
end

local function madeMultiplier(stats, recipeName: string?): number
	local now = os.clock()

	-- Variety decay: how many times has THIS recipe been made recently?
	stats.RecentMakes = stats.RecentMakes or {}
	local repeats = 0
	for i = #stats.RecentMakes, 1, -1 do
		local entry = stats.RecentMakes[i]
		if now - entry.At > VARIETY_WINDOW then
			table.remove(stats.RecentMakes, i)
		elseif recipeName and entry.Recipe == recipeName then
			repeats += 1
		end
	end
	local varietyMult = VARIETY_MULTS[repeats] or 0.2

	-- Rate soft-cap: total drinks in the last minute
	stats.MakeTimes = stats.MakeTimes or {}
	pruneTimes(stats.MakeTimes, RATE_WINDOW, now)
	local rateMult = (#stats.MakeTimes < RATE_FREE) and 1.0 or 0.25

	table.insert(stats.RecentMakes, { Recipe = recipeName, At = now })
	table.insert(stats.MakeTimes, now)

	return varietyMult * rateMult
end

-- XP scaled by grade: Perfect(100) → 30 + 10 mastery bonus = 40,
-- Good(80) → 25, Weak(60) → 20, Ruined(0) → 5 — then anti-grind multipliers.
-- First-ever craft of a SECRET recipe pays a one-time +75 discovery bonus
-- (never dampened: it's one-time by definition).
function StatsService.awardDrinkMade(player: Player, score: number?, recipeName: string?, isSecret: boolean?)
	local stats = statsByPlayer[player]
	if not stats then return end
	stats.Made += 1
	local s = tonumber(score) or 0
	local xp = 5 + math.floor(s / 4)
	if s >= 90 then
		xp += 10 -- mastery bonus for a Perfect
	end
	xp = math.max(math.floor(xp * madeMultiplier(stats, recipeName)), 1)
	if isSecret and recipeName and not stats.Secrets[recipeName] then
		stats.Secrets[recipeName] = true
		xp += 75 -- secret discovered!
	end
	grantXP(player, xp)
end

function StatsService.awardDrinkDrunk(player: Player)
	local stats = statsByPlayer[player]
	if not stats then return end
	stats.Drunk += 1
	-- Same rate window as making: chugging a queue of drinks pays less
	local now = os.clock()
	stats.DrinkTimes = stats.DrinkTimes or {}
	pruneTimes(stats.DrinkTimes, RATE_WINDOW, now)
	local xp = (#stats.DrinkTimes < RATE_FREE) and 6 or 2
	table.insert(stats.DrinkTimes, now)
	grantXP(player, xp)
end

-- Service bonus: someone ELSE finished a drink you made. Each maker↔drinker
-- pair only pays once per cooldown so two friends can't ping-pong farm it,
-- and a GLOBAL cap stops alt-account swarms from scaling it linearly.
local SERVE_GLOBAL_WINDOW = 300 -- seconds
local SERVE_GLOBAL_MAX = 6      -- payouts per window regardless of who drinks

function StatsService.awardServe(player: Player, drinkerUserId: number?)
	local stats = statsByPlayer[player]
	if not stats then return end
	local now = os.clock()
	if drinkerUserId then
		stats.ServeFrom = stats.ServeFrom or {}
		local last = stats.ServeFrom[drinkerUserId]
		if last and (now - last) < SERVE_PAIR_COOLDOWN then
			return -- this pair already paid out recently
		end
		stats.ServeFrom[drinkerUserId] = now
	end
	stats.ServeTimes = stats.ServeTimes or {}
	pruneTimes(stats.ServeTimes, SERVE_GLOBAL_WINDOW, now)
	if #stats.ServeTimes >= SERVE_GLOBAL_MAX then
		return -- serve XP saturated for this window
	end
	table.insert(stats.ServeTimes, now)
	grantXP(player, 15)
end

-- Controller registers a celebration hook (level-up packet to the client)
function StatsService.setLevelUpHandler(handler: (player: Player, newLevel: number) -> ())
	onLevelUp = handler
end

function StatsService.init()
	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayer(player)
	end
	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(function(player)
		savePlayer(player)
		statsByPlayer[player] = nil
	end)
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			savePlayer(player)
		end
	end)
end

return StatsService
