--[[
	Ballistics — projectile guidance and integration. Pure maths, no
	Instances, no networking.

	WHY THIS IS SHARED
	------------------
	The server owns whether a missile HITS. Every client owns what the
	missile LOOKS like. Both have to agree closely, and the only reliable
	way to make two integrations agree is for there to be one integration.

	Same reasoning as the kart: hand-integrated so it behaves identically
	at any frame rate, and a capped turn rate is what keeps a homing
	missile dodgeable rather than inevitable.

	The caller supplies the target position and the raycast filter,
	because those are the two things the server and a client legitimately
	disagree about — the server sees authoritative kart positions, a
	client sees its own replicated view.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")

local Route = require(BloxKart:WaitForChild("Route"))

local Ballistics = {}

export type State = {
	item: any,
	pos: Vector3,
	dir: Vector3,
	up: Vector3,
	-- ABSOLUTE route index of the node being flown toward — grows past
	-- the checkpoint count as laps accumulate. See Route.absoluteOf.
	abs: number,
}

--=====================================================================
--  GUIDANCE
--
--  Route-following exists because a missile fired down the kart's nose
--  flies into the outside wall of the first corner. On a real track that
--  means it never reaches anybody.
--
--  WHEN DOES IT STOP FOLLOWING THE ROUTE AND START CHASING?
--  --------------------------------------------------------
--  Topologically, not by distance. The missile walks the checkpoint
--  sequence until it reaches the segment the TARGET is in, and only then
--  homes:
--
--      shooter at 4, target at 8
--        → route through 5, 6, 7, 8
--        → reaching 8's segment, home
--
--  Straight-line distance is the wrong test on its own, and this is
--  worth being precise about: on a hairpin the target can be 60 studs
--  away through a cliff. A distance-triggered missile turns hard into
--  the rock face and dies, having "found" a target it could never reach.
--
--  Distance is still used, but only as a SECOND condition once the
--  missile is already within a segment of the target — by which point
--  the straight line and the road agree.
--
--  Both indices are ABSOLUTE (laps included), so a target that has just
--  lapped the shooter reads as far ahead rather than as behind.
--=====================================================================

export type Target = {
	pos: Vector3?,
	abs: number?, -- absolute route index; see Route.absoluteOf
}

local function aimFor(p: State, target: Target?): (Vector3?, number)
	local item = p.item
	local targetPos = target and target.pos

	-- Route following is opt-in per item; without these an item behaves
	-- as it always did — straight, or homing if it has a target.
	local radius = item.WaypointRadius
	local turn = item.WaypointTurnRate or item.HomingRate
	if not radius then
		return targetPos, item.HomingRate
	end

	local nodes = Route.nodes()
	if #nodes == 0 then
		-- No checkpoints on this track, so there's no route to follow. A
		-- bare test map still works, it just flies straight or homes.
		return targetPos, item.HomingRate
	end

	-- Advance through waypoints already reached. A loop rather than a
	-- single step so a fast missile can't overshoot one and then turn
	-- round to collect it.
	for _ = 1, #nodes do
		local node = Route.nodeAt(nodes, p.abs)
		if not node or (node.position - p.pos).Magnitude > radius then
			break
		end
		p.abs += 1
	end

	local node = Route.nodeAt(nodes, p.abs)
	if not node then
		return targetPos, item.HomingRate
	end

	if targetPos and target and target.abs then
		-- How many segments behind the target we still are. 0 or less
		-- means we've arrived in their part of the track.
		local behind = target.abs - p.abs

		if behind <= 0 then
			return targetPos, item.HomingRate
		end
		-- One segment short and physically close: the road and the straight
		-- line agree from here, so cut the corner and commit.
		if behind <= 1 and item.HomingRange and (targetPos - p.pos).Magnitude <= item.HomingRange then
			return targetPos, item.HomingRate
		end
	elseif targetPos and item.HomingRange and (targetPos - p.pos).Magnitude <= item.HomingRange then
		-- No route position for the target (no standings yet, or a target
		-- that isn't racing). Fall back to plain distance rather than
		-- refusing to home at all.
		return targetPos, item.HomingRate
	end

	return node.position, turn
end

-- Keep the projectile a fixed height above whatever road is beneath it.
--
-- `up` is carried per-projectile and updated from the surface normal, so
-- this still works on a loop where "down" stops meaning -Y.
local function followTerrain(p: State, dt: number, rayParams: RaycastParams)
	local item = p.item
	-- Opt-in. An item that declares no cruise height flies dead straight,
	-- which is a reasonable thing to want.
	if not (item.CruiseHeight and item.CruiseProbe and item.ClimbRate) then
		return
	end
	local probe = workspace:Raycast(p.pos, -p.up * item.CruiseProbe, rayParams)
	if not probe then
		return -- over a gap; hold the current line and coast across
	end

	-- Track the surface's own normal so a loop or a banked corner rolls
	-- the notion of "up" with the road rather than fighting it.
	p.up = p.up:Lerp(probe.Normal, math.min(item.ClimbRate * dt, 1)).Unit

	local height = (p.pos - probe.Position).Magnitude
	local drift = item.CruiseHeight - height

	-- Correct the DIRECTION rather than the position, then renormalise:
	-- that keeps the flight path smooth instead of stair-stepping over
	-- every bump.
	local corrected = p.dir + p.up * (drift * item.ClimbRate * dt / math.max(item.Speed, 1))
	if corrected.Magnitude > 1e-3 then
		p.dir = corrected.Unit
	end
end

--=====================================================================
--  STEP
--=====================================================================

-- Advances one projectile by dt, mutating `p`.
--
-- Returns the position it stopped at if it ran into a wall, or nil if
-- it's still flying. The caller decides what a wall means: the server
-- detonates, a client just stops drawing.
function Ballistics.step(p: State, dt: number, target: Target?, rayParams: RaycastParams): Vector3?
	-- Steer, but only as hard as the turn rate allows. An uncapped chase
	-- is unavoidable, and unavoidable isn't fun.
	local aim, turnRate = aimFor(p, target)
	if aim then
		local toward = aim - p.pos
		if toward.Magnitude > 1e-3 then
			p.dir = p.dir:Lerp(toward.Unit, math.min(turnRate * dt, 1)).Unit
		end
	end

	followTerrain(p, dt, rayParams)

	local delta = p.dir * p.item.Speed * dt

	-- Walls stop it; FLOORS do not.
	--
	-- Treating every surface as a wall is what used to kill a missile on
	-- the first kerb, feet from the launcher. A surface whose normal
	-- points roughly the same way as the projectile's up is road, and road
	-- is for following, not exploding on.
	local floorDot = p.item.FloorDot or 1 -- no FloorDot: all walls, as before
	local wall = workspace:Raycast(p.pos, delta, rayParams)
	if wall and wall.Normal:Dot(p.up) < floorDot then
		p.pos = wall.Position
		return wall.Position
	end

	p.pos += delta
	return nil
end

-- The CFrame to draw it at. Rolled onto the local up so it banks through
-- corners and looks like it belongs to the track rather than sliding
-- over it.
function Ballistics.cframe(p: State): CFrame
	return CFrame.lookAt(p.pos, p.pos + p.dir, p.up)
end

return Ballistics
