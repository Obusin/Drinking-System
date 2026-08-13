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
	-- CHECKPOINTS ARE RESPAWN ANCHORS. That is all they do.
	--
	-- They used to gate a lap: every gate had to be banked in order
	-- before the finish line counted. That made each one a way to
	-- invalidate a lap you had genuinely driven — miss one because you
	-- were knocked wide, or because it was placed somewhere awkward, and
	-- the lap silently did not count.
	--
	-- Now they only record where to put you back when you fall off. A lap
	-- is proved by distance along the route instead; see LapNeed.
	CheckpointTag = "Checkpoint",

	-- HOW MUCH OF THE ROUTE MUST BE DRIVEN for a line crossing to bank a
	-- lap, as a fraction of the path.
	--
	-- Lenient where the gates were strict — a shortcut still counts,
	-- because a kart game is not a rally scrutineer — and strict exactly
	-- where it matters: reversing back over the line banks no forward
	-- distance at all, so it cannot be farmed.
	LapNeed = 0.8,

	-- HOW CLOSE A LAUNCHER HAS TO BE for a gap in the road to count as a
	-- JUMP rather than a hole.
	--
	-- Without this every jump on the track reports as a fault, and a
	-- check that cries wolf six times is a check you learn to scroll
	-- past. Generous on purpose: a ramp sits at the START of a gap, and
	-- the line can leave the ground a fair way past it.
	RouteJumpLookout = 90,

	-- Biggest single-frame step counted as distance driven, as a fraction
	-- of the path. Anything larger is a respawn, a teleport or the wrap at
	-- the start line — none of which is distance you drove.
	LapStepMax = 0.05,

	-- THE LINE BOTS DRIVE, separate from the gates that prove a lap.
	--
	-- Checkpoints are VALIDATION geometry: placed to be impossible to
	-- miss, so they are wide, sparse, and routinely hang over the edge of
	-- the road. That makes them a poor driving line, and it is most of
	-- why bots looked stupid — they were following the officiating rather
	-- than the road.
	--
	-- Tag parts with this to describe where to actually drive. Ordered by
	-- the same `Order` attribute, with the same trailing-digits fallback,
	-- and it supports forks the same way: two parts sharing an Order is a
	-- split, and each bot commits to one side.
	--
	-- Put down as many as you like — more nodes is a smoother line, and
	-- unlike a checkpoint there is no cost to a dense one.
	--
	-- Leave none tagged and bots fall back to the checkpoints, so an
	-- existing track keeps working untouched.
	-- NOTE: this is the authoritative route now — progress, standings and
	-- the bots all read it, not just bots. The name is kept because the
	-- map is already tagged with it; it is referenced from exactly this
	-- one place, so renaming it later is a one-line change here.
	BotPathTag = "BotPath",

	-- HOW FAR EITHER SIDE OF THE LAST KNOWN POSITION `nearestU` LOOKS,
	-- in node units. Only used when a caller passes a hint.
	--
	-- A global search takes the nearest point on the WHOLE lap, and on a
	-- big track the line passes near itself — a hairpin, a bridge, two
	-- straights side by side. The winner flips to a distant stretch, `u`
	-- jumps, the bot turns to chase it, the flip reverses, and it goes in
	-- circles. It was never orbiting a node; it was oscillating between
	-- two equally valid answers.
	--
	-- 1.5 nodes is comfortably more than anything can travel in a frame
	-- and far less than the distance to a different part of the circuit.
	RouteSearchSpan = 1.5,
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

	TotalLaps = 2,

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

	-- How far below a checkpoint to look for the road when building the
	-- racing line. A gate volume's centre floats above the tarmac, and a
	-- line built from those centres hangs in the air — which reads as a
	-- permanent corner to anything measuring how much the road bends.
	RouteDropProbe = 40,

	-- ROAD WIDTH, felt for with rays sideways from the racing line.
	--
	-- NOT taken from the checkpoint volumes. That was the first attempt
	-- and it's wrong on any real track: gates get drawn generously so
	-- nobody squeezes past one, so they hang out over the void at exactly
	-- the corners where being wrong is fatal. It told bots there was
	-- tarmac where there was nothing.
	--
	-- Measured once per checkpoint and cached with the rest of the node,
	-- so the ray cost is paid at track load and never again.
	RouteEdgeStep = 2, -- studs between samples going outward. Smaller is a
	-- finer edge and more rays; 2 is well under a kart's width
	RouteMaxHalfWidth = 60, -- stop looking past this. Only a ceiling on
	-- the search, not a claim about your track
	RouteEdgeProbeUp = 6, -- start each probe this far above the road, so a
	-- kerb or a slight rise doesn't read as a gap
	RouteEdgeDrop = 30, -- and look this far down
	RouteEdgeStepDrop = 5, -- a surface further than this BELOW the road is
	-- a different surface. This is what makes a ledge with ground far
	-- underneath read as a fall rather than as more road

	-- Node units either side of a point when measuring how tightly the
	-- road turns there. Too small and it reads the spline's own wobble as
	-- a corner; too large and it averages a real corner away.
	RouteCurvatureSpan = 0.35,

	-- Used where nothing could be measured — no route, or a probe that
	-- found nothing at all. Set it to roughly your track's half-width.
	RouteDefaultHalfWidth = 18,
	RouteMinHalfWidth = 6, -- never trust a measurement tighter than a kart

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
	-- Seconds of continuous wrong way before the game puts you back.
	--
	-- WHY NOT JUST FORGIVE MISSED CHECKPOINTS. A percentage allowance —
	-- "you may skip 10% of them" — turns into a shortcut budget the
	-- moment anyone works out WHICH gate is skippable, and then the
	-- fastest line is the one that spends it. It is also invisible: you
	-- cannot see how much allowance you have left, so it never reads as a
	-- rule, only as the game being inconsistent about laps.
	--
	-- The problem was never that checkpoints are strict. It is that a
	-- player who misses one has no idea and no way back. So: keep the
	-- rule, say what happened, and recover them if they clearly cannot.
	--
	-- Long, and much longer than the warning. Driving backwards briefly
	-- is legitimate — turning around after an overshoot, doubling back
	-- for an item, catching a spin — and yanking someone out of any of
	-- those is worse than the problem it solves.
	LostTime = 5,

	WrongWaySpeed = 15, -- studs/s. Below this you're probably reversing
	-- out of a wall on purpose and don't need telling.

	-- Prints the checkpoint table to Output once at startup: how many
	-- parts, what order each resolved to, and a loud warning if they all
	-- collapsed into one. Leave it on while building a track.
	Debug = false,

	-- Placeholder convenience: with no RaceStart tagged anywhere, start
	-- the clock as soon as you're moving, so the HUD can be tested
	-- before a track exists.
	AutoStartOnMove = true,
	AutoStartSpeed = 5,
}
