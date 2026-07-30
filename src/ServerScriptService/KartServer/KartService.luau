--[[
	KartService — kart lifecycle: spawn, claim, ownership, lock-in,
	respawn.

	OWNERSHIP
	---------
	The hitbox is anchored while idle so it just sits there, and
	unanchored while driven — a client can only replicate CFrame changes
	on a part it owns, and it can't own an anchored one.
--]]

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
local function bindOwnership(kart: Model)
	local seat = kart:FindFirstChild("Seat") :: VehicleSeat
	local hitbox = kart.PrimaryPart :: BasePart

	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
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
	if player.Bot then
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
	log("%s -> visual %s", if player then player.Name else "start-line kart", wanted or RIG.VisualName)
	local kart = KartFactory.build(KartFactory.colorFor(slot), wanted)
	kart.Name = name
	kart:PivotTo(Placement.cframeFor(pad, slot))
	kart.Parent = workspace
	bindOwnership(kart)
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

	-- Unanchored and server-owned. An anchored part moved from a server
	-- loop replicates as bare position updates with no interpolation —
	-- the same thing that made missiles stutter. Physics-replicated
	-- motion is interpolated for free.
	local hitbox = kart.PrimaryPart
	if hitbox then
		hitbox.Anchored = false
	end
	return racer, kart
end

function KartService.removeBots()
	for racer, kart in karts do
		if racer.Bot then
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

	-- Kart on the pad first, players second. This runs unconditionally,
	-- so there is always something to drive even if the player wiring
	-- breaks.
	local ok, err = pcall(function()
		unclaimed = createKart("Kart", 0)
	end)
	if not ok then
		warn("[KartService] could not build the start-line kart: " .. tostring(err))
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
	RunService.Heartbeat:Connect(function()
		if unclaimed and isLost(unclaimed) then
			unclaimed:Destroy()
			unclaimed = createKart("Kart", 0)
		end

		local fallen
		for player, kart in karts do
			if isLost(kart) then
				fallen = fallen or {}
				table.insert(fallen, player)
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
