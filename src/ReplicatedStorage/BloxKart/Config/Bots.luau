--[[
	Bots — AI racers, so a lobby is never empty.

	THEY DRIVE THE SAME KART YOU DO
	-------------------------------
	A bot runs the same Simulation, reading its controls off the same
	table your keyboard fills in. It has no special physics, no hidden
	speed, and no ability to corner harder than the kart allows.

	That's the important bit. The usual way to make bots competitive is to
	cheat their handling, and it always shows: they hold lines no player
	can hold, and losing to one feels arbitrary. Here a bot can only be
	quick by driving well, and every mistake it makes is a mistake you
	could have made.

	SO HOW ARE THEY BEATABLE?
	-------------------------
	By being deliberately imperfect, not by being slowed down:

	  - they lift for corners, and how early is a per-bot trait
	  - they take a slightly wrong line, and drift off it over time
	  - they react to items on a human-ish delay
	  - they miss drift opportunities they "should" take

	Skill is one number per bot, rolled at spawn. It scales all of the
	above together, so a low-skill bot isn't a fast bot with a handicap —
	it's a worse driver.
--]]

return {
	--== FIELD =========================================================
	-- Filled up to this many RACERS in total, humans included. Three
	-- means solo practice is a four-kart race.
	FillTo = 2, -- one human plus one bot
	MaxBots = 7, -- never more than the grid has slots for

	--== IDLE  (rig test) ==============================================
	-- Parks the bots and just wags the wheel, so you can look at the
	-- driver: rig seated, hands on the wheel, arms following the
	-- steering. Nothing drives, nothing races.
	--
	-- Also drops the checkpoint requirement — a parked bot needs no
	-- racing line, and the whole point is to check the rig on a track
	-- that isn't finished.
	Idle = true,
	IdleSteerRate = 1.1, -- wags per second
	IdleSteerAmount = 1, -- 1 is lock to lock

	-- Every frame, and it has to be.
	--
	-- Their karts are unanchored so motion replicates smoothly, which
	-- means physics runs on them at 60Hz. Writing their CFrame at 30
	-- meant physics extrapolated them along their velocity for a frame
	-- and then got snapped back by the next write — visible as a flicker.
	-- Matching the physics rate makes each correction tiny.
	--
	-- The controller is frame-rate independent, so lowering this doesn't
	-- change how bots DRIVE. It trades smoothness for server cost, and
	-- smoothness is the thing you notice.
	StepRate = 60,

	--== SKILL =========================================================
	-- Rolled per bot at spawn, and scales everything below. Kept away
	-- from 1 at the top: a perfect bot is a boring one.
	SkillMin = 0.45,
	SkillMax = 0.92,

	-- Drivers. NOTHING TO SET UP: without a model of this name in
	-- ServerStorage, Roblox builds a default R15 rig and that gets sat in
	-- the seat instead.
	--
	-- Requiring an authored rig was the wrong default — a rig you have to
	-- make is a rig that doesn't exist yet, and every failure to produce
	-- one looked like a bug in the seating rather than a missing asset.
	--
	-- Put a Model with a Humanoid here to dress them properly; "" for
	-- empty karts. Rider puts hands on the wheel either way, and doesn't
	-- care that the driver isn't a player.
	RigName = "BotRig",

	Names = {
		"Rusty",
		"Bolt",
		"Nitro",
		"Vex",
		"Dash",
		"Cinder",
		"Blitz",
	},

	--== DRIVING =======================================================
	-- How far up the racing line it aims. THE most important number
	-- here: too short and it saws at the wheel chasing a point it's
	-- almost on top of, too long and it cuts every corner.
	--
	-- Scaled by speed, because at 120 studs/s a fixed 20-stud lookahead
	-- is a sixth of a second of warning.
	LookaheadBase = 18,
	LookaheadPerSpeed = 0.28, -- extra studs per stud/s of speed

	-- How much a corner SHORTENS the lookahead, 0..1. Helps, but it is
	-- NOT the fix for corner cutting — see LineCorrect. Chasing a point
	-- up the road always cuts the apex, because the straight line to that
	-- point lies inside the bend; this only makes the cut smaller.
	LookaheadTighten = 0.7,

	SteerGain = 2.4, -- how hard it aims at the lookahead point. Higher is
	-- twitchier, not faster

	-- How hard it corrects being OFF the line, per stud of error.
	--
	-- The corner-cutting dial, and a different thing from SteerGain:
	-- that one chases a point up the road, which by itself always cuts
	-- the apex. This one has no opinion about what's ahead, it just
	-- refuses to be off the line. Raise it if bots still clip the inside.
	LineCorrect = 0.07,
	SteerSlew = 9, -- how fast its steering input can move. This is what
	-- stops a bot flicking to full lock instantly, which no human can do

	--== DRIVING LIKE A PERSON =========================================
	-- What makes a bot READ as a bot isn't its line, it's the input. A
	-- computed steering value is exact, instant and updated sixty times a
	-- second, and nothing alive drives like that.
	--
	-- None of this makes them slower. It makes the signal human-shaped:
	-- late, approximate, and corrected in bursts rather than continuously.

	-- Sees the world as it was this long ago. Human visual-motor lag is
	-- roughly 150-250ms and it's the single biggest tell — a bot with
	-- zero reaction time starts turning before a corner is visible.
	ReactionTime = 0.19,

	-- Won't bother correcting an error smaller than this. People don't
	-- micro-adjust every frame; they let a small error sit, notice it,
	-- then fix it. That cycle is most of what "driven" looks like.
	SteerDeadzone = 0.07,

	-- Slow wandering error on top. Not noise per frame — that reads as a
	-- broken servo — but a drifting bias that has to be corrected for.
	SteerNoise = 0.06,
	SteerNoiseRate = 1.6,

	-- Throttle isn't a smooth function of anything for a human. They
	-- lift, reapply, and hold it slightly wrong the whole time.
	ThrottleJitter = 0.05,
	ThrottleJitterRate = 0.9,

	-- Corners. The bot measures how much the road bends between here and
	-- its lookahead point, and lifts off proportionally.
	CornerLookahead = 2.2, -- nodes ahead to measure the bend over
	CornerBrake = 0.85, -- how much of a sharp bend translates to lifting
	MinCornerSpeed = 0.42, -- never lifts below this fraction of top speed

	--== LINE ==========================================================
	-- Bots don't drive the centreline exactly; each holds an offset and
	-- wanders it. This is most of what makes them look driven rather
	-- than railed, and it's why they're overtakeable.
	LineOffset = 9, -- studs either side, at worst skill
	LineDrift = 0.35, -- how fast the offset wanders

	-- Moving over for traffic. Karts pass through each other by design,
	-- but two on one line drive as a single overlapping lump, which reads
	-- as bumping even though nothing collides.
	AvoidRadius = 26, -- studs, and only counts karts AHEAD
	AvoidStrength = 11, -- studs of offset at closest range

	--== DRIFTING ======================================================
	-- Drifts when the corner is sharp enough and it's quick enough to
	-- benefit, same as a player would.
	DriftBend = 0.32, -- bend required before it considers a drift
	DriftMinSpeed = 55,
	DriftChance = 0.85, -- rolled per corner, scaled by skill. A bot that
	-- takes every drift perfectly is one you can't out-drive

	--== NITRO =========================================================
	-- Spent on straights, which is where a player would. Waiting for a
	-- full three tanks is optimal and inhuman; they mostly don't.
	NitroStraight = 0.18, -- bend below this counts as a straight
	NitroMinTanks = 1,
	NitroHoldChance = 0.4, -- chance it saves a tank for later anyway

	--== ITEMS =========================================================
	-- Reaction time before using what it picks up. The single biggest
	-- lever on how nasty they feel.
	ItemDelayMin = 0.6,
	ItemDelayMax = 2.4,
	-- Odds it throws forward rather than dropping behind, when the item
	-- can do both. A bot in the lead defending is more interesting than
	-- one that always lobs everything up the road.
	ForwardChance = 0.65,

	-- Draws the racing line (blue checkpoints, yellow spline between
	-- them), a white line to where each bot is steering, and a throttle
	-- bar above it that turns red when it thinks it's cornering.
	--
	-- The racing line is the one that settles arguments: if THAT cuts a
	-- corner, no amount of bot tuning helps — it's RouteTension or more
	-- checkpoints.
	Debug = false,
}
