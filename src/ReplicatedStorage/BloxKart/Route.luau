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

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Triggers = require(BloxKart:WaitForChild("Triggers"))

local R = Config.Race

local Route = {}

export type Node = {
	order: number,
	position: Vector3,
	parts: { BasePart },
	-- Studs of ROAD either side of the centreline here, felt for with
	-- rays rather than read off the checkpoint volume — gates routinely
	-- overhang the tarmac, and a confident wrong answer to "may I drive
	-- here" is worse than no answer.
	--
	-- Separate sides because a checkpoint is rarely centred on its road.
	-- halfWidth is the narrower of the two, for callers that only want
	-- one number.
	leftWidth: number,
	rightWidth: number,
	halfWidth: number,
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

-- A checkpoint's CENTRE is not where the road is.
--
-- A gate volume is usually a tall slab spanning the track, so its middle
-- floats several studs above the tarmac. Taken literally, the racing
-- line built from those centres hangs in the air — which tilts every
-- tangent, so anything measuring how much the road bends reads a
-- permanent corner. Bots brake for it and crawl; missiles cruise at the
-- wrong height.
--
-- So each node is dropped onto whatever is beneath it. Along the PART's
-- own up rather than world down, so this still works on a loop.
local dropParams = RaycastParams.new()
dropParams.FilterType = Enum.RaycastFilterType.Exclude

local function dropToRoad(at: Vector3, part: BasePart): Vector3
	-- Everything trigger-ish is excluded, or a node lands on the gate
	-- above it or on a power-up box sitting on the road.
	dropParams.FilterDescendantsInstances = Triggers.collect({})

	local up = part.CFrame.UpVector
	-- From the top of the part downward: starting at the centre would
	-- miss a road the volume is already sunk into.
	local from = at + up * (part.Size.Y * 0.5 + 2)
	local hit = workspace:Raycast(from, -up * (part.Size.Y + R.RouteDropProbe), dropParams)
	return if hit then hit.Position else at
end

-- Walks sideways from the centreline until the floor stops.
--
-- "Stops" means one of two things, and both matter: no hit at all (thin
-- air), or a hit far enough BELOW the road to be a different surface.
-- The second case is the one that catches bots out — a ledge with ground
-- thirty studs down isn't a wide road, it's a fall, and a plain
-- did-the-ray-hit test calls it drivable.
local function edgeDistance(from: Vector3, dir: Vector3, up: Vector3): number
	dropParams.FilterDescendantsInstances = Triggers.collect({})

	local base = from:Dot(up)
	local last = 0
	local d = R.RouteEdgeStep
	while d <= R.RouteMaxHalfWidth do
		local at = from + dir * d
		local hit = workspace:Raycast(at + up * R.RouteEdgeProbeUp, -up * (R.RouteEdgeProbeUp + R.RouteEdgeDrop), dropParams)
		-- Measured along the local up, not world Y, so this survives a
		-- banked corner and a loop.
		if not hit or math.abs(hit.Position:Dot(up) - base) > R.RouteEdgeStepDrop then
			break
		end
		last = d
		d += R.RouteEdgeStep
	end

	return math.max(last, R.RouteMinHalfWidth)
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
			position = dropToRoad(sum / #group, group[1]),
			parts = group,
			halfWidth = R.RouteDefaultHalfWidth,
			leftWidth = R.RouteDefaultHalfWidth,
			rightWidth = R.RouteDefaultHalfWidth,
		})
	end

	-- WHERE THE ROAD ACTUALLY ENDS. Second pass, because it needs the
	-- direction of travel and that needs the neighbours placed first.
	--
	-- This is FELT FOR, not read off the checkpoint volume.
	--
	-- Measuring it from the gate was the obvious free answer — a gate is a
	-- slab spanning the track, so surely its width is the road's. It
	-- isn't. Gates get drawn generously so nobody can squeeze past one,
	-- and on a real track they hang out over the void at exactly the
	-- corners where it matters. Trusting them told bots there was tarmac
	-- where there was nothing, which is worse than not knowing at all: it
	-- gave a confident wrong answer to "may I drive here".
	--
	-- So: step outward from the centreline and raycast down until the
	-- floor stops being there. Costs a few dozen rays per node, once, on a
	-- table that's already cached for the life of the track.
	--
	-- LEFT AND RIGHT SEPARATELY, because a checkpoint is rarely centred on
	-- its road. One symmetric number splits the difference and is wrong on
	-- both sides — too tight where there's room, too generous over the
	-- drop, and it's the generous side that kills bots.
	for i, node in nodes do
		local prev = nodes[if i > 1 then i - 1 else #nodes]
		local nxt = nodes[if i < #nodes then i + 1 else 1]
		local forward = nxt.position - prev.position
		if forward.Magnitude < 1e-3 then
			continue
		end

		-- Same convention as lateralAt, or every sign downstream flips.
		local up = node.parts[1].CFrame.UpVector
		local across = forward.Unit:Cross(up)
		if across.Magnitude < 1e-4 then
			continue
		end
		across = across.Unit

		node.leftWidth = edgeDistance(node.position, -across, up)
		node.rightWidth = edgeDistance(node.position, across, up)
		node.halfWidth = math.min(node.leftWidth, node.rightWidth)
	end

	cache = nodes
	cachedCount = #parts
	return nodes
end

-- How much room there is on each side of the line here, blended between
-- nodes so it doesn't step at every gate.
--
-- Signed like lateralAt: right is positive. A bot's chosen offset is
-- clamped between these, which is the whole reason they exist.
function Route.roomAt(u: number): (number, number)
	local nodes = Route.nodes()
	local n = #nodes
	if n == 0 then
		return R.RouteDefaultHalfWidth, R.RouteDefaultHalfWidth
	end
	local i = math.floor(u) % n
	local t = u - math.floor(u)
	local a, b = nodes[i + 1], nodes[(i + 1) % n + 1]
	local function mix(x: number?, y: number?): number
		local p = x or R.RouteDefaultHalfWidth
		local q = y or R.RouteDefaultHalfWidth
		return p + (q - p) * t
	end
	return mix(a.leftWidth, b.leftWidth), mix(a.rightWidth, b.rightWidth)
end

-- The narrower of the two. Kept because plenty of callers only want "how
-- much room is there", and it's the safe answer for both sides.
function Route.halfWidthAt(u: number): number
	local left, right = Route.roomAt(u)
	return math.min(left, right)
end

-- Is there road at this point? The live version of the same question the
-- width pass answers offline — used by bots to check the ground under
-- where they are about to steer, which no cached width can cover once
-- they have been knocked off the line.
function Route.hasGround(at: Vector3, up: Vector3): boolean
	dropParams.FilterDescendantsInstances = Triggers.collect({})
	local from = at + up * R.RouteEdgeProbeUp
	local hit = workspace:Raycast(from, -up * (R.RouteEdgeProbeUp + R.RouteEdgeDrop), dropParams)
	return hit ~= nil
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
--
-- CENTRIPETAL Catmull-Rom (alpha = 0.5), not the uniform kind.
--
-- Uniform Catmull-Rom overshoots when its control points are unevenly
-- spaced — the curve bulges OUTSIDE the polygon through them, and on a
-- tight corner between two distant checkpoints that bulge goes through
-- the scenery. It can also form a cusp or a small loop where spacing
-- changes sharply, which puts a missile briefly through the wall and
-- back.
--
-- Centripetal parameterisation is proven not to self-intersect or cusp,
-- and stays much closer to the control polygon. The cost is the four
-- knot values below; the benefit is that checkpoint spacing stops being
-- something you have to be careful about.
function Route.pointAt(u: number): Vector3?
	local nodes = Route.nodes()
	local n = #nodes
	if n == 0 then
		return nil
	end

	local i = math.floor(u)
	local s = u - i
	local p0, p1 = wrapNode(nodes, i - 1), wrapNode(nodes, i)
	local p2, p3 = wrapNode(nodes, i + 1), wrapNode(nodes, i + 2)

	-- Knots spaced by the SQUARE ROOT of the distance between points.
	-- Guarded against coincident checkpoints, which would otherwise
	-- divide by zero — two nodes at the same spot is a setup mistake, not
	-- a reason to error.
	local function knot(a: number, from: Vector3, to: Vector3): number
		return a + math.max((to - from).Magnitude, 1e-4) ^ 0.5
	end
	local t0 = 0
	local t1 = knot(t0, p0, p1)
	local t2 = knot(t1, p1, p2)
	local t3 = knot(t2, p2, p3)

	local t = t1 + (t2 - t1) * s

	local a1 = p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
	local a2 = p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
	local a3 = p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))

	local b1 = a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
	local b2 = a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))

	local curved = b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1))

	-- Pulled back toward the straight line between the two checkpoints.
	-- Bounds how far the route can bow away from them, which is the thing
	-- that actually decides whether a missile clips a corner — see
	-- Race.RouteTension.
	if R.RouteTension >= 1 then
		return curved
	end
	return p1:Lerp(p2, s):Lerp(curved, math.clamp(R.RouteTension, 0, 1))
end

-- Which way the road runs at `u`. Sampled rather than differentiated —
-- the exact derivative buys nothing here and this can't divide by zero.
function Route.tangentAt(u: number): Vector3?
	local nodes = Route.nodes()
	local n = #nodes
	if n == 0 then
		return nil
	end

	local i = math.floor(u)
	local a = nodes[((i - 1) % n) + 1].position
	local b = nodes[(i % n) + 1].position
	
	local d = b - a

	if d.Magnitude < 1e-4 then
		return nil
	end

	return d.Unit
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

-- Where on the racing line a world position sits, as a `u`.
--
-- Needed because a racer's checkpoint COUNT is only an integer — it says
-- which checkpoint they last passed, not where between that one and the
-- next they are. Launching a missile from the integer drops it back at
-- the checkpoint behind the shooter, which looks like it spawning and
-- vanishing.
--
-- Coarse sweep then a local refine. Called once per launch, not per
-- frame, so simple beats clever.
function Route.nearestU(pos: Vector3): number
	local nodes = Route.nodes()
	local n = #nodes
	if n == 0 then
		return 0
	end

	local bestU, bestD = 0, math.huge
	local steps = n * 8
	for k = 0, steps - 1 do
		local u = k / 8
		local pt = Route.pointAt(u)
		if pt then
			local d = (pt - pos).Magnitude
			if d < bestD then
				bestU, bestD = u, d
			end
		end
	end

	-- Refine around the winner, halving the window each pass.
	local window = 1 / 8
	for _ = 1, 6 do
		for _, u in { bestU - window, bestU + window } do
			local pt = Route.pointAt(u % n)
			if pt then
				local d = (pt - pos).Magnitude
				if d < bestD then
					bestU, bestD = u, d
				end
			end
		end
		window *= 0.5
	end
	return bestU % n
end

-- Sideways offset of a world position from the racing line at `u`,
-- positive to the right. `up` decides which way "right" is, so this
-- still works on a banked or inverted section.
function Route.lateralAt(u: number, pos: Vector3, up: Vector3): number
	local centre = Route.pointAt(u)
	local tangent = Route.tangentAt(u)
	if not (centre and tangent) then
		return 0
	end
	local right = tangent:Cross(up)
	if right.Magnitude < 1e-4 then
		return 0
	end
	return (pos - centre):Dot(right.Unit)
end

return Route
