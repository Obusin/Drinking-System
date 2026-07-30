--[[
	Respawn — getting back on track after falling off it.

	Tag parts `VoidZone` in the Tag Editor for anything that should kill
	on contact: pits, water, lava, the gap between two track pieces.
	Like every other trigger they're meant to be CanCollide = false —
	you drive THROUGH them.

	CHECKPOINT AUTHORING
	--------------------
	You respawn at the last checkpoint you passed, facing its LookVector.
	So a checkpoint part's FRONT FACE must point down the track. Get that
	backwards and players respawn facing a wall.
--]]

return {
	VoidTag = "VoidZone",

	-- HOW "FELL OFF" IS DETECTED
	--
	-- By TIME IN FREEFALL, not by height. Height thresholds need to know
	-- where the track is, and they always guess wrong: measured against a
	-- checkpoint they break because a gate's centre sits well above the
	-- road, and measured absolutely they break on any track that isn't
	-- near Y=0. Both fire while you're driving perfectly normally.
	--
	-- Falling continuously for this long means you are not coming back,
	-- on any track, at any altitude, with no tuning. Jumps and drops
	-- never reach it — you land.
	--
	-- OFF for now, by choice. Big jumps, launch ramps and long airborne
	-- sections would all trip a freefall timer, and a respawn mid-stunt
	-- is worse than no respawn at all. VoidZone tags do the job instead.
	--
	-- Raise it to ~6 if you ever want the net back — long enough that no
	-- legitimate jump reaches it.
	FreefallTime = 0,

	-- Absolute last resort, for a track suspended over nothing. Keep it
	-- well ABOVE Config.Rig.RespawnBelow or the server rebuilds the whole
	-- kart before this runs.
	FallFloor = -500,

	RespawnLift = 5, -- studs above the checkpoint, so you drop in clean
	FreezeTime = 0.7, -- controls locked briefly on arrival, so you don't
	-- immediately drive back off the same edge
	Cooldown = 1.5, -- minimum gap between respawns, so a void zone that
	-- overlaps the respawn point can't loop

	-- Banked nitro survives. Losing the tanks as well as the position is
	-- a double punishment for one mistake.
	KeepTanks = true,

	ResetKeys = { Enum.KeyCode.R, Enum.KeyCode.ButtonSelect },

	--== STUCK DETECTION ===============================================
	-- Reset is OFFERED, never always-available. An always-on reset key
	-- is a shortcut: skip a corner you keep failing by resetting to the
	-- checkpoint just past it. Gating it behind "you are demonstrably
	-- stuck" removes that without punishing anyone genuinely wedged.
	--
	-- The signal is trying to move and not moving — throttle down, speed
	-- near zero. Coasting to a stop at the start line isn't stuck.
	StuckSpeed = 4, -- studs/s below which you count as not moving
	StuckTime = 2.5, -- seconds of trying before the offer appears

	-- Falling with no ground under you. Long, and it only OFFERS the
	-- button rather than respawning you, so it can't ruin a stunt the
	-- way an automatic freefall respawn would.
	StuckAirTime = 4.0,

	ButtonText = "RESET TO TRACK",
	ButtonHint = "R",
}
