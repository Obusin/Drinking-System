local Recipes = {
	["Blue Screen"] = {
		DisplayName = "Blue Screen",
		Ingredients = { "Vodqa", "Coolnag", "Soda Water" },
		OutputColor = Color3.fromRGB(91, 177, 255),
		RequireShaker = false,
		StrongnessOverride = 2,
		Steps = {
			{ Ingredient = "Vodqa" },
			{ Ingredient = "Coolnag" },
			{ Ingredient = "Soda Water" },
		},
		Presentation = {
			Garnishes = { "Lime" },
		},
	},
	["Debt Collector"] = {
		DisplayName = "Debt Collector",
		Ingredients = { "JacklineDale", "Maple Syrup", "Creamora" },
		OutputColor = Color3.fromRGB(116, 74, 50),
		RequireShaker = true,
		StrongnessOverride = 3,
		Steps = {
			{ Ingredient = "JacklineDale" },
			{ Ingredient = "Maple Syrup" },
			{ Ingredient = "Creamora" },
			{ Tool = "Shaker" },
		},
		Presentation = {
			Garnishes = { "Orange" },
		},
	},
	["Heatstroke"] = {
		DisplayName = "Heatstroke",
		Ingredients = { "Bilijin", "Tropica", "Sugar" },
		OutputColor = Color3.fromRGB(255, 146, 76),
		RequireShaker = false,
		StrongnessOverride = 2,
		Steps = {
			{ Ingredient = "Biljin" },
			{ Ingredient = "Tropica" },
			{ Ingredient = "Sugar" },
		},
		Presentation = {
			Garnishes = { "Orange" },
		},
	},
	["Dealer's Choice"] = {
		DisplayName = "Dealer's Choice",
		Ingredients = { "Almendra", "Chocoluxe", "Creamora" },
		OutputColor = Color3.fromRGB(150, 102, 79),
		RequireShaker = true,
		StrongnessOverride = 2,
		Steps = {
			{ Ingredient = "Almendra" },
			{ Ingredient = "Chocoluxe" },
			{ Ingredient = "Creamora" },
			{ Tool = "Shaker" },
		},
		Presentation = {
			Garnishes = { "Cherry" },
		},
	},
}

return Recipes
