--[[
	Suspension — how the wheels ride the road. PURELY COSMETIC.

	THE CONSISTENCY RULE STILL HOLDS, AND THIS IS THE FILE MOST LIKELY TO
	BREAK IT IF SOMEBODY IS CARELESS LATER.
	--------------------------------------------------------------------
	Every number here moves a wheel on SCREEN. Not one of them reaches
	Simulation. The controller still reads exactly the Hitbox and the
	Seat, so a kart with soft springs and a kart with none handle
	identically and always will.

	The moment a suspension ray starts informing grip, ride height or
	collision, art has an opinion about handling — which is the thing the
	whole architecture exists to prevent.

	WHY THIS IS WHAT FOUR SEPARATE WHEELS BOUGHT
	--------------------------------------------
	Two combined wheels can only move together, so the best they can do is
	bob. Four independent wheels each read their own patch of ground: ride
	a kerb with the left pair and the left pair rises, on its own, while
	the right stays down. That asymmetry is the entire read — it is what
	makes a kart look like it is ON a surface rather than sliding above
	one.

	IT IS A REAL SPRING, NOT A CHASE
	--------------------------------
	Approaching a target gets there and stops, which reads as the wheel
	being dragged. A spring with damping OVERSHOOTS and settles, so
	landing gives you the little bounce that sells the weight.

	DAMPING IS A RATE, AND IT HAS A RIGHT ANSWER.
	---------------------------------------------
	The first cut wrote `vel *= 0.82 ^ dt`, treating damping as a fraction
	kept per second. At 60fps that is 0.9967 per frame — very nearly no
	damping at all — so the wheel overshot to the bump stop and then
	oscillated for as long as you cared to watch. It looked like a
	suspension bug and was really a units bug.

	It is `exp(-Damping * dt)` now, and Damping is tied to Stiffness the
	way it is in any real spring:

	    Damping = 2 * sqrt(Stiffness) * zeta

	zeta is the character. 1.0 is critical — no bounce at all. Below that
	it overshoots, and how much is worth knowing before you touch it:

	    zeta 0.45  ->  19% overshoot, settles in 0.60s   (floaty)
	    zeta 0.60  ->   7% overshoot, settles in 0.53s   (here)
	    zeta 0.75  ->   1% overshoot, settles in 0.38s   (taut)

	A go-kart is stiff and light, so it wants the taut end with just
	enough overshoot to be visible. 0.6 gives one clear bounce on landing
	and nothing on small bumps, which is the read.
--]]

return {
	Enabled = true,

	-- How far below its resting height a wheel will look for ground. Past
	-- this it is treated as airborne and droops.
	RayLength = 6,

	-- The most a wheel can move up into the body. Small on purpose: a
	-- kart has almost no suspension travel, and too much makes it read as
	-- a 4x4. This is the number to raise for cartoonier bounce.
	Travel = 0.85,

	-- And how far it hangs down when there is nothing under it. Less than
	-- Travel, because wheels drop out of an arch further than they tuck
	-- into one — and because a kart in the air with its wheels dangling
	-- looks broken rather than airborne.
	Droop = 0.35,

	-- Spring rate. Higher is tighter and more immediate.
	Stiffness = 170,
	-- Decay RATE, not a fraction — see the note above. 15.6 is
	-- 2*sqrt(170)*0.6, which is a damping ratio of 0.6: one visible
	-- bounce on landing, dead flat over small bumps.
	--
	-- Change Stiffness and this should move with it, or the character
	-- changes as a side effect: 2*sqrt(Stiffness)*0.6.
	Damping = 15.6,

	-- LANDING.
	--
	-- A spring alone barely reacts to a hard landing, because the wheel
	-- only ever has Travel studs to give. This adds compression scaled by
	-- how fast the kart was falling, which is the difference between
	-- touching down and ARRIVING.
	LandingKick = 0.045, -- studs of extra squash per stud/s of fall
	LandingMax = 1.2, -- ceiling on it, so a long drop cannot fold the kart
	LandingSpeed = 12, -- fall speed below which a landing is not a landing

	-- Ride the same rig as everything else: a wheel's resting height above
	-- the road is its own radius, and Rig.RoadWheelRadius already states
	-- it for the rolling maths. Stated here as a trim in case the art's
	-- pivot is not at the axle.
	RadiusTrim = 0,

	Debug = false,
}
