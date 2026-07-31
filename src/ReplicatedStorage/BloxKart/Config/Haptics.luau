--[[
	Haptics — controller rumble.

	TWO THINGS, KEPT APART
	----------------------
	A continuous bed proportional to what the tyres are doing, and short
	impacts that punch through it. The bed has to stay quiet or the
	impacts have nothing to punch through, and a motor that is always on
	carries no information at all — the player stops feeling it within a
	lap.

	If in doubt, turn the bed DOWN. Rumble is at its best when you only
	notice it changing.

	All values are 0..1 motor strength.
--]]

return {
	Enabled = true,

	-- Below this a motor either won't spin or whines instead of
	-- rumbling, so anything under it is sent as a clean zero.
	MotorFloor = 0.06,

	--== THE BED ======================================================
	-- Road noise: scales with speed, and is the reason a fast kart feels
	-- heavier than a slow one. Silent while airborne, on purpose — that
	-- gap is what makes a landing land.
	SpeedRumble = 0.16,

	-- Tyre scrub, on the small motor where detail belongs. Follows
	-- tyreLoad, so it rises through a hard corner and peaks when you're
	-- fighting a slide — the same signal the screech follows.
	ScrubRumble = 0.34,

	-- Nitro and boost pads, layered on top. A whine rather than a thump,
	-- which is why it goes to the small motor.
	BoostRumble = 0.22,

	--== IMPACTS ======================================================
	-- Seconds for a punch to fade out. Short: a jolt that outstays its
	-- welcome stops reading as an impact and starts reading as a fault.
	PunchDecay = 0.35,

	-- How much of a punch reaches the small motor. Under 1 so a hit is
	-- felt mostly as a thump in the body of the pad rather than as a
	-- buzz, which is what an impact feels like.
	PunchSmallShare = 0.55,

	-- Per-event weight, 0..1. A missile is the loudest thing that can
	-- happen to you; a landing is routine and mustn't compete with it.
	HitPunch = 1,
	BlockedPunch = 0.45, -- a shield eating a hit. Softer, and reassuring
	LandPunch = 0.35,
	BoostPunch = 0.5, -- nitro lighting
	DriftPunch = 0.25, -- the hop into a drift

	--== TRIGGERS =====================================================
	-- Only on controllers that have trigger motors; everything here is
	-- silently skipped where they don't exist.
	--
	-- This is the one that makes a pad feel like a car. The throttle
	-- trigger fights back as the rears let go, so a slide is something
	-- you feel in the finger already holding the throttle — which is the
	-- fastest route into a driver there is. The brake trigger carries
	-- the same signal while braking, the way an ABS pedal does.
	TriggerSlip = 0.7,
}
