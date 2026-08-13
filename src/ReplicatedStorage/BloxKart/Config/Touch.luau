--[[
	Touch — the mobile control layout.

	Roblox's default touch controls are replaced entirely, not
	supplemented. The default thumbstick steers a HUMANOID; the race uses two
	dedicated left/right steering buttons instead. They never drift,
	accelerate, brake, or use an item — those actions have their own controls.

	GAS + BRAKE
	-----------
	Mobile gets explicit pedals. This gives the driver meaningful lift-off,
	coasting, braking, and reverse control instead of silently accelerating
	all race.

	LAYOUT
	------
	Thumbs live at the bottom corners and nothing important goes anywhere
	else. The left thumb has left/right steering buttons; gas and brake are
	the right thumb's first job. The three race actions form one compact row
	above the pedals, rather than covering the whole road with controls.

	Positions are UDim2, so this scales from a phone to a tablet without
	arithmetic. Sizes are in pixels on purpose: a thumb is the same size
	on both.
--]]

return {
	-- Force the touch UI on in Studio to check the layout without a
	-- device. "auto" = show it only on a touch device with no keyboard.
	Mode = "auto", -- "auto" | "always" | "never"
	-- Studio's device emulator can still expose a keyboard to the client. Keep
	-- the custom controls visible there for layout testing; this has no effect
	-- in a published experience.
	StudioPreview = true,


	-- Steering buttons ease in instead of instantly applying full lock, so a
	-- short touch still lets a player feather a corner rather than snapping.
	SteerRamp = 11,
	SteerRelease = 15,
	GasThrottle = 1,
	BrakeThrottle = -1,

	--== THROTTLE: PEDALS OR LEVER =====================================
	-- "pedals" is the original pair of GAS / BRAKE buttons.
	-- "lever" replaces both with one vertical throttle the thumb slides:
	-- forward for gas, centre for neutral, back for brake and reverse.
	--
	-- The lever's advantage is not that it looks nicer. It is that a
	-- thumb can PARK it — set a cruising throttle and let go — which
	-- frees the right thumb for items and drift without lifting off the
	-- power. Two pedals can never do that; they are held or they are not.
	Throttle = "lever", -- "pedals" | "lever"

	Lever = {
		-- Track geometry. Tall and narrow, in the right thumb's arc.
		-- SHORTER THAN THE FIRST CUT (240). Three detents need the thumb
		-- to REACH three zones, not to travel a long way, and 240 took a
		-- quarter of a phone screen to say one of three things.
		Size = Vector2.new(94, 210),
		Position = UDim2.new(1, -22, 1, -20),
		Anchor = Vector2.new(1, 1),
		Round = 30,

		-- The knob the thumb drags. Round and a good deal wider than a
		-- fingertip is precise, because it is a target, not a readout.
		KnobSize = Vector2.new(86, 74),
		KnobRound = 24,

		--=============================================================
		--  IT STAYS WHERE YOU PUT IT.
		--
		--  A lever that springs back to centre on release is a pedal
		--  with extra steps — you must keep a thumb on it to go
		--  anywhere, which is the exact limitation this replaces.
		--
		--  Parking it is the point: set a throttle, take the thumb away,
		--  steer and use items with both hands still free.
		--
		--  It is reset to centre whenever the pad deactivates, so a
		--  respawn or a race end can never hand the player a kart that
		--  is already accelerating.
		--
		--  Set > 0 for a rate that springs it back to neutral, if that
		--  turns out to be preferred.
		--=============================================================
		ReturnRate = 0,

		--=============================================================
		--  THREE POSITIONS, NOT A SLIDE: GAS / NEUTRAL / REVERSE.
		--
		--  A continuous lever sounds better than it plays. Simulation
		--  reads throttle as a GATE — any amount asks for full speed
		--  (see the note in BotService) — so honouring fractional
		--  positions meant a whole second input threaded through the
		--  simulation purely to serve one control, and the reward was
		--  a thumb having to hold a precise angle on glass while also
		--  steering.
		--
		--  Detents give the one thing that actually matters here: you
		--  can find full gas, or neutral, or reverse WITHOUT LOOKING,
		--  by slamming the thumb to a third of the track. There is no
		--  partial state to hold, and no way to leave it at 40% by
		--  accident.
		--
		--  How far from centre before the lever commits to an end.
		--  A third of the travel each way — thirds are the natural
		--  reading of a three-position switch and there is no dead
		--  band to explain.
		--=============================================================
		DetentAt = 0.33,

		-- How fast the knob CHASES the thumb. Not instant: a smoothed
		-- knob hides the jitter of a thumb resting on glass, and the
		-- same smoothing is what keeps a dragged lever from stuttering
		-- the throttle.
		FollowRate = 26,

		--== LOOK ==================================================
		TrackFill = Color3.fromRGB(18, 26, 42),
		TrackTransparency = 0.25,
		-- The gas half and the brake half are tinted so the neutral
		-- point is findable at a glance rather than by feel alone.
		GasTint = Color3.fromRGB(43, 139, 94),
		BrakeTint = Color3.fromRGB(94, 48, 54),
		HalfTransparency = 0.55,
		KnobFill = Color3.fromRGB(214, 224, 240),
		KnobPressed = Color3.fromRGB(255, 255, 255),
		KnobTransparency = 0.06,
		-- The neutral line across the middle of the track.
		NotchColor = Color3.fromRGB(255, 255, 255),
		NotchTransparency = 0.45,
		NotchThickness = 2,
		LabelSize = 13,
	},

	--== LOOK ==========================================================
	-- Colours are deliberately flat and low-contrast: these sit on top of
	-- the track for the whole race, and a bright HUD competes with the
	-- thing you're trying to look at.
	Fill = Color3.fromRGB(24, 34, 54),
	FillTransparency = 0.2,
	FillPressed = Color3.fromRGB(190, 220, 255),
	FillPressedTransparency = 0.08,
	SteerFill = Color3.fromRGB(205, 215, 232),

	Accent = Color3.fromRGB(255, 157, 55), -- drift, the one warm button
	AccentTransparency = 0.12,

	Stroke = Color3.fromRGB(255, 255, 255),
	StrokeThickness = 2,
	StrokeTransparency = 0.3,

	LabelColor = Color3.fromRGB(255, 255, 255),
	LabelSize = 15,
	FadeTime = 0.25, -- fade in/out as you get in and out of a kart

	--== BUTTONS =======================================================
	-- Each entry: Action is what it does, everything else is where it is.
	-- Hold = true means press-and-hold (pedals, drift); false is a tap.
	--
	-- To move a button, edit its Position. To add one, add a row here and
	-- a case in TouchHud's ACTIONS table — nothing else.
	Buttons = {
		{
			-- Fully custom steering: these replace the stock mobile thumbstick
			-- while seated. They stay inside the left thumb zone and never write
			-- throttle or any racing action.
			Action = "SteerLeft",
			Label = "◀",
			Hold = true,
			Steer = true,
			Size = Vector2.new(76, 76),
			Position = UDim2.new(0, 24, 1, -22),
			Anchor = Vector2.new(0, 1),
			Round = 22,
			Color = Color3.fromRGB(210, 220, 238),
			PressedColor = Color3.fromRGB(255, 255, 255),
			Transparency = 0.14,
		},
		{
			Action = "SteerRight",
			Label = "▶",
			Hold = true,
			Steer = true,
			Size = Vector2.new(76, 76),
			Position = UDim2.new(0, 110, 1, -22),
			Anchor = Vector2.new(0, 1),
			Round = 22,
			Color = Color3.fromRGB(210, 220, 238),
			PressedColor = Color3.fromRGB(255, 255, 255),
			Transparency = 0.14,
		},
		{
			-- The two primary pedals sit under the right thumb. Explicit throttle
			-- is essential for ramps, corner entry and fair manual control.
			Action = "Gas",
			Label = "GAS",
			Hold = true,
			Primary = true,
			Size = Vector2.new(116, 104),
			Position = UDim2.new(1, -20, 1, -20),
			Anchor = Vector2.new(1, 1),
			Round = 22,
			Color = Color3.fromRGB(43, 139, 94),
			PressedColor = Color3.fromRGB(84, 224, 145),
		},
		{
			-- Brake/reverse deliberately mirrors the gas pedal; it wins if both
			-- are held so an accidental overlap never adds acceleration.
			Action = "Brake",
			Label = "BRAKE",
			Hold = true,
			Primary = true,
			Size = Vector2.new(92, 104),
			Position = UDim2.new(1, -142, 1, -20),
			Anchor = Vector2.new(1, 1),
			Round = 18,
			Color = Color3.fromRGB(94, 48, 54),
			PressedColor = Color3.fromRGB(190, 78, 72),
		},
		{
			-- Three compact race actions, one row above the pedals. They leave the
			-- lower half of the screen to driving rather than becoming a second HUD.
			Action = "Drift",
			Label = "DRIFT",
			Hold = true,
			Size = Vector2.new(66, 50),
			-- LEFT OF THE LEVER, not on top of it. The lever occupies the
			-- right 22..116 and stands 210 tall, straight through where
			-- this row used to sit — with the pedals gone there was
			-- nothing left holding this column out of its way.
			Position = UDim2.new(1, -128, 1, -132),
			Anchor = Vector2.new(1, 1),
			Round = 18,
			Accent = true,
		},
		{
			Action = "Nitro",
			Label = "N2O",
			Size = Vector2.new(58, 50),
			Position = UDim2.new(1, -202, 1, -132),
			Anchor = Vector2.new(1, 1),
			Round = 18,
			Color = Color3.fromRGB(44, 104, 176),
			PressedColor = Color3.fromRGB(92, 171, 255),
		},
		{
			-- One forward-use button. Rear throw and look-back stay on keyboard /
			-- controller instead of turning the mobile cluster into seven buttons.
			Action = "Item",
			Label = "USE",
			Size = Vector2.new(66, 50),
			Position = UDim2.new(1, -268, 1, -132),
			Anchor = Vector2.new(1, 1),
			Round = 18,
			Color = Color3.fromRGB(174, 48, 52),
			PressedColor = Color3.fromRGB(255, 94, 82),
			Transparency = 0.1,
		},
	},
}
