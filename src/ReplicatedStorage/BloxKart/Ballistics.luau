--[[
	Ballistics — projectile guidance. Pure maths, no Instances, no
	networking.

	IT RIDES THE ROAD; IT DOESN'T FLY TO IT
	---------------------------------------
	A missile's position is not a point in the world that we steer. It's a
	position ON THE ROUTE:

	    u        how far along the racing line, in node units
	    lateral  how far to the side of the centreline
	    height   how far above the surface

	World position is DERIVED from those three every frame. The missile is
	on rails, and the rails are the checkpoint spline.

	This replaced free-flight steering toward waypoints, which produced
	two problems that are really one problem:

	  - it flew STRAIGHT at the next checkpoint, so on any bend it went
	    through the scenery. Whiskers and wall tests were us fighting a
	    symptom
	  - arriving, it couldn't turn tightly enough at 210 studs/s to reach
	    the node, so it overshot, turned back, overshot again — orbiting
	    the waypoint in a limit cycle

	Neither can happen now. Cutting a corner is not something the missile
	is able to express, and there's no waypoint to circle because `u` only
	ever goes forwards. Same reason a Mario Kart red shell never flies
	into a wall: it isn't really flying.

	WHAT IT GIVES UP
	----------------
	It can't leave the road — to cut a corner deliberately, or to chase
	someone who's gone off a ramp. Kart racers generally can't do either,
	and nobody misses them.

	It needs enough checkpoints to describe the road. Under four there's
	no spline and it falls back to straight lines between them; with none
	it flies straight, which keeps a bare test map working.

	SHARED, DELIBERATELY
	--------------------
	The server owns whether a missile HITS; every client owns what it
	LOOKS like. The only reliable way to make two integrations agree is
	for there to be one integration.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")

local Route = require(BloxKart:WaitForChild("Route"))
local Util = require(BloxKart:WaitForChild("Util"))

local Ballistics = {}

export type State = {
	item: any,
	pos: Vector3,
	dir: Vector3,
	up: Vector3,
	u: number, -- position along the racing line, node units, wraps past a lap
	lateral: number, -- studs right of the centreline
	way: number?, -- +1 down the track, -1 back up it. Nil means forwards
	locked: boolean?, -- committed to the target; never returns to the rails
}

export type Target = {
	pos: Vector3?,
	abs: number?, -- absolute route index; see Route.absoluteOf
}

--=====================================================================
--  HEIGHT
--
--  Route nodes are checkpoint centres, which may sit anywhere from road
--  level to well above it. So the road is found by probing DOWN from the
--  racing line rather than trusting the node's own height.
--
--  Probing along the projectile's own up rather than world down is what
--  keeps this working through a loop.
--=====================================================================
local function surfaceUnder(p: State, at: Vector3, rayParams: RaycastParams): (Vector3, Vector3)
	local item = p.item
	local from = at + p.up * item.CruiseProbe * 0.25
	local probe = workspace:Raycast(from, -p.up * item.CruiseProbe, rayParams)
	if probe then
		return probe.Position, probe.Normal
	end
	return at, p.up
end

--=====================================================================
--  STEP
--=====================================================================

-- Advances one projectile by dt, mutating `p`.
--
-- Returns a position if it should stop, else nil. On the rails that
-- never happens; only the free-flight paths can hit a wall.
function Ballistics.step(p: State, dt: number, target: Target?, rayParams: RaycastParams): Vector3?
	local item = p.item
	local targetPos = target and target.pos
	local step = item.Speed * dt

	local centre = if p.u then Route.pointAt(p.u) else nil

	----------------------------------------------------------------
	-- No route. Free flight, so a bare test map still works.
	----------------------------------------------------------------
	if not centre then
		p.dbgMode = "no-route"
		p.dbgAim = targetPos
		if targetPos then
			local toward = targetPos - p.pos
			if toward.Magnitude > 1e-3 then
				p.dir = p.dir:Lerp(toward.Unit, math.min(item.HomingRate * dt, 1)).Unit
			end
		end
		local hit = workspace:Raycast(p.pos, p.dir * step, rayParams)
		if hit then
			p.pos = hit.Position
			return hit.Position
		end
		p.pos += p.dir * step
		return nil
	end

	----------------------------------------------------------------
	-- Final approach, and it LATCHES.
	--
	-- Testing the range every frame made the missile dither: it would
	-- enter strike range, the target would pull away, and it would drop
	-- back onto the rails — then re-enter, and back again. From outside
	-- that reads as the missile not knowing whether it wants the player
	-- or the checkpoint. Committing once and never going back is both
	-- less code and what it should have been doing.
	--
	-- Locked only when the target is actually VISIBLE, so it can't commit
	-- through the inside of a hairpin and bury itself in the wall. That
	-- check is the entire reason a wall raycast still exists here.
	----------------------------------------------------------------
	if not p.locked and targetPos and (targetPos - p.pos).Magnitude <= item.StrikeRange then
		if not workspace:Raycast(p.pos, targetPos - p.pos, rayParams) then
			p.locked = true
		end
	end

	if p.locked then
		p.dbgMode = "strike"
		p.dbgAim = targetPos
		-- Target gone — respawned, or left. Committed either way; it flies
		-- on and expires rather than rejoining the route somewhere it no
		-- longer belongs.
		if targetPos then
			local toward = targetPos - p.pos
			if toward.Magnitude > 1e-3 then
				p.dir = p.dir:Lerp(toward.Unit, math.min(item.HomingRate * dt, 1)).Unit
			end
		end
		p.pos += p.dir * step
		return nil
	end

	----------------------------------------------------------------
	-- On the rails.
	----------------------------------------------------------------
	p.dbgMode = "route"

	-- Advance along the line, converted through the local segment length
	-- so a short segment isn't crossed as slowly as a long one. `way` is
	-- -1 for an item thrown backwards, which rides the same rails in the
	-- opposite direction.
	local way = p.way or 1
	p.u += way * step / Route.segmentLength(p.u)
	centre = Route.pointAt(p.u) or centre
	local tangent = (Route.tangentAt(p.u) or p.dir) * way

	-- The surface under the racing line, and its normal — which becomes
	-- our up, so a banked or inverted section carries the missile round
	-- with it for free.
	local ground, normal = surfaceUnder(p, centre, rayParams)
	p.up = p.up:Lerp(normal, math.min(item.ClimbRate * dt, 1)).Unit

	local right = tangent:Cross(p.up)
	right = if right.Magnitude > 1e-4 then right.Unit else Vector3.zero

	-- Slide across the road toward whichever side the target is on, so it
	-- arrives on their line rather than down the middle. Rate limited:
	-- snapping across the track reads as a bug, drifting across is what a
	-- real one does.
	if targetPos and right.Magnitude > 0 then
		local want = math.clamp((targetPos - centre):Dot(right), -item.MaxLateral, item.MaxLateral)
		p.lateral = Util.approach(p.lateral, want, item.LateralRate, dt)
	end

	local before = p.pos
	local onRail = ground + right * p.lateral + p.up * item.CruiseHeight

	-- Settled onto the rail as a DECAYING OFFSET, not a lerp from the
	-- previous position.
	--
	-- The launch point is the kart's nose, which is never exactly on the
	-- racing line, and snapping to the rail on frame one is the difference
	-- between a missile leaving the kart and one appearing near it. But
	-- lerping position toward the rail would also scale down the forward
	-- step, so the missile would crawl out of the launcher.
	--
	-- Holding the displacement separately and shrinking it lets the
	-- missile travel the road at full speed from the first frame while
	-- visibly converging onto the line.
	p.railOff = if p.railOff then p.railOff else (before - onRail)
	p.railOff = p.railOff:Lerp(Vector3.zero, math.min(dt / math.max(item.RailBlend, 1e-3), 1))
	p.pos = onRail + p.railOff

	-- Facing follows actual movement, so it points where it's going even
	-- while sliding sideways across the road.
	local moved = p.pos - before
	p.dir = if moved.Magnitude > 1e-3 then moved.Unit else tangent

	-- Debug line runs a node ahead: that's the road it's committed to.
	p.dbgAim = Route.pointAt(p.u + 1)
	return nil
end

-- The CFrame to draw it at. Rolled onto the local up so it banks through
-- corners and looks like it belongs to the track rather than sliding
-- over it.
function Ballistics.cframe(p: State): CFrame
	local up = p.up
	-- lookAt fails if up is parallel to the view direction, which happens
	-- the moment a missile is diving straight down a wall.
	if math.abs(p.dir:Dot(up)) > 0.99 then
		up = Vector3.yAxis
	end
	return CFrame.lookAt(p.pos, p.pos + p.dir, up)
end

return Ballistics
