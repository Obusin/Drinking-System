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

--=====================================================================
--  THE RACING LINE
--
--  Checkpoint nodes are corners of a polygon; a missile flying straight
--  between them cuts every bend, which on a real track means through the
--  scenery. A Catmull-Rom spline through the same nodes gives a smooth
--  curve that passes through all of them, which is the racing line.
--
--  Catmull-Rom specifically because it INTERPOLATES its control points
--  rather than being pulled near them — the curve goes through each
--  checkpoint exactly, which is what makes it a valid route rather than
--  an approximation of one.
--
--  `u` is a position along the route in node units and wraps: 3.5 is
--  halfway between node 3 and node 4, and it keeps counting past the
--  lap so laps stay comparable.
--=====================================================================

local function wrapNode(nodes: { Node }, i: number): Vector3
	return nodes[((i - 1) % #nodes) + 1].position
end

-- Position on the racing line at `u`.
function Route.pointAt(u: number): Vector3?
	local nodes = Route.nodes()
	local n = #nodes
	if n == 0 then
		return nil
	end
	if n < 4 then
		-- Too few points for a spline; straight lines are all the shape
		-- there is to describe.
		local i = math.floor(u)
		local t = u - i
		return wrapNode(nodes, i):Lerp(wrapNode(nodes, i + 1), t)
	end

	local i = math.floor(u)
	local t = u - i
	local p0, p1 = wrapNode(nodes, i - 1), wrapNode(nodes, i)
	local p2, p3 = wrapNode(nodes, i + 1), wrapNode(nodes, i + 2)

	local t2, t3 = t * t, t * t * t
	return 0.5
		* (
			2 * p1
			+ (-p0 + p2) * t
			+ (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
			+ (-p0 + 3 * p1 - 3 * p2 + p3) * t3
		)
end

-- Which way the road runs at `u`. Sampled rather than differentiated —
-- the exact derivative buys nothing here and this can't divide by zero.
function Route.tangentAt(u: number): Vector3?
	local a = Route.pointAt(u)
	local b = Route.pointAt(u + 0.02)
	if not (a and b) then
		return nil
	end
	local d = b - a
	return if d.Magnitude > 1e-4 then d.Unit else nil
end

-- How far apart the two nodes bracketing `u` are, so a speed in studs
-- can be converted into a step in node units. Without this a missile
-- crosses a short segment as slowly as a long one.
function Route.segmentLength(u: number): number
	local nodes = Route.nodes()
	if #nodes == 0 then
		return 0
	end
	local i = math.floor(u)
	return math.max((wrapNode(nodes, i + 1) - wrapNode(nodes, i)).Magnitude, 1)
end

return Route
