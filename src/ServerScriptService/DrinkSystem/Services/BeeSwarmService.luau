-- BeeSwarmService: visual-only secret effect. Clones the "Bee Swarm" VFX and
-- orbits it around the player's torso, plays the buzzing sound + a "shooing
-- bees away" animation. Purely cosmetic — no movement lock, unlike Ice Cube.
--
-- Studio setup: put your VFX at
--   ReplicatedStorage/DrinkSystem/VFX/Bee Swarm
-- Works whether "Bee Swarm" is a ParticleEmitter, a BasePart, or a Model —
-- the code adapts to whichever one it finds and moves it every frame.
--
-- Everything spawned here is a real Instance parented to workspace, so it
-- replicates to every nearby player automatically — no extra client script
-- needed just to make others see it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystem:WaitForChild("Config")
local Settings = require(ConfigFolder:WaitForChild("Settings"))

local DrinkEffectsService = require(script.Parent:WaitForChild("DrinkEffectsService"))

local BeeSwarmService = {}

local VFX_FOLDER_NAME = "VFX"
local VFX_ITEM_NAME = "Bee Swarm"

local ORBIT_RADIUS = 1.6   -- studs out from the torso
local ORBIT_SPEED = 3.6    -- rad/sec
local ORBIT_HEIGHT = 0.6   -- studs above the torso's own position
local BOB_SPEED = 5
local BOB_AMOUNT = 0.15    -- small vertical wobble so it doesn't look like a perfect circle

type ActiveState = {
	Conn: RBXScriptConnection,
	Cleanup: () -> (),
	AnimTrack: AnimationTrack?,
}

local active: { [Player]: ActiveState } = {}

local function findTemplate(): Instance?
	local vfxFolder = DrinkSystem:FindFirstChild(VFX_FOLDER_NAME)
	if not vfxFolder then
		return nil
	end
	return vfxFolder:FindFirstChild(VFX_ITEM_NAME)
end

-- Clones the template and returns a mover function + cleanup, adapting to
-- whatever type the template is so Studio setup stays flexible.
local function spawnMovable(template: Instance): (((Vector3) -> ())?, (() -> ())?)
	local clone = template:Clone()

	if clone:IsA("Model") then
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
			end
		end
		clone.Parent = workspace
		return function(pos: Vector3)
			clone:PivotTo(CFrame.new(pos))
		end, function()
			clone:Destroy()
		end
	elseif clone:IsA("BasePart") then
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanQuery = false
		clone.Parent = workspace
		return function(pos: Vector3)
			clone.CFrame = CFrame.new(pos)
		end, function()
			clone:Destroy()
		end
	elseif clone:IsA("ParticleEmitter") then
		local carrier = Instance.new("Part")
		carrier.Name = "DS_BeeSwarmCarrier"
		carrier.Size = Vector3.new(0.2, 0.2, 0.2)
		carrier.Transparency = 1
		carrier.Anchored = true
		carrier.CanCollide = false
		carrier.CanQuery = false
		carrier.Parent = workspace
		clone.Parent = carrier
		return function(pos: Vector3)
			carrier.CFrame = CFrame.new(pos)
		end, function()
			carrier:Destroy() -- destroys the cloned emitter with it
		end
	end

	clone:Destroy()
	return nil, nil
end

function BeeSwarmService.IsActive(player: Player): boolean
	return active[player] ~= nil
end

function BeeSwarmService.Stop(player: Player)
	local state = active[player]
	if not state then
		return
	end
	active[player] = nil
	state.Conn:Disconnect()
	if state.AnimTrack then
		state.AnimTrack:Stop(0.2)
	end
	state.Cleanup()
end

function BeeSwarmService.Start(player: Player, duration: number?)
	if active[player] then
		return -- already buzzing, don't stack
	end
	local char = player.Character
	if not char then
		return
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local anchor = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
	if not anchor then
		return
	end

	local template = findTemplate()
	if not template then
		warn(("[BeeSwarmService] No VFX found at ReplicatedStorage.DrinkSystem.%s.%s"):format(VFX_FOLDER_NAME, VFX_ITEM_NAME))
		return
	end

	local move, cleanup = spawnMovable(template)
	if not move or not cleanup then
		warn("[BeeSwarmService] 'Bee Swarm' VFX must be a ParticleEmitter, BasePart, or Model")
		return
	end

	DrinkEffectsService.playCharacterSound(player, Settings.BeeSwarmSoundId, Settings.BeeSwarmSoundVolume or 0.5)

	local animTrack: AnimationTrack? = nil
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator and Settings.BeeSwarmAnimationId then
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. tostring(Settings.BeeSwarmAnimationId)
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if ok and track then
			track.Looped = true
			track:Play()
			animTrack = track
		end
	end

	local dur = duration or 7
	local expiresAt = os.clock() + dur
	local startClock = os.clock()
	local baseAngle = math.random() * math.pi * 2 -- so back-to-back triggers don't look identical

	local conn = RunService.Heartbeat:Connect(function()
		if not anchor.Parent or not humanoid.Parent then
			BeeSwarmService.Stop(player)
			return
		end
		local t = os.clock() - startClock
		local angle = baseAngle + t * ORBIT_SPEED
		local bob = math.sin(t * BOB_SPEED) * BOB_AMOUNT
		local pos = anchor.Position + Vector3.new(
			math.cos(angle) * ORBIT_RADIUS,
			ORBIT_HEIGHT + bob,
			math.sin(angle) * ORBIT_RADIUS
		)
		move(pos)
		if os.clock() >= expiresAt then
			BeeSwarmService.Stop(player)
		end
	end)

	active[player] = { Conn = conn, Cleanup = cleanup, AnimTrack = animTrack }
end

function BeeSwarmService.init()
	Players.PlayerRemoving:Connect(BeeSwarmService.Stop)
end

return BeeSwarmService
