--[[
	Handling — everything that decides how the kart MOVES.

	All of it is asset-independent. Nothing in here is measured off the
	art; swap the visual model and the driving is bit-for-bit identical.

	Speeds are studs/s, turn rates rad/s, angles degrees.
--]]

return {
	--== SPEED =========================================================
	-- THE ONE DIAL FOR OVERALL PACE. Was 120, which made a straight over
	-- before you could read the corner at the end of it — and made bots
	-- uncatchable, since a bot on the correct line at full throttle is
	-- only beatable if there is time to catch it.
	--
	-- Nothing else about the handling changed. This is a top speed, not a
	-- physics change: acceleration shape, grip, turn rates and drift all
	-- behave exactly as before, and everything measured as a FRACTION of
	-- top speed (turn rate falloff, the accel curve, bot corner speeds)
	-- rescales with it automatically.
	--
	-- Raise it back toward 120 if the track starts feeling slow; that is
	-- the whole knob.
	MaxSpeed = 95, -- forward top speed
	ReverseSpeed = 32, -- reverse top speed
	Accel = 3.4, -- base approach rate to target speed

	-- ACCELERATION CURVE (the "wave graph")
	--
	-- Multiplies Accel, sampled across your speed. Index 1 = standstill,
	-- last = top speed, interpolated between.
	--
	--   1.0 |          ___
	--       |       __/   \__
	--   0.5 |    __/         \__
	--       | __/               \_
	--   0.0 +---------------------- speed ->
	--
	-- Weak off the line, strongest through the midrange, tapering at the
	-- top. That shape IS the feeling of weight — a kart that leaves the
	-- line hardest and tapers feels light and electric; one that has to
	-- build feels like it has mass.
	--
	-- A flat { 1 } restores the old behaviour exactly.
	AccelCurve = { 0.30, 0.55, 0.85, 1.00, 0.95, 0.70, 0.45 },
	-- launch. A lerp rate, not a force, so it's mass-independent.
	BrakeRate = 5.5, -- approach rate when braking
	CoastRate = 1.1, -- approach rate to 0 when off the throttle

	--== STEERING ======================================================
	--== WEIGHT ========================================================
	-- The kart travels along a `travel` vector that CHASES the nose
	-- rather than being welded to it. That lag IS momentum: turn the
	-- wheel and the kart keeps going where it was going for a moment
	-- before the new heading takes hold.
	--
	-- Set Grip very high and this disappears entirely — the kart moves
	-- exactly where it points, which is what it did before and exactly
	-- why it felt weightless and on-rails.
	--== TYRE LOAD  (drives the screech, not the handling) =============
	-- NOTE: distinct from DriftScrubCurve below, which is SPEED scrub and
	-- does affect handling. Different thing, similar word.
	--
	-- The screech follows how hard the tyres are WORKING, not the slip
	-- angle. Counter-steering to catch a slide REDUCES slip by definition
	-- — you're pointing the nose where the kart already goes — while
	-- loading the tyres harder than anything else you can do. Driving the
	-- sound off slip alone silenced it at exactly the moment the driver
	-- was fighting hardest.
	--
	-- Nothing here affects movement. Only Audio reads the result.
	TyreDriftLoad = 0.55, -- a committed drift is never quiet, whatever
	-- the nose is doing
	TyreCounterLoad = 1.0, -- fighting the slide, scaled by how much lock is
	-- being used. The loudest case there is.
	TyreCornerLoad = 0.45, -- hard cornering at speed while still gripped

	Grip = 9, -- how fast travel catches the nose when gripping.
	-- LOWER = heavier, washes wider into corners
	DriftGrip = 3.5, -- ...and while drifting. Lower still, so a drift
	-- genuinely slides wide before the rotation reels it back in
	MaxSlip = 32, -- degrees travel may lag the nose. Hard cap, so the
	-- kart can never end up driving sideways or backwards

	TurnRate = 2.5, -- rad/s at full lock, low speed
	TurnRateTop = 1.6, -- rad/s at full lock, top speed
	TurnRampSpeed = 14, -- studs/s at which steering reaches full
	-- authority. Stops spinning on the spot.
	-- How fast the steering input LOADS UP versus how fast it UNWINDS.
	-- Deliberately asymmetric: a heavy wheel resists being turned but
	-- self-centres briskly when you let go. Making both slow is what
	-- turns "weighty" into "mushy" — the kart stops answering you.
	--
	-- These control response TIME, not turn radius. For how sharply it
	-- turns once loaded, see TurnRate / TurnRateTop below.
	SteerSmoothing = 7, -- winding lock ON. Lower = heavier
	SteerReturn = 16, -- unwinding back to centre. Keep well above the above

	--== HOP ===========================================================
	HopSpeed = 18, -- upward studs/s on the hop
	Gravity = 150, -- OUR gravity, not Roblox's. Lower = floatier hops.
	-- Roblox's 196 feels heavy for a kart.
	HopMinSpeed = 8, -- below this the hop is cosmetic
	HopMinAir = 0.05, -- minimum air time before a landing counts

	--== DRIFT =========================================================
	-- Drifting turns TIGHTER than steering. That's the whole reward —
	-- it's why you drift instead of just cornering.
	DriftTurnBase = 1, -- rad/s baseline while drifting
	DriftTurnTrim = 1.4, -- rad/s added/removed by steering
	DriftVisualAngle = 30, -- degrees the body is rotated out. PURELY
	-- COSMETIC — it does not steer the kart.

	-- A single 0..1 blend eases the kart into and out of the drift. It
	-- drives BOTH the body angle and the extra turn rate together, so
	-- there's no frame where either one steps. Smoothstepped, meaning
	-- the rate of change is zero at both ends — that's what kills the
	-- snap. Seconds, not rates.
	DriftEnterTime = 0.26, -- time to fully commit to the drift
	DriftExitTime = 0.45, -- time to unwind. Longer on purpose: a drift
	-- should end like a car settling.
	DriftMinSpeed = 22, -- speed needed to start a drift
	DriftExitSpeed = 12, -- drop below this and the drift breaks
	DriftEngageSteer = 0.15, -- steer held on landing to lock in
	-- DRIFT SPEED CURVE
	--
	-- Per-frame speed retention across the LIFE of a drift, sampled over
	-- DriftScrubWindow seconds. Below 1 scrubs speed, above 1 builds it.
	--
	--   1.00 |\                    __/
	--        | \__            ____/
	--   0.98 |    \__________/
	--        +------------------------- drift time ->
	--
	-- Enter fast, wash speed off as the kart takes a set, then wind back
	-- up as it hooks up and comes off the corner. Committing to a long
	-- drift should feel like it costs something before it pays.
	--
	-- A flat { 1 } means a drift neither scrubs nor builds.
	DriftScrubCurve = { 1.0, 0.988, 0.980, 0.982, 0.992, 1.002, 1.006 },
	DriftScrubWindow = 2.6, -- seconds the curve spans before it holds

	DriftSpeedKeep = 0.995, -- flat multiplier applied on top of the curve.
	-- 1.0 = zero scrub. Keep it near 1 so drifting is the fast line.

	--== BOOST =========================================================
	BoostTier1Time = 0.85, -- seconds of drift for blue
	BoostTier2Time = 1.80, -- orange
	BoostTier3Time = 2.90, -- purple
	-- NOTE: drift release no longer fires a boost — it banks nitro, and
	-- the player spends it. Speed per tier now lives in Config.Nitro's
	-- stage table. The Time values above are still what decide which
	-- tier a drift reaches, and therefore how much it banks.
	BoostAccel = 9, -- how hard it snaps up to boost speed

	--== GROUND ========================================================
	RideHeight = 1.4, -- hitbox origin height above the ground
	GroundSnap = 3.0, -- how far BELOW to still count as grounded, i.e.
	-- how big a drop it follows instead of launching off. Keep modest or
	-- the kart sticks to the floor when it should get air.
	GroundSnapUp = 8.0, -- how far ABOVE. Generous on purpose: a ramp
	-- taken at boost speed gains height fast, and one shared value meant
	-- the kart outran the snap and ended up inside the wedge.
	ProbeUp = 2.5, -- ray start height above the origin
	MaxSlopeDot = 0.25, -- minimum surface normal dot OUR up that counts
	-- as drivable. LOWER = climbs steeper ramps. Below this is a wall.
	ProbeSpread = 2.2, -- how far out the corner ground rays sit.
	-- Multiple rays stop a single centre ray misreading a sharp ledge.

	--== SURFACE GRAVITY  (loops, walls, ceilings) =====================
	-- "Down" is the track's surface normal, not the world's. Drive up a
	-- loop and gravity rotates with you, which is why you can stop dead
	-- upside-down and stay put. You leave the road by driving off an
	-- edge or jumping — never by falling off.
	SurfaceAlignRate = 14, -- how fast OUR up chases the surface. Must be
	-- brisk or tight loops shed the kart.
	AirAlignRate = 2.5, -- how fast up returns to world-up once genuinely
	-- airborne, so you land upright
	-- How far to look for track beneath a jumping kart before deciding
	-- it's over open air and levelling out to world-up.
	--
	-- Generous on purpose: it only has to beat the height of a hop, and
	-- being wrong the other way means falling off a loop. Anything under
	-- the arc of a jump is fine.
	AirSurfaceProbe = 40,

	StickTime = 0.16, -- grace period after losing contact before world
	-- gravity takes back over. Bridges seams and stair nosings.
	StairSmoothing = true, -- average the probe normals instead of
	-- trusting the highest hit. Turns a staircase into a ramp; without
	-- it every riser reads as a wall.

	--== COLLISION =====================================================
	WallScrub = 0.55, -- speed lost on a head-on wall hit (0..1)
	SkinWidth = 0.1, -- gap kept from surfaces
	CollisionPasses = 3, -- slide iterations per frame, each re-cast.
	-- 1 = shoots through corners, because the slide itself would never
	-- be collision-checked.
	Depenetrate = 55, -- studs/sec push-out if we end up inside a wall.
	-- A Blockcast that STARTS overlapping reports nothing, so without
	-- this one bad frame frees the kart permanently.
	StepTolerance = 0.35, -- studs a probe must sit above the centre's own
	-- surface plane before it counts as a STEP rather than a slope. Below
	-- this it's just gradient, and treating gradient as a step is what
	-- makes ramps and wedges lumpy.

	StepHeight = 1.5, -- obstacles this tall are ignored by the sweep and
	-- climbed by the ground snap. THIS is what stops sharp ledges and
	-- ramp lips halting the kart dead.

	--== INTEGRATION ===================================================
	MaxTimestep = 1 / 20, -- never integrate a bigger frame than this
}
