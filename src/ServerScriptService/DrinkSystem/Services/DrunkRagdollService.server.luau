local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local applyEvent = Instance.new("RemoteEvent")
applyEvent.Name   = "DS_DrunkApplyEvent"
applyEvent.Parent = ReplicatedStorage

type SavedState = {
	balls:     { BallSocketConstraint },
	walkSpeed: number,
	jumpPower: number,
}
local saved: { [Player]: SavedState } = {}

local function ragdollOn(player: Player, character: Model, humanoid: Humanoid)
	local balls = {}

	for _, desc in character:GetDescendants() do
		if desc:IsA("AnimationConstraint") and desc.Attachment0 and desc.Attachment1 then
			desc.Enabled = false
			local ball = Instance.new("BallSocketConstraint")
			ball.Attachment0   = desc.Attachment0
			ball.Attachment1   = desc.Attachment1
			ball.LimitsEnabled = false
			ball.Parent        = desc.Parent
			table.insert(balls, ball)
		end
	end

	saved[player] = {
		balls     = balls,
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
	}

	humanoid.AutoRotate    = false
	humanoid.WalkSpeed     = 16
	humanoid.JumpPower     = 0
	humanoid.PlatformStand = true
	-- Physics state makes the WHOLE body fall. Without it the humanoid keeps
	-- the root/torso balanced upright and only the limbs flop — reads as
	-- "standing but welded to the torso".
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	applyEvent:FireClient(player, true)
end

local function ragdollOff(player: Player, character: Model, humanoid: Humanoid)
	local state = saved[player]
	saved[player] = nil

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if hrp then
		hrp.Anchored = true
		hrp.CFrame   = CFrame.new(hrp.Position)
	end

	if state then
		for _, ball in state.balls do
			if ball and ball.Parent then ball:Destroy() end
		end
	end

	for _, desc in character:GetDescendants() do
		if desc:IsA("AnimationConstraint") then desc.Enabled = true end
	end

	applyEvent:FireClient(player, false)

	task.wait(0.1)
	if hrp then hrp.Anchored = false end

	humanoid.AutoRotate    = true
	humanoid.PlatformStand = false
	humanoid.WalkSpeed     = state and state.walkSpeed or 16
	humanoid.JumpPower     = state and state.jumpPower or 50
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
end

-- One set of hooks per PLAYER (not per character). Previous version hooked
-- Changed + OnServerEvent inside CharacterAdded, stacking a new connection
-- every respawn — collapse would then fire ragdollOn multiple times.
local function onPlayerAdded(player: Player)
	local isRagdolled = { value = false }

	-- Resolve character/humanoid live so the same hook works across respawns
	local function setRagdoll(collapsed: boolean)
		local character = player.Character
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end
		if collapsed and not isRagdolled.value then
			isRagdolled.value = true
			ragdollOn(player, character, humanoid)
		elseif not collapsed and isRagdolled.value then
			isRagdolled.value = false
			ragdollOff(player, character, humanoid)
		end
	end

	-- DrunkCollapsed lives on the player, created by DrinkEffectsService on first drink
	local function hookValue(val: BoolValue)
		val.Changed:Connect(setRagdoll)
	end

	local existing = player:FindFirstChild("DrunkCollapsed")
	if existing and existing:IsA("BoolValue") then
		hookValue(existing :: BoolValue)
	else
		local conn: RBXScriptConnection
		conn = player.ChildAdded:Connect(function(child)
			if child.Name == "DrunkCollapsed" and child:IsA("BoolValue") then
				conn:Disconnect()
				hookValue(child :: BoolValue)
			end
		end)
	end

	player.CharacterAdded:Connect(function(character: Model)
		isRagdolled.value = false
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid.Died:Connect(function()
			saved[player] = nil
			isRagdolled.value = false
		end)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, plr in ipairs(Players:GetPlayers()) do
	onPlayerAdded(plr)
end

Players.PlayerRemoving:Connect(function(player) saved[player] = nil end)
