--[[
	RemoteAudio — engine and tyres for everyone ELSE'S kart.

	WHY THIS EXISTS
	---------------
	Audio.new builds its Sound instances on the client, parented to the
	local kart. Instances created on a client never replicate, so every
	engine note and tyre screech in the game was audible to exactly one
	person: the driver. A race sounded like driving alone, because as far
	as your speakers were concerned you were.

	NO NEW REPLICATION, ON PURPOSE
	------------------------------
	The obvious fix is for each kart to publish "am I drifting" and "how
	fast am I going" as attributes. That's a replication event per kart
	per frame for something nobody would notice being slightly wrong, and
	SetAttribute traffic is the thing this codebase is careful about
	everywhere else.

	It isn't needed. Both quantities are already visible in the one thing
	that DOES replicate — where the kart is:

	    speed   how far it moved since last frame
	    slip    the angle between the way it moved and the way it faces

	That second one is not an approximation of drifting, it IS drifting.
	A kart travelling sideways to its nose is sliding, by definition, and
	it's the same quantity the local screech follows.

	It also works for bots for free. Their karts are anchored and
	server-driven, so AssemblyLinearVelocity reads zero on them — a
	velocity-based version would have left every bot silent. Position
	delta doesn't care what moved the part.

	WHAT IT DELIBERATELY DOESN'T DO
	-------------------------------
	No one-shots — no hits, no pickups, no boosts. Those are events, and
	events need to be told to you rather than inferred from a position;
	guessing at them from motion would fire them wrongly. This is the
	continuous bed of a race happening around you, and nothing else.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))
local Util = require(BloxKart:WaitForChild("Util"))

local A = Config.Audio
local H = Config.Handling

local RemoteAudio = {}

type Voice = {
	engine: Sound,
	screech: Sound,
	last: Vector3,
	speed: number,
	slip: number,
}

local voices: { [BasePart]: Voice } = {}

local function isOurs(kart: Model): boolean
	return kart:GetAttribute(Names.OWNER) == Players.LocalPlayer.UserId
end

local function newVoice(hitbox: BasePart): Voice
	local function make(id: string, volume: number, looped: boolean): Sound
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Looped = looped
		s.Volume = 0
		-- Rolls off with distance, which is what makes a pack sound like a
		-- pack: the kart alongside you is loud and the one a corner back
		-- is a hint.
		s.RollOffMaxDistance = A.RemoteRollOff
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.Parent = hitbox
		if id ~= "" and looped then
			s:Play()
		end
		return s
	end

	return {
		engine = make(A.EngineSoundId, A.EngineVolume, true),
		screech = make(A.ScreechId, A.ScreechVolume, true),
		last = hitbox.Position,
		speed = 0,
		slip = 0,
	}
end

local function drop(hitbox: BasePart)
	local v = voices[hitbox]
	if not v then
		return
	end
	v.engine:Destroy()
	v.screech:Destroy()
	voices[hitbox] = nil
end

local function step(dt: number)
	if dt <= 0 then
		return
	end

	local seen = {}

	for _, kart in CollectionService:GetTagged("Kart") do
		local hitbox = kart.PrimaryPart
		-- Our own kart already has a full Audio of its own, driven by the
		-- simulation rather than guessed at from motion. Doubling it would
		-- be two engines slightly out of phase.
		if not hitbox or not kart.Parent or isOurs(kart) then
			continue
		end
		seen[hitbox] = true

		local v = voices[hitbox]
		if not v then
			voices[hitbox] = newVoice(hitbox)
			continue -- one frame to establish a previous position
		end

		----------------------------------------------------------------
		-- Everything, from where it moved.
		----------------------------------------------------------------
		local moved = hitbox.Position - v.last
		v.last = hitbox.Position

		-- Smoothed, because replication arrives in steps: the raw frame
		-- delta is zero on frames with no update and double on the frame
		-- after, which would make every remote engine warble.
		local raw = moved.Magnitude / dt
		v.speed = Util.approach(v.speed, raw, A.RemoteSmoothing, dt)

		-- SLIP: the angle between where it went and where it points. A
		-- kart moving sideways to its nose is sliding, which is the whole
		-- definition of a drift.
		local rawSlip = 0
		if moved.Magnitude > 1e-3 and v.speed > A.ScreechSpeedFloor then
			local dir = moved.Unit
			local facing = hitbox.CFrame.LookVector
			-- Flattened against the kart's own up so a hill isn't slip.
			local up = hitbox.CFrame.UpVector
			dir -= up * dir:Dot(up)
			facing -= up * facing:Dot(up)
			if dir.Magnitude > 1e-3 and facing.Magnitude > 1e-3 then
				local cos = math.clamp(dir.Unit:Dot(facing.Unit), -1, 1)
				rawSlip = math.clamp(math.deg(math.acos(cos)) / H.MaxSlip, 0, 1)
			end
		end
		v.slip = Util.approach(v.slip, rawSlip, A.ScreechFade, dt)

		----------------------------------------------------------------
		-- Drive the sounds.
		----------------------------------------------------------------
		local frac = math.clamp(v.speed / H.MaxSpeed, 0, 1)
		if v.engine.SoundId ~= "" then
			v.engine.Volume = A.EngineVolume * A.RemoteEngineShare
			v.engine.PlaybackSpeed = A.EngineIdlePitch + (A.EngineMaxPitch - A.EngineIdlePitch) * frac
		end

		if v.screech.SoundId ~= "" then
			local over = math.max(v.slip - A.ScreechMinSlip, 0) / math.max(1 - A.ScreechMinSlip, 1e-3)
			v.screech.Volume = over * A.ScreechVolume * A.RemoteScreechShare
			v.screech.PlaybackSpeed = A.ScreechPitchLow + (A.ScreechPitchHigh - A.ScreechPitchLow) * over
		end
	end

	-- Karts that went away, and karts that became ours.
	for hitbox in voices do
		if not seen[hitbox] or not hitbox.Parent then
			drop(hitbox)
		end
	end
end

function RemoteAudio.start()
	if not A.RemoteEnabled then
		return
	end
	CollectionService:GetInstanceRemovedSignal("Kart"):Connect(function(kart)
		for hitbox in voices do
			if not hitbox.Parent or hitbox:IsDescendantOf(kart) then
				drop(hitbox)
			end
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return RemoteAudio
