--[[
	Crowd — stadium ambience, and cheers when something happens.

	Two jobs that sound like one thing:

	  the BED   a quiet, continuous murmur that says "there are people
	            watching". Never draws attention to itself; you should
	            only notice it when it stops.
	  the CHEER a reaction to a moment. Two sizes, so a routine trick and
	            somebody eating a missile are not the same event.

	Parented to SoundService rather than to a part, so there is no
	position and no falloff — a stadium surrounds you, and a crowd that
	pans as you steer reads as one man with a megaphone.

	PHASE-DRIVEN, like the music. Eased rather than cut: a crowd that
	appears the instant the grid loads draws attention to the phase
	change rather than to the race.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Shared = require(BloxKart:WaitForChild("Match"))
local Util = require(BloxKart:WaitForChild("Util"))

local A = Config.Audio
local P = Shared.Phase

local Crowd = {}
Crowd.__index = Crowd

-- Same diagnostic every other sound in this project carries. A SoundId
-- Roblox will not play is SILENT and says nothing, which looks exactly
-- like a wiring bug — and every custom id in this project so far has hit
-- exactly that. See BUGS #31.
local function check(sound: Sound, label: string)
	if sound.SoundId == "" then
		return
	end
	task.delay(5, function()
		if sound.Parent and not sound.IsLoaded then
			warn(("[Crowd] %s (%s) never loaded — Roblox will not play audio you do not own."):format(label, sound.SoundId))
		end
	end)
end

function Crowd.new()
	local created = {}
	local function make(props): Sound
		local sound = Instance.new("Sound")
		for k, v in props do
			sound[k] = v
		end
		sound.Parent = SoundService
		table.insert(created, sound)
		return sound
	end

	local bed = make({
		Name = "_CrowdBed",
		SoundId = A.CrowdBedId,
		Looped = true,
		Volume = 0,
	})
	if bed.SoundId ~= "" then
		bed:Play() -- held at 0 and faded, so it never starts mid-murmur
	end

	local self = setmetatable({
		created = created,
		bed = bed,
		-- TWO SIZES. Which one plays is the SIZE OF THE MOMENT, not a
		-- coin flip — see Cheer.
		small = make({ Name = "_CrowdCheerSmall", SoundId = A.CrowdCheerSmallId, Volume = A.CrowdCheerVolume }),
		big = make({ Name = "_CrowdCheerBig", SoundId = A.CrowdCheerBigId, Volume = A.CrowdCheerVolume }),
		level = 0,
		nextAt = 0,
	}, Crowd)

	check(bed, "crowd bed")
	check(self.small, "crowd cheer (small)")
	check(self.big, "crowd cheer (big)")
	return self
end

-- SOMETHING HAPPENED. `big` picks the larger crowd, and it should mean
-- "this mattered" rather than "this was loud" — a trick you land every
-- lap is small however spectacular it looks, a missile landing on the
-- leader is big however quiet it was.
--
-- RATE-LIMITED, because a four-kart pile-up raises four events inside a
-- second and four overlapping cheers is a klaxon. The first one through
-- wins and the rest are swallowed, which is also what a real crowd does
-- — it reacts once to a moment, not once per participant.
function Crowd:Cheer(big: boolean?)
	if self.level < A.CrowdCheerMinBed then
		return -- no crowd present to do the cheering
	end
	local now = os.clock()
	if now < (self.nextAt or 0) then
		return
	end
	local sound = if big then self.big else self.small
	if sound.SoundId == "" then
		return
	end
	self.nextAt = now + A.CrowdCheerCooldown
	-- PITCHED SLIGHTLY DIFFERENTLY EVERY TIME. Two samples heard twenty
	-- times a race become two samples; a little variance keeps them
	-- reading as a crowd rather than as a button.
	sound.PlaybackSpeed = A.CrowdCheerPitch + (math.random() * 2 - 1) * A.CrowdCheerPitchVary
	-- Scaled by how present the crowd is, so a cheer during the fade-in
	-- cannot arrive louder than the bed it belongs to.
	sound.Volume = A.CrowdCheerVolume * self.level
	sound:Play()
end

-- The bed follows the phase. Racing and the grid have a crowd; the lobby
-- does not, because you are not in the stadium yet.
function Crowd:Update(dt: number, phase: string?)
	local racing = phase == P.Racing or phase == P.Grid
	local want = if A.CrowdEverywhere or racing then 1 else 0
	self.level = Util.approach(self.level, want, A.CrowdFade, dt)
	self.bed.Volume = A.CrowdBedVolume * self.level
end

function Crowd:Destroy()
	for _, sound in self.created do
		sound:Destroy()
	end
	self.created = {}
end

return Crowd
