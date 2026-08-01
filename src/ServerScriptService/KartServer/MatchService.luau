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
local Names = require(BloxKart:WaitForChild("Names"))
local Place = require(BloxKart:WaitForChild("Place"))
-- For the progress attribute, which has to be cleared with the finish
-- attributes or a new round starts holding the last one's scores.
local Standings = require(BloxKart:WaitForChild("Standings"))
local Util = require(BloxKart:WaitForChild("Util"))
local KartService = require(script.Parent.KartService)
local KartFactory = require(script.Parent.KartFactory)
local Progress = require(script.Parent.Progress)

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

-- THE ROUND'S RESULTS, kept here rather than read off the karts.
--
-- The board used to be rebuilt from live karts at the flag. That worked
-- only while karts survived to the end of the round, and they no longer
-- do: a racer retires a few seconds after finishing, so by the time the
-- results appear the earliest finishers have left the world entirely —
-- the winner would be missing from their own results screen.
--
-- A record written when it happens cannot be lost by cleaning up the
-- thing it describes.
type Result = {
	place: number?,
	name: string,
	time: number?,
	score: number,
	userId: number?,
	dnf: boolean?,
}

local results: { Result } = {}
local racingStartedAt = 0 -- server clock when the lights went out
local ready: { [Player]: boolean } = {}

--=====================================================================
--  PUBLISHING
--
--  One write per field, and only when it changes — every SetAttribute
--  is a replication event to every client.
--=====================================================================
-- Karts that have not crossed the line. The only honest way to ask "is
-- the race over", because it counts what is LEFT rather than comparing
-- two numbers that move independently.
local function stillRacing(): number
	local n = 0
	for _, kart in KartService.allKarts() do
		if not kart:GetAttribute(Match.FINISH_PLACE) then
			n += 1
		end
	end
	return n
end

local function racerCount(): number
	local n = 0
	for _ in KartService.allKarts() do
		n += 1
	end
	return n
end

-- Racers with a person behind them. The field can be mostly bots, and
-- anything asking "is everyone ready" means everyone who can answer.
-- PEOPLE WHO CAN RACE, which is not the same as people holding a kart.
--
-- A finisher is retired a few seconds after crossing the line: kart
-- destroyed, avatar despawned. Counting karts therefore reported ZERO
-- humans the moment a solo player finished, the round fell back to
-- Waiting, and the only thing that hands avatars back runs on the way
-- OUT of Intermission — which Waiting could never reach without a
-- human. The player sat at "0 / 1" with nothing able to spawn them.
--
-- Someone between lives is still someone.
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
	local humans = humanRacers()
	if state:GetAttribute(Match.HUMANS) ~= humans then
		state:SetAttribute(Match.HUMANS, humans)
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
-- Sent to each player as the flag drops. ONLY the things the client
-- cannot work out for itself: it already rebuilds standings from the
-- replicated finish attributes, and sending those again would be the
-- same board described twice.
local function sendRewards()
	if not MatchService.reward then
		return
	end

	-- WHO THE BOARD THINKS RACED. Logged because "the results only
	-- showed bots" cannot be diagnosed from the code — every path sets a
	-- name, so the question is which racers were in the list at all, and
	-- that is only answerable from a round where it happened.
	local board = MatchService.standings()
	local who = {}
	for _, r in board do
		table.insert(who, tostring(r.name) .. (if r.userId then "" else " [bot]"))
	end
	log("results: %d racer(s) — %s", #board, table.concat(who, ", "))
	for _, player in Players:GetPlayers() do
		MatchService.reward:FireClient(player, {
			level = Progress.summary(player),
			xpGained = Progress.since(player),
			-- Anyone who never finished is still out there when the flag
			-- drops. They are added here, at the
			-- one moment the whole field is known, rather than tracked
			-- alongside the record and kept in step with it.
			standings = board,
		})
	end
end

-- The finishers in order, then everyone still running when the flag
-- dropped, ordered by how far they got.
function MatchService.standings(): { Result }
	local out: { Result } = {}
	for _, r in results do
		table.insert(out, r)
	end

	local running: { Result } = {}
	for _, kart in KartService.allKarts() do
		if not kart:GetAttribute(Match.FINISH_PLACE) then
			table.insert(running, {
				name = kart:GetAttribute(Names.RACER_NAME) or "Racer",
				score = kart:GetAttribute(Standings.ATTRIBUTE) or 0,
				userId = kart:GetAttribute(Names.OWNER),
				dnf = true,
			})
		end
	end
	table.sort(running, function(a, b)
		return a.score > b.score
	end)
	for _, r in running do
		table.insert(out, r)
	end
	return out
end

local function enter(next: string, duration: number?)
	phase = next
	endsAt = if duration and duration > 0 then workspace:GetServerTimeNow() + duration else 0
	-- Stamped on the way in, so anything measuring elapsed race time reads
	-- it from here rather than keeping a second copy.
	if next == P.Racing then
		racingStartedAt = workspace:GetServerTimeNow()
	end
	-- Marked at the grid and diffed at the flag, so "+N XP this race" is
	-- one subtraction rather than a second running total to keep in step.
	if next == P.Grid then
		-- Every row written from here on is traceable to this race.
		-- Server time plus the round number, so it is unique across
		-- servers without needing anything to hand one out.
		Progress.matchId = ("%d_%d"):format(math.floor(workspace:GetServerTimeNow()), round)
		for _, player in Players:GetPlayers() do
			Progress.mark(player)
		end
	elseif next == P.Results then
		-- Hand every remaining kart to the AI before the board goes up.
		-- Nobody needs to be driving once the race is decided, and a
		-- player steering blind behind a results panel is the opposite of
		-- an ending.
		if MatchService.onResults then
			MatchService.onResults()
		end
		sendRewards()
	end
	log("→ %s%s", next, if duration then (" (%.1fs)"):format(duration) else "")

	-- THE LOOP, IN ONE LINE PER TRANSITION.
	--
	-- Every number here decides something: `people` gates every phase
	-- change, `karts` is what racerCount compares against, `finishers`
	-- is what ends a race early, and `bots` is what fill trims. A round
	-- that misbehaves is diagnosable from these without reading a line
	-- of code — which is how it should have been done from the start
	-- rather than after the sixth downstream fix.
	if M.LoopTrace then
		local karts, mine = 0, 0
		for racer in KartService.allKarts() do
			karts += 1
			if typeof(racer) == "Instance" then
				mine += 1
			end
		end
		print(
			("[Loop] %-12s round %d | people %d | karts %d (%d player) | finishers %d | results %d"):format(
				next,
				round,
				humanRacers(),
				karts,
				mine,
				finishers,
				#results
			)
		)
	end

	publish()
end

-- Wipe last round's finish attributes. Done on entering the grid rather
-- than on leaving results, so a late joiner watching the board still
-- sees the previous round's places until the next one actually starts.
local function clearFinishes()
	for _, kart in KartService.allKarts() do
		kart:SetAttribute(Match.FINISH_PLACE, nil)
		kart:SetAttribute(Match.FINISH_TIME, nil)
		-- AND THE PROGRESS SCORE, which used to be left behind.
		--
		-- It was harmless while progress reports overwrote whatever was
		-- there. It stopped being harmless the moment those reports
		-- started refusing to move a score BACKWARDS: last round's score
		-- would sit on the kart, every fresh report from the new race
		-- would be lower and therefore rejected, and the standings would
		-- be frozen on the previous round for the rest of the server's
		-- life.
		kart:SetAttribute(Standings.ATTRIBUTE, nil)
	end
	table.clear(results)
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

	-- A new spread of colours each race. Every racer still gets one
	-- nobody else has — it is an offset, not a shuffle — so this buys
	-- variety across races without costing distinctness within one.
	if Config.Skins.RotatePaintPerRound then
		KartFactory.paintOffset = round
	end
	-- RELEASE FIRST, then top up. Karts handed to the AI last round are
	-- still counted as bots until they're given back, so filling the
	-- field before releasing them would size it against a bot count that
	-- is about to shrink — and a player would line up in a kart the
	-- server is still driving.
	if MatchService.onRelease then
		MatchService.onRelease()
	end
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
-- Takes a KART, not a player.
--
-- This split is what lets a bot win. Finishing used to be reachable only
-- through the client remote below, and a bot has no client — so however
-- fast one drove, it could never cross the line, never take a place, and
-- never end the round. Bots weren't losing races; they were not entered
-- in them.
--
-- Same counter, same attributes, same grace-period logic for everybody.
-- A separate bot path would drift out of step with this one, and the
-- whole point is that a bot's win is the same object as yours.
local function finishKart(kart: Model, who: string, totalTime: number)
	if phase ~= P.Racing or not kart then
		return
	end
	-- Already in. Re-reporting is either lag or a client trying to claim
	-- a better place.
	if kart:GetAttribute(Match.FINISH_PLACE) then
		return
	end

	finishers += 1
	kart:SetAttribute(Match.FINISH_PLACE, finishers)
	kart:SetAttribute(Match.FINISH_TIME, totalTime)
	log("%s finished P%d in %.2fs", who, finishers, totalTime)

	-- Resolved from the kart rather than taken from `who`, so both
	-- routes in — the client remote and the bot one — pay through the
	-- same line. A bot resolves to nil and earns nothing, which is
	-- correct and is exactly the "assumes a Player behind the kart"
	-- shape this project keeps rediscovering. Stated so nobody fixes it.
	local ownerId = kart:GetAttribute(Names.OWNER)
	local owner = ownerId and Players:GetPlayerByUserId(ownerId)
	if owner then
		-- THEIR BOARD, NOW. It goes up a few seconds after this and was
		-- being built with no payload at all — no level, no XP, and a
		-- currency row reading zero, because the only send was at the
		-- flag. Sent here as well so a personal finish has real numbers
		-- on it.
		--
		-- Deferred by a frame: Progress.finished below is what awards
		-- the placement XP, and a board sent before it would show the
		-- total from before they crossed the line.
		task.defer(function()
			if MatchService.reward and owner.Parent then
				MatchService.reward:FireClient(owner, {
					level = Progress.summary(owner),
					xpGained = Progress.since(owner),
					standings = MatchService.standings(),
				})
			end
		end)
		-- The grid slot comes along so "finish 3 places above where you
		-- started" is answered by the server, which is the only thing
		-- that knows where you started.
		Progress.finished(owner, finishers, kart:GetAttribute(Match.GRID_SLOT))
	end

	-- The AI takes the kart over for whatever is left of the round, so
	-- the people still racing keep a full field to fight through instead
	-- of watching rivals park on the track as they finish.
	--
	-- A hook rather than a require: MatchService is upstream of
	-- BotService and shouldn't learn it exists. Same pattern as onGrid.
	if MatchService.onFinished then
		MatchService.onFinished(kart, who)
	end

	table.insert(results, {
		place = finishers,
		name = who,
		time = totalTime,
		score = kart:GetAttribute(Standings.ATTRIBUTE) or 0,
		userId = kart:GetAttribute(Names.OWNER),
	})

	-- NOBODY RETIRES ANY MORE, and this is a deletion rather than a fix.
	--
	-- Retiring a finished racer destroyed their kart, and every problem
	-- of the last day came out of that one idea: the respawn at the
	-- spawn point, the deadlock at 0/1, the missing kart, the race
	-- ending a lap in, the ghost registry entries. Each was a real bug
	-- and each was downstream of a feature nothing needed.
	--
	-- The trace settled it: at the flag the board reported "karts 2 (0
	-- player)". The player's kart had been destroyed before their own
	-- results appeared, which is why spectating had nothing to hold and
	-- why the kart kept vanishing.
	--
	-- A finished kart stays and the AI drives it, exactly as it does
	-- between crossing the line and the flag. It goes back to its owner
	-- at the next grid through releaseTakeOvers, which was always the
	-- plan for a taken-over kart.
	--
	-- The one thing retirement was FOR — a finished bot lapping the
	-- field twice more — is worth less than a kart that stays where it
	-- is, and is better solved by a bot that stops racing than by one
	-- that stops existing.

	if finishers == 1 then
		-- The leader is home. Everyone else is on the clock now, so the
		-- round can't be held open by someone parked on the track.
		local grace = math.min(M.FinishGrace, Match.timeLeft(endsAt))
		endsAt = workspace:GetServerTimeNow() + grace
		publish()
	end

	-- IS ANYBODY STILL RACING?
	--
	-- This used to be `finishers >= racerCount()`, and retirement broke
	-- it: a finished kart is destroyed five seconds later and leaves the
	-- registry, so racerCount FALLS while finishers climbs. Four
	-- finishers against four remaining karts reads as "everyone is in"
	-- while four people are still driving — the race ending a lap in.
	--
	-- Counting who is LEFT cannot drift that way. A kart that has gone
	-- is not still racing, whether it finished, retired or was never
	-- there.
	if stillRacing() == 0 then
		-- Everyone's in; don't sit through the grace period.
		endsAt = workspace:GetServerTimeNow() + M.FinishSettle
		publish()
	end
end

-- The client's route in. Resolves the kart, then goes through the same
-- door as everyone else.
--
-- This function went missing in a revert while its call site below
-- survived, so every finish raised "attempt to call a nil value" inside
-- the remote handler. Nothing was ever recorded, `finishers` never left
-- zero, and the round could only ever end on the time limit — which is
-- exactly "the match doesn't end even though everyone finished".
--
-- TODO: validate. The server knows when Racing began, so a time shorter
-- than the phase has been running is provably fake, and the progress
-- relay already says whether they reached the last checkpoint. Both
-- belong HERE, on the path a client can reach, and deliberately not in
-- finishKart, which the server calls for bots and trusts.
local function recordFinish(player: Player, totalTime: number)
	local kart = KartService.kartFor(player)
	if kart then
		finishKart(kart, player.Name, totalTime)
	end
end

-- The server's route in, for racers with nobody at a keyboard.
function MatchService.botFinished(kart: Model, name: string, totalTime: number)
	finishKart(kart, name, totalTime)
end

-- When the lights went out, so BotService can time a lap without keeping
-- its own copy of the phase clock. A second copy is a second thing to
-- get wrong.
function MatchService.racingSince(): number?
	return if phase == P.Racing then racingStartedAt else nil
end

--=====================================================================
--  TICK
--
--  One timer, checked a few times a second. A match state machine has
--  no business running per-frame.
--=====================================================================
local function tick()
	-- GATED ON PEOPLE, NOT KARTS. A round exists because somebody is
	-- here to race it; the bots are the field, not the reason.
	--
	-- Counting karts deadlocked a solo lobby: bots spawn at the grid,
	-- the grid is only reached from Intermission, and Intermission
	-- required a kart count nothing could raise without bots.
	local people = humanRacers()

	if phase == P.Waiting then
		if people >= M.MinRacers then
			enter(P.Intermission, M.IntermissionTime)
		else
			publish() -- keep the count live so the HUD can say "0 / 1"
		end
		return
	end

	-- Everyone left mid-round. Nothing to race — and an empty server
	-- must not keep running rounds for bots nobody is watching.
	if people < M.MinRacers and phase ~= P.Results then
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
			if people >= M.MinRacers then
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

	-- Server -> client only. Nothing is listened for on it: the client
	-- has no business telling the server what it earned.
	local reward = Instance.new("RemoteEvent")
	reward.Name = Names.REWARD_REMOTE
	reward.Parent = BloxKart
	MatchService.reward = reward

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
-- Called when a racer crosses the line, so their kart can be handed to
-- the AI for the rest of the round, and when the grid is next assigned
-- so it can be handed back. Declared here rather than only assigned in
-- init.server, so the contract is visible from the file that calls them.
MatchService.onFinished = nil
MatchService.onRelease = nil
-- Called as the flag drops, before the board is sent.
MatchService.onResults = nil :: (() -> ())?

function MatchService.phase(): string
	return phase
end

-- MAY ITEMS BE PICKED UP AND USED RIGHT NOW?
--
-- On a track: only while a round is actually running. The rule exists
-- so nobody hoovers up every box during the intermission and arrives on
-- the grid holding a full stack.
--
-- In a LOBBY there is no grid to arrive at and no round to stockpile
-- for, so the rule has nothing to protect and items are simply live.
-- The hub is where you practise with them.
--
-- ONE function rather than the same condition written at each of the
-- three gates. It was already three copies of `Match.isDriving(phase)`,
-- and three copies of a rule is three chances to update two of them.
function MatchService.itemsLive(): boolean
	return Place.isLobby() or Match.isDriving(phase)
end

return MatchService
