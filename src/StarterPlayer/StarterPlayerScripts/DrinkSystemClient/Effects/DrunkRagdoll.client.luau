local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player      = Players.LocalPlayer
local camera      = workspace.CurrentCamera
local applyEvent  = ReplicatedStorage:WaitForChild("DS_DrunkApplyEvent", 30) :: RemoteEvent

local function screenShake()
	local shakeConn: RBXScriptConnection
	local elapsed  = 0
	local duration = 0.4
	local magnitude = 0.12
	shakeConn = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local progress = elapsed / duration
		if progress >= 1 then
			shakeConn:Disconnect()
			return
		end
		local decay = 1 - progress
		local ox = (math.random() * 2 - 1) * magnitude * decay
		local oy = (math.random() * 2 - 1) * magnitude * decay
		camera.CFrame = camera.CFrame * CFrame.new(ox, oy, 0)
	end)
end

local SHUFFLE_SPEED = 7  -- ragdoll crawl speed (was 16 — "too fast" per playtests)
local shuffleConn: RBXScriptConnection? = nil
local shuffleVel: LinearVelocity? = nil
local shuffleAttachment: Attachment? = nil

local function stopClientAnims()
	local character = player.Character
	if not character then return end
	local humanoid  = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local animator  = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	for _, track in animator:GetPlayingAnimationTracks() do track:Stop(0) end
end

local function startShuffle(hrp: BasePart, humanoid: Humanoid, character: Model)
	-- LinearVelocity actuator (BodyVelocity is deprecated). Plane mode with a
	-- world-space XZ plane: it only drives horizontal crawl velocity, leaving
	-- Y fully to gravity/physics — same behavior BodyVelocity gave with
	-- MaxForce.Y = 0, but on the supported constraint.
	local attachment = Instance.new("Attachment")
	attachment.Name = "DS_ShuffleAttachment"
	attachment.Parent = hrp
	shuffleAttachment = attachment

	local bv = Instance.new("LinearVelocity")
	bv.Name = "DS_ShuffleVelocity"
	bv.Attachment0 = attachment
	bv.RelativeTo = Enum.ActuatorRelativeTo.World
	bv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	bv.PrimaryTangentAxis = Vector3.xAxis
	bv.SecondaryTangentAxis = Vector3.zAxis
	bv.PlaneVelocity = Vector2.zero
	bv.MaxForce = 1e4
	bv.Parent = hrp
	shuffleVel = bv

	shuffleConn = RunService.Heartbeat:Connect(function(dt)
		if not bv.Parent then return end

		for _, desc in character:GetDescendants() do
			if desc:IsA("BasePart") and not desc.Parent:IsA("Accessory") and desc.Name ~= "HumanoidRootPart" then
				if not desc.CanCollide then desc.CanCollide = true end
			end
		end

		local dir = humanoid.MoveDirection
		if dir.Magnitude > 0.1 then
			bv.PlaneVelocity = Vector2.new(dir.X, dir.Z) * SHUFFLE_SPEED
			hrp.AssemblyAngularVelocity = Vector3.new(0, math.sin(time() * 1.5) * 3, 0)
		else
			bv.PlaneVelocity = Vector2.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
		end
	end)
end

local function stopShuffle()
	if shuffleConn then shuffleConn:Disconnect(); shuffleConn = nil end
	if shuffleVel and shuffleVel.Parent then shuffleVel:Destroy() end
	shuffleVel = nil
	if shuffleAttachment and shuffleAttachment.Parent then shuffleAttachment:Destroy() end
	shuffleAttachment = nil
	-- Sweep for ANY leftover velocity actuator on the root — a survivor here
	-- keeps pushing the character and causes the post-ragdoll sliding.
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp then
		for _, child in ipairs(hrp:GetChildren()) do
			if child:IsA("LinearVelocity") or child:IsA("BodyVelocity")
				or (child:IsA("Attachment") and child.Name == "DS_ShuffleAttachment") then
				child:Destroy()
			end
		end
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end
end

-- Chat bubbles follow the DS_BubbleAnchor part in each character (created by
-- DrunkRagdollService). Normally it's welded at the head; while a player is
-- ragdolled the server floats THEIR anchor above the body — so only ragdolled
-- players' bubbles are lifted, everyone else's stay exactly stock.
do
	local TextChatService = game:GetService("TextChatService")
	local bubbleConfig = TextChatService:FindFirstChildOfClass("BubbleChatConfiguration")
	if bubbleConfig then
		bubbleConfig.AdorneeName = "DS_BubbleAnchor"
	end
end

-- Respawn safety: never carry shuffle state into a fresh character
player.CharacterAdded:Connect(function()
	if shuffleConn then shuffleConn:Disconnect(); shuffleConn = nil end
	shuffleVel = nil
	shuffleAttachment = nil
end)

applyEvent.OnClientEvent:Connect(function(isRagdolling: boolean)
	local character = player.Character
	if not character then return end
	local humanoid  = character:FindFirstChildOfClass("Humanoid")
	local hrp       = character:FindFirstChild("HumanoidRootPart") :: BasePart

	if isRagdolling then
		stopClientAnims()
		screenShake()
		local upperTorso = character:FindFirstChild("UpperTorso")
		if upperTorso then
			camera.CameraSubject = upperTorso
			upperTorso:ApplyAngularImpulse(upperTorso.CFrame.LookVector * 60)
		end
		if hrp and humanoid then startShuffle(hrp, humanoid, character) end
	else
		stopShuffle()
		for _, desc in character:GetDescendants() do
			if desc:IsA("BasePart") and not desc.Parent:IsA("Accessory") and desc.Name ~= "HumanoidRootPart" then
				desc.CanCollide = false
			end
		end
		if humanoid then camera.CameraSubject = humanoid end
	end
end)
