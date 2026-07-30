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
	BoostFovPunch = 16,
	FovRate = 5,

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
