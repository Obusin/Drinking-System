--[[
	KartServer — THE server script.
	--------------------------------------------------------------------
	Single Script Architecture: this is the only Script on the server.
	Everything else is a ModuleScript underneath it, started from here in
	a deliberate order.

		KartServer (Script)
		├── KartService        lifecycle: spawn, own, seat, respawn
		├── BotService         AI racers, so a lobby is never empty
		├── MatchService       the round loop: grid, countdown, results
		├── RaceService        progress relay, item boxes, hazards
		├── ProjectileService  homing missiles
		├── KartFactory        assembles the kart model
		├── SteeringWheel      the Motor6D wheel assembly
		├── PlaceholderVisual  stand-in art
		└── Placement          SpawnLocation + start-line maths

	Tunables all live in ReplicatedStorage.BloxKart.Config.

	To add a system: write a module here, require it below, start it.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Names = require(ReplicatedStorage.BloxKart.Names)
local Place = require(ReplicatedStorage.BloxKart.Place)
local WorldFilter = require(ReplicatedStorage.BloxKart.WorldFilter)
local Assets = require(script.Assets)
local Skins = require(script.Skins)
local KartService = require(script.KartService)
local MatchService = require(script.MatchService)
local RaceService = require(script.RaceService)
local ProjectileService = require(script.ProjectileService)
local BotService = require(script.BotService)
local Progress = require(script.Progress)
local Ledger = require(script.Ledger)
local DataService = require(script.DataService)
local GarageService = require(script.GarageService)
local QuestService = require(script.QuestService)
local PlayerVehicleService = require(script.PlayerVehicleService)
local QueueService = require(script.QueueService)
local ReturnService = require(script.ReturnService)

-- FIRST OF ALL: say what this is. Before any service starts, so a
-- server that dies on startup still tells you which code died — and so
-- two places can be compared without reading either of them.
local B = require(ReplicatedStorage.BloxKart.Config).Build
if B.Announce then
	print(("[BloxKart] %s (%s) — %s place, id %d"):format(B.Version, B.Note, Place.role():upper(), game.PlaceId))
end

-- FIRST, before anything queries the world.
--
-- This is what makes a kart pass through other karts and through trigger
-- volumes: movement here is query-based, so the exclusion list IS the
-- collision rule. The client has always started it. The server hadn't,
-- which meant bots ran their movement against an EMPTY filter — every
-- other kart and every checkpoint registered as solid geometry.
--
-- That was one root cause wearing two hats: bots bumping each other, and
-- bots wedging on checkpoints. They share Simulation with players, so
-- they were only ever going to behave differently where the world they
-- were shown differed.
WorldFilter.start()

-- BEFORE ANY CLIENT CAN DRAW. Copies the authored rocket out of
-- ServerStorage into ReplicatedStorage, because ServerStorage is
-- server-only and missiles are drawn by each client locally. A client
-- that loads before this simply gets the fallback part for its first
-- missile, so earlier is better and this is as early as it gets.
Assets.start()

KartService.start()

-- IS THERE A RACE HERE?
--
-- The lobby runs this same script, and the difference is smaller than it
-- first looks: TWO services, the round loop and the AI.
--
-- Items stay ON in the lobby. A hub with karts and no power-ups is a
-- driving demo; the practice ring is where you learn what a missile
-- feels like, and none of that needs a round. RaceService and
-- ProjectileService are happy without one — the only thing they asked
-- MatchService was "may items be used", and that question now has a
-- lobby answer.
--
-- Lap timing comes along with RaceService and does nothing, because a
-- hub has no checkpoints tagged. That is the right kind of nothing: it
-- costs a few idle connections and it means the practice ring works the
-- day somebody DOES tag one.
local racing = Place.isRace()

if racing then
	-- Before RaceService: MatchService counts the karts KartService owns
	-- to decide whether there are enough racers to start.
	MatchService.start()
end

RaceService.start()
-- After RaceService: it waits on the KartItemHit remote that one makes.
ProjectileService.start()

if racing then
	-- Last: bots need every service they drive through to exist first, and
	-- they fill the grid on the match's cue rather than at startup.
	BotService.start()
	-- The way BACK. Its own module because the round loop should not
	-- need to know the lobby exists any more than it needs to know bots
	-- do — MatchService just fires onResults and does not care who is
	-- listening.
	ReturnService.start()
else
	print("[KartServer] LOBBY — karts and items, no round loop and no bots.")
	-- After KartService, because it drives it. Policy only: KartService
	-- still owns how a kart is built and seated, and this owns whether
	-- somebody may ask for one.
	PlayerVehicleService.start()
	-- The way out of the hub. A teleport today, matchmaking later, and
	-- the seam is the same either way.
	QueueService.start()
end

-- Last, and only a probe: cycles a kart mesh to establish whether a skin
-- can be an asset id rather than a separate model. Rig.SkinTest = false
-- turns it off.
-- Knockable scenery. Runs in BOTH places — a hub with cones is as much
-- fun as a track with them, and it needs no round loop.
local PropService = require(script.PropService)
PropService.start()

Skins.start()
-- History first. Nothing here persists yet, but a record cannot be
-- written retroactively, so the recording goes in before the thing it
-- records does.
Ledger.start()
-- Profiles. Gated by Config.Data.Enabled and mocked in Studio, so this
-- is safe to leave wired while the trust seams are still open.
DataService.start()
-- After DataService: it subscribes to onLoaded to push each player their
-- equipped loadout as soon as their profile is up.
GarageService.start()

-- EQUIPPING HAS TO REACH THE KART, not just the profile.
--
-- A hook rather than a require, same shape as the missile relay below:
-- KartService already requires GarageService, so GarageService cannot
-- require it back. Wired here because this is the file that knows both
-- exist.
--
-- Without it, equipping wrote the profile and stopped there — the kart
-- you were sitting in kept its old bodywork until something destroyed
-- and rebuilt it, which reads exactly like the garage not saving.
GarageService.onEquipped = KartService.redressFor

QuestService.start()

-- DEVELOPER CONSOLE. Last, deliberately: its inspectors read KartService,
-- BotService and MatchService, and starting before them would capture a
-- half-built server. It creates its own remotes and is inert for anyone
-- not on the roster — see ServerScriptService/KartServer/DeveloperConsole.
local DevConsoleService = require(script.DeveloperConsole.DevConsoleService)
DevConsoleService.start()

-- The wiring BETWEEN the race services. Gated with them rather than
-- left assigned unconditionally: the assignment itself is harmless in a
-- lobby, and a hook that is set but can never fire is a lie the next
-- person reading this has to disprove.
if racing then
	MatchService.onGrid = BotService.onGrid
	-- A finished player's kart is handed to the AI for the rest of the
	-- round, and handed back before the next grid. Hooks rather than
	-- requires, so MatchService never learns BotService exists.
	MatchService.onFinished = function(kart, who)
		BotService.takeOver(kart, who .. " (AI)")
	end
	-- The flag: every kart still driven by a person carries on without
	-- them, so the results play over a moving track.
	--
	-- COMPOSED, not assigned twice — onResults is single-subscriber, so
	-- the second assignment would silently replace the first rather than
	-- add to it. This is the one hook two unrelated systems both need,
	-- which is exactly the shape SYSTEM.md §4b flags as the reason an
	-- event bus is coming; until then, composing by hand here.
	MatchService.onResults = function()
		BotService.takeOverAll()
		ReturnService.onResults()
	end
	MatchService.onRelease = function()
		BotService.releaseTakeOvers()
	end

	-- A hit on a kart with no Player behind it goes to the bots. A hook
	-- rather than a require: RaceService is upstream of BotService and
	-- shouldn't have to know it exists.
	RaceService.onNonPlayerHit = BotService.applyHit
	-- A missile inside hopping range of a bot. Hooks rather than
	-- requires: ProjectileService is upstream of BotService and should
	-- not learn it exists — the same reason the hit relay works this way.
	ProjectileService.onMissileNear = BotService.missileNear
	ProjectileService.onMissileGone = BotService.missileGone
end

-- XP as it is earned, so a hit is worth something visibly rather than
-- only on the results screen ten laps later.
local xpRemote = Instance.new("RemoteEvent")
xpRemote.Name = Names.XP_REMOTE
xpRemote.Parent = ReplicatedStorage.BloxKart
Progress.onAward = function(player, info)
	xpRemote:FireClient(player, info)
end

-- The client's driving counters for the race just finished. Clamped in
-- Progress.report against Config.Level.StatCaps — see Tally for why the
-- client is the one reporting and what that costs.
local statsRemote = Instance.new("RemoteEvent")
statsRemote.Name = Names.STATS_REMOTE
statsRemote.Parent = ReplicatedStorage.BloxKart
statsRemote.OnServerEvent:Connect(function(player, batch)
	Progress.report(player, batch)
end)

