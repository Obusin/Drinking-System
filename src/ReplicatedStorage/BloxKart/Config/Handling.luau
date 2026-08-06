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
	DriftGrip = 2.9, -- ...and while drifting. Lower still, so a drift
	-- genuinely slides wide before the rotation reels it back in

	-- MaxSlip IS PART OF THE DRIFT SET, not a safety rail bolted on the
	-- side. It moved WITH DriftGrip and had to.
	--
	-- In a settled drift the nose rotates at `DriftTurnBase + trim *
	-- DriftTurnTrim` and travel settles a lag angle behind it of roughly
	--
	--     slip = driftTurn / DriftGrip      (radians)
	--
	-- which is why the cap is reached at some FRACTION of full lock, and
	-- why that fraction moves when either number does. Past it the clamp
	-- takes over: extra lock still rotates the kart, it just stops adding
	-- any visible slide, so the drift feels like it hit a stop.
	--
	-- At the old 3.5 grip against a 32° cap that happened at about 68% of
	-- lock. Dropping grip to 2.9 and leaving the cap alone would have
	-- pulled it forward to 57% — a WIDER dead band, the exact opposite of
	-- the loosening it was meant to buy. 38° puts it back at 66%, and
	-- every input below it now carries about 20% more slip than before:
	-- 16.4° -> 19.8° neutral, 27.8° -> 29.3° at half lock.
	--
	-- Raise DriftGrip without dropping this and the reverse happens: the
	-- clamp stops being reachable and MaxSlip quietly stops existing.
	MaxSlip = 38, -- degrees travel may lag the nose. Hard cap, so the
	-- kart can never end up driving sideways or backwards

	-- Grip is not switched between states, it is CHASED. Every other part
	-- of the drift already eases (the body angle and the turn rate share
	-- one smoothstepped blend); grip was the last thing left stepping, and
	-- it stepped at the two worst moments — the frame a hop leaves the
	-- ground and the frame a drift is released, where the kart snapped
	-- from 2.9 to 9 and hooked up like it had hit tarmac.
	--
	-- High enough that it never becomes a second, slower drift timer.
	-- Lower it and grip starts lagging visibly behind the body.
	GripBlendRate = 12,

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

	-- THE HOP HAD NO FALL. This is the one that mattered.
	--
	-- HopSpeed 18 against Gravity 150 gives an apex of 1.08 studs — well
	-- inside GroundSnap (3.0). The snap only refuses while the kart is
	-- still rising, so the instant vertVel crossed zero AT THE APEX the
	-- ground grabbed it and put it back down in a single frame. The hop
	-- was a 0.12s rise followed by a teleport: a sawtooth, not an arc,
	-- and precisely why it read as a discrete state change rather than a
	-- movement.
	--
	-- So a deliberate hop gets its own, much tighter snap distance. The
	-- big GroundSnap is there to follow the road over dips and seams; it
	-- has no business reeling in a jump the player asked for. Only real
	-- touchdown counts now, so the kart falls the whole 1.08 studs and
	-- lands at about 15 studs/s — which is also what finally gives the
	-- landing an impact worth cushioning.
	--
	-- Air time stays deterministic (~0.22s, from the arc alone), which
	-- matters because this is the gate the drift is timed off.
	HopSnap = 0.35,

	-- The hop unloads the wheels — the drift spec always said so, and the
	-- kinematic rewrite quietly dropped it. Full grip in mid-air meant
	-- travel snapped to wherever the nose was pointed the moment you
	-- landed, so the drift began from zero slip every time and the entry
	-- was a step. Carrying momentum through the hop instead means the kart
	-- is ALREADY sideways when it touches down, and the drift picks up a
	-- slide that has already started.
	--
	-- Deliberately below DriftGrip, so grip only ever rises out of a hop
	-- into a drift and never spikes back toward Grip in between.
	--
	-- Applies to the hop state only, NOT to being airborne generally —
	-- a ramp jump still steers as before. That is a separate question and
	-- changing it would move every bot line in the game.
	HopGrip = 1.5,

	--== BEING SPUN ===================================================
	-- How far a spinout knocks you off line, on top of the speed it
	-- costs. Applied once, at the moment of the hit.
	--
	-- A spinout used to be cosmetic plus a speed penalty — the body
	-- thrashed but the heading never moved, so you came out pointing
	-- exactly where you went in and recovery was holding the throttle
	-- and waiting. There was nothing to actually do about it.
	--
	-- KEEP THESE SMALL. The reason a spin is recoverable at all is that
	-- you never lose your bearings; past roughly 40 degrees it stops
	-- being "reposition the kart" and starts being "which way am I
	-- facing", which is disorienting rather than difficult. This should
	-- cost a corner, not a lap.
	SpinYaw = 22, -- degrees the nose is knocked round, random direction
	SpinShove = 3.5, -- studs sideways, the same direction as the yaw

	--== DRIFT =========================================================
	-- Drifting turns TIGHTER than steering. That's the whole reward —
	-- it's why you drift instead of just cornering.
	--
	-- THESE TWO ARE THE DRIFT LINE, AND THEY WERE LEFT ALONE ON PURPOSE.
	--
	-- It is tempting to raise them to "compensate" for the looser grip
	-- below, on the theory that a lower grip makes drifts run wide. It
	-- does not, and this is worth writing down because the assumption is
	-- very natural and wrong: in a SETTLED drift `travel` rotates at
	-- exactly the same rate as the nose whatever the grip, because that
	-- is what settled means. Grip decides how far the kart lags and how
	-- much it washes on the way IN. It never touches the radius the drift
	-- eventually holds — that is these two numbers and nothing else.
	--
	-- So there is nothing here to compensate for, and moving them would
	-- have silently changed what the fast line is.
	DriftTurnBase = 1, -- rad/s baseline while drifting
	DriftTurnTrim = 1.4, -- rad/s added/removed by steering. Must stay
	-- above DriftTurnBase or full countersteer can no longer rotate the
	-- kart back OUT of the slide, which is the only way to catch one.
	DriftVisualAngle = 32, -- degrees the body is rotated out. PURELY
	-- COSMETIC — it does not steer the kart.
	-- ...and how much more the body opens up when you lean on it.
	--
	-- A single fixed angle meant the kart struck one pose on turn-in and
	-- held it for the whole corner, identical whether you were feathering
	-- the slide or pinned against the stop. Steering into the drift now
	-- opens the body out, catching it tucks it back in — which is also
	-- the tell that tells you which one you are doing.
	--
	-- KEEP THIS SMALL. What the driver actually sees is this angle PLUS
	-- the slip angle, and they add: the body yaws into the corner while
	-- travel trails out of it. At 32 + 6 against a 38° slip cap the
	-- extreme is already about 76° of body-to-travel, which is a long way
	-- past anything Mario Kart shows you. There is no headroom left here.
	--
	-- Driven off the SMOOTHED steer value, so the body swings rather than
	-- snapping with the stick. Still purely cosmetic.
	DriftVisualAngleTrim = 6,

	-- A single 0..1 blend eases the kart into and out of the drift. It
	-- drives BOTH the body angle and the extra turn rate together, so
	-- there's no frame where either one steps. Smoothstepped, meaning
	-- the rate of change is zero at both ends — that's what kills the
	-- snap. Seconds, not rates.
	DriftEnterTime = 0.30, -- time to fully commit to the drift. Longer
	-- than it was: with grip now riding this same blend, the extra beat is
	-- the kart taking a set rather than arriving already sideways.
	DriftExitTime = 0.45, -- time to unwind. Longer on purpose: a drift
	-- should end like a car settling.
	DriftMinSpeed = 22, -- speed needed to start a drift
	DriftExitSpeed = 12, -- drop below this and the drift breaks
	DriftEngageSteer = 0.15, -- steer held on landing to lock in
	-- DRIFT SPEED CURVE
	--
	-- Speed retention PER SECOND across the LIFE of a drift, sampled over
	-- DriftScrubWindow seconds. Below 1 scrubs speed, above 1 builds it.
	--
	--   1.00 |\                    __/
	--        | \__            ____/
	--   0.84 |    \__________/
	--        +------------------------- drift time ->
	--
	-- Enter fast, wash speed off as the kart takes a set, then wind back
	-- up as it hooks up and comes off the corner. Committing to a long
	-- drift should feel like it costs something before it pays.
	--
	-- PER SECOND. NOT PER FRAME. Simulation raises these to `^dt`, and
	-- that is the only reason the numbers below are readable as
	-- percentages. Applied per frame — which is what it did until
	-- 2026-08-06 — a value of 0.98 is 0.98^60 = 30% of your speed
	-- SURVIVING each second, and the whole curve becomes a frame-rate
	-- dependent cliff. Measured before the fix: a drift bled to 68% of
	-- top speed at 60fps, and 49% at 144fps.
	--
	-- So read these as "how much speed a second of drift keeps". 0.84 at
	-- the trough is a 16%/s bleed, which against the accel curve pulling
	-- the other way settles the kart at about 93% of top speed — a dip
	-- you feel, not a wall you hit.
	--
	-- KEEP THE LAST VALUE AT 1.0. sampleCurve holds the final value once
	-- the window is past, so anything above 1 there is a permanent
	-- overspeed for as long as a sweeper can be held.
	--
	-- A flat { 1 } means a drift neither scrubs nor builds.
	DriftScrubCurve = { 1.0, 0.90, 0.84, 0.86, 0.93, 0.99, 1.00 },
	DriftScrubWindow = 2.6, -- seconds the curve spans before it holds

	DriftSpeedKeep = 1.0, -- flat multiplier on top of the curve, also per
	-- second. THIS is the one dial for "is drifting faster or slower than
	-- driving straight" — the curve owns the shape, this owns the level.
	-- Above 1 and a drift outruns the throttle; below 1 and it costs you.

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

	-- WHY A "SOLID-LOOKING" SURFACE STILL SLIDES A KART OFF IT.
	--
	-- The centre probe not only has to hit something, the hit's NORMAL
	-- has to pass MaxSlopeDot above. A part with no CanQuery (or a stray
	-- CollectionService tag WorldFilter excludes — see Race.SurfaceTag)
	-- gives no hit at all; an imported mesh with inverted/backward
	-- triangle winding gives a hit whose normal points the wrong way and
	-- fails the dot check even though the surface looks flat. Both read
	-- identically from the driver's seat: the kart falls through or
	-- slides off something that looks perfectly solid.
	--
	-- ON, this prints — rate-limited — exactly which of the two it is,
	-- and the instance it actually hit, the moment the centre probe
	-- fails. OFF by default: it fires every rejected frame while
	-- genuinely airborne over open track, which is normal and not worth
	-- narrating.
	GroundDebug = false,

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

	--== RIDING A SURFACE THAT ISN'T FLAT ==============================
	-- The ground snap puts the kart exactly RideHeight above whatever
	-- the centre probe hit, every frame. On flat parts that number never
	-- moves, so an instant snap is invisible and correct.
	--
	-- A CURVED MESH IS NOT SMOOTH TO A RAYCAST. Roblox builds collision
	-- geometry for a MeshPart out of convex hulls, so a road that looks
	-- perfectly smooth is a chain of flat FACETS underneath. Driving
	-- along it, consecutive frames hit different facets and get slightly
	-- different heights and normals — and an instant snap turns that
	-- into a hard jolt every facet boundary. That is the "bendy surfaces
	-- are buggy" symptom, and no amount of mesh care removes it: the
	-- faceting is in the collision build, not the model.
	--
	-- So SMALL height corrections are eased instead of snapped. Large
	-- ones are not — landing, and climbing a genuine step, still want to
	-- be immediate, and easing those would feel floaty.
	GroundSmooth = 0.75, -- corrections up to this many studs are eased.
	-- Roughly facet-noise sized. Raise if a curved road still jitters;
	-- lower if the kart feels like it floats over small bumps.
	GroundSmoothRate = 18, -- how fast an eased correction is applied.
	-- Very high is the same as no smoothing at all, which is what this
	-- did before and is still correct for a track built from parts.

	--== INTEGRATION ===================================================
	MaxTimestep = 1 / 20, -- never integrate a bigger frame than this

	-- HOW MANY OF THOSE A SINGLE FRAME MAY RUN.
	--
	-- MaxTimestep on its own is a trap, and it cost a "the kart feels
	-- super slow" report to find. `Step` clamps dt to it, so a caller
	-- that calls Step ONCE per frame silently DISCARDS everything past
	-- 50ms — and discarded time is lost motion, not a stutter:
	--
	--     30 fps -> fine, under the cap
	--     15 fps -> 66ms elapsed, 50ms integrated -> 75% speed
	--     10 fps -> 50% speed
	--
	-- The kart does not judder, it goes SLOW, smoothly, and the
	-- speedometer agrees because the simulation really is that slow.
	-- From the seat it reads as the handling having been nerfed, which is
	-- the last thing anyone would investigate.
	--
	-- So a long frame is integrated as several capped steps. This bounds
	-- the catch-up: past 4 slices (0.2s of real time) we drop the
	-- remainder on purpose, because fully repaying a one-second hitch
	-- costs a second of simulation on the very next frame and turns one
	-- hitch into a spiral.
	--
	-- ANY new caller of Step must sub-step too. There is nothing in the
	-- module that can enforce it.
	MaxSubSteps = 4,
}
