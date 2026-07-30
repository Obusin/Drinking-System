--[[
	Race — lap timing and validation.

	Tag parts in Studio's Tag Editor. Like the boost pads they're meant
	to be CanCollide = false: you drive through them.

	  RaceStart   crossing it starts the clock
	  RaceEnd     crossing it banks a lap, IF the lap was valid
	  Checkpoint  must all be passed, in order, for a lap to count

	START AND END ON THE SAME PART
	------------------------------
	Normal for a circuit — tag one part with both. The first crossing
	starts the race without also banking a lap, and checkpoints stop the
	same line counting twice.

	CHECKPOINT ORDER  ← the one that bites
	----------------
	Set an `Order` attribute (a number) on each checkpoint part in the
	Properties panel. Failing that, a trailing number in the part's name
	is used, so `Checkpoint3` works without any attribute.

	Gaps are fine — 10, 20, 30 sorts the same as 1, 2, 3.

	⚠️ Checkpoints with NO number and NO attribute all count as order 0,
	which collapses them into a single checkpoint — so only the first one
	you touch registers and the rest do nothing. Either number them or
	name them `Checkpoint1`, `Checkpoint2`… The Output window says so
	loudly at startup if this happens.

	WHICH WAY IS FORWARD
	--------------------
	Respawns face down the track using the trigger part's own rotation,
	so a part has to be aimed. `CheckpointFacing` below picks WHICH of
	its axes counts as forward, named after Studio's move-handle arrow
	colours — so you can just look at the selected part and match it.
--]]

return {
	StartTag = "RaceStart",
	EndTag = "RaceEnd",
	CheckpointTag = "Checkpoint",
	CheckpointOrderAttribute = "Order",

	-- Which of a race trigger's own axes points DOWN THE TRACK, named
	-- after the move-handle arrows in Studio:
	--
	--   "X" / "-X"   the RED arrows
	--   "Y" / "-Y"   the GREEN arrows (up — almost never what you want)
	--   "Z" / "-Z"   the BLUE arrows
	--
	-- Applies to checkpoints and the start line, because it would be
	-- baffling if they disagreed. Get it wrong and respawns drop you
	-- sideways across the road.
	--
	-- Unsigned means the POSITIVE axis. "-Z" is the part's front face,
	-- which is what Roblox itself calls LookVector.
	CheckpointFacing = "X",

	TotalLaps = 3,

	-- With no checkpoints tagged anywhere, this is the only thing
	-- stopping a finish line double-counting, so it's enforced. Once
	-- checkpoints exist they're the real validation and this is ignored
	-- — otherwise a short track could never register a lap.
	MinLapTime = 5,

	TriggerCooldown = 1.0, -- per-part retrigger guard (start/end lines;
	-- checkpoints don't use it — the order sequence is their guard)

	-- How many checkpoint parts may overlap the kart at once. Straddling
	-- a seam between two road segments is 2; the headroom is for wide
	-- gates built from several parts.
	CheckpointMaxOverlap = 8,

	ForceQueryable = true,

	-- Tag a trigger part with this AS WELL as its own tag to say "this is
	-- also track you drive ON", and it stays solid to the kart.
	--
	-- Only needed for the unusual case of making the ROAD itself a
	-- checkpoint. A normal invisible gate volume wants nothing to do with
	-- it — leave it untagged and the kart passes straight through, which
	-- is what you want 99% of the time.
	--
	-- This used to be inferred from CanCollide, which was a mistake: a
	-- fresh Part defaults to CanCollide = true, so every zone anyone
	-- created became an invisible wall. Explicit opt-in means the default
	-- is always the safe one.
	SurfaceTag = "TrackSurface",

	--== RACING LINE ===================================================
	-- How curved the missile's route is between checkpoints.
	--
	--   1  full spline — smoothest, but it bows out from the straight
	--      line between checkpoints, and on a tight corner that bow is
	--      what puts it through the scenery
	--   0  straight segments — never strays from checkpoint to
	--      checkpoint, but corners like a tram
	--
	-- This is the real lever on clipping. Deviation is bounded by this
	-- times the spline's own bow, so dropping it is a guaranteed fix
	-- where changing the spline maths is not.
	--
	-- The other lever is MORE CHECKPOINTS: shorter segments bow less, and
	-- they cost nothing but placement.
	RouteTension = 0.75,

	--== WRONG WAY =====================================================
	-- Needs no extra setup: "which way does traffic flow here" is already
	-- stated by CheckpointFacing, so the warning reads the facing of the
	-- checkpoint you're currently in. With the road segments tagged as
	-- checkpoints that's exactly the local road direction.
	--
	-- Dot of your heading against that direction. -1 is straight back up
	-- the track, 0 is perpendicular. Kept well below 0 so a hairpin or a
	-- wide drift never trips it.
	WrongWayDot = -0.35,
	WrongWayTime = 0.7, -- seconds facing the wrong way before it appears.
	-- Long enough to survive a spin, short enough to be useful.
	WrongWaySpeed = 15, -- studs/s. Below this you're probably reversing
	-- out of a wall on purpose and don't need telling.

	-- Prints the checkpoint table to Output once at startup: how many
	-- parts, what order each resolved to, and a loud warning if they all
	-- collapsed into one. Leave it on while building a track.
	Debug = true,

	-- Placeholder convenience: with no RaceStart tagged anywhere, start
	-- the clock as soon as you're moving, so the HUD can be tested
	-- before a track exists.
	AutoStartOnMove = true,
	AutoStartSpeed = 5,
}
