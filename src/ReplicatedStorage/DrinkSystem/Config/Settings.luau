local Settings = {
	MaxIngredientsPerMix      = 6,  -- custom drinks go up to 6 (house recipes stay 1-4)
	MaxGlasses                = 5,
	GlassToolNames            = { "Glass", "Highball", "Lowball", "Martini" },
	WaterSoberAmount          = -35,  -- drunkness change when drinking Water directly
	ShakerToolName            = "Shaker",
	MaxInteractDistance       = 12,
	ActionCooldown            = 0.12,
	DrinkConsumeCooldown      = 0.35,
	GuidanceUpdateInterval    = 0.25,
	MaxDrinkTime              = 60,
	-- Mix speed scoring (timer starts at FIRST pour): ≤Fast = full time points,
	-- ≤Ok = partial, slower = minimal. Also drives the live mix timer bar.
	MixTimeFastSeconds        = 5,
	MixTimeOkSeconds          = 10,
	DefaultDrinkSips          = 3,
	PlaceKey                  = "Q",
	BartenderGamepassId       = 0,
	RequireGamepassForGlass   = false,
	RequireGamepassForMixing  = false,
	EnableGuidance            = true,
	EnableHoverInteractionController   = true,
	EnableRecipeMenu                   = true,   -- in-game recipe book (B key / side button)
	EnableDrinkVisualController        = true,
	EnableShakerController             = true,

	-- ── Drunkness ─────────────────────────────────────────────────────
	DrunknessMax = 100,

	-- Passive recovery: 1.5x slower than before (was 1.1) — 100→0 in ~2.3 min naturally.
	DrunknessRecoveryPerSecond = 0.73,
	-- Drunkness holds steady this long after the last drink before decaying —
	-- keeps the buzz while actively drinking.
	SoberGraceSeconds          = 25,
	-- Bubbles above drunk players' heads (server-side — visible to everyone)
	DrunkBubblesEnabled        = true,
	DrunkBubblesTexture        = 249902641,

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
	PourSoundVolume     = 0.25,
	DrinkSoundId        = 82098479361178,
	DrinkSoundVolume    = 0.55,
	SolaireSoundId      = 140335089989960,  -- plays when sipping Solaire's Spit
	SolaireSoundVolume  = 0.45,             -- low but audible
	ShakerSoundId       = 82990263580916,   -- loops while the shake animation plays
	ShakerSoundVolume   = 0.5,
	TrashSoundId        = 103865555979173,  -- glass thrown into a DS_Trash can
	TrashSoundVolume    = 0.5,

	-- Custom drink maker (paid "your drink on the menu")
	-- Duration tiers: hours → Dev Product ID. Create one product per tier on
	-- Creator Hub (price them ascending) and fill the IDs in here.
	CustomDrinkProducts = {
		[4]  = 0,
		[8]  = 0,
		[12] = 0,
		[24] = 0,
	},
	CustomDrinkFreeTesting = true,  -- TRUE = anyone can create free (testing). TURN OFF FOR LAUNCH.

	-- Ice Cube secret (Water + Ice garnish → shake, then freeze + trap in a
	-- sliding ice cube). Fires the moment the garnish is added, not on sip.
	IceCubeShakeDuration = 1.8,
	IceCubeDuration = 20,
	EnableIceCubeTestButton = true,  -- on-screen button to trigger it instantly for QA. TURN OFF FOR LAUNCH.

	-- Bee Swarm secret (visual-only effect, not yet wired to a recipe)
	BeeSwarmDuration      = 7,       -- matches the sound clip length
	BeeSwarmSoundId       = 127842099060677,
	BeeSwarmSoundVolume   = 0.5,
	BeeSwarmAnimationId   = 77426382296799, -- "shooing the bees away"
	EnableBeeSwarmTestButton = true, -- on-screen button to trigger it instantly for QA. TURN OFF FOR LAUNCH.

	-- On-screen buttons to fire ANY drink callback by name for QA, no
	-- brewing required. TURN OFF FOR LAUNCH.
	EnableSecretEffectTestButtons = true,

	-- Live outfit refresh (apply whatever avatar is currently saved on the
	-- account, without a full respawn — see AvatarRefreshService)
	EnableOutfitRefresh   = true,
	OutfitRefreshSoundId  = 112485797063762,
	OutfitRefreshVolume   = 0.5,
	OutfitRefreshCooldown = 5, -- seconds — ApplyDescription is a real API call, don't let it be spammed

	-- Chicken Dinner secret (Soda Water + Vermix + Caffemo)
	ChickenDinnerSoundId     = 131137853843046,
	ChickenDinnerSoundVolume = 0.5,

	-- Owner's Delight secret (Caffemo x4) — inverted controls
	OwnersDelightDuration = 12,

	-- Hotdog Bread Drink secret (Bukonelle x2 + Soda Water) — smoke from head
	HotdogSmokeDuration = 10,

	-- Birthday Party secret (Soda Water + Sugar) — low gravity + bouncy jumps
	BirthdayPartyDuration               = 12,
	BirthdayPartyGravityCounterFraction = 0.6,  -- 0 = normal gravity, 1 = weightless
	BirthdayPartyJumpPower              = 90,

	-- Relapse Drink secret (Fonador x4) — movement stays free the whole time.
	-- Standing still for RelapseIdleThreshold seconds re-triggers the
	-- stumble animation (+ a small drunkness bump) as long as they stay
	-- idle, at most once every RelapseMinInterval seconds, for the whole
	-- RelapseEffectDuration window — then it just stops.
	RelapseAnimationId    = 93645548410631,
	RelapseEffectDuration = 25,
	RelapseIdleThreshold  = 3,
	RelapseMinInterval    = 4,
	RelapseDrunknessBump  = 6,

	-- Olkab's Hair secret (Absmith x4) — strips Hair accessories for a while,
	-- restores exactly what was removed (same Handle/weld state)
	OlkabsHairDuration      = 20,
	OlkabsHairYoinkDelay    = 1.5, -- lets the sip animation finish before the yoink
	OlkabsHairYoinkSoundId  = 90539754123219,
	OlkabsHairYoinkVolume   = 0.6,

	-- Outcome jingles (local, play with the grade toast)
	OutcomeHighSoundId  = 113307491257691,  -- Perfect / Good
	OutcomeLowSoundId   = 4342630136,       -- Weak / Experimental / Ruined
	OutcomeSoundVolume  = 0.5,
	EnableDrunkDebug    = false,
	DrunkDebugInterval  = 0.5,

	Animations = {
		Pour = 138176167772150,
	},
}

return Settings
