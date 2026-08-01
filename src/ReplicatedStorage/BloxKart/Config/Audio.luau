--[[
	Audio — sound ids, volumes, pitches.
--]]

return {
	--== DRIFT CHARGE NOTES ============================================
	-- Each tier fires a FRESH one-shot from the start at its own pitch,
	-- overlapping whatever is still ringing. No gliding — the step is
	-- instant, which is what makes it read as a note rather than a siren.
	TierNoteId = "rbxassetid://127199850989931",
	TierNoteVolume = 0.85,
	TierNoteVoices = 4, -- pool size. A Sound can't overlap itself, so
	-- notes round-robin across this many.
	-- Equal-temperament ratios, so the steps land on real notes.
	TierNotePitches = {
		1.000, -- do  (C)  drift starts
		1.122, -- re  (D)  tier 1, blue
		1.260, -- mi  (E)  tier 2, orange
		1.498, -- sol (G)  tier 3, purple — skips fa for a brighter top
	},

	--== BOOST =========================================================
	BoostSoundId = "rbxassetid://83211426606907",
	BoostSoundVolume = 0.9,
	BoostSoundPitch = 1.0, -- base pitch; each tier nudges it up
	BoostPitchPerTier = 0.07,

	--== TYRE SCREECH ==================================================
	-- Driven by actual slip angle, not a drifting on/off flag. Lean on
	-- the kart mid-corner and the tyres complain a little; commit to a
	-- drift and they howl. That continuity is most of what makes a
	-- screech sound like it belongs to the driving rather than being
	-- pasted over it.
	ScreechId = "rbxassetid://109487442763183",
	ScreechVolume = 0.75, -- at full slip
	ScreechFade = 11, -- how fast volume follows slip
	ScreechMinSlip = 0.18, -- below this the tyres stay quiet, so normal
	-- cornering doesn't squeal constantly
	ScreechSpeedFloor = 14, -- studs/s under which tyres never screech
	ScreechPitchLow = 0.88, -- pitch at the threshold
	ScreechPitchHigh = 1.22, -- pitch at full slip
	ScreechPitchRate = 9, -- smoothed, like the engine — a screech that
	-- steps between pitches sounds like a broken sample

	--== PICKUP ========================================================
	--== BEING HIT ====================================================
	-- Played whenever something lands on you and spins you, whatever it
	-- was. Getting hit is one event to the player — the kart is gone from
	-- under them — so it gets one sound, and the item on top of it says
	-- WHICH thing did it.
	HitSoundId = "rbxassetid://85376004233635", -- spun out
	HitSoundVolume = 0.9,

	-- Per-item, layered OVER the generic one. A missile arriving should
	-- sound like a missile arriving, not like a banana.
	--
	-- Keyed by item Id, so adding a sound for a new item is one line here
	-- and nothing anywhere else. An item with no entry simply gets the
	-- generic hit and is none the worse for it.
	ItemHitIds = {
		Missile = "rbxassetid://122840050680240", -- explosion
		-- The strike. Lightning arrives with no projectile and no engine
		-- cue, so the sound IS the event — it is the only thing that
		-- says what just happened at the moment it happens.
		Lightning = "rbxassetid://116644751820648",
	},
	ItemHitVolume = 1,

	PickupSoundId = "rbxassetid://117570443671176", -- roulette lands
	PickupVolume = 0.85,
	-- One click per name the roulette cycles past. A single Sound is
	-- correct here rather than a pool: a click that overlaps itself
	-- smears into a buzz, and rewinding is what makes it read as ticks.
	RouletteTickId = "rbxassetid://133220299283816",
	RouletteTickVolume = 0.45,

	--== ENGINE ========================================================
	-- Pitch tracks speed. Deliberately SMOOTH, unlike the drift notes —
	-- an engine that snaps between pitches sounds broken, whereas a
	-- musical note that slides sounds like a siren.
	EngineSoundId = "rbxassetid://9112787518",
	EngineVolume = 0.45,
	EngineIdlePitch = 0.70, -- pitch at a standstill
	EngineMaxPitch = 1.85, -- pitch at MaxSpeed
	EngineBoostPitch = 2.15, -- pitch while boosting
	EnginePitchRate = 7, -- how fast pitch chases speed

	--== OTHER PEOPLE'S KARTS =========================================
	-- Every sound above is built on the client and parented to YOUR
	-- kart, and client-made instances never replicate — so all of it was
	-- audible to exactly one person. A race sounded like driving alone.
	--
	-- RemoteAudio gives every other kart an engine and a set of tyres,
	-- worked out from the only thing that does replicate: where the kart
	-- is. Speed is how far it moved; slip is the angle between the way it
	-- moved and the way it faces, which is not an approximation of
	-- drifting but the definition of it.
	--
	-- No extra replication, which matters — publishing "am I drifting"
	-- per kart per frame is exactly the SetAttribute traffic this file is
	-- careful about everywhere else.
	RemoteEnabled = true,

	-- Quieter than your own, both of them. You should hear the pack
	-- without losing your own kart in it, and eight engines at full
	-- volume is a wall rather than a race.
	RemoteEngineShare = 0.45,
	RemoteScreechShare = 0.7, -- tyres carry further than engines, and a
	-- drift beside you is worth hearing

	RemoteRollOff = 140, -- studs. Short enough that the field ahead is a
	-- hint rather than a crowd in your ear

	-- How fast the estimated speed follows the measured one. Replication
	-- arrives in steps, so the raw frame delta is zero on frames with no
	-- update and double on the frame after — unsmoothed, every remote
	-- engine warbles.
	RemoteSmoothing = 8,
}
