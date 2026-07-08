-- IngredientRegistry.lua
-- These names must match DS_IngredientName on your bottles

local IngredientRegistry = {}

local BASE_STRONGNESS = 1
local BASE_COLOR = Color3.fromRGB(235, 235, 235)

local INGREDIENTS = {
	-- Drinks
	Absmith = { Strongness = BASE_STRONGNESS, Color = BASE_COLOR },
	Almendra = { Strongness = BASE_STRONGNESS, Color = BASE_COLOR },
	Barcandy = { Strongness = BASE_STRONGNESS, Color = BASE_COLOR },
	Bilijin = { Strongness = BASE_STRONGNESS, Color = BASE_COLOR },
	Bukonelle = { Strongness = BASE_STRONGNESS, Color = BASE_COLOR },
	["Double Time"] = { Strongness = BASE_STRONGNESS, Color = BASE_COLOR },
	Fonador = { Strongness = BASE_STRONGNESS, Color = BASE_COLOR },
	JacklineDale = { Strongness = BASE_STRONGNESS, Color = BASE_COLOR },
	Nguermo = { Strongness = BASE_STRONGNESS, Color = BASE_COLOR },
	Vermix = { Strongness = BASE_STRONGNESS, Color = BASE_COLOR },
	Vodqa = { Strongness = BASE_STRONGNESS, Color = BASE_COLOR },
	Caffemo = { Strongness = BASE_STRONGNESS, Color = BASE_COLOR },
	Calliamo = { Strongness = BASE_STRONGNESS, Color = BASE_COLOR },
	Chocoluxe = { Strongness = BASE_STRONGNESS, Color = BASE_COLOR },
	Cochoco = { Strongness = BASE_STRONGNESS, Color = BASE_COLOR },
	Coolnag = { Strongness = BASE_STRONGNESS, Color = BASE_COLOR },
	Creamora = { Strongness = BASE_STRONGNESS, Color = BASE_COLOR },
	Tropica = { Strongness = BASE_STRONGNESS, Color = BASE_COLOR },
	["Sgm Jinn"] = { Strongness = BASE_STRONGNESS, Color = BASE_COLOR },
	Mintverde = { Strongness = BASE_STRONGNESS, Color = BASE_COLOR },

	-- Sides
	["Maple Syrup"] = { Strongness = 0, Color = BASE_COLOR },
	["Simple Syrup"] = { Strongness = 0, Color = BASE_COLOR },
	["Soda Water"] = { Strongness = 0, Color = BASE_COLOR },
	Sugar = { Strongness = 0, Color = BASE_COLOR },

	-- Stand Alone
	Water = { Strongness = 0, Color = Color3.fromRGB(95, 175, 255) },
	["Beer Tap"] = { Strongness = BASE_STRONGNESS, Color = Color3.fromRGB(210, 170, 80) },
	["Beer Can"] = { Strongness = BASE_STRONGNESS, Color = Color3.fromRGB(220, 180, 70) },
}

function IngredientRegistry.get(name: string)
	return INGREDIENTS[name]
end

function IngredientRegistry.exists(name: string)
	return INGREDIENTS[name] ~= nil
end

function IngredientRegistry.list()
	return INGREDIENTS
end

function IngredientRegistry.listNames(): {string}
	local names = {}
	for name in pairs(INGREDIENTS) do
		table.insert(names, name)
	end
	return names
end

return IngredientRegistry
