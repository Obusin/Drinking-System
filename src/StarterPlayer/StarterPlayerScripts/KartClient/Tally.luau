--[[
	Tally — the driving counters, collected over a race and sent once.

	Drifts, nitro, air time, items used, boxes, blocks: the server cannot
	see any of it. Movement is simulated on the client and items are used
	there, so the only thing that knows a drift boost happened is the
	machine it happened on.

	SO THE CLIENT REPORTS, AND THE SERVER CLAMPS.
	--------------------------------------------
	One batch at the flag rather than an event at a time. Three reasons,
	and the last is the one that matters:

	  1. One remote call per race instead of hundreds per minute.
	  2. A race is the natural unit — every cap is "per race" and every
	     quest counts things across races.
	  3. It bounds the lie. A per-event remote can be fired forever; a
	     per-race batch can be inflated only to the cap, once per race.

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
	local self = setmetatable({ n = {}, remote = nil, sent = false }, Tally)
	task.spawn(function()
		self.remote = BloxKart:WaitForChild(Names.STATS_REMOTE, 20)
	end)
	self:Reset()
	return self
end

function Tally:Reset()
	table.clear(self.n)
	self.sent = false
end

function Tally:Add(metric: string, by: number?)
	self.n[metric] = (self.n[metric] or 0) + (by or 1)
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

-- Once per race. `sent` guards it because the flag can be reported more
-- than once — a finish, then the round ending — and a second send would
-- count the whole race twice.
function Tally:Send()
	if self.sent or not self.remote then
		return
	end
	self.sent = true

	-- Derived at the flag rather than tracked all race: both of these
	-- are questions about the race as a whole, and asking once is
	-- cheaper and impossible to get out of step.
	if (self.n.respawns or 0) == 0 then
		self:Add("cleanRaces")
	end

	self.remote:FireServer(self.n)
end

return Tally
