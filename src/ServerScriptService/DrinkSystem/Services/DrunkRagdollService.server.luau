local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local applyEvent = Instance.new("RemoteEvent")
applyEvent.Name   = "DS_DrunkApplyEvent"
applyEvent.Parent = ReplicatedStorage

---------------------------------------------------------------------
-- Chat bubble anchor: clients point BubbleChat at this named part
-- (AdorneeName). Normally welded at the head; while ragdolled the server
-- floats it above the body so bubbles never sink into the floor.
---------------------------------------------------------------------
local BUBBLE_ANCHOR_NAME = "DS_BubbleAnchor"
local bubbleFollow: { [Player]: RBXScriptConnection } = {}

local function ensureBubbleAnchor(character: Model): BasePart?
	local existing = character:FindFirstChild(BUBBLE_ANCHOR_NAME)
	if existing and existing:IsA("BasePart") then return existing end
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not head then return nil end

	local anchor = Instance.new("Part")
	anchor.Name = BUBBLE_ANCHOR_NAME
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Massless = true
	anchor.CFrame = head.CFrame
	anchor.Parent = character

	local weld = Instance.new("WeldConstraint")
	weld.Name = "DS_BubbleWeld"
	weld.Part0 = anchor
	weld.Part1 = head
	weld.Parent = anchor
	return anchor
end

local function setBubbleAnchorRagdolled(player: Player, character: Model, ragdolled: boolean)
	local anchor = ensureBubbleAnchor(character)
	if not anchor then return end
	local old = bubbleFollow[player]
	if old then old:Disconnect(); bubbleFollow[player] = nil end

	if ragdolled then
		-- Float above the body: unweld, anchor, and track the torso each frame
		local weld = anchor:FindFirstChild("DS_BubbleWeld")
		if weld then weld:Destroy() end
		anchor.Anchored = true
		bubbleFollow[player] = RunService.Heartbeat:Connect(function()
			local torso = character:FindFirstChild("UpperTorso")
				or character:FindFirstChild("Torso")
				or character:FindFirstChild("Head")
			if torso then
				anchor.CFrame = CFrame.new(torso.Position + Vector3.new(0, 1.5, 0))
			end
		end)
	else
		-- Back to the head
		anchor.Anchored = false
		local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
		if head then
			anchor.CFrame = head.CFrame
			if not anchor:FindFirstChild("DS_BubbleWeld") then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "DS_BubbleWeld"
				weld.Part0 = anchor
				weld.Part1 = head
				weld.Parent = anchor
			end
		end
	end
end

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
	setBubbleAnchorRagdolled(player, character, true)

	applyEvent:FireClient(player, true)
end

local function ragdollOff(player: Player, character: Model, humanoid: Humanoid)
	local state = saved[player]
	saved[player] = nil

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if hrp then
		hrp.Anchored = true
		-- Stand up ON the actual floor: after flopping on uneven ground the
		-- HRP is often half-inside a slope — unanchoring from there makes
		-- physics eject the character (stuck/sliding). Raycast down and place
		-- the root at proper standing height above the hit.
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local hit = workspace:Raycast(hrp.Position + Vector3.new(0, 6, 0), Vector3.new(0, -60, 0), params)
		local standY = hit and (hit.Position.Y + 3) or (hrp.Position.Y + 2.5)
		hrp.CFrame = CFrame.new(hrp.Position.X, standY, hrp.Position.Z)
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

	-- Kill residual physics energy — leftover assembly velocities are what
	-- makes players slide across the floor after standing back up.
	local function zeroVelocities()
		for _, desc in character:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.AssemblyLinearVelocity = Vector3.zero
				desc.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
	zeroVelocities()

	task.wait(0.1)
	if hrp then hrp.Anchored = false end
	zeroVelocities()

	humanoid.AutoRotate    = true
	humanoid.PlatformStand = false
	humanoid.WalkSpeed     = state and state.walkSpeed or 16
	humanoid.JumpPower     = state and state.jumpPower or 50
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	setBubbleAnchorRagdolled(player, character, false)
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
		local follow = bubbleFollow[player]
		if follow then follow:Disconnect(); bubbleFollow[player] = nil end
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		character:WaitForChild("Head", 10)
		ensureBubbleAnchor(character)
		humanoid.Died:Connect(function()
			saved[player] = nil
			isRagdolled.value = false
		end)
	end)
	if player.Character then
		ensureBubbleAnchor(player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, plr in ipairs(Players:GetPlayers()) do
	onPlayerAdded(plr)
end

Players.PlayerRemoving:Connect(function(player)
	saved[player] = nil
	local follow = bubbleFollow[player]
	if follow then follow:Disconnect(); bubbleFollow[player] = nil end
end)
