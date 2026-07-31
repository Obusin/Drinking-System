--[[
	RaceService — relays race progress so every client can see the field.

	Clients own their own simulation, so each one knows exactly where IT
	is and nothing about anyone else. Attributes written by a client
	don't replicate, so progress comes up over a RemoteEvent and the
	server writes it onto the kart, where it replicates to everyone.

	Deliberately thin: the server does not yet verify that a reported
	score is achievable. This is the seam where anti-cheat goes when the
	race stops being a placeholder — one function, one place.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Standings = require(BloxKart:WaitForChild("Standings"))
local Names = require(BloxKart:WaitForChild("Names"))
local Config = require(BloxKart:WaitForChild("Config"))
-- For the settle probe: it has to ignore karts, characters and every
-- other trigger volume, which is exactly what this list already is.
local WorldFilter = require(BloxKart:WaitForChild("WorldFilter"))
local Match = require(BloxKart:WaitForChild("Match"))
local Items = require(BloxKart:WaitForChild("Items"))
local MatchService = require(script.Parent.MatchService)
local KartService = require(script.Parent.KartService)
local Progress = require(script.Parent.Progress)

local RaceService = {}

local remote: RemoteEvent
local itemRemote: RemoteEvent
local hitRemote: RemoteEvent

-- "X hit Y with Z", to everyone. A hit is a spectacle: half the value of
-- a well-timed missile is the lobby seeing it land, and in a race you
-- rarely even see the person you hit.
--
-- Server-side because only the server knows both ends — the attacker's
-- client can't be trusted to name its own victim, and the victim's client
-- doesn't know who fired.
-- Names rather than Players, because a bot has no Player object and the
-- feed shouldn't care which kind of racer landed the hit.
function RaceService.announce(itemId: string?, byName: string?, victimName: string?)
	if not (RaceService.feed and victimName and itemId) then
		return
	end
	local item = Items.byId(itemId)
	RaceService.feed:FireAllClients({
		item = if item then item.Name else itemId,
		-- The icon carries the verb. An icon between two names reads as
		-- "did this to" in every game that has ever shipped a kill feed,
		-- and unlike a word it survives translation.
		icon = if item then item.Icon else "",
		-- Nil `by` is normal: a mine kills long after its owner drove off,
		-- and a missile fired at nobody still hits whoever it runs into.
		by = byName,
		victim = victimName,
	})
end

-- Applying a hit. One path for every attacker and every victim.
--
-- The victim used to be resolved with GetPlayerByUserId and dropped if
-- that came back nil — which is every bot, because a bot kart has no
-- owner. So missiles, mines and lightning all landed on them and did
-- absolutely nothing. They weren't AI, they were scenery, and you could
-- only tell by trying to hit one.
--
-- Non-player victims go to whoever registered onNonPlayerHit (see
-- BotService, wired in init.server). A hook rather than a require,
-- because RaceService is upstream of BotService and shouldn't know it
-- exists.
RaceService.onNonPlayerHit = nil

-- Cheapest possible bound on the hit remote. Generous enough that no
-- honest player will ever touch it — landing two items in a third of a
-- second is not a thing that happens — and finite, which is the point.
local HIT_COOLDOWN = 0.35
local lastHitAt: { [number]: number } = {}

Players.PlayerRemoving:Connect(function(player)
	lastHitAt[player.UserId] = nil
end)

-- `byPlayer` is the attacker as a Player, where there is one. It is
-- separate from `byName` on purpose: the feed wants a name and works
-- fine for a bot, whereas XP needs an account and must NOT be awarded
-- to one. Passing the name and hoping to resolve it back would be the
-- same question answered twice, and wrong for any bot sharing a name.
function RaceService.relayHit(byName: string?, targetKart: Model, payload, byPlayer: Player?)
	-- Clamped once, here, and reused for both kinds of victim. This is a
	-- client-supplied table and the only thing between it and somebody
	-- else's simulation; clamps are generous enough for any real item but
	-- finite, so a forged payload can't stun anyone for a minute.
	local effect = {
		item = payload.item,
		spin = math.clamp(tonumber(payload.spin) or 1, 0, 5),
		keep = math.clamp(tonumber(payload.keep) or 0.5, 0, 1),
		stun = math.clamp(tonumber(payload.stun) or 0, 0, 3),
		reverse = math.clamp(tonumber(payload.reverse) or 0, 0, 8),
		note = math.clamp(math.floor(tonumber(payload.note) or 1), 0, 3),
	}

	local victimId = targetKart:GetAttribute(Names.OWNER)
	local victim = victimId and Players:GetPlayerByUserId(victimId)

	-- A takedown is a hit that actually costs the victim time. The game
	-- has no elimination — nobody dies in a kart racer, they spin and
	-- carry on — so this is the closest honest thing to one.
	local takedown = effect.spin > 0 or effect.stun > 0
	-- Never pay for hitting yourself. A mine you drove into is still a
	-- hit for the feed; it is not an achievement.
	if byPlayer and byPlayer ~= victim then
		Progress.hit(byPlayer, takedown)
	end

	if victim then
		RaceService.announce(tostring(effect.item), byName, victim.DisplayName)
		-- Only the victim's own client applies it, same rule as always.
		hitRemote:FireClient(victim, effect)
		return
	end

	if RaceService.onNonPlayerHit then
		local name = RaceService.onNonPlayerHit(targetKart, effect)
		if name then
			RaceService.announce(tostring(effect.item), byName, name)
		end
	end
end

--=====================================================================
--  FLIGHT  (thrown hazards and scattered drops)
--
--  Handed to Roblox's physics rather than integrated by hand, which is
--  the opposite of what the kart and the missile do — and right for the
--  same reason those are wrong.
--
--  A thrown item is plain ballistics with nobody steering it. It needs
--  no determinism, no route and no feel, so the only thing that matters
--  is that everyone SEES it thrown. Moving an anchored part from a
--  server loop replicates as bare position updates with no interpolation
--  — over a 0.6s arc that's a dozen steps and it reads as a stutter or a
--  teleport. Exactly what was wrong with the missile before it was
--  rendered client-side.
--
--  An unanchored part with a velocity on it is interpolated by Roblox's
--  own replication, so it arcs smoothly for everybody at no cost in code
--  or bandwidth.
--
--  TRADE: physics gravity is world-down, so an item thrown ON A LOOP
--  falls off it rather than arcing onto the ceiling. Everything else in
--  this game is surface-relative, and this deliberately isn't — a
--  hand-integrated arc was surface-correct and looked broken, which is
--  the worse of the two.
--=====================================================================
local settling = {}

local function launch(part: BasePart, vel: Vector3, lifetime: number)
	-- Collidable while airborne or it falls through the road; back off
	-- on landing so it never blocks anyone.
	part.Anchored = false
	part.CanCollide = true

	-- COLLIDES WITH THE WORLD, NEVER WITH A KART.
	--
	-- The trigger filter keeps a hazard out of a kart's own movement
	-- queries, which is why the old comment said karts ignore it. That is
	-- only half of it: the filter is OUR query rule, and Roblox physics
	-- has its own opinion. A hazard sat in the default group with
	-- CanCollide on, so a bomb in flight physically struck karts and
	-- bounced off them — a throw at the racer in front would deflect
	-- rather than land, which is exactly the kind of thing that reads as
	-- the throw being wrong.
	--
	-- The kart group is already set non-collidable with itself, so
	-- putting the hazard in it gives both halves at once: passes through
	-- every kart, still lands on the road.
	part.CollisionGroup = Config.Rig.CollisionGroup
	part.AssemblyLinearVelocity = vel
	-- A little spin, so it tumbles rather than sliding through the air
	-- facing one way.
	part.AssemblyAngularVelocity = Vector3.new(math.random() * 8 - 4, math.random() * 8 - 4, math.random() * 8 - 4)

	table.insert(settling, {
		part = part,
		-- Settled when it stops moving, or when this runs out — a throw
		-- off the edge of the map would otherwise never settle.
		stop = os.clock() + math.min(Config.Items.ThrowTime, lifetime),
		-- For the trace below. A throw that never lands has to be able to
		-- say where it started and how hard it left.
		from = part.Position,
		speed = vel.Magnitude,
		-- Where it was last frame, for the swept ground test in
		-- stepSettling. Without this the only way to know it had landed
		-- was to ask physics, which never noticed.
		last = part.Position,
	})

	if Config.Items.ThrowDebug then
		print(
			("[Throw] %s launched at %.0f studs/s from %s"):format(
				part.Name,
				vel.Magnitude,
				tostring(part.Position)
			)
		)
	end
end

-- PUT IT ON THE ROAD, don't just stop it where it is.
--
-- Freezing in place was the whole bug: settling fires either when the
-- part slows down OR when ThrowTime runs out, and the timeout branch
-- doesn't care whether the thing has landed. A bomb still in the air
-- when its four seconds expired simply anchored there, hanging in
-- mid-air, which is exactly "it doesn't attach to the ground".
--
-- The velocity branch has the same hole in a smaller way: a lobbed item
-- passes through a slow moment near the apex, and a hazard that stops
-- on the lip of a ledge is left balanced on nothing.
--
-- So settling now means "find the ground beneath it and sit on it".
-- Probing down rather than trusting where it stopped is also what makes
-- a hazard sit flush on a ramp instead of floating over the slope.
-- A ring that expands and fades where a hazard planted itself.
--
-- Throwing had no landing cue at all. You lob a bomb a hundred-odd studs
-- up the road while doing ninety, and the only confirmation was
-- eventually driving over it — so a throw felt like it went nowhere even
-- when it worked perfectly.
--
-- Server-spawned so everyone sees it, which is the point: a throw
-- landing in front of the pack is worth seeing from behind too.
--
-- No asset needed. It's a flat neon ring, so it reads at a glance and
-- can't be a missing-image square.
local function landingRing(at: Vector3, normal: Vector3, colour: Color3)
	local IT = Config.Items
	if IT.LandRingTime <= 0 then
		return
	end
	local ring = Instance.new("Part")
	ring.Name = "LandRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, IT.LandRingStart, IT.LandRingStart)
	-- Cylinders point along X, so it's turned to lie flat on the surface.
	ring.CFrame = CFrame.lookAt(at + normal * 0.1, at + normal) * CFrame.Angles(0, math.rad(90), 0)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = colour
	ring.Transparency = IT.LandRingTransparency
	ring.Parent = workspace

	local grow = TweenService:Create(ring, TweenInfo.new(IT.LandRingTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, IT.LandRingEnd, IT.LandRingEnd),
		Transparency = 1,
	})
	grow:Play()
	Debris:AddItem(ring, IT.LandRingTime + 0.1)
end

-- Returns FALSE if there is nothing under it yet, and the caller must
-- then leave it falling rather than anchoring it.
--
-- That return value is the actual fix. This used to anchor
-- unconditionally and only reposition the part IF the probe happened to
-- hit — so a probe that found nothing froze the hazard exactly where it
-- was, which for a bomb still in flight is in the air. "Doesn't stick to
-- its landing point" is that: it never reached a landing point, and it
-- was stopped anyway.
-- Plants the part flush on a surface it has been shown to have reached.
--
-- Sits it half its own height above the contact point and keeps its yaw,
-- so a thrown model settles upright rather than snapping to face
-- somewhere new on landing.
--
-- RE-ARMS THE OWNER GRACE. That grace starts when the item is THROWN and
-- a forward throw spends most of it in the air, so by the time the thing
-- is a trap on the road the person who threw it has almost no protection
-- left. Restarting it here covers the part that matters. Guarded on the
-- attribute existing, so scattered drops — which have no arming — are
-- untouched.
local function plant(part: BasePart, at: Vector3, normal: Vector3)
	local _, y, _ = part.CFrame:ToEulerAnglesYXZ()
	part.CFrame = CFrame.new(at + normal * (part.Size.Y * 0.5)) * CFrame.Angles(0, y, 0)
	part.Anchored = true
	part.CanCollide = false
	if part:GetAttribute(Names.ARM_AT) then
		part:SetAttribute(Names.ARM_AT, workspace:GetServerTimeNow() + Config.Items.HazardOwnerGrace)
	end
	landingRing(at, normal, part.Color)
end

local function groundOut(part: BasePart): boolean
	local from = part.Position + Vector3.yAxis * Config.Items.SettleProbeUp
	local hit = workspace:Raycast(from, Vector3.yAxis * -Config.Items.SettleProbeDown, WorldFilter.rayParams)
	if not hit then
		return false
	end
	plant(part, hit.Position, hit.Normal)
	return true
end

-- Freeze anything that has come to rest, so a hazard doesn't get nudged
-- around the track by whatever brushes it afterwards.
local function stepSettling()
	local now = os.clock()
	for i = #settling, 1, -1 do
		local f = settling[i]
		local part = f.part
		if not part.Parent then
			table.remove(settling, i)
			continue
		end
		----------------------------------------------------------------
		-- DID IT CROSS THE GROUND SINCE LAST FRAME?
		--
		-- Asking physics whether it landed does not work, and the numbers
		-- say why: an item leaves the kart at over 200 studs/s, which is
		-- 3.7 studs per physics step, while oil is a 0.2-stud plate and a
		-- mine is 1.2. Both pass entirely through the road between one
		-- step and the next, so there is no contact to detect — the thing
		-- simply keeps going and falls out of the world.
		--
		-- So the ground test is a SWEPT one: a ray along the segment the
		-- part actually travelled this frame. Thickness and speed stop
		-- mattering, because a segment cannot skip over a surface the way
		-- a moving box can.
		--
		-- This is also why the previous fix didn't hold. Probing straight
		-- down from where the part ended up is fine for something resting
		-- on the road and useless for something already beneath it.
		----------------------------------------------------------------
		local travelled = part.Position - (f.last or part.Position)
		f.last = part.Position
		if travelled.Magnitude > 1e-3 then
			local hit = workspace:Raycast(part.Position - travelled, travelled, WorldFilter.rayParams)
			if hit then
				plant(part, hit.Position, hit.Normal)
				if Config.Items.ThrowDebug then
					print(
						("[Throw] %s LANDED at %s, %.0f studs from where it was thrown"):format(
							part.Name,
							tostring(hit.Position),
							(hit.Position - f.from).Magnitude
						)
					)
				end
				table.remove(settling, i)
				continue
			end
		end

		-- NOT AIRBORNE. Velocity alone is not "landed" — a lob passes
		-- through a slow moment at the top of its arc, and freezing it
		-- there is a bomb hanging in the sky. So the part must also have
		-- ground close beneath it, which is what groundOut reports.
		local resting = part.AssemblyLinearVelocity.Magnitude < 3
		if resting or now >= f.stop then
			if groundOut(part) then
				if Config.Items.ThrowDebug then
					print(
						("[Throw] %s LANDED at %s, %.0f studs from where it was thrown"):format(
							part.Name,
							tostring(part.Position),
							(part.Position - f.from).Magnitude
						)
					)
				end
				table.remove(settling, i)
			elseif now >= f.stop + Config.Items.SettleGrace then
				-- Always warns, not just in debug. A thrown item that never
				-- finds ground is the difference between the mechanic
				-- working and not, and it leaves no other trace.
				warn(
					("[Throw] %s NEVER LANDED — gave up at %s after %.1fs, still moving at %.0f studs/s. Nothing was under it: the settle probe looks straight down %d studs and ignores karts, characters and trigger volumes."):format(
						part.Name,
						tostring(part.Position),
						Config.Items.ThrowTime + Config.Items.SettleGrace,
						part.AssemblyLinearVelocity.Magnitude,
						Config.Items.SettleProbeDown
					)
				)
				-- Never found anything to sit on: thrown off the map, or
				-- over a hole. LEFT FALLING deliberately — its lifetime
				-- will collect it. Anchoring here is what produced a
				-- hazard stopped in mid-air over a gap.
				table.remove(settling, i)
			end
		end
	end
end

--=====================================================================
--  HAZARDS
--
--  A function rather than remote-handler guts, because BOTS drop things
--  too and a bot can't fire a remote at its own server. The handler
--  below is now just validation plus a call to this.
--
--  `ownerId` is a UserId for a player, or 0 for a bot — nobody's, so
--  every racer including the one that laid it can trigger it. Bots have
--  no client to be protected from their own traps.
--=====================================================================
function RaceService.spawnHazard(ownerId: number, cf: CFrame, item, back: boolean?, power: number?)
	local IT = Config.Items
	local spec = item.Hazard

	local hz = Instance.new("Part")
	hz.Name = item.Id
	hz.Size = spec.Size
	hz.CFrame = cf
	hz.Anchored = true
	hz.CanCollide = false
	hz.CanQuery = true -- clients detect it with a spatial query
	hz.Color = spec.Color
	hz.Material = spec.Material
	hz.Transparency = spec.Transparency
	-- Stamped so a dropper doesn't immediately drive into their own
	-- hazard, nobody can claim someone else's, and the victim's
	-- client knows which effect to apply.
	hz:SetAttribute(Names.OWNER, ownerId)
	-- SERVER TIME, not os.clock().
	--
	-- os.clock() is time since THIS process started, so the server's and
	-- each client's are unrelated numbers — comparing them is meaningless
	-- and fails in both directions. A client newer than the server is
	-- immune to its own hazards forever; a client older than the server
	-- gets no grace at all, drives into its own item the instant it
	-- spawns, and the hit destroys it. That second case is exactly
	-- "nothing spawns in front when I throw".
	--
	-- GetServerTimeNow is the same clock everywhere, which is the entire
	-- requirement for a timestamp that crosses the wire.
	hz:SetAttribute(Names.ARM_AT, workspace:GetServerTimeNow() + IT.HazardOwnerGrace)
	hz:SetAttribute(Names.HAZARD_ITEM, item.Id)
	-- Optional art. The part above stays the trigger volume and goes
	-- invisible; the model is decoration welded to it, and must never
	-- be queryable or it would read as a wall to a kart's sweep.
	if spec.Model then
		local folder = ServerStorage:FindFirstChild(IT.HazardModelFolder)
		local template = folder and folder:FindFirstChild(spec.Model)
		-- A Model OR a single Part. Art is just as often one
		-- MeshPart with decals on it as a whole model, and rejecting
		-- that was a silent fallback to the grey box.
		if template and (template:IsA("Model") or template:IsA("BasePart")) then
			hz.Transparency = 1
			local art = template:Clone()
			art.Name = "Visual"
			art.Parent = hz
			if art:IsA("Model") then
				art:PivotTo(cf)
			else
				art.CFrame = cf
			end
			local parts = if art:IsA("BasePart") then { art } else {}
			for _, d in art:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(parts, d)
				end
			end
			for _, d in parts do
				-- WELDED, not anchored. The hazard part is unanchored
				-- while it's in the air, and anchored art would stay
				-- hanging where it was created while the thing it
				-- decorates arcs away without it.
				d.Anchored = false
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Massless = true
				local weld = Instance.new("WeldConstraint")
				weld.Part0, weld.Part1 = hz, d
				weld.Parent = hz
			end
		else
			warn(
				("[RaceService] %s wants %q in ServerStorage.%s — no Model or Part by that name, using the plain part."):format(
					item.Id,
					spec.Model,
					IT.HazardModelFolder
				)
			)
		end
	end

	hz.Parent = workspace
	CollectionService:AddTag(hz, IT.HazardTag)

	-- Thrown forward: it arcs out of the kart. Dropped backwards it just
	-- sits where it was put — the item modules already place a backward
	-- drop BEHIND the kart, so it needs no arc to get there.
	if not back then
		-- Wind-up scales the FORWARD speed only. Lift stays put, so
		-- a weak throw is a short lob at the same height rather than
		-- a sad little hop — it's how far it goes that the player is
		-- choosing, not how high.
		--
		-- Clamped here because it arrived from a client.
		local charge = math.clamp(tonumber(power) or 1, 0, 1)
		local reach = IT.ThrowSpeed * (IT.ThrowMinPower + (1 - IT.ThrowMinPower) * charge)

		-- PLUS WHAT THE THROWER WAS ALREADY DOING.
		--
		-- The arc was built purely from the throw, as if it left a
		-- standing kart. It doesn't — you are doing most of the game's
		-- top speed when you throw, and anything you release inherits
		-- that. Without it a "forward" throw barely outruns the kart that
		-- threw it and lands almost underneath you, which is why it read
		-- as not going far enough.
		--
		-- A constant rather than the kart's measured velocity, because a
		-- bot's kart is anchored and reports zero — reading it would make
		-- bots throw shorter than players for a reason nobody could see.
		-- One number, same for everyone, matching the speed a racer is
		-- realistically doing when they throw.
		launch(hz, cf.LookVector * (reach + IT.ThrowLead) + cf.UpVector * IT.ThrowLift, item.Lifetime)
	elseif Config.Items.ThrowDebug then
		-- The other half of the trace. A backward drop is PLACED, never
		-- launched, so it can never appear in the settle log — and a
		-- forward throw arriving with back=true would look exactly like
		-- "you can throw it but it never lands".
		print(("[Throw] %s placed behind at %s (back=true, no arc)"):format(hz.Name, tostring(hz.Position)))
	end

	task.delay(item.Lifetime, function()
		if hz.Parent then
	hz:Destroy()
		end
	end)
	return hz
end

function RaceService.start()
	remote = Instance.new("RemoteEvent")
	remote.Name = Standings.REMOTE
	remote.Parent = BloxKart

	remote.OnServerEvent:Connect(function(player, score)
		if typeof(score) ~= "number" or score ~= score then
			return -- NaN or garbage
		end
		local kart = KartService.kartFor(player)
		if not kart then
			return
		end

		-- A FINISHED RACER'S PROGRESS IS FROZEN.
		--
		-- Where they finished is the truth and nothing after the flag can
		-- improve on it — but plenty can make it worse. Respawning resets
		-- the client's own lap tracking, so the very next report is a
		-- score from the start of the race, and writing that dropped a
		-- player who crossed the line FIRST to last in the order.
		--
		-- Sitting still does it too, more slowly, once the AI takes the
		-- kart over and the client is no longer the thing driving it.
		--
		-- Frozen rather than ignored outright: the attribute keeps the
		-- score they finished on, so they still rank ahead of everyone
		-- who hasn't finished. That is what finishing first means.
		if kart:GetAttribute(Match.FINISH_PLACE) then
			return
		end

		-- Never BACKWARDS, either.
		--
		-- Progress in a race only goes one way. A respawn, a rejoin, or a
		-- client that lost its place has no business lowering a score that
		-- was already earned, and the only thing a lower number can ever
		-- be is wrong.
		--
		-- This is also most of the validation the TODO below wanted: a
		-- forged score can still be too HIGH, but the whole class of
		-- accidental self-demotion is gone.
		local had = kart:GetAttribute(Standings.ATTRIBUTE)
		if typeof(had) == "number" and score < had then
			return
		end

		-- TODO: validate the jump UPWARD against the last known score
		-- before trusting it. Cheap to add here, impossible to add later
		-- if everything reads the attribute directly instead.
		kart:SetAttribute(Standings.ATTRIBUTE, score)
	end)

	----------------------------------------------------------------
	-- ITEM BOXES
	--
	-- The server owns box state. If clients owned it, the leader would
	-- collect a box and it would still be sitting there for everyone
	-- else — or vanish inconsistently for each of them.
	----------------------------------------------------------------
	itemRemote = Instance.new("RemoteEvent")
	itemRemote.Name = "KartItemPickup"
	itemRemote.Parent = BloxKart

	local IT = Config.Items
	local rng = Random.new()

	itemRemote.OnServerEvent:Connect(function(player, box)
		-- Only during the race itself. Players are free to drive around
		-- between rounds, so without this they could hoover up every box
		-- on the track during the intermission and arrive on the grid
		-- holding a full stack.
		if not Match.isDriving(MatchService.phase()) then
			return
		end
		if typeof(box) ~= "Instance" or not box:IsA("BasePart") then
			return
		end
		if not box.Parent then
			return
		end

		-- A dropped item, not a box: grant exactly what it is rather than
		-- rolling. Somebody already paid for this one by being spun.
		if CollectionService:HasTag(box, IT.DropTag) then
			local dropped = box:GetAttribute(Names.DROP_ITEM)
			local item = typeof(dropped) == "string" and Items.byId(dropped)
			if item then
				box:Destroy() -- one taker; destroyed before the reply so a
				-- second request in the same frame finds nothing
				itemRemote:FireClient(player, item.Id)
			end
			return
		end

		if not CollectionService:HasTag(box, IT.BoxTag) then
			return
		end
		-- Already taken and waiting to respawn.
		if box:GetAttribute(Names.TAKEN) then
			return
		end

		-- Rolled server-side so the client can't choose its own item, and
		-- weighted by race position so trailers get better odds.
		local kart = KartService.kartFor(player)
		local place, field = 0, 0
		if kart then
			local order = Standings.order(CollectionService:GetTagged(Names.KART_TAG))
			place, field = Standings.placeOf(order, kart)
		end
		local item = Items.roll(rng, place, field)
		if not item then
			return
		end

		box:SetAttribute(Names.TAKEN, true)
		box.Transparency = 1
		box.CanQuery = false
		itemRemote:FireClient(player, item.Id)

		task.delay(IT.RespawnTime, function()
			if box.Parent then
				box:SetAttribute(Names.TAKEN, false)
				box.Transparency = 0
				box.CanQuery = true
			end
		end)
	end)

	----------------------------------------------------------------
	-- ITEM HITS
	--
	-- A client may never tell another client it was hit — it would be
	-- trivially forgeable. The firing client names a target, the server
	-- relays, and only the TARGET's own client applies the effect.
	----------------------------------------------------------------
	hitRemote = Instance.new("RemoteEvent")
	hitRemote.Name = "KartItemHit"
	hitRemote.Parent = BloxKart

	local feed = Instance.new("RemoteEvent")
	feed.Name = Names.FEED_REMOTE
	feed.Parent = BloxKart
	RaceService.feed = feed

	hitRemote.OnServerEvent:Connect(function(player, targetKart, payload)
		if typeof(targetKart) ~= "Instance" or not targetKart:IsA("Model") then
			return
		end
		if not CollectionService:HasTag(targetKart, Names.KART_TAG) then
			return
		end
		if typeof(payload) ~= "table" then
			return
		end
		-- RATE LIMIT.
		--
		-- This remote was already the thinnest thing between a modified
		-- client and everyone else's simulation — it can name any victim
		-- and stun them. It now also grants XP, which turns spamming it
		-- from griefing into farming, and farming gets automated.
		--
		-- This is a cap, NOT a fix. The real answer is the server owning
		-- which item a player is holding and whether it was fired, which
		-- is the same trust seam the finish time has. Until then this
		-- bounds the damage to roughly what honest play produces.
		local now = os.clock()
		if now - (lastHitAt[player.UserId] or 0) < HIT_COOLDOWN then
			return
		end
		lastHitAt[player.UserId] = now

		-- Never to yourself, whatever the client claims.
		local victimId = targetKart:GetAttribute(Names.OWNER)
		if victimId ~= player.UserId then
			RaceService.relayHit(player.DisplayName, targetKart, payload, player)
		end
	end)

	----------------------------------------------------------------
	-- HAZARDS  (mines)
	--
	-- Server-spawned for two reasons: a client can't be trusted to place
	-- a world object that affects other players, and a dropper who
	-- disconnects shouldn't leave a phantom hazard behind.
	----------------------------------------------------------------
	local hazardRemote = Instance.new("RemoteEvent")
	hazardRemote.Name = "KartHazard"
	hazardRemote.Parent = BloxKart

	hazardRemote.OnServerEvent:Connect(function(player, action, arg, itemId, back, power)
		if action == "drop" then
			-- Racing only, same reason as the boxes. "hit" is deliberately
			-- NOT gated: a hazard left on the track when the round ended
			-- still has to be removable, or it sits there forever.
			if not Match.isDriving(MatchService.phase()) then
				return
			end
			if typeof(arg) ~= "CFrame" or typeof(itemId) ~= "string" then
				return
			end
			-- Appearance and lifetime come from the item module, so adding
			-- a hazard item never means editing this file.
			local item = Items.byId(itemId)
			if not (item and item.Scope == "world" and item.Hazard) then
				return
			end
			RaceService.spawnHazard(player.UserId, arg, item, back, power)
		elseif action == "spill" then
			-- Someone was spun and scattered their stack. Server-spawned for
			-- the same reason hazards are: a client can't be trusted to
			-- create a world object other players can collect, and the
			-- victim disconnecting mid-spin shouldn't leave phantoms.
			if typeof(arg) ~= "CFrame" or typeof(itemId) ~= "table" then
				return
			end
			for i, id in itemId do
				if typeof(id) ~= "string" or i > IT.MaxHeld then
					continue
				end
				local item = Items.byId(id)
				if not item then
					continue
				end

				local drop = Instance.new("Part")
				drop.Name = "Dropped" .. item.Id
				drop.Size = Vector3.one * IT.DropSize
				-- Spread sideways from where they span, so a full stack
				-- doesn't land as one unpickable pile.
				-- All spawned ON the victim and thrown apart, rather than
				-- placed in a tidy row: they were knocked out of a kart, so
				-- they should look like it.
				drop.CFrame = arg
				drop.Anchored = true -- launch() unanchors it
				drop.CanCollide = false
				drop.CanQuery = true -- clients find it with a spatial query
				drop.Transparency = 1 -- the billboard IS the visual
				drop:SetAttribute(Names.DROP_ITEM, item.Id)
				drop.Parent = workspace

				local bb = Instance.new("BillboardGui")
				bb.Size = UDim2.fromScale(IT.DropBillboard, IT.DropBillboard)
				-- LIFTED CLEAR OF THE ROAD.
				--
				-- A BillboardGui is centred on its adornee, and the part it
				-- hangs off sits with its BOTTOM on the tarmac — so half the
				-- icon was below the surface. With AlwaysOnTop false the road
				-- occludes it honestly, which reads as the pickup being sunk
				-- into the ground rather than lying on it.
				--
				-- Offset rather than AlwaysOnTop on purpose: an icon that
				-- draws through walls stops being a thing in the world and
				-- becomes a HUD element that happens to have a position, and
				-- you can no longer tell what is round the next corner.
				bb.StudsOffset = Vector3.new(0, IT.DropLift, 0)
				bb.AlwaysOnTop = false
				bb.LightInfluence = 0
				bb.Parent = drop

				-- Just the icon, floating. No panel behind it: on a track
				-- these sit among scenery and a solid tile reads as a UI
				-- element someone left lying about rather than as a thing
				-- in the world.
				local hasIcon = (item.Icon or "") ~= ""
				if hasIcon then
					local icon = Instance.new("ImageLabel")
					icon.Size = UDim2.fromScale(1, 1)
					icon.BackgroundTransparency = 1
					icon.Image = item.Icon
					icon.Parent = bb
				else
					-- Fallback ONLY when there's no art yet. Without it an
					-- item with no icon would be an invisible pickup, which
					-- is worse than an ugly one.
					local tile = Instance.new("Frame")
					tile.Size = UDim2.fromScale(0.7, 0.7)
					tile.Position = UDim2.fromScale(0.5, 0.5)
					tile.AnchorPoint = Vector2.new(0.5, 0.5)
					tile.BackgroundColor3 = item.Tint or Color3.fromRGB(200, 200, 200)
					tile.BackgroundTransparency = 0.2
					tile.BorderSizePixel = 0
					tile.Parent = bb
					local round = Instance.new("UICorner")
					round.CornerRadius = UDim.new(0.2, 0)
					round.Parent = tile
				end

				-- Fanned across the road, evenly either side of the victim,
				-- so a full stack doesn't land as one unpickable pile.
				local fan = (i - (#itemId + 1) * 0.5) / math.max(#itemId, 1)
				launch(
					drop,
					arg.RightVector * (fan * 2 * IT.DropScatter)
						+ arg.UpVector * IT.DropPop
						-- A little backwards, so they land behind the spinout
						-- rather than in the path of whoever caused it.
						- arg.LookVector * IT.DropScatter * 0.4,
					IT.DropLifetime
				)

				CollectionService:AddTag(drop, IT.DropTag)
				task.delay(IT.DropLifetime, function()
					if drop.Parent then
						drop:Destroy()
					end
				end)
			end
		elseif action == "hit" then
			-- The victim reports driving into it; the server removes it so
			-- it can't be triggered twice.
			if typeof(arg) == "Instance" and arg:IsA("BasePart") and CollectionService:HasTag(arg, IT.HazardTag) then
				-- Read BEFORE destroying, or the attribution goes with it.
				local ownerId = arg:GetAttribute(Names.OWNER)
				local owner = ownerId and Players:GetPlayerByUserId(ownerId)
				RaceService.announce(
					arg:GetAttribute(Names.HAZARD_ITEM),
					if owner then owner.DisplayName else nil,
					player.DisplayName
				)
				arg:Destroy()
			end
		end
	end)

	RunService.Heartbeat:Connect(stepSettling)

	Players.PlayerRemoving:Connect(function(player)
		local kart = KartService.kartFor(player)
		if kart then
			kart:SetAttribute(Standings.ATTRIBUTE, nil)
		end
	end)
end

return RaceService
