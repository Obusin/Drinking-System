--[[
	BotService — AI racers.

	THEY DRIVE YOUR KART, NOT A COPY OF IT
	--------------------------------------
	Each bot owns a Simulation — the same module your client runs — and
	fills in the same five controls a keyboard does: throttle, steer,
	drift held, drift pressed, nitro taps. It has no special physics, no
	hidden top speed, and cannot corner harder than the kart allows.

	That's deliberate and it's the whole design. The usual way to make
	bots competitive is to cheat their handling, and it always shows:
	they hold lines no player can hold, and losing to one feels arbitrary
	rather than earned. Here a bot is quick only by driving well, and
	every mistake it makes is one you could have made.

	HOW THEY'RE BEATABLE
	--------------------
	By being imperfect, not by being throttled. Each bot rolls a skill
	once, and it scales: how early it lifts for a corner, how far off the
	ideal line it sits, how long it dithers before using an item, and how
	often it takes a drift it should have taken. A low-skill bot isn't a
	fast bot with a handicap — it is a worse driver.

	WHY THE SERVER
	--------------
	A bot has no client to run its simulation on. Which is also simpler:
	the server already owns their karts, so there's no ownership dance
	and no trust boundary to police.

	Their karts are UNANCHORED. An anchored part moved from a server loop
	replicates as bare position updates with no interpolation, and at 120
	studs/s that stutters — the same problem missiles had. Physics-
	replicated motion is interpolated for free.
--]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))
local Route = require(BloxKart:WaitForChild("Route"))
local Simulation = require(BloxKart:WaitForChild("Simulation"))
local Standings = require(BloxKart:WaitForChild("Standings"))
local Match = require(BloxKart:WaitForChild("Match"))
local Util = require(BloxKart:WaitForChild("Util"))
local KartService = require(script.Parent.KartService)
local MatchService = require(script.Parent.MatchService)
local RaceService = require(script.Parent.RaceService)
local ProjectileService = require(script.Parent.ProjectileService)
local Registry = require(BloxKart:WaitForChild("Items"))
local TagZones = require(BloxKart:WaitForChild("TagZones"))
local CollectionService = game:GetService("CollectionService")

local B = Config.Bots
local log = Util.logger("BotService", B.Debug)

local BotService = {}

local bots = {}
local rng = Random.new()
local warnedNoRoute = false
local warnedNoRig = false

--=====================================================================
--  CONTROLS
--
--  Exactly the shape Simulation expects off a keyboard. Nothing here
--  knows it's a bot, which is why a bot can't accidentally be given
--  abilities a player doesn't have.
--=====================================================================
local function newControls()
	return {
		touchThrottle = 0,
		touchSteer = 0,
		driftHeld = false,
		_driftPress = false,
		_nitroTaps = 0,

		consumeDriftPress = function(self)
			local p = self._driftPress
			self._driftPress = false
			return p
		end,
		consumeNitroTap = function(self)
			if self._nitroTaps > 0 then
				self._nitroTaps -= 1
				return true
			end
			return false
		end,
	}
end

-- Simulation calls these as plain functions, not methods, so they're
-- bound to their own table on creation.
local function bindControls(c)
	local press, nitro = c.consumeDriftPress, c.consumeNitroTap
	c.consumeDriftPress = function()
		return press(c)
	end
	c.consumeNitroTap = function()
		return nitro(c)
	end
	return c
end

--=====================================================================
--  READING THE ROAD
--=====================================================================

-- How sharply the road bends between here and `ahead` nodes on, 0..1.
-- Measured off the racing line rather than off the geometry, so it sees
-- a corner coming before the kart is in it.
local function bendAt(u: number, ahead: number, up: Vector3): number
	local a = Route.tangentAt(u)
	local b = Route.tangentAt(u + ahead)
	if not (a and b) then
		return 0
	end

	-- Flattened onto the surface first. A crest or a dip changes the
	-- tangent as much as a corner does, and a bot that brakes for every
	-- slope crawls up every hill — which looks exactly like being stuck.
	a = a - up * a:Dot(up)
	b = b - up * b:Dot(up)
	if a.Magnitude < 1e-4 or b.Magnitude < 1e-4 then
		return 0
	end

	-- 1 - dot maps "same direction" to 0 and "hairpin" to 1-ish.
	return math.clamp((1 - a.Unit:Dot(b.Unit)) * 0.5, 0, 1)
end

--=====================================================================
--  DEBUG
--
--  Draws what a bot has decided, because guessing at this has already
--  cost two rounds. Same idea as the missile's path lines, and for the
--  same reason: "it gets stuck" describes a dozen different causes.
--
--    white line   where it's steering
--    green        throttle, as a bar rising out of the roof
--    red          it thinks it's cornering, so it's braking
--
--  Debug parts are CanQuery and CanCollide off, or the debugging tool
--  becomes the bug.
--=====================================================================
-- THE RACING LINE ITSELF, drawn once.
--
-- Everything navigates by this — bots steer along it, missiles ride it,
-- wrong-way reads it. Until now it was invisible, so "it's taking
-- shortcuts" could mean the bot is cutting the line OR the line itself
-- cuts the corner. Those need completely different fixes and look
-- identical from the driving seat.
--
-- Blue balls are the checkpoints. The thin trail between them is the
-- spline the checkpoints produce, which is what anything actually
-- follows — if THAT goes through a wall, the fix is RouteTension or more
-- checkpoints, not bot tuning.
local lineParts: { BasePart } = {}
local lineNodeCount = -1

local function drawRacingLine()
	local nodes = Route.nodes()
	if #nodes == lineNodeCount then
		return
	end
	for _, p in lineParts do
		p:Destroy()
	end
	table.clear(lineParts)
	lineNodeCount = #nodes
	if #nodes == 0 then
		return
	end

	local function marker(at: Vector3, size: number, colour: Color3, ball: boolean)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = colour
		p.Transparency = 0.35
		p.Shape = if ball then Enum.PartType.Ball else Enum.PartType.Block
		p.Size = Vector3.one * size
		p.Position = at
		p.Parent = workspace
		table.insert(lineParts, p)
	end

	for i, node in nodes do
		marker(node.position + Vector3.yAxis * 2, 4, Color3.fromRGB(90, 170, 255), true)
		-- Sampled between nodes, so the CURVE is visible rather than
		-- guessed at from the checkpoints.
		for k = 1, 7 do
			local at = Route.pointAt(i - 1 + k / 8)
			if at then
				marker(at + Vector3.yAxis * 1.5, 1.1, Color3.fromRGB(255, 230, 120), false)
			end
		end
	end
	print(("[BotService] racing line drawn: %d checkpoints"):format(#nodes))
end

local function debugPart(bot, key: string, colour: Color3): BasePart
	local part = bot.dbg[key]
	if not part then
		part = Instance.new("Part")
		part.Name = "BotDbg_" .. key
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = colour
		part.Parent = workspace
		bot.dbg[key] = part
	end
	return part
end

local function drawDebug(bot, aim: Vector3?, bend: number)
	if not B.Debug then
		return
	end
	drawRacingLine()
	local from = bot.sim.pos

	local line = debugPart(bot, "aim", Color3.fromRGB(255, 255, 255))
	if aim then
		local span = aim - from
		line.Size = Vector3.new(0.3, 0.3, math.max(span.Magnitude, 0.1))
		line.CFrame = CFrame.lookAt(from + span * 0.5, aim)
		line.Transparency = 0.3
	else
		line.Transparency = 1
	end

	-- Throttle as a bar, so a bot crawling for no reason is obvious from
	-- across the track rather than from a log line.
	local bar = debugPart(bot, "throttle", Color3.fromRGB(90, 240, 130))
	local t = bot.controls.touchThrottle
	bar.Color = if bend > 0.2 then Color3.fromRGB(255, 90, 90) else Color3.fromRGB(90, 240, 130)
	bar.Size = Vector3.new(0.6, math.max(t, 0.05) * 8, 0.6)
	bar.CFrame = CFrame.new(from + bot.sim.up * (4 + math.max(t, 0.05) * 4))
	bar.Transparency = 0.2
end

local function clearDebug(bot)
	for _, part in bot.dbg do
		part:Destroy()
	end
	table.clear(bot.dbg)
end

--=====================================================================
--  DRIVING
--=====================================================================
local function drive(bot, dt: number)
	local sim = bot.sim
	local c = bot.controls

	-- Where we are on the racing line. Re-projected each step rather than
	-- integrated, so a bot that gets knocked off, spun or respawned finds
	-- its way back instead of steering at a point it has long passed.
	bot.u = Route.nearestU(sim.pos)

	local speed = math.abs(sim.speed)
	local bend = bendAt(bot.u, B.CornerLookahead, sim.up)

	----------------------------------------------------------------
	-- LINE
	--
	-- Not the centreline. Each bot holds an offset and wanders it, which
	-- is most of what makes them look driven rather than railed — and
	-- it's the reason there's room to overtake one.
	----------------------------------------------------------------
	bot.lineAt += dt * B.LineDrift
	local wander = math.sin(bot.lineAt) * B.LineOffset * (1 - bot.skill)
	local offset = bot.lineBias + wander

	----------------------------------------------------------------
	-- TRAFFIC
	--
	-- Karts pass THROUGH each other on purpose — that's what stops a
	-- race becoming a physics accident. But two bots sharing one racing
	-- line drive as a single overlapping lump, which reads as bumping
	-- even though nothing is colliding.
	--
	-- So they move over, which is what a driver does and costs one loop.
	----------------------------------------------------------------
	local sideways = sim.forward:Cross(sim.up)
	if sideways.Magnitude > 1e-4 then
		sideways = sideways.Unit
		for _, other in Standings.allKarts() do
			local hb = other.PrimaryPart
			if other ~= bot.kart and hb then
				local toward = hb.Position - sim.pos
				local dist = toward.Magnitude
				-- AHEAD only. Moving over for someone behind you is how you
				-- get rammed by them.
				if dist < B.AvoidRadius and dist > 1e-3 and toward:Dot(sim.forward) > 0 then
					local side = toward:Dot(sideways)
					-- Dead ahead has no side to pick, so the tie is broken by
					-- our own line bias rather than by rounding — two bots
					-- agreeing to dodge the same way is worse than neither
					-- dodging at all.
					local away = if math.abs(side) < 0.5 then -math.sign(bot.lineBias + 0.001) else -math.sign(side)
					offset += away * (1 - dist / B.AvoidRadius) * B.AvoidStrength
				end
			end
		end
	end

	----------------------------------------------------------------
	-- STEERING
	--
	-- Aim at a point up the road, offset onto our own line. Lookahead
	-- grows with speed: at 120 studs/s a fixed 18 studs is a seventh of
	-- a second of warning, which is not enough to turn on.
	----------------------------------------------------------------
	-- Shortened for a corner. A fixed lookahead aims at a point 50 studs
	-- up the road, and on a bend that point is across the apex — so the
	-- bot steers at it and cuts the corner. Every shortcut it takes is
	-- this number being too big for the bend it's in.
	local lookahead = (B.LookaheadBase + speed * B.LookaheadPerSpeed) * (1 - bend * B.LookaheadTighten)
	local aheadU = bot.u + lookahead / Route.segmentLength(bot.u)
	local aim = Route.pointAt(aheadU)
	if not aim then
		return
	end

	local tangent = Route.tangentAt(aheadU)
	if tangent then
		local across = tangent:Cross(sim.up)
		if across.Magnitude > 1e-4 then
			aim += across.Unit * offset
		end
	end

	-- Signed error across the kart's own right, so this stays correct
	-- sideways and upside-down on a loop.
	local toAim = aim - sim.pos
	local flat = toAim - sim.up * toAim:Dot(sim.up)
	local right = sim.forward:Cross(sim.up)
	local wantSteer = 0
	if flat.Magnitude > 1e-3 and right.Magnitude > 1e-4 then
		wantSteer = flat.Unit:Dot(right.Unit) * B.SteerGain
	end

	-- CROSS-TRACK ERROR. This is the actual fix for corner cutting, and
	-- shortening the lookahead never could be.
	--
	-- Chasing a point up the road ALWAYS cuts a corner: the straight line
	-- to that point lies inside the bend, so a bot steering at it drives
	-- inside the bend. That's inherent to the method, not a tuning
	-- problem — a shorter lookahead just makes the cut smaller.
	--
	-- So steer on two things. Where the road goes, and how far off the
	-- line we currently ARE. The second term has no opinion about the
	-- corner ahead; it simply refuses to be off the line, which is what
	-- holds the kart on the tarmac through an apex.
	local actualOffset = Route.lateralAt(bot.u, sim.pos, sim.up)
	wantSteer += math.clamp((offset - actualOffset) * B.LineCorrect, -1, 1)
	wantSteer = math.clamp(wantSteer, -1, 1)

	-- Slewed, not snapped. A bot that can flick to full lock in one frame
	-- corners in a way no player can, which reads as cheating even though
	-- the handling is identical.
	c.touchSteer = Util.approach(c.touchSteer, wantSteer, B.SteerSlew, dt)

	----------------------------------------------------------------
	-- THROTTLE
	--
	-- Lifts for corners. How early is skill: a poor bot brakes late,
	-- carries too much speed and runs wide, exactly like a poor driver.
	----------------------------------------------------------------
	local ease = bend * B.CornerBrake * (2 - bot.skill)
	c.touchThrottle = math.clamp(1 - ease, B.MinCornerSpeed, 1)

	drawDebug(bot, aim, bend)

	----------------------------------------------------------------
	-- DRIFTING
	--
	-- Same trigger a player uses: a corner sharp enough to be worth it,
	-- at a speed where it pays. Rolled once per corner so a bot doesn't
	-- take every single one — that's the difference between a rival and
	-- a metronome.
	----------------------------------------------------------------
	local wantsDrift = bend >= B.DriftBend and speed >= B.DriftMinSpeed

	if wantsDrift and not bot.driftDecided then
		bot.driftDecided = true
		bot.willDrift = rng:NextNumber() < B.DriftChance * bot.skill
	elseif not wantsDrift then
		bot.driftDecided = false
		bot.willDrift = false
	end

	local drifting = wantsDrift and bot.willDrift
	if drifting and not c.driftHeld then
		c._driftPress = true -- the hop, exactly as a keypress would
	end
	c.driftHeld = drifting

	----------------------------------------------------------------
	-- NITRO
	--
	-- Spent on straights, where a player would. Holding out for three
	-- full tanks is optimal and inhuman, so mostly they don't.
	----------------------------------------------------------------
	if sim.tanks >= B.NitroMinTanks and bend <= B.NitroStraight and sim.burnStage == 0 then
		if rng:NextNumber() > B.NitroHoldChance * (1 - bot.skill) then
			c._nitroTaps += 1
		end
	end
end

--=====================================================================
--  ITEMS
--
--  Bots use the same item modules players do, through a context shaped
--  like the client's. Anything a bot can do, a player can do — there is
--  no bot-only item behaviour to balance separately.
--=====================================================================
local function useItem(bot)
	local item = bot.item
	bot.item = nil
	if not item then
		return
	end

	local sim = bot.sim
	local back = rng:NextNumber() > B.ForwardChance

	local order = Standings.order(Standings.allKarts())
	local ctx = {
		sim = sim,
		kart = bot.kart,
		back = back,
		charge = rng:NextNumber(0.5, 1), -- never a perfect wind-up
		aheadOf = function(k)
			return Standings.ahead(order, k)
		end,
		victimOf = function(k)
			return if back then Standings.behind(order, k) else Standings.ahead(order, k)
		end,
		everyone = function()
			local out = {}
			local sign = if back then -1 else 1
			for _, k in Standings.allKarts() do
				local hb = k.PrimaryPart
				if k ~= bot.kart and hb and (hb.Position - sim.pos):Dot(sim.forward) * sign > 0 then
					table.insert(out, k)
				end
			end
			return out
		end,
		-- Server-side already, so these call the services directly rather
		-- than going out over a remote and straight back in.
		dropHazard = function(cf, itemId, power)
			BotService.dropHazard(bot, cf, itemId, back, power)
		end,
		fireProjectile = function(itemId)
			BotService.fireProjectile(bot, itemId, back)
		end,
		fire = function(target, payload)
			payload.item = item.Id
			BotService.hit(bot, target, payload)
		end,
	}

	local ok = item.Use(ctx)
	if ok == false then
		-- Couldn't fire — nobody in that direction. Keep it and try again
		-- shortly, exactly as a player would hold onto it.
		bot.item = item
		bot.itemAt = os.clock() + 1
	else
		log("%s used %s%s", bot.name, item.Id, if back then " (back)" else "")
	end
end

--=====================================================================
--  ACTIONS
--
--  Straight calls into the services rather than remotes: a bot is
--  already on the server, so going out over the network and back in
--  would be theatre.
--
--  Owner is passed as a NAME. A bot has no Player object, and nothing
--  downstream needs one — the feed wants something to print and the
--  hazard wants an owner id, which is 0 for a bot: nobody's, so every
--  racer can trigger it including the bot that laid it. Bots have no
--  client to be protected from their own traps.
--=====================================================================
function BotService.dropHazard(bot, cf: CFrame, itemId: string, back: boolean?, power: number?)
	local item = Registry.byId(itemId)
	if item and item.Hazard then
		RaceService.spawnHazard(0, cf, item, back, power)
	end
end

function BotService.fireProjectile(bot, itemId: string, back: boolean?)
	local item = Registry.byId(itemId)
	if item and item.Projectile then
		ProjectileService.fire(bot.kart, nil, item, back, bot.name)
	end
end

function BotService.hit(bot, target: Model, payload)
	if target and target ~= bot.kart then
		RaceService.relayHit(bot.name, target, payload)
	end
end

--=====================================================================
--  PICKUPS
--
--  Bots collect boxes and dropped items on the same terms as players:
--  the same tags, the same roll, the same three-slot limit. A bot
--  holding an item nobody could have got is the sort of thing players
--  notice long before they can prove it.
--=====================================================================
-- Driving into a mine, oil or a fake box. The victim detects its own
-- hazard hit — that's true for players and had to become true for bots.
local function checkHazards(bot)
	local hitbox = bot.kart.PrimaryPart
	if not hitbox then
		return
	end
	local hz = bot.hazards:Touch(hitbox.CFrame, hitbox.Size)
	if not hz then
		return
	end

	local item = Registry.byId(hz:GetAttribute(Names.HAZARD_ITEM) or "")
	if not item then
		return
	end

	local landed = bot.sim:Spinout(item.SpinTime, item.SpeedKeep, item.StunTime)
	if landed and (item.SpinTime or 0) > 0 then
		bot.item = nil
	end

	-- Whoever laid it gets the credit, exactly as when a player hits one.
	local ownerId = hz:GetAttribute(Names.OWNER)
	local owner = ownerId and ownerId ~= 0 and Players:GetPlayerByUserId(ownerId)
	RaceService.announce(item.Id, if owner then owner.DisplayName else nil, bot.name)
	hz:Destroy()
	log("%s drove into a %s", bot.name, item.Id)
end

local function collect(bot)
	if bot.item then
		return -- one at a time; a bot hoarding three is a bot you can't beat
	end
	local hitbox = bot.kart.PrimaryPart
	if not hitbox then
		return
	end

	local box = bot.drops:Touch(hitbox.CFrame, hitbox.Size) or bot.boxes:Touch(hitbox.CFrame, hitbox.Size)
	if not box then
		return
	end

	local item
	if CollectionService:HasTag(box, Config.Items.DropTag) then
		-- A dropped item grants exactly what it is.
		item = Registry.byId(box:GetAttribute(Names.DROP_ITEM) or "")
		if item then
			box:Destroy()
		end
	elseif not box:GetAttribute(Names.TAKEN) then
		local order = Standings.order(Standings.allKarts())
		local place, field = Standings.placeOf(order, bot.kart)
		item = Registry.roll(rng, place, field)
		if item then
			box:SetAttribute(Names.TAKEN, true)
			box.Transparency = 1
			box.CanQuery = false
			task.delay(Config.Items.RespawnTime, function()
				if box.Parent then
					box:SetAttribute(Names.TAKEN, false)
					box.Transparency = 0
					box.CanQuery = true
				end
			end)
		end
	end

	if item then
		bot.item = item
		-- Human-ish dithering before using it. The single biggest lever on
		-- how nasty they feel, and it's why they don't fire the instant a
		-- box is touched.
		bot.itemAt = os.clock() + rng:NextNumber(B.ItemDelayMin, B.ItemDelayMax) * (2 - bot.skill)
		log("%s picked up %s", bot.name, item.Id)
	end
end

--=====================================================================
--  STEP
--=====================================================================
local function step(dt: number)
	if #bots == 0 then
		return
	end
	local racing = Match.isDriving(MatchService.phase())
	local now = os.clock()

	for i = #bots, 1, -1 do
		local bot = bots[i]
		-- Kart gone entirely — fell past the destroy height, or something
		-- removed it. Rebuilt rather than dropped: a bot vanishing
		-- mid-race takes a rival out of the standings and leaves a gap
		-- nobody can explain.
		if not bot.kart.Parent then
			log("%s lost its kart — rebuilding", bot.name)
			BotService.revive(bot)
			continue
		end

		-- Held on the grid exactly like a player, so the countdown means
		-- the same thing for everybody.
		bot.sim:Hold(not racing)

		-- And placed on it. A player's own client applies GridCF; a bot
		-- has no client, so it does it here — once per round, watching the
		-- same attribute for the same reason.
		local grid = bot.kart:GetAttribute(Match.GRID_CF)
		if typeof(grid) == "CFrame" and grid ~= bot.grid then
			bot.grid = grid
			bot.sim:RespawnAt(grid)
			bot.sim:ResetForRound()
			bot.u = Route.nearestU(grid.Position)
			bot.lastU = nil
			bot.laps = 0
			bot.item = nil
		end

		-- Fell off the world, or ended up somewhere the road isn't. No
		-- character to re-seat, so it puts itself back on the racing line
		-- — which it already knows how to find.
		if bot.sim.pos.Y < Config.Rig.RespawnBelow then
			log("%s fell off and rejoined the line", bot.name)
			BotService.revive(bot)
		end

		local ok, err = pcall(function()
			if racing then
				drive(bot, dt)
				collect(bot)
				checkHazards(bot)
				if bot.item and now >= bot.itemAt then
					useItem(bot)
				end
				-- Laps, from the route wrapping rather than from trigger
				-- volumes: a bot is already tracked by `u`, so watching it
				-- wrap is free and can't miss a gate at speed.
				if bot.lastU and bot.u < bot.lastU - #Route.nodes() * 0.5 then
					bot.laps += 1
				end
				bot.lastU = bot.u
			end
			bot.sim:Step(dt, bot.controls)
		end)
		if not ok then
			warn("[BotService] " .. bot.name .. " step failed: " .. tostring(err))
		end

		-- One line a second per bot when debugging. A bot that has stopped
		-- says which of the three possible reasons it is: no throttle, no
		-- route, or wedged against something with throttle applied.
		if B.Debug and now >= (bot.nextLog or 0) then
			bot.nextLog = now + 1
			log(
				"%s u=%.1f spd=%.0f thr=%.2f steer=%+.2f %s",
				bot.name,
				bot.u or 0,
				bot.sim.speed,
				bot.controls.touchThrottle,
				bot.controls.touchSteer,
				if bot.sim.grounded then "" else "AIRBORNE"
			)
		end

		-- Progress, so bots appear in the standings and the missile's
		-- route entry. Written directly: the server owns these karts, so
		-- there's no report to relay.
		local nodes = #Route.nodes()
		if nodes > 0 then
			bot.kart:SetAttribute(Standings.ATTRIBUTE, Standings.score(bot.laps, math.floor(bot.u or 0), 0))
		end
		-- And its steering, so Rider turns the wheel and the front tyres.
		bot.kart:SetAttribute(Names.STEER, bot.sim.steer)
		bot.kart:SetAttribute(Names.DRIFT, bot.sim.driftAngle)
	end
end

--=====================================================================
--  LIFECYCLE
--=====================================================================
-- Tops the field up to FillTo. Refuses mid-race: adding a bot to a race
-- in progress puts a kart on the track from nowhere, and removing one
-- deletes a racer somebody may be about to overtake.
function BotService.fill()
	if Match.isDriving(MatchService.phase()) then
		return
	end
	-- No racing line, no bots. They steer along the checkpoint spline and
	-- there is nothing else for them to follow — spawned anyway they'd
	-- sit on the grid as statues, which reads as broken code rather than
	-- as a track that isn't finished.
	if #Route.nodes() == 0 then
		if #bots > 0 then
			for _, bot in bots do
				bot.boxes:Destroy()
				bot.drops:Destroy()
				bot.kart:Destroy()
			end
			table.clear(bots)
		end
		if not warnedNoRoute then
			warnedNoRoute = true
			warn("[BotService] no Checkpoint-tagged parts — bots have no racing line to follow, so none will spawn. Tag and number some checkpoints (see Kart/SETUP.md).")
		end
		return
	end
	warnedNoRoute = false

	local humans = #Players:GetPlayers()
	local want = math.clamp(B.FillTo - humans, 0, B.MaxBots)

	while #bots > want do
		local bot = table.remove(bots)
		bot.boxes:Destroy()
		bot.drops:Destroy()
		bot.hazards:Destroy()
		clearDebug(bot)
		if bot.rig then
			bot.rig:Destroy()
		end
		bot.kart:Destroy()
	end

	while #bots < want do
		local name = B.Names[(#bots % #B.Names) + 1] .. tostring(#bots + 1)
		local racer, kart = KartService.addBot(name)
		local hitbox = kart.PrimaryPart
		local seat = kart:FindFirstChild("Seat")
		if not (hitbox and seat) then
			warn("[BotService] built a kart with no hitbox or seat for " .. name)
			break
		end

		local bot = {
			name = name,
			racer = racer,
			kart = kart,
			sim = Simulation.new(kart, hitbox, seat),
			controls = bindControls(newControls()),
			-- One roll, and it scales everything. A low-skill bot is a
			-- worse driver, not a slower one.
			skill = rng:NextNumber(B.SkillMin, B.SkillMax),
			-- A fixed bias plus wander, so two bots don't drive the same
			-- line and sit inside each other down a straight.
			lineBias = rng:NextNumber(-1, 1) * B.LineOffset,
			lineAt = rng:NextNumber(0, 6),
			u = 0,
			laps = 0,
			driftDecided = false,
			willDrift = false,
			item = nil,
			itemAt = 0,
			lastU = nil,
			dbg = {},
			boxes = TagZones.new(Config.Items.BoxTag, { cooldown = Config.Items.PickupCooldown, forceQueryable = true }),
			drops = TagZones.new(Config.Items.DropTag, { cooldown = 0.5, forceQueryable = true }),
			-- Bots drove straight over mines and oil without noticing:
			-- hazards are detected by whoever hits them, and nothing was
			-- doing that on their behalf.
			hazards = TagZones.new(Config.Items.HazardTag, { cooldown = 0.5, forceQueryable = true }),
		}
		table.insert(bots, bot)
		BotService.seatRig(bot)
		log("%s joined, skill %.2f", name, bot.skill)
	end
end

-- Puts a bot back on the racing line, rebuilding its kart if that went
-- with it. One path for "fell off" and "kart destroyed", because from a
-- race's point of view they're the same event.
--=====================================================================
--  DRIVERS
--
--  A rig sat in the seat, so a bot looks like a racer rather than an
--  empty kart. Rider picks it up from there for free: it already puts
--  hands on the wheel for whoever is sitting in one, and doesn't care
--  whether they're a player.
--
--  Authored rather than generated: ServerStorage[Bots.RigName], any
--  model with a Humanoid. Without one bots drive empty karts, which is
--  a missing feature rather than a broken game.
--=====================================================================
function BotService.seatRig(bot)
	if bot.rig then
		bot.rig:Destroy()
		bot.rig = nil
	end
	if B.RigName == "" then
		return
	end

	local template = ServerStorage:FindFirstChild(B.RigName)
	if not (template and template:IsA("Model") and template:FindFirstChildOfClass("Humanoid")) then
		if not warnedNoRig then
			warnedNoRig = true
			warn(("[BotService] no Model named %q with a Humanoid in ServerStorage — bots will drive empty karts."):format(B.RigName))
		end
		return
	end

	local seat = bot.kart:FindFirstChild("Seat")
	local rig = template:Clone()
	rig.Name = bot.name
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	-- It never walks anywhere, and a rig that can stand up climbs out of
	-- the kart the first time anything jostles it.
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			-- Same group as the kart, so drivers never knock each other
			-- about as two karts pass.
			d.CollisionGroup = Config.Rig.CollisionGroup
			d.CanQuery = false
			-- Non-solid. A seated rig is welded to the kart, so a limb
			-- catching on scenery drags the whole kart to a stop — and
			-- limbs are CanCollide by default.
			d.CanCollide = false
			d.Massless = true
		end
	end

	rig.Parent = workspace
	rig:PivotTo(seat.CFrame)
	task.defer(function()
		if seat and seat.Parent and humanoid.Parent then
			seat:Sit(humanoid)
		end
	end)
	bot.rig = rig
end

function BotService.revive(bot)
	if not bot.kart.Parent then
		local _, kart = KartService.addBot(bot.name)
		bot.kart = kart
		local hitbox = kart.PrimaryPart
		local seat = kart:FindFirstChild("Seat")
		if not (hitbox and seat) then
			return
		end
		bot.sim = Simulation.new(kart, hitbox, seat)
		BotService.seatRig(bot)
	end

	local u = Route.nearestU(bot.sim.pos)
	local at = Route.pointAt(u)
	local tangent = Route.tangentAt(u)
	if at and tangent then
		bot.sim:RespawnAt(CFrame.lookAt(at + Vector3.yAxis * 5, at + tangent + Vector3.yAxis * 5))
		bot.u = u
		bot.lastU = nil
	end
end

--=====================================================================
--  BEING HIT
--
--  Registered with RaceService, which calls this when a hit lands on a
--  kart that has no Player behind it.
--
--  Without it every item landed on a bot and did nothing: the hit path
--  resolved a victim through GetPlayerByUserId, got nil, and dropped it.
--  Bots weren't AI, they were scenery — and the only way to find out was
--  to fire something at one.
--
--  No remote involved. Their Simulation is right here, so the effect is
--  applied to it directly.
--=====================================================================
function BotService.applyHit(kart: Model, effect): string?
	for _, bot in bots do
		if bot.kart == kart then
			local landed = bot.sim:Spinout(effect.spin, effect.keep, effect.stun)
			-- Scramble carries no spin, so Spinout reports nothing landed
			-- and the shield has to be asked separately.
			if effect.reverse and effect.reverse > 0 and not bot.sim:HasShield() then
				bot.sim:Scramble(effect.reverse)
				landed = true
			end
			-- Same rule as a player: a hit that SPINS you costs your stack.
			if landed and (effect.spin or 0) > 0 and bot.item then
				bot.item = nil
			end
			log("%s was hit by %s", bot.name, tostring(effect.item))
			return bot.name
		end
	end
	return nil
end

function BotService.all()
	return bots
end

function BotService.start()
	-- Filled when the field changes, NOT only at the start of a round.
	-- The match won't leave Waiting until there are enough racers, and
	-- bots are what make up the numbers — waiting for the grid to fill
	-- them in would mean a solo player waiting forever for a race that
	-- needs a bot that needs the race to start.
	Players.PlayerAdded:Connect(function()
		task.defer(BotService.fill)
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(BotService.fill)
	end)
	task.defer(BotService.fill)

	-- Stepped at StepRate rather than every frame. The controller is
	-- frame-rate independent by construction, so this changes nothing
	-- about how they drive — it halves the server's raycast load, which
	-- is the real limit on how many bots a race can hold.
	local accum = 0
	local interval = 1 / math.max(B.StepRate, 1)

	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < interval then
			return
		end
		step(accum)
		accum = 0
	end)
end

return BotService
