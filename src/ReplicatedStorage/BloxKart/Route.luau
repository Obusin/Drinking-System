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
	-- ONE ENTRY PER GATE AT THIS ORDER. Two checkpoints sharing an order
	-- is how a FORK is authored — left way and right way, same progress —
	-- and the centroid of those two is the wall between them. Anything
	-- that has to drive the road picks a branch; anything that only needs
	-- one reference per order keeps using `position`.
	branches: { Vector3 },
	-- {left, right} per branch, measured from that gate rather than from
	-- the centroid, which on a fork is not on the road at all.
	branchWidths: { { number } },
	-- THE DIRECTION THE WIDTHS WERE MEASURED ALONG. Stored rather than
	-- recomputed, because anything that recomputes it gets a slightly
	-- different answer — a CENTRED tangent (next minus prev) is not the
	-- forward one, and the part's own up is not world up on a banked
	-- corner. Two places deriving this independently is how the debug
	-- markers ended up beside the road instead of on its edges.
	across: Vector3,
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
local cache: { [string]: { Node } } = {}
local cachedCount: { [string]: number } = {}
-- Arc-length data is read by every bot tick and every standings refresh. It
-- belongs to the authored, cached node table, so build it once per route
-- table instead of allocating a length/prefix pair for every racer.
local distanceCache = setmetatable({}, { __mode = "k" }) :: { [any]: any }

--=====================================================================
--  ONE BUILDER, TWO TAGS.
--
--  CHECKPOINTS ARE VALIDATION GEOMETRY. They are where a lap is proven,
--  so they get placed to be impossible to miss — wide, sparse, and often
--  hanging over the edge of the road. That makes them a poor DRIVING
--  line, and it is why bots looked stupid: they were following the
--  officiating, not the road.
--
--  So a second tag describes the line to drive. Same node structure,
--  same `Order` attribute, same everything downstream — it is only a
--  different set of parts. Put down as many as you like, wherever the
--  road actually goes.
--
--  Falls back to the checkpoints when nothing is tagged, so a track that
--  has not been given a path still works exactly as before.
--=====================================================================
local function buildNodes(tag: string): { Node }
	local parts = CollectionService:GetTagged(tag)
	if cache[tag] and cachedCount[tag] == #parts then
		return cache[tag]
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
		--==========================================================
		--  A FORK, NOT A WIDE GATE.
		--
		--  Two checkpoints sharing an order is how you author a
		--  split — left way and right way, same progress. The
		--  centroid of those two is the point BETWEEN them, which on
		--  a real fork is the wall or the void dividing them, and
		--  bots drove straight at it because that is what the route
		--  told them to do.
		--
		--  `position` stays the centroid, because progress scoring
		--  and anything that wants ONE reference per order still
		--  needs one. `branches` keeps the real gates, and anything
		--  that has to DRIVE through them asks for a branch.
		--==========================================================
		local branches = {}
		for _, part in group do
			table.insert(branches, dropToRoad(part.Position, part))
		end

		table.insert(nodes, {
			order = o,
			position = dropToRoad(sum / #group, group[1]),
			branches = branches,
			branchWidths = {},
			across = Vector3.zero,
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

		-- Kept so nothing has to derive it a second time and get a
		-- different answer.
		node.across = across
		node.leftWidth = edgeDistance(node.position, -across, up)
		node.rightWidth = edgeDistance(node.position, across, up)
		node.halfWidth = math.min(node.leftWidth, node.rightWidth)

		-- MEASURED FROM EACH GATE, not from the centroid. On a fork the
		-- centroid sits off the road entirely, so its widths describe a
		-- piece of track that does not exist — and it is the generous
		-- side of a wrong answer that kills bots.
		if #node.branches > 1 then
			for k, at in node.branches do
				node.branchWidths[k] = {
					edgeDistance(at, -across, up),
					edgeDistance(at, across, up),
				}
			end
		end
	end

	cache[tag] = nodes
	cachedCount[tag] = #parts
	return nodes
end

-- The CHECKPOINTS. Progress, missiles, respawn and lap validation all
-- still mean these — nothing about officiating has changed.
function Route.nodes(): { Node }
	return buildNodes(R.CheckpointTag)
end

-- THE LINE TO DRIVE. What bots follow. Falls back to the checkpoints so
-- an untagged track behaves exactly as it did before.
function Route.path(): { Node }
	local nodes = buildNodes(R.BotPathTag)
	if #nodes == 0 then
		return Route.nodes()
	end
	return nodes
end

-- How much room there is on each side of the line here, blended between
-- nodes so it doesn't step at every gate.
--
-- Signed like lateralAt: right is positive. A bot's chosen offset is
-- clamped between these, which is the whole reason they exist.
function Route.roomAt(u: number, branch: number?, src: { Node }?): (number, number)
	local nodes = src or Route.nodes()
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
	-- At a fork, the room is the chosen GATE's room. The centroid's
	-- widths describe track between the two ways, which is not road.
	local function side(node): (number, number)
		local w = node.branchWidths and node.branchWidths[((branch or 1) - 1) % math.max(#node.branches, 1) + 1]
		if branch and w then
			return w[1], w[2]
		end
		return node.leftWidth, node.rightWidth
	end
	local al, ar = side(a)
	local bl, br = side(b)
	return mix(al, bl), mix(ar, br)
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

-- `branch` is optional and only matters at a fork. Nil keeps the old
-- behaviour exactly — the centroid — so every existing caller is
-- unchanged and only the things that must DRIVE the road pass one.
local function wrapNode(nodes: { Node }, i: number, branch: number?): Vector3
	local node = nodes[((i - 1) % #nodes) + 1]
	local list = node.branches
	if branch and list and #list > 1 then
		return list[((branch - 1) % #list) + 1]
	end
	return node.position
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
function Route.pointAt(u: number, branch: number?, src: { Node }?): Vector3?
	local nodes = src or Route.nodes()
	local n = #nodes
	if n == 0 then
		return nil
	end

	local i = math.floor(u)
	local s = u - i
	local p0, p1 = wrapNode(nodes, i - 1, branch), wrapNode(nodes, i, branch)
	local p2, p3 = wrapNode(nodes, i + 1, branch), wrapNode(nodes, i + 2, branch)

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
function Route.tangentAt(u: number, branch: number?, src: { Node }?): Vector3?
	local nodes = src or Route.nodes()
	local n = #nodes
	if n == 0 then
		return nil
	end

	local i = math.floor(u)
	local a = wrapNode(nodes, i, branch)
	local b = wrapNode(nodes, i + 1, branch)
	
	local d = b - a

	if d.Magnitude < 1e-4 then
		return nil
	end

	return d.Unit
end

-- How far apart the two nodes bracketing `u` are, so a speed in studs
-- can be converted into a step in node units. Without this a missile
-- crosses a short segment as slowly as a long one.
function Route.segmentLength(u: number, src: { Node }?): number
	local nodes = src or Route.nodes()
	if #nodes == 0 then
		return 0
	end
	local i = math.floor(u)
	return math.max((wrapNode(nodes, i + 1) - wrapNode(nodes, i)).Magnitude, 1)
end

-- How much authored road lies before `u`, plus the fractional part of its
-- current segment.  `u` is a convenient steering coordinate but its units
-- are NODES: treating every segment as one unit made a sparse 100-stud
-- straight worth the same as a tightly sampled 5-stud corner in standings.
--
-- This intentionally measures the authored centreline chords.  It is stable,
-- cheap, and follows BotPath density without letting path-node spacing decide
-- who is ahead.
function Route.distanceAt(u: number, src: { Node }?): (number, number)
	local nodes = src or Route.nodes()
	local n = #nodes
	if n == 0 then
		return 0, 0
	end

	local entry = distanceCache[nodes]
	if not entry or entry.count ~= n then
		local lengths, prefix = {}, {}
		local total = 0
		for i = 0, n - 1 do
			local a = nodes[i + 1].position
			local b = nodes[(i + 1) % n + 1].position
			local length = math.max((b - a).Magnitude, 1e-3)
			lengths[i + 1] = length
			prefix[i + 1] = total
			total += length
		end
		entry = { count = n, lengths = lengths, prefix = prefix, total = total }
		distanceCache[nodes] = entry
	end

	local wrapped = u % n
	local index = math.floor(wrapped) % n
	local fraction = wrapped - math.floor(wrapped)
	return entry.prefix[index + 1] + entry.lengths[index + 1] * fraction, entry.total
end

-- A normalised lap fraction based on real route distance rather than an
-- arbitrary path-node count.  This is the shared standings ruler for bots,
-- players, the HUD, and item catch-up placement.
function Route.progressAt(u: number, src: { Node }?): number
	local distance, total = Route.distanceAt(u, src)
	if total <= 0 then
		return 0
	end
	return math.clamp(distance / total, 0, 0.999999)
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
function Route.nearestU(pos: Vector3, src: { Node }?, near: number?): number
	local nodes = src or Route.nodes()
	local n = #nodes
	if n == 0 then
		return 0
	end

	--=================================================================
	--  SEARCH NEAR WHERE YOU WERE, NOT ACROSS THE WHOLE LAP.
	--
	--  This used to take the global minimum over every node, every
	--  frame. On a big track the racing line passes near itself — a
	--  hairpin, a bridge, two straights side by side — and the nearest
	--  point can flip to a completely different part of the lap. `u`
	--  jumps, the bot turns to chase it, the flip reverses, and it
	--  circles. That is the "driving in circles around a node" — it was
	--  never orbiting anything, it was oscillating between two answers.
	--
	--  Sparse nodes make it worse, because the spline bulges further
	--  from the road between them and there is more chance some other
	--  stretch is closer than the one you are on.
	--
	--  With `near` the search is a window around where the caller
	--  already was, so `u` can only move a little per frame and cannot
	--  teleport. Leave it nil for a genuinely unknown position — a
	--  respawn, a grid placement — where a global search is correct.
	--
	--  It is also far cheaper. Global was `n * 8` spline evaluations per
	--  bot per frame: 60 nodes and 8 bots is ~230,000 a second. The
	--  window is about thirty.
	--=================================================================
	local first, last = 0, n * 8 - 1
	if near then
		local span = R.RouteSearchSpan * 8
		first, last = math.floor(near * 8 - span), math.ceil(near * 8 + span)
	end

	local bestU, bestD = near or 0, math.huge
	for k = first, last do
		local u = (k / 8) % n
		local pt = Route.pointAt(u, nil, nodes)
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
			-- PASSING `nodes`, which the original did not. Threading a
			-- second node source through the module left this one call
			-- reading the CHECKPOINTS while the loop above indexed the
			-- path — so a bot searched one line and measured against
			-- another. Silent, and exactly the kind of thing the type
			-- checker cannot see.
			local pt = Route.pointAt(u % n, nil, nodes)
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
-- HOW TIGHTLY THE ROAD TURNS HERE, signed, in 1/studs.
--
-- This is the number that lets a bot steer a corner BECAUSE IT IS THERE
-- rather than because it has already drifted wide. Without it every
-- input a bot makes is a reaction to its own error, and a loop that only
-- reacts to error must produce error to work — which is the swerve.
--
-- Menger curvature through three points on the spline: k = 4A/(abc).
-- Exact for a circle through them, and it needs no derivatives, so it
-- can't amplify the spline's own noise the way finite differencing a
-- tangent does.
--
-- SIGN, and it matters: positive means the road bends toward
-- `tangent:Cross(up)`, matching lateralAt and the bots' steering. For a
-- path curving that way, v1:Cross(v2) points AGAINST up — hence the
-- minus. Get this backwards and a bot steers away from every corner.
function Route.curvatureAt(u: number, up: Vector3, branch: number?, src: { Node }?): number
	local span = R.RouteCurvatureSpan
	local p0 = Route.pointAt(u - span, branch, src)
	local p1 = Route.pointAt(u, branch, src)
	local p2 = Route.pointAt(u + span, branch, src)
	if not (p0 and p1 and p2) then
		return 0
	end

	local v1, v2 = p1 - p0, p2 - p1
	local a, b = v1.Magnitude, v2.Magnitude
	local c = (p2 - p0).Magnitude
	if a < 1e-3 or b < 1e-3 or c < 1e-3 then
		return 0
	end

	local cross = v1:Cross(v2)
	local kappa = 4 * (cross.Magnitude * 0.5) / (a * b * c)
	return if cross:Dot(up) > 0 then -kappa else kappa
end

function Route.lateralAt(u: number, pos: Vector3, up: Vector3, src: { Node }?): number
	local centre = Route.pointAt(u, nil, src)
	local tangent = Route.tangentAt(u, nil, src)
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
