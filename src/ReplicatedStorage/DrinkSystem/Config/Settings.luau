local Settings = {
	MaxIngredientsPerMix      = 4,
	MaxGlasses                = 5,
	GlassToolNames            = { "Glass", "Highball", "Lowball", "Martini" },
	WaterSoberAmount          = -35,  -- drunkness change when drinking Water directly
	ShakerToolName            = "Shaker",
	MaxInteractDistance       = 12,
	ActionCooldown            = 0.12,
	DrinkConsumeCooldown      = 0.35,
	GuidanceUpdateInterval    = 0.25,
	MaxDrinkTime              = 60,
	DefaultDrinkSips          = 3,
	PlaceKey                  = "Q",
	BartenderGamepassId       = 0,
	RequireGamepassForGlass   = false,
	RequireGamepassForMixing  = false,
	EnableGuidance            = true,
	EnableHoverInteractionController   = true,
	EnableDrinkVisualController        = true,
	EnableShakerController             = true,

	-- ── Drunkness ─────────────────────────────────────────────────────
	DrunknessMax = 100,

	-- Passive recovery: 1.5x slower than before (was 1.1) — 100→0 in ~2.3 min naturally.
	DrunknessRecoveryPerSecond = 0.73,

	-- Visual effects reach full intensity at 70 drunkness (not 100),
	-- so effects feel strong and noticeable well before you're fully maxed.
	DrunknessVisualMax            = 70,
	DrunknessVisualRisePerSecond  = 4,   -- slow build after each sip (was 12 — read as a lurch)
	DrunknessVisualFallPerSecond  = 1.5,
	DrunkEffectIntensity          = 1.6,   -- master multiplier for wobble/blur/DOF

	-- Stage thresholds (fraction of DrunknessMax):
	--   Buzzed  = 20  (1st light drink)
	--   Drunk   = 45  (~1.5 medium drinks)
	--   Wasted  = 72  (~2 medium or 1 strong drink)
	--   Collapse= 92  (~3 medium or 1.5 strong drinks)
	DrunkStageThresholds = {
		Buzzed = 0.20,
		Drunk  = 0.45,
		Wasted = 0.72,
	},
	DrunkCollapseThreshold    = 0.92,
	DrunkCollapseDuration     = 30,   -- stay collapsed 30s — they can still shuffle around ragdolled
	DrunkCollapseCooldown     = 90,   -- can only collapse once per 90s
	DrunkCollapseRecoveryRatio= 0.50, -- wake up at 50% drunkness (wasted but not collapsed)

	-- Movement penalties scale with stage
	DrunkMovementMaxAlpha = 1,
	DrunkWalkSpeedMultipliers = {
		Sober     = 1,
		Buzzed    = 0.92,
		Drunk     = 0.75,
		Wasted    = 0.50,
		Collapsed = 0,
	},
	DrunkJumpPowerMultipliers = {
		Sober     = 1,
		Buzzed    = 0.92,
		Drunk     = 0.72,
		Wasted    = 0.42,
		Collapsed = 0,
	},

	-- Stumbles: start at Wasted (72%), ramp up as drunkness climbs.
	-- Chance min/max are per-second probabilities rolled each Heartbeat.
	DrunkStumbleThreshold          = 0.72,
	DrunkStumbleChancePerSecondMin  = 0.12,
	DrunkStumbleChancePerSecondMax  = 0.45,
	DrunkStumbleDuration            = 3.5,
	DrunkStumbleCooldown            = 4,

	-- Camera + movement drift
	DrunkControlSkewMaxDegrees = 30,
	DrunkSidewaysSwayMax       = 0.72,

	DrunkHiccupSoundId  = 9114396275,
	-- World sounds (played server-side on the character so nearby players hear them)
	PourSoundId         = 96961332439928,
	PourSoundVolume     = 0.4,
	DrinkSoundId        = 82098479361178,
	DrinkSoundVolume    = 0.55,
	SolaireSoundId      = 140335089989960,  -- plays when sipping Solaire's Spit
	SolaireSoundVolume  = 0.45,             -- low but audible
	EnableDrunkDebug    = false,
	DrunkDebugInterval  = 0.5,

	Animations = {
		Pour = 138176167772150,
	},
}

return Settings
