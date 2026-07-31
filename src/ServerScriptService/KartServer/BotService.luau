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
local H = Config.Handling
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
-- Show or hide a kart's shield bubble.
--
-- Server-side twin of what Effects does for the local player. Effects
-- fades; this snaps, because a bot's shield going up is something you
-- see from across the track rather than something you're looking at.
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

	local narrowest, narrowestAt = math.huge, 0
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

		-- GREEN EDGES: how wide this thinks the road is, and therefore the
		-- box a bot's line is clamped inside.
		--
		-- Worth drawing because the measurement comes from your checkpoint
		-- volumes, so a gate narrower than the tarmac shows up here as
		-- green markers sitting well inside the kerb — and a gate WIDER
		-- than the tarmac shows up as green out in the scenery, which is
		-- the setup mistake that puts bots off the track.
		local tangent = Route.tangentAt(i - 1)
		if tangent then
			local across = tangent:Cross(Vector3.yAxis)
			if across.Magnitude > 1e-4 then
				across = across.Unit
				-- Each side its own distance. A checkpoint is rarely centred
				-- on its road, and one averaged number is too tight where
				-- there's room and too generous over the drop.
				local l = math.max(node.leftWidth - B.EdgeMargin, 0)
				local r = math.max(node.rightWidth - B.EdgeMargin, 0)
				marker(node.position - across * l + Vector3.yAxis * 1.5, 1.6, Color3.fromRGB(120, 230, 140), false)
				marker(node.position + across * r + Vector3.yAxis * 1.5, 1.6, Color3.fromRGB(120, 230, 140), false)
			end
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
	-- Damped on a straight, and this was a real part of the swerve: an
	-- unconditional sine wave on the lateral target is an instruction to
	-- weave, and no controller improvement can refuse it. A driver holds
	-- a straight and gets untidy through corners, so the wander follows
	-- the bend rather than the clock.
	local straightness = 1 - math.min(bend / math.max(B.WanderFullBend, 1e-3), 1)
	local wanderRoom = B.LineOffset * (1 - bot.skill) * (B.WanderOnStraight + (1 - B.WanderOnStraight) * (1 - straightness))
	local wander = math.sin(bot.lineAt) * wanderRoom
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
	-- Asymmetric, because a checkpoint is rarely centred on its road and
	-- one averaged number is too generous on exactly the side with the
	-- drop. Both sides are probed with rays, not read off the gate.
	local roomL, roomR = Route.roomAt(bot.u)
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
	local caution = bot.caution[math.floor(bot.u) % math.max(#Route.nodes(), 1)] or 0
	if caution > 0 then
		local pull = math.clamp(caution * B.CautionPull, 0, 1)
		roomL *= 1 - pull
		roomR *= 1 - pull
	end

	-- The narrower side, used only to judge whether the bot is still
	-- meaningfully ON the road when recording a safe position.
	local room = math.min(roomL, roomR)
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
	-- WHAT SEPARATES A RAMP FROM A CLIFF: whether the gap is ON THE
	-- RACING LINE.
	--
	-- The first version asked whether the route had ground somewhere
	-- further along, which is very nearly always true — the route runs
	-- down the middle of the road, so of course there's tarmac under it
	-- up ahead. Practically every gap therefore classified as a jump and
	-- the bot floored it, which is why they flew off ledges.
	--
	-- The question is not "is there road ahead somewhere". It's "does the
	-- LINE ITSELF go over nothing here". The line is where the designer
	-- says to drive, so a hole underneath it is a hole they put there on
	-- purpose. A hole under our own aim point while the line beside it is
	-- perfectly solid means only that we have wandered off the road, and
	-- flooring it is the worst available response.
	local ledge, jump = false, false
	local nose = sim.pos + sim.forward * (B.LedgeLook + speed * B.LedgeLookPerSpeed)
	if not (Route.hasGround(aim, sim.up) and Route.hasGround(nose, sim.up)) then
		local centre = Route.pointAt(aheadU)
		local lineOverAir = centre ~= nil and not Route.hasGround(centre, sim.up)

		if lineOverAir then
			-- The route is airborne here. Only commit if there's somewhere
			-- to land, or a bot happily accelerates into a chasm the
			-- designer built as a hazard rather than as a jump.
			local beyond = Route.pointAt(aheadU + B.JumpSpan)
			jump = beyond ~= nil and Route.hasGround(beyond, sim.up)
			ledge = not jump
		else
			-- Solid road on the line, nothing under us. We're the problem.
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
		local centre = Route.pointAt(aheadU)
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
	local kappaPath = Route.curvatureAt(aheadU, sim.up)

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
	if sim.grounded and math.abs(actualOffset) <= room then
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

	-- PACE. How hard this bot is willing to push, rolled from its skill.
	--
	-- This is a limit on the DRIVER, not the kart — the same kind of
	-- thing as lifting early for a corner. It does not touch grip, top
	-- speed or turn rate, so a bot still cannot do anything you couldn't,
	-- and catching one is still a matter of driving better rather than
	-- waiting for a handicap to apply.
	--
	-- It exists because "beatable by being imperfect" only works if the
	-- imperfections are big enough to see. A bot on the correct line at
	-- permanent full throttle is uncatchable however many small mistakes
	-- it makes, because none of them cost it anything on a straight.
	c.touchThrottle *= bot.pace

	-- A JUMP THE ROUTE CROSSES. Speed is what clears it, so every reason
	-- to lift is overruled — including the corner-braking above, which
	-- reads a ramp's approach as a bend and would take the pace off at
	-- exactly the wrong moment.
	-- A jump means DON'T LIFT. It does not mean floor it.
	--
	-- This used to raise the throttle to JumpThrottle, which overrode
	-- corner braking, pace and everything else — so bots hit ramps harder
	-- than they would have driven them, and launched. That was never the
	-- job. The problem being solved was a bot BRAKING for a ramp, and all
	-- that needs is for the ledge cap below not to apply.
	--
	-- So a jump now simply falls through: the bot arrives at whatever
	-- speed its normal driving produced, exactly as a player would.
	if bot.jumping then
		-- Nothing. Deliberately.
	elseif (bot.ledgeFor or 0) > 0 then
		-- Off the edge of the world beats every other consideration.
		-- Allowed below MinCornerSpeed, which nothing else is: that floor
		-- exists so bots don't crawl round corners, and it must not stop
		-- one slowing for a drop.
		c.touchThrottle = math.min(c.touchThrottle, B.LedgeThrottle)
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
		local b = bendAt(at, B.CornerLookahead, sim.up)
		if b > aheadBend then
			aheadBend, aheadAt = b, at
		end
	end

	if not bot.driftPlan and aheadBend >= B.DriftBend and speed >= B.DriftMinSpeed then
		-- Rolled once per corner. A bot that takes every drift perfectly
		-- is one you can never out-drive; missing some is what leaves the
		-- door open.
		if rng:NextNumber() < B.DriftChance * bot.skill then
			bot.driftPlan = {
				-- Entered BEFORE the apex, and how early is skill: a good
				-- driver commits sooner and carries more through.
				entry = aheadAt - B.DriftEntry * bot.skill,
				exit = aheadAt + B.DriftHold,
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
	-- DON'T START A DRIFT AT THE EDGE OF ANYTHING.
	--
	-- Entering a drift means pressing drift, and in this game pressing
	-- drift is a HOP — it sets vertVel and leaves the ground on purpose.
	-- That's the mechanic, and it's fine in the middle of a corner. Do it
	-- on a ramp lip or at the edge of a drop and the bot launches itself,
	-- which is most of what "the bot still jumps" looks like.
	--
	-- Only initiation is blocked. A drift already in progress is left
	-- alone: yanking a bot out of one mid-corner would spit it straight
	-- off the outside of the bend, which is the thing being avoided.
	local edgy = (bot.ledgeFor or 0) > 0 or bot.jumping or not sim.grounded
	if edgy and not c.driftHeld then
		drifting = false
	end

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
				bot.u = Route.nearestU(grid.Position)
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
				bot.item = nil
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
		-- IS THE HOLD ACTUALLY HOLDING?
		--
		-- Bots moving during the countdown has now survived two fixes,
		-- both of which I reasoned my way to rather than measured. So
		-- this stops reasoning and reports numbers: how far the kart
		-- moved ACROSS the ground while held, plus every value that
		-- could have caused it.
		--
		-- Sideways only. Gravity settling a kart onto the grid is
		-- expected and would otherwise trip this every single round.
		--
		-- Reports facts and draws no conclusion, deliberately. The last
		-- diagnostic in this file asserted "falling through the world,
		-- not driving off it", was wrong, and cost a session.
		--------------------------------------------------------------
		if not racing then
			if bot.heldAt then
				local d = bot.sim.pos - bot.heldAt
				d -= bot.sim.up * d:Dot(bot.sim.up)
				bot.heldSlide = (bot.heldSlide or 0) + d.Magnitude
			end
			bot.heldAt = bot.sim.pos

			if (bot.heldSlide or 0) > B.HeldSlideWarn and now - (bot.heldWarnAt or 0) > 3 then
				bot.heldWarnAt = now
				warn(
					("[BotService] %s slid %.1f studs sideways while HELD in phase %s — speed %.2f, throttle %.2f, steer %.2f, grounded %s, boosting %s, burning %s"):format(
						bot.name,
						bot.heldSlide,
						tostring(MatchService.phase()),
						bot.sim.speed,
						bot.controls.touchThrottle,
						bot.controls.touchSteer,
						tostring(bot.sim.grounded),
						tostring(bot.sim.boosting),
						tostring(bot.sim.burning)
					)
				)
				bot.heldSlide = 0
			end
		else
			bot.heldAt, bot.heldSlide = nil, 0
		end

		-- Let go of everything while held. drive() is the only thing that
		-- writes these and it doesn't run outside Racing, so otherwise a
		-- bot sits on the grid still holding last lap's full throttle.
		-- Simulation zeroes the input itself when frozen, so this changes
		-- no behaviour today — it removes a loaded gun. Every "held kart
		-- moved anyway" bug so far has been something downstream deciding
		-- the hold didn't apply to it.
		if not racing then
			bot.controls.touchThrottle = 0
			bot.controls.touchSteer = 0
			bot.controls.driftHeld = false
		end


		-- Fell off the world, or ended up somewhere the road isn't. No
		-- character to re-seat, so it puts itself back on the racing line
		-- — which it already knows how to find.
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
				if bot.item and now >= bot.itemAt then
					useItem(bot)
				end
				-- Laps, from the route wrapping rather than from trigger
				-- volumes: a bot is already tracked by `u`, so watching it
				-- wrap is free and can't miss a gate at speed.
				if bot.lastU and bot.u < bot.lastU - #Route.nodes() * 0.5 then
					bot.laps += 1
					-- A lap survived is evidence the caution worked, so let
					-- it fade. Without this a single incident makes a bot
					-- crawl that corner for the rest of the server's life.
					BotService.decayCaution(bot)

					-- CROSSING THE LINE. Bots could not do this at all
					-- until now: finishing was reachable only through the
					-- client remote, and a bot has no client. However fast
					-- one drove it never took a place and never ended the
					-- round — they weren't losing races, they were not
					-- entered in them.
					--
					-- Reported once. FINISH_PLACE is the guard, and
					-- MatchService checks it too, so a bot that keeps
					-- driving after the flag can't claim a second place.
					if bot.laps >= Config.Race.TotalLaps and not bot.kart:GetAttribute(Match.FINISH_PLACE) then
						local since = MatchService.racingSince()
						if since then
							MatchService.botFinished(bot.kart, bot.name, workspace:GetServerTimeNow() - since)
						end
					end
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
				if bot.sim.grounded then "" else "AIRBORNE — no ground under it"
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

		-- The shield bubble, which nothing else would ever show.
		--
		-- Effects drives it for a player, and Effects is a client module
		-- that only ever looks at the local kart. A bot has no client, so
		-- its bubble is whatever KartFactory left it as — now hidden,
		-- which made bots permanently unshielded-looking instead of
		-- permanently shielded-looking. Neither is the truth.
		--
		-- Toggled on change rather than written every step: this walks the
		-- model, and doing that 75 times a second per bot to set a value
		-- that is already correct is waste.
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
	if #Route.nodes() == 0 and not B.Idle then
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

		-- Rolled before the table so pace can be derived from it.
		local skill = rng:NextNumber(B.SkillMin, B.SkillMax)

		local bot = {
			name = name,
			racer = racer,
			kart = kart,
			sim = Simulation.new(kart, hitbox, seat),
			controls = bindControls(newControls()),
			-- One roll, and it scales everything. A low-skill bot is a
			-- worse driver, not a slower one.
			skill = skill,
			-- How hard it's willing to push, from its skill. A limit on
			-- the driver's right foot, not on the kart — see the note in
			-- drive(). The best bot on the grid is close to flat out; the
			-- worst is visibly not trying as hard.
			pace = B.PaceMin + (B.PaceMax - B.PaceMin) * skill,
			-- A fixed bias plus wander, so two bots don't drive the same
			-- line and sit inside each other down a straight.
			lineBias = rng:NextNumber(-1, 1) * B.LineOffset,
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
			driftPlan = nil,
			item = nil,
			itemAt = 0,
			lastU = nil,
			-- Where it last had wheels on measured road, and the checkpoint
			-- that goes with it. revive() keeps the second and deliberately
			-- throws away the first — see the comment there.
			safeU = nil,
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
-- Where the rig comes from, in order of preference.
--
-- Roblox will build a correct default R15 for us, which is the reason
-- this no longer needs anything in ServerStorage. That mattered: a rig
-- you have to author is a rig that doesn't exist yet, and every failure
-- to produce one looked like a bug in the seating rather than a missing
-- asset.
--
-- An authored model still wins if there is one — that's how you dress
-- the drivers later.
local function buildRig(): Model?
	local template = ServerStorage:FindFirstChild(B.RigName)
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
		local rig = buildRig()
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

		rig.Parent = workspace
		-- Placed ON the seat before sitting. Sat immediately rather than
		-- deferred: a deferred Sit gives an unanchored rig a frame to fall,
		-- and Sit on something already falling can miss.
		rig:PivotTo(seat.CFrame + seat.CFrame.UpVector * 2)
		seat:Sit(humanoid)
		bot.rig = rig

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
function BotService.noteWentOff(bot)
	local nodes = #Route.nodes()
	if nodes == 0 then
		return
	end
	-- The node it was last SAFE at, not the one nearest the wreck. Where
	-- it left is the useful fact; where it landed is noise.
	local key = math.floor(bot.safeU or bot.u or 0) % nodes
	bot.caution[key] = math.min((bot.caution[key] or 0) + 1, B.CautionMax)

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
		local at = Route.pointAt(bot.safeU)
		local tangent = Route.tangentAt(bot.safeU)
		if at and tangent then
			bot.sim:RespawnAt(CFrame.lookAt(at + Vector3.yAxis * 4, at + tangent + Vector3.yAxis * 4))
			bot.u = bot.safeU
			bot.lastU = nil
			return
		end
	end

	-- Never got a clean lap position — spun off the grid, say. Only now is
	-- projecting the wreck onto the line the best we can do.
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

	-- FIXED TIMESTEP, with sub-stepping.
	--
	-- The old loop could only ever fire ONCE per Heartbeat, so any
	-- StepRate above the server's 60Hz silently did nothing — 75 and 60
	-- ran identically, and the config was quietly lying. It also passed
	-- the accumulated time as dt and zeroed the accumulator, which is a
	-- variable timestep dressed up as a fixed one.
	--
	-- Now the integrator always advances by exactly `interval`, however
	-- many of those fit in the frame. Below 60 it skips frames as before;
	-- above 60 it genuinely sub-steps.
	local accum = 0
	local interval = 1 / math.max(B.StepRate, 1)

	RunService.Heartbeat:Connect(function(dt)
		-- Clamped BEFORE accumulating. A hitch — a big spawn, someone
		-- joining — must not bank a second of work that the next frame
		-- then tries to pay off all at once, which makes the next frame
		-- slow and banks more still. Dropping the excess costs a little
		-- simulated time; not dropping it costs the server.
		accum += math.min(dt, interval * B.MaxSubSteps)

		local n = 0
		while accum >= interval and n < B.MaxSubSteps do
			step(interval)
			accum -= interval
			n += 1
		end
	end)
end

return BotService
