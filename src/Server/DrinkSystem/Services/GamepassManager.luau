-- ServerScriptService/DrinkSystem/GamepassManager

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DrinkSystemFolder = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystemFolder:WaitForChild("Config")
local Settings = require(ConfigFolder:WaitForChild("Settings"))

local GamepassManager = {}

local cache: { [number]: boolean } = {}

function GamepassManager.playerHasBartenderPass(player: Player): boolean
	local userId = player.UserId
	if cache[userId] ~= nil then
		return cache[userId]
	end

	local success, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, Settings.BartenderGamepassId)
	end)

	if not success then
		-- Fail safe: treat as not owning; you can optionally log
		cache[userId] = false
		return false
	end

	cache[userId] = result
	return result
end

function GamepassManager.clearCacheForPlayer(player: Player)
	cache[player.UserId] = nil
end

return GamepassManager
