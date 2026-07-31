--[[
	MatchService — the round loop. The server decides when a race starts
	and when it's over; clients only report crossing the line.

		Waiting  →  Intermission  →  Grid  →  Racing  →  Results  →  ⤾

	WHY THE SERVER OWNS THIS
	------------------------
	Everything else in the kart is client-owned on purpose: the
	simulation has to run on the machine holding the input or it can't
	feel right. But "has the race started" cannot be a client's opinion
	— two clients disagreeing about that is two different races. So the
	server owns phase, the grid, and the finish order, and the client
	owns only how the kart moves between the lights and the line.

	This is also the seam where finish times get validated. Right now a
	reported time is trusted; see recordFinish.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Match = require(BloxKart:WaitForChild("Match"))
local Util = require(BloxKart:WaitForChild("Util"))
local KartService = require(script.Parent.KartService)

local M = Config.Match
local P = Match.Phase
local log = Util.logger("MatchService", M.Debug)

local MatchService = {}

local state: Folder
local finishRemote: RemoteEvent
local readyRemote: RemoteEvent

local phase = P.Waiting
local endsAt = 0
local round = 0
local finishers = 0 -- how many have crossed the line this round
local ready: { [Player]: boolean } = {}

--=====================================================================
--  PUBLISHING
--
--  One write per field, and only when it changes — every SetAttribute
--  is a replication event to every client.
--=====================================================================
local function racerCount(): number
	local n = 0
	for _ in KartService.allKarts() do
		n += 1
	end
	return n
end

-- Racers with a person behind them. The field can be mostly bots, and
-- anything asking "is everyone ready" means everyone who can answer.
local function humanRacers(): number
	local n = 0
	for _, player in Players:GetPlayers() do
		if KartService.kartFor(player) then
			n += 1
		end
	end
	return n
end

-- Players who have left still sit in `ready` until PlayerRemoving fires;
-- checking Parent means a leaver can never make the lobby look readier
-- than it is.
local function readyCount(): number
	local n = 0
	for player in ready do
		if player.Parent then
			n += 1
		end
	end
	return n
end

local function publish()
	local racers = racerCount()
	local readied = readyCount()

	if state:GetAttribute(Match.PHASE) ~= phase then
		state:SetAttribute(Match.PHASE, phase)
	end
	if state:GetAttribute(Match.ENDS_AT) ~= endsAt then
		state:SetAttribute(Match.ENDS_AT, endsAt)
	end
	if state:GetAttribute(Match.RACERS) ~= racers then
		state:SetAttribute(Match.RACERS, racers)
	end
	if state:GetAttribute(Match.READY) ~= readied then
		state:SetAttribute(Match.READY, readied)
	end
	if state:GetAttribute(Match.ROUND) ~= round then
		state:SetAttribute(Match.ROUND, round)
	end
end

--=====================================================================
--  PHASES
--=====================================================================
local function enter(next: string, duration: number?)
	phase = next
	endsAt = if duration and duration > 0 then workspace:GetServerTimeNow() + duration else 0
	log("→ %s%s", next, if duration then (" (%.1fs)"):format(duration) else "")
	publish()
end

-- Wipe last round's finish attributes. Done on entering the grid rather
-- than on leaving results, so a late joiner watching the board still
-- sees the previous round's places until the next one actually starts.
local function clearFinishes()
	for _, kart in KartService.allKarts() do
		kart:SetAttribute(Match.FINISH_PLACE, nil)
		kart:SetAttribute(Match.FINISH_TIME, nil)
	end
	finishers = 0
end

-- Mines and oil left on the track when the last round ended. Their own
-- lifetimes would eventually get them, but "eventually" can be after the
-- next race has started, and a hazard nobody dropped this round is just
-- an unexplained spinout.
local function clearHazards()
	for _, hz in CollectionService:GetTagged(Config.Items.HazardTag) do
		hz:Destroy()
	end
end

local function startGrid()
	round += 1
	-- Topped up before the grid is assigned, so new bots get a slot and a
	-- start position with everybody else.
	if MatchService.onGrid then
		MatchService.onGrid()
	end
	clearFinishes()
	clearHazards()
	table.clear(ready)
	-- Stamps every kart with where it starts. The client applies it —
	-- the hitbox is network-owned by the driver, so the server moving it
	-- would just be overwritten on the next client frame.
	KartService.assignGrid()
	enter(P.Grid, M.GridTime)
end

--=====================================================================
--  FINISHING
--=====================================================================
local function recordFinish(player: Player, totalTime: number)
	if phase ~= P.Racing then
		return
	end
	local kart = KartService.kartFor(player)
	if not kart then
		return
	end
	-- Already in. Re-reporting is either lag or a client trying to claim
	-- a better place.
	if kart:GetAttribute(Match.FINISH_PLACE) then
		return
	end

	-- TODO: validate. The server knows when Racing began, so a time
	-- shorter than the phase has been running is provably fake, and the
	-- progress relay already tells us whether they ever reached the last
	-- checkpoint. Both belong here, in this function, before the
	-- attribute is written.
	finishers += 1
	kart:SetAttribute(Match.FINISH_PLACE, finishers)
	kart:SetAttribute(Match.FINISH_TIME, totalTime)
	log("%s finished P%d in %.2fs", player.Name, finishers, totalTime)

	if finishers == 1 then
		-- The leader is home. Everyone else is on the clock now, so the
		-- round can't be held open by someone parked on the track.
		local grace = math.min(M.FinishGrace, Match.timeLeft(endsAt))
		endsAt = workspace:GetServerTimeNow() + grace
		publish()
	end

	if finishers >= racerCount() then
		-- Everyone's in; don't sit through the grace period.
		endsAt = workspace:GetServerTimeNow() + M.FinishSettle
		publish()
	end
end

--=====================================================================
--  TICK
--
--  One timer, checked a few times a second. A match state machine has
--  no business running per-frame.
--=====================================================================
local function tick()
	local racers = racerCount()

	if phase == P.Waiting then
		if racers >= M.MinRacers then
			enter(P.Intermission, M.IntermissionTime)
		else
			publish() -- keep the racer count live so the HUD can say "1/2"
		end
		return
	end

	-- Everyone left mid-round. Nothing to race.
	if racers < M.MinRacers and phase ~= P.Results then
		enter(P.Waiting)
		return
	end

	if phase == P.Intermission then
		-- Ready is compared against the HUMANS, not the field. Bots have
		-- no way to press ready and are always willing, so counting them
		-- as unready made the skip impossible to satisfy the moment any
		-- bot existed — one human in a five-kart lobby could never start
		-- early, and it looked like the button had stopped working.
		local waiting = humanRacers()
		local everyoneReady = M.AllowReadySkip and waiting > 0 and readyCount() >= waiting
		if everyoneReady or Match.timeLeft(endsAt) <= 0 then
			startGrid()
		else
			publish()
		end
	elseif phase == P.Grid then
		if Match.timeLeft(endsAt) <= 0 then
			enter(P.Racing, M.TimeLimit)
		end
	elseif phase == P.Racing then
		if Match.timeLeft(endsAt) <= 0 then
			enter(P.Results, M.ResultsTime)
		end
	elseif phase == P.Results then
		if Match.timeLeft(endsAt) <= 0 then
			if racers >= M.MinRacers then
				enter(P.Intermission, M.IntermissionTime)
			else
				enter(P.Waiting)
			end
		end
	end
end

--=====================================================================
--  START
--=====================================================================
function MatchService.start()
	state = Instance.new("Folder")
	state.Name = Match.FOLDER
	state.Parent = BloxKart

	finishRemote = Instance.new("RemoteEvent")
	finishRemote.Name = Match.FINISH_REMOTE
	finishRemote.Parent = BloxKart

	readyRemote = Instance.new("RemoteEvent")
	readyRemote.Name = Match.READY_REMOTE
	readyRemote.Parent = BloxKart

	finishRemote.OnServerEvent:Connect(function(player, totalTime)
		if typeof(totalTime) ~= "number" or totalTime ~= totalTime or totalTime < 0 then
			return -- NaN, negative, or not a number at all
		end
		recordFinish(player, totalTime)
	end)

	readyRemote.OnServerEvent:Connect(function(player)
		if phase ~= P.Intermission then
			return
		end
		ready[player] = true
		publish()
	end)

	Players.PlayerRemoving:Connect(function(player)
		ready[player] = nil
	end)

	enter(P.Waiting)

	task.spawn(function()
		while true do
			local ok, err = pcall(tick)
			if not ok then
				-- A match loop that dies leaves the game permanently stuck
				-- in one phase with no error anyone would notice.
				warn("[MatchService] tick failed: " .. tostring(err))
			end
			task.wait(0.2)
		end
	end)
end

-- Set by BotService, so MatchService needn't know bots exist — it just
-- gives whoever cares a moment before the grid is laid out.
MatchService.onGrid = nil

function MatchService.phase(): string
	return phase
end

return MatchService
