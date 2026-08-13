--[[
	Triggers — "which parts in the world are volumes rather than geometry".

	One source of truth, shared by everything that casts a ray through the
	world:

	  WorldFilter (client)        kart movement and ground probes
	  ProjectileService (server)  missile wall tests

	WHY SHARED
	----------
	This list used to live only in WorldFilter. The server's missile
	filter excluded karts and characters and nothing else, so a missile
	detonated on the first checkpoint zone it flew through — while every
	client, using the fuller filter, drew it sailing straight on. A
	desynced explosion is bad; a desynced explosion caused by two
	copies of "what counts as a wall" is worse, because fixing one copy
	looks like fixing the bug.

	Tags come from Config, so adding a trigger tag anywhere can't leave it
	behaving as a wall in one of these places and not the other.

	THE TrackSurface EXCEPTION
	--------------------------
	A part may be both a trigger and road — tagging the road itself
	`Checkpoint` is a supported way to build a track. Those carry
	`Race.SurfaceTag` and are deliberately NOT excluded: they're geometry,
	and a missile should hit them exactly like any other wall or floor.
--]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("BloxKart"):WaitForChild("Config"))

local Triggers = {}

-- Read from config rather than typed out, so a new trigger tag is
-- automatically excluded everywhere.
local function tagList(): { string }
	local tags = {
		Config.Items.BoxTag,
		Config.Items.HazardTag,
		Config.Race.StartTag,
		Config.Race.EndTag,
		Config.Race.CheckpointTag,
		-- THE BOT PATH. Purely a line to drive — nothing ever touches one,
		-- and unlike a checkpoint there is no reason to place it sparsely,
		-- so a dense path would otherwise litter the road with invisible
		-- walls the karts would grind along.
		--
		-- Excluded from the movement SWEEP here. It stays queryable, like
		-- the glide ramps below, because Route finds these with an
		-- explicit include-filter tag query — which is a different thing
		-- from being solid.
		Config.Race.BotPathTag,
		Config.Respawn.VoidTag,

		-- GLIDE RAMPS AND LANDING ZONES. Both are markers, not geometry:
		-- a ramp says "launch here" and a landing zone says "aim there".
		-- Neither should ever be something the kart can hit, so they go in
		-- the same exclusion list as every other trigger.
		--
		-- They stay QUERYABLE, which matters — the glide check below finds
		-- ramps with an explicit include-filter query. This list excludes
		-- them from the movement SWEEP, which is a different thing.
		Config.Glide.RampTag,
		Config.Glide.LandTag,

		-- WATER. A marker for "you are in the wet", never geometry — the
		-- thing the kart drives on is a floor at the waterline, which is
		-- ordinary road as far as the controller is concerned.
		Config.Swim.ZoneTag,

		-- Flip ramps. A launcher, not a wall.
		Config.Trick.RampTag,

		-- PROPS. Scenery you can knock over, and the reason it belongs
		-- HERE rather than being disarmed by the client module that
		-- animates it:
		--
		-- CanQuery is what decides whether the movement sweep sees a
		-- part, and the Props module sets it false when it adopts one.
		-- But that only helps if that module ran, on that machine, before
		-- you drove into the cone — so a client that failed to load it,
		-- and the SERVER simulating bots, both still saw solid walls.
		--
		-- This list is the project's answer to "invisible to movement",
		-- it is shared by the client sweep and the server's missile
		-- filter, and it is live via Triggers.watch. Excluding props here
		-- means a prop can never be a wall for anybody, whatever else
		-- does or does not happen.
		Config.Props.Tag,
	}
	for _, pad in Config.Boosters.Pads do
		if typeof(pad) == "table" and typeof(pad.Tag) == "string" then
			table.insert(tags, pad.Tag)
		end
	end
	return tags
end

Triggers.TAGS = tagList()
Triggers.SURFACE_TAG = Config.Race.SurfaceTag

-- Every part that should be invisible to a world query, right now.
--
-- Rebuilt on demand rather than cached: the callers already rebuild their
-- filters on tag changes, and hazards appear and vanish mid-race.
function Triggers.collect(into: { Instance }?): { Instance }
	local out = into or {}
	for _, tag in Triggers.TAGS do
		for _, part in CollectionService:GetTagged(tag) do
			-- Also road? Then it's geometry, and geometry stays.
			if not CollectionService:HasTag(part, Triggers.SURFACE_TAG) then
				table.insert(out, part)
			end
		end
	end
	return out
end

-- Connect `fn` to every signal that can change the answer. Returns the
-- connections so the caller can drop them.
function Triggers.watch(fn: () -> ()): { RBXScriptConnection }
	local conns = {}
	for _, tag in Triggers.TAGS do
		table.insert(conns, CollectionService:GetInstanceAddedSignal(tag):Connect(fn))
		table.insert(conns, CollectionService:GetInstanceRemovedSignal(tag):Connect(fn))
	end
	-- The surface marker too, so tagging a road as track while playtesting
	-- takes effect immediately rather than next reload.
	table.insert(conns, CollectionService:GetInstanceAddedSignal(Triggers.SURFACE_TAG):Connect(fn))
	table.insert(conns, CollectionService:GetInstanceRemovedSignal(Triggers.SURFACE_TAG):Connect(fn))
	return conns
end

return Triggers
