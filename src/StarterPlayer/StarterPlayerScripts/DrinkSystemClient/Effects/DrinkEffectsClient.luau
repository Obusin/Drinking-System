-- Client-side drink effects (visuals only)

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystem:WaitForChild("Config")
local Settings = require(ConfigFolder:WaitForChild("Settings"))

local DrinkEffectsClient = {}
DrinkEffectsClient.__index = DrinkEffectsClient

local function getOrCreateEffect(name: string, className: string)
	local existing = Lighting:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

function DrinkEffectsClient.new(player: Player, maxDrunkness: number)
	local self = setmetatable({}, DrinkEffectsClient)
	self.Player = player
	self.MaxDrunkness = maxDrunkness
	self.VisualMaxDrunkness = Settings.DrunknessVisualMax or math.max(8, math.floor(maxDrunkness * 0.15))
	self.VisualRisePerSecond = Settings.DrunknessVisualRisePerSecond or 4.5
	self.VisualFallPerSecond = Settings.DrunknessVisualFallPerSecond or 1.5
	self.LastOffset = CFrame.new()
	self.LastFovOffset = 0
	self.WobbleSpeed = 1.55
	self.Intensity = Settings.DrunkEffectIntensity or 1
	self.DebugEnabled = Settings.EnableDrunkDebug == true
	self.DebugInterval = Settings.DrunkDebugInterval or 0.5
	self.LastDebugAt = 0
	self.LastDrunkness = 0
	self.DisplayDrunkness = 0
	self.SipKick = 0
	self.SipKickDecayPerSecond = 1.75
	self.NextHiccupAt = 0

	self.Blur = getOrCreateEffect("DS_DrunkBlur", "BlurEffect")
	self.Color = getOrCreateEffect("DS_DrunkColor", "ColorCorrectionEffect")
	self.DOF = getOrCreateEffect("DS_DrunkDOF", "DepthOfFieldEffect")
	self.Bloom = getOrCreateEffect("DS_DrunkBloom", "BloomEffect")
	self.SunRays = getOrCreateEffect("DS_DrunkSunRays", "SunRaysEffect")

	self.Blur.Size = 0
	self.Color.Saturation = 0
	self.Color.Contrast = 0
	self.Color.Brightness = 0
	self.Color.TintColor = Color3.fromRGB(255, 255, 255)
	self.DOF.Enabled = false
	self.Bloom.Enabled = true
	self.Bloom.Intensity = 0
	self.Bloom.Size = 0
	self.Bloom.Threshold = 1.2
	self.SunRays.Intensity = 0
	self.SunRays.Spread = 0
	self.DOF.FarIntensity = 0.2
	self.DOF.NearIntensity = 0.4
	self.DOF.FocusDistance = 12

	return self
end

function DrinkEffectsClient:_getDrunkness(): number
	local val = self.Player:FindFirstChild("Drunkness")
	return val and val.Value or 0
end

function DrinkEffectsClient:_getMoveAlpha(): number
	local val = self.Player:FindFirstChild("DrunkMoveAlpha")
	return val and val.Value or 0
end

function DrinkEffectsClient:_isCollapsed(): boolean
	local val = self.Player:FindFirstChild("DrunkCollapsed")
	return val and val.Value == true or false
end

function DrinkEffectsClient:_playHiccup()
	local soundId = Settings.DrunkHiccupSoundId
	if typeof(soundId) ~= "number" and typeof(soundId) ~= "string" then
		return
	end

	local character = self.Player.Character
	local parentPart = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. tostring(soundId)
	sound.Volume = 0.65
	sound.PlaybackSpeed = 0.94 + math.random() * 0.16
	sound.Parent = parentPart or SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

function DrinkEffectsClient:_resetCamera()
	local cam = workspace.CurrentCamera
	if not cam then return end
	if self.LastOffset ~= CFrame.new() then
		cam.CFrame = cam.CFrame * self.LastOffset:Inverse()
		self.LastOffset = CFrame.new()
	end
	if self.LastFovOffset ~= 0 then
		cam.FieldOfView -= self.LastFovOffset
		self.LastFovOffset = 0
	end
end

function DrinkEffectsClient:Update(dt: number)
	local cam = workspace.CurrentCamera
	if not cam then return end

	local drunkness = self:_getDrunkness()
	local delta = drunkness - self.LastDrunkness
	if delta > 0 then
		-- Consume pulse: extra wobble kick right after a successful drink.
		local kick = math.clamp(delta / math.max(self.VisualMaxDrunkness, 1), 0.12, 0.4)
		self.SipKick = math.clamp(self.SipKick + kick, 0, 0.55)
		if self.DebugEnabled then
			print("[DrinkSystem][DrinkDetected]", "Delta=", delta, "SipKick=", self.SipKick, "Drunkness=", drunkness)
		end
	end
	self.LastDrunkness = drunkness
	self.SipKick = math.max(0, self.SipKick - (self.SipKickDecayPerSecond * dt))

	if self.DisplayDrunkness < drunkness then
		self.DisplayDrunkness = math.min(drunkness, self.DisplayDrunkness + (self.VisualRisePerSecond * dt))
	else
		self.DisplayDrunkness = math.max(drunkness, self.DisplayDrunkness - (self.VisualFallPerSecond * dt))
	end

	local t = math.clamp(self.DisplayDrunkness / math.max(self.VisualMaxDrunkness, 1), 0, 1)
	local effectiveT = math.clamp(t + self.SipKick, 0, 1.35)

	if t <= 0 and self.SipKick <= 0 then
		self:_resetCamera()
		self.Blur.Size = 0
		self.Color.Saturation = 0
		self.Color.Contrast = 0
		self.Color.Brightness = 0
		self.Color.TintColor = Color3.fromRGB(255, 255, 255)
		self.DOF.Enabled = false
		self.Bloom.Intensity = 0
		self.Bloom.Size = 0
		self.SunRays.Intensity = 0
		self.SunRays.Spread = 0
		return
	end

	local time = os.clock()
	local moveAlpha = self:_getMoveAlpha()
	local collapsed = self:_isCollapsed()
	local distortionBoost = math.clamp(moveAlpha * 0.65 + (collapsed and 0.4 or 0), 0, 1)
	local amp = (0.022 + (0.056 * effectiveT) + (0.038 * distortionBoost)) * self.Intensity
	local roll = (0.018 + (0.07 * effectiveT) + (0.026 * distortionBoost)) * self.Intensity
	local yaw = (0.007 + (0.028 * effectiveT)) * self.Intensity
	local fovOffset = 0

	local offset = CFrame.new(
		(math.sin(time * self.WobbleSpeed) + math.sin(time * self.WobbleSpeed * 1.7) * 0.3) * amp,
		(math.sin(time * self.WobbleSpeed * 0.75) + math.cos(time * self.WobbleSpeed * 1.2) * 0.18) * amp * 0.9,
		0
	) * CFrame.Angles(
		0,
		math.sin(time * self.WobbleSpeed * 0.45) * yaw,
		math.sin(time * self.WobbleSpeed * 0.9) * roll
	)

	cam.CFrame = cam.CFrame * self.LastOffset:Inverse() * offset
	self.LastOffset = offset
	cam.FieldOfView = cam.FieldOfView - self.LastFovOffset + fovOffset
	self.LastFovOffset = fovOffset

	self.Blur.Size = math.min(8, (0.7 + (2.35 * effectiveT) + (0.9 * distortionBoost)) * self.Intensity)
	self.Color.Saturation = 0
	self.Color.Contrast = 0
	self.Color.Brightness = 0
	self.Color.TintColor = Color3.fromRGB(255, 255, 255)
	self.DOF.Enabled = false
	self.Bloom.Intensity = 0
	self.Bloom.Size = 0
	self.SunRays.Intensity = 0
	self.SunRays.Spread = 0

	if effectiveT >= 0.25 and time >= self.NextHiccupAt then
		self:_playHiccup()
		self.SipKick = math.clamp(self.SipKick + 0.08, 0, 0.55)
		local baseInterval = 10 - (5.5 * math.min(effectiveT, 1))
		local jitter = -0.85 + (math.random() * 2.2)
		self.NextHiccupAt = time + math.max(2.4, baseInterval + jitter)
	end

	if self.DebugEnabled and (time - self.LastDebugAt) >= self.DebugInterval then
		self.LastDebugAt = time
		print(
			"[DrinkSystem][DrunknessFX]",
			"Drunkness=", drunkness,
			"DisplayDrunkness=", self.DisplayDrunkness,
			"Normalized=", t,
			"Effective=", effectiveT,
			"SipKick=", self.SipKick,
			"Blur=", self.Blur.Size,
			"Intensity=", self.Intensity
		)
	end
end

function DrinkEffectsClient:Start()
	if self.Connection then return end
	self.Connection = RunService.RenderStepped:Connect(function(dt)
		self:Update(dt)
	end)
end

function DrinkEffectsClient:Stop()
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
	self:_resetCamera()
end

return DrinkEffectsClient
