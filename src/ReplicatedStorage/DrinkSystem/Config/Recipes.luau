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
	["Tropicali"] = {
		DisplayName    = "Tropicali",
		Ingredients    = { "Tropica", "Coolnag", "Simple Syrup" },
		OutputColor    = Color3.fromRGB(255, 200, 60),
		RequireShaker  = false,
		StrongnessOverride = 20,
		Steps = {
			{ Ingredient = "Tropica" },
			{ Ingredient = "Coolnag" },
			{ Ingredient = "Simple Syrup" },
		},
		Presentation = { Garnishes = { "Orange" } },
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
		Ingredients    = { "Biljin", "Tropica", "Sugar" },
		OutputColor    = Color3.fromRGB(255, 146, 76),
		RequireShaker  = false,
		StrongnessOverride = 22,
		Steps = {
			{ Ingredient = "Biljin" },
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
		Ingredients    = { "Calliamo", "Biljin", "Creamora" },
		OutputColor    = Color3.fromRGB(230, 120, 200),
		RequireShaker  = true,
		StrongnessOverride = 68,
		Steps = {
			{ Ingredient = "Calliamo" },
			{ Ingredient = "Biljin" },
			{ Ingredient = "Creamora" },
			{ Tool = "Shaker" },
		},
		Presentation = { Garnishes = { "Cherry" } },
	},
	["Debt Collector"] = {
		DisplayName    = "Debt Collector",
		Ingredients    = { "JacklineDale", "Maple Syrup", "Creamora" },
		OutputColor    = Color3.fromRGB(116, 74, 50),
		RequireShaker  = true,
		StrongnessOverride = 65,
		Steps = {
			{ Ingredient = "JacklineDale" },
			{ Ingredient = "Maple Syrup" },
			{ Ingredient = "Creamora" },
			{ Tool = "Shaker" },
		},
		Presentation = { Garnishes = { "Orange" } },
	},
	["Barcandy Bomb"] = {
		DisplayName    = "Barcandy Bomb",
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

	-- ── SOBER ─────────────────────────────────────────────────────────
	["Still Water"] = {
		DisplayName    = "Still Water",
		Ingredients    = { "Water" },
		OutputColor    = Color3.fromRGB(200, 230, 255),
		RequireShaker  = false,
		StrongnessOverride = -35,
		Steps = {
			{ Ingredient = "Water" },
		},
		Presentation = { Garnishes = {} },
	},
}

return Recipes
