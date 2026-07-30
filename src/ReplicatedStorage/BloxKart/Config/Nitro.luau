--[[
	Nitro — three tanks, banked by drifting, spent on demand.

	Drifting fills tanks one at a time. Tapping the nitro key COMMITS a
	tank and lights the burn; tapping again mid-burn commits another and
	steps up a stage. So "one shift, two shifts, three shifts" is
	literally how many tanks you're spending.

		tap        stage 1   1 tank      long, efficient
		tap tap    stage 2   2 tanks     shorter, faster
		tap x3     stage 3   3 tanks     brief, fastest

	THE STAGES ARE DELIBERATELY INEFFICIENT
	---------------------------------------
	If stage 3 gave three times the value of three stage-1 burns, there
	would be no decision — you'd always dump everything. Peak power has
	to cost you total distance:

	    stage 1   18 x 4.0s  / 1 tank  =  72 speed-seconds per tank
	    stage 2   45 x 2.6s  / 2 tanks =  58
	    stage 3   80 x 1.6s  / 3 tanks =  43

	Three separate stage-1 burns carry you furthest. A stage 3 wins you
	one specific moment — an overtake, a hill, a defence — and you pay
	for it. That gap IS the mechanic. If you retune, keep the per-tank
	efficiency descending or the stages become cosmetic.

	Discrete tanks rather than one continuous bar because you can count
	them at a glance. "Do I have enough for a stage 2?" is a question you
	answer from peripheral vision mid-corner; reading a percentage isn't.

	These numbers are placeholders. A nitro economy is lap-scale: how
	much is right depends on track length, how often you can drift and
	whether you're chasing or defending. Retune once there are real races.
--]]

return {
	--== TANKS =========================================================
	MaxTanks = 3,

	-- Fills CONTINUOUSLY while drifting, not as a lump on release —
	-- watching a tank climb as you hold the slide is what makes a long
	-- drift feel worth committing to.
	FillPerSecond = 0.55, -- tanks per second (~1.8s per tank)
	-- Deeper drift tiers fill faster, so holding past each threshold
	-- pays more per second as well as for longer.
	TierFillBonus = { 1.0, 1.25, 1.5 },

	-- Once all three are full, further drifting is wasted. Creates
	-- spend-it-or-lose-it pressure rather than letting players hoard.
	AllowOverflow = false,

	--== ANTI-CHAIN ====================================================
	-- Spending nitro ENDS the drift you're in.
	--
	-- Without it a player never has to leave the drift state: charge, tap,
	-- keep holding, charge, tap — a permanent boost loop that costs
	-- nothing and looks nothing like driving. Ending the drift forces the
	-- choice the mechanic is supposed to be about: keep sliding to bank
	-- more, or cash in and go straight.
	EndDriftOnBurn = true,

	-- Hard cap on what ONE unbroken drift can bank. Past this it earns
	-- nothing until you release and re-enter.
	--
	-- Belt and braces alongside EndDriftOnBurn, which only triggers if the
	-- player actually spends — a very long sweeper could otherwise fill
	-- all three tanks on its own and there'd be no reason to stop sliding.
	-- Set 0 to disable the cap.
	MaxTanksPerDrift = 2,

	-- You cannot earn and spend at the same time.
	--
	-- Without this, drifting THROUGH a burn refills the tanks at least as
	-- fast as they drain, which is infinite boost — and it isn't even an
	-- exploit you have to look for, it's what happens naturally when you
	-- light a stage into a long corner. Closing it keeps the loop honest:
	-- a drift either earns or it doesn't.
	FillWhileBurning = false,

	--== BURN STAGES ===================================================
	-- Stage N costs N tanks in total: lighting it spends one, and each
	-- escalation spends one more. Duration and speed both come from
	-- whichever stage you end up at.
	Stages = {
		{ Speed = 18, Duration = 4.0, Fov = 4, Shake = 0.15 },
		{ Speed = 45, Duration = 2.6, Fov = 9, Shake = 0.35 },
		{ Speed = 80, Duration = 1.6, Fov = 15, Shake = 0.60 },
	},

	-- How hard the kart pulls toward the boosted speed. Higher than the
	-- normal Accel so a burn feels like a shove, not a slow build.
	BurnAccel = 7,

	-- Below this a tank can't be lit, so you can't dump three tanks into
	-- a standstill.
	MinBurnSpeed = 8,
}
