--[[
	Touch — the mobile control layout.

	Roblox's default touch controls are replaced entirely, not
	supplemented. The default thumbstick steers a HUMANOID; we need
	something that steers a kart, and the two want completely different
	shapes — a stick you have to hold at an angle is much worse than a
	pair of big paddles you can slam.

	AUTO THROTTLE
	-------------
	On by default, following every mobile kart racer including the one
	this layout is modelled on. A phone has no room for an accelerator
	you'd hold down for three minutes anyway, and holding it changes
	nothing — you're always accelerating. So the throttle button becomes
	a BRAKE instead, which is the input you actually make decisions with.

	LAYOUT
	------
	Thumbs live at the bottom corners and nothing important goes anywhere
	else. Steering is the left thumb's whole job; drift is the right
	thumb's. Everything else is placed so it can be reached WITHOUT
	letting go of either — an item button you have to release the wheel
	for is an item button you don't press.

	Positions are UDim2, so this scales from a phone to a tablet without
	arithmetic. Sizes are in pixels on purpose: a thumb is the same size
	on both.
--]]

return {
	-- Force the touch UI on in Studio to check the layout without a
	-- device. "auto" = show it only on a touch device with no keyboard.
	Mode = "auto", -- "auto" | "always" | "never"


	-- How fast the steer value ramps to full when a paddle is held.
	-- Instant would be correct for a keyboard, but a thumb lands on a
	-- paddle over a few frames anyway and ramping stops the very first
	-- frame of a tap counting as full lock.
	-- SteerRamp, matching the asymmetry in Handling.

	--== LOOK ==========================================================
	-- Colours are deliberately flat and low-contrast: these sit on top of
	-- the track for the whole race, and a bright HUD competes with the
	-- thing you're trying to look at.
	Fill = Color3.fromRGB(120, 150, 200),
	FillTransparency = 0.55,
	FillPressed = Color3.fromRGB(190, 220, 255),
	FillPressedTransparency = 0.25,

	Accent = Color3.fromRGB(255, 170, 60), -- drift, the one warm button
	AccentTransparency = 0.28,

	Stroke = Color3.fromRGB(255, 255, 255),
	StrokeThickness = 2,
	StrokeTransparency = 0.55,

	LabelColor = Color3.fromRGB(255, 255, 255),
	LabelSize = 15,
	FadeTime = 0.25, -- fade in/out as you get in and out of a kart

	--== BUTTONS =======================================================
	-- Each entry: Action is what it does, everything else is where it is.
	-- Hold = true means press-and-hold (steer, drift); false is a tap.
	--
	-- To move a button, edit its Position. To add one, add a row here and
	-- a case in TouchHud's ACTIONS table — nothing else.
	Buttons = {
		{
			-- The big one, under the right thumb where it rests.
			Action = "Drift",
			Label = "DRIFT",
			Hold = true,
			Accent = true,
			Size = Vector2.new(150, 150),
			Position = UDim2.new(1, -22, 1, -22),
			Anchor = Vector2.new(1, 1),
			Round = 75, -- half the size = a circle
		},
		{
			Action = "Nitro",
			Label = "N2O",
			Size = Vector2.new(96, 96),
			Position = UDim2.new(1, -184, 1, -30),
			Anchor = Vector2.new(1, 1),
			Round = 48,
		},
		{
			Action = "Item",
			Label = "▲",
			Size = Vector2.new(96, 96),
			Position = UDim2.new(1, -40, 1, -186),
			Anchor = Vector2.new(1, 1),
			Round = 48,
		},
		{
			-- Directly under the forward one, so the pair reads as one
			-- control with two directions rather than two buttons.
			Action = "ItemBack",
			Label = "▼",
			Size = Vector2.new(96, 78),
			Position = UDim2.new(1, -40, 1, -288),
			Anchor = Vector2.new(1, 1),
			Round = 39,
		},
		{
			-- Small and out of the way: useful, but not something you need
			-- mid-corner.
			Action = "LookBack",
			Label = "◎",
			Hold = true,
			Size = Vector2.new(72, 72),
			Position = UDim2.new(1, -160, 1, -196),
			Anchor = Vector2.new(1, 1),
			Round = 36,
		},
	},
}
