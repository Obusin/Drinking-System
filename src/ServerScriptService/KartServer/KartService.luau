--[[
	KartService — kart lifecycle: spawn, claim, ownership, lock-in,
	respawn.

	OWNERSHIP
	---------
	The hitbox is anchored while idle so it just sits there, and
	unanchored while driven — a client can only replicate CFrame changes
	on a part it owns, and it can't own an anchored one.
--]]

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.BloxKart.Config)
local Names = require(ReplicatedStorage.BloxKart.Names)
local Util = require(ReplicatedStorage.BloxKart.Util)
local Match = require(ReplicatedStorage.BloxKart.Match)
local KartFactory = require(script.Parent.KartFactory)
local Placement = require(script.Parent.Placement)

local RIG = Config.Rig
local log = Util.logger("KartService", RIG.Debug)

local KartService = {}

-- Keyed by RACER, not by Player: a bot is a plain table with a Name, and
-- everything here only ever needed a unique key and a name. Widening the
-- type was most of what bots cost this file.
export type Racer = Player | { Name: string, Bot: true }

-- MUST be a type check, not `racer.Bot`.
--
-- Roblox Instances THROW on unknown property access, so reading `.Bot`
-- off a real Player errors rather than returning nil — which took out
-- the whole spawn path for actual players the moment bots existed.
local function isBot(racer: any): boolean
	return typeof(racer) == "table" and racer.Bot == true
end

local karts: { [any]: Model } = {}
local slots: { [any]: number } = {}

-- Lowest free grid slot, so a leaver's position is reused rather than
-- pushing the next joiner another row back. Slot decides both grid
-- position and colour, so recycling keeps the field tidy.
local function takeSlot(player: any): number
	if slots[player] then
		return slots[player]
	end
	local used = {}
	for _, s in slots do
		used[s] = true
	end
	local i = 0
	while used[i] do
		i += 1
	end
	slots[player] = i
	return i
end

-- Built at server start, before anyone joins, so spawning never depends
-- on the player/character/seat chain. The first player claims it.
local unclaimed: Model? = nil

--=====================================================================
--  COLLISION
--
--  Karts pass through each other, and so do the racers sitting in
--  them. Bumping is a physics problem we don't need — and since our
--  movement is query-based, two karts colliding would fight the
--  kinematic controller rather than push each other cleanly.
--=====================================================================
local function setupCollisionGroup()
	local ok = pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(RIG.CollisionGroup) then
			PhysicsService:RegisterCollisionGroup(RIG.CollisionGroup)
		end
		PhysicsService:CollisionGroupSetCollidable(RIG.CollisionGroup, RIG.CollisionGroup, false)
	end)
	if not ok then
		warn("[KartService] could not set up collision group " .. RIG.CollisionGroup)
	end
end

-- Names anything that could still make two karts touch.
--
-- Karts are meant to pass through each other completely: the hitbox is
-- CanCollide false, every part is put in a collision group that is set
-- non-collidable with itself, and Simulation's movement queries exclude
-- every tagged kart. On paper there is no path left.
--
-- "On paper" is why this exists. Reading the code three times and
-- concluding it cannot happen is not evidence, and a part that slipped
-- out of the group — art added after the sweep, a model welded on later,
-- a mesh that arrived with CanCollide on — would produce exactly the
-- bumping being reported while every line still looks correct.
--
-- So it reports rather than argues, and it names the part.
function KartService.auditCollisions()
	local bad = {}
	for _, kart in CollectionService:GetTagged(KartFactory.TAG) do
		for _, d in kart:GetDescendants() do
			if d:IsA("BasePart") and d.CanCollide and d.CollisionGroup ~= RIG.CollisionGroup then
				table.insert(bad, ("%s (group %q)"):format(d:GetFullName(), d.CollisionGroup))
			end
		end
	end
	if #bad > 0 then
		warn(
			("[KartService] %d kart part(s) can still collide with the world outside the %q group — this is what makes karts bump: %s"):format(
				#bad,
				RIG.CollisionGroup,
				table.concat(bad, ", ")
			)
		)
	end
	return bad
end

-- A seated racer's limbs are still collidable, so two karts passing
-- close would knock their drivers together. Move the whole character
-- into the kart group while they're aboard.
local function setCharacterGroup(character: Model?, group: string)
	if not character then
		return
	end
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CollisionGroup = group
		end
	end
end

--=====================================================================
--  OWNERSHIP
--=====================================================================
-- `botKart` karts are excluded from the anchoring entirely.
--
-- This used to anchor the hitbox whenever the occupant wasn't a Player —
-- which a bot's driver never is. So the instant a bot's rig sat down,
-- this fired, found no player, and anchored the kart wherever it
-- happened to be at that moment. Mid-air, usually. That was the floating.
--
-- The anchoring exists so an EMPTY kart sits still instead of drifting
-- off. A bot's kart is never empty and never idle: BotService writes its
-- CFrame every frame and owns its position outright.
local function bindOwnership(kart: Model, botKart: boolean?)
	local seat = kart:FindFirstChild("Seat") :: VehicleSeat
	local hitbox = kart.PrimaryPart :: BasePart

	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if botKart then
			return
		end
		local occupant = seat.Occupant
		local driver = occupant and Players:GetPlayerFromCharacter(occupant.Parent)

		if driver then
			hitbox.Anchored = false
			setCharacterGroup(driver.Character, RIG.CollisionGroup)
			local ok, err = pcall(function()
				hitbox:SetNetworkOwner(driver)
			end)
			if not ok then
				warn("[KartService] Could not set network owner: " .. tostring(err))
			end
		else
			hitbox.AssemblyLinearVelocity = Vector3.zero
			hitbox.AssemblyAngularVelocity = Vector3.zero
			hitbox.Anchored = true
		end

		log("%s %s %s", driver and driver.Name or "nobody", occupant and "got into" or "left", kart.Name)
	end)
end

--=====================================================================
--  SPAWNING
--=====================================================================
-- Which art this player gets. Cosmetic only — see Rig.VisualByPlayer.
--
-- Case-insensitive, because a username that differs only in case here is
-- the sort of thing you stare straight past.
local function visualFor(player: any?): string?
	if not player then
		return nil
	end
	-- Bots get whatever the config says, so they show up in the new kart
	-- alongside you rather than in the placeholder.
	if isBot(player) then
		return RIG.BotVisual ~= "" and RIG.BotVisual or nil
	end
	for name, visual in RIG.VisualByPlayer do
		if name:lower() == player.Name:lower() then
			return visual
		end
	end
	-- Studio names its test players Player1/Player2, so nothing above can
	-- ever match in a local server test. See Rig.StudioVisual.
	if RunService:IsStudio() and RIG.StudioVisual ~= "" then
		return RIG.StudioVisual
	end
	return nil
end

local function createKart(name: string, slot: number, player: any?): Model
	local pad = Placement.findSpawn()
	if pad then
		log("spawn pad: %s at %s", pad:GetFullName(), tostring(pad.Position))
	else
		warn(("[KartService] No SpawnLocation in Workspace — using fallback at %s.")
			:format(tostring(RIG.FallbackCF.Position)))
	end

	local wanted = visualFor(player)
	-- Printed for every kart, so "the bot isn't in the same kart as me"
	-- is a thing you read rather than infer. Two lines, same name = same
	-- art; different names = the lookup, not the model.
	log(
		"%s -> visual %q%s",
		if player then player.Name else "start-line kart",
		wanted or RIG.VisualName,
		if isBot(player) then " (bot)" else ""
	)
	local kart = KartFactory.build(KartFactory.colorFor(slot), wanted)
	kart.Name = name
	kart:PivotTo(Placement.cframeFor(pad, slot))
	kart.Parent = workspace
	bindOwnership(kart, isBot(player))
	log("built %s at %s", kart.Name, tostring(kart:GetPivot().Position))
	return kart
end

--=====================================================================
--  SEATING  (non-test mode: players are locked in)
--=====================================================================
local function seatPlayer(player: Player, kart: Model)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = kart:FindFirstChild("Seat") :: VehicleSeat?
	if not (humanoid and seat and humanoid.Health > 0) then
		log("seat FAILED for %s", player.Name)
		return
	end
	humanoid.JumpHeight = 0
	humanoid.JumpPower = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	seat:Sit(humanoid)
	log("seated %s", player.Name)
end

-- Treats an empty seat as an escape attempt.
local function bindLockIn(player: Player, kart: Model)
	local seat = kart:FindFirstChild("Seat") :: VehicleSeat
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if seat.Occupant or karts[player] ~= kart then
			return
		end
		task.wait(RIG.ReseatDelay)
		if karts[player] == kart and player.Parent then
			seatPlayer(player, kart)
		end
	end)
end

local function spawnKartFor(player: Player)
	local existing = karts[player]
	if existing then
		karts[player] = nil
		existing:Destroy()
	end

	local slot = takeSlot(player)

	local kart
	-- The start-line kart was built before anyone joined, so it carries
	-- the DEFAULT art. A player with their own visual can't inherit it or
	-- they'd silently get the placeholder — and since the first player to
	-- join is always slot 0, that would be almost every test.
	local ownArt = visualFor(player) ~= nil

	if unclaimed and unclaimed.Parent and slot == 0 and not ownArt then
		-- Only slot 0 can inherit the start-line kart; it was built in
		-- slot 0's colour and position.
		kart = unclaimed
		unclaimed = nil
		kart.Name = player.Name .. "_Kart"
	else
		kart = createKart(player.Name .. "_Kart", slot, player)
	end
	log("%s -> slot %d", player.Name, slot)

	-- Stamped so RaceService can map a reporting player to their kart
	-- without keeping a second table in sync.
	kart:SetAttribute(Names.OWNER, player.UserId)
	karts[player] = kart
	bindLockIn(player, kart)
	seatPlayer(player, kart)
end

local function onCharacterAdded(player: Player, character: Model)
	character:WaitForChild("Humanoid", 10)
	task.wait(RIG.SeatDelay)
	-- An error in here would otherwise die quietly inside the connection
	-- coroutine and look exactly like "the car doesn't spawn".
	local ok, err = pcall(spawnKartFor, player)
	if not ok then
		warn("[KartService] spawnKartFor FAILED: " .. tostring(err))
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

--=====================================================================
--  ROSTER  (read by MatchService)
--=====================================================================
-- Adds a bot racer and its kart. The caller keeps the returned racer
-- handle; everything else here treats it exactly like a player.
function KartService.addBot(name: string): (any, Model)
	local racer = { Name = name, Bot = true }
	local slot = takeSlot(racer)
	local kart = createKart(name .. "_Kart", slot, racer)
	karts[racer] = kart

	-- ANCHORED. One thing may own a part's position, and here that is us.
	--
	-- A player's kart is unanchored because their CLIENT owns it: the
	-- client's Simulation writes the CFrame and Roblox replicates an
	-- owned part smoothly. Exactly one authority.
	--
	-- A bot's kart has no owner. Unanchored, Roblox's physics integrates
	-- it — gravity pulls it down — while the server writes the CFrame
	-- back sixty times a second. Two authorities disagreeing, which looks
	-- like the kart sinking and then snapping back to the racing line.
	-- Writing the velocity too doesn't settle it; it just tells the
	-- engine to argue faster.
	--
	-- Anchored, physics has no opinion. The cost is that replication of an
	-- anchored CFrame isn't interpolated, so motion arrives in steps at
	-- the network rate rather than smoothly. That's a visual limit with a
	-- known fix (draw it client-side, as missiles do) and not two systems
	-- fighting over where a kart is.
	local hitbox = kart.PrimaryPart
	if hitbox then
		hitbox.Anchored = true
	end
	return racer, kart
end

function KartService.removeBots()
	for racer, kart in karts do
		if isBot(racer) then
			karts[racer] = nil
			slots[racer] = nil
			kart:Destroy()
		end
	end
end

function KartService.kartFor(player: any): Model?
	return karts[player]
end

-- The live roster, keyed by player. Returned directly rather than
-- copied: callers only ever read it, and this is polled several times a
-- second.
function KartService.allKarts(): { [Player]: Model }
	return karts
end

-- Stamps each kart with the CFrame it starts the round on.
--
-- The server does NOT move the kart itself. While a player is aboard,
-- the hitbox is network-owned by them, so a server-side PivotTo is
-- overwritten by the client's very next simulation frame. Instead the
-- grid position is published as an attribute and the client's own
-- Simulation:RespawnAt puts it there — the same path used by checkpoint
-- respawns, so there's one way a kart gets teleported, not two.
function KartService.assignGrid()
	local pad = Placement.findSpawn()
	for player, kart in karts do
		local slot = slots[player] or 0
		kart:SetAttribute(Match.GRID_CF, Placement.cframeFor(pad, slot))
	end
end

--=====================================================================
--  RESPAWN
--=====================================================================
local function isLost(kart: Model): boolean
	-- No PrimaryPart means FallenPartsDestroyHeight already ate it.
	local body = kart.PrimaryPart
	return not body or body.Position.Y < RIG.RespawnBelow
end

--=====================================================================
--  START
--=====================================================================
function KartService.start()
	log("starting")
	setupCollisionGroup()

	-- TEST MODE ONLY. This is the spare kart that sits on the pad waiting
	-- to be walked into.
	--
	-- It used to be built unconditionally — the comment said "so there is
	-- always something to drive even if the player wiring breaks", which
	-- made sense before players were seated automatically. Now it just
	-- leaves a kart nobody drives parked on the spawn for the whole
	-- round: it takes a grid colour, it sits in the middle of the start
	-- line, and anything that looks for karts finds it.
	if RIG.TestMode then
		local ok, err = pcall(function()
			unclaimed = createKart("Kart", 0)
		end)
		if not ok then
			warn("[KartService] could not build the start-line kart: " .. tostring(err))
		end
	end

	if RIG.TestMode then
		log("TEST MODE — kart is on the pad, walk into it. E to get out.")
	else
		Players.PlayerAdded:Connect(onPlayerAdded)
		for _, player in Players:GetPlayers() do
			task.spawn(onPlayerAdded, player)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		local kart = karts[player]
		karts[player] = nil
		slots[player] = nil
		if kart then
			kart:Destroy()
		end
	end)

	-- Fell off the world? Rebuild it on the pad.
	-- Collected first, then respawned: spawnKartFor mutates `karts`, and
	-- mutating a table mid-iteration is undefined in Luau.
	--=================================================================
	--  NETWORK OWNERSHIP WATCHDOG
	--
	--  "I'm driving but everyone else sees me parked" is this, every
	--  time. A player's kart is unanchored and their CLIENT writes the
	--  CFrame — which only replicates to anyone else if that client
	--  actually OWNS the part. Without ownership the server keeps
	--  authority, the client's writes stay local, and the driver has a
	--  perfectly normal race that nobody else can see.
	--
	--  Ownership is granted once, from the Occupant signal. Once is not
	--  enough: SetNetworkOwner can throw (it already has a pcall around
	--  it, which means it was expected to), the signal can land while a
	--  character is still assembling, and Roblox reclaims ownership by
	--  itself when a part sleeps or is repositioned by the server.
	--  Any of those leaves a player stranded for the rest of the round
	--  with no error and no way to tell from inside the kart.
	--
	--  So it is re-asserted. Cheap — a comparison per seated player, a
	--  couple of times a second — and it converts a race-ruining desync
	--  into a hiccup nobody notices.
	--=================================================================
	task.spawn(function()
		while true do
			task.wait(RIG.OwnershipCheck)
			for racer, kart in karts do
				if isBot(racer) then
					continue
				end
				local hitbox = kart.PrimaryPart
				local seat = kart:FindFirstChild("Seat") :: VehicleSeat?
				if not (hitbox and seat and seat.Occupant and not hitbox.Anchored) then
					continue
				end
				local driver = Players:GetPlayerFromCharacter(seat.Occupant.Parent)
				if not driver then
					continue
				end
				local ok, owner = pcall(function()
					return hitbox:GetNetworkOwner()
				end)
				if ok and owner ~= driver then
					local set = pcall(function()
						hitbox:SetNetworkOwner(driver)
					end)
					-- Loud, because this should be rare. If it repeats for
					-- one player every few seconds, something is taking
					-- ownership back and that is the real bug.
					warn(
						("[KartService] %s did not own their own kart (owner was %s) — reassigned%s. They would have been driving on their screen only."):format(
							driver.Name,
							owner and owner.Name or "the server",
							if set then "" else " BUT THE REASSIGN FAILED"
						)
					)
				end
			end
		end
	end)

	-- Delayed: karts, bots and their art all stream in, and auditing on
	-- the first frame reports a world that isn't built yet.
	task.delay(RIG.CollisionAuditDelay, KartService.auditCollisions)

	RunService.Heartbeat:Connect(function()
		-- Only ever non-nil in TestMode now, so this rebuild can't
		-- resurrect the spare kart in a normal round.
		if unclaimed and isLost(unclaimed) then
			unclaimed:Destroy()
			unclaimed = createKart("Kart", 0)
		end

		local fallen
		for racer, kart in karts do
			-- Bots excluded: this path re-seats a character, and a bot has
			-- none. BotService puts its own back on the road — it already
			-- knows where the racing line is.
			if not isBot(racer) and isLost(kart) then
				fallen = fallen or {}
				table.insert(fallen, racer)
			end
		end
		if fallen then
			for _, player in fallen do
				spawnKartFor(player)
			end
		end
	end)
end

return KartService
