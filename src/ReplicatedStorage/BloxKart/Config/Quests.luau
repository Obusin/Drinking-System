--[[
	Quests — the pools. 50 of them.

	Design lives in the vault at "BloxKart Quest Design"; this is the
	content. Nothing reads this file yet: quests need counters, counters
	need `DataService`, and `DataService` needs the two client-authority
	seams closed first. The pools are authored now because they are the
	part that needs judgement, and they can be argued about without any
	of that existing.

	THE RULE EVERY ENTRY HERE OBEYS
	-------------------------------
	A quest must never make you play the race badly. That is the failure
	mode of nearly every kart-game quest list, and it is easy to write by
	accident:

		"Hold an item for 60 seconds"   you stop using items
		"Hit 3 players with missiles"   you hunt instead of racing
		"Drift for 60 seconds"          you drift on straights, slower

	So there is no quest here that rewards HOLDING, no quest that names a
	specific item as a weapon, and no quest that asks for a duration of
	something you should only do when the corner calls for it. What is
	here instead counts things winning already produces.

	THE OTHER RULE: at least one daily must be completable while
	finishing last. That is the whole `Guaranteed` slot.

	Difficulty never depends on lobby population — the field is filled
	with bots, so "beat 5 racers" means the same thing at 3am as at peak.
	The one exception is the `Social` weekly slot, which is about other
	humans by definition and is therefore a single slot, not a theme.

	--== METRICS ======================================================
	`metric` is the counter a quest reads. Emitting them is the work this
	file is waiting on. Today:

		LIVE (Progress already counts these)
			races, finishes, hits, takedowns, eliminations, xp

		KNOWN BUT NOT EMITTED (the client or a service has the number,
		nothing publishes it)
			laps, checkpoints, place, raceSeconds, driftBoosts,
			boostPads, nitroBurns, itemsUsed, itemBoxes, topSpeedSeconds,
			respawns, gridGain, bestLap

		NEEDS A SYSTEM THAT DOES NOT EXIST
			skinsEquipped, kartsRaced, partsOwned, craftsClaimed,
			friendsRaced, clubmatesRaced  (DataService, Skins catalogue,
			and any social layer at all)

	A quest whose metric is not live is not broken, it is unreachable —
	it will simply never tick. THE GENERATOR MUST FILTER BY METRIC, not
	draw blind from these tables, or a player gets handed a bar that
	cannot move and no way to tell why. Nothing is commented out here on
	purpose: the pools are the design, and which of them are currently
	reachable is a property of the code, not of the content.
--]]

return {
	--== DAILY =========================================================
	-- Three slots a day, one drawn from each pool below, plus one
	-- reroll. Rewards are Bolt and Pass XP only — Crystals come from
	-- weeklies, so that monthly Crystal income stays a number a player
	-- can compute.
	Daily = {
		-- SLOT 1. No skill component, no mode requirement, and every one
		-- of these completes while finishing last. This is the slot that
		-- stops a bad night being a wasted one.
		Guaranteed = {
			{ id = "d_race3", text = "Race 3 times", metric = "races", target = 3, bolt = 120, xp = 60 },
			{ id = "d_race5", text = "Race 5 times", metric = "races", target = 5, bolt = 180, xp = 90 },
			{ id = "d_finish2", text = "Finish 2 races", metric = "finishes", target = 2, bolt = 130, xp = 65 },
			{ id = "d_finish3", text = "Finish 3 races", metric = "finishes", target = 3, bolt = 170, xp = 85 },
			{ id = "d_laps8", text = "Complete 8 laps", metric = "laps", target = 8, bolt = 120, xp = 60 },
			{ id = "d_laps12", text = "Complete 12 laps", metric = "laps", target = 12, bolt = 160, xp = 80 },
			{ id = "d_cp30", text = "Pass 30 checkpoints", metric = "checkpoints", target = 30, bolt = 110, xp = 55 },
			{ id = "d_time5", text = "Spend 5 minutes on track", metric = "raceSeconds", target = 300, bolt = 140, xp = 70 },
		},

		-- SLOT 2. Things you already do while driving well. Every target
		-- is reachable inside the same 3 races slot 1 asks for, so the
		-- two never pull in different directions.
		Verb = {
			{ id = "d_drift15", text = "Drift-boost 15 times", metric = "driftBoosts", target = 15, bolt = 140, xp = 70 },
			{ id = "d_drift30", text = "Drift-boost 30 times", metric = "driftBoosts", target = 30, bolt = 200, xp = 100 },
			{ id = "d_pads10", text = "Hit 10 boost pads", metric = "boostPads", target = 10, bolt = 130, xp = 65 },
			{ id = "d_nitro5", text = "Burn nitro 5 times", metric = "nitroBurns", target = 5, bolt = 130, xp = 65 },
			{ id = "d_items5", text = "Use 5 items", metric = "itemsUsed", target = 5, bolt = 130, xp = 65 },
			{ id = "d_items10", text = "Use 10 items", metric = "itemsUsed", target = 10, bolt = 190, xp = 95 },
			{ id = "d_boxes8", text = "Collect 8 item boxes", metric = "itemBoxes", target = 8, bolt = 130, xp = 65 },
			{ id = "d_top20", text = "Spend 20 seconds at top speed", metric = "topSpeedSeconds", target = 20, bolt = 150, xp = 75 },
			{ id = "d_hits5", text = "Land 5 items on other racers", metric = "hits", target = 5, bolt = 160, xp = 80 },
			{ id = "d_take3", text = "Spin out 3 racers", metric = "takedowns", target = 3, bolt = 180, xp = 90 },
		},

		-- SLOT 3. Real, but never punishing — and note that none of
		-- these require WINNING except the one that says so, which is
		-- one option in eight rather than the daily itself.
		Stretch = {
			{ id = "d_top3", text = "Finish in the top 3", metric = "place", target = 3, compare = "atMost", bolt = 260, xp = 130 },
			{ id = "d_win1", text = "Win a race", metric = "place", target = 1, compare = "atMost", bolt = 320, xp = 160 },
			{ id = "d_bestlap", text = "Beat your best lap on any track", metric = "bestLap", target = 1, bolt = 280, xp = 140 },
			{ id = "d_gain3", text = "Finish 3 places above your grid slot", metric = "gridGain", target = 3, bolt = 280, xp = 140 },
			{ id = "d_elim2", text = "Knock 2 racers off the track", metric = "eliminations", target = 2, bolt = 300, xp = 150 },
			{ id = "d_clean1", text = "Finish a race without respawning", metric = "cleanRaces", target = 1, bolt = 300, xp = 150 },
		},
	},

	--== WEEKLY ========================================================
	-- Five slots, reset Monday. Large totals and NO per-day requirement:
	-- forgiving a missed day is the entire design brief of this layer.
	-- No streak — a streak that breaks is a reason to stop playing.
	--
	-- This is where Crystals come from. A fixed weekly payout makes
	-- monthly Crystal income computable, which is what turns the
	-- economy's 1-2 month target into something a player can plan
	-- toward rather than hope for.
	Weekly = {
		General = {
			{ id = "w_races20", text = "Race 20 times", metric = "races", target = 20, bolt = 900, xp = 450, crystals = 8 },
			{ id = "w_finish15", text = "Finish 15 races", metric = "finishes", target = 15, bolt = 900, xp = 450, crystals = 8 },
			{ id = "w_laps60", text = "Complete 60 laps", metric = "laps", target = 60, bolt = 850, xp = 420, crystals = 7 },
			{ id = "w_wins5", text = "Win 5 races", metric = "wins", target = 5, bolt = 1200, xp = 600, crystals = 12 },
			{ id = "w_top3x10", text = "Finish top 3 ten times", metric = "podiums", target = 10, bolt = 1050, xp = 520, crystals = 10 },
			{ id = "w_drift100", text = "Drift-boost 100 times", metric = "driftBoosts", target = 100, bolt = 900, xp = 450, crystals = 8 },
			{ id = "w_pads50", text = "Hit 50 boost pads", metric = "boostPads", target = 50, bolt = 800, xp = 400, crystals = 7 },
			{ id = "w_items40", text = "Use 40 items", metric = "itemsUsed", target = 40, bolt = 850, xp = 420, crystals = 7 },
			{ id = "w_hits30", text = "Land 30 items on other racers", metric = "hits", target = 30, bolt = 950, xp = 470, crystals = 9 },
			{ id = "w_elims10", text = "Knock 10 racers off the track", metric = "eliminations", target = 10, bolt = 1100, xp = 550, crystals = 11 },
		},

		-- One slot, deliberately. The cheapest possible version of the
		-- club-quest hook, available before any hub exists — and the
		-- only place in the whole list where other humans are required,
		-- so a quiet server never blocks the other four.
		Social = {
			{ id = "w_full5", text = "Race 5 times in a full lobby", metric = "fullLobbyRaces", target = 5, bolt = 900, xp = 450, crystals = 8 },
			{ id = "w_friend3", text = "Race 3 times with a friend", metric = "friendsRaced", target = 3, bolt = 1000, xp = 500, crystals = 10 },
			{ id = "w_club3", text = "Race 3 times with a club member", metric = "clubmatesRaced", target = 3, bolt = 1000, xp = 500, crystals = 10 },
			{ id = "w_beat10", text = "Finish ahead of 10 human racers", metric = "humansBeaten", target = 10, bolt = 1050, xp = 520, crystals = 10 },
		},

		-- Gets people WEARING what they own. An unworn cosmetic
		-- advertises nothing; a worn one is the shop's best display.
		Collection = {
			{ id = "w_newskin", text = "Equip a skin you have not used", metric = "skinsEquipped", target = 1, bolt = 800, xp = 400, crystals = 7 },
			{ id = "w_karts3", text = "Race in 3 different karts", metric = "kartsRaced", target = 3, bolt = 900, xp = 450, crystals = 8 },
			{ id = "w_craft1", text = "Claim a fragment craft", metric = "craftsClaimed", target = 1, bolt = 950, xp = 470, crystals = 9 },
			{ id = "w_fullset", text = "Race wearing a matched set", metric = "matchedSetRaces", target = 1, bolt = 850, xp = 420, crystals = 7 },
		},
	},

	--== MONTHLY =======================================================
	-- Not a bigger weekly. This is the season, and it is ONE TRACK that
	-- dailies and weeklies both pour into — so a player who ignores the
	-- quest screen entirely still moves along it by racing.
	--
	-- Sized to roughly 60% of a month's active days. Someone playing
	-- four days a week finishes it. That number is chosen against the
	-- reference game, whose top-item grind reviewers called out by name.
	--
	-- The month's keepsake is NOT in this table. It sits on the free
	-- line of the Pass, is never purchasable, and is the one reward in
	-- the entire economy money cannot reach.
	Monthly = {
		{ id = "m_races100", text = "Race 100 times", metric = "races", target = 100, bolt = 4000, xp = 2000, crystals = 40 },
		{ id = "m_laps300", text = "Complete 300 laps", metric = "laps", target = 300, bolt = 3800, xp = 1900, crystals = 38 },
		{ id = "m_wins25", text = "Win 25 races", metric = "wins", target = 25, bolt = 5000, xp = 2500, crystals = 50 },
		{ id = "m_podium40", text = "Finish top 3 forty times", metric = "podiums", target = 40, bolt = 4400, xp = 2200, crystals = 44 },
		{ id = "m_elims60", text = "Knock 60 racers off the track", metric = "eliminations", target = 60, bolt = 4600, xp = 2300, crystals = 46 },
		{ id = "m_level10", text = "Reach level 10", metric = "level", target = 10, bolt = 4200, xp = 0, crystals = 42 },
		{ id = "m_xp20k", text = "Earn 20,000 XP", metric = "xp", target = 20000, bolt = 4000, xp = 0, crystals = 40 },
		{ id = "m_parts10", text = "Own 10 kart parts", metric = "partsOwned", target = 10, bolt = 4400, xp = 2200, crystals = 44 },
	},
}
