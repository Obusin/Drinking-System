--[[
	Inspect — read-only adapter: server state and player state.

	Everything here is a READ. Nothing in this module changes anything,
	which is why it needs no rate limiting of its own beyond the router's
	and why a `viewer` may use all of it.

	"UNAVAILABLE" IS AN ANSWER.
	---------------------------
	Where the server genuinely does not know something — item slots, most
	notably, because they live on the client — this reports the string
	"unavailable" rather than a zero or an empty table. A console that
	invents a plausible value is worse than one that admits ignorance:
	the invented value is indistinguishable from a real one, so the first
	time it disagrees with the game nobody knows which to believe.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart.Config)
local Names = require(BloxKart.Names)
local Place = require(BloxKart.Place)
local Standings = require(BloxKart.Standings)

local KartService = require(script.Parent.Parent.Parent.KartService)
local DevRegistry = require(script.Parent.Parent.DevRegistry)

local RIG = Config.Rig

local Inspect = {}

local startedAt = os.clock()

-- Optional at require time: MatchService and BotService only exist in a
-- race place, and requiring them unconditionally would break the console
-- in the lobby — where most of it is still useful.
local function tryRequire(name: string): any?
	local parent = script.Parent.Parent.Parent
	local module = parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	return if ok then result else nil
end

function Inspect.server(): { [string]: any }
	local players = Players:GetPlayers()
	local match = tryRequire("MatchService")
	local bots = tryRequire("BotService")

	local phase = "unavailable"
	if match and type(match.phase) == "function" then
		local ok, value = pcall(match.phase)
		phase = if ok then tostring(value) else "unavailable"
	end

	local botCount: any = "unavailable"
	if bots and type(bots.all) == "function" then
		local ok, all = pcall(bots.all)
		if ok and type(all) == "table" then
			local n = 0
			for _ in all do
				n += 1
			end
			botCount = n
		end
	end

	return {
		placeId = game.PlaceId,
		jobId = game.JobId,
		-- PrivateServerId is empty on a public server. Reported as the
		-- boolean AND the raw fields, because "is this private" is the
		-- question and the ids are the evidence.
		isPrivate = game.PrivateServerId ~= "",
		privateServerId = game.PrivateServerId,
		privateServerOwnerId = game.PrivateServerOwnerId,
		isStudio = RunService:IsStudio(),
		place = if Place.isLobby() then "lobby" else "race",
		uptimeSeconds = math.floor(os.clock() - startedAt),
		playerCount = #players,
		maxPlayers = Players.MaxPlayers,
		kartCount = #CollectionService:GetTagged(Names.KART_TAG),
		aiCount = botCount,
		devAiCount = DevRegistry.count("ai"),
		devPickupCount = DevRegistry.count("pickup"),
		matchPhase = phase,
	}
end

-- The list, deliberately thin: enough to choose somebody, no more. The
-- expensive per-player detail is only gathered for the one selected.
function Inspect.playerList(): { any }
	local out = {}
	for _, player in Players:GetPlayers() do
		table.insert(out, {
			userId = player.UserId,
			name = player.Name,
			displayName = player.DisplayName,
			hasKart = KartService.kartFor(player) ~= nil,
		})
	end
	table.sort(out, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
	return out
end

function Inspect.player(userId: number): { [string]: any }?
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return nil
	end

	local kart = KartService.kartFor(player)
	local hitbox = kart and kart.PrimaryPart

	local identity = {
		userId = player.UserId,
		name = player.Name,
		displayName = player.DisplayName,
		accountAge = player.AccountAge,
		-- Roblox reports ping in ms via this stat; guarded because it is
		-- not present in every context.
		ping = (function()
			local ok, value = pcall(function()
				return player:GetNetworkPing() * 1000
			end)
			return if ok then math.floor(value) else "unavailable"
		end)(),
	}

	-- KART. The server has position and velocity because it owns the
	-- model, but NOT drift/boost/nitro — those live in the client's
	-- Simulation and are never replicated as state.
	local kartInfo: { [string]: any } = { present = kart ~= nil }
	if kart then
		kartInfo.name = kart.Name
		kartInfo.owner = kart:GetAttribute(Names.OWNER)
		kartInfo.aiDriven = kart:GetAttribute(Names.AI_DRIVEN) == true
		if hitbox then
			local v = hitbox.AssemblyLinearVelocity
			kartInfo.speed = math.floor(v.Magnitude * 10) / 10
			kartInfo.position = {
				x = math.floor(hitbox.Position.X),
				y = math.floor(hitbox.Position.Y),
				z = math.floor(hitbox.Position.Z),
			}
		end
		-- Stated, not omitted: a blank field reads as a bug, whereas
		-- "unavailable" reads as a boundary. See the module note.
		kartInfo.driftState = "unavailable (client-owned)"
		kartInfo.nitro = "unavailable (client-owned)"
		kartInfo.boostState = "unavailable (client-owned)"
	end

	-- RACE. Placement comes from the same Standings the game uses, so
	-- the console cannot disagree with the scoreboard.
	local race: { [string]: any } = {}
	if kart then
		local ok, order = pcall(function()
			return Standings.order(CollectionService:GetTagged(Names.KART_TAG))
		end)
		if ok and order then
			local place, field = Standings.placeOf(order, kart)
			race.place = place
			race.fieldSize = field
		end
	end
	race.lap = "unavailable (client-owned)"
	race.checkpoint = "unavailable (client-owned)"

	return {
		identity = identity,
		kart = kartInfo,
		race = race,
		-- The honest answer. Item slots are held by KartClient/Items and
		-- never sent to the server, so there is nothing here to report.
		-- See docs/developer-console/POWERUP_INTEGRATION.md.
		items = { slots = "unavailable (client-owned)", maxHeld = Config.Items.MaxHeld },
	}
end

-- WHAT THE SERVER WANTS THIS KART TO WEAR vs WHAT IT ACTUALLY HAS.
--
-- This is the panel that would have ended the skinning saga in one run
-- instead of five. Every failure in that chain was a NAME that did not
-- match a part, and nothing anywhere could show those two lists side by
-- side — so a wrong name, a wrong class and a profile that never loaded
-- all looked identical from the driver's seat.
--
-- Reports the ASKED-FOR names, the parts that actually exist with their
-- class, and the intersection. `missing` is the answer to "why is my
-- kart not changing".
function Inspect.dressing(userId: number): { [string]: any }?
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return nil
	end
	local kart = KartService.kartFor(player)
	if not kart then
		return { hasKart = false }
	end

	local GarageService = require(script.Parent.Parent.Parent.GarageService)
	local look = GarageService.lookFor(player) or {}
	local paint = GarageService.paintFor(player)

	local asked, hit, miss = {}, {}, {}
	for name in look do
		table.insert(asked, name)
	end
	table.sort(asked)
	for _, name in asked do
		local part = kart:FindFirstChild(name, true)
		-- A part that exists but is NOT a MeshPart can never take a mesh.
		-- Reported distinctly, because it needs an art fix rather than a
		-- config fix and the two are otherwise indistinguishable.
		if part and part:IsA("MeshPart") then
			table.insert(hit, name)
		elseif part then
			table.insert(miss, ("%s<%s — not a MeshPart>"):format(name, part.ClassName))
		else
			table.insert(miss, name)
		end
	end

	-- Everything actually on the kart, so a name that belongs in
	-- Config.Rig can be read straight off this panel.
	local meshParts, painted = {}, {}
	for _, d in kart:GetDescendants() do
		if d:IsA("MeshPart") then
			table.insert(meshParts, d.Name)
		end
		if d:IsA("BasePart") and table.find(RIG.PaintParts, d.Name) then
			table.insert(painted, ("%s=%d,%d,%d"):format(
				d.Name,
				math.floor(d.Color.R * 255),
				math.floor(d.Color.G * 255),
				math.floor(d.Color.B * 255)
			))
		end
	end
	table.sort(meshParts)

	return {
		hasKart = true,
		kart = kart:GetFullName(),
		asked = asked,
		matched = hit,
		missing = miss,
		meshParts = meshParts,
		paintWanted = if paint
			then ("%d,%d,%d"):format(
				math.floor(paint.R * 255),
				math.floor(paint.G * 255),
				math.floor(paint.B * 255)
			)
			else "factory",
		paintActual = painted,
	}
end

return Inspect
