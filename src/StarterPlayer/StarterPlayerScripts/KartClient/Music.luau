--[[
	Music — background tracks, and when they should be playing.

	CLIENT-SIDE AND 2D, DELIBERATELY
	--------------------------------
	Parented to SoundService rather than to a part, so it has no position
	and doesn't roll off. Music is not something happening in the world;
	it's something happening to the player.

	Client-side so it can be muted per person later without touching the
	server, and so a track starting has no bandwidth cost at all.

	THE PLAYLIST IS ALLOWED TO BE EMPTY
	-----------------------------------
	Nothing here breaks with no tracks — it simply stays silent. That
	matters because ids arrive later than the code that plays them, and a
	music system that errors until it's populated is a music system that
	gets commented out.

	WHY IT FOLLOWS THE MATCH
	------------------------
	A race and a lobby want different energy, and one track playing
	across both makes the lights going out feel like nothing happened.
	Racing gets the playlist; everything else gets the calmer lobby list
	if there is one, and silence if there isn't.

	Crossfades rather than cuts, because a hard switch on a phase change
	draws attention to the phase change rather than to the race.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Shared = require(BloxKart:WaitForChild("Match"))
local Util = require(BloxKart:WaitForChild("Util"))

local M = Config.Music
local P = Shared.Phase

local Music = {}
Music.__index = Music

-- Fisher-Yates over a copy. Shuffled ONCE per pass rather than picking
-- at random each time: random picking replays the same track back to
-- back often enough to be noticed, and being noticed is the one thing
-- background music must not be.
local function shuffled(list: { string }): { string }
	local out = table.clone(list)
	for i = #out, 2, -1 do
		local j = math.random(i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

function Music.new()
	local sound = Instance.new("Sound")
	sound.Name = "BloxKartMusic"
	sound.Looped = false
	sound.Volume = 0
	sound.Parent = SoundService

	local self = setmetatable({
		sound = sound,
		queue = {},
		list = nil, -- which playlist the queue was built from
		want = 0, -- volume we're heading toward
		playing = nil,
	}, Music)

	-- Advance on its own, so a playlist runs continuously without anything
	-- polling for the end of a track.
	sound.Ended:Connect(function()
		self:_next()
	end)

	return self
end

function Music:_listFor(phase: string?): { string }
	if phase == P.Racing or phase == P.Grid then
		return M.Race
	end
	return M.Lobby
end

function Music:_next()
	local list = self.list
	if not list or #list == 0 then
		self.sound:Stop()
		self.playing = nil
		return
	end
	if #self.queue == 0 then
		self.queue = shuffled(list)
		-- A one-track playlist would otherwise restart identically, which
		-- is fine; more than one and we avoid repeating the track that
		-- just finished across the shuffle boundary.
		if #self.queue > 1 and self.queue[1] == self.playing then
			self.queue[1], self.queue[#self.queue] = self.queue[#self.queue], self.queue[1]
		end
	end
	local id = table.remove(self.queue, 1)
	self.playing = id
	self.sound.SoundId = id
	self.sound.TimePosition = 0
	self.sound:Play()
end

-- Called every frame with the current match phase. Switching playlists
-- is a fade-out, a swap, and a fade-in — never a cut.
function Music:Update(dt: number, phase: string?)
	local list = self:_listFor(phase)

	if list ~= self.list then
		self.list = list
		table.clear(self.queue)
		-- Started from silence so the new list fades up rather than
		-- arriving at whatever volume the old one was at.
		self.want = if #list > 0 then M.Volume else 0
		self.sound.Volume = 0
		self:_next()
	end

	self.sound.Volume = Util.approach(self.sound.Volume, self.want, M.FadeRate, dt)
end

-- Ducked while something louder matters — a countdown, or results. Not
-- used yet; here because "turn the music down for a moment" is the first
-- thing anyone asks for once music exists, and it belongs with the
-- music rather than scattered through the caller.
function Music:Duck(on: boolean)
	self.want = if on then M.Volume * M.DuckShare else M.Volume
end

function Music:Destroy()
	self.sound:Destroy()
end

return Music
