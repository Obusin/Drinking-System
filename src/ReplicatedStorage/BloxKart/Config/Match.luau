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
	-- HUMANS needed to run a round, not karts. One is right: the field
	-- is filled with AI, so a solo player has seven opponents and a race
	-- rather than an empty track and a wait for somebody who may never
	-- arrive.
	--
	-- Counting KARTS here is what made it look like two players were
	-- required. Bots only spawn at the grid, the grid is only reached
	-- from Intermission, and Intermission was gated on a kart count that
	-- nothing could raise — so one player waited forever for the bots
	-- that were waiting for them.
	MinRacers = 1,

	-- ONE LINE PER PHASE CHANGE, with the counts that decide the next
	-- one. On by default: the loop has been debugged by inference for
	-- long enough, and a round that goes wrong should say what it did
	-- rather than leave it to be reconstructed.
	LoopTrace = true,
	-- NOTE: grid size lives in Rig.MaxRacers, not here. There was a second
	-- copy of it in this file that nothing read — two numbers meaning one
	-- thing, waiting to disagree.

	--== PHASE LENGTHS =================================================
	-- Time between rounds. Long enough to read the results board and
	-- short enough that nobody alt-tabs.
	-- TESTING: shortened from 8 so a lap-and-restart cycle is quick to
	-- iterate on. Put this back to 8 before shipping — 3 is not enough
	-- time to read a results board.
	IntermissionTime = 3,
	-- Maximum time spent waiting for a joining client's splash to reveal. The
	-- normal route is event-driven; this only prevents one failed client from
	-- holding a whole server forever.
	IntermissionLoadTimeout = 30,

	-- Karts are on the grid and held still for this long. This is the
	-- 3-2-1-GO, so it wants to be a whole number of seconds plus a beat
	-- for "GO" to land on zero.
	GridTime = 4,
	-- The Grid phase first places and holds every kart, then waits for all
	-- expected human clients to confirm that their local kart attached and
	-- applied the grid CFrame. This is a safety ceiling, not a normal path:
	-- a broken/disconnecting client must not stall an entire server forever.
	GridReadyTimeout = 15,

	-- Authored camera markers live at ReplicatedFirst.Intermission. All
	-- BaseParts beneath it are read as an ordered cinematic path by the
	-- client; rotate each part to compose its shot.
	IntermissionCamera = {
		Enabled = true,
		FolderName = "Intermission",
		SegmentTime = 3.5,
		FinalHold = 1.0,
		-- The intermission is a presentation beat, not a ready-up skip.
		-- When markers exist, always let the complete authored rail play.
		LockFullSequence = true,
		Fov = 72,
	},

	-- After the Intermission rail ends, CUT to a dedicated wide player shot,
	-- then tighten into normal chase composition. The two camera sequences are
	-- deliberately separate; this is presentation only and never delays input.
	GridCamera = {
		Enabled = true,
		Duration = 1.45,
		StartFov = 82,
		StartDistance = 48,
		StartHeight = 22,
		StartLookHeight = 4,
	},

	-- Hard cap on a round. Nobody should ever hit this — it exists so a
	-- single AFK player can't hold the server hostage.
	--
	-- 300 -> 600. Sunset Circuit runs about 4 minutes for three laps, and
	-- a five-minute cap gives a slow driver only 25% headroom. That is
	-- not a safety net, it is a second finish line — and the one it cuts
	-- off is always the player already having the worst race.
	--
	-- Rule of thumb: roughly TWICE the expected finish time. It should be
	-- unreachable by anyone actually driving, which is the only way it
	-- stays what the comment above says it is.
	TimeLimit = 600,

	-- Once the FIRST racer finishes, everyone else gets this long to
	-- come in before the round is called. Standard kart-game behaviour:
	-- you get to finish, but you don't get to hold up the lobby.
	FinishGrace = 45,

	-- Beat between the last car crossing the line and the board coming
	-- up, so the finish registers before the UI takes over.
	FinishSettle = 1.5,

	ResultsTime = 15,

	--== AFTER THE FLAG ================================================
	-- How long a finished kart coasts before it parks. It is not a racing
	-- AI: no pickups, no hazards and no power-ups are allowed after the flag.
	--
	-- It also exists for a plainer reason: a bot that finished used to
	-- keep racing until the round ended, lapping the field two or three
	-- more times and cluttering the track for everyone still trying to
	-- finish. Finishing has to actually end the drive.
	FinishDriveTime = 1.25,
	-- How long the FINISH banner hangs before fading. Longer than the
	-- countdown's, because it is read rather than reacted to.
	FinishFadeTime = 1.6,

	--== ELIMINATION ===================================================
	-- Fall in the void within this many seconds of being hit and whoever
	-- hit you is CREDITED with an elimination.
	--
	-- NOBODY IS REMOVED FROM THE RACE. The victim respawns at their last
	-- checkpoint exactly as they always have; this is a tally and an XP
	-- award, nothing more.
	--
	-- The window is what makes the credit belong to the hit rather than
	-- to the fall. Drive into a pit unprovoked and nobody scored; get
	-- missiled off a bridge and somebody did. Same geometry, different
	-- story, and the difference is whether someone put you there.
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
