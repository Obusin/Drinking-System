--[[
	Route — the track as an ordered list of waypoints.

	Checkpoints already describe the racing line: they're placed round the
	lap, in order, pointing down the track. Anything that needs to know
	"where does the track go from here" can read them rather than having a
	second set of nodes placed by hand.

	Used by:
	  Race (client)              lap validation and wrong-way
	  ProjectileService (server) missiles following the road round corners

	Shared because `orderOf` living in two places is how the two ends
	quietly start disagreeing about what order a checkpoint is.

	NODES, NOT PARTS
	----------------
	One node per distinct Order, because several parts may share an order
	— a wide gate built from two slabs, say. The node's position is the
	average of its parts, so a two-part gate aims at the middle of the
	road rather than at one edge of it.
--]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("BloxKart"):WaitForChild("Config"))

local R = Config.Race

local Route = {}

export type Node = {
	order: number,
	position: Vector3,
	parts: { BasePart },
}

-- Order attribute first, trailing digits in the name as a fallback, so
-- `Checkpoint3` works with nothing configured.
function Route.orderOf(part: BasePart): number
	local attr = part:GetAttribute(R.CheckpointOrderAttribute)
	if typeof(attr) == "number" then
		return attr
	end
	return tonumber(part.Name:match("(%d+)$") or "") or 0
end

--=====================================================================
--  NODES
--
--  Cached: a missile in flight wants this every frame, and rebuilding
--  it means a tag query plus two tables. Invalidated on tagged-part
--  count, which is the only realistic runtime change.
--=====================================================================
local cache: { Node }? = nil
local cachedCount = -1

function Route.nodes(): { Node }
	local parts = CollectionService:GetTagged(R.CheckpointTag)
	if cache and cachedCount == #parts then
		return cache
	end

	local byOrder: { [number]: { BasePart } } = {}
	local orders = {}
	for _, part in parts do
		if part:IsA("BasePart") then
			local o = Route.orderOf(part)
			if not byOrder[o] then
				byOrder[o] = {}
				table.insert(orders, o)
			end
			table.insert(byOrder[o], part)
		end
	end
	table.sort(orders)

	local nodes: { Node } = {}
	for _, o in orders do
		local group = byOrder[o]
		local sum = Vector3.zero
		for _, part in group do
			sum += part.Position
		end
		table.insert(nodes, {
			order = o,
			position = sum / #group,
			parts = group,
		})
	end

	cache = nodes
	cachedCount = #parts
	return nodes
end

--=====================================================================
--  PROGRESS
--=====================================================================

-- How many checkpoints a racer has banked this lap, decoded out of the
-- single Standings score. See Standings for the encoding — this is the
-- only place that unpacks it, so the two stay together.
function Route.passedFrom(score: number?): number
	if typeof(score) ~= "number" then
		return 0
	end
	return math.floor((score % 1e6) / 1e3)
end

-- ABSOLUTE route position: how many checkpoints deep into the RACE,
-- laps included. This is what lets two racers be compared as "ahead" or
-- "behind" along the track rather than by straight-line distance.
--
-- A wrapped 1..count index can't do that — index 1 is both the start of
-- the race and the start of lap 3, so a target that has just lapped you
-- would compare as being behind.
function Route.absoluteOf(score: number?, count: number): number
	if count <= 0 then
		return 0
	end
	local s = if typeof(score) == "number" then score else 0
	local laps = math.floor(s / 1e6)
	return laps * count + Route.passedFrom(s)
end

-- The node at an absolute index, wrapping round the lap. Absolute
-- indices grow forever; there are only `count` nodes.
function Route.nodeAt(nodes: { Node }, abs: number): Node?
	if #nodes == 0 then
		return nil
	end
	return nodes[((abs - 1) % #nodes) + 1]
end

return Route
