--[[
	ProjectileService — server-owned projectiles, client-rendered.

	THE SPLIT, AND WHY
	------------------
	This used to own a visible Anchored Part and set its CFrame every
	Heartbeat. That is the wrong technique for anything fast: a scripted
	CFrame change on an anchored part replicates as a property update at
	Roblox's replication rate, with no interpolation between updates. At
	210 studs/s a missile covers ~10 studs between them, so what everyone
	saw was a stuttering teleport — and it cost bandwidth per projectile
	per player to look that bad.

	So the Part is gone from the server. What stays here is purely
	numeric, and three small messages go out:

	    launch   once — everything a client needs to reproduce the flight
	    sync     a few times a second — authoritative pos/dir, for drift
	    gone     once — stop drawing, and whether it actually hit

	Every client renders its own visual and integrates it locally at full
	frame rate (see KartClient/Projectiles). Both ends run the SAME
	guidance out of Ballistics, so they track each other on their own; the
	sync messages exist to correct slow drift, not to drive the motion.

	Net result: three small events instead of a CFrame stream, and it
	looks better because it's drawn at 60fps rather than at replication
	rate.

	WHAT THE SERVER STILL DECIDES
	-----------------------------
	Everything that matters. Whether a projectile exists, where it is for
	hit purposes, and who it hits. A client drawing a missile slightly out
	of place changes nothing except its own picture.

	KINEMATIC, LIKE THE KARTS
	-------------------------
	No physics, no BodyMovers — see Ballistics. A capped turn rate is what
	makes a homing missile dodgeable instead of inevitable.

	NO TARGET IS FINE
	-----------------
	Fired with nobody ahead it flies the route and expires, and it can
	still hit anyone it runs into on the way. That keeps the item useful in
	first place and on an empty server rather than failing to fire and
	feeling broken.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Items = require(BloxKart:WaitForChild("Items"))
local Names = require(BloxKart:WaitForChild("Names"))
local Match = require(BloxKart:WaitForChild("Match"))
local Route = require(BloxKart:WaitForChild("Route"))
local Triggers = require(BloxKart:WaitForChild("Triggers"))
local Ballistics = require(BloxKart:WaitForChild("Ballistics"))
local Config = require(BloxKart:WaitForChild("Config"))
local MatchService = require(script.Parent.MatchService)
local RaceService = require(script.Parent.RaceService)
local KartService = require(script.Parent.KartService)

local IT = Config.Items

local ProjectileService = {}

local live = {} -- active projectiles, numeric only
local nextUid = 0

local remote: RemoteEvent -- client → server: "I fired this"
local viewRemote: RemoteEvent -- server → clients: launch / sync / gone
local hitRemote: RemoteEvent

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- What a missile may hit.
--
-- Karts and characters are excluded: a missile passing near a kart
-- shouldn't detonate on its bodywork, proximity to the target is what
-- counts.
--
-- Trigger volumes are excluded too, and this is the important one — a
-- checkpoint zone is CanQuery = true so TagZones can find it, which also
-- makes it a wall to a raycast. Without this the missile detonated on
-- the first checkpoint it flew through while every client, using the
-- fuller filter, drew it sailing straight on. The list is shared with
-- WorldFilter now precisely so the two can't disagree again.
local function refreshFilter()
	local skip = {}
	for _, kart in CollectionService:GetTagged(Names.KART_TAG) do
		table.insert(skip, kart)
	end
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(skip, plr.Character)
		end
	end
	Triggers.collect(skip)
	rayParams.FilterDescendantsInstances = skip
end

-- Where the target is. Trivial now that a Target is only a position —
-- it carried a route index until the server took over deciding when to
-- commit.
local function targetOf(kart: Model?): Ballistics.Target?
	local hb = kart and kart.PrimaryPart
	return if hb then { pos = hb.Position } else nil
end

--=====================================================================
--  ACQUISITION
--
--  A missile hunts whoever gets in the way, not whoever the standings
--  say is next. That's simpler and much better to play against: aiming
--  at the racer one place ahead meant ignoring the one it was flying
--  straight through.
--
--  Server-side because a lock decides who gets hit, and every client
--  drawing a different target would be two different missiles.
--=====================================================================
local function acquire(p)
	if p.locked then
		return
	end
	local item = p.item
	if not (item.AcquireRange and item.AcquireArc) then
		return
	end

	local best, bestDist = nil, item.AcquireRange
	for _, kart in CollectionService:GetTagged(Names.KART_TAG) do
		local hb = kart.PrimaryPart
		-- Never the shooter, and never a mis-tagged model with no hitbox.
		if hb and kart ~= p.from then
			local toward = hb.Position - p.pos
			local dist = toward.Magnitude
			-- In FRONT of where it's travelling. Without this it locks
			-- something it has already flown past and turns round.
			if dist < bestDist and dist > 1e-3 and toward.Unit:Dot(p.dir) >= item.AcquireArc then
				-- And actually visible: locking through the inside of a
				-- hairpin just buries it in the wall.
				if not workspace:Raycast(p.pos, toward, rayParams) then
					best, bestDist = kart, dist
				end
			end
		end
	end

	if best then
		p.target = best
		p.locked = true
		if IT.ProjectileDebug then
			print(("[Missile] #%d locked onto %s at %.0f studs"):format(p.uid, best.Name, bestDist))
		end
	end
end

--=====================================================================
--  END OF LIFE
--=====================================================================
local function detonate(p, victim: Model?, why: string?)
	if IT.ProjectileDebug then
		print(
			("[Missile] #%d %s after %.1fs — u %.1f, %s"):format(
				p.uid,
				why or (if victim then "HIT " .. victim.Name else "gone"),
				os.clock() - p.born,
				p.u or 0,
				p.dbgMode or "?"
			)
		)
	end
	local i = table.find(live, p)
	if i then
		table.remove(live, i)
	end

	-- Told to everyone, not just the victim: every client is drawing this
	-- projectile and needs to stop, at roughly the right place.
	viewRemote:FireAllClients("gone", {
		uid = p.uid,
		pos = p.pos,
		hit = victim ~= nil,
	})

	if not victim then
		return
	end
	local id = victim:GetAttribute(Names.OWNER)
	local plr = id and Players:GetPlayerByUserId(id)
	if plr and plr ~= p.owner then
		RaceService.announce(p.item.Id, p.owner, plr)
		-- Only the victim's own client applies the effect, same rule as
		-- every other hit in the game.
		hitRemote:FireClient(plr, {
			spin = p.item.SpinTime,
			keep = p.item.SpeedKeep,
			stun = p.item.StunTime,
			note = p.item.HitNote,
		})
	end
end

--=====================================================================
--  FLIGHT
--=====================================================================
local function step(dt: number)
	if #live == 0 then
		return
	end
	refreshFilter()
	local now = os.clock()

	for i = #live, 1, -1 do
		local p = live[i]

		if now >= p.expires then
			detonate(p, nil, "EXPIRED (out of range — raise Lifetime)")
			continue
		end

		-- Look for somebody to hit before moving, so a kart that pulls
		-- across in front is caught on the frame it does it.
		acquire(p)

		local wall = Ballistics.step(p, dt, targetOf(p.target), rayParams)
		if wall then
			detonate(p, nil, "WALL at " .. tostring(wall))
			continue
		end

		-- Proximity to ANY kart but the shooter's, not just the target, so
		-- a missile fired at nobody is still dangerous.
		local blew = false
		for _, kart in CollectionService:GetTagged(Names.KART_TAG) do
			local hb = kart.PrimaryPart
			if hb and kart ~= p.from and (hb.Position - p.pos).Magnitude <= p.item.HitRadius then
				detonate(p, kart)
				blew = true
				break
			end
		end
		if blew then
			continue
		end

		-- Low-rate correction. Deliberately NOT every frame: clients run
		-- the same integration and only need pulling back into line
		-- occasionally. This is the whole network cost of a projectile in
		-- flight.
		if now >= p.nextSync then
			p.nextSync = now + IT.ProjectileSyncInterval
			viewRemote:FireAllClients("sync", {
				uid = p.uid,
				pos = p.pos,
				dir = p.dir,
				up = p.up,
				-- Who it locked, so every client draws the same chase
				-- rather than each picking its own idea of a target.
				target = p.target,
				locked = p.locked,
			})
		end
	end
end

--=====================================================================
--  START
--=====================================================================
function ProjectileService.start()
	hitRemote = BloxKart:WaitForChild("KartItemHit")

	remote = Instance.new("RemoteEvent")
	remote.Name = "KartProjectile"
	remote.Parent = BloxKart

	viewRemote = Instance.new("RemoteEvent")
	viewRemote.Name = "KartProjectileView"
	viewRemote.Parent = BloxKart

	remote.OnServerEvent:Connect(function(player, itemId, _unusedTarget, back)
		-- Racing only. Between rounds players are free to drive but not to
		-- shoot: a missile fired during the countdown would arrive while
		-- the field is still pinned on the grid and unable to dodge.
		if not Match.isDriving(MatchService.phase()) then
			return
		end
		if typeof(itemId) ~= "string" then
			return
		end
		local item = Items.byId(itemId)
		if not (item and item.Projectile) then
			return
		end
		-- The client no longer nominates anybody. It says "I fired this,
		-- forwards or backwards" and the server locks whoever gets in the
		-- way — which removes the last thing a client could lie about here.

		-- Spawn position comes from the REPLICATED kart, never from the
		-- client, so nobody can fire from across the map.
		local from = KartService.kartFor(player)
		local hb = from and from.PrimaryPart
		if not hb then
			return
		end

		local up = hb.CFrame.UpVector

		-- Launched LEVEL with the road, not down the nose. A kart pitched
		-- nose-down on a crest would otherwise fire straight into the
		-- tarmac — flattening against the kart's own up means it leaves
		-- level whatever the kart is doing.
		local dir = hb.CFrame.LookVector
		local flat = dir - up * dir:Dot(up)
		dir = if flat.Magnitude > 1e-3 then flat.Unit else dir
		-- Thrown backwards: leaves out of the back and rides the route the
		-- other way. Boolean-ised because it came from a client and could
		-- be anything at all.
		local way = if back == true then -1 else 1
		dir *= way

		-- Starts at cruise height so it doesn't spend its first frames
		-- climbing out of the ground.
		local cruise = if item.CruiseHeight then up * item.CruiseHeight else Vector3.zero
		local pos = hb.Position + dir * item.Projectile.Offset + cruise

		-- Enters the route at the shooter's ACTUAL position on it, not at
		-- the last checkpoint they passed.
		--
		-- A checkpoint count is an integer: it says which one you're past,
		-- not where between it and the next you are. Launching from the
		-- integer drops the missile back at the checkpoint behind the
		-- shooter, so it appears at the kart and is instantly somewhere
		-- else — which reads as it spawning and vanishing.
		local nodes = Route.nodes()
		local startU = if #nodes > 0 then Route.nearestU(pos) else 0
		local startLateral = if #nodes > 0 then Route.lateralAt(startU, pos, up) else 0

		nextUid += 1
		local p = {
			uid = nextUid,
			item = item,
			owner = player,
			from = from,
			target = nil, -- acquired in flight, never handed over
			pos = pos,
			dir = dir,
			up = up,
			u = startU,
			way = way,
			-- On the shooter's own line rather than the centre of the road,
			-- so it leaves from where the kart actually is.
			lateral = startLateral,
			-- railOff is captured on the first step, from wherever the nose
			-- was versus the racing line, and decays to nothing.
			born = os.clock(),
			expires = os.clock() + item.Lifetime,
			nextSync = 0,
		}
		table.insert(live, p)

		if IT.ProjectileDebug then
			print(
				("[Missile] #%d launched by %s — %d route nodes, entering at u %.2f (lat %.1f)%s"):format(
					nextUid,
					player.Name,
					#nodes,
					p.u,
					p.lateral,
					if way < 0 then " BACKWARDS" else ""
				)
			)
		end

		-- Everything a client needs to reproduce the flight itself.
		viewRemote:FireAllClients("launch", {
			uid = p.uid,
			itemId = item.Id,
			pos = pos,
			dir = dir,
			up = up,
			u = p.u,
			lateral = p.lateral,
			way = p.way,
			shooter = from,
		})
	end)

	RunService.Heartbeat:Connect(step)
end

return ProjectileService
