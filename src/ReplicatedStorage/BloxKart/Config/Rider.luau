--[[
	Rider — the driver: steering wheel rotation and hand IK.
	Cosmetic only. Runs for every kart in the world, not just yours.
--]]

return {
	--== WHEEL =========================================================
	-- How much of the drift counter-steer shows on the STEERING wheel, on
	-- top of the player's own input. The hands follow via IK, so this is
	-- what makes the driver look like they're working to hold a slide
	-- rather than just holding a key.
	--
	-- Less than the tyres get, because a driver's arms don't travel as far
	-- as the front wheels do. 0 shows pure input, which is the honest
	-- reading of what the player is actually pressing.
	WheelCounterSteer = 0.55,

	MaxWheelAngle = 130, -- degrees of wheel rotation at full lock
	WheelSmoothing = 9, -- how fast the wheel chases the input. Kept a
	-- little AHEAD of Handling.SteerSmoothing on purpose: the driver
	-- turns the wheel and the kart answers, not the other way round.
	InvertWheel = false, -- flip if the wheel turns the wrong way

	--== HANDS =========================================================
	-- Uses Roblox's IKControl rather than writing Motor6D joints by
	-- hand. That matters: the Animator OWNS Motor6D.Transform and
	-- composes it away every frame, so a hand-rolled solver loses
	-- whatever it writes. Disabling the animation to win that fight
	-- makes it worse — the Animator then stops flushing at all and the
	-- driver stands bolt upright. IKControl is applied by the animation
	-- system itself, so it layers on top of the sit pose instead of
	-- competing with it. See "Motor6D Transform vs C0" in the vault.
	IKEnabled = true,

	-- Root each arm at its OWN shoulder.
	--
	-- Rooting both at the torso looks tempting — the driver would twist
	-- into the turn — but it gives the two chains a SHARED root, and
	-- they then fight over it: solving one arm drags the torso out from
	-- under the other. That's what left one hand welded to the wheel and
	-- the other floating near it. Disjoint chains both solve cleanly.
	--
	-- Set true only if you want that twist badly enough to live with one
	-- arm being approximate.
	IKChainFromTorso = false,

	IKWeight = 1, -- 0..1. Lower to blend back toward the sit animation
	IKSmoothTime = 0.06, -- seconds of easing. 0 is rigid, high is floaty

	-- Where the elbows are pulled toward. Without a pole the solver is
	-- free to put the elbow anywhere on the circle around the
	-- shoulder-to-hand axis, and it picks straight out sideways — chicken
	-- wings. This drags them down and in against the ribs.
	--
	-- Kart-local studs, relative to the hitbox centre. X is mirrored for
	-- the left arm. +Y up, +Z backwards (toward the driver).
	--   raise Y      -> elbows higher
	--   raise X      -> elbows further out
	--   raise Z      -> elbows further back, tucked behind the wheel
	--   negate X     -> swaps the poles across the body entirely
	--
	-- Tried Z = -0.6 (elbows forward, toward the wheel) on the theory
	-- that a reaching arm folds ahead of the shoulder. Looked worse in
	-- practice, so it's back at +1.0. Don't re-derive that from first
	-- principles — it was tested.
	ElbowPole = Vector3.new(1.15, 1.35, 1.0),

	Debug = false, -- report in Output why the IK is idle. Turn off once
	-- the hands are on the wheel.
}
