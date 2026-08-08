--[[
	Trick — flip ramps.

	Hit a ramp, the kart throws a flip, you land with a little boost. The
	Mario Kart trick, and the reason it exists there: it turns every jump
	from a gap you survive into a thing you WANT to hit.

	THE FLIP IS VISUAL. THE KART FLIES ITS NORMAL ARC.
	--------------------------------------------------
	Nothing here rotates the simulation. `up` and `forward` are untouched,
	so the ground probe, the landing and the sweep all behave exactly as
	they would on any other jump — you come down level, every time,
	however many turns the art did.

	The alternative is genuinely rotating the kart, and it is a trap: the
	moment `up` is upside down, surface gravity is pointing at the sky,
	the ground probe is looking the wrong way, and a landing mid-rotation
	is undefined. All of that for something the player only ever sees.

	IT ENDS LEVEL BY CONSTRUCTION, NOT BY TIDYING UP.
	-------------------------------------------------
	The rotation is a whole number of turns spread across the expected
	airtime, so the end pose IS the start pose — the same trick the props
	timeline uses. It cannot land crooked, because at t=1 the angle is
	`turns * 2pi`, which is zero.

	Airtime is worked out at launch from the kick and gravity, so the
	flip is paced to the jump rather than to a fixed duration that would
	be wrong on every ramp of a different height.
--]]

return {
	Enabled = true,

	-- Tag a part with this. Its UP is the launch direction, the same as a
	-- glide ramp — aim it by rotating it in Studio.
	RampTag = "FlipRamp",

	-- Below this it is just a bump. Stops a kart nudging onto a ramp and
	-- getting a free trick.
	MinSpeed = 30,

	-- Studs/s of upward kick, along the RAMP's up.
	LaunchUp = 62,

	-- OFF THE GROUND, SAID OUT LOUD. A kick alone does not clear
	-- GroundSnap within a frame, so without this the next probe still
	-- reports contact and the ramp re-triggers. The glide ramp learned
	-- this the hard way.
	MinAirTime = 0.3,

	--== THE TRICKS ===================================================
	-- Picked at random unless the ramp names one in a `Trick` attribute,
	-- so a ramp CAN be authored to always throw the same shape while the
	-- default stays varied.
	--
	-- `axis` is in the KART's frame: X is its right, Y its up, Z its
	-- back. So a flip about X is a front or back flip, about Z a barrel
	-- roll, about Y a flat spin.
	Tricks = {
		{ id = "frontflip", axis = "X", turns = 1 },
		{ id = "backflip", axis = "X", turns = -1 },
		{ id = "barrel", axis = "Z", turns = 1 },
		{ id = "spin", axis = "Y", turns = 1 },
		{ id = "double", axis = "X", turns = 2 },
	},

	-- Fraction of the airtime the flip occupies. Under 1 so it FINISHES
	-- before touchdown rather than at it — landing mid-rotation reads as
	-- a crash even when the maths is exact, because the eye wants to see
	-- the kart settled before the wheels arrive.
	Window = 0.82,

	-- SLOW OFF THE RAMP, FAST INTO THE LANDING. This is an ease-IN, and
	-- it is the opposite of what was here.
	--
	-- `1 - (1-t)^n` is an ease-OUT: most of the rotation is spent in the
	-- first moments and it crawls to a stop. That reads as the kart being
	-- flicked and then hanging there, which is why it looked like several
	-- fast flips rather than one deliberate one.
	--
	-- `t^n` puts the speed at the END. The kart leaves the ramp with a
	-- lazy hang, winds up through the arc, and whips through the last
	-- part just as the ground arrives — so the fastest moment and the
	-- landing coincide, which is what makes it feel earned rather than
	-- merely completed.
	--
	-- Higher is lazier at the start and more violent at the end. Past
	-- about 3 the first half looks like nothing is happening.
	Ease = 2.2,

	--== THE REWARD ===================================================
	-- Reported as `boostFired`, the same event a drift release uses — so
	-- the sound, the VFX and the thruster flare all come for free and can
	-- never drift out of sync with the originals.
	BoostSpeed = 140,
	BoostTime = 0.9,
	BoostTier = 2,

	-- Only if the flip actually completed. Bailing out early — landing
	-- before the rotation finished — should cost you the boost, or the
	-- ramp is a free boost dispenser and the trick is decoration.
	RequireLanding = true,

	Debug = false,
}
