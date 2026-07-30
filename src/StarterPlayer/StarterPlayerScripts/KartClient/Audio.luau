--[[
	Audio — engine, drift charge notes, boost.

	The engine glides; the notes do not. That asymmetry is deliberate: a
	stepped engine sounds broken, and a musical note that slides sounds
	like a siren.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))

local A = Config.Audio

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

	return setmetatable({
		created = created,
		boost = boost,
		engine = engine,
		screech = screech,
		tick = tick,
		pickup = pickup,
		notes = notes,
		noteIndex = 0,
	}, Audio)
end

-- Rewinds on every call, which is what makes a rapid click read as
-- ticks instead of smearing into a buzz.
function Audio:PlayTick()
	if self.tick.SoundId ~= "" then
		self.tick:Play()
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
