--[[
	Camera — Mario Kart-style chase camera.

	The kart should sit near the bottom-center of the screen while keeping
	a large amount of road visible ahead.
--]]

return {
	--== FIELD OF VIEW =================================================

	-- Mario Kart does not rely on an extremely wide default FOV.
	FovBase = 68,
	FovAtTopSpeed = 78,

	BoostFovStage = {
		2.5,
		5,
		8,
	},

	BoostFovPunch = 3.5,

	FovRate = 5,
	FovRiseRate = 11,

	--== BOOST CAMERA FEEL =============================================

	-- Keep boost pullback fairly small because the normal camera is
	-- already positioned farther away.
	BoostPullBack = {
		0.6,
		1.2,
		2,
	},

	BoostDrop = {
		0.1,
		0.25,
		0.45,
	},

	BoostShake = {
		0.02,
		0.045,
		0.08,
	},

	BoostShakeSpeed = 28,

	--== IMPACTS AND EVENTS ===========================================
	-- ONE SHAKE CHANNEL, DECAYING, fed by several sources. A separate
	-- timer per event ends up with two of them fighting over the same
	-- offset — and the loser is whichever ran second, which is a
	-- coin-flip nobody can debug.
	--
	-- Everything below just raises the same amplitude, and it bleeds off
	-- at one rate.
	ImpactShakeDecay = 6, -- per second
	ImpactShakeSpeed = 42, -- oscillations, faster than the boost jitter

	-- LANDING. Scaled by how hard, so a drift hop is nothing and a drop
	-- off a bridge rattles.
	LandShakeMin = 55, -- studs/s of impact before the camera notices
	LandShakePer = 0.006, -- amplitude per stud/s above that
	LandShakeMax = 0.55,

	-- The camera also dips with the kart on a heavy landing, a beat
	-- behind — it is the weight of the CAMERA, not of the kart, and
	-- having it lag is what makes the drop feel shared.
	-- THE DROP EASES IN, IT IS NOT ASSIGNED.
	--
	-- Setting it directly teleported the camera down by up to half a stud
	-- on the landing frame — the same mistake the kart's squash had, one
	-- layer up, and the reason a trace of snap survived after the kart
	-- itself stopped jumping.
	--
	-- In fast, out slow: the camera should be dragged down quickly by the
	-- impact and float back, which is what a heavy camera does. Equal
	-- rates read as a bob.
	LandDrop = 0.5, -- studs, at LandShakeMax
	LandDropFall = 26, -- per second, going down
	LandDropRecover = 7, -- and coming back

	-- WALL. A stun should feel like one.
	WallShake = 0.7,

	--== THE WATER HOP ================================================
	-- THIS IS LAG, NOT SHAKE, and the difference is the whole point.
	--
	-- Shake is high-frequency noise added to the eye; it reads as an
	-- earthquake and it is what you never want on something firing two
	-- to three times a second. This is a SMOOTH, PARTIAL, LATE follow of
	-- the kart's hop — the camera goes with it, less far and a beat
	-- behind. That is the same trick `LandDrop` uses on a real landing,
	-- and the same reason: a camera that shares the motion makes it feel
	-- weighty, a camera that ignores it makes the kart look like a
	-- sprite sliding on glass.
	--
	-- The kart is drawn at `pos + swimHop`; the camera aims at
	-- `pos + swimHop * Follow`, smoothed. So the kart genuinely rises in
	-- frame by the DIFFERENCE, and the camera hauls itself after it.
	-- With Follow at 1 and an infinite rate the hop would be invisible —
	-- perfectly tracked motion is no motion at all.
	SwimHopFollow = 0.7, -- fraction of the hop the camera takes
	-- A SPRING, NOT A LERP. A lerp only ever chases, so it can only ever
	-- SUBTRACT from what is on screen — turning it up to feel it more
	-- just cancels more of the hop. That is why the first version could
	-- not be felt at any setting: gain and visibility were the same dial
	-- pulling opposite ways.
	--
	-- A spring has its own phase. Under-damped it overshoots, so when the
	-- kart starts falling the camera is still rising and the two are
	-- briefly moving APART. Measured against the lerp it replaced:
	--
	--                        camera travel   kart in frame
	--   lerp 0.5 / rate 9        0.318           0.808
	--   spring k120 z0.35        0.879           1.254
	--
	-- Nearly three times the camera motion AND more visible hop, because
	-- out-of-phase motions add rather than cancel.
	--
	-- Damping is a RATE tied to stiffness, 2*sqrt(k)*zeta — the same form
	-- the suspension and the sea's heave use. zeta 0.35 is deliberately
	-- loose: critical damping is a lerp again.
	SwimHopSpring = 120,
	SwimHopDamp = 7.7, -- 2*sqrt(120)*0.35

	--== SWIM SWAY — THROWN TO THE OUTSIDE OF THE TURN =================
	-- Turn left, the eye slides RIGHT. Turn right, it slides LEFT. The
	-- camera behaving like it has mass and is being swung wide — the
	-- cheapest way to make a boat feel heavy, because a hull takes a
	-- moment to come round and the camera being thrown while it does
	-- sells the wait.
	--
	-- A SLIDE, NOT AN ORBIT, and that distinction is the feature. This
	-- was built as an orbit first: swinging the eye AROUND the kart turns
	-- the whole view, which reads as steering the camera rather than as
	-- the camera being thrown. Sliding it sideways holds the view steady
	-- and lets the kart drift across the frame instead.
	--
	-- WHY IT IS NOT NAUSEATING, which is the only reason it is safe at
	-- all: motion sickness lives in FREQUENCY, not amplitude.
	--
	--   the hop      2-3 Hz   <- the band to keep the camera out of
	--   steering     ~0.5 Hz  <- 0.93s to full lock in water, then
	--                            smoothed again by SwayRate
	--
	-- An order of magnitude apart. It also rotates the OFFSET rather
	-- than the view — the camera orbits the kart and keeps looking at
	-- it, so nothing tilts and the horizon stays level. A rolling
	-- horizon is what actually makes people ill; a moving one does not.
	--
	-- STUDS, not degrees. Deliberately modest against a 13.5-stud chase
	-- distance: past about 5 the kart starts leaving the frame on a long
	-- corner, and a camera that loses the thing it is following is not a
	-- camera with mass, it is a broken one.
	SwimSwaySlide = 3, -- studs sideways at full lock
	-- SLOWER THAN THE STEERING ITSELF, on purpose. If the camera kept up
	-- exactly it would just be part of the kart and you would not feel
	-- it; arriving late is the entire effect, same as the hop spring.
	-- It is also what makes the slide RECOVER slowly when you straighten,
	-- which is the half of the motion that reads as weight.
	SwimSwayRate = 2.5,

	--== FLIPPING =====================================================
	-- The camera does NOT roll with the kart. A camera that flips with a
	-- barrel roll is a camera nobody can play through — the horizon
	-- inverts, and the player loses the one reference they steer against.
	-- It shakes and widens instead, which reads as "something big is
	-- happening" without taking the world away.
	FlipShake = 0.42,
	--=================================================================
	--  IN, NOT OUT. THE TRICK IS THE SHOW.
	--
	--  This used to widen and pull back "to fit the kart in", which is
	--  correct framing and the wrong instinct: it made the kart SMALLER
	--  at the one moment it is doing the most interesting thing it can
	--  do. A barrel roll you can barely make out is not worth a camera
	--  move at all.
	--
	--  Both dials now push the same way. A narrower FOV and a closer eye
	--  compound rather than cancel — together they roughly double the
	--  kart on screen through a flip.
	--
	--  The shake stays, and the camera still does NOT roll: the horizon
	--  is the reference the player steers against, and closer framing
	--  makes keeping it level MORE important, not less.
	--=================================================================
	--  ENOUGH TO KEEP THE TRICK READABLE, AND NO MORE.
	--
	--  This is not a zoom. The job is to stop the kart SHRINKING at the
	--  one moment it is worth looking at — the old pull-back put it at
	--  0.73x through a flip, and a barrel roll at three-quarter size is
	--  a barrel roll you squint at.
	--
	--  Nudging to ~1.2x holds the framing where it already was and lets
	--  the trick read. Going further was tried and it is too much: at
	--  1.55x the camera is on top of the kart and the shot stops looking
	--  like the game.
	--
	--    old  +3.5 / +5   ->  0.73x   trick too small to see
	--    -3.0 / -10       ->  1.54x   a close-up, not a chase cam
	--    -1.5 /  -4       ->  1.21x   still reads as a camera move
	--    -0.75 / -2       ->  1.10x   <- here. Felt, not noticed.
	--
	--  Weighted toward FOV rather than distance because MinChase is a
	--  hard 9-stud floor and a bike already sits 0.9 closer than a kart,
	--  so there is very little room to move in before it clamps — and a
	--  clamped pull makes a flip and a glide look identical.
	FlipFov = -2, -- degrees narrower through the trick
	FlipPull = -0.75, -- studs closer, well clear of the MinChase floor

	--== GLIDING ======================================================
	-- ALSO IN. The old framing pulled back and raised to show the gap
	-- you were crossing, which is genuinely useful information — and it
	-- is information the minimap already carries, whereas the only place
	-- the glider itself can be seen is here.
	--
	-- The rise stays. Height shows the ground going past underneath,
	-- which is what sells the SPEED of a glide, and it costs nothing at
	-- a closer distance.
	-- The old framing put the GLIDER — the thing a glide exists to show
	-- off — at 0.60x. Whatever it was buying in landing-zone visibility,
	-- it was paying for by hiding the subject.
	GlideFov = -2, -- degrees narrower
	GlidePull = -0.75, -- studs closer; same MinChase reasoning as FlipPull
	GlideRise = 3, -- studs higher, to show the ground you are crossing
	GlideRate = 4, -- how fast it eases in and out

	--=================================================================
	--  THE LANDING KICK. The world opens back up as you touch down.
	--
	--  Coming out of a flip or a glide, the framing has been tight for
	--  a second or more. Easing straight back to neutral is correct and
	--  flat; overshooting OUTWARDS first and settling in gives the
	--  landing a beat of its own — the camera flinches back, then comes
	--  to rest.
	--
	--  It rides the same signal as the landing drop, so it is already
	--  scaled by how hard you hit: a drift hop does nothing, a real drop
	--  off a ramp opens the whole frame.
	--
	--  OUT FAST, BACK SLOW. The reverse of the drop above, and for the
	--  same reason — the fast half is the impact, the slow half is the
	--  recovery, and equal rates read as a bounce.
	--=================================================================
	-- SCALED TO THE FRAMING IT RELEASES. The air framing only moves the
	-- eye 1.5 studs, so a 6-stud kick was four times the thing it was
	-- supposed to be recovering from — a lurch rather than a release.
	LandKick = 1.5, -- studs the eye flings back at a full-strength landing
	LandKickFall = 16, -- out fast
	LandKickRecover = 3.5, -- and back in slowly

	BoostLag = {
		0.4,
		0.8,
		1.3,
	},

	BoostLagRecover = 5.5,

	--== BLUR ==========================================================

	BoostBlur = {
		0.5,
		1.25,
		2,
	},

	BlurRate = 8,

	--== CHASE CAMERA ==================================================

	Enabled = true,

	-- THE FRAMING, AND HOW TO WORK IT OUT INSTEAD OF GUESSING.
	--
	-- CameraRig builds exactly two points:
	--
	--   eye = kart + up*(LookHeight + Height) - look*Distance
	--   aim = kart + up*LookHeight           + look*LookAhead
	--
	-- Note LookHeight is in BOTH, so it slides the whole rig up and down
	-- and changes the framing not at all. The tilt is:
	--
	--   pitch      = atan(Height / (Distance + LookAhead))
	--   thing at h = atan((LookHeight + Height - h) / Distance) - pitch
	--                ...below the camera axis, then
	--   screen y   = 0.5 + 0.5 * tan(that) / tan(Fov/2)
	--
	-- WHAT WAS WRONG: at Height 4.6 / LookAhead 15 the RIDER'S HEAD
	-- landed at 44% of screen height — dead centre, exactly where you
	-- look to drive. Mario Kart puts its rider at about 65%, well below
	-- the sightline, which is why that camera reads as being "over" the
	-- kart rather than level with it.
	--
	-- A Roblox avatar seated is ~5 studs tall against Mario's ~2.5, so
	-- matching 65% exactly would need a helicopter shot. 56% is the
	-- honest target: the head is clear of centre and out of the racing
	-- line, without the camera leaving the kart behind.
	--
	-- Raise `Height` to push the kart further down the frame. Raise
	-- `LookAhead` to do the same AND aim further up the road, which is
	-- the better of the two levers because looking where you are going is
	-- what the camera is for. Cutting `Distance` also drops it, and makes
	-- the kart bigger.
	Distance = 13.5,
	Height = 7.0,

	-- 15 -> 28. The old value aimed barely past the nose, which both sat
	-- the kart high in frame and meant you saw a corner about when you
	-- arrived at it.
	LookAhead = 28,
	-- Slides the whole rig, changes the framing not at all. See above.
	LookHeight = 1.4,

	PosRate = 10,
	RollRate = 7.5,

	SpeedPull = 0.6,
	BoostPull = 0,

	DriftFollow = 0.2,

	Collide = true,
	MinDistance = 6,
	MinChase = 9,

	OrbitChaseBoost = 2.5,

	--== LOOKING AROUND ================================================

	FreeLookSens = 0.0045,
	PadLookSens = 2.1,
	PadLookDeadzone = 0.17,

	LookPitchLimit = 42,
	LookRecenterRate = 7,
}