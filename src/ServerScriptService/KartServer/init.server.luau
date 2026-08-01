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
local QuestService = require(script.QuestService)

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
-- After KartService: MatchService counts the karts it owns to decide
-- whether there are enough racers to start.
MatchService.start()
RaceService.start()
-- After RaceService: it waits on the KartItemHit remote that one makes.
ProjectileService.start()

-- Last: bots need every service they drive through to exist first, and
-- they fill the grid on the match's cue rather than at startup.
BotService.start()

-- Last, and only a probe: cycles a kart mesh to establish whether a skin
-- can be an asset id rather than a separate model. Rig.SkinTest = false
-- turns it off.
Skins.start()
-- History first. Nothing here persists yet, but a record cannot be
-- written retroactively, so the recording goes in before the thing it
-- records does.
Ledger.start()
-- Profiles. Gated by Config.Data.Enabled and mocked in Studio, so this
-- is safe to leave wired while the trust seams are still open.
DataService.start()
QuestService.start()
MatchService.onGrid = BotService.onGrid
-- A finished player's kart is handed to the AI for the rest of the
-- round, and handed back before the next grid. Hooks rather than
-- requires, so MatchService never learns BotService exists.
MatchService.onFinished = function(kart, who)
	BotService.takeOver(kart, who .. " (AI)")
end
-- The flag: every kart still driven by a person carries on without
-- them, so the results play over a moving track.
MatchService.onResults = BotService.takeOverAll
MatchService.onRelease = function()
	BotService.releaseTakeOvers()
end
-- A kart leaving the world, by either route. The AI is unhooked FIRST:
-- a bot stepping a Simulation against a destroyed model is a stream of
-- errors rather than a visible bug.
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

-- A hit on a kart with no Player behind it goes to the bots. A hook
-- rather than a require: RaceService is upstream of BotService and
-- shouldn't have to know it exists.
RaceService.onNonPlayerHit = BotService.applyHit
-- A missile inside hopping range of a bot. Hooks rather than requires:
-- ProjectileService is upstream of BotService and should not learn it
-- exists — the same reason the hit relay works this way.
ProjectileService.onMissileNear = BotService.missileNear
ProjectileService.onMissileGone = BotService.missileGone

