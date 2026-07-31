--[[
	Spectate — watching once you're out of the race.

	Two modes: orbit a racer, or fly the camera. The orbit is what you
	want almost always; free cam is for looking at the track rather than
	at a driver.
--]]

return {
	--== FOLLOW ========================================================
	Distance = 26, -- studs behind the subject, at default zoom
	DistanceMin = 10,
	DistanceMax = 90,
	ZoomStep = 6, -- studs per scroll notch

	LookHeight = 3, -- aim a little over the roof rather than at the floor

	-- How fast the camera chases. Smoothed because a spectated kart
	-- arrives in replication steps, and an unsmoothed follow turns those
	-- steps into judder. Switching subject cuts rather than sweeps.
	Follow = 6,

	-- How fast the AIM point chases the kart, separately from the camera
	-- body. Faster on purpose: the aim has to stay locked on or the
	-- subject slides toward the edge of frame through a corner, whereas
	-- the body can afford to lag because nothing is measured against it.
	--
	-- This is what takes the shake out of watching a bot. Their karts are
	-- anchored and server-written, so they arrive in replication steps,
	-- and aiming at the raw position puts every one of those steps into
	-- the camera's ROTATION — which is precisely where the eye sees it.
	FocusFollow = 14,

	--== LOOK ==========================================================
	-- Radians per pixel of mouse movement.
	LookSensitivity = 0.006,
	PitchMin = -80, -- degrees. Not quite +/-90: straight down the axis is
	PitchMax = 70, -- where lookAt has no answer and the view rolls

	--== FREE CAM ======================================================
	FreeSpeed = 90, -- studs/s
	FreeBoost = 3.5, -- multiplier while shift is held. Tracks are big;
	-- crossing one at walking pace is not a camera, it's a chore
}
