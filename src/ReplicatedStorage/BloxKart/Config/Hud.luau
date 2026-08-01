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
	IncomingText = "◤  INCOMING",
	IncomingColor = Color3.fromRGB(255, 120, 110),
	-- Seconds out at which the warning appears. Long enough to use a
	-- shield, short enough that it is not on screen for half the lap.
	IncomingLead = 3.0,
	-- MINIMUM TIME ON SCREEN once it appears. A missile fired from close
	-- behind is only a threat for a fraction of a second, and a warning
	-- that comes and goes inside a few frames is one nobody ever sees —
	-- which is indistinguishable from a warning that never fired.
	IncomingHold = 0.7,

	--== WHAT HIT YOU =================================================
	-- Some items have no projectile and no travel time. Lightning
	-- reaches everyone ahead the instant it is used, so there is nothing
	-- to see coming and nothing a warning could have told you — you are
	-- simply spinning, which reads as "a missile I did not see".
	--
	-- A warning is impossible; an EXPLANATION is not. The hit feed
	-- already names it, but the feed is small text at the top of the
	-- screen and the one moment nobody reads it is while their kart is
	-- spinning.
	HitByText = "HIT BY %s",
	HitByColor = Color3.fromRGB(255, 150, 110),
	HitByHold = 1.4,

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
	ControlsToggleKey = Enum.KeyCode.H,

	--== ITEM SLOTS ====================================================
	-- Right-hand edge with everything else. Cramming the readouts into
	-- one corner leaves the whole left and centre of the screen for the
	-- track, which is what you're actually looking at.
	ItemPosition = UDim2.new(1, -22, 0, 168), -- under the TIME / LAP block
	ItemAnchor = Vector2.new(1, 0),
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
	NitroPosition = UDim2.new(1, -20, 1, -186),
	NitroAnchor = Vector2.new(1, 1),
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
	MobileSpeedPosition = UDim2.new(0.5, 0, 1, -16),
	MobileSpeedAnchor = Vector2.new(0.5, 1),
	MobileSpeedWidth = 210,
	MobileSpeedHeight = 66,

	-- Directly above the number, still centred.
	MobileNitroPosition = UDim2.new(0.5, 0, 1, -86),
	MobileNitroAnchor = Vector2.new(0.5, 1),
	-- Narrower than the desktop bar: it has to fit between two thumbs
	-- rather than hug a corner.
	MobileNitroSize = Vector2.new(168, 18),
}
