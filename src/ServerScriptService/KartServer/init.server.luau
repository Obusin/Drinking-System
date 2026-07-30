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
local WorldFilter = require(ReplicatedStorage.BloxKart.WorldFilter)
local KartService = require(script.KartService)
local MatchService = require(script.MatchService)
local RaceService = require(script.RaceService)
local ProjectileService = require(script.ProjectileService)
local BotService = require(script.BotService)

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
MatchService.onGrid = BotService.fill
