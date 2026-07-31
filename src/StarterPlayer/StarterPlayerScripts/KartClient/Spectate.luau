--[[
	Spectate — watch the rest of the race after you've finished.

	WHY IT HAS TO EXIST
	-------------------
	Crossing the line used to leave you sitting in a kart the AI is now
	driving, staring at your own bonnet while the race you care about
	happens somewhere else. The last thirty seconds of a round are the
	most interesting part of it and the person who won was the only one
	who couldn't watch.

	WHAT IT WATCHES
	---------------
	Anyone still racing, cheapest first: a kart with no finish place is
	still fighting for one. Cycle through them; when the last of them
	finishes there is nothing left to watch and it falls back to whoever
	is nearest the front.

	It never follows YOUR kart. That is not spectating, that is the game
	you were already playing, and your kart is being driven by the AI now
	anyway.

	CAMERA OWNERSHIP
	----------------
	This takes the camera outright while active, and gives it back
	untouched when it stops. It deliberately does not go through
	CameraRig: that one is built around a Simulation it can read every
	frame, and a kart somebody else is driving gives us nothing but a
	CFrame. Chasing that CFrame is a different job with a different
	failure mode, so it is a different module.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))
local Shared = require(BloxKart:WaitForChild("Match"))
local Standings = require(BloxKart:WaitForChild("Standings"))

local SP = Config.Spectate
local P = Shared.Phase

local Spectate = {}
Spectate.__index = Spectate

function Spectate.new()
	return setmetatable({
		active = false,
		target = nil :: Model?,
		index = 0,
		pos = nil :: Vector3?, -- smoothed camera position
		saved = nil :: Enum.CameraType?,
	}, Spectate)
end

-- Everyone worth watching: still racing, not us, and real.
local function candidates(): { Model }
	local out = {}
	for _, kart in Standings.allKarts() do
		if kart:GetAttribute(Names.OWNER) == Players.LocalPlayer.UserId then
			continue
		end
		if kart:GetAttribute(Shared.FINISH_PLACE) then
			continue -- already home; nothing left to watch them do
		end
		table.insert(out, kart)
	end
	-- Leaders first, so the default view is the race for the lead rather
	-- than whoever happens to be first in the tag list.
	table.sort(out, function(a, b)
		return (a:GetAttribute(Standings.ATTRIBUTE) or 0) > (b:GetAttribute(Standings.ATTRIBUTE) or 0)
	end)
	return out
end

function Spectate:_pick(step: number)
	local list = candidates()
	if #list == 0 then
		self.target = nil
		return
	end
	self.index = (self.index + step - 1) % #list + 1
	self.target = list[self.index]
	-- Jump rather than sweep across the map when switching subject.
	self.pos = nil
end

function Spectate:Next()
	if self.active then
		self:_pick(1)
	end
end

function Spectate:Prev()
	if self.active then
		self:_pick(-1)
	end
end

function Spectate:_start()
	self.active = true
	local cam = workspace.CurrentCamera
	if cam then
		self.saved = cam.CameraType
		cam.CameraType = Enum.CameraType.Scriptable
	end
	self.index = 0
	self:_pick(1)
end

function Spectate:_stop()
	self.active = false
	self.target = nil
	self.pos = nil
	local cam = workspace.CurrentCamera
	if cam and self.saved then
		cam.CameraType = self.saved
		self.saved = nil
	end
end

-- `finished` is whether OUR kart has crossed the line this round.
function Spectate:Update(dt: number, phase: string?, finished: boolean)
	-- Only during a race we're out of. Results has its own board and the
	-- lobby has nothing to look at.
	local want = finished and phase == P.Racing
	if want ~= self.active then
		if want then
			self:_start()
		else
			self:_stop()
		end
	end
	if not self.active then
		return
	end

	-- The one we're on may have finished, been destroyed, or the field
	-- may have emptied since last frame.
	if not (self.target and self.target.Parent and not self.target:GetAttribute(Shared.FINISH_PLACE)) then
		self:_pick(1)
	end
	local kart = self.target
	local cam = workspace.CurrentCamera
	if not (kart and cam) then
		return
	end
	local hitbox = kart.PrimaryPart
	if not hitbox then
		return
	end

	-- A plain chase: behind and above, looking at the kart. Deliberately
	-- simple — a spectator camera that tries to be clever about corners
	-- is a spectator camera that loses the subject.
	local cf = hitbox.CFrame
	local want3 = cf.Position - cf.LookVector * SP.Distance + Vector3.yAxis * SP.Height

	-- Smoothed so replication steps don't jitter the view. Nil on a
	-- switch, so changing subject cuts instead of flying across the map.
	self.pos = if self.pos then self.pos:Lerp(want3, math.min(SP.Follow * dt, 1)) else want3
	cam.CFrame = CFrame.lookAt(self.pos, cf.Position + Vector3.yAxis * SP.LookHeight)
end

-- Who we're watching, for the HUD. Nil when not spectating.
function Spectate:TargetName(): string?
	if not (self.active and self.target) then
		return nil
	end
	local id = self.target:GetAttribute(Names.OWNER)
	local player = id and Players:GetPlayerByUserId(id)
	if player then
		return player.DisplayName
	end
	local named = self.target:GetAttribute(Names.RACER_NAME)
	return if typeof(named) == "string" and named ~= "" then named else "Racer"
end

function Spectate:Destroy()
	self:_stop()
end

return Spectate
