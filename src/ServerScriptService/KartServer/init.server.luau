--[[
	KartServer — THE server script.
	--------------------------------------------------------------------
	Single Script Architecture: this is the only Script on the server.
	Everything else is a ModuleScript underneath it, started from here in
	a deliberate order.

		KartServer (Script)
		├── KartService        lifecycle: spawn, own, seat, respawn
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

local KartService = require(script.KartService)
local MatchService = require(script.MatchService)
local RaceService = require(script.RaceService)
local ProjectileService = require(script.ProjectileService)

KartService.start()
-- After KartService: MatchService counts the karts it owns to decide
-- whether there are enough racers to start.
MatchService.start()
RaceService.start()
-- After RaceService: it waits on the KartItemHit remote that one makes.
ProjectileService.start()
