--[[
	Tally — the driving counters, collected over a race and sent once.

	Drifts, nitro, air time, items used, boxes, blocks: the server cannot
	see any of it. Movement is simulated on the client and items are used
	there, so the only thing that knows a drift boost happened is the
	machine it happened on.

	SO THE CLIENT REPORTS, AND THE SERVER CLAMPS.
	--------------------------------------------
	DELTAS, on a slow timer and again at the flag. Not one batch per
	event, and not one batch per race either — a single batch at the end
	meant a quest bar sat frozen for a whole race and then jumped, which
	reads exactly like quests being unwired.

	Each send carries only what has happened since the last one, so
	sending five times a race totals the same as sending once.

	  1. A handful of remote calls per race rather than hundreds a
	     minute.
	  2. Progress that visibly moves while you play, which is the entire
	     point of showing it.
	  3. It still bounds the lie: the server clamps the CUMULATIVE total
	     per race, so more frequent sends buy an exploiter nothing.

	None of that makes it TRUSTED. `Config.Level.StatCaps` is a bound on
	how wrong it can be, not a proof that it is right, and it holds only
	while none of this persists. The real fix is the same one the finish
	time needs, and it is written down in the vault.

	Nothing here decides anything. It counts, and it forgets at the grid.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))

local HANDLING = Config.Handling

local Tally = {}
Tally.__index = Tally

function Tally.new()
	local self = setmetatable({ n = {}, sent = {}, unacked = {}, remote = nil, finalised = false }, Tally)
	task.spawn(function()
		self.remote = BloxKart:WaitForChild(Names.STATS_REMOTE, 20)
	end)
	self:Reset()
	return self
end

function Tally:Reset()
	table.clear(self.n)
	table.clear(self.sent)
	table.clear(self.unacked)
	self.finalised = false
end

function Tally:Add(metric: string, by: number?)
	self.n[metric] = (self.n[metric] or 0) + (by or 1)
end

--=====================================================================
--  WHAT THE PANEL SHOWS
--
--  NOT PREDICTION. The client is the thing that counts drifts, laps and
--  items, so it is not guessing at a number the server owns — it is
--  showing the part of its own count that has not been reported yet.
--  Confirmed plus in-flight, and the two cannot disagree because they
--  come from the same source.
--
--  That distinction matters: a predicted value can be WRONG and has to
--  be reconciled, with a bar that visibly snaps when it is. This one
--  cannot be wrong, so nothing ever snaps.
--
--  `unacked` is the piece that stops it going BACKWARDS. Between
--  sending a delta and the server's next push, the amount has left
--  `pending` but has not yet appeared in the server's figure. Held here
--  until a push arrives, so the total is continuous across the gap.
--=====================================================================
function Tally:Pending(metric: string): number
	local total = math.floor(self.n[metric] or 0)
	local sent = self.sent[metric] or 0
	return (total - sent) + (self.unacked[metric] or 0)
end

-- Called when a server snapshot arrives: everything sent before it is
-- assumed to be in that figure now.
function Tally:Acked()
	table.clear(self.unacked)
end

--=====================================================================
--  PER-FRAME SAMPLING
--
--  Durations, not counts. Sampled rather than event-driven because
--  "seconds at top speed" has no event to hang off — it is a property
--  of every frame, and asking each frame is both simpler and exact.
--=====================================================================
function Tally:Sample(dt: number, sim)
	if not sim then
		return
	end
	-- Time actually on track, which is what "spend 5 minutes racing"
	-- means. Counted from having a simulation at all rather than from
	-- the phase clock: sitting in the lobby is not racing.
	self:Add("raceSeconds", dt)
	if sim.drifting then
		self:Add("driftSeconds", dt)
	end
	if not sim.grounded then
		self:Add("airSeconds", dt)
	end
	-- "At top speed" is a band, not an equality. A kinematic kart sits a
	-- hair under MaxSpeed almost all the time, so an exact test would
	-- read zero forever.
	if sim.speed >= HANDLING.MaxSpeed * 0.97 then
		self:Add("topSpeedSeconds", dt)
	end
end

--=====================================================================
--  EVENTS
--
--  Every one of these already fires. Nothing new is being detected
--  here; it was simply going nowhere.
--=====================================================================
function Tally:Drive(events)
	if events.boostFired then
		self:Add("driftBoosts")
		-- The top tier specifically. Rewards drifting WELL rather than
		-- drifting more, which is the difference between a quest that
		-- improves you and one that slows you down.
		if events.boostFired >= 3 then
			self:Add("driftTier3")
		end
	end
	if events.driftStarted then
		self:Add("drifts")
	end
	if events.tankFilled then
		self:Add("nitroTanks")
	end
	if events.nitroStage and events.nitroStage > 0 then
		self:Add("nitroBurns")
	end
	if events.landed then
		self:Add("landings")
	end
end

function Tally:Items(itemEvents)
	if itemEvents.used then
		self:Add("itemsUsed")
		-- Per item, so "use 10 Missiles" is possible without a second
		-- counting path. `used` IS the item id — it comes straight from
		-- the catalogue.
		if typeof(itemEvents.used) == "string" and itemEvents.used ~= "" then
			self:Add("itemsUsed_" .. itemEvents.used)
		end
	end
	if itemEvents.dropped then
		self:Add("hazardsDropped")
	end
	if itemEvents.blocked then
		-- Shield actually stopping something. The only defensive stat in
		-- the game, and it was already being announced to nobody.
		self:Add("shieldBlocks")
	end
	if itemEvents.gained then
		self:Add("itemBoxes", itemEvents.gained)
	end
end

function Tally:Lap(lapEvents)
	if lapEvents.checkpoint then
		self:Add("checkpoints")
	end
	if lapEvents.lapDone then
		self:Add("laps")
	end
	if lapEvents.bestLap then
		self:Add("bestLap")
	end
	if lapEvents.bestLap then
		self:Add("bestLap")
	end
end

function Tally:Pad()
	self:Add("boostPads")
end

function Tally:Respawned()
	self:Add("respawns")
end

--=====================================================================
--  SEND
--=====================================================================

-- Sends what has changed since the last send. Safe to call as often as
-- you like: what has already gone up is remembered, so a metric is
-- never reported twice.
function Tally:Flush()
	if not self.remote then
		return
	end

	local delta = nil
	for metric, total in self.n do
		local already = self.sent[metric] or 0
		-- Whole units only. Durations accumulate in fractions of a
		-- second and the server floors anyway; carrying the remainder
		-- here is what stops a 0.4s-per-frame drift never adding up.
		local whole = math.floor(total) - already
		if whole > 0 then
			delta = delta or {}
			delta[metric] = whole
			self.sent[metric] = already + whole
			-- Still shown until the server's next push accounts for it,
			-- or the bar dips by exactly this much in the meantime.
			self.unacked[metric] = (self.unacked[metric] or 0) + whole
		end
	end

	if delta then
		self.remote:FireServer(delta)
	end
end

-- The flag. Adds the things that are only true of a whole race, then
-- flushes the remainder.
--
-- `finalised` guards the once-per-race parts, because the end of a race
-- can be reported more than once — a finish, then the round ending —
-- and a second pass would count them twice.
function Tally:Send()
	if not self.finalised then
		self.finalised = true
		-- Derived at the flag rather than tracked all race: this is a
		-- question about the race as a whole, and asking once is cheaper
		-- and impossible to get out of step.
		if (self.n.respawns or 0) == 0 then
			self:Add("cleanRaces")
		end
	end
	self:Flush()
end

return Tally
