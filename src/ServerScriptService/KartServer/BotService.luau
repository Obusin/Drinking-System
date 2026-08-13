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
local BotBrain = require(script.Parent.BotBrain)
local MatchService = require(script.Parent.MatchService)
local RaceService = require(script.Parent.RaceService)
local ProjectileService = require(script.Parent.ProjectileService)
local Registry = require(BloxKart:WaitForChild("Items"))
local TagZones = require(BloxKart:WaitForChild("TagZones"))
local CollectionService = game:GetService("CollectionService")

local B = Config.Bots
local H = Config.Handling
local M = Config.Match
local log = Util.logger("BotService", B.Debug)

local BotService = {}

local bots = {}
local rng = Random.new()
local avatarDescriptions = {}
local avatarDescriptionFailed = {}
local avatarNames = {}
local avatarNameFailed = {}

local function botAvatarUserIdForSlot(slot: number): number?
	local pool = B.AvatarPool
	if type(pool) ~= "table" or #pool == 0 then
		return nil
	end

	local raw = pool[(slot % #pool) + 1]
	if type(raw) == "number" then
		return raw
	end
	if type(raw) == "table" and type(raw.userId) == "number" then
		return raw.userId
	end
	return nil
end

local function avatarNameFor(userId: number): string?
	if avatarNames[userId] then
		return avatarNames[userId]
	end
	if avatarNameFailed[userId] then
		return nil
	end

	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" and name ~= "" then
		avatarNames[userId] = name
		return name
	end

	avatarNameFailed[userId] = true
	warn(("[BotService] could not resolve bot avatar name for userId %d: %s"):format(userId, tostring(name)))
	return nil
end

local function avatarDescriptionFor(userId: number): HumanoidDescription?
	if avatarDescriptions[userId] then
		return avatarDescriptions[userId]
	end
	if avatarDescriptionFailed[userId] then
		return nil
	end

	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(userId)
	end)
	if ok and typeof(description) == "Instance" and description:IsA("HumanoidDescription") then
		avatarDescriptions[userId] = description
		return description
	end

	avatarDescriptionFailed[userId] = true
	warn(("[BotService] could not load bot avatar description for userId %d: %s"):format(userId, tostring(description)))
	return nil
end

local function publishBotIdentity(bot)
	if not (bot.kart and bot.kart.Parent) then
		return
	end
	bot.kart:SetAttribute(Names.RACER_NAME, bot.name)
	if bot.avatarUserId then
		bot.kart:SetAttribute(Names.BOT_AVATAR_USER_ID, bot.avatarUserId)
	else
		bot.kart:SetAttribute(Names.BOT_AVATAR_USER_ID, nil)
	end
end

-- The simulation still applies every item effect. This marker only keeps
-- the resulting forced trajectory out of route-learning evidence.
local function markExternalInterference(bot, duration: number, source: string)
	if duration <= 0 then
		return
	end
	local total = duration + B.LearnExternalGrace
	bot.externalInterferenceUntil = math.max(bot.externalInterferenceUntil or 0, os.clock() + total)
	bot.segmentExternallyDisrupted = true
	log("%s learning paused for %.1fs after %s", bot.name, total, source)
end

local function learningInterrupted(bot): boolean
	return bot.segmentExternallyDisrupted == true or os.clock() < (bot.externalInterferenceUntil or 0)
end

-- THE VOID ZONES, one query set for every bot rather than one each.
--
-- Built with NO cooldown of its own: TagZones remembers the last touch
-- per PART, so a shared instance with a cooldown would let the first
-- bot to hit a pit swallow everyone else's touch of the same pit. The
-- wait is kept per bot instead, where it belongs.
local voidZones = nil
local warnedNoRoute = false
local warnedNoRig = false

--=====================================================================
--  CONTROLS
--
--  Exactly the shape Simulation expects off a keyboard. Nothing here
--  knows it's a bot, which is why a bot can't accidentally be given
--  abilities a player doesn't have.
--=====================================================================
-- Show or hide a kart's shield bubble.
--
-- Server-side twin of what Effects does for the local player. Effects
-- fades it; this snaps, because a bot's shield going up is something you
-- notice from across the track rather than something you are looking at.
local function setShieldVisible(kart: Model, on: boolean)
	local bubble = kart:FindFirstChild(Config.Effects.ShieldName, true)
	if not bubble then
		return
	end
	local alpha = if on then Config.Effects.ShieldTransparency else 1
	for _, part in { bubble, table.unpack(bubble:GetDescendants()) } do
		if part:IsA("BasePart") then
			part.Transparency = alpha
		end
	end
end

-- SKILL AS A 0..1 FRACTION of the range bots are actually rolled in.
--
-- `bot.skill` is drawn between SkillMin and SkillMax — 0.45 to 0.92 —
-- so lerping a chance by it directly never reaches either end. Every
-- "at SkillMin" in the config was a lie by about half: the worst bot
-- shielded 47% of the time against a configured 20%.
--
-- Normalised here so those numbers mean what they say, and so widening
-- the skill range later does not silently squash every behaviour that
-- reads it.
local function skillFrac(bot): number
	local span = B.SkillMax - B.SkillMin
	if span <= 0 then
		return 1
	end
	return math.clamp((bot.skill - B.SkillMin) / span, 0, 1)
end

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
	local a = Route.tangentAt(u, nil, Route.path())
	local b = Route.tangentAt(u + ahead, nil, Route.path())
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

-- Same rule the client applies: one pad at a time, and a global guard so
-- a row of overlapping pads cannot stack into one enormous boost.
local function checkPads(bot)
	if not bot.padZones then
		return
	end
	local now = os.clock()
	if now < (bot.padNextAt or 0) then
		return
	end
	local cf, size = bot.sim.hitbox.CFrame, bot.sim.hitbox.Size
	for _, entry in bot.padZones do
		if entry.zone:Touch(cf, size) then
			bot.padNextAt = now + Config.Boosters.GlobalCooldown
			bot.sim:ApplyBoost(entry.def.Speed, entry.def.Duration)
			break
		end
	end
end

--=====================================================================
--  WATCHING THE PEOPLE.
--
--  A player carrying speed cleanly through a corner proves it works, and
--  that is better evidence than a bot discovering it over ninety laps.
--
--  OBSERVED, NOT REPORTED. The kart's position replicates to the server
--  anyway, so the route position is computed here and there is no
--  message to forge. That matters because this feeds behaviour that gets
--  SAVED — a client-reported version would let one modified player teach
--  every bot on the server to drive into a wall, permanently.
--
--  Only clean, unboosted node crossings count. A player through a corner
--  at 160 because of a nitro is not proof the corner is takeable at 160,
--  and crediting it would teach bots to arrive somewhere they cannot
--  physically turn.
--=====================================================================
local watched: { [Model]: { node: number, hurt: boolean } } = {}
local nextReport = 0

local function watchPlayers()
	if not (B.LearnEnabled and B.LearnFromPlayers) then
		return
	end
	local nodes = #Route.path()
	if nodes == 0 then
		return
	end
	for _, kart in KartService.allKarts() do
		local hitbox = kart.PrimaryPart
		-- Bots are already reporting their own experience; this is only
		-- the people.
		if hitbox and kart:GetAttribute(Names.OWNER) then
			local seen = watched[kart]
			local u = Route.nearestU(hitbox.Position, Route.path(), seen and seen.node + 0.0 or nil)
			local at = math.floor(u) % nodes

			-- Boost of any kind disqualifies the crossing. What is being
			-- learned is what the KART can do here, not what a pick-up
			-- did for it.
			local boosting = kart:GetAttribute(Names.BOOSTING) == true

			if not seen then
				watched[kart] = { node = at, hurt = boosting, at = os.clock() }
			else
				-- WENT BACKWARDS A LONG WAY = they were put back. A
				-- respawn is the clearest signal a player can give about
				-- a stretch of track, and it needs no client message —
				-- the position jump IS the report.
				--
				-- Guarded against the lap wrap, which is also a big
				-- negative step and means the opposite thing.
				local back = seen.node - at
				if back > nodes * 0.25 and back < nodes * 0.75 then
					BotBrain.wentOff(seen.node)
					seen.node = at
					seen.hurt = boosting
					seen.at = os.clock()
				elseif at ~= seen.node then
					-- TOOK FAR TOO LONG counts too, same as for bots —
					-- a stretch people crawl through is one bots should
					-- not be flinging themselves at either.
					local span = Route.segmentLength(seen.node, Route.path())
					local expect = span / math.max(H.MaxSpeed * B.LearnSlowPace, 1)
					local took = os.clock() - (seen.at or os.clock())
					if took > expect * B.LearnSlowFactor then
						BotBrain.wasSlow(seen.node)
					elseif not seen.hurt then
						BotBrain.playerPass(seen.node)
					end
					seen.node = at
					seen.hurt = boosting
					seen.at = os.clock()
				elseif boosting then
					seen.hurt = true
				end
			end
		end
	end
	-- Karts come and go every round; without this the table grows by one
	-- entry per kart that has ever existed.
	for kart in watched do
		if not kart.Parent then
			watched[kart] = nil
		end
	end
end

local function drawRacingLine(force: boolean?)
	local nodes = Route.path()
	-- The guard is "has the path changed", which is right for the
	-- per-frame call and wrong for a deliberate redraw: after a preflight
	-- rebuild the count is often identical while the nodes themselves
	-- moved.
	if #nodes == lineNodeCount and not force then
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

	local narrowest, narrowestAt = math.huge, 0
	for i, node in nodes do
		marker(node.position + Vector3.yAxis * 2, 4, Color3.fromRGB(90, 170, 255), true)
		-- Sampled between nodes, so the CURVE is visible rather than
		-- guessed at from the checkpoints.
		-- RED MEANS THERE IS NOTHING UNDER IT.
		--
		-- The line between two nodes is a Catmull-Rom curve, and on a
		-- tight corner it bows OUTSIDE the road — so a path can be made
		-- entirely of nodes that sit on tarmac and still run through the
		-- air between them. Bots follow the curve, not the nodes, so that
		-- is a real hole and not a drawing artefact.
		--
		-- Drawn in red rather than reported in a log line because the fix
		-- is spatial: you need to see WHICH stretch to put another node
		-- on, and a number cannot tell you that.
		local up = node.parts[1].CFrame.UpVector
		for k = 1, 7 do
			local at = Route.pointAt(i - 1 + k / 8, nil, Route.path())
			if at then
				local solid = Route.hasGround(at, up)
				-- THREE STATES, NOT TWO. A gap with a launcher near it is
				-- a JUMP and the road is supposed to stop — colouring
				-- that the same as a hole reports every ramp on the
				-- track as a fault, and a check that cries wolf is one
				-- you learn to scroll past.
				local colour, size
				if solid then
					colour, size = Color3.fromRGB(255, 230, 120), 1.1
				elseif Route.launcherNear(at, Config.Race.RouteJumpLookout) then
					colour, size = Color3.fromRGB(120, 200, 255), 1.6 -- a jump
				else
					colour, size = Color3.fromRGB(255, 70, 70), 2.2 -- a hole
				end
				marker(at + up * 1.5, size, colour, false)
			end
		end

		-- GREEN EDGES: how wide this thinks the road is, and therefore the
		-- box a bot's line is clamped inside.
		--
		-- Worth drawing because the measurement comes from your checkpoint
		-- volumes, so a gate narrower than the tarmac shows up here as
		-- green markers sitting well inside the kerb — and a gate WIDER
		-- than the tarmac shows up as green out in the scenery, which is
		-- the setup mistake that puts bots off the track.
		-- THE SAME `across` THE WIDTHS WERE MEASURED WITH, read back off
		-- the node rather than derived again.
		--
		-- This used to recompute it as `tangentAt(i-1) x world-up`, and
		-- that is a different vector: the widths use a CENTRED tangent
		-- (next minus prev) and the part's OWN up. On a corner the two
		-- headings diverge, and on a banked one the ups do as well — so
		-- the markers were drawn beside the road while the numbers they
		-- represent were measured across it. The markers were wrong, not
		-- the widths.
		local across = node.across
		if across.Magnitude > 1e-4 then
			-- Each side its own distance. A gate is rarely centred on its
			-- road, and one averaged number is too tight where there's
			-- room and too generous over the drop.
			local l = math.max(node.leftWidth - B.EdgeMargin, 0)
			local r = math.max(node.rightWidth - B.EdgeMargin, 0)
			-- Lifted along the NODE's up, not world up, or the markers
			-- float off the surface on a banked corner — the same
			-- mismatch that put them beside the road in the first place.
			local lift = node.parts[1].CFrame.UpVector * 1.5
			marker(node.position - across * l + lift, 1.6, Color3.fromRGB(120, 230, 140), false)
			marker(node.position + across * r + lift, 1.6, Color3.fromRGB(120, 230, 140), false)
		end

		if node.halfWidth < narrowest then
			narrowest, narrowestAt = node.halfWidth, node.order
		end
	end
	print(
		("[BotService] racing line drawn: %d checkpoints. Green markers are the road edge, FELT FOR with rays rather than read off the gate volumes — so they should land on tarmac, not on the checkpoint. Narrowest measured stretch is %.0f studs at checkpoint %d. Green over the void now means the probe found a floor that isn't road (raise Race.RouteEdgeStepDrop), not that a gate is oversized."):format(
			#nodes,
			narrowest * 2,
			narrowestAt
		)
	)
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
	-- Orange beats red: a bot that has seen a drop is doing something
	-- quite different from one that has merely seen a corner, and the two
	-- were indistinguishable when both showed as "slowing down".
	bar.Color = if (bot.ledgeFor or 0) > 0
		then Color3.fromRGB(255, 170, 60)
		elseif bend > 0.2 then Color3.fromRGB(255, 90, 90)
		else Color3.fromRGB(90, 240, 130)
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
	-- HINTED WITH THE PREVIOUS u, so the search is a window rather than
	-- the whole lap. Without it the nearest point can flip to a distant
	-- stretch that happens to pass close by, and the bot turns to chase
	-- it — which is the circling. Every OTHER call here stays global on
	-- purpose: a respawn or a grid placement genuinely does not know
	-- where it is, and a window around a stale u would strand it.
	bot.u = Route.nearestU(sim.pos, Route.path(), bot.u)

	local speed = math.abs(sim.speed)
	local bend = bendAt(bot.u, B.CornerLookahead, sim.up)

	-- Asymmetric, because a checkpoint is rarely centred on its road and
	-- one averaged number is too generous on exactly the side with the
	-- drop. Both sides are probed with rays, not read off the gate.
	local roomL, roomR = Route.roomAt(bot.u, bot.branch, Route.path())
	roomL = math.max(roomL - B.EdgeMargin, 0)
	roomR = math.max(roomR - B.EdgeMargin, 0)

	-- LEARNED CAUTION. Every time this bot leaves the track it marks the
	-- node it left, and thereafter it drives that stretch nearer the
	-- middle and slower. See BotService.noteWentOff.
	--
	-- This is the whole of "learn from its mistake" and it is not
	-- learning in any clever sense — it's a number that goes up when
	-- something goes wrong and decays when it doesn't. That's enough,
	-- because the failure it has to stop repeating is entirely local: one
	-- corner, taken too wide, every lap.
	-- THE BOT'S OWN NERVES PLUS THE CIRCUIT'S REPUTATION. One is what
	-- this driver has learned this race; the other is what every bot has
	-- learned here across every session. They add, because a corner can
	-- be both generally nasty and personally unlucky.
	local hereIdx = math.floor(bot.u) % math.max(#Route.path(), 1)
	local caution = (bot.caution[hereIdx] or 0) + BotBrain.dangerAt(hereIdx) * B.CautionMax
	if caution > 0 then
		local pull = math.clamp(caution * B.CautionPull, 0, 1)
		roomL *= 1 - pull
		roomR *= 1 - pull
	end

	-- The narrower side, used only to judge whether the bot is still
	-- meaningfully ON the road when recording a safe position.
	local room = math.min(roomL, roomR)

----------------------------------------------------------------
	-- LINE
	--
	-- Not the centreline. Each bot holds an offset and wanders it, which
	-- is most of what makes them look driven rather than railed — and
	-- it's the reason there's room to overtake one.
	----------------------------------------------------------------
	bot.lineAt += dt * B.LineDrift
	-- Damped on a straight, and this was a real part of the swerve: an
	-- unconditional sine wave on the lateral target is an instruction to
	-- weave, and no controller improvement can refuse it. A driver holds
	-- a straight and gets untidy through corners, so the wander follows
	-- the bend rather than the clock.
	local straightness = 1 - math.min(bend / math.max(B.WanderFullBend, 1e-3), 1)
	-- Also a fraction of the road rather than a stud count, so a narrow
	-- section tightens the wander instead of having it clamped off.
	local wanderRoom = math.min(roomL, roomR)
		* B.LineWander
		* (1 - bot.skill)
		* (B.WanderOnStraight + (1 - B.WanderOnStraight) * (1 - straightness))
	local wander = math.sin(bot.lineAt) * wanderRoom
	-- Scaled to the room available on the side it is heading for. Done
	-- here rather than at spawn because the road width changes along the
	-- lap, and a line chosen once cannot know that.
	--=============================================================
	--  STRAIGHT OFF THE LINE, THEN FIND YOUR LINE.
	--
	--  `lineBias` and `wander` are live from the first frame, so the
	--  moment the lights go out every bot immediately sets off toward
	--  its own randomly-chosen side of a road it has not looked at yet.
	--  Eight of them doing that at once is the weaving at the start —
	--  it is not a bug in any one behaviour, it is every behaviour
	--  arriving at full strength before there is any information.
	--
	--  A real grid launches straight and sorts itself out over the
	--  first few seconds. This ramps the personality in over
	--  `SettleTime` instead of switching it on, so they leave the line
	--  pointed forwards and fan out as they go.
	--=============================================================
	local settle = 1
	local since = MatchService.racingSince()
	if since then
		local racing = workspace:GetServerTimeNow() - since
		settle = math.clamp(racing / math.max(B.SettleTime, 1e-3), 0, 1)
		-- Eased, or the bias arrives as a step at the end of the ramp
		-- and they all twitch outward on the same frame.
		settle = settle * settle * (3 - 2 * settle)
	end
	bot.settle = settle

	----------------------------------------------------------------
	-- THE RACING LINE, WHICH THEY DID NOT HAVE.
	--
	-- The line was a RANDOM bias per bot plus a sine wander. That is a
	-- personality, not a plan: it takes no notice of where the corners
	-- are, so a bot would sit on the outside through an apex and cut
	-- across the exit for no reason. From outside it reads exactly as
	-- "makes bad decisions", because it is not making any.
	--
	-- A real line is geometric: OUTSIDE on the way in, INSIDE at the
	-- apex, and let it run wide on exit. That is one signed number —
	-- the road's own curvature — read at two places:
	--
	--   curvature AHEAD  a corner is coming, so move to its outside
	--   curvature HERE   I am in it, so take the inside
	--
	-- `Route.curvatureAt` is signed, and the sign convention lands the
	-- right way round with no correction: NEGATIVE is a left turn, so
	-- `sign(k)` is already "which side is the inside".
	--
	-- The bias and wander survive at a fraction of their old strength.
	-- Two bots on identical lines look like one bot drawn twice, and the
	-- variety is worth keeping — it just should not be the plan.
	----------------------------------------------------------------
	local path = Route.path()
	local kHere = Route.curvatureAt(bot.u, sim.up, bot.branch, path)
	local kSoon = Route.curvatureAt(bot.u + B.ApexLook, sim.up, bot.branch, path)

	local tight = math.clamp(math.abs(kHere) / B.ApexFullCurve, 0, 1)
	local coming = math.clamp(math.abs(kSoon) / B.ApexFullCurve, 0, 1)

	-- Fraction of the available road, -1 (hard left) to +1 (hard right).
	-- Wide is negated because the outside of a corner is the side away
	-- from the way it turns.
	local wide = -math.sign(kSoon) * coming * B.ApexWide
	local apex = math.sign(kHere) * tight * B.ApexTight
	-- The apex wins as it arrives: you cannot still be setting up for a
	-- corner you are already in.
	local lineWant = wide * (1 - tight) + apex

	local sideRoom = if lineWant >= 0 then roomR else roomL
	local biasRoom = if bot.lineBias >= 0 then roomR else roomL
	local offset = (lineWant * sideRoom + bot.lineBias * biasRoom * B.LineSpread + wander) * settle

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
	-- STAY ON THE ROAD
	--
	-- Everything above is free to move the bot sideways: a personal line
	-- bias up to LineOffset, a wander of the same size again, and up to
	-- AvoidStrength more for traffic. Nothing so far has had any idea how
	-- wide the road is.
	--
	-- So a bot that rolled a positive bias, wandered the same way, and
	-- dodged someone would aim tens of studs right of the centreline and
	-- drive off the track — reliably, since the bias never changes. Which
	-- is exactly what it did.
	--
	-- The road's width is measured from the checkpoint volumes (see
	-- Route.nodes), so this clamps against the track you actually built
	-- rather than a number someone guessed.
	----------------------------------------------------------------

	----------------------------------------------------------------
	-- A SOFT EDGE, THEN THE HARD ONE.
	--
	-- The clamp below is a wall the bot is happy to lean on: every term
	-- above — the line bias, the wander, a dodge — can push past the
	-- limit, and clamping simply parks the bot AT it. So a field spent
	-- the race tracking the outer edge, which on most corners is the
	-- barrier, and any nudge put them into it.
	--
	-- A clamp says "you may not go further". It never says "you are
	-- already too far", and those are different instructions.
	--
	-- So the last stretch of road before the edge is now a spring rather
	-- than a wall. Inside `EdgeSoft` studs of the limit the offset is
	-- pushed back toward the middle, harder the closer it gets — the
	-- bot still uses the whole road when it has a reason to, and drifts
	-- off the paint when it does not.
	----------------------------------------------------------------
	local limit = if offset >= 0 then roomR else roomL
	if limit > 1e-3 then
		local slack = limit - math.abs(offset)
		if slack < B.EdgeSoft then
			-- 0 at the soft line, 1 at the edge. Squared so the push is
			-- gentle where it starts and firm where it matters.
			local how = math.clamp(1 - slack / B.EdgeSoft, 0, 1)
			offset -= math.sign(offset) * how * how * B.EdgeSoft * B.EdgePush
		end
	end

	----------------------------------------------------------------
	-- RAMPS, WHICH BOTS COULD NOT SEE AT ALL.
	--
	-- There was no mention of GlideRamp or FlipRamp anywhere in this
	-- file, so a bot hit one only by accident — and a ramp the field
	-- never uses is a piece of track that may as well not be built.
	--
	-- A GLIDE RAMP IS TAKEN EVERY TIME. It is a shortcut across a gap;
	-- declining it is not a personality, it is a mistake, and a bot that
	-- drives past the interesting part of the track looks broken.
	--
	-- A FLIP RAMP IS A CHOICE. It is a boost, not a route, so it is
	-- rolled per bot per approach — some take it, some do not, which is
	-- where variety belongs.
	--
	-- Implemented as a PULL ON THE OFFSET, not as a new aim point. The
	-- bot keeps following the racing line and simply drifts onto the
	-- ramp's lateral position as it closes — so everything downstream
	-- (the soft edge, traffic, the clamp) still applies, and a ramp
	-- hanging over the void cannot drag a bot off the road.
	----------------------------------------------------------------
	bot.rampAhead = 0
	if B.SeekRamps and (bot.settle or 1) > 0.5 then
		local nose = sim.pos + sim.forward * 2
		-- Same convention as everywhere else: right is positive, so a
		-- ramp's `want` drops straight into `offset` with no sign fixing.
		local fwd = Route.tangentAt(bot.u, bot.branch, Route.path())
		local across = if fwd then fwd:Cross(sim.up) else nil
		if across and across.Magnitude > 1e-4 then
			across = across.Unit
			local bestPull, bestAt = 0, nil
			for _, tag in { Config.Glide.RampTag, Config.Trick.RampTag } do
				local definite = tag == Config.Glide.RampTag
				for _, ramp in CollectionService:GetTagged(tag) do
					if ramp:IsA("BasePart") then
						local span = ramp.Position - nose
						local along = span:Dot(sim.forward)
						-- Ahead, within reach, and roughly on our road.
						if along > 0 and along < B.RampSeekRange and span.Magnitude < B.RampSeekRange then
							local want = span:Dot(across)
							-- Closer means commit harder, so a bot lines up
							-- gradually instead of jinking at the last moment.
							local urgency = 1 - math.clamp(along / B.RampSeekRange, 0, 1)
							local take = definite or bot.takesFlips
							if take and urgency > bestPull then
								bestPull, bestAt = urgency, want
							end
						end
					end
				end
			end
			if bestAt then
				offset += (bestAt - offset) * bestPull * B.RampSeekPull
				-- COMMITTED. A ramp needs SPEED to fire — a FlipRamp
				-- refuses below Trick.MinSpeed — and the throttle rules
				-- below have no idea a ramp is there. `bot.jumping` does
				-- not cover it either: that means "the route crosses a
				-- gap", and a flip ramp is usually a bump on solid road.
				--
				-- So the bot read the ramp's approach as a bend, lifted,
				-- arrived under the threshold, and drove over a launcher
				-- that did nothing. It was not failing the trick; it was
				-- never starting one.
				bot.rampAhead = bestPull
			end
		end
	end

	----------------------------------------------------------------
	-- STEERING HOME. Set when the bot has stopped making progress.
	--
	-- Everything above builds a line with a personality — a bias, a
	-- wander, a dodge, a ramp. All of it is what put the bot round the
	-- side of a tube in the first place, so while it is lost the whole
	-- lot is overruled and it simply drives the centreline until it is
	-- moving down the track again.
	--
	-- A plain override rather than another weighted term: the point of
	-- this state is that the usual reasoning is what failed.
	----------------------------------------------------------------
	if (bot.homeFor or 0) > 0 then
		bot.homeFor = math.max(bot.homeFor - dt, 0)
		offset = 0
	elseif BotBrain.tameAt(hereIdx) > B.LearnTameAt then
		-- LEARNED: bots keep taking forever through this node. That is
		-- the tunnel signature — nothing crashes, nothing leaves the
		-- road, and nobody gets anywhere. Drive the centre and stop
		-- being clever, because the cleverness is what got them stuck.
		--
		-- Eased rather than snapped to zero: a node that flips this on
		-- mid-corner should not yank the wheel.
		offset *= 1 - math.clamp(BotBrain.tameAt(hereIdx), 0, 1)
	end

	offset = math.clamp(offset, -roomL, roomR)

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

	-- FLOOR IT AT TWICE THE CONTROL LAG DISTANCE.
	--
	-- Pure pursuit is stable only while the lookahead is comfortably
	-- longer than the road covered during the controller's own lag —
	-- reaction, plus SteerSlew, plus the Simulation's steering smoothing,
	-- about 0.45s. At 100 studs/s that is 45 studs, and the lookahead
	-- used to work out at 46. Sitting on the boundary is what made bots
	-- swerve down a straight, and it could not have been tuned out
	-- anywhere else.
	--
	-- Applied AFTER the corner shortening above, because shortening it
	-- for a bend is precisely how you fall back under the limit.
	lookahead = math.max(lookahead, speed * B.ControlLag * B.LookaheadLagMargin)
	local aheadU = bot.u + lookahead / Route.segmentLength(bot.u, Route.path())
	local aim = Route.pointAt(aheadU, bot.branch, Route.path())
	if not aim then
		return
	end

	local tangent = Route.tangentAt(aheadU, bot.branch, Route.path())
	if tangent then
		local across = tangent:Cross(sim.up)
		if across.Magnitude > 1e-4 then
			aim += across.Unit * offset
		end
	end

	----------------------------------------------------------------
	-- IS THERE ROAD WHERE I'M POINTING?
	--
	-- The cached widths describe the road AT THE CENTRELINE, which is
	-- the right answer right up until a bot gets knocked off, spun, or
	-- respawned somewhere the line doesn't run. Then it's steering across
	-- ground nothing has ever checked.
	--
	-- So: two rays. One under the point it's steering at, one just ahead
	-- of its own nose. The nose ray is the important one — it's the only
	-- thing that can catch a bot already halfway off.
	--
	-- Finding nothing does NOT mean brake and hope. It means aim at the
	-- centreline, which is the one place on the map known to have road,
	-- and lift so the correction has time to work. A bot that lifts and
	-- turns in looks like a driver catching a mistake. One that only
	-- brakes goes off the edge slowly.
	----------------------------------------------------------------
	--
	-- A GAP IS NOT AUTOMATICALLY A MISTAKE. Tracks are built with jumps
	-- you're meant to take flat out, and the first version of this
	-- treated any missing floor as an emergency: it lifted to
	-- LedgeThrottle on the approach, which is the one input guaranteed to
	-- turn a jump you'd have cleared into a fall. It was braking for the
	-- ramp.
	--
	-- The racing line settles it. The line is by definition where the
	-- designer says to drive, so if the ROUTE carries on across the gap
	-- and there's road on the far side, this is a jump: line up, stay on
	-- the throttle, commit. Only a gap the route does NOT cross is a
	-- bot about to drive off the map.
	local ledge, jump = false, false
	local nose = sim.pos + sim.forward * (B.LedgeLook + speed * B.LedgeLookPerSpeed)
	if not (Route.hasGround(aim, sim.up) and Route.hasGround(nose, sim.up)) then
		local beyond = Route.pointAt(aheadU + B.JumpSpan, bot.branch, Route.path())
		if beyond and Route.hasGround(beyond, sim.up) then
			jump = true
		else
			ledge = true
		end
	end

	-- Already in the air: whatever is or isn't under the nose, there is
	-- nothing to be done about it now, and lifting mid-flight only
	-- shortens the landing.
	if not sim.grounded then
		ledge = false
	end

	if ledge or jump then
		-- Both want the same line — the centre, where the road is and
		-- where a jump is surveyed from. They differ entirely on throttle.
		local centre = Route.pointAt(aheadU, bot.branch, Route.path())
		if centre then
			aim = centre
		end
	end

	bot.jumping = jump
	if ledge then
		bot.ledgeFor = B.LedgeHold
	else
		-- Held briefly after the ground comes back, or a bot skimming an
		-- edge flickers in and out of the correction and never commits to
		-- either line.
		bot.ledgeFor = math.max((bot.ledgeFor or 0) - dt, 0)
	end

	----------------------------------------------------------------
	-- STEERING: PLAN THE ARC, THEN TRIM IT
	--
	-- The old controller was one line — steer proportional to the heading
	-- error toward the aim point — and that is why bots swerved down
	-- perfectly straight road.
	--
	-- A pure error-driven loop has to PRODUCE error in order to have
	-- something to work on. It notices it's off, hauls the wheel over,
	-- arrives, overshoots because nothing damped it, and repeats. Put a
	-- 190ms reaction delay in that loop and it's not a bug any more, it's
	-- a guaranteed oscillator: delay plus gain plus no damping is the
	-- textbook recipe for one. That was the swerve, and it was never
	-- going to tune out — the loop was unstable by construction.
	--
	-- So it's built the way vehicle controllers are actually built:
	-- FEED-FORWARD plus FEEDBACK.
	--
	--   feed-forward  the road's own curvature. It turns because the
	--                 corner is there, not because it has already run
	--                 wide. On a straight this is exactly zero.
	--   feedback      a small correction toward the aim point, which is
	--                 all that's left once the corner is handled.
	--
	-- Everything is computed as CURVATURE (1/studs) and converted to a
	-- steering input at the end through the kart's own model. That
	-- conversion is why this works at all: we know that lock L at speed v
	-- yields yaw rate L*turn, so curvature k needs L = k*v/turn. The
	-- controller asks for a shape of path and the maths returns the input
	-- that produces it, instead of guessing a number and correcting.
	----------------------------------------------------------------
	local right = sim.forward:Cross(sim.up)
	right = if right.Magnitude > 1e-4 then right.Unit else Vector3.zero

	-- FEED-FORWARD. The single biggest change here.
	local kappaPath = Route.curvatureAt(aheadU, sim.up, bot.branch, Route.path())

	-- FEEDBACK, as pure pursuit in curvature form: k = 2y/L² is the arc
	-- that actually passes THROUGH the aim point. The old dot-product was
	-- an approximation of this that overshoots for exactly the same
	-- reason a P controller overshoots a step.
	--
	-- The aim point already carries our chosen line offset, so this one
	-- term covers both "get back on line" and "follow the line" — which
	-- is why the separate saturating cross-track term is gone.
	local toAim = aim - sim.pos
	local flat = toAim - sim.up * toAim:Dot(sim.up)
	local kappaAim = 0
	local L = flat.Magnitude
	if L > 1e-3 and right.Magnitude > 0 then
		-- No deadband on this. It is tempting — "don't fuss about being
		-- slightly off" — but this quantity is not cross-track error. It
		-- mixes position and heading, and it falls to zero whenever the
		-- kart is POINTING at the target, which includes running parallel
		-- to the line several studs wide of it. Deadbanding it suppressed
		-- the correction in exactly the case that needed one, and left
		-- bots driving permanently off their own racing line.
		kappaAim = 2 * flat:Dot(right) / (L * L)
	end

	local kappaWant = kappaPath * B.FeedForward + kappaAim * B.PursuitGain

	-- How far off the chosen line we are. Only two things want it now: the
	-- safe-position record below, and the ledge emergency. The steering
	-- itself no longer has a cross-track term at all — the aim point
	-- already carries the line offset, so pure pursuit toward it covers
	-- both jobs, and one term that can't fight itself is worth more than
	-- two that can.
	local actualOffset = Route.lateralAt(bot.u, sim.pos, sim.up)
	local crossErr = offset - actualOffset

	-- LAST PLACE IT WAS DEFINITELY ON THE TRACK.
	--
	-- Remembered here, while we already know both facts that make it
	-- true: wheels down, and inside the road's width.
	--
	-- revive() used to respawn at whatever point on the racing line was
	-- nearest to where the kart ENDED UP. A kart that drives off the right
	-- and falls is nearest to the road it was aiming at, not the road it
	-- left — so it came back at the following checkpoint, or on a hairpin
	-- at some entirely unrelated stretch it happened to fall beside. From
	-- outside that reads as a bot skipping ahead, which is what it was.
	--
	-- Where you fell is not where you were. Store where you were.
	-- ROAD UNDER ME, not "near the middle of a number I measured".
	--
	-- This used to require `|offset| <= room`, and in a tube that never
	-- holds: `room` comes from rays fired sideways, which in a rounded
	-- section hit the wall curving upward a few studs out. So the bot is
	-- "unsafe" for the entire tunnel, `safeU` stops updating at the
	-- entrance, and a fall at the far end puts it back before the tunnel.
	-- That is the "sent back very far" — it was never about the fall, it
	-- was about the last point that qualified.
	--
	-- `hasGround` asserts the thing actually being claimed: this is a
	-- place worth coming back to. The offset test stays as a cheap
	-- accept, so nothing gets slower on ordinary road.
	if sim.grounded and (math.abs(actualOffset) <= room or Route.hasGround(sim.pos, sim.up)) then
		bot.safeU = bot.u
		bot.safeCF = CFrame.lookAt(sim.pos, sim.pos + sim.forward, sim.up)
	end

	-- On a ledge, forget the chosen line and the deadband — head for the
	-- centre hard. It's the one place known to have road under it.
	if (bot.ledgeFor or 0) > 0 then
		kappaWant += -crossErr * B.LedgeRecover
	end

	----------------------------------------------------------------
	-- REACTION, applied to the PLAN and nothing else.
	--
	-- This used to delay the finished steering input, which put a 190ms
	-- pure lag inside the stabilising loop — and a delay inside a
	-- feedback loop is the classic way to build an oscillator. Half the
	-- swerve came from here.
	--
	-- It was also the wrong model of a person. Reaction time is how long
	-- you take to respond to something NEW: a corner appearing, a rival
	-- moving, an item. It is not how long you take to hold a lane —
	-- that's a trained reflex running an order of magnitude faster, and
	-- nobody weaves down a straight road because of it.
	--
	-- So the plan arrives late, like a person's does, and the correction
	-- that keeps the kart pointing straight runs now, like a person's
	-- does. The tell survives; the oscillator doesn't.
	----------------------------------------------------------------
	table.insert(bot.sawSteer, { at = os.clock(), value = kappaWant })
	while #bot.sawSteer > 1 and os.clock() - bot.sawSteer[1].at >= B.ReactionTime do
		kappaWant = bot.sawSteer[1].value
		table.remove(bot.sawSteer, 1)
	end

	----------------------------------------------------------------
	-- CURVATURE -> STEERING INPUT, through the kart's own model.
	--
	-- Simulation yaws at `steer * turn` rad/s, and a path of curvature k
	-- travelled at v needs k*v rad/s. So the lock that produces the arc
	-- we asked for is k*v/turn. No tuning constant, no guessing: it is
	-- the inverse of the thing the kart actually does.
	--
	-- This is what makes the feed-forward term worth having. An
	-- open-loop guess would need trimming, so the feedback would be back
	-- to doing all the work — and back to swerving.
	----------------------------------------------------------------
	local turn = H.TurnRate + (H.TurnRateTop - H.TurnRate) * math.clamp(speed / H.MaxSpeed, 0, 1)
	local wantSteer = kappaWant * math.max(speed, B.SteerMinSpeed) / math.max(turn, 1e-3)

	----------------------------------------------------------------
	-- YAW DAMPING.
	--
	-- Compares the yaw rate we asked for against the one we're getting
	-- and trims the difference. This is the term that was missing
	-- entirely, and the reason nothing ever settled: two position terms
	-- fighting each other with nothing watching the RATE will always
	-- cross the line rather than arrive at it.
	--
	-- It also silently absorbs everything the model above doesn't know
	-- about — drift, a bump, a kerb — because it doesn't care WHY the
	-- kart isn't rotating as asked, only that it isn't.
	local yawNow = 0
	if bot.lastForward and dt > 1e-4 then
		-- Signed the same way as everything else: positive is toward
		-- `forward:Cross(up)`.
		yawNow = -(bot.lastForward:Cross(sim.forward)):Dot(sim.up) / dt
	end
	bot.lastForward = sim.forward

	local yawWant = kappaWant * speed
	wantSteer += math.clamp((yawWant - yawNow) / math.max(turn, 1e-3) * B.YawDamp, -B.YawAuthority, B.YawAuthority)

	wantSteer = math.clamp(wantSteer, -1, 1)

	----------------------------------------------------------------
	-- MAKING IT LOOK DRIVEN
	--
	-- Everything above computes the perfect input. What follows spoils it
	-- on purpose, because the perfect input is exactly what reads as a
	-- machine: exact, instant, and recomputed sixty times a second.
	--
	-- None of this makes a bot slower. It makes the signal human-shaped.
	----------------------------------------------------------------

	-- Reaction is handled up in the planner now — see the note there. It
	-- delays the PLAN, not the correction, because delaying the
	-- correction is what built the oscillator.
	local seen = wantSteer

	-- WANDER, and only where a person actually wanders.
	--
	-- This was unconditional, so bots were commanded to weave down
	-- straights — a sine wave added to the output of a loop that then
	-- tried to correct it. Some of the swerve you could see was not the
	-- controller failing. It was this, working exactly as written.
	--
	-- Nobody drifts about on a straight road; they hold it, and get
	-- untidy through corners where the car is actually moving around
	-- underneath them. So it's scaled by how hard the bot is working.
	bot.noiseAt += dt * B.SteerNoiseRate
	local effort = math.min(math.abs(wantSteer) / math.max(B.NoiseFullSteer, 1e-3), 1)
	local busy = B.NoiseOnStraight + (1 - B.NoiseOnStraight) * effort
	seen += math.sin(bot.noiseAt * 1.7) * math.cos(bot.noiseAt * 0.6) * B.SteerNoise * (2 - bot.skill) * busy

	-- The deadzone that used to sit here is gone. Holding the last input
	-- until the new one differed enough is hysteresis inside a feedback
	-- loop, which generates a limit cycle on its own — and once the
	-- lookahead grew it became worse than that. The correct input for
	-- being five studs off the line at a 108-stud lookahead is about
	-- 0.049, under the 0.108 threshold a typical bot had, so the
	-- correction was discarded every frame and the bot drove parallel to
	-- the line forever without ever rejoining it.
	--
	-- SteerSlew below already stops a bot flicking to full lock, which is
	-- the realism this was reaching for, and it shapes the input instead
	-- of throwing it away.
	bot.heldSteer = seen

	-- Slewed, not snapped. A bot that can flick to full lock in one frame
	-- corners in a way no player can, which reads as cheating even though
	-- the handling is identical.
	c.touchSteer = Util.approach(c.touchSteer, math.clamp(bot.heldSteer, -1, 1), B.SteerSlew, dt)

	----------------------------------------------------------------
	-- THROTTLE
	--
	-- Lifts for corners. How early is skill: a poor bot brakes late,
	-- carries too much speed and runs wide, exactly like a poor driver.
	----------------------------------------------------------------
	local ease = bend * B.CornerBrake * (2 - bot.skill)

	----------------------------------------------------------------
	-- THE CORNER HAS A SPEED LIMIT, AND IT IS NOT A GUESS.
	--
	-- The lift above is proportional to how sharp the bend is and takes
	-- NO ACCOUNT OF HOW FAST THE BOT IS GOING. A kart at 95 and one at
	-- 40 get the same throttle cut into the same corner, so the fast one
	-- arrives at a corner it physically cannot turn through and
	-- understeers into the wall. No racing line fixes that — only
	-- arriving slower does.
	--
	-- This kart's own steering model gives the limit exactly, with no
	-- grip constant to invent. Full lock at speed v yields yaw rate
	-- turn(v), so the tightest curvature it can hold is turn(v)/v:
	--
	--     turn(v) = TurnRate + (TurnRateTop - TurnRate) * v/MaxSpeed
	--     hold k   <=>   turn(v)/v >= k
	--     solving  ->    v <= TurnRate / (k + (TurnRate - TurnRateTop)/MaxSpeed)
	--
	-- Which says a 50-stud radius tops out near 85 studs/s and a 20-stud
	-- hairpin near 42 — numbers the bend-based lift had no way to know.
	--
	-- A MARGIN, because driving at exactly the limit IS understeer: the
	-- kart needs steering left over to correct with. Better bots use
	-- more of it, which is what skill should mean.
	----------------------------------------------------------------
	local kWorst = 0
	for k = 0, 4 do
		local at = bot.u + k * (B.CornerLookahead / 4)
		kWorst = math.max(kWorst, math.abs(Route.curvatureAt(at, sim.up, bot.branch, Route.path())))
	end
	local fade = (H.TurnRate - H.TurnRateTop) / math.max(H.MaxSpeed, 1)
	local vLimit = H.TurnRate / math.max(kWorst + fade, 1e-4)

	-- LEARNING BUYS MARGIN, NOT SPEED. A naive bot leaves 12% of the
	-- corner limit unused because it needs steering left over to correct
	-- with; one that has never got this corner wrong does not need as
	-- much. That is the entire mechanism by which experience makes them
	-- quicker, and it is bounded by physics rather than by a dial —
	-- nothing here can ask for a corner speed the kart cannot hold.
	local learned = BotBrain.confidenceAt(hereIdx)
	local margin = B.CornerMargin + (B.CornerMarginLearned - B.CornerMargin) * learned
	vLimit *= margin * (B.CornerMarginSkill + (1 - B.CornerMarginSkill) * bot.skill)

	-- Only bites when actually too fast. Below the limit this is zero and
	-- the bot is on full throttle, which is the half the bend-based rule
	-- got wrong in the other direction — it lifted on every bend whether
	-- it needed to or not.
	local over = math.clamp(speed / math.max(vLimit, 1) - 1, 0, 1)
	ease = math.max(ease, over * B.CornerBrakeHard)

	-- Throttle isn't a smooth function of anything for a human: they
	-- lift, reapply, and hold it slightly wrong throughout. A bot pinned
	-- at exactly 1.000 down every straight is a bot.
	bot.throttleAt += dt * B.ThrottleJitterRate
	local jitter = math.sin(bot.throttleAt * 2.3) * B.ThrottleJitter * (2 - bot.skill)

	c.touchThrottle = math.clamp(1 - ease + jitter, B.MinCornerSpeed, 1)

	-- Slower where it has gone off before. Same number that pulls the line
	-- in — a corner you keep running wide at is one you were carrying too
	-- much speed into, and a driver arrives at that conclusion too.
	if caution > 0 then
		c.touchThrottle *= 1 - math.clamp(caution * B.CautionLift, 0, B.CautionLiftMax)
	end

	-- A JUMP THE ROUTE CROSSES. Speed is what clears it, so every reason
	-- to lift is overruled — including the corner-braking above, which
	-- reads a ramp's approach as a bend and would take the pace off at
	-- exactly the wrong moment.
	if bot.jumping or (bot.rampAhead or 0) > B.RampCommitAt then
		c.touchThrottle = math.max(c.touchThrottle, B.JumpThrottle)
	elseif (bot.ledgeFor or 0) > 0 then
		-- Off the edge of the world beats every other consideration.
		-- Allowed below MinCornerSpeed, which nothing else is: that floor
		-- exists so bots don't crawl round corners, and it must not stop
		-- one slowing for a drop.
		c.touchThrottle = math.min(c.touchThrottle, B.LedgeThrottle)
	end

	----------------------------------------------------------------
	-- CRUISE — how fast this bot is actually willing to go.
	--
	-- THE ONE THAT MAKES THEM CATCHABLE, and it has to be done as a LIFT
	-- rather than as a smaller throttle. Simulation reads throttle as a
	-- gate, not a dial:
	--
	--     elseif throttle > 0.05 then target = H.MaxSpeed
	--
	-- Any throttle at all targets full speed. So scaling touchThrottle
	-- down — the obvious way to make a bot slower — changes nothing
	-- whatsoever until it crosses 0.05, at which point it changes
	-- everything. There is no middle.
	--
	-- A slower driver doesn't hold a smaller throttle anyway. They get to
	-- their pace and then feather it, which is exactly this: off the
	-- power above `cruise`, back on below it. CoastRate is gentle, so it
	-- reads as a driver holding a speed rather than as stuttering, and it
	-- gives the throttle trace the on/off texture a real one has.
	--
	-- A small band underneath, so it settles into a cruise instead of
	-- chattering on the threshold every frame.
	--
	-- Nitro deliberately still overrides this: a burn sets the speed
	-- target directly and bypasses throttle entirely, so a bot on boost
	-- goes properly quick — same as you.
	----------------------------------------------------------------
	-- Proper hysteresis, held in a flag rather than inferred from speed.
	--
	-- The first version put throttle to MinCornerSpeed (0.42) inside the
	-- band, which — by the very rule written above — is still wide open.
	-- 0.42 targets MaxSpeed exactly as hard as 1.0 does, so bots surged
	-- back to full speed the instant they dipped under cruise, and the
	-- cap did almost nothing. I made the mistake I had just documented.
	if speed > bot.cruise then
		bot.coasting = true
	elseif speed < bot.cruise * B.CruiseBand then
		bot.coasting = false
	end
	if bot.coasting then
		c.touchThrottle = 0
	end

	drawDebug(bot, aim, bend)

	----------------------------------------------------------------
	-- DRIFTING
	--
	-- Same trigger a player uses: a corner sharp enough to be worth it,
	-- at a speed where it pays. Rolled once per corner so a bot doesn't
	-- take every single one — that's the difference between a rival and
	-- a metronome.
	----------------------------------------------------------------
	-- PLANNED, not reacted to.
	--
	-- Deciding to drift when the corner is already under the wheels is
	-- what a bot does; a driver sees a corner coming, decides, and is
	-- already sideways by the time they reach it. That difference is
	-- visible from across the track — a reactive bot always initiates a
	-- beat late and finishes the corner straightening up.
	--
	-- So: scan ahead for the sharpest bend within reach, commit to it
	-- once, and hold the drift through the corner rather than re-asking
	-- every frame whether it's still sharp enough.
	local aheadBend, aheadAt = 0, 0
	for k = 1, 6 do
		local at = bot.u + k * (B.DriftScanAhead / 6)
		local b = bendAt(at, B.DriftBendLookahead, sim.up)
		if b > aheadBend then
			aheadBend, aheadAt = b, at
		end
	end

	--=============================================================
	--  DO NOT START A DRIFT YOU HAVE NO ROOM FOR.
	--
	--  A drift is a controlled slide OUTWARD, and nothing here ever
	--  asked whether there was road out there to slide onto. A bot
	--  already sitting near the edge would commit to one and leave the
	--  track every time — which is the single most common way they get
	--  off the grid.
	--
	--  Also suppressed during the launch settle: drifting off the line
	--  before the field has spread out is most of the opening-corner
	--  chaos, and a bot that just drives the first corner cleanly beats
	--  one that slides into the wall.
	--=============================================================
	-- Validate the WHOLE proposed manoeuvre, not only the road under the
	-- kart right now. A narrow entry or exit is just as capable of turning
	-- an otherwise good apex into a wall hit.
	local entry = aheadAt - B.DriftEntry * bot.skill
	local exit = aheadAt + B.DriftHold
	local function driftWindowSafe(): boolean
		local samples = math.max(B.DriftSafetySamples, 2)
		for sample = 0, samples - 1 do
			local at = entry + (exit - entry) * sample / (samples - 1)
			local node = math.floor(at) % math.max(#path, 1)
			local left, right = Route.roomAt(at, bot.branch, path)
			left = math.max(left - B.EdgeMargin, 0)
			right = math.max((right or left) - B.EdgeMargin, 0)
			-- Conservatively reserve drift room on both sides: the planner's
			-- line and drift direction can change through an S-bend.
			if math.min(left, right) < B.DriftNeedRoom then
				return false
			end
			if not BotBrain.driftOkAt(node) or BotBrain.tameAt(node) > B.LearnTameAt then
				return false
			end
		end
		return true
	end
	local haveRoom = driftWindowSafe()

	if
		not bot.driftPlan
		and aheadBend >= B.DriftBend
		and speed >= B.DriftMinSpeed
		and haveRoom
		and not learningInterrupted(bot)
		and (bot.settle or 1) >= B.DriftAfterSettle
		-- LEARNED: this corner keeps putting bots into a wall, so it is
		-- not one to be sideways in. Everywhere else still drifts.
	then
		-- Rolled once per corner. A bot that takes every drift perfectly
		-- is one you can never out-drive; missing some is what leaves the
		-- door open.
		if rng:NextNumber() < B.DriftChance * bot.skill then
			bot.driftPlan = {
				-- Entered BEFORE the apex, and how early is skill: a good
				-- driver commits sooner and carries more through.
				entry = entry,
				exit = exit,
			}
		else
			-- Remember we declined this one, so it isn't re-rolled every
			-- frame until it eventually says yes.
			bot.driftPlan = { declined = true, exit = aheadAt + B.DriftHold }
		end
	end

	local drifting = false
	if bot.driftPlan then
		if bot.u > bot.driftPlan.exit then
			bot.driftPlan = nil
		elseif not bot.driftPlan.declined then
			drifting = bot.u >= bot.driftPlan.entry and speed >= H.DriftExitSpeed
		end
	end
	if drifting and not c.driftHeld then
		c._driftPress = true -- the hop, exactly as a keypress would
	end
	c.driftHeld = drifting

	----------------------------------------------------------------
	-- HOPPING A MISSILE
	--
	-- The same input, for the same reason a player would use it, and it
	-- costs a bot the same thing: hopping mid-corner throws away the
	-- drift it was charging.
	--
	-- The decision is made ONCE per missile — `bot.dodging` is set when
	-- one gets close and the roll is taken there. Rolling per step at
	-- 60Hz turns any chance into a certainty, which this project has
	-- already paid to learn about nitro.
	----------------------------------------------------------------
	if bot.dodging and sim.grounded then
		c._driftPress = true
		bot.dodging = false
	end

	----------------------------------------------------------------
	-- NITRO
	--
	-- Spent on straights, where a player would. Holding out for three
	-- full tanks is optimal and inhuman, so mostly they don't.
	----------------------------------------------------------------
	-- A CHANCE PER SECOND, NOT PER STEP.
	--
	-- This is why they were uncatchable. The old roll ran every step — 75
	-- times a second — so a "40% chance to hold" was really a 40% chance
	-- to hold FOR ONE SEVENTY-FIFTH OF A SECOND. It fired essentially
	-- immediately, every time, meaning bots burned nitro the instant they
	-- banked a tank and were on a straight.
	--
	-- And nitro bypasses the cruise cap entirely, because a burn sets the
	-- speed target directly: stage 1 is MaxSpeed + 18, stage 3 is
	-- MaxSpeed + 80. So the one thing that could beat the pace limit was
	-- also the thing running permanently.
	--
	-- Scaled by dt it means what it reads like, and a cooldown afterwards
	-- stops a bot chaining tanks back-to-back down one straight.
	if
		sim.tanks >= B.NitroMinTanks
		and bend <= B.NitroStraight
		and sim.burnStage == 0
		and os.clock() >= (bot.nitroReadyAt or 0)
	then
		-- Better drivers spend it a little more readily.
		local odds = B.NitroUsePerSecond * (0.6 + 0.4 * bot.skill) * dt
		if rng:NextNumber() < odds then
			c._nitroTaps += 1
			bot.nitroReadyAt = os.clock() + B.NitroCooldown
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
-- IS THERE ANYBODY TO SHOOT AT?
--
-- Straight-line, in front, within range. Deliberately crude: this is a
-- driver glancing up the road, not a targeting computer, and a bot that
-- only ever fires on a perfect solution is a bot that never misses.
local function somebodyAhead(bot, back: boolean): boolean
	local sim = bot.sim
	local sign = if back then -1 else 1
	for _, k in Standings.allKarts() do
		local hb = k.PrimaryPart
		if k ~= bot.kart and hb then
			local away = hb.Position - sim.pos
			if away:Dot(sim.forward) * sign > 0 and away.Magnitude <= B.FireRange then
				return true
			end
		end
	end
	return false
end

local function useItem(bot)
	local item = bot.item
	if not item then
		return
	end

	local sim = bot.sim
	local back = rng:NextNumber() > B.ForwardChance

	----------------------------------------------------------------
	-- HOLD FIRE, SOMETIMES.
	--
	-- A missile down an empty straight is wasted, and a bot that never
	-- notices looks like it is firing at random — which it was.
	--
	-- Patience scales with skill, so a bad bot shoots at nothing and
	-- keeps doing it. That is not a handicap bolted on afterwards, it is
	-- what a bad player looks like, and it is the difference between
	-- losing to a computer and losing to a driver.
	--
	-- PatienceLimit stops it becoming a bot that hoards: past that it
	-- fires regardless, target or no target.
	----------------------------------------------------------------
	if item.Projectile and not somebodyAhead(bot, back) then
		bot.itemHeldSince = bot.itemHeldSince or os.clock()
		local waited = os.clock() - bot.itemHeldSince
		local patience = B.PatienceMin + (B.PatienceMax - B.PatienceMin) * skillFrac(bot)
		if waited < B.PatienceLimit and rng:NextNumber() < patience then
			-- Look again shortly. Not every frame: a decision this cheap
			-- still does not need making sixty times a second.
			bot.itemAt = os.clock() + 0.4
			return
		end
	end

	bot.item = nil
	bot.itemHeldSince = nil

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
	if landed then
		markExternalInterference(bot, math.max(item.SpinTime or 0, item.StunTime or 0), item.Id)
	end
	if landed and (item.SpinTime or 0) > 0 then
		bot.item = nil
	end

	-- Whoever laid it gets the credit, exactly as when a player hits one.
	local ownerId = hz:GetAttribute(Names.OWNER)
	local owner = ownerId and ownerId ~= 0 and Players:GetPlayerByUserId(ownerId)
	RaceService.announce(item.Id, if owner then owner.DisplayName else nil, bot.name, bot.kart)
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
		-- Fresh item, fresh patience. Without this a bot that waited out
		-- a whole PatienceLimit on one missile fires the next one
		-- instantly, having inherited a clock that ran out before it
		-- owned the thing.
		bot.itemHeldSince = nil
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
	-- ROLLING, not racing. Nothing counts any more once the flag is out,
	-- but the karts keep going — the results board plays over a track
	-- that is still moving rather than over a freeze frame.
	local racing = Match.isRolling(MatchService.phase())
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

		-- A finished racer gets a tiny coast for the finish camera, then parks.
		-- This intentionally bypasses the normal bot loop: a completed kart
		-- must never collect a box, learn from traffic, or throw a power-up.
		if bot.finished and racing then
			if not bot.parked and now < (bot.parkAt or now) then
				bot.controls.touchThrottle = 0
				bot.controls.touchSteer = 0
				bot.sim:Step(dt, bot.controls)
			elseif not bot.parked then
				bot.parked = true
				bot.controls.touchThrottle = 0
				bot.controls.touchSteer = 0
				local body = bot.kart.PrimaryPart
				if body then
					body.Anchored = true
				end
			end
			continue
		end

		----------------------------------------------------------------
		-- BACK TO THE GRID
		--
		-- Flagged by the match, NOT detected by watching the grid CFrame
		-- change. Slot 3 is in the same place every round, so "has this
		-- attribute changed" is true exactly once and never again — bots
		-- lined up for the first race and then stayed wherever the last
		-- one left them, for the rest of the server's life.
		--
		-- The client keys off the round NUMBER for the same reason. This
		-- is the server-side half of the same idea.
		----------------------------------------------------------------
		if bot.needsGrid then
			local grid = bot.kart:GetAttribute(Match.GRID_CF)
			if typeof(grid) == "CFrame" then
				bot.needsGrid = false
				bot.sim:RespawnAt(grid)
				bot.sim:ResetForRound()
				bot.u = Route.nearestU(grid.Position, Route.path())
				bot.lastU = nil
				-- The grid IS a known-good position, and last round's is
				-- not — reviving to a corner from the previous race would
				-- put a bot on the track mid-lap before the lights go out.
				bot.safeU = bot.u
				bot.safeCF = grid
				bot.revives = 0
				bot.ledgeFor = 0
				-- Caution SURVIVES the restart on purpose. It's what the
				-- bot has learned about this track, and three laps is
				-- nowhere near enough to converge — throwing it away every
				-- round means it never learns anything at all.
				bot.laps = 0
				-- Back to needing checkpoint 1 next. Without this a bot
				-- carries last round's position in the sequence into the
				-- new one and is credited a lap for reaching a gate it
				-- passed before the restart.
				-- The lap's DISTANCE counter, not a sequence index. Reset
				-- for the same reason the old one was: carrying last
				-- round's progress into a new one credits a lap that was
				-- driven before the restart.
				bot.lapU = 0
				bot.lastNodeIdx = -1
				bot.lastU = nil
				bot.airFor = 0
				bot.item = nil
				bot.finished = nil
				bot.parked = nil
				bot.parkAt = nil
				bot.heldSteer = 0
				table.clear(bot.sawSteer)
				log("%s on the grid", bot.name)
			end
		end

		----------------------------------------------------------------
		-- IDLE — parked, wagging the wheel.
		--
		-- Steps the simulation with zero throttle, so the kart settles on
		-- the ground properly rather than being frozen mid-air, and wags
		-- the steering so the wheel turns and the driver's arms follow.
		-- Rider does the rest; it reads the same attribute a racing bot
		-- publishes.
		----------------------------------------------------------------
		if B.Idle then
			bot.sim:Hold(false)
			bot.controls.touchThrottle = 0
			bot.controls.touchSteer = math.sin(now * B.IdleSteerRate * math.pi * 2) * B.IdleSteerAmount
			bot.controls.driftHeld = false
			bot.sim:Step(dt, bot.controls)
			bot.kart:SetAttribute(Names.STEER, bot.sim.steer)
			bot.kart:SetAttribute(Names.DRIFT, bot.sim.driftAngle)
			continue
		end

		-- Held on the grid exactly like a player, so the countdown means
		-- the same thing for everybody.
		bot.sim:Hold(not racing)

		--------------------------------------------------------------
		-- AND ACTUALLY PINNED THERE.
		--
		-- Hold() stops the kart being DRIVEN, and that is all it claims
		-- to do. It does not stop the kart being moved by anything else,
		-- and something else was moving them: bots drifted off the grid
		-- through the warm-up and the countdown, which is unfair before a
		-- race and looks broken during one.
		--
		-- Rather than hunt every possible nudge through the simulation,
		-- this asserts the thing we actually want. The grid CFrame is
		-- already published per kart for exactly this purpose, so a bot
		-- that has wandered off its slot is simply put back on it.
		--
		-- Tolerance, not a per-frame reset: a kart settling onto the pad
		-- under gravity moves a little and should be left alone. Only a
		-- bot that has genuinely left its slot gets corrected, so this is
		-- silent in the normal case.
		--
		-- Deliberately NOT a physics change. Nothing in Simulation is
		-- touched; this is the match telling a kart where it belongs
		-- between rounds, which is the match's job.
		--------------------------------------------------------------
		if not racing then
			local grid = bot.kart:GetAttribute(Match.GRID_CF)
			if typeof(grid) == "CFrame" and (bot.sim.pos - grid.Position).Magnitude > B.GridHoldTolerance then
				bot.sim:RespawnAt(grid)
			end
		end


		-- Fell off the world, or ended up somewhere the road isn't. No
		-- character to re-seat, so it puts itself back on the racing line
		-- — which it already knows how to find.
		--------------------------------------------------------------
		-- FLYING WATCHDOG.
		--
		-- A NET, NOT A CURE, and worth being honest about which. The
		-- cause of a bot occasionally taking off is still unknown — it
		-- is rare now rather than constant — so this does not pretend to
		-- fix it. It bounds the damage: a kart that has been off the
		-- ground implausibly long, or has climbed far above the racing
		-- line it is supposed to be driving, is put back on that line.
		--
		-- Two tests because they catch different failures. A long air
		-- time catches a slow floater that never comes down; height
		-- above the route catches one launched hard, which can be back
		-- on the ground quickly and a hundred studs up in between.
		--
		-- Both thresholds are set well beyond any legitimate jump, so a
		-- real ramp is never interrupted. If this fires, the log line
		-- says which test tripped and how far it got, which is the
		-- evidence needed to actually diagnose it.
		--------------------------------------------------------------
		-- RAMPS ARE LEGITIMATE AIR, AND THIS USED TO NOT KNOW THAT.
		--
		-- The thresholds were chosen when the only way off the ground was
		-- a hop, and the comment above still claims they sit "well beyond
		-- any legitimate jump". The glider broke that: 2*46/24 is 3.83s of
		-- ballistic airtime against a 4s limit, and the flare CAPS the
		-- descent, so a real glide runs longer than the arc says and
		-- routinely trips it. The bot was then teleported back mid-flight.
		-- Apex is 44 studs too, against a 60-stud ceiling that an elevated
		-- ramp clears easily.
		--
		-- So the watchdog now measures UNEXPLAINED air only. A glide or a
		-- trick is a state the simulation knows about; while one is
		-- running there is nothing to recover from, and the safety net is
		-- still there for everything else.
		--  AND A PLAIN RAMP OVER A GAP, which this still did not cover.
		--
		--  Glides and tricks were excused, but the commonest long flight
		--  is neither: an ordinary launch across a gap the route crosses.
		--  `bot.jumping` is already the flag for exactly that — "the road
		--  carries on over there, this is a ramp and not a cliff" — and
		--  the watchdog was not consulting it. A landing far enough away
		--  therefore exceeded MaxAirTime mid-flight and the bot was
		--  yanked back, which is the same failure the glider had.
		--
		--  LATCHED, because `jumping` is about the road ahead and can go
		--  false in the last moments of a flight that is going perfectly
		--  well. It is cleared on touchdown.
		--
		--  EXCUSED IS NOT UNLIMITED. A deliberate jump gets a much longer
		--  leash, not an infinite one, so a bot that genuinely ends up
		--  flying forever is still recovered — it just is not interrupted
		--  for doing the thing the track asked it to do.
		if bot.sim.grounded then
			bot.airLaunched = false
		elseif bot.jumping then
			bot.airLaunched = true
		end

		local excused = bot.sim.state == "glide" or (bot.sim.trickUntil or 0) > os.clock()
		local limit = if bot.airLaunched then B.MaxAirTimeJumping else B.MaxAirTime
		local ceiling = if bot.airLaunched then B.MaxAboveRouteJumping else B.MaxAboveRoute
		if bot.sim.grounded or excused then
			bot.airFor = 0
		else
			bot.airFor = (bot.airFor or 0) + dt
		end

		local above = 0
		local onLine = Route.pointAt(bot.u, bot.branch, Route.path())
		if onLine then
			above = bot.sim.pos.Y - onLine.Y
		end

		if not excused and ((bot.airFor or 0) > limit or above > ceiling) then
			warn(
				("[BotService] %s recovered by the flying watchdog — airborne %.1fs, %.0f studs above the racing line, speed %.0f. This is a safety net; the cause is still unknown."):format(
					bot.name,
					bot.airFor or 0,
					above,
					bot.sim.speed
				)
			)
			bot.airFor = 0
			-- LEARNED FROM, like every other way of ending up somewhere
			-- you should not be. The comment above says the cause is
			-- unknown, and that is exactly why it is worth recording:
			-- bots repeatedly launching into space at one node is a fact
			-- about that node whether or not anyone knows the mechanism,
			-- and approaching it more carefully is the right response to
			-- a hazard you cannot explain.
			BotService.noteWentOff(bot)
			BotService.revive(bot)
		end

		--=============================================================
		--  THE VOID, WHICH BOTS USED TO DRIVE STRAIGHT THROUGH.
		--
		--  A player gets three ways back: the VoidZone tag, freefall
		--  time, and a world floor. A bot only ever had the floor — so a
		--  void that is a PLANE at track level (water, lava, a shallow
		--  pit) never triggered, and the bot drove through it and kept
		--  going until it happened to fall far enough.
		--
		--  That is most of "bots leave the track": they were not leaving
		--  it once, they were leaving it and continuing to drive around
		--  outside it, reported each time they eventually dropped.
		--
		--  Same tag, same helper, same rule as the player. It has to be
		--  the same one — a second answer to "where is the void" is the
		--  oldest bug shape in this project.
		--=============================================================
		if voidZones and now - (bot.voidAt or 0) > B.VoidCooldown then
			local hitbox = bot.kart.PrimaryPart
			if hitbox and voidZones:Touch(hitbox.CFrame, hitbox.Size) then
				bot.voidAt = now
				-- Counted as leaving the track, because it is, and the
				-- existing message already says where and how far off.
				bot.revives = (bot.revives or 0) + 1
				BotService.noteWentOff(bot)
				BotService.revive(bot)
				continue
			end
		end

		if bot.sim.pos.Y < Config.Rig.RespawnBelow then
			-- Counted, because a bot that rejoins the line over and over is
			-- not falling off the map — something is putting it back, and
			-- that reads from outside as flying to the checkpoint.
			-- Counted AND located. The count alone said a bot kept coming
			-- back; it took a screenshot to find out the bot was driving
			-- off the right-hand edge every lap, so the count now carries
			-- the one fact that identifies that: which side it left from,
			-- and how far off the racing line it was when it went.
			bot.revives = (bot.revives or 0) + 1
			if bot.revives % 5 == 1 then
				local off = Route.lateralAt(bot.safeU or bot.u, bot.sim.pos, bot.sim.up) or 0
				warn(
					("[BotService] %s left the track %d time(s) — last seen %.0f studs %s of the racing line near node %.1f (road is %.0f wide there). Off-centre by more than half the road means it is steering off, not falling through."):format(
						bot.name,
						bot.revives,
						math.abs(off),
						if off >= 0 then "RIGHT" else "LEFT",
						bot.safeU or bot.u or 0,
						Route.halfWidthAt(bot.safeU or bot.u or 0) * 2
					)
				)
			end
			BotService.noteWentOff(bot)
			BotService.revive(bot)
		end

		local ok, err = pcall(function()
			if racing then
				drive(bot, dt)
				collect(bot)
				checkHazards(bot)
				checkPads(bot)
				if bot.item and now >= bot.itemAt then
					useItem(bot)
				end
				-- Laps, from the route wrapping rather than from trigger
				-- volumes: a bot is already tracked by `u`, so watching it
				-- wrap is free and can't miss a gate at speed.
				-- CHECKPOINTS, IN ORDER, LIKE YOU HAVE TO.
				--
				-- A lap used to be credited purely on `u` wrapping past
				-- half the track, which is not the same thing as visiting
				-- the checkpoints at all. Anything that moved a bot a long
				-- way — flying, a shortcut across the infield, a respawn —
				-- wrapped `u` and paid out a lap it had not driven. You
				-- have to pass every gate; bots were on a weaker rule, and
				-- that is exactly as unfair as it sounds.
				--
				-- Now it must reach each node in sequence. Skipping one
				-- means the counter simply stops advancing until it comes
				-- back for it, so a bot that flies over half the track
				-- gains nothing at all from the trip.
				--=================================================
				--  ONE LAP RULE FOR EVERYONE.
				--
				--  Bots used to need every path node index IN ORDER,
				--  while players need the finish line plus 80% of the
				--  route driven. Two different rules producing one
				--  number that placement sorts on.
				--
				--  On a dense path that is 61 indices a bot has to hit
				--  exactly. One miss — a knock, a respawn, a windowed
				--  nearestU stepping over it — and `nextIdx` stalls, so
				--  the lap never counts and the bot sits a whole lap
				--  behind in the standings while driving perfectly well.
				--  That is the placement being wrong, and it was never
				--  about the bot.
				--
				--  Now it accumulates forward route distance exactly as
				--  Race.luau does, and banks a lap on passing the start
				--  node having covered `LapNeed` of the path. Same
				--  question, same answer, whoever is asking.
				--=================================================
				local n = #Route.path()
				if n > 0 and bot.lastU then
					local step = bot.u - bot.lastU
					if step < -n * 0.5 then
						step += n -- unwrapped: crossing node 0
					end
					-- Small forward steps only. A big jump is a respawn
					-- or a teleport, and neither is distance driven.
					if step > 0 and step < n * Config.Race.LapStepMax then
						bot.lapU = (bot.lapU or 0) + step
					end

					local at = math.floor(bot.u) % n
					if at == 0 and (bot.lastNodeIdx or -1) ~= 0 then
						if (bot.lapU or 0) >= n * Config.Race.LapNeed then
							bot.lapU = 0
							bot.laps += 1
							-- A lap survived is evidence the caution worked,
							-- so let it fade. Otherwise one incident makes a
							-- bot crawl that corner for the rest of the
							-- server's life.
							BotService.decayCaution(bot)

							-- NEW LAP, NEW WAY THROUGH THE SPLITS. Chosen
							-- once at spawn, a bot takes the same side of
							-- every fork for the whole race, which is the
							-- variety the fork was built for not happening.
							-- Re-rolled here rather than mid-lap, because
							-- swapping branches while approaching one is a
							-- bot changing its mind at the divider.
							bot.branch = math.random(1, 4)

						end
					end
					-- Edge-triggered: the lap banks on ARRIVING at node 0,
					-- not on every frame spent sitting on it.
					bot.lastNodeIdx = at
				end

				-- ONE OFFICIAL FINISH RULE. `bot.laps` above exists only for
				-- branch/caution learning; it must never decide placement or a
				-- finish. RaceService projects this bot's physical kart onto the
				-- same authored path, samples the same end zone, and banks the
				-- same route-distance proof as it does for a player.
				if not bot.kart:GetAttribute(Match.FINISH_PLACE) and RaceService.canFinish(bot.kart) then
					local since = MatchService.racingSince()
					if since then
						MatchService.botFinished(bot.kart, bot.name, workspace:GetServerTimeNow() - since)
					end
				end
				--=================================================
				--  GOING NOWHERE FAST.
				--
				--  Every recovery so far asks "is it off the track" or
				--  "is it in the air". None of them ask the question a
				--  tube actually poses: the bot is ON the road, moving
				--  at speed, upright, and making NO PROGRESS ALONG IT.
				--
				--  In a rounded section the lateral direction curves
				--  around the barrel, so a bot that drifts off the
				--  centreline can drive round the circumference instead
				--  of down the length. Nothing is wrong by any existing
				--  test — it is simply orbiting.
				--
				--  Measured on `u`, unwrapped, because that is the only
				--  thing that means "further round the lap". Speed is
				--  deliberately part of it: a bot sat still at the
				--  lights is not lost, and one pinned against a wall is
				--  already handled by the stuck check.
				--=================================================
				if bot.lastU then
					local step = bot.u - bot.lastU
					local nodes = #Route.path()
					if nodes > 0 and step < -nodes * 0.5 then
						step += nodes
					end
					if step > B.LostStep or math.abs(bot.sim.speed) < B.LostMinSpeed then
						bot.lostFor = 0
					else
						bot.lostFor = (bot.lostFor or 0) + dt
					end
				end
				bot.lastU = bot.u

				--=================================================
				--  WHAT THIS NODE JUST DID TO THIS BOT.
				--
				--  Reported per NODE CROSSING rather than per frame,
				--  so a bot grinding a wall for a second logs one
				--  incident and not sixty. `wallHere` latches while
				--  inside a node and is banked when it leaves.
				--=================================================
				local hereNode = math.floor(bot.u) % math.max(#Route.path(), 1)
				if hereNode ~= bot.lastNode then
					if bot.lastNode then
						-- HOW LONG SHOULD THIS HAVE TAKEN? The segment's
						-- own length at an unremarkable pace — so a long
						-- straight is not reported for being long, and a
						-- short tunnel is not excused for being short.
						local span = Route.segmentLength(bot.lastNode, Route.path())
						local expect = span / math.max(H.MaxSpeed * B.LearnSlowPace, 1)
						local took = now - (bot.nodeAt or now)
						local interrupted = learningInterrupted(bot)
						if not interrupted then
							if bot.wallHere then
								BotBrain.hitWall(bot.lastNode)
							elseif took > expect * B.LearnSlowFactor then
								BotBrain.wasSlow(bot.lastNode)
							else
								BotBrain.gotThrough(bot.lastNode)
							end
						end
					end
					bot.lastNode = hereNode
					bot.wallHere = false
					-- If this segment starts under an item effect, keep it
					-- excluded even if the effect expires just before it ends.
					bot.segmentExternallyDisrupted = now < (bot.externalInterferenceUntil or 0)
					bot.nodeAt = now
				end

				if (bot.lostFor or 0) > B.LostTime then
					bot.lostFor = 0
					-- STEER HOME FIRST, revive only if that fails. A
					-- teleport is jarring and visible; being nudged back
					-- onto the line is neither, and in a tube it is
					-- usually all that is needed.
					bot.homeFor = B.LostSteerHome
					bot.lostTries = (bot.lostTries or 0) + 1
					if bot.lostTries > B.LostTriesBeforeRevive then
						bot.lostTries = 0
						warn(
							("[BotService] %s was going nowhere near node %.1f — steering home did not work, putting it back. Usually a rounded section where the lateral axis curves around the barrel."):format(
								bot.name,
								bot.u
							)
						)
						BotService.noteWentOff(bot)
						BotService.revive(bot)
					end
				end
			end
			-- EVENTS WERE BEING THROWN AWAY. The simulation already
			-- reports a wall hit; nothing server-side was listening, so
			-- "this bot keeps hitting things" was unknowable.
			--
			-- Latched rather than counted: one contact is one incident
			-- for this node however many frames it lasts.
			local events = bot.sim:Step(dt, bot.controls)
			if typeof(events) == "table" and (events.wallStunned or events.bounced) then
				bot.wallHere = true
			end
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
				if bot.sim.grounded then "" else "AIRBORNE — no ground under it"
			)
		end

		-- RaceService is the sole writer of KartProgress, RacePlace and
		-- RaceFieldSize for EVERY racer. BotService has its own `bot.u` for
		-- steering, but publishing it used a second lap bank between the
		-- server standings ticks and could make a bot look ahead on a
		-- different ruler than a player.
		-- And its steering, so Rider turns the wheel and the front tyres.
		bot.kart:SetAttribute(Names.STEER, bot.sim.steer)
		bot.kart:SetAttribute(Names.DRIFT, bot.sim.driftAngle)

		-- The shield bubble, which nothing else would ever show for a bot.
		--
		-- Effects drives it for a player and only ever looks at the local
		-- kart. A bot has no client at all, so its bubble stays however
		-- KartFactory left it — hidden. This is the other half: the server
		-- owns a bot's simulation, so the server shows the shield.
		--
		-- Toggled on change, not written every step: this walks the model,
		-- and doing that per step per bot to set a value already correct
		-- is pure waste.
		local shielded = bot.sim:HasShield()
		if shielded ~= bot.shieldShown then
			bot.shieldShown = shielded
			setShieldVisible(bot.kart, shielded)
		end
	end
end

--=====================================================================
--  LIFECYCLE
--=====================================================================
-- Called by MatchService as a round starts. Tops the field up and sends
-- everybody back to the grid.
--
-- The flag rather than the placement, because this fires BEFORE
-- KartService.assignGrid has written the positions — so the bots pick
-- them up on their next step, once they exist.
function BotService.onGrid()
	BotService.fill()
	for _, bot in bots do
		bot.needsGrid = true
	end
end

-- Builds the bot state for a kart that already exists.
--
-- Lifted out of fill() so a HUMAN'S kart can be handed to the AI on
-- exactly the same terms. A takeover that built its own slightly
-- different bot would drift out of step with the real one the first time
-- either changed, and the whole point is that a taken-over kart drives
-- like every other bot.
local function makeBot(name: string, racer: any, kart: Model, hitbox: BasePart, seat: Instance, avatarUserId: number?)
	-- Rolled before the table, so cruise can be derived from it.
	local skill = rng:NextNumber(B.SkillMin, B.SkillMax)

	-- A bot's name has to reach the client, because every screen that
	-- lists racers needs it — results, spectator, the reward panel. It
	-- was only ever on the rig, which is server-side furniture, so those
	-- screens all showed a bot as "Racer" or as the model's name.
	-- KartService already stamps this for players; this is the other
	-- half of the same answer.
	kart:SetAttribute(Names.RACER_NAME, name)

	local bot = {
		name = name,
		fallbackName = name,
		avatarUserId = avatarUserId,
		racer = racer,
		kart = kart,
		sim = Simulation.new(kart, hitbox, seat),
		controls = bindControls(newControls()),
		-- One roll, and it scales everything. A low-skill bot is a
		-- worse driver, not a slower one.
		skill = skill,
		-- The speed it settles at on a straight, in studs/s. A limit
		-- on the DRIVER — see the cruise block in drive() — not on the
		-- kart, which is identical to yours and always will be.
		cruise = Config.Handling.MaxSpeed * (B.CruiseMin + (B.CruiseMax - B.CruiseMin) * skill),
		-- WHERE ON THE ROAD THIS BOT SITS, as a fraction from -1 (left
		-- edge) to +1 (right edge). NOT studs.
		--
		-- drive() multiplies it by the road width available on that side,
		-- so the spread scales with the tarmac instead of being clamped
		-- to the edges on a narrow section. Leaving LineOffset in here
		-- made the product nine times too large — every bot pinned to an
		-- edge, which is worse than the stacking it was meant to fix.
		lineBias = rng:NextNumber(-1, 1),
		lineAt = rng:NextNumber(0, 6),
		-- Per-bot phase, so two of them never wander or jitter in step
		-- with each other — synchronised imperfection looks more
		-- mechanical than no imperfection at all.
		noiseAt = rng:NextNumber(0, 20),
		throttleAt = rng:NextNumber(0, 20),
		sawSteer = {},
		heldSteer = 0,
		lastCrossErr = nil,
		crossRate = 0,
		-- Placed on the grid by its first step, so a bot joining
		-- mid-intermission still starts from the line.
		needsGrid = true,
		u = 0,
		laps = 0,
		-- The checkpoint it must reach next, counted upward and taken
		-- mod the node count. Sequential, so skipping a gate stalls
		-- progress until the bot comes back for it — the same rule a
		-- player is held to.
		-- Seconds off the ground, for the flying watchdog.
		airFor = 0,
		driftPlan = nil,
		item = nil,
		itemAt = 0,
		lastU = nil,
		-- Where it last had wheels on measured road, and the checkpoint
		-- that goes with it. revive() keeps the second and deliberately
		-- throws away the first — see the comment there.
		safeU = nil,
		lostFor = 0,
		loopNode = nil,
		loopAt = 0,
		loopCount = 0,
		lapU = 0,
		lastNodeIdx = -1,
		rampAhead = 0,
		nodeAt = 0,
		airLaunched = false,
		lastNode = nil,
		wallHere = false,
		externalInterferenceUntil = 0,
		segmentExternallyDisrupted = false,
		homeFor = 0,
		lostTries = 0,
		safeCF = nil,
		-- Seconds left of "there's no road that way". Held briefly
		-- rather than read per frame, or a bot skimming an edge
		-- flickers between two lines and commits to neither.
		ledgeFor = 0,
		-- True while the route carries on across a gap ahead: a ramp,
		-- not a cliff. Overrides every reason to lift.
		jumping = false,
		-- checkpoint index -> how much this bot has learned to distrust
		-- that stretch. Per bot: it's a driver learning a circuit, not
		-- a fact about the circuit.
		caution = {},
		--=============================================================
		--  WHICH WAY IT TAKES AT A FORK.
		--
		--  Two checkpoints sharing an order is an authored SPLIT — left
		--  way and right way, same progress. The route's node for that
		--  order is the centroid of the two, which is the wall between
		--  them, and every bot drove at it.
		--
		--  A bot now commits to one gate and steers through it. Picked
		--  at random per bot so a field spreads across both ways rather
		--  than filing down one, and re-rolled each lap so the same bot
		--  does not take the same line all race — the variety the split
		--  was built for only shows up if they actually vary.
		--
		--  Any number works: it is taken modulo the number of gates at
		--  whichever fork is reached, so it is meaningful at a
		--  three-way split and harmless where there is no fork at all.
		--=============================================================
		branch = math.random(1, 4),
		-- A glide ramp is a route and always taken; a flip ramp is a
		-- boost, so whether this bot bothers is personality. Rolled once
		-- at spawn — a bot that changes its mind about the same ramp
		-- every lap reads as indecision rather than character.
		takesFlips = math.random() < 0.6,
		dbg = {},
		boxes = TagZones.new(Config.Items.BoxTag, { cooldown = Config.Items.PickupCooldown, forceQueryable = true }),
		drops = TagZones.new(Config.Items.DropTag, { cooldown = 0.5, forceQueryable = true }),
		-- Bots drove straight over mines and oil without noticing:
		-- hazards are detected by whoever hits them, and nothing was
		-- doing that on their behalf.
		hazards = TagZones.new(Config.Items.HazardTag, { cooldown = 0.5, forceQueryable = true }),
		--=============================================================
		--  BOOST PADS, WHICH BOTS COULD NOT USE AT ALL.
		--
		--  `Boosters` lives in StarterPlayerScripts, so it is a CLIENT
		--  module and the server never ran it. Bots drove over every pad
		--  on the track and nothing happened — so on any circuit with
		--  pads they were slower than a player for a reason that had
		--  nothing to do with driving.
		--
		--  The definitions still come from Config.Boosters.Pads, so what
		--  a pad DOES cannot differ between bots and players. Only the
		--  touch loop is repeated, and it is eight lines.
		--=============================================================
		padZones = (function()
			local zones = {}
			for _, def in Config.Boosters.Pads do
				table.insert(zones, {
					def = def,
					zone = TagZones.new(def.Tag, {
						cooldown = Config.Boosters.Cooldown,
						forceQueryable = Config.Boosters.ForceQueryable,
					}),
				})
			end
			return zones
		end)(),
		padNextAt = 0,
	}
	publishBotIdentity(bot)
	return bot
end

--=====================================================================
--  TAKEOVER
--
--  Hands a finished player's kart to the AI so the race behind them
--  still has a full field to fight through.
--
--  WHY THIS WORKS AT ALL, given the framework: a bot IS a kart with a
--  server-side Simulation and an anchored hitbox, and a player's kart is
--  a kart with a client-side Simulation and a client-owned hitbox. The
--  takeover is just moving it from the second arrangement to the first.
--
--  ONE AUTHORITY, and that is the whole risk. Network ownership has to
--  be revoked and the hitbox anchored BEFORE the bot starts stepping it,
--  or the driver's client and the server both write the CFrame and the
--  kart tears itself apart — the same two-authorities failure that made
--  bot karts float earlier in the project.
--
--  The kart is marked so nothing else tries to give it back: the
--  ownership watchdog re-asserts a driver's ownership every couple of
--  seconds and would otherwise undo this immediately.
--=====================================================================
function BotService.takeOver(kart: Model, name: string): boolean
	if not B.TakeOverOnFinish or not kart or not kart.Parent then
		return false
	end
	-- Already driving itself, or already a bot's.
	if kart:GetAttribute(Names.AI_DRIVEN) then
		return false
	end
	for _, bot in bots do
		if bot.kart == kart then
			return false
		end
	end

	local hitbox = kart.PrimaryPart
	local seat = kart:FindFirstChild("Seat")
	if not (hitbox and seat) then
		return false
	end

	-- READ THE SPEED BEFORE ANCHORING, because anchoring destroys it.
	-- The hitbox is a physics part right up to this line and its velocity
	-- is the only record of how fast the driver was going. A frame later
	-- it is zero and unrecoverable.
	local carried = 0
	local pose = hitbox.CFrame
	pcall(function()
		local vel = hitbox.AssemblyLinearVelocity
		-- Along the kart's own heading, not the raw magnitude: a kart
		-- dropping off a ledge is moving fast downward and should not
		-- inherit that as forward speed.
		carried = math.max(vel:Dot(pose.LookVector), 0)
	end)

	-- ORDER IS LOAD-BEARING. Mark first so the watchdog can never race
	-- us, then take ownership back, then anchor. Anchoring while a client
	-- still owns the part is the one ordering that visibly breaks.
	kart:SetAttribute(Names.AI_DRIVEN, true)
	pcall(function()
		hitbox:SetNetworkOwner(nil)
	end)
	hitbox.Anchored = true
	-- PINNED TO WHERE IT ACTUALLY WAS. Handing ownership back and
	-- anchoring in the same frame lets the physics system settle the part
	-- on the server's own last authoritative pose, which can be behind
	-- the one the driver was looking at. Writing the captured pose back
	-- makes the handover start exactly where the kart appeared to be, and
	-- an anchored part will not be moved out from under it.
	hitbox.CFrame = pose

	local bot = makeBot(name, { Name = name, Bot = true }, kart, hitbox, seat)
	-- It inherits the race in progress rather than starting a fresh one:
	-- the position, lap and checkpoint it had when its driver finished
	-- are still true, and resetting them would drop it to last.
	-- lapsFrom, NOT Route.passedFrom. Both decode the same packed score
	-- and they return different fields — passedFrom gives checkpoints,
	-- which as a lap count is nonsense.
	-- AND IT INHERITS THE SPEED. A new Simulation starts at zero, so the
	-- AI used to take the wheel from a dead stop — the kart braked to
	-- nothing the instant you crossed the line and then pulled away
	-- again, which is the stop-and-restart at the flag.
	--
	-- Clamped to the real maximum: a kart that was boosting hands over
	-- above it, and inheriting that would let the AI keep boost speed it
	-- never earned.
	-- MARKED, because this entry drives somebody else's kart. When that
	-- kart goes, this bot goes with it — it must never build a
	-- replacement.
	bot.takenOver = true
	bot.sim.speed = math.min(carried, Config.Handling.MaxSpeed)
	-- Travel matches the heading it actually had, or the first frames of
	-- AI driving are spent unwinding a direction the kart was never
	-- going in.
	bot.sim.travel = pose.LookVector

	bot.laps = Standings.lapsFrom(kart:GetAttribute(Standings.ATTRIBUTE))
	bot.u = Route.nearestU(bot.sim.pos, Route.path())
	-- Taking over mid-race: no distance banked for this lap yet, and no
	-- previous `u` to measure a step against.
	bot.lapU = 0
	bot.lastNodeIdx = -1
	bot.lastU = nil
	bot.safeU = bot.u
	-- No rig: the finished player is still sitting in it, which is
	-- exactly what it should look like.
	table.insert(bots, bot)
	log("%s handed to the AI", name)
	return true
end

-- Finish takeover is deliberately not a normal race takeover. It preserves
-- the kart and a short visible coast, but permanently removes it from every
-- competitive bot behaviour until the next grid resets it.
function BotService.parkFinished(kart: Model, name: string): boolean
	local target = nil
	for _, bot in bots do
		if bot.kart == kart then
			target = bot
			break
		end
	end
	if not target then
		if not BotService.takeOver(kart, name) then
			return false
		end
		for _, bot in bots do
			if bot.kart == kart then
				target = bot
				break
			end
		end
	end
	if not target then
		return false
	end
	target.finished = true
	target.parked = false
	target.parkAt = os.clock() + M.FinishDriveTime
	target.item = nil
	target.itemAt = math.huge
	return true
end

-- Gives a taken-over kart back, so the next round starts clean and its
-- owner drives their own kart again.
-- Unhooks the AI from ONE kart and cleans up everything it owned.
-- Called when a kart retires — a bot whose model has been destroyed
-- underneath it keeps stepping a Simulation against a part with no
-- parent, which is a stream of errors rather than a visible bug.
--
-- Returns whether anything was actually driving it, so the caller can
-- tell a bot's kart from a player's.
function BotService.detach(kart: Model): boolean
	for i = #bots, 1, -1 do
		local bot = bots[i]
		if bot.kart == kart then
			bot.boxes:Destroy()
			bot.drops:Destroy()
			bot.hazards:Destroy()
			clearDebug(bot)
			if bot.rig then
				bot.rig:Destroy()
			end
			table.remove(bots, i)
			return true
		end
	end
	return false
end

-- EVERY REMAINING KART GOES TO THE AI at the flag.
--
-- This is what makes the ending a shot rather than a screen. Once the
-- race is decided nobody needs to be driving, and a player left holding
-- a kart while the board covers their view is driving blind — so their
-- kart carries on without them and they get to watch it.
--
-- Reuses takeOver outright: same anchoring, same ownership handover,
-- same inherited speed. A second path for "the round ended" would drift
-- from the one for "you finished" the first time either changed.
function BotService.takeOverAll()
	for _, kart in Standings.allKarts() do
		if not kart:GetAttribute(Names.AI_DRIVEN) then
			local who = kart:GetAttribute(Names.RACER_NAME) or "Racer"
			BotService.takeOver(kart, who .. " (AI)")
		end
	end
end

-- EVERY TAKEOVER GOES BACK, unconditionally.
--
-- This used to require the kart to still exist AND still be AI_DRIVEN.
-- Anything failing either test stayed in `bots` forever — stepped every
-- frame, counted by the flying watchdog, and accumulating one more
-- stranded entry per round.
--
-- That is the whole of what was going wrong at the end of a race:
--
--   * four "Racer (AI) recovered by the flying watchdog" during
--     Intermission, one per stranded takeover
--   * a kart welded to its player that would not move — AI_DRIVEN never
--     cleared, so it stayed anchored and server-owned
--   * a frozen camera — the client's step() returns early on AI_DRIVEN,
--     and everything after that line, the camera included, stops running
--
-- The identity is `takenOver`, which is intrinsic to the entry. AI_DRIVEN
-- is an attribute on a kart that anything can clear, and keying the
-- release on it meant one stray write stranded a player for the rest of
-- the server's life.
function BotService.releaseTakeOvers()
	for i = #bots, 1, -1 do
		local bot = bots[i]
		if bot.takenOver then
			-- Released if there is anything left to release. Dropped from
			-- the list either way — a takeover whose kart has gone has
			-- nothing to drive and no business being stepped.
			if bot.kart and bot.kart.Parent then
				bot.kart:SetAttribute(Names.AI_DRIVEN, nil)
			-- HANDED BACK EXPLICITLY.
			--
			-- The first version left it anchored and unowned, on the
			-- assumption that KartService's Occupant signal would pick it
			-- up when the round restarted. It never would: that signal
			-- fires when the occupant CHANGES, and the finished player sat
			-- in the kart the entire time. The kart would have stayed
			-- anchored and server-owned forever, with its driver unable to
			-- move — for the rest of the server's life.
				KartService.restoreOwnership(bot.kart)
			end
			bot.boxes:Destroy()
			bot.drops:Destroy()
			bot.hazards:Destroy()
			clearDebug(bot)
			table.remove(bots, i)
		end
	end
end

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
	-- A parked bot needs no racing line, and checking a rig on an
	-- unfinished track is exactly what idle mode is for.
	if #Route.path() == 0 and not B.Idle then
		-- Same rule as the trim below: a taken-over kart belongs to a
		-- player and is not this function's to delete, whatever the
		-- track looks like.
		for j = #bots, 1, -1 do
			local bot = bots[j]
			if not bot.takenOver then
				table.remove(bots, j)
				bot.boxes:Destroy()
				bot.drops:Destroy()
				KartService.dropRacer(bot.racer)
			end
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

	--=================================================================
	--  A TAKEN-OVER KART IS NOT THIS FUNCTION'S TO DESTROY.
	--
	--  When a player's kart goes to the AI it joins `bots`, and this
	--  trim removed entries from the end and destroyed their karts. So a
	--  player's kart, sitting in that list, was deleted the moment the
	--  field needed to be smaller — which is the kart that goes missing
	--  after the first race.
	--
	--  releaseTakeOvers is supposed to have removed them by now, and
	--  usually has. "Usually" is not good enough when the failure is a
	--  player permanently without a kart, and this function has no
	--  business deciding the fate of one either way.
	--
	--  So the count and the trim both look at REAL bots only.
	--=================================================================
	local owned = 0
	for _, bot in bots do
		if not bot.takenOver then
			owned += 1
		end
	end

	local i = #bots
	while owned > want and i >= 1 do
		local bot = bots[i]
		if bot.takenOver then
			i -= 1
			continue
		end
		table.remove(bots, i)
		i -= 1
		owned -= 1
		bot.boxes:Destroy()
		bot.drops:Destroy()
		bot.hazards:Destroy()
		clearDebug(bot)
		if bot.rig then
			bot.rig:Destroy()
		end
		-- Through KartService, which owns the registry. Destroying the
		-- kart here and leaving the entry behind is what put a ghost in
		-- every racer count.
		KartService.dropRacer(bot.racer)
	end

	while owned < want do
		local name = B.Names[(owned % #B.Names) + 1] .. tostring(owned + 1)
		local avatarUserId = botAvatarUserIdForSlot(owned)
		local racer, kart = KartService.addBot(name)
		local hitbox = kart.PrimaryPart
		local seat = kart:FindFirstChild("Seat")
		if not (hitbox and seat) then
			warn("[BotService] built a kart with no hitbox or seat for " .. name)
			break
		end

		local bot = makeBot(name, racer, kart, hitbox, seat, avatarUserId)
		table.insert(bots, bot)
		owned += 1
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
-- Where the rig comes from, in order of preference.
--
-- Roblox will build a correct default R15 for us, which is the reason
-- this no longer needs anything in ServerStorage. That mattered: a rig
-- you have to author is a rig that doesn't exist yet, and every failure
-- to produce one looked like a bug in the seating rather than a missing
-- asset.
--
-- Avatar identities win when assigned. An authored model remains the fallback,
-- so tracks without a roster can still use a local BotRig.
local function buildRig(userId: number?): Model?
	local description = if userId then avatarDescriptionFor(userId) else nil
	if description then
		local ok, rig = pcall(function()
			return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
		end)
		if ok and rig and rig:FindFirstChildOfClass("Humanoid") then
			return rig
		end
		warn(("[BotService] could not build dressed bot rig for userId %d: %s"):format(userId, tostring(rig)))
	end

	-- RECURSIVE, for the same reason Assets.luau is: art gets filed. Once
	-- the shared art is a Package it lives one folder deeper than it did
	-- when this was written, and a top-level-only search finds nothing
	-- and falls through to the default rig without saying why.
	local template = ServerStorage:FindFirstChild(B.RigName, true)
	if template and template:IsA("Model") and template:FindFirstChildOfClass("Humanoid") then
		return template:Clone()
	end

	-- YIELDS, and can fail if Roblox is having a bad day. A bot without a
	-- driver is a cosmetic loss, so it must never take the race with it.
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if ok and rig and rig:FindFirstChildOfClass("Humanoid") then
		return rig
	end

	if not warnedNoRig then
		warnedNoRig = true
		warn("[BotService] could not build a driver rig: " .. tostring(rig))
	end
	return nil
end

function BotService.seatRig(bot)
	if bot.rig then
		bot.rig:Destroy()
		bot.rig = nil
	end
	if B.RigName == "" then
		return
	end

	-- Built off the main path because CreateHumanoidModelFromDescription
	-- yields, and filling a grid shouldn't wait on six network calls.
	task.spawn(function()
		if bot.avatarUserId then
			local resolvedName = avatarNameFor(bot.avatarUserId)
			if resolvedName then
				bot.name = resolvedName
				if bot.racer then
					bot.racer.Name = resolvedName
				end
				publishBotIdentity(bot)
			end
		end

		local rig = buildRig(bot.avatarUserId)
		if not rig then
			return
		end

		-- The bot may have been removed, or had its kart rebuilt, while we
		-- were waiting on that.
		local seat = bot.kart and bot.kart.Parent and bot.kart:FindFirstChild("Seat")
		if not seat then
			rig:Destroy()
			return
		end

		rig.Name = bot.name
		local humanoid = rig:FindFirstChildOfClass("Humanoid")
		-- It never walks anywhere, and a rig that can stand up climbs out
		-- of the kart the first time anything jostles it.
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		-- No death, no ragdoll, no falling apart mid-race.
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false

		for _, d in rig:GetDescendants() do
			if d:IsA("BasePart") then
				-- ANCHORED RIGS CANNOT SIT. An authored one posed in
				-- ServerStorage is almost always anchored, and Sit fails
				-- silently on it — no error, no occupant, no hands.
				d.Anchored = false
				-- Same group as the kart, so drivers never knock each other
				-- about as two karts pass.
				d.CollisionGroup = Config.Rig.CollisionGroup
				d.CanQuery = false
				-- Non-solid: a seated rig is welded to the kart, so a limb
				-- catching on scenery drags the whole kart to a stop.
				d.CanCollide = false
			end
		end

		-- PARENTED UNDER THE KART, not into workspace.
		--
		-- WorldFilter excludes two things from every kart's movement
		-- queries: models tagged Kart, and the characters of actual
		-- Players. A bot's rig was neither — it sat loose in workspace, so
		-- the only thing keeping it out of everyone's collision sweeps was
		-- the CanQuery pass below.
		--
		-- That pass runs once, over the descendants that exist at that
		-- moment. Anything appearing afterwards — an accessory still
		-- loading, a part Sit creates — never gets it, and a single
		-- queryable limb is a solid obstacle to every kart on the track.
		-- "I collide with the bots" is exactly what that looks like.
		--
		-- Under the kart it inherits the kart's own exclusion, for every
		-- part it will ever have, without anything having to remember.
		rig.Parent = bot.kart
		-- Placed ON the seat before sitting. Sat immediately rather than
		-- deferred: a deferred Sit gives an unanchored rig a frame to fall,
		-- and Sit on something already falling can miss.
		rig:PivotTo(seat.CFrame + seat.CFrame.UpVector * 2)
		seat:Sit(humanoid)
		bot.rig = rig

		-- THE HUMANOID PUTS CanCollide BACK on the torso parts, and the
		-- sweep above cannot stop it — the state machine owns collision
		-- there and re-asserts it as it changes state.
		--
		-- PHYSICS STATE WAS THE WRONG ANSWER TO THAT. It does hand the
		-- parts back, and it also stops the humanoid being SEATED: the
		-- rig came away from the kart and drifted alongside it, which is
		-- the AI looking detached from its own kart. A collision flag is
		-- not worth breaking the thing that holds a driver in.
		--
		-- Re-asserting the flag instead. The rig is welded and still, so
		-- the sweep below costs a handful of property writes on a slow
		-- timer, and the humanoid keeps its state machine and its seat.

		-- ANYTHING THAT ARRIVES LATER GETS THE SAME TREATMENT.
		--
		-- The sweep above ran over the descendants that existed at that
		-- moment. Accessories are still loading, and Sit creates parts of
		-- its own — every one of them arrives collidable and queryable,
		-- and a single queryable limb is a solid obstacle to every kart
		-- on the track. The comment above already knew this about
		-- CanQuery; it was never true for CanCollide either.
		rig.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
				d.CollisionGroup = Config.Rig.CollisionGroup
			end
		end)

		-- KEPT OFF, on a slow timer. The humanoid puts it back whenever
		-- it changes state and there is no event for that, so the only
		-- honest options are a poll or breaking the state machine — and
		-- breaking it takes the rig out of its seat.
		--
		-- Cheap: a dozen parts, a few times a second at most, on a rig
		-- that never moves relative to its kart. It stops when the rig
		-- does.
		task.spawn(function()
			while rig.Parent and bot.rig == rig do
				for _, d in rig:GetDescendants() do
					if d:IsA("BasePart") and d.CanCollide then
						d.CanCollide = false
						d.CanQuery = false
					end
				end
				task.wait(B.RigCollideCheck)
			end
		end)

		-- Verified, because every way this fails is silent — an anchored
		-- part, a missing HumanoidRootPart, a humanoid that can't enter the
		-- Seated state all produce an empty kart and no error at all.
		task.delay(0.6, function()
			if rig.Parent and seat.Parent and seat.Occupant ~= humanoid then
				warn(("[BotService] %s would not stay seated in its kart."):format(bot.name))
			else
				log("%s is seated", bot.name)
			end
		end)
	end)
end

--=====================================================================
--  LEARNING FROM IT
--
--  Not machine learning, and deliberately not. A number per checkpoint
--  that goes up when the bot leaves the track there and decays when it
--  doesn't. High caution means: drive this bit nearer the middle and
--  slower.
--
--  That is the entire mechanism, and it is enough, because the failure
--  it has to stop repeating is completely local. A bot doesn't go off
--  "in general" — it goes off at turn four, the same way, every lap. One
--  number attached to turn four fixes turn four and leaves the rest of
--  the track alone.
--
--  It also converges in the right direction by construction: caution can
--  only rise on evidence, and only decays on a clean lap past the same
--  spot. Worst case a bot ends up crawling round one corner, which is
--  slow but never broken.
--
--  PER BOT, not per track. It's a driver learning a circuit, so a fresh
--  bot starts naive — and if this is ever persisted (see SPEC-bots
--  Layer 8) it should be keyed by track, because three laps is nowhere
--  near enough to converge on anything.
--=====================================================================
-- On the module rather than a local, because step() calls it and step is
-- defined above this point. A `local function` here would be nil there.
--=====================================================================
--  A RESPAWN LOOP IS NOT A DIFFICULT CORNER.
--
--  Sometimes a bot comes back, fails immediately, comes back again, and
--  keeps going. Every cycle reports the same node, so within a minute
--  one stretch has fifty incidents against it and the brain concludes
--  the corner is lethal — when what is actually broken is the place it
--  is being PUT BACK, which may be inside geometry, under the road, or
--  facing a wall.
--
--  That is the data being corrupted by the recovery rather than by the
--  track, and it is worth catching for that reason alone: a poisoned
--  node vetoes drifting and tames the line for every bot, permanently,
--  from evidence that describes a bug.
--
--  Two responses, in order:
--    STOP RECORDING   the loop teaches nothing true
--    MOVE THE TARGET  put it back somewhere else entirely
--=====================================================================
local function loopingAt(bot, node: number): boolean
	local now = os.clock()
	-- A different node means whatever happened is not a loop; reset.
	if bot.loopNode ~= node or now - (bot.loopAt or 0) > B.ReviveLoopWindow then
		bot.loopNode, bot.loopAt, bot.loopCount = node, now, 1
		return false
	end
	bot.loopAt = now
	bot.loopCount = (bot.loopCount or 0) + 1
	return bot.loopCount > B.ReviveLoopCount
end

function BotService.noteWentOff(bot)
	local nodes = #Route.path()
	if nodes == 0 then
		return
	end
	-- The node it was last SAFE at, not the one nearest the wreck. Where
	-- it left is the useful fact; where it landed is noise.
	local key = math.floor(bot.safeU or bot.u or 0) % nodes

	-- Recovery remains necessary; blaming the last safe corner for a
	-- confirmed item/hazard displacement does not.
	if learningInterrupted(bot) then
		return
	end

	-- LOOPING? Then this is not evidence. Nudge the recovery point down
	-- the road instead — the usual cause is the spot it is being put
	-- back at, not the corner it is being blamed on.
	if loopingAt(bot, key) then
		bot.safeU = (bot.safeU or bot.u or 0) + B.ReviveLoopSkip
		if bot.loopCount % 5 == 1 then
			warn(
				("[BotService] %s is stuck in a respawn loop at node %d (%d times). Not recording it — a loop teaches nothing true — and moving the recovery point forward. Check that node for geometry the kart can spawn inside."):format(
					bot.name,
					key,
					bot.loopCount
				)
			)
		end
		return
	end

	bot.caution[key] = math.min((bot.caution[key] or 0) + 1, B.CautionMax)
	-- And into the shared brain, so the next session starts knowing.
	BotBrain.wentOff(key)

	-- The approach matters as much as the corner — a bot that goes off at
	-- four was usually already too fast at three.
	local before = (key - 1) % nodes
	bot.caution[before] = math.min((bot.caution[before] or 0) + 0.5, B.CautionMax)
end

-- Called once per completed lap. Caution earned on a lap that then went
-- cleanly is caution that has done its job, so it fades — otherwise a bot
-- that goes off once drives that corner timidly for the rest of the
-- server's life.
function BotService.decayCaution(bot)
	for key, value in bot.caution do
		local next = value - B.CautionDecay
		bot.caution[key] = if next > 0 then next else nil
	end
end

function BotService.revive(bot)
	-- Same rule a player gets: if somebody put this bot in the void, they
	-- get the credit for it. Checked here because this is the one place a
	-- bot comes back from a fall, so there is no second path to keep in
	-- step — and it changes nothing about the revive itself. The bot
	-- carries on from its last safe point exactly as before.
	if bot.kart.Parent then
		RaceService.creditVoidKill(bot.kart, bot.name)
	end

	-- A TAKEN-OVER KART IS NOT A BOT'S TO REPLACE.
	--
	-- When a player's kart is handed to the AI, this entry drives a kart
	-- that belongs to somebody else. If that kart then leaves the world —
	-- retired at the flag, or rebuilt by the kart watchdog — the code
	-- below used to spawn a REPLACEMENT through addBot, which produces a
	-- brand new kart named after the takeover: "Racer (AI)", airborne,
	-- speed zero, five studs off the racing line.
	--
	-- That is where the extra kart came from, and it is why the player's
	-- own kart appeared to vanish: theirs was rebuilt while an orphan
	-- carried on in its place.
	--
	-- Nothing to revive. The player is getting their kart back through
	-- KartService, which is the only thing that should be building one.
	if not bot.kart.Parent and bot.takenOver then
		for i = #bots, 1, -1 do
			if bots[i] == bot then
				table.remove(bots, i)
				break
			end
		end
		log("%s dropped — its kart was a player's and has gone", bot.name)
		return
	end

	if not bot.kart.Parent then
		local _, kart = KartService.addBot(bot.name)
		bot.kart = kart
		publishBotIdentity(bot)
		local hitbox = kart.PrimaryPart
		local seat = kart:FindFirstChild("Seat")
		if not (hitbox and seat) then
			return
		end
		bot.sim = Simulation.new(kart, hitbox, seat)
		BotService.seatRig(bot)
	end

	-- Back to where it last was on the road — but on the CENTRELINE there,
	-- not on the exact spot it occupied.
	--
	-- Two separate mistakes, fixed together:
	--
	-- Projecting the crash site onto the line put bots at the checkpoint
	-- AFTER the one they left. Fall off the outside of a right-hander and
	-- the nearest point on the line is the straight you were aiming at.
	--
	-- Then respawning at the exact recorded spot replaced that with a
	-- loop, and this one was mine. The last place a bot was legally on the
	-- road is, by definition, the last inch before it left — so putting it
	-- back there points it at the same edge, at the same angle, and it
	-- drives off again. Forever. It looked like flying to the checkpoint;
	-- it was a bot being helpfully returned to the scene of the accident.
	--
	-- So keep the progress (u is right, and it earned it) and discard the
	-- position. Back to the middle of the road, facing along it.
	if bot.safeU then
		local at = Route.pointAt(bot.safeU, bot.branch, Route.path())
		local tangent = Route.tangentAt(bot.safeU, bot.branch, Route.path())
		if at and tangent then
			bot.sim:RespawnAt(CFrame.lookAt(at + Vector3.yAxis * 4, at + tangent + Vector3.yAxis * 4))
			bot.u = bot.safeU
			bot.lastU = nil
			return
		end
	end

	-- Never got a clean lap position — spun off the grid, say. Only now is
	-- projecting the wreck onto the line the best we can do.
	local u = Route.nearestU(bot.sim.pos, Route.path())
	local at = Route.pointAt(u, bot.branch, Route.path())
	local tangent = Route.tangentAt(u, bot.branch, Route.path())
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
-- A MISSILE HAS COME INSIDE HOPPING RANGE of this bot. Called by
-- ProjectileService, which is the only thing that knows where missiles
-- are — a bot polling for them would be every bot asking every frame
-- about something that is almost never true.
--
-- The roll happens HERE and once. `decided` stops a missile that lingers
-- in range from being rolled again every frame, which is the difference
-- between a chance and a certainty.
function BotService.missileNear(kart: Model)
	for _, bot in bots do
		if bot.kart == kart then
			if bot.dodgeDecided then
				return
			end
			bot.dodgeDecided = true

			-- SHIELD FIRST, IF THEY HAVE ONE AND THINK OF IT. A shield
			-- is certain and a hop is a timing test, so a bot that
			-- manages both should prefer the shield — but only if it
			-- notices in time, which is what the reaction delay decides.
			if bot.item and bot.item.Id == "Shield" then
				local sk = skillFrac(bot)
				local notice = B.ShieldChanceMin + (B.ShieldChanceMax - B.ShieldChanceMin) * sk
				if rng:NextNumber() < notice then
					-- BROUGHT FORWARD, not fired. The existing use path
					-- still runs it, so a shield goes up through exactly
					-- the same door a player's does.
					--
					-- Better drivers react faster. A missile that lands
					-- inside this window beats the shield, and the bot is
					-- left holding one it was half a second too slow to
					-- use — which is the most human thing in this file
					-- and took no simulating at all.
					local react = B.ShieldReactMax - (B.ShieldReactMax - B.ShieldReactMin) * sk
					bot.itemAt = math.min(bot.itemAt or math.huge, os.clock() + react)
					-- Committed to the shield; no need to also throw the
					-- kart in the air.
					bot.dodging = false
					return
				end
			end

			local chance = B.DodgeChanceMin + (B.DodgeChanceMax - B.DodgeChanceMin) * skillFrac(bot)
			bot.dodging = rng:NextNumber() < chance
			return
		end
	end
end

-- Cleared when the threat is gone, so the next missile gets its own
-- roll rather than inheriting this one's answer.
function BotService.missileGone(kart: Model)
	for _, bot in bots do
		if bot.kart == kart then
			bot.dodgeDecided = false
			bot.dodging = false
			return
		end
	end
end

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
			if landed then
				markExternalInterference(bot, math.max(effect.spin or 0, effect.stun or 0, effect.reverse or 0), tostring(effect.item))
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
	-- Loaded once, before any bot drives. A track with no saved brain is
	-- one the bots have not met yet, which is the same thing an empty
	-- table means — so a DataStore that is down costs nothing but memory
	-- of previous sessions.
	BotBrain.start()
	-- Validate a loaded brain before any bot consults it. The old
	-- round-end-only call let a changed route influence the first race.
	BotBrain.reshape(#Route.path())

	-- Saved between rounds by MatchService, which is the only place that
	-- knows when the field is idle.
	MatchService.onRoundLearned = function()
		-- CHECKED BEFORE SAVING, and every round. Route.preflight has
		-- just rebuilt the path, so this is the first moment the true
		-- node count is known — and the last moment before more lessons
		-- are written against indices that may no longer mean the same
		-- corners.
		BotBrain.reshape(#Route.path())
		BotBrain.save()

	end
	-- The same tagged parts the player's Respawn watches. One instance,
	-- no cooldown of its own — see the declaration.
	voidZones = TagZones.new(Config.Respawn.VoidTag, { cooldown = 0, forceQueryable = true })

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
		-- Runs on the same tick as the bots and at the same rate. It is
		-- one windowed route lookup per human kart, which is a fraction
		-- of what a single bot costs.
		watchPlayers()
		accum = 0

		-- THE LEARNING BAR, PRINTED. So a server can be started and left
		-- alone: the console command answers when asked, this one speaks
		-- up on its own. Guarded on the clock rather than the tick, and
		-- it only prints when the percentage has actually moved.
		if os.clock() >= (nextReport or 0) then
			nextReport = os.clock() + B.LearnReportEvery
			BotBrain.report(#Route.path())
		end
	end)
end

return BotService
