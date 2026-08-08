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

	--== FLIPPING =====================================================
	-- The camera does NOT roll with the kart. A camera that flips with a
	-- barrel roll is a camera nobody can play through — the horizon
	-- inverts, and the player loses the one reference they steer against.
	-- It shakes and widens instead, which reads as "something big is
	-- happening" without taking the world away.
	FlipShake = 0.42,
	FlipFov = 5, -- degrees wider through the trick
	FlipPull = 3.5, -- studs further back, to fit the kart in

	--== GLIDING ======================================================
	-- Pulled back and raised. A glider is about where you are GOING —
	-- the gap, the landing zone — and the ground game's tight framing
	-- puts all of that off the bottom of the screen.
	GlideFov = 6, -- degrees wider
	GlidePull = 7, -- studs further back
	GlideRise = 3, -- studs higher, to show the ground you are crossing
	GlideRate = 2.5, -- how fast it eases in and out

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