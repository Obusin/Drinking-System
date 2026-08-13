--[[
	BotBrain — what the bots have learned about THIS track.

	A LOOKUP TABLE, NOT A MODEL. Four numbers per path node:

	    off    how often a bot left the road here
	    wall   how often a bot hit something here
	    slow   how often one took far too long to get through
	    clean  how often a bot got through without any of that

	61 nodes is 244 numbers, about 3 KB of JSON. There is no training,
	no inference and no runtime cost beyond a table index — the entire
	mechanism is `+= 1` on failure and `+= 1` on success.

	COLLECTIVE, NOT PER BOT. Eight bots on a track learn eight times
	faster than one, and a lesson that only one of them remembers is a
	lesson the field does not act on. The per-bot `caution` table stays as
	it is: that is a driver's own nerves within a race, and this is the
	circuit's reputation across all of them.

	PER PLACE. Keyed on `game.PlaceId`, so every map learns separately and
	nothing carries over from a track with different corners in different
	places. That is the whole reason it is keyed at all.

	WHY WALL HITS ARE TRACKED SEPARATELY FROM GOING OFF
	---------------------------------------------------
	They ask for different fixes and they were previously indistinguishable.

	Going off means the line was too wide — the answer is less road.
	Hitting a wall usually means the DRIFT was wrong for that corner, and
	the answer is not to drift there. Right now a bot that never drifts is
	quicker than one that does, which is exactly backwards: drifting is
	supposed to be the fast way round. It is not the drift that is slow,
	it is drifting into things.

	So a corner that keeps producing wall hits stops being drifted, and
	the bots that do drift get to keep the advantage everywhere else.

	AND WHY "SLOW" IS ITS OWN SIGNAL
	--------------------------------
	It is the only one that catches a bot which is not crashing, not off
	the road, not in the air, and not getting anywhere either — a tunnel
	or a rounded section where the lateral axis curves around the barrel
	and the racing line's personality sends it round instead of along.

	Nothing is wrong by any single-frame test. It is simply taking
	forever, and the only way to see that is to time it.

	The fix is not a better line, it is NO line: fall back to the centre
	of the path and drive it. Everything that makes a bot interesting is
	what got it stuck, so all of it is what gets turned down.

	IT IS CAPPED SO THEY STAY BEATABLE
	----------------------------------
	Confidence has a hard ceiling and is lost instantly on any incident.
	Slow to earn, immediate to lose — so bots converge on "clean and
	quick" rather than improving without limit. A bot that has run your
	track five hundred times is a few percent better than one that has
	not, and that is a property of the arithmetic rather than of tuning.
--]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))

local B = Config.Bots
local log = Util.logger("BotBrain", B.Debug)

type Cell = { off: number, wall: number, clean: number, slow: number }

local BotBrain = {}

local cells: { [number]: Cell } = {}
local dirty = false
local store: DataStore? = nil
local loaded = false
-- Did a read actually round-trip? `GetDataStore` succeeds in Studio even
-- with API access off — it is the first GetAsync that throws — so the
-- handle existing proves nothing. Without this, every round tried to
-- save and warned when it could not.
local available = false

--=====================================================================
--  STUDIO LEARNS SEPARATELY FROM LIVE, and that is deliberate.
--
--  A build session is not a race. You drive bots into walls on purpose,
--  half the track does not exist yet, and you restart mid-lap twenty
--  times an hour. All of that is evidence, and all of it is wrong —
--  writing it into the key live servers read would teach the real field
--  habits learned from a track that was never finished.
--
--  Same place, same code, separate memory. Turn it off only if you
--  specifically want a Studio session to train the live brain.
--=====================================================================
local function key(): string
	local suffix = if RunService:IsStudio() and B.LearnStudioSeparate then "_studio" else ""
	return ("bots_v1_%d%s"):format(game.PlaceId, suffix)
end

--=====================================================================
--  THE PATH'S SHAPE, STORED WITH THE LEARNING.
--
--  A node is identified by its INDEX along the path, not by its authored
--  Order — `math.floor(u)` is a position in a sorted array. So inserting
--  one BotPath node in the middle shifts every node after it, and every
--  lesson past that point silently reattaches to the WRONG corner.
--
--  While a map is being built that is not an edge case, it is Tuesday.
--  And it fails quietly: bots would drive a corner cautiously because of
--  something that happened somewhere else entirely, and nothing would
--  look broken.
--
--  So the node count is stored alongside, and learning that describes a
--  different path is discarded rather than misapplied. Moving a node is
--  fine — indices do not shift — which is why the count is enough.
--=====================================================================
local shape = -1

function BotBrain.reshape(nodes: number)
	if nodes <= 0 or shape == nodes then
		return
	end
	if shape >= 0 then
		warn(
			("[BotBrain] the path changed (%d nodes -> %d). Learning is indexed by position along the path, so every lesson past the edit would now describe a different corner — discarded rather than misapplied."):format(
				shape,
				nodes
			)
		)
		table.clear(cells)
		dirty = true
	end
	shape = nodes
end

local function cell(node: number): Cell
	local c = cells[node]
	if not c then
		c = { off = 0, wall = 0, clean = 0, slow = 0 }
		cells[node] = c
	end
	return c
end

--=====================================================================
--  LOAD / SAVE
--
--  Failure is not fatal anywhere here. A track with no saved brain is a
--  track the bots have not driven yet, which is the same thing an empty
--  table means — so a DataStore that is down costs nothing but the
--  memory of previous sessions.
--=====================================================================
function BotBrain.load()
	if loaded or not B.LearnEnabled then
		return
	end
	loaded = true
	-- Studio has no DataStore access unless it is switched on, and a
	-- pcall here keeps a local playtest from erroring on line one.
	local ok, result = pcall(function()
		store = DataStoreService:GetDataStore("BloxKartBots")
		return store:GetAsync(key())
	end)
	if not ok then
		-- Almost always Studio with API access off. Not an error: bots
		-- still learn within the session, it just is not written down.
		log("datastore unavailable (%s) — bots will learn this session only", key())
		return
	end
	available = true
	if typeof(result) ~= "table" then
		log("no saved brain for %s — starting fresh", key())
		return
	end

	local n = 0
	-- Read the stored shape first, so a path that has changed since the
	-- save is caught before a single lesson is loaded from it.
	local savedShape = if typeof(result.shape) == "table" then tonumber(result.shape.off) else nil
	if savedShape then
		shape = savedShape
	end

	for k, v in result do
		local node = tonumber(k)
		if node and typeof(v) == "table" then
			cells[node] = {
				off = tonumber(v.off) or 0,
				wall = tonumber(v.wall) or 0,
				clean = tonumber(v.clean) or 0,
				slow = tonumber(v.slow) or 0,
			}
			n += 1
		end
	end
	log("loaded %d node(s) from %s", n, key())
end

function BotBrain.save()
	if not (B.LearnEnabled and dirty and store and available) then
		return
	end
	local blob = { shape = { off = shape, wall = 0, clean = 0, slow = 0 } }
	local count = 0
	for node, c in cells do
		count += 1
		-- Rounded on the way out. These are counts of incidents, and
		-- storing them to fourteen decimal places is bytes spent on noise.
		blob[tostring(node)] = {
			off = math.floor(c.off * 100) / 100,
			wall = math.floor(c.wall * 100) / 100,
			clean = math.floor(c.clean * 100) / 100,
			slow = math.floor(c.slow * 100) / 100,
		}
	end
	local ok, err = pcall(function()
		store:SetAsync(key(), blob)
	end)
	if ok then
		dirty = false
		log("saved %d node(s)", count)
	else
		warn("[BotBrain] save failed: " .. tostring(err))
	end
end

--=====================================================================
--  REPORTING
--=====================================================================
-- FORWARD DECLARED. The reporting functions below call this, and it is
-- defined further down beside the readers whose thresholds it compares
-- against. Without the declaration those calls would resolve to a nil
-- global at runtime — which the type checker does catch, and which is
-- the same shape as every other "attempt to call a nil value" this
-- project has hit.
local announce: (node: number) -> ()
-- FORGETTING IS PART OF LEARNING, and here it is the part that matters
-- most: you will edit this map. A corner that was lethal before you
-- widened it would otherwise be treated as lethal forever, and the bots
-- would crawl round a piece of road that is now fine.
--
-- Every incident ages the whole node slightly, so old evidence loses to
-- new evidence without anything having to detect that the track changed.
local function age(c: Cell)
	c.off *= B.LearnDecay
	c.wall *= B.LearnDecay
	c.clean *= B.LearnDecay
	c.slow *= B.LearnDecay
end

function BotBrain.wentOff(node: number)
	if not B.LearnEnabled then
		return
	end
	local c = cell(node)
	age(c)
	c.off = math.min(c.off + 1, B.LearnMax)
	dirty = true
	announce(node)
end

function BotBrain.hitWall(node: number)
	if not B.LearnEnabled then
		return
	end
	local c = cell(node)
	age(c)
	c.wall = math.min(c.wall + 1, B.LearnMax)
	dirty = true
	announce(node)
end

-- TOOK FAR TOO LONG TO GET THROUGH THIS ONE.
--
-- The most useful signal there is, because it is the only one that
-- catches a bot that is not crashing, not off the road, not in the air,
-- and not making progress either — the tunnel case. Nothing is WRONG by
-- any single-frame test; it is simply taking forever.
--
-- Reported per crossing and compared against how long the segment should
-- take at a reasonable speed, so a long straight is not flagged for
-- being long.
function BotBrain.wasSlow(node: number)
	if not B.LearnEnabled then
		return
	end
	local c = cell(node)
	age(c)
	c.slow = math.min(c.slow + 1, B.LearnMax)
	dirty = true
	announce(node)
end

-- A PERSON GOT THROUGH THIS CLEANLY.
--
-- Worth more than a bot doing it, because a player choosing a line and
-- carrying speed through a corner is proof it works — bots spend ninety
-- laps discovering what a good driver demonstrates on their second.
--
-- CREDITED INTO THE SAME COUNTER, not a parallel one. A second channel
-- would need its own ceiling, its own decay and its own collapse rule,
-- and the two could then disagree about the same corner. This just
-- advances the existing apprenticeship faster.
--
-- The physics clamp is what makes it safe to accept at all: confidence
-- only ever raises the corner margin TOWARD `vLimit`, which is derived
-- from the kart's own steering model on the server. Even a wildly wrong
-- observation cannot ask for a corner speed the kart could not hold.
function BotBrain.playerPass(node: number)
	if not (B.LearnEnabled and B.LearnFromPlayers) then
		return
	end
	local c = cell(node)
	c.clean = math.min(c.clean + B.LearnPlayerWorth, B.LearnMax)
	dirty = true
	announce(node)
end

function BotBrain.gotThrough(node: number)
	if not B.LearnEnabled then
		return
	end
	local c = cell(node)
	c.clean = math.min(c.clean + 1, B.LearnMax)
	dirty = true
	announce(node)
end

--=====================================================================
--  READING
--=====================================================================
-- 0..1. How much this node has hurt bots, against how often they have
-- got through it. A corner nobody has ever driven returns 0, which is
-- "no opinion" rather than "safe" — the per-bot caution still has to
-- learn it the hard way the first time.
--=====================================================================
--  THE LEARNING LOG — what shows up on F4.
--
--  STATE CHANGES, NOT EVERY INCIDENT. "Bot hit a wall" happens hundreds
--  of times a session and answers nothing: the question is not whether
--  bots crash, it is whether crashing is CHANGING anything. So a line is
--  written when a node crosses a threshold and the bots' behaviour there
--  actually differs from a minute ago.
--
--  That also keeps it out of the way. The audit ring is bounded and
--  shared with security records; flooding it with telemetry would push
--  real events out of the window they are needed in.
--=====================================================================
local flags: { [number]: { drift: boolean, tame: boolean, conf: boolean } } = {}

local function note(msg: string, data: any)
	-- Required lazily. DevAudit must not depend on anything here, and
	-- keeping the edge one-way is what stops a require cycle.
	local ok, DevAudit = pcall(function()
		return require(script.Parent.DeveloperConsole.DevAudit)
	end)
	if ok and DevAudit then
		DevAudit.record(
			{ userId = 0, name = "BotBrain", role = "system" },
			"learn",
			true,
			"OK",
			data,
			msg
		)
	end
	log("%s", msg)
end

-- Called after any incident. Compares what the bots WOULD do at this
-- node now against what they would have done before, and says so only
-- when the answer moved.
announce = function(node: number)
	local was = flags[node] or { drift = true, tame = false, conf = false }
	local c = cells[node]
	if not c then
		return
	end
	local now = {
		drift = BotBrain.driftOkAt(node),
		tame = BotBrain.tameAt(node) > B.LearnTameAt,
		conf = BotBrain.confidenceAt(node) > 0,
	}

	if now.drift ~= was.drift then
		note(
			("node %d: drifting %s (wall %.1f vs clean %.1f)"):format(
				node,
				if now.drift then "ALLOWED again" else "VETOED",
				c.wall,
				c.clean
			),
			{ node = node, wall = c.wall, clean = c.clean }
		)
	end
	if now.tame ~= was.tame then
		note(
			("node %d: %s (slow %.1f vs clean %.1f)"):format(
				node,
				if now.tame then "TAMED — driving the centre here" else "back to the racing line",
				c.slow,
				c.clean
			),
			{ node = node, slow = c.slow, clean = c.clean }
		)
	end
	if now.conf ~= was.conf then
		note(
			("node %d: %s"):format(
				node,
				if now.conf
					then ("CONFIDENT +%.0f%%"):format(BotBrain.confidenceAt(node) * 100)
					else "confidence lost"
			),
			{ node = node, clean = c.clean }
		)
	end
	flags[node] = now
end

local function ratio(hits: number, clean: number): number
	local total = hits + clean
	if total < B.LearnMinSamples then
		return 0
	end
	return math.clamp(hits / total, 0, 1)
end

-- How much to distrust this node's ROAD WIDTH. Feeds the same place the
-- per-bot caution does, so the two add rather than compete.
function BotBrain.dangerAt(node: number): number
	local c = cells[node]
	if not c then
		return 0
	end
	return ratio(c.off, c.clean)
end

-- SHOULD A BOT DRIFT HERE? Wall hits are the signal, because that is
-- what a badly chosen drift produces — the kart goes sideways into
-- something rather than off the edge.
--
-- This is the fix for "a bot that does not drift is faster than one that
-- does". It is not the drifting that is slow, it is drifting into
-- things, and the two were previously the same number.
function BotBrain.driftOkAt(node: number): boolean
	local c = cells[node]
	if not c then
		return true
	end
	return ratio(c.wall, c.clean) < B.LearnDriftVeto
end

-- A SMALL SPEED BONUS where they have repeatedly got through cleanly,
-- and this is the only thing that makes bots FASTER than stock.
--
-- Hard-capped, and it collapses to zero the moment the node has any
-- meaningful incident rate — slow to earn, instant to lose. That
-- asymmetry, not a tuning value, is what stops them becoming
-- unbeatable: the ceiling is `LearnConfidenceMax` and nothing can climb
-- past it however many laps are run.
-- DRIVE THIS ONE STRAIGHT. 0..1.
--
-- High where bots have repeatedly taken too long to get through, which
-- in practice means a rounded or enclosed section where the racing line's
-- personality — the bias, the wander, a dodge — sends them round the
-- barrel instead of down it.
--
-- The answer is not a better line, it is NO line: fall back to the
-- centre of the path and just drive it. Everything that makes a bot
-- interesting is what got it stuck here, so all of it is what gets
-- turned down.
function BotBrain.tameAt(node: number): number
	local c = cells[node]
	if not c then
		return 0
	end
	return ratio(c.slow, c.clean)
end

function BotBrain.confidenceAt(node: number): number
	local c = cells[node]
	if not c then
		return 0
	end
	local hurt = ratio(c.off + c.wall + c.slow, c.clean)
	if hurt > B.LearnConfidenceSpoil then
		return 0
	end
	local runs = math.clamp(c.clean / B.LearnConfidenceRuns, 0, 1)
	return runs * B.LearnConfidenceMax
end

-- WHAT HAS BEEN LEARNED, worst first. For the dev console — the whole
-- point of a learner you cannot inspect is that you cannot tell whether
-- it is learning or just accumulating.
--
-- Sorted by how much trouble a node causes, because a list of 61 nodes
-- in index order is data and the first five worst is an answer.
function BotBrain.summary(limit: number?): { any }
	local rows = {}
	for node, c in cells do
		local total = c.off + c.wall + c.slow + c.clean
		if total > 0 then
			table.insert(rows, {
				node = node,
				off = c.off,
				wall = c.wall,
				slow = c.slow,
				clean = c.clean,
				danger = BotBrain.dangerAt(node),
				tame = BotBrain.tameAt(node),
				drift = BotBrain.driftOkAt(node),
				confidence = BotBrain.confidenceAt(node),
			})
		end
	end
	table.sort(rows, function(a, b)
		return (a.off + a.wall + a.slow) > (b.off + b.wall + b.slow)
	end)
	local out = {}
	for i = 1, math.min(#rows, limit or 12) do
		table.insert(out, rows[i])
	end
	return out
end

-- Is anything actually being written down? The question the console is
-- really being asked.
function BotBrain.status(): any
	local nodes, incidents, cleans = 0, 0, 0
	for _, c in cells do
		nodes += 1
		incidents += c.off + c.wall + c.slow
		cleans += c.clean
	end
	return {
		key = key(),
		persisted = available,
		enabled = B.LearnEnabled,
		nodes = nodes,
		incidents = incidents,
		cleans = cleans,
		unsaved = dirty,
	}
end

-- HOW FAR THROUGH LEARNING THIS TRACK IS, 0..1.
--
-- Averaged over every node the path HAS, not every node that happens to
-- have a row — otherwise a track where one corner is fully learned and
-- sixty are untouched reports 100%, which is the opposite of useful.
function BotBrain.progress(pathNodes: number): number
	if pathNodes <= 0 then
		return 0
	end
	local sum = 0
	for node = 0, pathNodes - 1 do
		local c = cells[node]
		if c then
			-- Against the runs needed for FULL confidence, so the bar
			-- fills as the thing it is measuring actually completes.
			sum += math.clamp(c.clean / B.LearnConfidenceRuns, 0, 1)
		end
	end
	return sum / pathNodes
end

-- THE BAR, AS A STRING. Shared by the console command and the periodic
-- print, so the two can never describe the same state differently.
function BotBrain.bar(pathNodes: number, cells: number?): string
	local done = BotBrain.progress(pathNodes)
	local n = cells or 20
	local filled = math.floor(done * n + 0.5)
	return ("[%s] %3.0f%%"):format(string.rep("#", filled) .. string.rep("-", n - filled), done * 100)
end

--=====================================================================
--  PRINTS ITSELF, so you can start a server and walk away.
--
--  The console command answers "how is it going" when asked. This is for
--  the other case, which is the actual one: leave twenty bots running
--  for an hour and glance at Output now and then. Having to type
--  something to find out whether waiting is working defeats the point of
--  waiting.
--
--  Only prints when the number has MOVED. A line every thirty seconds
--  saying the same thing trains you to stop reading it, and the whole
--  value here is that a change catches your eye.
--=====================================================================
local lastShown = -1

function BotBrain.report(pathNodes: number)
	if not B.LearnEnabled or pathNodes <= 0 then
		return
	end
	local done = math.floor(BotBrain.progress(pathNodes) * 100)
	if done == lastShown then
		return
	end
	lastShown = done
	local nodes, incidents, cleans = 0, 0, 0
	for _, c in cells do
		nodes += 1
		incidents += c.off + c.wall + c.slow
		cleans += c.clean
	end
	print(
		("[BotBrain] %s learned  ·  %d/%d node(s) touched  ·  %d incident(s)  ·  %d clean  ·  %s"):format(
			BotBrain.bar(pathNodes),
			nodes,
			pathNodes,
			incidents,
			cleans,
			if available then "saving" else "session only"
		)
	)
end

function BotBrain.wipe()
	table.clear(cells)
	dirty = true
	log("wiped")
end

-- A round is minutes long and a save is one request, so this is nowhere
-- near the DataStore budget. BindToClose covers a server shutting down
-- between rounds, which is where a session's learning would otherwise be
-- lost entirely.
function BotBrain.start()
	if not B.LearnEnabled then
		return
	end
	BotBrain.load()
	if not RunService:IsStudio() then
		game:BindToClose(function()
			BotBrain.save()
		end)
	end
end

return BotBrain
