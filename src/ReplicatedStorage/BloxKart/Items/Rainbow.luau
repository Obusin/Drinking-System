--[[ Rainbow — guided recovery rail. Gameplay is owned by RainbowService. ]]
return {
	Id = "Rainbow",
	Name = "RAINBOW",
	Tint = Color3.fromRGB(255, 120, 220),
	Icon = "",
	Scope = "self",
	Weight = 8,
	DurationMin = 3.5,
	DurationPreferredMax = 4.75,
	DurationHardMax = 6.0,
	LiftHeight = 5,
	LiftTime = 0.55,
	LaunchOvershoot = 3,
	SpeedMultiplier = 1.15,
	DriveSpeed = 190,
	BoostRefresh = 0.14,
	RampApproach = 34,
	RampSpeed = 118,
	WarningTime = 0.8,
	-- Temporary route-follower soak test. Keep this explicit so normal
	-- gameplay values remain beside it and can be restored in one edit.
	StressTest = false,
	StressDuration = 35,
	StressSpeed = 200,
	LandingSearchAheadNodes = 12,
	LandingBlendTime = 0.45,
	HitProtection = true,
	Use = function(ctx)
		-- The slot is consumed only by the server-confirmation callback.
		-- A rejected request must leave the item in hand instead of looking
		-- like a power-up that did nothing.
		return ctx.requestRainbow()
	end,
}
