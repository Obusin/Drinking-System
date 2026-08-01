--[[
	Camera — chase cam, FOV, and looking around.
--]]

return {
	--== FIELD OF VIEW =================================================
	-- Speed is sold with FOV, not distance. Pulling the camera back to
	-- convey speed just makes the kart smaller and harder to place on the
	-- road; widening the lens smears the edges of the screen and reads as
	-- pace without costing you any control.
	FovBase = 70,
	FovAtTopSpeed = 92, -- most of "feeling fast" is this

	-- HELD while a burn stage is running, and each stage is wider than
	-- the last. This is the escalation: one tank opens the view, two
	-- opens it further, three is the widest the camera ever goes.
	--
	-- A punch alone could not do that. It was added to the CURRENT field
	-- of view and then eased back toward a speed-only target, so by the
	-- time the next stage fired the last one had already decayed —
	-- every stage started from the same place and none of them built.
	BoostFovStage = { 5, 12, 21 },

	-- The kick ON TOP, when a stage begins. Smaller than it was, because
	-- the hold above is now doing the work the punch was being asked to
	-- do on its own.
	BoostFovPunch = 7,

	FovRate = 5, -- easing back DOWN
	-- Easing UP is faster on purpose. A boost should arrive rather than
	-- drift in, and the same rate in both directions makes the widest
	-- stage feel like it is still opening when the burn has already
	-- ended.
	FovRiseRate = 13,

	--== THE REST OF THE SPEED FEEL ====================================
	-- All of it lives on the camera. Streaks flying at the screen were
	-- tried and removed: they are drawn ON the glass, so they say the
	-- SCREEN is moving fast rather than the kart, and at three stages
	-- they turned the track into confetti at the moment it most needed
	-- reading.
	--
	-- Everything below moves the actual camera instead, which is the
	-- only thing that can make the WORLD look fast.

	-- Pulled back per burn stage. A wider view with the kart smaller in
	-- it reads as covering ground, and it compounds with the field of
	-- view rather than fighting it.
	BoostPullBack = { 1.6, 3.4, 5.8 },

	-- And dropped slightly, so the camera is closer to the road. Height
	-- is most of why a kart cam feels slow: the further above the
	-- surface you are, the less of it appears to move.
	BoostDrop = { 0.3, 0.7, 1.2 },

	-- Positional noise, in studs. TINY on purpose — this is engine
	-- vibration, not an earthquake, and anything you can consciously see
	-- becomes motion sickness within a lap.
	BoostShake = { 0.06, 0.14, 0.26 },
	BoostShakeSpeed = 34, -- how fast the noise moves

	-- The camera falls behind at the start of a burn and catches up.
	-- This is the strongest speed cue available and the cheapest: being
	-- overtaken by your own kart for a quarter of a second says "that
	-- accelerated" better than any amount of blur.
	BoostLag = { 0.9, 2.0, 3.4 },
	BoostLagRecover = 3.5, -- studs per second it reels back in

	--== BLUR ==========================================================
	-- Kept, because it is a camera effect rather than something drawn
	-- over the world. Small numbers: this is a suggestion of motion, and
	-- more makes the track unreadable exactly when it needs reading.
	BoostBlur = { 3, 6, 10 },
	BlurRate = 6,

	--== CHASE CAM =====================================================
	-- The default Roblox camera is locked to world-up, so it would stay
	-- upright while the kart rolled around a loop — unwatchable. This
	-- one rolls with the track normal instead.
	Enabled = true,
	Distance = 13, -- studs behind the kart
	Height = 4.5, -- studs above it, along OUR up
	LookAhead = 8, -- how far ahead it aims
	LookHeight = 2.2,
	PosRate = 9, -- how fast the camera chases position
	RollRate = 7, -- how fast it rolls onto a new surface. Slower than
	-- the kart on purpose — the lag is what sells a loop.
	-- Both zero on purpose: FOV does this job now. Raise them only if you
	-- want the camera to physically back off as well.
	SpeedPull = 0, -- extra distance at top speed
	BoostPull = 0, -- extra distance while boosting
	DriftFollow = 0.35, -- 0 = camera stays behind the direction of
	-- TRAVEL, so a drift reads fully sideways on screen. 1 = follows
	-- the body round, which kills the effect.
	Collide = true, -- pull in when scenery gets between camera and kart.
	-- Matters on loops, where the track itself is often behind you.
	MinDistance = 4, -- closest the COLLISION pull-in may bring it, when
	-- squeezing the camera past scenery
	-- Absolute floor, enforced after everything else. Measured from the
	-- kart's CENTRE, so it has to clear half the hitbox length (3.5) with
	-- room to spare — below about 6 you're looking at the driver's head.
	-- This is what stops the kart catching its own camera during look-back
	-- at speed; see CameraRig for why that happens.
	MinChase = 8,
	OrbitChaseBoost = 2.5, -- position chases this much harder while
	-- free-looking, so the orbit feels attached to the mouse

	--== LOOKING AROUND ================================================
	-- A Scriptable camera loses Roblox's mouse orbit, so it's rebuilt.
	-- Orbit happens in the KART's frame, not the world's, so it still
	-- behaves upside-down on a loop.
	FreeLookSens = 0.006, -- radians per pixel of mouse movement
	PadLookSens = 2.6, -- radians/sec at full right-stick deflection
	PadLookDeadzone = 0.15,
	LookPitchLimit = 55, -- degrees up/down before it stops
	LookRecenterRate = 6, -- how fast free-look swings back when you let
	-- go. Racing cameras should recentre.
	-- Look-back is NOT eased — it's a hard cut, like a mirror. Easing it
	-- just means half a second of staring at your own back wheels.
}
