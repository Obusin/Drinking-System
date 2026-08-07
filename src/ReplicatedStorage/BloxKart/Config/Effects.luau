--[[
	Effects — trails, speed lines, and the cosmetic body motion.
	None of this feeds back into movement.
--]]

return {
	--== SHIELD BUBBLE =================================================
	-- Authored art, not built in code: a Model (or part) with this name
	-- anywhere inside the kart visual. Found by name so it can be nested
	-- and rearranged freely, and everything below is a no-op if the kart
	-- doesn't have one.
	--
	-- Every part of it is forced non-colliding and non-queryable when
	-- found — it's decoration welded to the kart and must never register
	-- as a wall, least of all to the swept collision of the racer it's
	-- wrapped around.
	-- SLIP ANGLE DRIVES THE RIBBON'S SIZE; the tier drives its COLOUR.
--
-- Two different facts, so two different channels. Colour says "how
-- charged is this drift" — a countdown to a boost. Width says "how hard
-- am I actually sliding right now", which is the thing the driver is
-- controlling moment to moment and had no readout at all.
--
-- Without this a lazy 20-degree drift and a balanced 36-degree one on
-- opposite lock look identical, so the skill of holding a big angle is
-- invisible. Nothing about the handling changes; it is only that the
-- technique becomes legible.
TrailSlipFloor = 12, -- degrees below which the ribbon stays thin
TrailSlipWidth = 2.2, -- width multiplier at full MaxSlip
TrailSlipGlow = 0.5, -- extra LightEmission at full slip
TrailSlipRate = 8, -- how fast width follows the angle

ShieldName = "Shield",
	ShieldTransparency = 0.45, -- how solid it looks while up
	ShieldFadeRate = 8, -- faded rather than toggled: a bubble that pops
	-- into existence reads as a glitch, one that swells reads as a shield

	--== CHARGE TIER COLOURS ===========================================
	TierColors = {
		Color3.fromRGB(70, 150, 255), -- tier 1  blue
		Color3.fromRGB(255, 150, 40), -- tier 2  orange
		Color3.fromRGB(190, 90, 255), -- tier 3  purple
	},

	--== DRIFT TRAILS ==================================================
	TrailBaseColor = Color3.fromRGB(205, 205, 215), -- drifting, uncharged
	TrailLifetime = 0.55, -- how long the ribbon lingers
	TrailWidth = 0.55, -- studs. Set by the attachment spacing
	TrailInset = 2.0, -- how far out from the centreline
	TrailBack = 2.3, -- how far back

	--== BODY MOTION ===================================================
	LeanAngle = 7, -- degrees of body roll into a turn
	DriftLeanBonus = 6, -- extra roll while drifting
	LeanRate = 8,
	--== SPINOUT =======================================================
	-- Multiple fast revolutions with the body thrashing, rather than one
	-- tidy rotation. Getting hit should look like losing control, not
	-- like a turn signal.
	SpinRevolutions = 2.75,
	SpinEase = 1.4, -- <1 front-loaded and violent, >1 winds down harder
	SpinWobble = 22, -- degrees of roll thrown around during the spin
	SpinWobbleRate = 7, -- wobbles per second
	SpinPitch = 9, -- degrees of nose-up/down thrown in

	PitchOnAccel = 3, -- degrees of squat/dive
	PitchRate = 6,

	--== IN THE AIR ====================================================
	-- A hop with a rigid body is a lift, not a jump. These two put some
	-- motion into the 0.2s the kart is off the ground, which is most of
	-- what made the hop read as a state change rather than a movement.
	AirPitch = 7, -- degrees of nose-up while rising, nose-down while
	-- falling. Scaled by vertical speed against Handling.HopSpeed, so it
	-- passes through zero at the apex and is back to nothing on landing.
	HopLean = 5, -- extra degrees of roll toward whatever you are steering
	-- while hopping. This is the ANTICIPATION: the body loads up in the
	-- direction of the drift before the drift exists, so turn-in on
	-- landing continues a movement instead of starting one.

	BobAmount = 0.09, -- fake suspension travel
	BobSpeed = 22,

	--== LANDING =======================================================
	-- Scaled by how hard you actually arrive, because a drift hop and a
	-- fall off a bridge used to produce the identical 0.35 dip. Now the
	-- hop gets a light nod and a real drop gets a proper compression.
	-- THE LANDING DIP IS AN IMPULSE, NOT A POSITION.
	--
	-- It used to be assigned straight onto `squash`, which moves the
	-- kart's visual position — so on the contact frame the whole kart
	-- teleported downward by up to LandSquashMax studs. That instant drop
	-- was the "snap on the ground", and it happened on ARRIVAL, which is
	-- why easing the rebound never touched it.
	--
	-- The spring is given a VELOCITY instead and compresses over about
	-- five frames on its own, which is the suspension doing what it was
	-- always modelled to do. The damping is deliberately low (12 against
	-- a critical ~27.5), so it rings back out rather than sagging.
	--
	-- Doubled, because a spring that has to travel loses half its
	-- amplitude to damping on the way — the old assignment cheated by
	-- starting AT the target.
	-- HOW MUCH OF THE DEPENETRATION IS HIDDEN IN THE SUSPENSION.
	--
	-- Collision is discrete, so on the frame contact is detected the kart
	-- is already up to impact/60 studs UNDER the surface — 2.7 studs at
	-- 164 studs/s. `pos` is corrected upward in one step, and that step
	-- is a position teleport that scales with how hard you landed.
	--
	-- It survived every previous fix because all of them were aimed at
	-- the rebound, and this happens on ARRIVAL.
	--
	-- `squash` is subtracted from the visual position, so adding the
	-- correction to it cancels the jump exactly: the true position is
	-- fixed immediately, the drawn one does not move at all, and the
	-- spring rings the difference out over the next few frames. The
	-- suspension absorbs the collision error, which is precisely what
	-- suspension is for.
	--
	-- 1 is a perfect cancel. Slightly under, because a perfect cancel
	-- means a deep landing takes noticeably longer to return to ride
	-- height, and the eye reads that as sinking.
	LandCatchCorrection = 0.85,

	-- HELD SEPARATELY FROM `squash`, and not because it is tidier.
	--
	-- `squash` is clamped to LandSquashMax (0.9) so the cosmetic dip
	-- cannot get silly. A hard landing needs to absorb up to 2.7 studs of
	-- collision error, so folding the two together meant the clamp ate
	-- most of the catch and the teleport came back at speed — halved
	-- rather than removed.
	--
	-- They are different quantities: one is how much the suspension is
	-- COMPRESSING, the other is how much of the engine's discrete-step
	-- error is still being hidden. Sharing a variable forced one clamp to
	-- serve both.
	LandCatchRecover = 9, -- per second, back to true position

	LandSquashImpulse = 2, -- multiplier on the velocity needed to reach the dip

	LandSquash = 0.22, -- dip on the gentlest landing
	LandSquashMax = 0.9, -- ...and on the hardest
	LandSquashSpeed = 55, -- descent speed, studs/s, that reaches the max

	-- A SPRING, NOT A LERP — and note this is arithmetic in the
	-- controller driving a visual offset, NOT a physics constraint. The
	-- kart is still kinematic and Roblox still gets no vote.
	--
	-- A lerp toward zero can only ever sag back to rest, which reads as a
	-- dead cushion: the kart squats and gives up. Suspension overshoots.
	-- Underdamped on purpose (~zeta 0.44) so it rebounds once, a fifth of
	-- the way past neutral, and settles in about a third of a second.
	--
	-- Raise SquashDamp toward 2*sqrt(SquashSpring) (~27.5) to kill the
	-- rebound entirely; drop it below ~8 and the kart pogos.
	SquashSpring = 190,
	SquashDamp = 12,
	SlopeAlignRate = 9, -- how fast the BODY visually matches the surface.
	-- Lags the simulation slightly so kerbs don't jolt it.

	--== DEBUG =========================================================
	ShowState = false, -- print state / speed / tilt / tier while driving
}
