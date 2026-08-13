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
	--
	-- 62 -> 78. The flip was not only badly shaped, it was RUSHED: one
	-- full turn crammed into 0.68s. More airtime is the half of the fix
	-- that no curve can supply — 1.04s of arc, 0.85s of flip, and the
	-- peak drops from 3.2 revs/sec to 2.1.
	LaunchUp = 78,

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

	-- HOW LATE THE FAST PART LANDS. This is a bias INTO an S-curve, not
	-- a power curve on its own — see the render write, which does
	-- `smoothstep(t ^ Ease)`.
	--
	-- THREE SHAPES HAVE BEEN WRONG HERE, AND ONLY THE LAST IS ABOUT A
	-- NUMBER:
	--
	--   1 - (1-t)^n   ease-OUT. Spends the rotation in the first
	--                 moments and crawls to a stop — the kart looked
	--                 flicked, then hung there.
	--   t^n           ease-IN. Right idea, fatal shape: peak angular
	--                 velocity sits AT t=1, so the flip span fastest in
	--                 the exact frame it stopped dead. 3.2 revs/sec to
	--                 zero in one frame. THAT is why it never felt
	--                 satisfying, and no value of n could fix it.
	--   smoothstep    zero velocity at both ends, but symmetric — the
	--                 fast part sits in the middle and it reads limp.
	--
	-- `smoothstep(t^Ease)` is the combination: eases out of the ramp,
	-- peaks around t=0.69 so it still winds up INTO the landing, and
	-- settles to a stop rather than being switched off mid-spin.
	--
	-- Higher is lazier at the start and later-peaking. 1 is a plain
	-- symmetric smoothstep; past about 2.5 the first half looks dead.
	Ease = 1.5,

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
