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

	--== RIDING THE WAVES — ORIENTATION, NOT ALTITUDE ==================
	-- THE FEEL IS IN THE ROTATION. A hull crossing a swell pitches, rolls
	-- and yaws far more than it rises, and the rotation is what the eye
	-- reads as water. Height alone is a lift; angle is a sea.
	--
	-- The previous version threw the kart with REAL vertical impulses.
	-- Two problems: anything under 30 studs/s was swallowed by GroundSnap
	-- and did nothing at all, and anything over it was a literal jump —
	-- the kart leaving the surface, which is not what a boat does.
	--
	-- So the bursts are VISUAL. The hull kicks up and pitches back over a
	-- crest through the body motor, the kart never leaves the floor, and
	-- nothing about the movement is touched.
	Bursts = true,
	BurstMinRise = 6, -- studs/s the wave must be rising to kick at all
	BurstLift = 0.09, -- studs of visual lift per stud/s of rise above it
	BurstLiftMax = 1.1, -- and its ceiling
	BurstPitch = 1.4, -- degrees of nose-up per stud/s over the threshold
	BurstPitchMax = 9,
	BurstDecay = 3.2, -- how fast a kick bleeds off

	-- YAW. A hull is pushed off line by water in a way a kart never is,
	-- and this is the cue that says "you are not on tarmac" more clearly
	-- than pitch does — because a kart's nose NEVER wanders on its own.
	--
	-- Visual only: the kart still goes exactly where the simulation says.
	-- It is the hull that slews, not the course.
	YawWander = 2.6, -- degrees either side
	YawRate = 0.37, -- cycles per second, deliberately not a wave rate

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
	WaveTilt = 9, -- degrees of tilt per stud of height difference
	WaveTiltMax = 11,

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
	-- a chassis does.
	RollScale = 1.6,

	--== AUDIO ========================================================
	-- The hull moving through water. Looped, and its VOLUME follows
	-- speed rather than the state — a moored boat is nearly silent and a
	-- moving one is not, which is the same reasoning as the glider's
	-- wind: the sound is a readout for how fast you are going, not a flag
	-- that says "you are in water".
	CruiseSoundId = "rbxassetid://123939612469793",
	CruiseVolume = 0.6,
	CruisePitchMin = 0.85,
	CruisePitchMax = 1.2,
	CruiseFade = 2.5,

	-- SPLASH, on the landing after a wave launch — not on the launch.
	-- The impact is the noise; going up is silent, which is also what
	-- actually happens.
	SplashSoundId = "rbxassetid://128701355933535",
	SplashVolume = 0.7,
	SplashPitchMin = 0.9,
	SplashPitchMax = 1.25,

	Debug = true, -- prints once per kart on entering water. Off for release.
}
