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
	-- STEERING
	--
	-- Aim at a point up the road, offset onto our own line. Lookahead
	-- grows with speed: at 120 studs/s a fixed 18 studs is a seventh of
	-- a second of warning, which is not enough to turn on.
	----------------------------------------------------------------
	local lookahead = B.LookaheadBase + speed * B.LookaheadPerSpeed
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
		wantSteer = math.clamp(flat.Unit:Dot(right.Unit) * B.SteerGain, -1, 1)
	end

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

		-- The kart is UNANCHORED so its motion replicates smoothly, which
		-- means Roblox physics is also acting on it — and it runs at 60Hz
		-- while bots step at 30. Left alone, gravity accumulates between
		-- our writes and walks the kart into the floor and off the map.
		--
		-- Writing the velocity we actually have does two jobs: it
		-- overwrites whatever physics accumulated, and it gives clients
		-- something to interpolate along between updates.
		local hitbox = bot.kart.PrimaryPart
		if hitbox then
			hitbox.AssemblyLinearVelocity = bot.sim.travel * bot.sim.speed + bot.sim.up * bot.sim.vertVel
			hitbox.AssemblyAngularVelocity = Vector3.zero
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
			boxes = TagZones.new(Config.Items.BoxTag, { cooldown = Config.Items.PickupCooldown, forceQueryable = true }),
			drops = TagZones.new(Config.Items.DropTag, { cooldown = 0.5, forceQueryable = true }),
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
