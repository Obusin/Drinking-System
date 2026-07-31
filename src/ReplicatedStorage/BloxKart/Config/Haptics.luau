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

	--== THE BED — MOSTLY OFF, AND THAT IS THE DESIGN ================
	-- The motors should be at ZERO most of the time you are driving.
	--
	-- Continuous rumble is what wears a controller out and flattens its
	-- battery: an impact is a few hundred milliseconds, a bed runs for
	-- the entire race. The first version had road noise scaling with
	-- speed, which meant both motors spinning every second the kart was
	-- moving. That is hard on the hardware and, worse, it is useless —
	-- a signal that is always present tells the player nothing.
	--
	-- So the bed is EVENT-SHAPED now. It fires when something is
	-- genuinely happening to the tyres and is silent otherwise, which is
	-- both kinder to the pad and more informative.

	-- Road noise from speed alone: OFF.
	--
	-- This was the expensive one — always on, always the same, and the
	-- least informative thing here. Left as a dial rather than deleted
	-- because it is defensible on a wheel or a pad being charged; just
	-- know it runs a motor continuously for the whole race.
	SpeedRumble = 0,

	-- Tyre scrub, and only once the tyres are genuinely working. Below
	-- the threshold there is nothing to say and the motor stays off, so a
	-- straight is completely silent and a corner is not.
	ScrubRumble = 0.22,
	ScrubThreshold = 0.45, -- tyreLoad below this produces no rumble

	-- Nitro. Brief by nature, so it costs nothing to let it speak.
	BoostRumble = 0.16,

	--== IMPACTS ======================================================
	-- Seconds for a punch to fade out. Short: a jolt that outstays its
	-- welcome stops reading as an impact and starts reading as a fault.
	PunchDecay = 0.3,

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
	-- Also thresholded, for the same reason as the scrub: gentle
	-- cornering is not a traction event, and a trigger buzzing through
	-- every mild corner is the fastest way to make a player turn rumble
	-- off entirely.
	TriggerSlip = 0.5,
	TriggerThreshold = 0.5, -- slip below this leaves the triggers alone
}
