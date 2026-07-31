--[[
	Spectate — watching the rest of the race after you've finished.

	A plain chase camera, and plain on purpose. A spectator view that
	tries to be clever about corners is one that loses the subject at
	exactly the moment something interesting happens to them.
--]]

return {
	Distance = 26, -- studs behind the kart
	Height = 9, -- and above it
	LookHeight = 3, -- aim a little over the roof rather than at the floor

	-- How fast the camera chases. Smoothed because a spectated kart
	-- arrives in replication steps, and an unsmoothed follow turns those
	-- steps into judder. Switching subject cuts rather than sweeps.
	Follow = 6,
}
