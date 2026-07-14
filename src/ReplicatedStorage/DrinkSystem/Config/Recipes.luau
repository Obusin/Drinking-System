-- StrongnessOverride = total drunkness added by one full drink (3 sips by default).
-- Target feel:
--   Light   (18-22) — ~4 drinks to wasted, casual crowd pleaser
--   Medium  (32-48) — ~2-3 drinks to wasted, the bread-and-butter orders
--   Strong  (62-75) — 1-2 drinks to wasted, shaker required = higher skill
--   Nuclear (85-95) — 1 drink takes you from 0 to nearly collapsed
--   Sober   (-35)   — Water cancels one medium drink worth of drunkness

local Recipes = {
	-- ── LIGHT ─────────────────────────────────────────────────────────
	["Minty Fresh"] = {
		DisplayName    = "Minty Fresh",
		Ingredients    = { "Mintverde", "Soda Water", "Simple Syrup" },
		OutputColor    = Color3.fromRGB(120, 220, 160),
		RequireShaker  = false,
		StrongnessOverride = 18,
		Steps = {
			{ Ingredient = "Mintverde" },
			{ Ingredient = "Soda Water" },
			{ Ingredient = "Simple Syrup" },
		},
		Presentation = { Garnishes = { "Lime" } },
	},
	["Cocoa Rush"] = {
		DisplayName    = "Cocoa Rush",
		Ingredients    = { "Cochoco", "Creamora", "Sugar" },
		OutputColor    = Color3.fromRGB(90, 55, 30),
		RequireShaker  = false,
		StrongnessOverride = 18,
		Steps = {
			{ Ingredient = "Cochoco" },
			{ Ingredient = "Creamora" },
			{ Ingredient = "Sugar" },
		},
		Presentation = { Garnishes = { "Cherry" } },
	},
	["Heatstroke"] = {
		DisplayName    = "Heatstroke",
		Ingredients    = { "Bilijin", "Tropica", "Sugar" },
		OutputColor    = Color3.fromRGB(255, 146, 76),
		RequireShaker  = false,
		StrongnessOverride = 22,
		Steps = {
			{ Ingredient = "Bilijin" },
			{ Ingredient = "Tropica" },
			{ Ingredient = "Sugar" },
		},
		Presentation = { Garnishes = { "Orange" } },
	},
	["Bukonelle Breeze"] = {
		DisplayName    = "Bukonelle Breeze",
		Ingredients    = { "Bukonelle", "Coolnag", "Soda Water" },
		OutputColor    = Color3.fromRGB(100, 180, 255),
		RequireShaker  = false,
		StrongnessOverride = 22,
		Steps = {
			{ Ingredient = "Bukonelle" },
			{ Ingredient = "Coolnag" },
			{ Ingredient = "Soda Water" },
		},
		Presentation = { Garnishes = { "Lime" } },
	},

	["Tropic Thunder"] = {
		DisplayName    = "Tropic Thunder",
		Ingredients    = { "Tropica", "Coolnag", "Sugar" },
		OutputColor    = Color3.fromRGB(255, 190, 70),
		RequireShaker  = false,
		StrongnessOverride = 20,
		Steps = {
			{ Ingredient = "Tropica" },
			{ Ingredient = "Coolnag" },
			{ Ingredient = "Sugar" },
		},
		Presentation = { Garnishes = { "Orange" } },
	},
	["Almendra Dream"] = {
		DisplayName    = "Almendra Dream",
		Ingredients    = { "Almendra", "Creamora", "Simple Syrup" },
		OutputColor    = Color3.fromRGB(235, 215, 180),
		RequireShaker  = false,
		StrongnessOverride = 24,
		Steps = {
			{ Ingredient = "Almendra" },
			{ Ingredient = "Creamora" },
			{ Ingredient = "Simple Syrup" },
		},
		Presentation = { Garnishes = { "Cherry" } },
	},

	["Cool Mint"] = {
		DisplayName    = "Cool Mint",
		Ingredients    = { "Mintverde", "Coolnag", "Simple Syrup" },
		OutputColor    = Color3.fromRGB(150, 230, 200),
		RequireShaker  = false,
		StrongnessOverride = 18,
		Steps = {
			{ Ingredient = "Mintverde" },
			{ Ingredient = "Coolnag" },
			{ Ingredient = "Simple Syrup" },
		},
		Presentation = { Garnishes = { "Lime" } },
	},
	["Choco Float"] = {
		DisplayName    = "Choco Float",
		Ingredients    = { "Cochoco", "Soda Water", "Simple Syrup" },
		OutputColor    = Color3.fromRGB(130, 90, 60),
		RequireShaker  = false,
		StrongnessOverride = 21,
		Steps = {
			{ Ingredient = "Cochoco" },
			{ Ingredient = "Soda Water" },
			{ Ingredient = "Simple Syrup" },
		},
		Presentation = { Garnishes = { "Cherry" } },
	},
	["Fonador Soda"] = {
		DisplayName    = "Fonador Soda",
		Ingredients    = { "Fonador", "Soda Water", "Sugar" },
		OutputColor    = Color3.fromRGB(230, 120, 110),
		RequireShaker  = false,
		StrongnessOverride = 22,
		Steps = {
			{ Ingredient = "Fonador" },
			{ Ingredient = "Soda Water" },
			{ Ingredient = "Sugar" },
		},
		Presentation = { Garnishes = { "Lemon" } },
	},

	-- ── MEDIUM ────────────────────────────────────────────────────────
	["Fonador Sling"] = {
		DisplayName    = "Fonador Sling",
		Ingredients    = { "Fonador", "Tropica", "Soda Water" },
		OutputColor    = Color3.fromRGB(210, 80, 80),
		RequireShaker  = false,
		StrongnessOverride = 32,
		Steps = {
			{ Ingredient = "Fonador" },
			{ Ingredient = "Tropica" },
			{ Ingredient = "Soda Water" },
		},
		Presentation = { Garnishes = { "Orange" } },
	},
	["Vermix Mule"] = {
		DisplayName    = "Vermix Mule",
		Ingredients    = { "Vermix", "Soda Water", "Mintverde" },
		OutputColor    = Color3.fromRGB(190, 230, 190),
		RequireShaker  = false,
		StrongnessOverride = 35,
		Steps = {
			{ Ingredient = "Vermix" },
			{ Ingredient = "Soda Water" },
			{ Ingredient = "Mintverde" },
		},
		Presentation = { Garnishes = { "Lime" } },
	},
	["Double Down"] = {
		DisplayName    = "Double Down",
		Ingredients    = { "Double Time", "Absmith", "Sugar" },
		OutputColor    = Color3.fromRGB(200, 170, 80),
		RequireShaker  = false,
		StrongnessOverride = 38,
		Steps = {
			{ Ingredient = "Double Time" },
			{ Ingredient = "Absmith" },
			{ Ingredient = "Sugar" },
		},
		Presentation = { Garnishes = { "Orange" } },
	},
	["Night Shift"] = {
		DisplayName    = "Night Shift",
		Ingredients    = { "Caffemo", "Absmith", "Simple Syrup" },
		OutputColor    = Color3.fromRGB(40, 30, 20),
		RequireShaker  = false,
		StrongnessOverride = 42,
		Steps = {
			{ Ingredient = "Caffemo" },
			{ Ingredient = "Absmith" },
			{ Ingredient = "Simple Syrup" },
		},
		Presentation = { Garnishes = { "Cherry" } },
	},

	["Jaxline Fizz"] = {
		DisplayName    = "Jaxline Fizz",
		Ingredients    = { "Jaxline", "Soda Water", "Sugar" },
		OutputColor    = Color3.fromRGB(215, 170, 105),
		RequireShaker  = false,
		StrongnessOverride = 35,
		Steps = {
			{ Ingredient = "Jaxline" },
			{ Ingredient = "Soda Water" },
			{ Ingredient = "Sugar" },
		},
		Presentation = { Garnishes = { "Lemon" } },
	},
	["Midnight Cocoa"] = {
		DisplayName    = "Midnight Cocoa",
		Ingredients    = { "Cochoco", "Caffemo", "Maple Syrup" },
		OutputColor    = Color3.fromRGB(60, 40, 28),
		RequireShaker  = false,
		StrongnessOverride = 38,
		Steps = {
			{ Ingredient = "Cochoco" },
			{ Ingredient = "Caffemo" },
			{ Ingredient = "Maple Syrup" },
		},
		Presentation = { Garnishes = { "Cherry" } },
	},
	["Calliamo Sunset"] = {
		DisplayName    = "Calliamo Sunset",
		Ingredients    = { "Calliamo", "Tropica", "Simple Syrup" },
		OutputColor    = Color3.fromRGB(250, 130, 120),
		RequireShaker  = false,
		StrongnessOverride = 42,
		Steps = {
			{ Ingredient = "Calliamo" },
			{ Ingredient = "Tropica" },
			{ Ingredient = "Simple Syrup" },
		},
		Presentation = { Garnishes = { "Orange" } },
	},

	["Candy Beach"] = {
		DisplayName    = "Candy Beach",
		Ingredients    = { "Barcandy", "Tropica", "Simple Syrup" },
		OutputColor    = Color3.fromRGB(255, 150, 130),
		RequireShaker  = false,
		StrongnessOverride = 34,
		Steps = {
			{ Ingredient = "Barcandy" },
			{ Ingredient = "Tropica" },
			{ Ingredient = "Simple Syrup" },
		},
		Presentation = { Garnishes = { "Orange" } },
	},
	["Frost Mule"] = {
		DisplayName    = "Frost Mule",
		Ingredients    = { "Vermix", "Coolnag", "Sugar" },
		OutputColor    = Color3.fromRGB(200, 240, 245),
		RequireShaker  = false,
		StrongnessOverride = 36,
		Steps = {
			{ Ingredient = "Vermix" },
			{ Ingredient = "Coolnag" },
			{ Ingredient = "Sugar" },
		},
		Presentation = { Garnishes = { "Lime" } },
	},
	["Bilijin Breeze"] = {
		DisplayName    = "Bilijin Breeze",
		Ingredients    = { "Bilijin", "Mintverde", "Soda Water" },
		OutputColor    = Color3.fromRGB(170, 235, 190),
		RequireShaker  = false,
		StrongnessOverride = 40,
		Steps = {
			{ Ingredient = "Bilijin" },
			{ Ingredient = "Mintverde" },
			{ Ingredient = "Soda Water" },
		},
		Presentation = { Garnishes = { "Lime" } },
	},
	["Overtime"] = {
		DisplayName    = "Overtime",
		Ingredients    = { "Double Time", "Caffemo", "Sugar" },
		OutputColor    = Color3.fromRGB(90, 60, 40),
		RequireShaker  = false,
		StrongnessOverride = 44,
		Steps = {
			{ Ingredient = "Double Time" },
			{ Ingredient = "Caffemo" },
			{ Ingredient = "Sugar" },
		},
		Presentation = { Garnishes = { "Cherry" } },
	},
	["Velvet Luxe"] = {
		DisplayName    = "Velvet Luxe",
		Ingredients    = { "Chocoluxe", "Creamora", "Simple Syrup" },
		OutputColor    = Color3.fromRGB(185, 140, 110),
		RequireShaker  = false,
		StrongnessOverride = 45,
		Steps = {
			{ Ingredient = "Chocoluxe" },
			{ Ingredient = "Creamora" },
			{ Ingredient = "Simple Syrup" },
		},
		Presentation = { Garnishes = { "Cherry" } },
	},

	-- ── STRONG (shaker required) ───────────────────────────────────────
	["Nguermo Noir"] = {
		DisplayName    = "Nguermo Noir",
		Ingredients    = { "Nguermo", "Chocoluxe", "Maple Syrup" },
		OutputColor    = Color3.fromRGB(55, 20, 60),
		RequireShaker  = true,
		StrongnessOverride = 62,
		Steps = {
			{ Ingredient = "Nguermo" },
			{ Ingredient = "Chocoluxe" },
			{ Ingredient = "Maple Syrup" },
			{ Tool = "Shaker" },
		},
		Presentation = { Garnishes = { "Cherry" } },
	},
	["Dealer's Choice"] = {
		DisplayName    = "Dealer's Choice",
		Ingredients    = { "Almendra", "Chocoluxe", "Creamora" },
		OutputColor    = Color3.fromRGB(150, 102, 79),
		RequireShaker  = true,
		StrongnessOverride = 62,
		Steps = {
			{ Ingredient = "Almendra" },
			{ Ingredient = "Chocoluxe" },
			{ Ingredient = "Creamora" },
			{ Tool = "Shaker" },
		},
		Presentation = { Garnishes = { "Cherry" } },
	},
	["Calliamo Crush"] = {
		DisplayName    = "Calliamo Crush",
		Ingredients    = { "Calliamo", "Bilijin", "Creamora" },
		OutputColor    = Color3.fromRGB(230, 120, 200),
		RequireShaker  = true,
		StrongnessOverride = 68,
		Steps = {
			{ Ingredient = "Calliamo" },
			{ Ingredient = "Bilijin" },
			{ Ingredient = "Creamora" },
			{ Tool = "Shaker" },
		},
		Presentation = { Garnishes = { "Cherry" } },
	},
	["Debt Collector"] = {
		DisplayName    = "Debt Collector",
		Ingredients    = { "Jaxline", "Maple Syrup", "Creamora" },
		OutputColor    = Color3.fromRGB(116, 74, 50),
		RequireShaker  = true,
		StrongnessOverride = 65,
		Steps = {
			{ Ingredient = "Jaxline" },
			{ Ingredient = "Maple Syrup" },
			{ Ingredient = "Creamora" },
			{ Tool = "Shaker" },
		},
		Presentation = { Garnishes = { "Orange" } },
	},
	["Barcandy Storm"] = {
		DisplayName    = "Barcandy Storm",
		Ingredients    = { "Barcandy", "Vermix", "Maple Syrup" },
		OutputColor    = Color3.fromRGB(220, 60, 90),
		RequireShaker  = true,
		StrongnessOverride = 72,
		Steps = {
			{ Ingredient = "Barcandy" },
			{ Ingredient = "Vermix" },
			{ Ingredient = "Maple Syrup" },
			{ Tool = "Shaker" },
		},
		Presentation = { Garnishes = { "Cherry" } },
	},
	["Sgm Horizon"] = {
		DisplayName    = "Sgm Horizon",
		Ingredients    = { "Sgm Jinn", "Fonador", "Simple Syrup" },
		OutputColor    = Color3.fromRGB(255, 100, 50),
		RequireShaker  = true,
		StrongnessOverride = 75,
		Steps = {
			{ Ingredient = "Sgm Jinn" },
			{ Ingredient = "Fonador" },
			{ Ingredient = "Simple Syrup" },
			{ Tool = "Shaker" },
		},
		Presentation = { Garnishes = { "Orange" } },
	},

	["Bukonelle Punch"] = {
		DisplayName    = "Bukonelle Punch",
		Ingredients    = { "Bukonelle", "Tropica", "Maple Syrup" },
		OutputColor    = Color3.fromRGB(190, 90, 160),
		RequireShaker  = true,
		StrongnessOverride = 64,
		Steps = {
			{ Ingredient = "Bukonelle" },
			{ Ingredient = "Tropica" },
			{ Ingredient = "Maple Syrup" },
			{ Tool = "Shaker" },
		},
		Presentation = { Garnishes = { "Orange" } },
	},
	["Long Shift"] = {
		DisplayName    = "Long Shift",
		Ingredients    = { "Caffemo", "Vodqa", "Soda Water", "Sugar" },
		OutputColor    = Color3.fromRGB(120, 90, 60),
		RequireShaker  = true,
		StrongnessOverride = 70,
		Steps = {
			{ Ingredient = "Caffemo" },
			{ Ingredient = "Vodqa" },
			{ Ingredient = "Soda Water" },
			{ Ingredient = "Sugar" },
			{ Tool = "Shaker" },
		},
		Presentation = { Garnishes = { "Lemon" } },
	},

	["Silk Road"] = {
		DisplayName    = "Silk Road",
		Ingredients    = { "Almendra", "Calliamo", "Simple Syrup" },
		OutputColor    = Color3.fromRGB(225, 170, 200),
		RequireShaker  = true,
		StrongnessOverride = 61,
		Steps = {
			{ Ingredient = "Almendra" },
			{ Ingredient = "Calliamo" },
			{ Ingredient = "Simple Syrup" },
			{ Tool = "Shaker" },
		},
		Presentation = { Garnishes = { "Cherry" } },
	},
	["Emerald Nguermo"] = {
		DisplayName    = "Emerald Nguermo",
		Ingredients    = { "Nguermo", "Vermix", "Simple Syrup" },
		OutputColor    = Color3.fromRGB(60, 140, 90),
		RequireShaker  = true,
		StrongnessOverride = 63,
		Steps = {
			{ Ingredient = "Nguermo" },
			{ Ingredient = "Vermix" },
			{ Ingredient = "Simple Syrup" },
			{ Tool = "Shaker" },
		},
		Presentation = { Garnishes = { "Lime" } },
	},
	["Sgm Rush"] = {
		DisplayName    = "Sgm Rush",
		Ingredients    = { "Sgm Jinn", "Barcandy", "Sugar" },
		OutputColor    = Color3.fromRGB(250, 110, 160),
		RequireShaker  = true,
		StrongnessOverride = 66,
		Steps = {
			{ Ingredient = "Sgm Jinn" },
			{ Ingredient = "Barcandy" },
			{ Ingredient = "Sugar" },
			{ Tool = "Shaker" },
		},
		Presentation = { Garnishes = { "Cherry" } },
	},
	["Double Debt"] = {
		DisplayName    = "Double Debt",
		Ingredients    = { "Jaxline", "Double Time", "Maple Syrup" },
		OutputColor    = Color3.fromRGB(140, 95, 45),
		RequireShaker  = true,
		StrongnessOverride = 68,
		Steps = {
			{ Ingredient = "Jaxline" },
			{ Ingredient = "Double Time" },
			{ Ingredient = "Maple Syrup" },
			{ Tool = "Shaker" },
		},
		Presentation = { Garnishes = { "Orange" } },
	},
	["Vodqa Mojito"] = {
		DisplayName    = "Vodqa Mojito",
		Ingredients    = { "Mintverde", "Vodqa", "Soda Water", "Simple Syrup" },
		OutputColor    = Color3.fromRGB(180, 235, 205),
		RequireShaker  = false,
		StrongnessOverride = 58,
		Steps = {
			{ Ingredient = "Mintverde" },
			{ Ingredient = "Vodqa" },
			{ Ingredient = "Soda Water" },
			{ Ingredient = "Simple Syrup" },
		},
		Presentation = { Garnishes = { "Lime" } },
	},

	-- ── NUCLEAR ───────────────────────────────────────────────────────
	["Blue Screen"] = {
		DisplayName    = "Blue Screen",
		Ingredients    = { "Vodqa", "Coolnag", "Soda Water" },
		OutputColor    = Color3.fromRGB(91, 177, 255),
		RequireShaker  = false,
		StrongnessOverride = 85,
		Steps = {
			{ Ingredient = "Vodqa" },
			{ Ingredient = "Coolnag" },
			{ Ingredient = "Soda Water" },
		},
		Presentation = { Garnishes = { "Lime" } },
	},
	["The Nguermo"] = {
		DisplayName    = "The Nguermo",
		Ingredients    = { "Nguermo", "Double Time", "Barcandy" },
		OutputColor    = Color3.fromRGB(80, 0, 30),
		RequireShaker  = true,
		StrongnessOverride = 90,
		Steps = {
			{ Ingredient = "Nguermo" },
			{ Ingredient = "Double Time" },
			{ Ingredient = "Barcandy" },
			{ Tool = "Shaker" },
		},
		Presentation = { Garnishes = { "Cherry" } },
	},
	["Sgm Overdrive"] = {
		DisplayName    = "Sgm Overdrive",
		Ingredients    = { "Sgm Jinn", "Vodqa", "Caffemo" },
		OutputColor    = Color3.fromRGB(30, 10, 60),
		RequireShaker  = true,
		StrongnessOverride = 95,
		Steps = {
			{ Ingredient = "Sgm Jinn" },
			{ Ingredient = "Vodqa" },
			{ Ingredient = "Caffemo" },
			{ Tool = "Shaker" },
		},
		Presentation = { Garnishes = { "Lime" } },
	},

	-- ── TAP & CAN ─────────────────────────────────────────────────────
	-- Straight pours from the tap or can — light, easy, no shaker.
	["Cold Draft"] = {
		DisplayName   = "Cold Draft",
		Ingredients   = { "Beer Tap" },
		OutputColor   = Color3.fromRGB(210, 165, 60),
		RequireShaker = false,
		StrongnessOverride = 20,
		Steps = {
			{ Ingredient = "Beer Tap" },
		},
		Presentation = { Garnishes = {} },
	},
	["Draft & Lime"] = {
		DisplayName   = "Draft & Lime",
		Ingredients   = { "Beer Tap", "Simple Syrup" },
		OutputColor   = Color3.fromRGB(190, 200, 80),
		RequireShaker = false,
		StrongnessOverride = 22,
		Steps = {
			{ Ingredient = "Beer Tap" },
			{ Ingredient = "Simple Syrup" },
		},
		Presentation = { Garnishes = { "Lime" } },
	},
	["Tin Rush"] = {
		DisplayName   = "Tin Rush",
		Ingredients   = { "Beer Can" },
		OutputColor   = Color3.fromRGB(220, 175, 65),
		RequireShaker = false,
		StrongnessOverride = 20,
		Steps = {
			{ Ingredient = "Beer Can" },
		},
		Presentation = { Garnishes = {} },
	},
	["Tin & Twist"] = {
		DisplayName   = "Tin & Twist",
		Ingredients   = { "Beer Can", "Mintverde" },
		OutputColor   = Color3.fromRGB(180, 210, 100),
		RequireShaker = false,
		StrongnessOverride = 24,
		Steps = {
			{ Ingredient = "Beer Can" },
			{ Ingredient = "Mintverde" },
		},
		Presentation = { Garnishes = { "Lime" } },
	},

	["Absmith Abyss"] = {
		DisplayName    = "Absmith Abyss",
		Ingredients    = { "Absmith", "Nguermo", "Vodqa" },
		OutputColor    = Color3.fromRGB(35, 25, 55),
		RequireShaker  = true,
		StrongnessOverride = 88,
		Steps = {
			{ Ingredient = "Absmith" },
			{ Ingredient = "Nguermo" },
			{ Ingredient = "Vodqa" },
			{ Tool = "Shaker" },
		},
		Presentation = { Garnishes = { "Cherry" } },
	},

	["Graveyard Shift"] = {
		DisplayName    = "Graveyard Shift",
		Ingredients    = { "Double Time", "Vodqa", "Absmith" },
		OutputColor    = Color3.fromRGB(40, 40, 50),
		RequireShaker  = true,
		StrongnessOverride = 86,
		Steps = {
			{ Ingredient = "Double Time" },
			{ Ingredient = "Vodqa" },
			{ Ingredient = "Absmith" },
			{ Tool = "Shaker" },
		},
		Presentation = { Garnishes = { "Lemon" } },
	},
	["Candy Burst"] = {
		DisplayName    = "Candy Burst",
		Ingredients    = { "Barcandy", "Bilijin", "Vodqa" },
		OutputColor    = Color3.fromRGB(255, 70, 120),
		RequireShaker  = true,
		StrongnessOverride = 90,
		Steps = {
			{ Ingredient = "Barcandy" },
			{ Ingredient = "Bilijin" },
			{ Ingredient = "Vodqa" },
			{ Tool = "Shaker" },
		},
		Presentation = { Garnishes = { "Cherry" } },
	},

	-- ── SECRET (never shown in guidance — players must discover them) ──
	["Sin Obu"] = {
		DisplayName    = "Sin Obu",
		Ingredients    = { "Vodqa", "Vodqa", "Vodqa" },
		OutputColor    = Color3.fromRGB(150, 20, 45),
		RequireShaker  = false,
		Secret         = true,
		StrongnessOverride = 90,
		Sips           = 1,  -- one gulp, then the consequences
		-- Special behavior lives in ServerScriptService/DrinkSystem/DrinkCallbacks/SinObu.luau
		-- (forced 60s ragdoll + spinning vision). New special drinks: one recipe
		-- entry + one callback module.
		Callback       = "SinObu",
		Steps = {
			{ Ingredient = "Vodqa" },
			{ Ingredient = "Vodqa" },
			{ Ingredient = "Vodqa" },
		},
		Presentation = { Garnishes = {} },
	},
	-- Made by pouring Water onto an already-finished Water drink twice more
	-- (special upgrade path in onPour — auto-finalize would otherwise stop it)
	["Solaire's Spit"] = {
		DisplayName    = "Solaire's Spit",
		Ingredients    = { "Water", "Water", "Water" },
		OutputColor    = Color3.fromRGB(248, 248, 248),
		RequireShaker  = false,
		Secret         = true,
		SkipShaker     = true,
		FillStageOverride = 3,
		StrongnessOverride = -100,  -- fully sobers you
		Steps = {
			{ Ingredient = "Water" },
			{ Ingredient = "Water" },
			{ Ingredient = "Water" },
		},
		Presentation = { Garnishes = {} },
	},

	-- ── SOBER ─────────────────────────────────────────────────────────
	-- Water works two ways (no shaker required for either):
	--   1. No glass in hand → click the water source, drink on the spot (onPour intercept)
	--   2. Glass in hand → pours into the glass, auto-finalizes to this recipe
	["Water"] = {
		DisplayName    = "Water",
		Ingredients    = { "Water" },
		OutputColor    = Color3.fromRGB(110, 185, 255),
		RequireShaker  = false,
		SkipShaker     = true,  -- bypass AUTO_SHAKER_ON_RECIPE — finalize instantly
		FillStageOverride = 3,  -- one pour fills the whole glass
		StrongnessOverride = -35,
		Steps = {
			{ Ingredient = "Water" },
		},
		Presentation = { Garnishes = {} },
	},
}

return Recipes
