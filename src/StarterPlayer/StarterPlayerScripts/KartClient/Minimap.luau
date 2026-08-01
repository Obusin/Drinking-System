--[[
	Minimap — where everyone is, on the track the bots drive.

	The outline comes from `Route.nodes()`, which is the same ordered
	checkpoint chain the AI navigates by. That is the whole reason it is
	trustworthy: a map authored separately is a second answer to "where
	does the track go", and the two drift the first time a checkpoint
	moves.

	HOW IT IS DRAWN
	---------------
	Top-down. World (x, z) is projected into map space once, using a
	scale that fits the node bounding box into the frame. The track is
	then a chain of thin rotated Frames — the same trick as the speed
	streaks, and far cheaper than any kind of render.

	A LOOP DRAWS OVER ITSELF, and that is correct. The map is a plan
	view; a track that passes over itself occupies the same plan
	position twice. Trying to disambiguate it with height would produce a
	diagram nobody can read at 200 studs a second.

	TWO MODES, ONE OF THEM CURRENTLY REACHABLE
	------------------------------------------
	North-up holds the map still and turns your marker. Heading-up turns
	the map and holds your marker pointing forward. Both are implemented;
	`Config.Minimap.Mode` picks. It is a setting waiting for a settings
	menu, not an unfinished feature.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))
local Route = require(BloxKart:WaitForChild("Route"))
local Standings = require(BloxKart:WaitForChild("Standings"))
local Shared = require(BloxKart:WaitForChild("Match"))

local M = Config.Minimap

local Minimap = {}
Minimap.__index = Minimap

local function dot(parent: Instance, size: number, colour: Color3, order: number): Frame
	local d = Instance.new("Frame")
	d.BackgroundColor3 = colour
	d.BorderSizePixel = 0
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Size = UDim2.fromOffset(size, size)
	d.ZIndex = order
	d.Visible = false
	d.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = d
	return d
end

function Minimap.new()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartMinimap"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 3
	gui.Enabled = false -- until the track is found
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "Map"
	frame.BackgroundColor3 = M.BackgroundColor
	frame.BackgroundTransparency = M.BackgroundTransparency
	frame.BorderSizePixel = 0
	frame.AnchorPoint = M.Anchor
	frame.Position = M.Position
	frame.Size = UDim2.fromOffset(M.Size.X, M.Size.Y)
	-- So a rotated map in heading mode cannot spill across the screen.
	frame.ClipsDescendants = true
	frame.Parent = gui

	-- EVERYTHING THAT LIVES IN WORLD SPACE goes in here. Heading-up
	-- rotates this one frame and every segment and dot comes with it,
	-- which is why the two modes are the same code with one number
	-- different.
	local world = Instance.new("Frame")
	world.Name = "World"
	world.BackgroundTransparency = 1
	world.AnchorPoint = Vector2.new(0.5, 0.5)
	world.Position = UDim2.fromScale(0.5, 0.5)
	world.Size = UDim2.fromScale(1, 1)
	world.Parent = frame

	return setmetatable({
		gui = gui,
		frame = frame,
		world = world,
		built = false,
		origin = Vector3.zero,
		scale = 1,
		markers = {}, -- kart -> Frame
		self_ = nil,
	}, Minimap)
end

--=====================================================================
--  BUILD  (once, when the track exists)
--=====================================================================
function Minimap:_build(): boolean
	local nodes = Route.nodes()
	if #nodes < 2 then
		return false
	end

	----------------------------------------------------------------
	-- Fit the whole track into the frame.
	----------------------------------------------------------------
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for _, n in nodes do
		minX = math.min(minX, n.position.X)
		maxX = math.max(maxX, n.position.X)
		minZ = math.min(minZ, n.position.Z)
		maxZ = math.max(maxZ, n.position.Z)
	end

	self.origin = Vector3.new((minX + maxX) * 0.5, 0, (minZ + maxZ) * 0.5)
	local spanX = math.max(maxX - minX, 1)
	local spanZ = math.max(maxZ - minZ, 1)
	-- ONE scale for both axes, never two. Separate scales would stretch
	-- the track to fill the box and every corner would be the wrong
	-- shape, which is worse than a map with empty space in it.
	local usable = (1 - M.Padding * 2)
	self.scale = math.min(M.Size.X * usable / spanX, M.Size.Y * usable / spanZ)

	----------------------------------------------------------------
	-- The outline, as a chain of segments.
	----------------------------------------------------------------
	for i = 1, #nodes do
		local a = self:_project(nodes[i].position)
		-- Wraps: the last node joins the first, because a lap is a loop
		-- and a map with a gap at the start line reads as a broken track.
		local b = self:_project(nodes[i % #nodes + 1].position)

		local delta = b - a
		local length = delta.Magnitude
		if length > 0.5 then
			local seg = Instance.new("Frame")
			seg.Name = "Seg" .. i
			seg.BackgroundColor3 = M.TrackColor
			seg.BorderSizePixel = 0
			seg.AnchorPoint = Vector2.new(0.5, 0.5)
			seg.Position = UDim2.new(0.5, (a.X + b.X) * 0.5, 0.5, (a.Y + b.Y) * 0.5)
			seg.Size = UDim2.fromOffset(M.TrackThickness, length + M.SegmentOverlap)
			-- A Frame's long axis is vertical, so it is turned to lie
			-- along the segment.
			seg.Rotation = math.deg(math.atan2(delta.Y, delta.X)) + 90
			seg.ZIndex = 1
			seg.Parent = self.world
		end
	end

	local start = self:_project(nodes[1].position)
	local flag = dot(self.world, M.StartSize, M.StartColor, 2)
	flag.Position = UDim2.new(0.5, start.X, 0.5, start.Y)
	flag.Visible = true

	self.built = true
	self.gui.Enabled = true
	return true
end

-- World position -> pixels from the centre of the map. Y of the world
-- is dropped: this is a plan view.
function Minimap:_project(pos: Vector3): Vector2
	return Vector2.new((pos.X - self.origin.X) * self.scale, (pos.Z - self.origin.Z) * self.scale)
end

--=====================================================================
--  UPDATE
--=====================================================================
function Minimap:Update(sim)
	if not M.Enabled then
		return
	end
	if not self.built and not self:_build() then
		return -- no track yet; try again next frame
	end

	----------------------------------------------------------------
	-- Heading-up turns the world; north-up leaves it alone.
	----------------------------------------------------------------
	local heading = 0
	if sim and sim.forward then
		-- Screen y grows downward and world z grows "south", which
		-- cancel — so this is the same atan2 the segments use.
		heading = math.deg(math.atan2(sim.forward.Z, sim.forward.X)) + 90
	end
	self.world.Rotation = if M.Mode == "heading" then -heading else 0

	----------------------------------------------------------------
	-- Racers
	----------------------------------------------------------------
	local me = Players.LocalPlayer.UserId
	local seen = {}

	for _, kart in Standings.allKarts() do
		local hitbox = kart.PrimaryPart
		if not hitbox then
			continue
		end
		seen[kart] = true

		local mine = kart:GetAttribute(Names.OWNER) == me
		local marker = self.markers[kart]
		if not marker then
			marker = dot(self.world, if mine then M.SelfSize else M.RacerSize, if mine then M.SelfColor else M.RacerColor, if mine then 5 else 4)
			self.markers[kart] = marker
		end

		local p = self:_project(hitbox.Position)
		marker.Position = UDim2.new(0.5, p.X, 0.5, p.Y)
		marker.Visible = true
		-- Dimmed once they have finished: the AI is still driving them
		-- around for a few seconds and they are still in the way, so
		-- hiding them would be a lie.
		marker.BackgroundTransparency = if kart:GetAttribute(Shared.FINISH_PLACE) then M.FinishedTransparency else 0
	end

	-- Karts that have left the world. Destroyed rather than hidden,
	-- because a retired kart never comes back and a hidden marker per
	-- retirement accumulates for the life of the server.
	for kart, marker in self.markers do
		if not seen[kart] then
			marker:Destroy()
			self.markers[kart] = nil
		end
	end
end

function Minimap:Destroy()
	self.gui:Destroy()
end

return Minimap
