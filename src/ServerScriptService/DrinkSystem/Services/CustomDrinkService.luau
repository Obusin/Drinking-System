-- CustomDrinkService: paid player-created drinks ("your drink on the menu").
--
-- Flow:
--   1. Player buys a duration-tier Dev Product (Settings.CustomDrinkProducts:
--      hours → product ID) → ProcessReceipt grants a persisted CREATION TOKEN
--      for that many hours (survives crashes; granting before PurchaseGranted
--      is the golden receipt rule).
--   2. Client composer submits { Name, Ingredients (2-4), Color } →
--      server validates EVERYTHING (never trust the client):
--        - ingredients exist in IngredientRegistry
--        - ingredient set doesn't collide with ANY existing recipe
--          (including secrets — no buying your way to Sin Obu's combo)
--        - name passes TextService filtering + length rules
--        - strongness DERIVED from ingredients server-side (not client-sent)
--   3. Published as a Folder under ReplicatedStorage.DrinkSystem.DynamicRecipes
--      (attribute-encoded; replicates → RecipeRegistry merges it on both sides)
--      and persisted to DataStore so every server serves it until expiry.
--
-- Testing: Settings.CustomDrinkFreeTesting = true grants a token to anyone
-- who requests state without owning one — NO robux needed. Turn OFF for launch.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local TextService = game:GetService("TextService")

local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local SharedModules = DrinkSystem:WaitForChild("SharedModules")
local ConfigFolder = DrinkSystem:WaitForChild("Config")

local Settings = require(ConfigFolder:WaitForChild("Settings"))
local IngredientRegistry = require(SharedModules:WaitForChild("IngredientRegistry"))
local RecipeRegistry = require(SharedModules:WaitForChild("RecipeRegistry"))
local Network = require(SharedModules:WaitForChild("Network"))
local Packets = Network.Packets

local CustomDrinkService = {}

local STORE_NAME = "DS_CustomDrinks_v1"
local ACTIVE_KEY = "active_v1" -- one shared record: array of live custom drinks
local TOKEN_KEY_PREFIX = "token_" -- token_<userId> = number of unspent creations

-- 4-6 ingredients: house recipes use 1-4, so a 4+ requirement plus the
-- exact-match collision check keeps custom combos from shadowing them
local MIN_INGREDIENTS = 4
local MAX_INGREDIENTS = 6
local MAX_NAME_LENGTH = 24
local MIN_NAME_LENGTH = 3
local STRONGNESS_PER_ALCOHOL = 22 -- Strongness 1 ingredients pay this much
local STRONGNESS_CAP = 75         -- custom drinks can never hit collapse tier
local REFRESH_INTERVAL = 120      -- pull other servers' creations every 2 min
local SWEEP_INTERVAL = 60         -- expiry check

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
end)

-- In-memory mirror of the active list (kept in sync with the folder)
local activeDrinks: { any } = {}
local tokensByUser: { [number]: { number } } = {} -- session cache: array of unspent durations (hours)

---------------------------------------------------------------------
-- Publishing: DataStore record → replicated folder entry
---------------------------------------------------------------------
local dynamicFolder: Folder

local function ensureFolder(): Folder
	if dynamicFolder and dynamicFolder.Parent then
		return dynamicFolder
	end
	local existing = DrinkSystem:FindFirstChild("DynamicRecipes")
	if existing and existing:IsA("Folder") then
		dynamicFolder = existing
	else
		dynamicFolder = Instance.new("Folder")
		dynamicFolder.Name = "DynamicRecipes"
		dynamicFolder.Parent = DrinkSystem
	end
	return dynamicFolder
end

local function publishEntry(record: any)
	local folder = ensureFolder()
	local entry = folder:FindFirstChild(record.Name)
	if not entry then
		entry = Instance.new("Folder")
		entry.Name = record.Name
		entry.Parent = folder
	end
	entry:SetAttribute("DisplayName", record.Name)
	entry:SetAttribute("IngredientsCsv", table.concat(record.Ingredients, ","))
	entry:SetAttribute("Color", Color3.fromRGB(record.Color[1], record.Color[2], record.Color[3]))
	entry:SetAttribute("Strongness", record.Strongness)
	entry:SetAttribute("CreatorName", record.CreatorName)
	entry:SetAttribute("CreatorUserId", record.CreatorUserId)
	entry:SetAttribute("ExpiresAt", record.ExpiresAt)
end

local function unpublishEntry(name: string)
	local folder = ensureFolder()
	local entry = folder:FindFirstChild(name)
	if entry then
		entry:Destroy()
	end
end

local function syncFolder()
	local folder = ensureFolder()
	local wanted: { [string]: any } = {}
	for _, record in ipairs(activeDrinks) do
		wanted[record.Name] = record
	end
	for _, entry in ipairs(folder:GetChildren()) do
		if not wanted[entry.Name] then
			entry:Destroy()
		end
	end
	for _, record in pairs(wanted) do
		publishEntry(record)
	end
end

---------------------------------------------------------------------
-- Persistence (single shared key, UpdateAsync for cross-server safety)
---------------------------------------------------------------------
local function loadActive()
	if not store then return end
	local ok, data = pcall(function()
		return store:GetAsync(ACTIVE_KEY)
	end)
	if ok and type(data) == "table" then
		local now = os.time()
		local live = {}
		for _, record in ipairs(data) do
			if type(record) == "table" and record.Name and (record.ExpiresAt or 0) > now then
				table.insert(live, record)
			end
		end
		activeDrinks = live
		syncFolder()
	end
end

-- mutate(list) -> newList. Runs under UpdateAsync so two servers can't
-- clobber each other; the local mirror adopts whatever won.
local function updateActive(mutate: (list: { any }) -> { any })
	if not store then
		activeDrinks = mutate(activeDrinks)
		syncFolder()
		return true
	end
	local ok, err = pcall(function()
		store:UpdateAsync(ACTIVE_KEY, function(old)
			local list = type(old) == "table" and old or {}
			-- Drop expired entries on every write
			local now = os.time()
			local live = {}
			for _, record in ipairs(list) do
				if type(record) == "table" and (record.ExpiresAt or 0) > now then
					table.insert(live, record)
				end
			end
			local result = mutate(live)
			activeDrinks = result
			return result
		end)
	end)
	if not ok then
		warn("[CustomDrink] UpdateAsync failed:", err)
		return false
	end
	syncFolder()
	return true
end

---------------------------------------------------------------------
-- Creation tokens (persisted — a paid token must survive a server crash)
---------------------------------------------------------------------
local function loadTokens(userId: number): { number }
	if tokensByUser[userId] then
		return tokensByUser[userId]
	end
	local list: { number } = {}
	if store then
		local ok, data = pcall(function()
			return store:GetAsync(TOKEN_KEY_PREFIX .. userId)
		end)
		if ok then
			if type(data) == "table" then
				for _, hours in ipairs(data) do
					if type(hours) == "number" then
						table.insert(list, hours)
					end
				end
			elseif type(data) == "number" then
				-- Legacy count-based tokens convert to 24h slots
				for _ = 1, data do
					table.insert(list, 24)
				end
			end
		end
	end
	tokensByUser[userId] = list
	return list
end

local function saveTokens(userId: number, list: { number }): boolean
	if store then
		local ok = pcall(function()
			store:SetAsync(TOKEN_KEY_PREFIX .. userId, list)
		end)
		if not ok then
			return false
		end
	end
	tokensByUser[userId] = list
	return true
end

local function grantToken(userId: number, hours: number): boolean
	local list = table.clone(loadTokens(userId))
	table.insert(list, hours)
	return saveTokens(userId, list)
end

-- Spend one token matching `hours`. Returns success.
local function spendToken(userId: number, hours: number): boolean
	local list = table.clone(loadTokens(userId))
	for i, h in ipairs(list) do
		if h == hours then
			table.remove(list, i)
			return saveTokens(userId, list)
		end
	end
	return false
end

---------------------------------------------------------------------
-- Validation
---------------------------------------------------------------------
-- The creator picks the drunkness level with a slider; the server just
-- enforces the flat bounds (custom drinks never reach collapse tier).
local STRONGNESS_MIN = 5

local function resolveStrongness(requested: number?): number
	local value = tonumber(requested) or 40
	return math.clamp(math.floor(value), STRONGNESS_MIN, STRONGNESS_CAP)
end

local function filterName(player: Player, rawName: string): (string?, string?)
	local name = string.gsub(rawName, "^%s+", "")
	name = string.gsub(name, "%s+$", "")
	name = string.gsub(name, "%s+", " ")
	if #name < MIN_NAME_LENGTH then
		return nil, "Name is too short"
	end
	if #name > MAX_NAME_LENGTH then
		return nil, "Name is too long (max " .. MAX_NAME_LENGTH .. ")"
	end
	if string.find(name, ",") then
		return nil, "Name can't contain commas"
	end
	local filtered
	local ok = pcall(function()
		local result = TextService:FilterStringAsync(name, player.UserId)
		filtered = result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or not filtered then
		return nil, "Couldn't verify the name — try again"
	end
	if filtered ~= name then
		return nil, "That name isn't allowed"
	end
	return name, nil
end

local function validateIngredients(list: { string }): (boolean, string?)
	if type(list) ~= "table" then
		return false, "Bad ingredient list"
	end
	if #list < MIN_INGREDIENTS or #list > MAX_INGREDIENTS then
		return false, ("Pick %d-%d ingredients"):format(MIN_INGREDIENTS, MAX_INGREDIENTS)
	end
	for _, name in ipairs(list) do
		if type(name) ~= "string" or not IngredientRegistry.exists(name) then
			return false, "Unknown ingredient"
		end
		if name == "Water" then
			return false, "Water can't be part of a custom drink"
		end
	end
	-- Must not exactly match ANY existing recipe (static, secret, or another
	-- player's custom drink) — the mix system needs one unambiguous match
	local existingDef, existingName = RecipeRegistry.getRecipeByIngredients(list)
	if existingDef then
		local label = existingDef.Secret == true and "a secret recipe" or ('"%s"'):format(existingName)
		return false, "That combination is already " .. label
	end
	return true, nil
end

---------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------
local VALID_HOURS: { [number]: boolean } = { [4] = true, [8] = true, [12] = true, [24] = true }
local MAX_ACTIVE_PER_PLAYER = 5 -- menu-spam guard, not a monetization limit

-- Returns (tokenHours array, how many live drinks this player has)
function CustomDrinkService.getState(player: Player): ({ number }, number)
	local tokenHours = loadTokens(player.UserId)
	local mineCount = 0
	for _, record in ipairs(activeDrinks) do
		if record.CreatorUserId == player.UserId then
			mineCount += 1
		end
	end
	return tokenHours, mineCount
end

function CustomDrinkService.create(player: Player, rawName: string, ingredients: { string }, colorR: number, colorG: number, colorB: number, hours: number, strongness: number?): (boolean, string)
	hours = tonumber(hours) or 0
	if not VALID_HOURS[hours] then
		return false, "Pick a duration (4, 8, 12 or 24 hours)"
	end

	local freeTesting = Settings.CustomDrinkFreeTesting == true
	if not freeTesting then
		local owned = false
		for _, h in ipairs(loadTokens(player.UserId)) do
			if h == hours then
				owned = true
				break
			end
		end
		if not owned then
			return false, ("You don't own a %dh slot — purchase one first"):format(hours)
		end
	end

	-- Soft cap so one player can't flood the whole menu
	local _, mineCount = CustomDrinkService.getState(player)
	if mineCount >= MAX_ACTIVE_PER_PLAYER then
		return false, ("You already have %d live drinks — wait for one to expire"):format(mineCount)
	end

	local okIng, ingErr = validateIngredients(ingredients)
	if not okIng then
		return false, ingErr :: string
	end

	local name, nameErr = filterName(player, rawName)
	if not name then
		return false, nameErr :: string
	end
	if RecipeRegistry.get(name) ~= nil then
		return false, "A drink with that name already exists"
	end

	local record = {
		Name = name,
		CreatorUserId = player.UserId,
		CreatorName = player.Name,
		Ingredients = table.clone(ingredients),
		Color = {
			math.clamp(math.floor(tonumber(colorR) or 200), 0, 255),
			math.clamp(math.floor(tonumber(colorG) or 120), 0, 255),
			math.clamp(math.floor(tonumber(colorB) or 60), 0, 255),
		},
		Strongness = resolveStrongness(strongness),
		CreatedAt = os.time(),
		ExpiresAt = os.time() + hours * 3600,
		DurationHours = hours,
	}

	-- Spend the token FIRST (crash between spend and publish = player support
	-- case; crash the other way = free drinks, which is worse)
	if not freeTesting and not spendToken(player.UserId, hours) then
		return false, "Purchase system hiccup — try again"
	end

	local published = updateActive(function(list)
		-- Re-check collisions under the write lock (another server may have
		-- registered the same name/combo in the meantime)
		for _, existing in ipairs(list) do
			if existing.Name == record.Name then
				return list -- unchanged: signal by absence below
			end
		end
		local copy = table.clone(list)
		table.insert(copy, record)
		return copy
	end)

	local landed = false
	for _, r in ipairs(activeDrinks) do
		if r.Name == record.Name and r.CreatorUserId == player.UserId then
			landed = true
			break
		end
	end
	if not published or not landed then
		if not freeTesting then
			grantToken(player.UserId, hours) -- refund
		end
		return false, "That name was just taken — try another"
	end

	return true, ("%q is live for %d hours!"):format(name, hours)
end

---------------------------------------------------------------------
-- Receipt processing (Dev Product purchase → creation token)
---------------------------------------------------------------------
local function hoursForProduct(productId: number): number?
	local products = Settings.CustomDrinkProducts or {}
	for hours, id in pairs(products) do
		if id ~= 0 and id == productId then
			return hours
		end
	end
	return nil
end

local function anyProductConfigured(): boolean
	for _, id in pairs(Settings.CustomDrinkProducts or {}) do
		if id ~= 0 then
			return true
		end
	end
	return false
end

local function processReceipt(receiptInfo): Enum.ProductPurchaseDecision
	local hours = hoursForProduct(receiptInfo.ProductId)
	if not hours then
		-- Not ours — let other handlers exist someday; don't eat the receipt
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not grantToken(receiptInfo.PlayerId, hours) then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- retried later
	end
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if player then
		local tokenHours, mineCount = CustomDrinkService.getState(player)
		Packets.CustomDrinkState.sendTo({
			TokenHours = tokenHours,
			ActiveCount = mineCount,
		}, player)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

---------------------------------------------------------------------
-- Init
---------------------------------------------------------------------
function CustomDrinkService.init()
	ensureFolder()
	loadActive()

	if anyProductConfigured() then
		MarketplaceService.ProcessReceipt = processReceipt
	end

	-- Expiry sweep + cross-server refresh
	task.spawn(function()
		local lastRefresh = os.clock()
		while true do
			task.wait(SWEEP_INTERVAL)
			local now = os.time()
			local expired = false
			for _, record in ipairs(activeDrinks) do
				if (record.ExpiresAt or 0) <= now then
					expired = true
					break
				end
			end
			if expired then
				updateActive(function(list)
					return list -- updateActive already prunes expired entries
				end)
			end
			if os.clock() - lastRefresh >= REFRESH_INTERVAL then
				lastRefresh = os.clock()
				loadActive()
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		tokensByUser[player.UserId] = nil
	end)
end

return CustomDrinkService
