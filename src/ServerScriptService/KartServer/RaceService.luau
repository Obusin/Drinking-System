--[[
	RaceService — relays race progress so every client can see the field.

	Clients may own responsive local simulation, but the server projects every
	live kart onto the authored route, banks valid laps at the finish line, and
	writes the replicated standings attributes. Clients never submit a score.
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
local Route = require(BloxKart:WaitForChild("Route"))
local Names = require(BloxKart:WaitForChild("Names"))
local Config = require(BloxKart:WaitForChild("Config"))
-- For the settle probe: it has to ignore karts, characters and every
-- other trigger volume, which is exactly what this list already is.
local WorldFilter = require(BloxKart:WaitForChild("WorldFilter"))
local TagZones = require(BloxKart:WaitForChild("TagZones"))
local Match = require(BloxKart:WaitForChild("Match"))
local Items = require(BloxKart:WaitForChild("Items"))
local MatchService = require(script.Parent.MatchService)
local KartService = require(script.Parent.KartService)
local Progress = require(script.Parent.Progress)

local RaceService = {}

local remote: RemoteEvent
local itemRemote: RemoteEvent
local hitRemote: RemoteEvent
local overtakeRemote: RemoteEvent
local liveStandingsRemote: RemoteEvent

-- Ranking is a server concern. Client-side CollectionService only contains
-- what that client has streamed in, which made an eight-kart field look like
-- 0/0 as distant bots unloaded. Publish the complete answer onto every live
-- kart; each owner always has their own kart streamed in and can read it.
-- A tenth of a second keeps an overtake feeling live without turning eight
-- route projections into per-frame work. More importantly, humans and bots
-- are sampled on this one schedule instead of bots publishing their own
-- intermediate estimate between server ticks.
local STANDINGS_INTERVAL = 0.10
local standingsAt = 0
local lastPlace: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local lastLiveStandingsKey = ""
local lastLiveStandings = {}
local lastLiveField = 0
-- Last local projection per kart. A nearby-window projection prevents a
-- bridge/hairpin from stealing a racer onto the wrong lap section; a large
-- miss below deliberately reacquires globally after a respawn or recovery.
local lastRouteU: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local lastSpotlightAt: { [number]: number } = {}
local SPOTLIGHT_COOLDOWN = 1.1
local ROUTE_REACQUIRE_DISTANCE = 70
-- Authoritative lap state. Client reports used to supply this bank, which
-- meant a forged score could turn into forged laps even after within-lap
-- distance moved server-side.
local serverLap: { [Model]: { laps: number, lapU: number, lastU: number?, inEnd: boolean } } = setmetatable({}, { __mode = "k" }) :: any
local endZone = TagZones.new(Config.Race.EndTag, {
	forceQueryable = Config.Race.ForceQueryable,
	maxParts = Config.Race.CheckpointMaxOverlap,
})

local function projectedRouteU(kart: Model, path): number
	local body = kart.PrimaryPart
	if not body or #path == 0 then
		return 0
	end

	local prior = lastRouteU[kart]
	local u = Route.nearestU(body.Position, path, prior)
	local point = Route.pointAt(u, nil, path)
	-- A window is exactly what protects parallel roads and overpasses, but it
	-- cannot recover after a reset when the old window is on the other side of
	-- the map. Reacquire only when the local answer is plainly not near this
	-- kart, rather than making every ordinary frame vulnerable to a crossover.
	if prior and (not point or (point - body.Position).Magnitude > ROUTE_REACQUIRE_DISTANCE) then
		u = Route.nearestU(body.Position, path)
	end
	lastRouteU[kart] = u
	return u
end

local function authoritativeLap(kart: Model, path): number
	local body = kart.PrimaryPart
	if not body or #path == 0 then
		return 0
	end
	local state = serverLap[kart]
	if not state then
		state = { laps = 0, lapU = 0, lastU = nil, inEnd = false }
		serverLap[kart] = state
	end
	if MatchService.phase() ~= Match.Phase.Racing then
		state.laps, state.lapU, state.lastU, state.inEnd = 0, 0, nil, false
		lastRouteU[kart] = nil
		return 0
	end

	local u = projectedRouteU(kart, path)
	local nodes = #path
	if state.lastU then
		local step = u - state.lastU
		if step < -nodes * 0.5 then
			step += nodes -- ordinary wrap at node zero
		end
		-- Teleports, recoveries and crossovers are not route distance driven.
		if step > 0 and step < nodes * Config.Race.LapStepMax then
			state.lapU += step
		end
	end
	state.lastU = u

	local inEnd = #endZone:Overlapping(body.CFrame, body.Size) > 0
	if inEnd and not state.inEnd and state.lapU >= nodes * Config.Race.LapNeed then
		state.laps += 1
		state.lapU = 0
	end
	state.inEnd = inEnd
	return state.laps
end

function RaceService.canFinish(kart: Model): boolean
	if MatchService.phase() ~= Match.Phase.Racing then
		return false
	end
	local path = Route.path()
	if #path == 0 then
		return false -- an authored race needs a route to be securely officiated
	end
	return authoritativeLap(kart, path) >= MatchService.laps()
end

local function publishStandings(now: number)
	local entries = {}
	local path = Route.path()
	for _, kart in KartService.allKarts() do
		if kart and kart.Parent then
			local score = kart:GetAttribute(Standings.ATTRIBUTE)
			-- The server owns BOTH the completed-lap bank and within-lap
			-- distance. The client remote remains for compatibility with older
			-- clients but has no authority over standings.
			if not kart:GetAttribute(Match.FINISH_PLACE) and #path > 0 then
				local laps = authoritativeLap(kart, path)
				score = Standings.routeScore(laps, projectedRouteU(kart, path), path)
				kart:SetAttribute(Standings.ATTRIBUTE, score)
			end
			table.insert(entries, {
				kart = kart,
				finish = kart:GetAttribute(Match.FINISH_PLACE),
				score = score,
				grid = kart:GetAttribute(Match.GRID_SLOT),
			})
		end
	end

	table.sort(entries, function(a, b)
		-- A crossed finish line is final. A finished P1 must stay ahead of
		-- a fast but still-running racer, even if the latter's route score
		-- happens to be numerically greater after a late report.
		local aFinished = type(a.finish) == "number"
		local bFinished = type(b.finish) == "number"
		if aFinished ~= bFinished then
			return aFinished
		end
		if aFinished and a.finish ~= b.finish then
			return a.finish < b.finish
		end

		local aScore = if type(a.score) == "number" then a.score else 0
		local bScore = if type(b.score) == "number" then b.score else 0
		if aScore ~= bScore then
			return aScore > bScore
		end

		-- During the grid countdown every score is zero. Grid slot makes
		-- that otherwise arbitrary tie stable and understandable.
		local aGrid = if type(a.grid) == "number" then a.grid else math.huge
		local bGrid = if type(b.grid) == "number" then b.grid else math.huge
		if aGrid ~= bGrid then
			return aGrid < bGrid
		end
		return a.kart.Name < b.kart.Name
	end)

	local field = #entries
	-- The local client cannot reliably enumerate a streamed-out field, so the
	-- server sends one compact, authoritative top-five snapshot. It is sent
	-- only when names/ranks/field size change, not every standings tick.
	local top = {}
	local signature = tostring(field)
	for place = 1, math.min(5, field) do
		local entry = entries[place]
		local kart = entry.kart
		local ownerId = kart:GetAttribute(Names.OWNER)
		local name = tostring(kart:GetAttribute(Names.RACER_NAME) or kart.Name)
		local id = if typeof(ownerId) == "number" then "u:" .. ownerId else "k:" .. kart.Name
		top[place] = { place = place, id = id, name = name, userId = ownerId }
		signature ..= "|" .. id
	end
	if liveStandingsRemote and signature ~= lastLiveStandingsKey then
		lastLiveStandingsKey = signature
		lastLiveStandings = top
		lastLiveField = field
		liveStandingsRemote:FireAllClients(top, field)
	end

	for place, entry in entries do
		local kart = entry.kart
		local was = lastPlace[kart]
		lastPlace[kart] = place
		if kart:GetAttribute(Standings.PLACE_ATTRIBUTE) ~= place then
			kart:SetAttribute(Standings.PLACE_ATTRIBUTE, place)
		end
		if kart:GetAttribute(Standings.FIELD_ATTRIBUTE) ~= field then
			kart:SetAttribute(Standings.FIELD_ATTRIBUTE, field)
		end

		-- The server sees the full field, unlike a streamed client. Tell
		-- only the affected player who moved relative to them; a card is
		-- feedback, never gameplay authority.
		local ownerId = kart:GetAttribute(Names.OWNER)
		if
			was
			and was ~= place
			and type(ownerId) == "number"
			and MatchService.phase() == Match.Phase.Racing
			and now - (lastSpotlightAt[ownerId] or 0) >= SPOTLIGHT_COOLDOWN
		then
			local opponent = entries[if place > was then place - 1 else place + 1]
			local player = Players:GetPlayerByUserId(ownerId)
			if opponent and player and overtakeRemote then
				lastSpotlightAt[ownerId] = now
				overtakeRemote:FireClient(player, {
					kind = if place > was then "overtaken" else "passed",
					from = was,
					to = place,
					opponent = {
						name = opponent.kart:GetAttribute(Names.RACER_NAME) or opponent.kart.Name,
						userId = opponent.kart:GetAttribute(Names.OWNER),
					},
				})
			end
		end
	end
end

-- "X hit Y with Z", to everyone. A hit is a spectacle: half the value of
-- a well-timed missile is the lobby seeing it land, and in a race you
-- rarely even see the person you hit.
--
-- Server-side because only the server knows both ends — the attacker's
-- client can't be trusted to name its own victim, and the victim's client
-- doesn't know who fired.
-- Names rather than Players, because a bot has no Player object and the
-- feed shouldn't care which kind of racer landed the hit.
function RaceService.announce(
	itemId: string?,
	byName: string?,
	victimName: string?,
	victimKart: Model?,
	byUserId: number?
)
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
		byUserId = byUserId,
		victim = victimName,
		victimUserId = victimKart and victimKart:GetAttribute(Names.OWNER),
		-- WHERE it happened, so every client can hear it. The feed
		-- already reaches everybody; it was carrying the news and not
		-- the noise. An Instance replicates fine and the client reads a
		-- live position off it, which is better than a stale one baked
		-- in here.
		kart = victimKart,
		id = itemId,
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

-- WHO LAST HIT EACH KART, AND WHEN. Server time.
--
-- This is the whole basis of the elimination tally: falling in the void
-- is nobody's doing normally, and somebody's if they put you there.
-- Kept here because this is the one place every hit passes through,
-- whoever threw it and whoever caught it.
--
-- Keyed by the kart rather than by a player, because a bot can be
-- knocked into the void too and a bot has no account. Weak keys: a
-- destroyed kart must not hold itself alive through this table.
local lastHit: { [Model]: any } = setmetatable({}, { __mode = "k" }) :: any

function RaceService.noteHit(kart: Model, byPlayer: Player?, byName: string?, itemId: string?)
	lastHit[kart] = {
		at = workspace:GetServerTimeNow(),
		byPlayer = byPlayer,
		byName = byName,
		item = itemId,
	}
end

-- Somebody fell in the void. Credit whoever put them there, if anyone
-- did and recently enough.
--
-- NOBODY IS REMOVED FROM THE RACE. The victim respawns at their last
-- checkpoint exactly as they always have — this awards a tally and some
-- XP to the attacker and nothing else. Returns true if a credit was
-- given, purely so callers can avoid announcing twice.
function RaceService.creditVoidKill(kart: Model, victimName: string): boolean
	local hit = lastHit[kart]
	if not hit then
		return false
	end
	if workspace:GetServerTimeNow() - hit.at > Config.Match.EliminationWindow then
		return false
	end
	-- Consumed, so one fall cannot be credited twice — a respawn that
	-- drops straight back into the void would otherwise pay again.
	lastHit[kart] = nil

	-- A bot can land the hit. It earns no XP, because it has no account,
	-- but it still gets its name on the line.
	if hit.byPlayer then
		Progress.eliminated(hit.byPlayer)
	end
	RaceService.announce(
		hit.item or Config.Match.EliminationText,
		hit.byName,
		victimName,
		kart,
		if hit.byPlayer then hit.byPlayer.UserId else nil
	)
	return true
end

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
	local windUp = math.clamp(tonumber(payload.windUp) or 0, 0, 3)
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

	-- A takedown is a hit that actually costs the victim time. Note it
	-- against the KART: if this racer ends up in the void in the next few
	-- seconds, that is an elimination rather than a respawn.
	local takedown = effect.spin > 0 or effect.stun > 0
	if takedown then
		RaceService.noteHit(targetKart, byPlayer, byName, tostring(effect.item))
	end
	-- Never pay for hitting yourself. A mine you drove into is still a
	-- hit for the feed; it is not an achievement.
	if byPlayer and byPlayer ~= victim then
		Progress.hit(byPlayer, takedown)
	end

	if victim then
		RaceService.announce(
			tostring(effect.item),
			byName,
			victim.DisplayName,
			targetKart,
			if byPlayer then byPlayer.UserId else nil
		)
		if windUp > 0 then
			-- TOLD FIRST, HIT SECOND. The warning is the whole reason the
			-- wind-up exists, so it goes out now and the effect follows.
			-- Sent as its own message rather than as a flag on the hit,
			-- because the hit has not happened yet and a client that
			-- treats it as one would spin early.
			hitRemote:FireClient(victim, { warn = effect.item, in_ = windUp })
			task.delay(windUp, function()
				-- Re-checked: a round can end, or the kart can leave the
				-- world, inside a second.
				if victim.Parent and targetKart.Parent then
					hitRemote:FireClient(victim, effect)
				end
			end)
		else
			-- Only the victim's own client applies it, same rule as always.
			hitRemote:FireClient(victim, effect)
		end
		return
	end

	if RaceService.onNonPlayerHit then
		-- Bots have no client to warn, so the wind-up is just a delay for
		-- them. Applied all the same, or a bot would be hit before the
		-- player it is racing beside.
		if windUp > 0 then
			task.delay(windUp, function()
				if targetKart.Parent and RaceService.onNonPlayerHit then
					local n = RaceService.onNonPlayerHit(targetKart, effect)
					if n then
						RaceService.announce(
							tostring(effect.item),
							byName,
							n,
							targetKart,
							if byPlayer then byPlayer.UserId else nil
						)
					end
				end
			end)
			return
		end
		local name = RaceService.onNonPlayerHit(targetKart, effect)
		if name then
			RaceService.announce(
				tostring(effect.item),
				byName,
				name,
				targetKart,
				if byPlayer then byPlayer.UserId else nil
			)
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
		-- Both RECURSIVE: the folder because a Package nests it a level
		-- deeper, the model because art gets filed inside the folder too.
		local folder = ServerStorage:FindFirstChild(IT.HazardModelFolder, true)
		local template = folder and folder:FindFirstChild(spec.Model, true)
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

	overtakeRemote = Instance.new("RemoteEvent")
	overtakeRemote.Name = Names.OVERTAKE_REMOTE
	overtakeRemote.Parent = BloxKart

	liveStandingsRemote = Instance.new("RemoteEvent")
	liveStandingsRemote.Name = Names.LIVE_STANDINGS_REMOTE
	liveStandingsRemote.Parent = BloxKart
	-- A late joiner must receive the current order even if nobody changes
	-- place after their listener connects.
	Players.PlayerAdded:Connect(function(player)
		if lastLiveField > 0 then
			liveStandingsRemote:FireClient(player, lastLiveStandings, lastLiveField)
		end
	end)
	liveStandingsRemote.OnServerEvent:Connect(function(player)
		if lastLiveField > 0 then
			liveStandingsRemote:FireClient(player, lastLiveStandings, lastLiveField)
		end
	end)

	remote.OnServerEvent:Connect(function(player, _score)
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

		-- Intentionally ignored. Scores are refreshed from server-visible
		-- kart positions in publishStandings; accepting this payload would
		-- re-open a placement and reward exploit.
	end)

	-- MatchService owns finish places and rewards; RaceService owns the
	-- route proof. A hook avoids a circular require in the other direction.
	MatchService.canFinish = RaceService.canFinish

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
		if not MatchService.itemsLive() then
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
				if item.Id == "Rainbow" then
					player:SetAttribute(Names.RAINBOW_HELD, (player:GetAttribute(Names.RAINBOW_HELD) or 0) + 1)
				end
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
		if item.Id == "Rainbow" then
			player:SetAttribute(Names.RAINBOW_HELD, (player:GetAttribute(Names.RAINBOW_HELD) or 0) + 1)
		end
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

	--==============================================================
	--  THE HORN. Cosmetic, and still rate-limited.
	--
	--  It takes NO PAYLOAD. The client says "I honked" and nothing
	--  else — there is nothing it could tell us that we would
	--  believe, and the kart position everyone needs is already
	--  replicated. The server supplies the player, so a client cannot
	--  honk as somebody else.
	--
	--  THE COOLDOWN IS THE POINT. This is a broadcast that any client
	--  can trigger, which is the shape of every audio-spam vector
	--  there is. The client has its own shorter cooldown for feel;
	--  that one is a courtesy and this one is the defence.
	--
	--  Rebroadcast to EVERYONE INCLUDING THE SENDER is deliberately
	--  avoided — the sender already played it locally the instant
	--  they pressed, so echoing it back would double it a round-trip
	--  later.
	--==============================================================
	--==============================================================
	--  THE BOT PATH IS A LINE, NOT GEOMETRY.
	--
	--  `Triggers.TAGS` already keeps these out of the kart's movement
	--  sweep and out of Route's own ground probes. That is enough for
	--  karts and it is NOT enough for everything else: a player on
	--  foot, a dropped item, or any raycast that does not use the
	--  shared exclude list still sees a solid part.
	--
	--  And unlike a checkpoint there is every reason to place these
	--  densely — a smooth line wants a lot of them — so leaving them
	--  solid litters the road with invisible walls.
	--
	--  Forced here rather than left to the author, because "remember to
	--  untick CanCollide on all sixty of them" is not a workflow.
	--  Transparency is deliberately NOT touched: whether you can see
	--  your own path while building is your call.
	--==============================================================
	local function tamePath(part: Instance)
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanTouch = false
			-- CanQuery is the flag that actually hides it from raycasts;
			-- CanCollide only stops things resting on it. Route finds
			-- these by TAG, never by ray, so nothing here needs it.
			part.CanQuery = false
			part.Anchored = true
			part.CastShadow = false
		end
	end
	for _, part in CollectionService:GetTagged(Config.Race.BotPathTag) do
		tamePath(part)
	end
	CollectionService:GetInstanceAddedSignal(Config.Race.BotPathTag):Connect(tamePath)

	local horn = Instance.new("RemoteEvent")
	horn.Name = Names.HORN_REMOTE
	horn.Parent = BloxKart
	local hornAt: { [Player]: number } = {}
	horn.OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		if now < (hornAt[player] or 0) then
			return
		end
		hornAt[player] = now + Config.Audio.HornServerCooldown
		for _, other in Players:GetPlayers() do
			if other ~= player then
				horn:FireClient(other, player)
			end
		end
	end)
	-- Or the table grows by one entry per player who ever joined.
	Players.PlayerRemoving:Connect(function(player)
		hornAt[player] = nil
	end)

	-- "I fell in the void." No payload: there is nothing the client
	-- could tell us that we would believe, and everything the credit
	-- needs is already here. The client respawns itself either way — it
	-- is not asking permission, it is reporting.
	local voidRemote = Instance.new("RemoteEvent")
	voidRemote.Name = Match.VOID_REMOTE
	voidRemote.Parent = BloxKart
	voidRemote.OnServerEvent:Connect(function(player)
		local kart = KartService.kartFor(player)
		if kart then
			RaceService.creditVoidKill(kart, player.DisplayName)
		end
	end)

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
			if not MatchService.itemsLive() then
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
					player.DisplayName,
					KartService.kartFor(player),
					ownerId
				)
				arg:Destroy()
			end
		end
	end)

	RunService.Heartbeat:Connect(stepSettling)
	RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		if now >= standingsAt then
			standingsAt = now + STANDINGS_INTERVAL
			publishStandings(now)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local kart = KartService.kartFor(player)
		if kart then
			kart:SetAttribute(Standings.ATTRIBUTE, nil)
			kart:SetAttribute(Standings.PLACE_ATTRIBUTE, nil)
			kart:SetAttribute(Standings.FIELD_ATTRIBUTE, nil)
		end
		lastSpotlightAt[player.UserId] = nil
	end)
end

return RaceService
