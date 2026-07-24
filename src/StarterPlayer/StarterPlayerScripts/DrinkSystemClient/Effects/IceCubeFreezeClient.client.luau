-- IceCubeFreezeClient: while frozen, suppress LOCALLY-triggered animations
-- (emotes, /e dance, the emote wheel) on our OWN character. The default
-- Roblox emote system plays instantly on the owning client for input
-- responsiveness — the server's Stop() calls only reach us after a
-- replication round-trip, so this same client that's playing the emote is
-- the only place that can actually kill it with zero visible delay.
-- Other players never see this in the first place — the server-side
-- IceCubeService already stops/suppresses tracks from THEIR point of view.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local SharedModules = DrinkSystem:WaitForChild("SharedModules")
local Network = require(SharedModules:WaitForChild("Network"))
local Packets = Network.Packets

local animConn: RBXScriptConnection? = nil
local pollConn: RBXScriptConnection? = nil

local function getAnimator(): Animator?
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	return humanoid and (humanoid:FindFirstChildOfClass("Animator") :: Animator?)
end

local function stopAllTracks()
	local animator = getAnimator()
	if not animator then
		return
	end
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		track:Stop(0)
	end
end

local function setFrozen(frozen: boolean)
	if animConn then
		animConn:Disconnect()
		animConn = nil
	end
	if pollConn then
		pollConn:Disconnect()
		pollConn = nil
	end
	if not frozen then
		return
	end

	stopAllTracks()
	local animator = getAnimator()
	if animator then
		-- Fires the instant a local emote/animation starts — this connection
		-- has TRUE local authority (same client that's playing it), unlike
		-- the server's version of this same hook
		animConn = animator.AnimationPlayed:Connect(function(track)
			track:Stop(0)
		end)
	end
	-- Belt-and-suspenders: catches the window right after a respawn where
	-- the Animator might not exist yet when setFrozen(true) first runs
	pollConn = RunService.Heartbeat:Connect(stopAllTracks)
end

Packets.IceCubeFrozen.listen(function(data)
	setFrozen(data.Trapped == true)
end)

-- Respawning mid-freeze would leave a stale hook on the old Animator;
-- the server always sends a fresh IceCubeFrozen packet after re-trapping,
-- but if they somehow respawn OUT of a trap, make sure nothing lingers
player.CharacterRemoving:Connect(function()
	setFrozen(false)
end)
