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
	FillTo = 4,
	MaxBots = 7, -- never more than the grid has slots for

	-- Bots are stepped at this rate rather than every frame. The
	-- controller is frame-rate independent by construction, so this costs
	-- nothing in behaviour and halves the server's raycast load — which
	-- is the real limit on how many bots a race can have.
	StepRate = 30,

	--== SKILL =========================================================
	-- Rolled per bot at spawn, and scales everything below. Kept away
	-- from 1 at the top: a perfect bot is a boring one.
	SkillMin = 0.45,
	SkillMax = 0.92,

	-- A Model with a Humanoid in ServerStorage, sat in each bot's seat so
	-- they look like racers rather than empty karts. Rider puts its hands
	-- on the wheel automatically — it doesn't care that the driver isn't
	-- a player. "" for empty karts.
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

	SteerGain = 2.4, -- how hard it corrects toward the line. Higher is
	-- twitchier, not faster
	SteerSlew = 9, -- how fast its steering input can move. This is what
	-- stops a bot flicking to full lock instantly, which no human can do

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

	Debug = false,
}
