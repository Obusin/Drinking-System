--[[
	Audio — sound ids, volumes, pitches.
--]]

return {
	--== RACE COUNTDOWN VOICE ==========================================
	-- Native Roblox TTS. This is local 2D audio, so every racer hears the
	-- starter independently and it never becomes a world-positioned sound.
	CountdownTTS = true,
	CountdownTTSVoiceId = "11", -- Roblox's host voice
	CountdownTTSVolume = 0.9,

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
	HitSoundId = "rbxassetid://129285831966291", -- spun out / stunned
	HitSoundVolume = 0.9,

	--== BUMPING INTO THINGS ===========================================
	-- Played on a BOUNCE, not on every graze. Simulation only raises
	-- `bounced` for a square-enough impact, so wall-riding a corner stays
	-- silent and an actual crash does not.
	BumpSoundId = "rbxassetid://131553371831354",
	BumpSoundVolume = 0.85,

	-- PITCH VARIES WITH THE IMPACT, and that is what stops it sounding
	-- like a sample. `bounced` carries how square the hit was (0..1), so
	-- a glancing thud is higher and lighter than a head-on one.
	BumpPitchLow = 1.12, -- barely square enough to count
	BumpPitchHigh = 0.86, -- dead-on. LOWER is heavier, hence the order.

	--== LEAPING ========================================================
	-- The launch off a ramp, and the skip off a wave. ONE SOUND FOR ALL
	-- OF THEM, pitched by how big the leap is — the same reasoning as the
	-- bump: a sample played identically every time stops being an event
	-- and becomes wallpaper.
	--
	-- Fired at the LAUNCH. Going up is the moment worth hearing; the
	-- landing already has the bump and the splash.
	LeapSoundId = "rbxassetid://120666632097409",
	LeapSoundVolume = 0.8,

	-- HIGHER FOR A SMALL LEAP, lower for a big one — pitch reads as mass,
	-- so a little skip should sound light and a ramp launch should not.
	LeapPitchLow = 1.18, -- the smallest leap that makes a sound
	LeapPitchHigh = 0.88, -- a full ramp launch

	-- THE WATER HOP IS QUIETER AND FUSSIER, because it fires far more
	-- often than a ramp ever does — 3 to 5 times a second, continuously,
	-- while a ramp fires once. At ramp volume that is a machine gun, so
	-- it is dropped to a fraction and only the biggest skips speak.
	--
	-- Set WaterLeapVolume to 0 to silence the water entirely and keep the
	-- ramps, which is the dial to reach for first if it feels busy.
	WaterLeapVolume = 0.3, -- fraction of LeapSoundVolume

	-- MEASURED, AND RE-MEASURED once the hop became continuous. It has
	-- been wrong twice in opposite ways, which is the point of the note:
	--
	--   0.55 gated NOTHING — it was also `Swim.WaveHopMinScale`, so the
	--        smallest possible hop already cleared it. A threshold set to
	--        the floor of the thing it filters is not a threshold.
	--   0.80 was right while hops were occasional, and became a drone the
	--        moment they went to 3-5 a second.
	--   0.93 was right at 3-5/s, and went too sparse when the cadence was
	--        halved to 1.5-2.5 — one sound every few seconds.
	--
	-- THE LESSON: this gate is a fraction of a RATE, so it has to be
	-- re-measured every time the hop cadence moves. It is not a property
	-- of the sound.
	--
	-- Hop size runs 0.72..1.0 with a median near 0.87. At the current
	-- 1.8-2.4 hops/s, what each gate lets through in sounds per second:
	--
	--    speed   hops/s   0.88   0.90   0.93
	--      12     1.77    0.69   0.51   0.25
	--      40     1.96    0.80   0.65   0.48
	--      95     2.36    0.96   0.81   0.69
	--
	-- 0.88 accents roughly the biggest 40% — about one a second — so it
	-- syncopates against the rhythm instead of doubling it. A sound on
	-- every hop is not a cue, it is an engine note.
	WaterLeapMinScale = 0.88, -- fraction of a full hop before it sounds

	--== THE CROWD =====================================================
	-- A BED AND A REACTION, which sound like one thing and are not.
	--
	-- The bed is a quiet continuous murmur that says "people are
	-- watching". It should never draw attention to itself — you only
	-- notice it when it stops. Subtle is the whole brief.
	--
	-- Non-positional, parented to SoundService like the music: a stadium
	-- SURROUNDS you, and a crowd that pans as you steer reads as one man
	-- with a megaphone.
	CrowdBedId = "rbxassetid://1839973460",
	CrowdBedVolume = 0.18, -- deliberately low. It is a bed, not a track.
	CrowdFade = 0.8, -- per second, in and out of the grid

	-- LOBBY TOO, FOR NOW. Normally the crowd belongs to Grid and Racing
	-- only — you are not in the stadium until you are on the grid, and a
	-- crowd murmuring over the menu says the race already started.
	--
	-- On while the sound is being auditioned, because the lobby is where
	-- you spend time when you are not racing. TURN THIS OFF FOR RELEASE;
	-- it is a testing switch, not a design decision.
	CrowdEverywhere = true,

	-- TWO SIZES, AND THE SIZE IS THE SIZE OF THE MOMENT — not a coin
	-- flip. A trick you land every lap is small however spectacular it
	-- looks; a missile landing on the leader is big however quiet it was.
	CrowdCheerSmallId = "rbxassetid://126615573673174",
	CrowdCheerBigId = "rbxassetid://91750672024999",
	CrowdCheerVolume = 0.45,

	-- RATE-LIMITED, because a four-kart pile-up raises four events inside
	-- a second and four overlapping cheers is a klaxon. The first through
	-- wins and the rest are swallowed — which is also what a real crowd
	-- does, reacting once to a moment rather than once per participant.
	CrowdCheerCooldown = 1.6, -- seconds
	-- No crowd present, no cheering. Stops a cheer arriving over silence
	-- during the fade-in at the grid.
	CrowdCheerMinBed = 0.25,

	-- Two samples heard twenty times a race become two samples. A little
	-- variance keeps them reading as a crowd rather than as a button.
	CrowdCheerPitch = 1.0,
	CrowdCheerPitchVary = 0.06,

	--== HORN ==========================================================
	-- Pressed, not triggered. It is the one sound in the game the player
	-- makes on purpose for no mechanical reason, which is exactly why it
	-- is worth having.
	--
	-- Positional and RELAYED, because a horn only you can hear is a horn
	-- for nobody. Played instantly on the presser's own machine and
	-- rebroadcast to everyone else — so it never feels like it lagged for
	-- the one person guaranteed to notice, and it still arrives from the
	-- right direction for everybody else.
	HornSoundId = "rbxassetid://124292388545479",
	HornVolume = 0.7,
	HornRollOff = 190,
	-- Leaning on the key should be a horn, not a saw. The SERVER enforces
	-- its own, longer cooldown: a client-side one is a courtesy, not a
	-- defence, and this is a broadcast that a griefer would otherwise
	-- hold down.
	HornCooldown = 0.45,
	HornServerCooldown = 0.6,
	-- Face-top is Nitro on a controller; horn is intentionally non-driving
	-- and non-critical, so it lives on the lower D-pad instead.
	HornKeys = { Enum.KeyCode.H, Enum.KeyCode.DPadDown },
	HornPitchVary = 0.05, -- same reasoning as the cheers

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

	--== OTHER PEOPLE'S HITS ==========================================
	-- Every hit already reaches every client through the feed. It was
	-- carrying the news and not the noise: a race where four bots are
	-- battling behind you sounded like an empty track.
	--
	-- Played at the VICTIM's kart so it arrives from the right
	-- direction, and quieter than your own — a hit you can hear but did
	-- not feel should read as somebody else's problem.
	RemoteHitVolume = 0.55,
	RemoteHitRollOff = 220,
	-- Sounds are pooled. A busy lap is dozens of hits and creating an
	-- instance per bang is churn for something that lasts a second.
	RemoteHitVoices = 6,

	--== PROJECTILES ==================================================
	-- The thruster, looped on the missile itself while it flies. A
	-- missile you can hear coming is a missile you can react to, which
	-- is most of what makes one frightening rather than arbitrary.
	MissileThrustId = "rbxassetid://128535433880811",
	MissileThrustVolume = 0.6,
	MissileThrustRollOff = 180,

	-- IT GOES OFF WHEREVER IT ENDS, hit or not. A missile that detonates
	-- on a wall, expires, or passes under somebody who jumped it made no
	-- sound at all — so a successful dodge was silent, which is the one
	-- moment that most deserves a bang.
	ProjectileBoomVolume = 0.9,
	ProjectileBoomRollOff = 320,
	-- Quieter when it hit nobody. Still audible, still satisfying, but a
	-- miss should not sound the same as a kill.
	ProjectileMissScale = 0.7,

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

	--== INTERFACE (2D UI SFX) =========================================
	-- Non-positional menu/HUD cues, played through SoundService by the
	-- shared UiSound helper. One id per named cue so any screen can ask
	-- for "Click"/"Hover"/etc. by name without knowing the asset.
	UI = {
		Volume = 0.5,
		Click = "rbxassetid://88442833509532",
		Hover = "rbxassetid://139800881181209",
		Error = "rbxassetid://87519554692663",
		Equip = "rbxassetid://138323438407619",
		Unequip = "rbxassetid://81904985537003",
		Open = "rbxassetid://127877437691780",
		Close = "rbxassetid://74657965144290",
		Notification = "rbxassetid://105983221709653",
		QuestCollect = "rbxassetid://80977935658780",
	},
}
