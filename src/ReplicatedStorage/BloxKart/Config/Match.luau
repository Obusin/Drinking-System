--[[
	Match — the race loop: who's in, when it starts, when it's over.

	The whole game used to be one endless free-drive. This is what turns
	it into rounds.

		Waiting  →  Intermission  →  Grid  →  Racing  →  Results  →  ⤾

	Every duration here is in seconds and every one is safe to change
	without touching code.
--]]

return {
	--== FIELD =========================================================
	-- 1 so you can test alone. Raise it once there are people to wait
	-- for; below this the match sits in Waiting and nothing starts.
	--
	-- NOTE: counts karts the match OWNS, which means player karts. With
	-- Rig.TestMode = true there are none — the shared kart on the pad
	-- isn't assigned to anybody — so the match sits in Waiting forever
	-- and you free-drive. That's usually what you want out of test mode,
	-- but it does mean the countdown can't be tested from it.
	MinRacers = 2,
	-- NOTE: grid size lives in Rig.MaxRacers, not here. There was a second
	-- copy of it in this file that nothing read — two numbers meaning one
	-- thing, waiting to disagree.

	--== PHASE LENGTHS =================================================
	-- Time between rounds. Long enough to read the results board and
	-- short enough that nobody alt-tabs.
	IntermissionTime = 8,

	-- Karts are on the grid and held still for this long. This is the
	-- 3-2-1-GO, so it wants to be a whole number of seconds plus a beat
	-- for "GO" to land on zero.
	GridTime = 4,

	-- Hard cap on a round. Nobody should ever hit this — it exists so a
	-- single AFK player can't hold the server hostage.
	TimeLimit = 300,

	-- Once the FIRST racer finishes, everyone else gets this long to
	-- come in before the round is called. Standard kart-game behaviour:
	-- you get to finish, but you don't get to hold up the lobby.
	FinishGrace = 45,

	-- Beat between the last car crossing the line and the board coming
	-- up, so the finish registers before the UI takes over.
	FinishSettle = 1.5,

	ResultsTime = 10,

	--== AFTER THE FLAG ================================================
	-- How long a finished racer keeps driving before it leaves the
	-- world. The AI already has the kart by then, so this is a short
	-- cutscene you watch rather than a pause you sit through.
	--
	-- It also exists for a plainer reason: a bot that finished used to
	-- keep racing until the round ended, lapping the field two or three
	-- more times and cluttering the track for everyone still trying to
	-- finish. Finishing has to actually end the drive.
	FinishDriveTime = 5,

	--== ELIMINATION ===================================================
	-- Touch the void within this many seconds of being hit and you are
	-- OUT, rather than respawned.
	--
	-- The window is what makes it a consequence of the hit rather than
	-- of the fall. Drive into a pit unprovoked and you respawn like
	-- always; get missiled off a bridge and you are gone. Same geometry,
	-- different story, and the difference is whether someone did it to
	-- you.
	--
	-- Long enough to cover the spin, the lost grip and the actual fall.
	-- Too short and the rule reads as random.
	EliminationWindow = 6,
	EliminationText = "ELIMINATED",


	--== READY UP ======================================================
	-- Everyone ready skips the rest of the intermission. Testing alone
	-- this means you never wait 8 seconds.
	AllowReadySkip = true,
	-- NOT R — that's Respawn.ResetKeys. Two actions on one key would
	-- both fire, and "ready up" would teleport you to a checkpoint.
	ReadyKey = Enum.KeyCode.F,

	--== HUD ===========================================================
	-- Countdown numbers and GO, centre screen.
	CountdownSize = 150,
	CountdownGoSize = 190,
	CountdownColor = Color3.fromRGB(255, 255, 255),
	CountdownGoColor = Color3.fromRGB(120, 255, 170),
	CountdownFadeTime = 0.7, -- how long GO lingers after the start

	-- Status line (waiting for racers, intermission clock).
	StatusSize = 22,
	StatusColor = Color3.fromRGB(210, 216, 230),
	StatusPosition = UDim2.new(0.5, 0, 0, 96),

	--== RESULTS BOARD =================================================
	ResultsWidth = 420,
	ResultsRowHeight = 40,
	ResultsTitleSize = 30,
	ResultsRowSize = 19,
	ResultsColor = Color3.fromRGB(255, 255, 255),
	ResultsDimColor = Color3.fromRGB(165, 172, 190),
	-- The local player's own row, so you can find yourself instantly in
	-- a field of eight.
	ResultsSelfColor = Color3.fromRGB(120, 255, 170),

	Debug = false,
}
