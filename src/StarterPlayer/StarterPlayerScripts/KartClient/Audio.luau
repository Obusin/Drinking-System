--[[
	Audio — engine, drift charge notes, boost.

	The engine glides; the notes do not. That asymmetry is deliberate: a
	stepped engine sounds broken, and a musical note that slides sounds
	like a siren.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))

local A = Config.Audio
local SW = Config.Swim

local Audio = {}
Audio.__index = Audio

function Audio.new(hitbox: BasePart)
	local created = {}
	local function make(props)
		local inst = Instance.new("Sound")
		for k, v in props do
			inst[k] = v
		end
		inst.Parent = hitbox
		table.insert(created, inst)
		return inst
	end

	local splash = make({
		SoundId = SW.SplashSoundId,
		Volume = SW.SplashVolume,
		RollOffMaxDistance = 220,
	})

	-- Ramps and water skips share one sound, pitched by size. See
	-- Audio:Leap.
	local leap = make({
		Name = "_Leap",
		SoundId = A.LeapSoundId,
		Volume = A.LeapSoundVolume,
		RollOffMaxDistance = 200,
	})

	-- Parented to the hitbox like everything else here, so it is
	-- positional and falls off with distance for free.
	local horn = make({
		Name = "_Horn",
		SoundId = A.HornSoundId,
		Volume = A.HornVolume,
		RollOffMaxDistance = A.HornRollOff,
	})

	local boost = make({
		Name = "_BoostSound",
		SoundId = A.BoostSoundId,
		Volume = A.BoostSoundVolume,
		PlaybackSpeed = A.BoostSoundPitch,
		RollOffMaxDistance = 200,
	})

	-- Runs for as long as you're in the kart; pitch tracks speed.
	local engine = make({
		Name = "_Engine",
		SoundId = A.EngineSoundId,
		Looped = true,
		Volume = A.EngineVolume,
		PlaybackSpeed = A.EngineIdlePitch,
		RollOffMaxDistance = 180,
	})
	if engine.SoundId ~= "" then
		engine:Play()
	end

	-- Tyres. Held at volume 0 rather than started and stopped, so it
	-- swells and fades instead of clicking in at the top of a loop.
	local screech = make({
		Name = "_Screech",
		SoundId = A.ScreechId,
		Looped = true,
		Volume = 0,
		PlaybackSpeed = A.ScreechPitchLow,
		RollOffMaxDistance = 170,
	})
	if screech.SoundId ~= "" then
		screech:Play()
	end

	local tick = make({
		Name = "_RouletteTick",
		SoundId = A.RouletteTickId,
		Volume = A.RouletteTickVolume,
		RollOffMaxDistance = 60,
	})

	local pickup = make({
		Name = "_Pickup",
		SoundId = A.PickupSoundId,
		Volume = A.PickupVolume,
		RollOffMaxDistance = 120,
	})

	-- Voice pool for the charge notes. A Sound restarts rather than
	-- layers when you Play() it again, so overlapping needs one instance
	-- per simultaneous voice.
	local notes = {}
	for i = 1, A.TierNoteVoices do
		table.insert(
			notes,
			make({
				Name = "_TierNote" .. i,
				SoundId = A.TierNoteId,
				Volume = A.TierNoteVolume,
				RollOffMaxDistance = 180,
			})
		)
	end

	-- Being hit. One generic thump for the spin, plus an optional
	-- per-item layer on top; see Audio:PlayHit.
	local hit = make({
		Name = "_Hit",
		SoundId = A.HitSoundId,
		Volume = A.HitSoundVolume,
		RollOffMaxDistance = 220,
	})
	-- SoundId is set at play time, because it depends on which item
	-- landed. One instance rather than one per item: only one hit can be
	-- arriving at a time, and swapping the id is free.
	local itemHit = make({
		Name = "_ItemHit",
		Volume = A.ItemHitVolume,
		RollOffMaxDistance = 260,
	})

	-- Bumping a wall. Its pitch is set at play time from how square the
	-- impact was, so one instance covers every severity.
	local bump = make({
		Name = "_Bump",
		SoundId = A.BumpSoundId,
		Volume = A.BumpSoundVolume,
		RollOffMaxDistance = 200,
	})

	-- The countdown is deliberately 2D and local. A shared world speaker
	-- would make every kart announce the same light and multiply the voice
	-- for nearby players. Roblox's AudioTextToSpeech connects directly to
	-- this client's output instead.
	local countdownSpeech: AudioTextToSpeech? = nil
	if A.CountdownTTS then
		local ok, speech = pcall(function()
			local output = Instance.new("AudioDeviceOutput")
			output.Name = "_CountdownVoiceOutput"
			output.Player = Players.LocalPlayer
			output.Parent = SoundService

			local tts = Instance.new("AudioTextToSpeech")
			tts.Name = "_CountdownVoice"
			tts.VoiceId = A.CountdownTTSVoiceId
			tts.Volume = A.CountdownTTSVolume
			tts.Parent = SoundService

			local wire = Instance.new("Wire")
			wire.Name = "_CountdownVoiceWire"
			wire.SourceInstance = tts
			wire.TargetInstance = output
			wire.Parent = SoundService

			table.insert(created, output)
			table.insert(created, tts)
			table.insert(created, wire)
			return tts
		end)
		if ok then
			countdownSpeech = speech
		else
			warn("[Audio] Roblox TTS countdown unavailable; keeping countdown beeps.")
		end
	end
	local self = setmetatable({
		created = created,
		bump = bump,
		boost = boost,
		splash = splash,
		leap = leap,
		horn = horn,
		engine = engine,
		screech = screech,
		tick = tick,
		pickup = pickup,
		hit = hit,
		itemHit = itemHit,
		notes = notes,
		noteIndex = 0,
		countdownSpeech = countdownSpeech,
	}, Audio)

	self:_checkSound(splash, "Swim splash")
	self:_checkSound(leap, "Leap")
	self:_checkSound(horn, "Horn")

	return self
end

-- Rewinds on every call, which is what makes a rapid click read as
-- ticks instead of smearing into a buzz.
function Audio:PlayTick()
	if self.tick.SoundId ~= "" then
		self.tick:Play()
	end
end

-- Speaks a single race light through Roblox's native 2D TTS graph. The
-- system can be unavailable on an older client or fail moderation/loading;
-- that must never block the round, so the normal countdown cue still plays.
function Audio:CountdownVoice(light: number)
	local speech = self.countdownSpeech
	if not speech then
		return
	end

	local phrase = if light <= 0 then "Go!" else tostring(light)
	local ok, err = pcall(function()
		speech.Text = phrase
		speech.TimePosition = 0
		speech:Play()
	end)
	if not ok then
		warn(string.format("[Audio] Roblox TTS countdown failed for %q: %s", phrase, tostring(err)))
	end
end

-- Something landed on you. `itemId` is optional and only decides
-- whether a second, item-specific layer plays over the top.
--
-- Two sounds rather than one lookup with a fallback: the thump is what
-- being spun FEELS like and should be identical every time, while the
-- item layer is what tells you WHAT hit you. Replacing the first with
-- the second would make a missile and a banana feel like different
-- amounts of trouble when they are the same amount.
-- BUMP. `square` is how head-on the impact was (0..1), straight from
-- Simulation's `bounced` event.
--
-- Pitched DOWN as it gets squarer: a heavier sound for a heavier hit is
-- the whole reason this is not a single fixed sample.
function Audio:PlayBump(square: number)
	if self.bump.SoundId == "" then
		return
	end
	local t = math.clamp(square, 0, 1)
	self.bump.PlaybackSpeed = A.BumpPitchLow + (A.BumpPitchHigh - A.BumpPitchLow) * t
	self.bump:Play()
end

function Audio:PlayHit(itemId: string?)
	if self.hit.SoundId ~= "" then
		self.hit:Play()
	end
	local layer = itemId and A.ItemHitIds[itemId]
	if layer and layer ~= "" then
		self.itemHit.SoundId = layer
		self.itemHit:Play()
	end
end

function Audio:PlayPickup()
	if self.pickup.SoundId ~= "" then
		self.pickup:Play()
	end
end

-- Fresh from the start, at this tier's pitch, over the top of whatever
-- is still ringing — no glide, no crossfade.
function Audio:PlayTierNote(tier: number)
	local pool = self.notes
	if #pool == 0 or pool[1].SoundId == "" then
		return
	end
	self.noteIndex = (self.noteIndex % #pool) + 1
	local voice = pool[self.noteIndex]
	voice.PlaybackSpeed = A.TierNotePitches[math.clamp(tier + 1, 1, #A.TierNotePitches)]
	voice.TimePosition = 0
	voice:Play() -- Play() rewinds, so this is always from scratch
end

-- Scaled by how hard the landing was, so a gentle touchdown is a lap
-- and a real drop is a crash. One sound, two readings.
-- Same diagnostic as Rider's: a SoundId Roblox will not play is silent
-- and says nothing, which looks exactly like a wiring bug.
function Audio:_checkSound(sound: Sound, label: string)
	if not sound or sound.SoundId == "" then
		return
	end
	task.delay(5, function()
		if sound.Parent and not sound.IsLoaded then
			warn(("[Audio] %s (%s) never loaded — Roblox will not play audio you do not own."):format(label, sound.SoundId))
		end
	end)
end

function Audio:Splash(impact: number)
	if not self.splash or self.splash.SoundId == "" then
		return
	end
	local hard = math.clamp(impact / 40, 0, 1)
	self.splash.Volume = SW.SplashVolume * (0.45 + 0.55 * hard)
	self.splash.PlaybackSpeed = SW.SplashPitchMax - (SW.SplashPitchMax - SW.SplashPitchMin) * hard
	self.splash:Play()
end

-- LEAVING THE GROUND — a ramp launch, or a skip off a wave.
--
-- One sound for all of them, pitched by size. `size` is 0..1: 0 is the
-- smallest leap worth hearing, 1 is a full ramp launch. Higher pitch for
-- a small one, because pitch reads as MASS — a little skip should sound
-- light and a ramp launch should not.
--
-- `quiet` scales the volume, and it is what keeps the water hop from
-- becoming a machine gun: it fires up to 2.89 times a second at top
-- speed, where a ramp fires once.
function Audio:Leap(size: number, quiet: number?)
	if not self.leap or self.leap.SoundId == "" then
		return
	end
	local big = math.clamp(size, 0, 1)
	self.leap.Volume = A.LeapSoundVolume * (quiet or 1)
	self.leap.PlaybackSpeed = A.LeapPitchLow - (A.LeapPitchLow - A.LeapPitchHigh) * big
	self.leap:Play()
end

-- THE HORN. Cosmetic, player-pressed, and the only sound in the game
-- made on purpose for no mechanical reason.
--
-- Returns whether it actually sounded, so the caller knows whether to
-- spend a network message. The cooldown lives here rather than at the
-- key binding because holding the key, tapping it and a gamepad's repeat
-- all arrive differently and only one of them should have to be right.
function Audio:Horn(): boolean
	if not self.horn or self.horn.SoundId == "" then
		return false
	end
	local now = os.clock()
	if now < (self.hornAt or 0) then
		return false
	end
	self.hornAt = now + A.HornCooldown
	self.horn.PlaybackSpeed = 1 + (math.random() * 2 - 1) * A.HornPitchVary
	self.horn:Play()
	return true
end

function Audio:Boost(tier: number)
	if self.boost.SoundId == "" then
		return
	end
	self.boost.PlaybackSpeed = A.BoostSoundPitch + tier * A.BoostPitchPerTier
	self.boost:Play()
end

function Audio:Update(dt: number, sim)
	----------------------------------------------------------------
	-- Engine — pitch tracks speed.
	----------------------------------------------------------------
	local engine = self.engine
	if engine.SoundId ~= "" then
		local revs = A.EngineIdlePitch + (A.EngineMaxPitch - A.EngineIdlePitch) * sim.speedFrac
		if sim.boosting then
			revs = math.max(revs, A.EngineBoostPitch)
		end
		engine.PlaybackSpeed = Util.approach(engine.PlaybackSpeed, revs, A.EnginePitchRate, dt)
	end

	----------------------------------------------------------------
	-- Tyres — volume and pitch both ride the real slip angle, so the
	-- screech grows out of hard cornering rather than switching on with
	-- the drift. Silent in the air and below a walking pace.
	----------------------------------------------------------------
	local screech = self.screech
	if screech.SoundId == "" then
		return
	end

	-- `tyreLoad`, not `slip`: tyre EFFORT rather than slide angle, so
	-- counter-steering to catch a drift stays loud instead of going
	-- silent. See Simulation for why those two differ.
	local howling = 0
	if sim.grounded and math.abs(sim.speed) > A.ScreechSpeedFloor and sim.tyreLoad > A.ScreechMinSlip then
		-- Remap above the threshold onto a full 0..1, so the sound opens
		-- from silence at the threshold instead of jumping in.
		howling = math.clamp((sim.tyreLoad - A.ScreechMinSlip) / (1 - A.ScreechMinSlip), 0, 1)
	end

	screech.Volume = Util.approach(screech.Volume, A.ScreechVolume * howling, A.ScreechFade, dt)
	local pitch = A.ScreechPitchLow + (A.ScreechPitchHigh - A.ScreechPitchLow) * howling
	screech.PlaybackSpeed = Util.approach(screech.PlaybackSpeed, pitch, A.ScreechPitchRate, dt)
end

function Audio:Destroy()
	for _, inst in self.created do
		inst:Destroy()
	end
	table.clear(self.created)
end

return Audio
