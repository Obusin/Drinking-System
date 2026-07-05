local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")

local player      = Players.LocalPlayer
local camera      = workspace.CurrentCamera
local ragdollEvent = ReplicatedStorage:WaitForChild("DS_DrunkRagdollEvent", 30) :: RemoteEvent
local applyEvent   = ReplicatedStorage:WaitForChild("DS_DrunkApplyEvent",   30) :: RemoteEvent

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

local SHUFFLE_SPEED = 16
local shuffleConn: RBXScriptConnection? = nil
local bodyVel: BodyVelocity? = nil

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
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e4, 0, 1e4)
	bv.Velocity = Vector3.zero
	bv.Parent   = hrp
	bodyVel = bv

	shuffleConn = RunService.Heartbeat:Connect(function(dt)
		if not bv.Parent then return end

		for _, desc in character:GetDescendants() do
			if desc:IsA("BasePart") and not desc.Parent:IsA("Accessory") and desc.Name ~= "HumanoidRootPart" then
				if not desc.CanCollide then desc.CanCollide = true end
			end
		end

		local dir = humanoid.MoveDirection
		if dir.Magnitude > 0.1 then
			bv.Velocity = dir * SHUFFLE_SPEED
			hrp.AssemblyAngularVelocity = Vector3.new(0, math.sin(time() * 1.5) * 3, 0)
		else
			bv.Velocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
		end
	end)
end

local function stopShuffle()
	if shuffleConn then shuffleConn:Disconnect(); shuffleConn = nil end
	if bodyVel and bodyVel.Parent then bodyVel:Destroy() end
	bodyVel = nil
end

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

-- E to test ragdoll toggle.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.E then ragdollEvent:FireServer() end
end)
