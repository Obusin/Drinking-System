--[[
	Swim — the kart on water.

	THE FLOOR IS AT THE WATERLINE, AND THAT IS THE WHOLE TRICK.
	----------------------------------------------------------
	There is no buoyancy here, no water plane, and no second movement
	mode. You put an invisible floor at the surface, the kart drives on it
	exactly as it drives on tarmac, and everything below is decoration on
	top of that.

	It means the sweep, the ground probe, surface gravity, drift and the
	suspension all keep working unchanged — because from the controller's
	point of view nothing has happened. Compare the alternative: replacing
	the ground probe with a water plane is a whole second movement mode,
	with its own landing rules, its own ride height and its own bugs.

	SO EVERY DIAL IN THIS FILE IS EITHER COSMETIC OR A SCALAR ON SOMETHING
	THAT ALREADY EXISTS. Nothing here introduces a new force.

	The Consistency Rule is intact: Simulation still reads exactly the
	Hitbox and the Seat. A swim zone changes what the kart LOOKS like and
	how fast it may go — never how it is simulated.
--]]

return {
	Enabled = true,

	--== THE WORLD ====================================================
	-- Tag the water VOLUME with this — the body of water itself, not its
	-- surface. Overlap is what matters, so the part should be as deep as
	-- the water looks.
	--
	-- It is a marker, not geometry: it goes in Triggers.TAGS like every
	-- other trigger, so it is never something the kart can hit. The thing
	-- the kart actually drives on is your own floor at the waterline.
	ZoneTag = "SwimZone",

	--== HANDLING, AS SCALARS =========================================
	-- Water is thicker than air. Both of these are fractions of the
	-- kart's normal figures, so retuning the kart retunes the boat.
	SpeedScale = 0.78,
	AccelScale = 0.7,

	-- Eased in and out, or crossing the shoreline is a step change in top
	-- speed and reads as hitting something.
	BlendRate = 2.2,

	--== IT HANDLES LIKE A BOAT =======================================
	-- A HULL HAS NO TYRES, so it does not bite — it pushes water and
	-- waits. Everything here is a scalar on something that already
	-- exists, so retuning the kart retunes the boat.
	--
	-- The steering DELAY is the single biggest cue. A kart answers the
	-- stick instantly; a boat leans on the rudder and comes round a
	-- moment later, and that lag is what your hands read as "this is a
	-- different vehicle" long before any visual does.
	SteerRateScale = 0.35, -- how fast the input reaches full lock
	TurnScale = 0.62, -- and how tightly it comes round at all

	-- NO DRIFTING. There is nothing to break traction against — a hull
	-- is already sliding. Attempting a drift on water should do nothing
	-- rather than something odd, and an existing drift ends the moment
	-- you enter the water.
	AllowDrift = false,

	--== THE WATER HOP — A DRAWN CURVE, NOT A SIMULATED ARC ===========
	-- THE KART SKIPS OVER WATER LIKE A STONE. This is the main motion,
	-- and it is a deliberate copy of what the real hop looks like when
	-- you spam jump across a swim zone — which is the reference, because
	-- that already reads better than any amount of tilt did.
	--
	-- NOTHING HERE IS SIMULATED. It is a number added to `visualPos` at
	-- the render write, beside `bob`, `squash` and `catch` — so it moves
	-- the WHOLE assembly, wheels and driver included, exactly as the real
	-- jump does. No impulse, no vertVel, no grounded change, no ground
	-- snap, no collision: the kart drives dead flat on the invisible
	-- floor the entire time.
	--
	-- TWO CURVES HAVE BEEN WRONG HERE, BOTH FOR SHAPE REASONS RATHER THAN
	-- TUNING ONES, which is the thing to remember before reaching for a
	-- number:
	--
	--   BURSTS  max()-latched, exp()-decayed. Fastest at the start,
	--           slowest at the end: no rise and no top. A hop is the
	--           opposite shape and no setting could produce one.
	--   ARC     a true parabola. Correct in the middle, but it has a
	--           velocity discontinuity at BOTH ends, and those corners
	--           are what read as snappy at two hops a second.
	--
	-- It is now a phase-driven curve whose shape is a dial. See
	-- WaveHopSmooth.
	--
	-- THE RHYTHM IS THE FEATURE. Height was never the missing piece —
	-- the first version hopped hard but irregularly, and irregular reads
	-- as broken however good each individual hop is. Everything below is
	-- tuned to a CADENCE first and a height second.
	WaveHopEnabled = true,

	-- BELOW THIS THE KART JUST FLOATS. A moored boat wallowing is right;
	-- a moored boat hopping four times a second is not. This is the only
	-- thing that stops the skipping now — the wave no longer gates it.
	WaveHopMinSpeed = 12, -- studs/s

	-- THE ARC, SOLVED BACKWARDS FROM THE CADENCE.
	--
	-- `apex = v * airtime / 4`, so `v = 4 * apex / airtime` and
	-- `g = 2v / airtime`. Pick the rhythm and the height, and the two
	-- dials fall out — which is the right way round, because the rhythm
	-- is the thing being copied.
	--
	--   ~2 hops/s at ~0.7 studs  ->  v 9.5, g 54.5
	--
	-- HEIGHT AND RHYTHM ARE SEPARABLE, which is worth knowing before
	-- touching either. At a fixed airtime `apex` is proportional to `v`,
	-- so scaling v and g by the SAME factor lowers the hop and leaves the
	-- cadence untouched — measured identical at 2.01/2.53/2.78 hops/s and
	-- 14-16 frames of air across a 40% range of heights.
	--
	-- To change the HEIGHT: scale v and g together.
	-- To change the RHYTHM: move WaveHopCooldown.
	-- The two do not interfere.
	--
	-- THE AIRTIME IS THE REAL HOP'S AIRTIME. HopSpeed 18 against gravity
	-- 150 is 0.24s of air, 14 frames. These give 14-16, and every retune
	-- so far has preserved that — it is the thing being copied. The
	-- HEIGHT is deliberately lower than the real hop's 1.08 studs,
	-- because this fires two to three times a second where the real one
	-- fires when you ask for it.
	--
	-- The phase model makes the cadence EXACT rather than measured: the
	-- cycle is `air + rest` by construction, so there is no gap sd left
	-- to report — it is zero by definition, and the wave varies only the
	-- height. That is the end of the irregularity complaint.
	--
	-- SCALED DOWN TOGETHER from 12/69 when the curve changed. The phase
	-- model scales size LINEARLY with the wave where the ballistic one
	-- scaled it with the square of the launch speed, so the same dials
	-- came out about a third taller. Same airtime, same rhythm.
	WaveHopVelocity = 9.5,
	WaveHopGravity = 54.5,

	--== THE CURVE, AND WHY IT IS NOT BALLISTIC ANY MORE ===============
	-- 0 is a true ballistic parabola. 1 is `sin^2`. Same apex, same
	-- duration; they differ only at the ENDS:
	--
	--   0  slope +4 at launch, -4 at landing   -> a corner at each end
	--   1  slope  0 at launch,  0 at landing   -> none
	--
	-- Those two corners are velocity discontinuities, and they are what
	-- read as "snappy". They are not a tuning fault — they are what a
	-- ballistic arc IS. One jump gets away with it; two and a half a
	-- second does not, because the corner arrives five times a second.
	--
	-- The landing squash follows this automatically: its impulse is the
	-- arrival slope, which goes to zero as this goes to 1. Smoothing the
	-- curve silences the thump without a second dial.
	--
	-- Drop toward 0 if it starts to feel floaty rather than smooth — at 1
	-- the kart leaves the water very gently indeed.
	WaveHopSmooth = 0.85,

	-- REST BETWEEN HOPS, ARMED ON LANDING — NOT ON LAUNCH. Armed at
	-- launch it can expire while the kart is still in the air, which
	-- makes it no rest at all.
	--
	-- THE BEAT BETWEEN SKIPS, and THE dial for the cadence. With the
	-- launch unconditional, `airtime + rest` is the cycle and `1/cycle`
	-- is the hop rate — so this is what to move when the rhythm is wrong,
	-- NOT the arc.
	--
	-- Halving the rate means doubling the cycle, and that is either more
	-- air or more rest. More air was tried and it floats: 0.5s hops at
	-- 91% aloft is a kart hovering, not one skipping. More rest keeps the
	-- real hop's arc and puts the kart back on the water between skips,
	-- which is what mashing jump actually looks like.
	--
	-- A REGULAR rest is a rhythm; an IRREGULAR one is a stutter. The
	-- original complaint was the second, so this being large is fine.
	--
	-- THIS IS THE ONE TO MOVE for the cadence. It has gone 0.05 -> 0.30
	-- -> 0.24 -> 0.15 and the AIRTIME never changed once, which is the
	-- intended division of labour.
	--
	-- The last move was not a taste change. Under the old ballistic model
	-- a smaller hop also had a shorter airtime, so the average cycle was
	-- shorter than `air + rest` and the measured rate ran ahead of the
	-- arithmetic. A phase cycle is exactly `air + rest` whatever the
	-- size, which is more honest and came out a third slower — so the
	-- rest had to come down to land back on the same 2-2.8/s.
	WaveHopCooldown = 0.15,

	--== GO FASTER, HOP FASTER ========================================
	-- The arc itself speeds up with the kart, which is the part a flat
	-- rate could never give you: at a constant airtime, driving faster
	-- only meant hopping HIGHER, and height alone does not read as pace.
	--
	-- `apex = v^2/2g`, `airtime = 2v/g`. Velocity is scaled by `k` and
	-- gravity by `k SQUARED`, so the apex is unchanged and the airtime is
	-- divided by `k` — the same hop, snapped through in less time.
	-- Raising gravity alone would flatten it; raising velocity alone
	-- would make it hang longer, which is slower, not faster.
	--
	-- With the cadence constant this now sets the SPREAD of the rhythm:
	-- ~2.0/s just above WaveHopMinSpeed, ~2.8/s at a 95 top speed.
	--
	-- `PaceArc` stays gentle: it shortens the ARC, and the arc is the
	-- real hop's and should be left alone. `PaceRest` does the work,
	-- because eating into the rest is how the rhythm tightens without
	-- touching the shape of a single hop.
	WaveHopPaceArc = 0.25, -- extra k at full speed
	WaveHopPaceRest = 0.49, -- fraction of the cooldown removed at full speed

	-- HOW BIG — and this is now the wave's ONLY job. Rise is mapped
	-- SYMMETRICALLY, -FullRise..+FullRise onto MinScale..1, so a crest
	-- gives the full arc and a trough the smallest one. Never zero: a
	-- trough may shrink the skip, it may not cancel it.
	--
	-- THE SYMMETRY MATTERS. Mapping 0..FullRise instead and clamping
	-- looks equivalent and is not — the field is falling half the time,
	-- so half of all hops pinned to the floor and the mean apex came out
	-- at 0.5 studs against the 1.0 these dials were solved for. Half the
	-- range was simply unreachable.
	--
	-- Measured rise peaks around 6 at a cruise and 18 at full speed, so 8
	-- is the span that varies across the range players actually drive.
	WaveHopFullRise = 8,
	-- RAISED with the constant cadence. When hops were occasional a weak
	-- one was fine; now that they are continuous, the smallest one is on
	-- screen constantly and 0.55 read as a stutter between proper hops.
	WaveHopMinScale = 0.72,

	-- PITCH, DRIVEN BY THE HOP'S OWN VELOCITY rather than by a timer.
	-- Nose rises while climbing, passes through neutral exactly at the
	-- apex because that is where velocity is zero, and drops on the way
	-- down. It cannot desynchronise from the arc, because it IS the arc.
	--
	-- NOTE THE SIGN IS HANDLED IN CODE. These are magnitudes; the render
	-- write negates them, because negative pitch is nose-up there — the
	-- same convention the real hop's air pitch already uses.
	WaveHopPitchUp = 7.5, -- degrees at full climb
	WaveHopPitchDown = 3.5, -- and at full descent, deliberately smaller

	-- THE LANDING, THROUGH THE SQUASH SPRING THAT ALREADY EXISTS. The
	-- kart has a landing squash with a spring and a damper on it; a skip
	-- onto water is the same event, smaller. Reusing it means the dip
	-- can never look like a different mechanism from a normal landing,
	-- and there is no second recovery rate to keep in step.
	--
	-- This is an IMPULSE into that spring — studs/s of squash velocity
	-- per stud/s of arrival — not a value assigned each frame. Assigning
	-- it is exactly how the kart's own landing bounce ended up snapping.
	--
	-- Peak dip is roughly v/sqrt(SquashSpring): 8.5 * 0.24 / sqrt(190)
	-- is about 0.15 studs. Subtle, because this is a skip, not a crash.
	WaveHopLandSquash = 0.24,

	-- Below this much swim blend there is no hopping at all, so the
	-- shoreline eases in instead of the kart popping the moment a wheel
	-- touches water.
	WaveHopMinSwim = 0.35,

	-- YAW. A hull is pushed off line by water in a way a kart never is,
	-- and this is the cue that says "you are not on tarmac" more clearly
	-- than pitch does — because a kart's nose NEVER wanders on its own.
	--
	-- Visual only: the kart still goes exactly where the simulation says.
	-- It is the hull that slews, not the course.
	--
	-- TURNED DOWN once the hop became the main motion. Wander is a
	-- seasoning: at 2.6 degrees it was competing with the skip for the
	-- eye, and two unrelated motions at similar strength read as drunk
	-- rather than playful.
	YawWander = 1.5, -- degrees either side
	YawRate = 0.37, -- cycles per second, deliberately not a wave rate

	--== BOW-UP TRIM — THE BOAT LEANS BACK ============================
	-- A hull below planing speed is climbing its own bow wave: the nose
	-- rides high and the stern squats. It is worst while ACCELERATING
	-- through that hump and settles once the boat is up and planing.
	--
	-- TWO TERMS, AND THE THROTTLE ONE IS THE BIG ONE. A speed-only lean
	-- would be wrong in the exact moment the player looks for it —
	-- pinning the throttle from rest would do nothing at all until the
	-- speed had already arrived, which is backwards. Throttle gives the
	-- lift while you are getting up to speed; the speed term is the
	-- smaller trim the hull holds once it is there.
	--
	-- Added to the kart's EXISTING accel-squat pitch rather than being a
	-- system of its own, so it inherits that smoothing and the render
	-- write, and it composes with the hop's pitch instead of fighting it.
	--
	-- THE THROTTLE TERM FADES OUT AS THE HULL GETS UP, by `1 - pace`.
	-- That is the physical story and not a fudge: the lift comes from
	-- CLIMBING the bow wave, and once you are planing you are on it
	-- rather than climbing it. Holding full bow-up at top speed would be
	-- a boat permanently stuck at its hump, nose to the sky down a
	-- flat-out straight — which is the one place a real hull is flattest.
	--
	-- Composed with everything else already on the pitch:
	--
	--   state                    squat  throttle  planing   total
	--   parked                     0.0     0.00     0.00     0.0
	--   pinning it from rest       1.5     6.50     0.00     8.0   <- the lean
	--   half speed                 1.5     3.25     1.25     6.0
	--   flat out, planing          1.5     0.00     2.50     4.0   <- settles
	--
	-- The hop adds a further +7.5 rising / -3.5 falling on top, but that
	-- OSCILLATES where these are sustained, so they do not stack into a
	-- permanent angle.
	--
	-- Reverse does not lift the bow — a boat backing up settles by the
	-- stern. Handled in code with math.max, not with a dial.
	TrimOnThrottle = 6.5, -- degrees of nose-up while getting up to speed
	TrimAtSpeed = 2.5, -- and the flatter trim it keeps once planing

	--== THE WHEELS GO SIDEWAYS =======================================
	-- Rolled flat so they read as paddles rather than tyres. This is the
	-- single clearest signal that the kart has changed mode — clearer
	-- than any particle, because it changes the silhouette.
	--
	-- About the wheel's own FORWARD axis, so a wheel lies over rather
	-- than steering; the roll and steer axes it already has are left
	-- alone and keep working underneath.
	--
	-- MIRRORED PER SIDE, so both pairs lean their tops toward the centre
	-- like a hull. A single shared angle tilts every wheel the same way,
	-- which leans one pair in and the other OUT — and a kart with its
	-- wheels leaning the same direction looks like it is falling over
	-- rather than floating.
	WheelTilt = 82, -- degrees. 90 is dead flat, which reads as broken.
	WheelTiltRate = 4, -- how fast they lie over

	-- And they keep turning, just slower — a paddle wheel, not a tyre.
	WheelSpinScale = 0.45,

	--== THE SEA ======================================================
	-- A WAVE FIELD SAMPLED AT THE KART'S POSITION, not a bob over time.
	--
	-- That distinction is the whole feeling. A sine of time alone gives
	-- you a kart vibrating in place: it bobs identically parked and at
	-- full speed, and two karts side by side rise and fall in perfect
	-- unison, which instantly reads as fake. A field of `h(x, z, t)`
	-- means the swell EXISTS in the world — you drive through it, you
	-- take it at an angle, and the boat next to you is on a different
	-- part of the same wave.
	--
	-- Three directional waves. One is a ripple; two beat against each
	-- other; three stops the pattern being findable, which is what makes
	-- it read as water rather than as an animation. Wavelengths and
	-- headings are deliberately unrelated so the sum never repeats on any
	-- timescale a player will sit through.
	Waves = {
		{ amp = 0.55, length = 46, heading = 0, speed = 5 }, -- the swell
		{ amp = 0.30, length = 25, heading = 58, speed = 7 }, -- crossing it
		{ amp = 0.11, length = 11, heading = -37, speed = 11 }, -- chop
	},

	-- PITCH AND ROLL COME FROM THE SLOPE OF THE WATER, not from a second
	-- animation. The field is sampled fore/aft and left/right and the
	-- difference IS the tilt — so the hull always lies along the wave it
	-- is actually on, and heave and tilt can never disagree.
	--
	-- Wider than the kart, deliberately: sampling at the exact wheel line
	-- picks up the chop and makes the kart twitch. This is the boat's
	-- waterline length, and a longer boat rides a short chop flatter.
	WaveSample = 5.5, -- studs fore/aft and left/right
	-- MEASURED, not guessed. The raw height difference across an 11-stud
	-- sample span runs 0.36 studs typical, 0.76 at peak — so 26 degrees
	-- per stud put every single frame on the 11-degree ceiling. Constant
	-- maximum tilt is not a rough sea, it is a broken one: nothing varies,
	-- so nothing reads as motion.
	--
	-- Measured against how often it hits the ceiling, because a ceiling
	-- the system SITS at is not a ceiling, it is the value:
	--
	--    tilt/stud   frames clamped (moored / cruising / flat out)
	--       26          every frame
	--       14        21%   23%   23%
	--        9         2.7%  1.2%  0.6%   <- here
	--
	-- SPEED DELIBERATELY DOES NOT SCALE THE TILT. A faster boat HEAVES
	-- harder over the same wave; it does not lie at a steeper angle to it.
	-- Folding SlamAtSpeed into the tilt as well was what kept it pinned
	-- at maximum however low the coefficient went.
	-- TURNED DOWN with the hop. The balance the sea wants is vertical
	-- motion as the melody and tilt as the harmony; at 9/11 the tilt was
	-- loud enough to be a second melody, which is the "seasick" reading.
	WaveTilt = 7.5, -- degrees of tilt per stud of height difference
	WaveTiltMax = 9.5,

	-- How fast the hull takes up a new angle. The wave field itself is
	-- already smooth; this is the hull's own inertia against it, and it
	-- is what stops a short chop being followed exactly.
	WaveTiltRate = 5, -- and a ceiling, because a wave is not a ramp

	--== THE BOUNCE ===================================================
	-- The hull does NOT rigidly follow the surface — it is sprung against
	-- it. That is the difference between floating and being welded to a
	-- moving plane, and the overshoot is the "bouncy" part.
	--
	-- Same spring form as the suspension, and the same rule: damping is a
	-- RATE, tied to stiffness, `2 * sqrt(k) * zeta`. Undamped it never
	-- settles; critically damped it may as well be rigid.
	HeaveStiffness = 55,
	HeaveDamping = 10, -- 2*sqrt(55)*0.67 — loose and rolling, like a boat

	-- Driving fast into a swell hits harder than drifting over it. Scales
	-- the whole sea by speed, so a moored kart wallows and a moving one
	-- slams.
	SlamAtSpeed = 0.55, -- extra fraction of the wave at full speed

	-- Lean into turns harder than on land, because a hull rolls more than
	-- a chassis does. This is the STEERING-RESPONSIVE lean and it stays —
	-- it is the one piece of the boat's motion the player is causing, so
	-- it is the last thing that should be quietened.
	RollScale = 1.45,

	--== AUDIO ========================================================
	-- The hull moving through water. Looped, and its VOLUME follows
	-- speed rather than the state — a moored boat is nearly silent and a
	-- moving one is not, which is the same reasoning as the glider's
	-- wind: the sound is a readout for how fast you are going, not a flag
	-- that says "you are in water".
	CruiseSoundId = "rbxassetid://123939612469793",
	CruiseVolume = 1,
	CruisePitchMin = 0.85,
	CruisePitchMax = 1.2,
	CruiseFade = 2.5,

	-- SPLASH, on the landing after a wave launch — not on the launch.
	-- The impact is the noise; going up is silent, which is also what
	-- actually happens.
	SplashSoundId = "rbxassetid://124279162156159",
	SplashVolume = 0.7,
	SplashPitchMin = 0.9,
	SplashPitchMax = 1.25,

	Debug = true, -- prints once per kart on entering water. Off for release.
}
