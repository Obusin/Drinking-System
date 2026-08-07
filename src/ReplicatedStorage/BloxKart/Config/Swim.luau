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

	--== FLOATING =====================================================
	-- The body bobs on the swell. Rides the SAME body motor as the roll
	-- and squash, so it composes with them instead of fighting: a kart
	-- landing in water still dips, it just dips while bobbing.
	BobHeight = 0.35, -- studs
	BobRate = 0.9, -- cycles per second
	-- A second, faster, smaller wave. One sine reads as a machine; two
	-- at unrelated rates reads as water.
	BobHeight2 = 0.12,
	BobRate2 = 2.3,

	-- Lean into turns harder than on land, because a hull rolls more than
	-- a chassis does.
	RollScale = 1.6,

	--== SPRAY ========================================================
	SpraySoundId = "",
	SprayVolume = 0.5,

	Debug = false,
}
