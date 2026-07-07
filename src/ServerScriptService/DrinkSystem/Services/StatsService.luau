-- StatsService: per-player drink stats shown in the Roblox player list
-- (leaderstats) and persisted across sessions via DataStore.
--   "Drinks Made"  — finalized drinks crafted (Water excluded)
--   "Drinks Drunk" — drinks fully finished (last sip; Water excluded)

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local StatsService = {}

local STORE_NAME = "DS_PlayerStats_v1"
local store = nil
pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
end)

local statsByPlayer: { [Player]: { Made: IntValue, Drunk: IntValue } } = {}

local function setupPlayer(player: Player)
	if statsByPlayer[player] then return end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local made = Instance.new("IntValue")
	made.Name = "Drinks Made"
	made.Parent = leaderstats

	local drunk = Instance.new("IntValue")
	drunk.Name = "Drinks Drunk"
	drunk.Parent = leaderstats

	statsByPlayer[player] = { Made = made, Drunk = drunk }

	if store then
		task.spawn(function()
			local ok, data = pcall(function()
				return store:GetAsync("p" .. player.UserId)
			end)
			if ok and type(data) == "table" then
				made.Value = tonumber(data.Made) or 0
				drunk.Value = tonumber(data.Drunk) or 0
			end
		end)
	end
end

local function savePlayer(player: Player)
	local stats = statsByPlayer[player]
	if not stats or not store then return end
	local made, drunk = stats.Made.Value, stats.Drunk.Value
	pcall(function()
		store:SetAsync("p" .. player.UserId, { Made = made, Drunk = drunk })
	end)
end

function StatsService.incrementMade(player: Player)
	local stats = statsByPlayer[player]
	if stats then stats.Made.Value += 1 end
end

function StatsService.incrementDrunk(player: Player)
	local stats = statsByPlayer[player]
	if stats then stats.Drunk.Value += 1 end
end

function StatsService.init()
	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayer(player)
	end
	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(function(player)
		savePlayer(player)
		statsByPlayer[player] = nil
	end)
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			savePlayer(player)
		end
	end)
end

return StatsService
