--[[
	WorldFilter — the shared "what counts as world geometry" filter.

	Our movement is entirely query-based (Blockcast, Raycast,
	GetPartBoundsInBox), so in multiplayer the thing that stops karts
	colliding isn't a collision group — it's this. Another racer's kart
	or body must never register as a wall or as ground.

	Excludes every tagged kart and every player's character, kept in
	sync as people join, leave and respawn. One shared pair of params
	because only one kart is ever simulated on a given client.

	TRIGGERS ARE EXCLUDED TOO
	-------------------------
	Every trigger volume has to be CanQuery = true or a spatial query
	can't detect it. But CanQuery is also what makes something solid to
	OUR movement, because the sweep is a query — so a power-up box, a
	checkpoint gate or a void slab would each act as an invisible wall and
	shove the kart.

	Detection is unaffected: TagZones carries its own Include-filtered
	params, so a part can be excluded here and still register there. The
	two uses are deliberately separate objects for exactly this reason.

	...UNLESS IT'S ALSO TRACK  (Race.SurfaceTag)
	--------------------------------------------
	A part is allowed to be both a trigger and drivable ground. Tagging
	the road itself `Checkpoint` is a reasonable way to build a track — no
	invisible gates to place, and road segments are already in order. But
	excluding it would delete the road from the kart's world and drop it
	through the floor, which looks nothing like a checkpoint problem.

	So that case opts IN, by carrying `TrackSurface` as well.

	This was briefly inferred from CanCollide instead, on the theory that
	"solid in Studio means solid to the kart" needed no new setup. That
	was wrong: a fresh Part defaults to CanCollide = true, so every zone
	volume anyone created silently became an invisible wall to bump into.
	An explicit tag means the DEFAULT is always the safe one, and the
	surprising behaviour is the one you have to ask for.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Triggers = require(ReplicatedStorage:WaitForChild("BloxKart"):WaitForChild("Triggers"))

local KART_TAG = "Kart"

local WorldFilter = {}

WorldFilter.rayParams = RaycastParams.new()
WorldFilter.rayParams.FilterType = Enum.RaycastFilterType.Exclude

WorldFilter.overlapParams = OverlapParams.new()
WorldFilter.overlapParams.FilterType = Enum.RaycastFilterType.Exclude
WorldFilter.overlapParams.MaxParts = 4

local excluded = {}

local function rebuild()
	table.clear(excluded)
	for _, kart in CollectionService:GetTagged(KART_TAG) do
		table.insert(excluded, kart)
	end
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(excluded, plr.Character)
		end
	end
	-- Triggers: detectable by TagZones, invisible to movement — unless
	-- they've opted in as track surface, in which case they're road and
	-- have to stay. Shared with the server's missile filter; see Triggers
	-- for why that matters and why this is a tag and not CanCollide.
	Triggers.collect(excluded)
	WorldFilter.rayParams.FilterDescendantsInstances = excluded
	WorldFilter.overlapParams.FilterDescendantsInstances = excluded
end

local started = false

function WorldFilter.start()
	if started then
		return
	end
	started = true

	CollectionService:GetInstanceAddedSignal(KART_TAG):Connect(rebuild)
	CollectionService:GetInstanceRemovedSignal(KART_TAG):Connect(rebuild)

	-- Hazards are spawned and destroyed mid-race, so this has to be live
	-- rather than gathered once at startup.
	Triggers.watch(rebuild)

	local function watch(plr: Player)
		plr.CharacterAdded:Connect(rebuild)
		plr.CharacterRemoving:Connect(rebuild)
	end
	Players.PlayerAdded:Connect(function(plr)
		watch(plr)
		rebuild()
	end)
	Players.PlayerRemoving:Connect(rebuild)
	for _, plr in Players:GetPlayers() do
		watch(plr)
	end

	rebuild()
end

return WorldFilter
