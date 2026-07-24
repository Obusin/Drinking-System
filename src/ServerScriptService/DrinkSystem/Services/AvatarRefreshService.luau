-- AvatarRefreshService: refreshes a player's outfit to whatever's currently
-- saved on their account, without the "hassle" of a normal respawn (walking
-- back from spawn, losing your place).
--
-- Humanoid:ApplyDescription looked like the right tool, but it does NOT
-- reliably rebuild body scale (HipHeight, R15 proportions) on a LIVE
-- character — outfits swap but the body stays shaped like the OLD avatar.
-- That's a real Roblox limitation, not something client-side property
-- nudges can fully patch around. The reliable fix is player:LoadCharacter()
-- — the exact same code path a real join/respawn uses, so scale + outfit
-- come out byte-for-byte correct — immediately re-positioned to where they
-- were standing so it reads as instant rather than a visible respawn.
--
-- Any per-character effect state tied to the OLD Humanoid/HRP instance is
-- orphaned by this (same as a normal death would do). IceCubeService already
-- force-releases on every CharacterAdded as a safety net; Olkab's Hair is
-- explicitly cancelled here for the same reason.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystem:WaitForChild("Config")
local SharedModules = DrinkSystem:WaitForChild("SharedModules")

local Settings = require(ConfigFolder:WaitForChild("Settings"))

local callbacksFolder = script.Parent.Parent:WaitForChild("DrinkCallbacks")
local OlkabsHair = require(callbacksFolder:WaitForChild("OlkabsHair"))
local DrinkEffectsService = require(script.Parent:WaitForChild("DrinkEffectsService"))

local AvatarRefreshService = {}

local lastRefreshAt: { [Player]: number } = {}

function AvatarRefreshService.Refresh(player: Player, iceCubeService: any?): (boolean, string)
	if Settings.EnableOutfitRefresh ~= true then
		return false, "Outfit refresh is disabled"
	end

	local now = os.clock()
	local cooldown = Settings.OutfitRefreshCooldown or 5
	local last = lastRefreshAt[player]
	if last and (now - last) < cooldown then
		return false, "Hold on a moment before refreshing again"
	end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not hrp then
		return false, "Character not ready"
	end

	-- Too risky to allow a character swap while welded/network-owned by the
	-- Ice Cube trap
	if iceCubeService and iceCubeService.IsTrapped(player) then
		return false, "Can't refresh while frozen"
	end

	local savedCFrame = hrp.CFrame

	-- About to go stale against whatever new character spawns in — abandon
	-- cleanly rather than restoring mismatched hair onto a new body later
	OlkabsHair.CancelForRefresh(player)

	-- An EQUIPPED tool is a child of the character, not Backpack — LoadCharacter
	-- destroys the old character outright, taking anything still equipped
	-- down with it. Unequip first so it survives in Backpack instead.
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("Tool") then
				child.Parent = backpack
			end
		end
	end

	local repositionConn: RBXScriptConnection? = nil
	repositionConn = player.CharacterAdded:Connect(function(newChar)
		if repositionConn then
			repositionConn:Disconnect()
			repositionConn = nil
		end
		newChar:PivotTo(savedCFrame)
		local newHrp = newChar:FindFirstChild("HumanoidRootPart") :: BasePart?
		if newHrp then
			newHrp.AssemblyLinearVelocity = Vector3.zero
			newHrp.AssemblyAngularVelocity = Vector3.zero
		end
		DrinkEffectsService.playCharacterSound(
			player,
			Settings.OutfitRefreshSoundId,
			Settings.OutfitRefreshVolume or 0.5
		)
	end)

	-- Tells DrinkSystemController's respawn handler to skip its "fresh join"
	-- wipe (glasses, drunkness, mix state) — this reload is cosmetic-only.
	player:SetAttribute("DS_SkipNextRespawnReset", true)

	local ok = pcall(function()
		player:LoadCharacter()
	end)
	if not ok then
		if repositionConn then
			repositionConn:Disconnect()
		end
		player:SetAttribute("DS_SkipNextRespawnReset", nil) -- don't let this leak into a later real respawn
		return false, "Refresh failed — try again"
	end

	lastRefreshAt[player] = now
	return true, "Outfit refreshed!"
end

function AvatarRefreshService.init()
	Players.PlayerRemoving:Connect(function(player)
		lastRefreshAt[player] = nil
	end)
end

return AvatarRefreshService
