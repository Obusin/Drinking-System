--[[
	Hud — shared look for every on-screen readout.

	Font and colours live here rather than in each HUD module, so the
	whole interface restyles from one place.
--]]

return {
	-- Resolved with Font.fromName, with a fallback if it isn't installed.
	FontName = "Zekton",
	FontWeight = Enum.FontWeight.Bold,

	-- Nothing has a panel behind it, so text carries its own contrast.
	StrokeTransparency = 0.45,

	--== TIME / LAP  (top right, after the reference) ==================
	RacePosition = UDim2.new(1, -22, 0, 16),
	RaceAnchor = Vector2.new(1, 0),
	RaceLabelColor = Color3.fromRGB(150, 200, 245), -- the small "TIME" / "LAP"
	RaceValueColor = Color3.fromRGB(255, 255, 255),
	RaceTimeSize = 34,
	RaceLapSize = 40,
	RaceSmallSize = 15,

	--== RIVAL SPOTLIGHT ===============================================
	-- Below the instruments: a rival should be noticed, never cover the
	-- road or compete with the time/lap readout.
	RivalPosition = UDim2.new(1, -22, 0, 158),
	RivalHold = 1.65,
	RivalFade = 0.35,
	RivalWidth = 290,
	RivalHeight = 74,
	-- Phone card sits in the narrow gap between the timer and live order.
	-- It is an acknowledgement of a pass, not a panel that takes over play.
	MobileRivalPosition = UDim2.new(1, -14, 0, 126),
	MobileRivalWidth = 176,
	MobileRivalHeight = 48,

	--== LIVE STANDINGS ================================================
	-- Server-fed top five. It begins below the rival card so instruments,
	-- encounter feedback, and the running order each own a clean band.
	StandingsPosition = UDim2.new(1, -22, 0, 246),
	StandingsAnchor = Vector2.new(1, 0),
	StandingsWidth = 238,
	StandingsRowHeight = 27,
	StandingsRows = 5,
	StandingsTitleSize = 13,
	StandingsNameSize = 15,
	MobileStandingsPosition = UDim2.new(1, -14, 0, 210),
	MobileStandingsWidth = 144,
	MobileStandingsRowHeight = 21,
	MobileStandingsTitleSize = 10,
	MobileStandingsNameSize = 11,

	--== WRONG WAY =====================================================
	-- The loudest thing on screen, and the only red. Everything else in
	-- this HUD is monochrome specifically so that this reads as an alarm
	-- rather than as more furniture.
	--
	-- Above centre, clear of MatchHud's countdown slot (0.44) so the two
	-- can never stack into an unreadable pile.
	WrongWayPosition = UDim2.fromScale(0.5, 0.26),
	WrongWayText = "⟲  WRONG WAY",
	WrongWaySize = 46,
	WrongWayColor = Color3.fromRGB(255, 80, 80),
	WrongWayPulse = 2.2, -- pulses per second
	WrongWayFade = 0.55, -- how far the pulse fades. Deliberately NOT 1:
	-- a warning that blinks fully off is easy to miss between blinks.

	-- Scramble (inverted steering). Shares the alert slot with wrong-way
	-- and loses to it on priority — see init.client. Different colour so
	-- the two are never confused at a glance.
	ScrambledText = "⇄  CONTROLS SCRAMBLED",
	ScrambledColor = Color3.fromRGB(200, 130, 255),

	--== INCOMING ======================================================
	-- Something is locked onto you. Shares the alert slot and OUTRANKS
	-- everything in it: wrong way and scrambled will still be true in a
	-- second, and a missile will not.
	IncomingText = "INCOMING",
	IncomingColor = Color3.fromRGB(255, 120, 110),
	-- Seconds out at which the warning appears. Long enough to use a
	-- shield, short enough that it is not on screen for half the lap.
	IncomingLead = 3.0,
	-- MINIMUM TIME ON SCREEN once it appears. A missile fired from close
	-- behind is only a threat for a fraction of a second, and a warning
	-- that comes and goes inside a few frames is one nobody ever sees —
	-- which is indistinguishable from a warning that never fired.
	IncomingHold = 0.7,

	-- Shown while a wind-up item is on its way. NAMED, because "you are
	-- about to be struck by Lightning" is a different thing to know than
	-- "something is coming" — and it is the only warning that can name
	-- what is coming before it arrives.
	WarnedText = "%s INCOMING",

	--== THE ICON =====================================================
	-- Every warning carries the item's own icon, so what is coming is
	-- readable before the words are. The catalogue already has one for
	-- every item; the alert was the one place still describing them in
	-- text alone.
	AlertIconSize = 34,
	AlertIconGap = 12,

	--== BLINK RATE AS A CLOCK =========================================
	-- The pulse carries the time remaining: slow while there is room,
	-- accelerating as it runs out. It is the same information a bar
	-- would carry, in a thing that is already blinking, without adding
	-- another readout to a racing screen.
	-- STATIC FIRST, THEN BLINK. Below this urgency the alert is simply
	-- on — solid and readable. Above it, it starts blinking and speeds
	-- up as it runs out.
	--
	-- A warning that blinks from the moment it appears is a warning with
	-- nothing left to say when the situation actually gets urgent. The
	-- blink has to MEAN something, so it has to start somewhere.
	AlertBlinkFrom = 0.55,
	AlertPulseSlow = 1.6, -- pulses per second as blinking begins
	AlertPulseFast = 9.0, -- about to happen

	--== HIT FEED ======================================================
	-- "MISSILE hit Obus1n". Top centre, under the countdown's slot, so it
	-- reads without competing with the instruments in the corners.
	FeedPosition = UDim2.fromScale(0.5, 0.13),
	FeedRows = 4, -- older lines pushed down and faded out
	FeedRowHeight = 24,
	FeedSize = 18,
	FeedHold = 3.2, -- seconds at full strength before fading
	FeedFade = 1.2, -- seconds to fade out
	FeedColor = Color3.fromRGB(230, 235, 245),
	-- The attacker and victim are tinted so a glance tells you whether it
	-- was you, without reading the whole line.
	FeedSelfColor = Color3.fromRGB(255, 200, 90),
	FeedItemColor = Color3.fromRGB(255, 120, 110),

	--== CONTROLS OVERLAY ==============================================
	ControlsPosition = UDim2.new(0, 18, 1, -18), -- bottom-left
	ControlsAnchor = Vector2.new(0, 1),
	ControlsKeySize = 15,
	ControlsLabelSize = 14,
	ControlsRowHeight = 19,
	ControlsKeyWidth = 62, -- column width for the key column
	ControlsKeyColor = Color3.fromRGB(255, 255, 255),
	ControlsTextColor = Color3.fromRGB(168, 176, 194),

	-- Shown on entering a kart, then faded out. A permanent controls
	-- list is clutter once you know them; a toggle brings it back.
	ControlsShowSeconds = 8,
	ControlsFadeTime = 0.6,
	-- H is the horn. Keep the controls overlay on an otherwise unused key
	-- so ContextActionService never has to decide which of two actions wins.
	ControlsToggleKey = Enum.KeyCode.F1,
	ControlsToggleGamepadKey = Enum.KeyCode.DPadUp,

	--== ITEM SLOTS ====================================================
	-- MOVED OUT OF THE CORNER 2026-08-06. The old note here argued for
	-- the right-hand edge, to leave the centre of the screen clear for
	-- the track. That is a good argument for things you GLANCE at and
	-- the wrong one for things you ACT on.
	--
	-- The item slot and the boost meter are decisions, not readouts, and
	-- they were 700 pixels apart and both a long way from the kart. You
	-- read your speed occasionally; you check what you are holding in the
	-- middle of a corner, which is exactly when you cannot afford to look
	-- at a corner of the screen.
	--
	-- So they cluster together just under the kart, where the eye
	-- already is. The dial stays bottom-right — it IS a glance readout,
	-- and it is the one thing here big enough to cover road.
	--
	-- Dead centre now that the nitro bar has moved onto the kart. It was
	-- offset to the left to sit beside the bar; with the bar gone there
	-- is nothing to make room for, and off-centre would just look wrong.
	ItemPosition = UDim2.new(0.5, 0, 1, -38),
	ItemAnchor = Vector2.new(0.5, 1),
	ItemSlotSize = 58,
	ItemSlotGap = 7,

	--== SPEEDOMETER ===================================================
	-- Round analog dial, bottom right, after Speed Drifters. Drawn from
	-- rotated frames rather than an image: ticks positioned radially and
	-- a needle pivoting from its base. No assets to make or upload, and
	-- it scales to any resolution.
	SpeedPosition = UDim2.new(1, -20, 1, -20), -- bottom right
	SpeedAnchor = Vector2.new(1, 1),

	DialSize = 152, -- px across
	DialStartAngle = 225, -- lower-left, in standard maths degrees
	DialSweep = 270, -- clockwise round through the top to lower-right
	-- 31 ticks with every 6th a major, so the majors land exactly on the
	-- 6 numerals. Evenly-weighted ticks all the way round is the thing
	-- that makes a gauge look generated rather than designed — real ones
	-- have a clear major/minor rhythm you can read at a glance.
	DialTicks = 31,
	DialTickLength = 11,
	DialTickWidth = 3,
	DialMajorEvery = 6,
	DialMajorLength = 20,
	DialMajorWidth = 5,
	DialTickRadius = 0.40, -- of DialSize, to the tick's outer end

	-- Numerals at the majors. The single biggest "this is a real
	-- instrument" signal, and the reference has them.
	DialNumerals = 6,
	DialNumeralRadius = 0.27,
	DialNumeralSize = 11,
	DialNumeralColor = Color3.fromRGB(190, 190, 190),

	-- Redline. Marked even when unlit, so the top of the gauge always
	-- looks like somewhere you have to earn.
	-- Monochrome, so the redline is marked by WEIGHT rather than hue —
	-- a brighter grey that stands out from the unlit ticks without
	-- reintroducing colour.
	DialRedlineFrom = 0.80, -- fraction along the sweep
	DialRedlineColor = Color3.fromRGB(140, 140, 140),

	-- Borderless: no fills anywhere structural. The face is a stroke,
	-- not a disc. Set DialFaceTransparency below 1 if you ever want the
	-- solid-panel look back.
	DialFaceColor = Color3.fromRGB(14, 19, 33),
	DialFaceTransparency = 1,
	DialRimColor = Color3.fromRGB(255, 255, 255),
	DialRimThickness = 3,
	DialRimTransparency = 0.2,
	DialBezelInset = 13, -- inner ring, for a bit of depth
	DialBezelColor = Color3.fromRGB(160, 160, 160),

	NeedleLength = 46,
	NeedleWidth = 4,
	NeedleTail = 13, -- counterweight past the pivot. Every real needle
	-- has one, and its absence is quietly obvious.
	NeedleColor = Color3.fromRGB(255, 255, 255),
	NeedleTailColor = Color3.fromRGB(120, 120, 120),
	NeedleSmoothing = 9, -- the needle lags a touch, like a real one

	--== NITRO BAR =====================================================
	-- A horizontal segmented bar, not a canister. Three wide cells read
	-- faster than three stacked ones, and it sits under the dial as part
	-- of the same cluster.
	--
	-- Built with UIListLayout + UIFlexItem so the cells divide the width
	-- themselves — no arithmetic, and changing NitroSegments needs no
	-- other edit. Wrapped in a CanvasGroup so the whole thing fades on
	-- one property instead of tweening every child.
	--== THE BAR LIVES ON THE KART =====================================
	-- Not on the screen at all. A boost meter is the one readout you
	-- watch WHILE steering, so putting it on the kart means it is inside
	-- the same glance — you are already looking there.
	--
	-- THE USUAL OBJECTIONS TO A BILLBOARD DO NOT APPLY TO YOUR OWN KART,
	-- which is why the Phase 7 note argued against them and this is still
	-- fine. Those objections are about OTHER people's karts:
	--
	--   "it shrinks with distance"  -- Size is in OFFSET (pixels), not
	--     scale, so it is a constant size on screen however far the
	--     chase camera has pulled back. Scale sizing is what shrinks.
	--   "it hides behind geometry"  -- AlwaysOnTop.
	--   "it competes with the track" -- it is a thin bar clear of the
	--     kart, and it is the only thing in world space.
	--
	-- Set NitroOnKart = false and everything falls back to the old
	-- screen bar at NitroPosition below, untouched. Both paths share one
	-- construction and one update; the bar does not exist twice.
	NitroOnKart = true,

	-- CAMERA-RELATIVE, deliberately: StudsOffset is measured in the
	-- billboard's screen-facing frame, so the bar holds the same spot
	-- beside the kart whichever way the kart is pointing. Anchoring it
	-- to the kart's own axes instead would swing it across the screen
	-- through every drift, which is exactly when you are reading it.
	--
	-- At the 14.5-stud chase distance and a 68 vertical FOV, 2.7 studs
	-- lands the bar about 150px right of the kart on 1080p and 100px on
	-- a phone. The GAP scales with resolution while the BAR does not,
	-- which is the right way round: the offset stays proportional to the
	-- kart's own on-screen size, the bar stays legible.
	--
	-- HEIGHT IS ABOUT CONTRAST, NOT CLEARANCE. At 1.7 the bar sat level
	-- with the rear wing, and a thin translucent meter over the kart's
	-- own bodywork is unreadable whatever colour it is — the red kart in
	-- the reference swallowed it completely. Raised to sit ABOVE the
	-- silhouette, against sky or track, where the cell strokes have
	-- something to read against.
	--
	-- 4.1 puts it a little over the driver's head, roughly half a kart
	-- height above where it was. Go higher and it stops feeling attached
	-- to the kart; lower and it is back on the bodywork.
	--
	-- THIS IS THE FIRST THING TO TUNE. It is one number and it decides
	-- whether the bar reads as attached to the kart or as floating next
	-- to it.
	NitroKartOffset = Vector3.new(2.7, 4.1, 0), -- studs: right, up
	-- PIXELS. See the size note above — this is why it does not shrink.
	NitroKartSize = Vector2.new(24, 96),

	-- Fallback screen position, used only when NitroOnKart is false.
	NitroPosition = UDim2.new(0.5, 0, 1, -38),
	NitroAnchor = Vector2.new(0.5, 1),
	NitroSize = Vector2.new(196, 22),
	NitroSegments = 3, -- one cell per tank, countable at a glance
	NitroSegmentGap = 5,
	NitroCornerRadius = 6,

	NitroRimColor = Color3.fromRGB(255, 255, 255),
	NitroEmptyColor = Color3.fromRGB(120, 120, 120),
	NitroEmptyTransparency = 0.55,
	NitroCellStroke = 1.5,

	-- Gradient across each filled cell, so a full bar has some depth
	-- rather than reading as flat blocks.
	NitroFillTop = Color3.fromRGB(255, 255, 255),
	NitroFillBottom = Color3.fromRGB(170, 170, 170),

	NitroLabel = "N2O",
	NitroLabelSize = 11,
	NitroFillRate = 14,
	NitroFullPulse = 6, -- rim pulses per second once every bar is full

	-- Studs/s is a small, unexciting number. Scaling it to something
	-- that reads like km/h costs nothing and makes top speed feel like
	-- top speed. Purely cosmetic — nothing reads this back.
	SpeedScale = 2.0,
	SpeedUnit = "KM/H",

	-- Monochrome instrument. The ramp is kept as three values rather
	-- than one so a cool-to-hot rev-counter gradient is three edits away
	-- if you ever want it back.
	SpeedRampLow = Color3.fromRGB(255, 255, 255),
	SpeedRampMid = Color3.fromRGB(255, 255, 255),
	SpeedRampHigh = Color3.fromRGB(255, 255, 255),
	SpeedSegmentOff = Color3.fromRGB(95, 95, 95), -- unlit ticks
	SpeedSegmentOffTransparency = 0.55,

	SpeedTextColor = Color3.fromRGB(255, 255, 255),
	SpeedBoostColor = Color3.fromRGB(255, 255, 255), -- while boosting
	SpeedUnitColor = Color3.fromRGB(175, 175, 175),
	SpeedTextSize = 44,
	SpeedUnitSize = 13,

	SpeedSmoothing = 12, -- the readout chases actual speed, so the
	-- number doesn't strobe at 60fps
	SpeedFadeTime = 0.35,

	--== MOBILE OVERRIDES ==============================================
	-- Bottom right belongs to the DRIFT button on a phone, and the two
	-- were sitting on top of each other. So on touch the whole cluster
	-- moves to bottom CENTRE, between the thumbs, where the reference
	-- puts it too.
	--
	-- The analog dial is dropped entirely rather than shrunk. A 150px
	-- circle in the middle of a phone screen covers the road you're
	-- trying to read, and the needle is the least useful part of the
	-- readout anyway — the number tells you your speed, the dial only
	-- tells you it prettily. Everything else (ticks, numerals, needle,
	-- bezel) is hidden, not deleted, so nothing else has to know.
	-- Raised from -16 to clear the rear threat strip, which owns the
	-- bottom 32px on every layout.
	MobileSpeedPosition = UDim2.new(0.5, 0, 1, -38),
	MobileSpeedAnchor = Vector2.new(0.5, 1),
	MobileSpeedWidth = 142,
	MobileSpeedHeight = 54,

	-- Directly above the number, still centred.
	MobileNitroPosition = UDim2.new(0.5, 0, 1, -96),
	MobileNitroAnchor = Vector2.new(0.5, 1),
	-- Narrower than the desktop bar: it has to fit between two thumbs
	-- rather than hug a corner.
	MobileNitroSize = Vector2.new(132, 14),

	-- Under the compact minimap, not across the kart/road. Item use buttons
	-- already live under the right thumb; this is only a small inventory read.
	MobileItemPosition = UDim2.new(0, 14, 0, 220),
	MobileItemAnchor = Vector2.new(0, 0),
	MobileItemSlotSize = 40,
	MobileItemSlotGap = 5,

	-- Race timing is compressed into the unused upper-right safe area. The
	-- desktop values are deliberately too large for a phone's road view.
	MobileRacePosition = UDim2.new(1, -14, 0, 94),
	MobileRaceAnchor = Vector2.new(1, 0),
	MobileRaceWidth = 142,
	MobileRaceTimeSize = 24,
	MobileRaceLapSize = 27,
	MobileRaceSmallSize = 11,

	--== THE REAR THREAT STRIP =========================================
	-- Who is behind you, as a strip of segments along the very bottom
	-- edge — under the cluster, out of the road, and readable without
	-- looking away from the kart.
	--
	-- BOTTOM OF THE SCREEN IS BEHIND YOU. That is the whole reason it
	-- lives here rather than in a corner: no legend to learn, the
	-- position of the lit segment IS the bearing. Dead centre is
	-- directly behind, left of centre is over your left shoulder.
	--
	-- TWO LAYERS, DELIBERATELY DIFFERENT IN KIND, because they answer
	-- different questions and one of them is almost always true:
	--
	--   PROXIMITY  faint, wide, always on when anyone is close. "Someone
	--              is there." Never sharp enough to pull your eye.
	--   THREAT     bright, narrow, rare. Something is actually inbound.
	--              This one is allowed to interrupt.
	--
	-- Sized for a phone first. The whole strip is a few pixels tall and
	-- carries no text, so it costs nothing on a small screen — which is
	-- the constraint that ruled out a rear-view mirror or a portrait.
	RearStripWidth = 0.56, -- fraction of screen width, centred
	RearStripBottom = 6, -- px above the bottom edge
	RearSegments = 7, -- odd, so one of them IS dead centre
	RearSegmentHeight = 4,
	RearSegmentGap = 3,
	RearSegmentRadius = 2,

	-- Nobody behind this far back is worth a pixel.
	RearRange = 95, -- studs
	-- ...and inside this, the segment is at full strength.
	RearNearRange = 26,

	-- How far the glow bleeds into neighbouring segments. Without some
	-- spread the indicator ticks between cells like a stepper motor
	-- instead of sweeping, which reads as broken rather than precise.
	RearSpread = 0.22, -- in units of the strip's half-width

	RearIdleColor = Color3.fromRGB(150, 160, 180),
	RearIdleTransparency = 0.88, -- the resting strip. Nearly invisible
	-- on purpose: it is furniture until something happens.
	RearCloseColor = Color3.fromRGB(255, 205, 110),
	RearThreatColor = Color3.fromRGB(255, 120, 110), -- matches IncomingColor

	-- THE FACE, AND WHY IT IS RATIONED.
	--
	-- Knowing WHO is on your bumper changes what you do about it, but a
	-- headshot floating over the road is exactly the "giant enemy head"
	-- problem — it covers the track at the moment you most need to see
	-- it. So it appears only when they are genuinely on you, it is small,
	-- and it sits under the cluster rather than over the road.
	RearIconRange = 18, -- studs. Tight on purpose.
	-- 22 is not arbitrary: the face sits at
	-- RearStripBottom + RearSegmentHeight + 4 = 14px up, so it reaches
	-- 36px, and the cluster's baseline is 38. Two pixels of clearance.
	-- Raise this and it starts overlapping the nitro bar — move the
	-- cluster baselines (Item/Nitro/MobileSpeed) up by the same amount.
	RearIconSize = 22,
	RearIconFadeTime = 0.25,
	-- Bots have no UserId and so no headshot. They get the plain lit
	-- segment, which is the honest answer rather than a stand-in face.

	RearPulseSlow = 1.8, -- pulses/sec for the threat layer, far out
	RearPulseFast = 8.0, -- ...and about to land

	-- HOW OFTEN THE STRIP LOOKS, not how often it draws.
	--
	-- Finding the nearest kart behind means walking every tagged kart and
	-- allocating a fresh table from GetTagged. At frame rate that is real
	-- work for an answer that changes over tenths of a second — and the
	-- simulation runs on `Handling.MaxTimestep` = 1/20, so anything that
	-- drags the client under 20fps makes THE KART ITSELF move slower than
	-- real time. No HUD is worth that.
	RearScanHz = 12,
	-- What is drawn is eased toward the last reading, which is what turns
	-- a 12Hz scan back into a smooth sweep.
	RearEaseRate = 9,
}
