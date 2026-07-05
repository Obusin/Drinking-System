-- Client-side drink effects (visuals only — no ragdoll, handled separately)

local Lighting      = game:GetService("Lighting")
local RunService    = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService  = game:GetService("SoundService")

local DrinkSystem   = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder  = DrinkSystem:WaitForChild("Config")
local Settings      = require(ConfigFolder:WaitForChild("Settings"))

local DrinkEffectsClient = {}
DrinkEffectsClient.__index = DrinkEffectsClient

local function getOrCreateEffect(name: string, className: string)
	local existing = Lighting:FindFirstChild(name)
	if existing and existing:IsA(className) then return existing end
	if existing then existing:Destroy() end
	local inst = Instance.new(className)
	inst.Name   = name
	inst.Parent = Lighting
	return inst
end

function DrinkEffectsClient.new(player: Player, maxDrunkness: number)
	local self = setmetatable({}, DrinkEffectsClient)
	self.Player       = player
	self.MaxDrunkness = maxDrunkness

	-- VisualMaxDrunkness = drunkness value where effects hit full intensity.
	-- Set to 70 so you feel fully hammered well before the 100 cap.
	self.VisualMaxDrunkness    = Settings.DrunknessVisualMax             or 70
	self.VisualRisePerSecond   = Settings.DrunknessVisualRisePerSecond   or 12
	self.VisualFallPerSecond   = Settings.DrunknessVisualFallPerSecond   or 1.5
	self.WobbleSpeed           = 1.6
	self.Intensity             = Settings.DrunkEffectIntensity           or 1.25
	self.DebugEnabled          = Settings.EnableDrunkDebug               == true
	self.DebugInterval         = Settings.DrunkDebugInterval             or 0.5
	self.LastDebugAt           = 0
	self.DisplayDrunkness      = 0

	self.NextHiccupAt          = 0
	self.LastOffset            = CFrame.new()
	self.LastFovOffset         = 0

	self.Blur = getOrCreateEffect("DS_DrunkBlur", "BlurEffect")
	self.DOF  = getOrCreateEffect("DS_DrunkDOF",  "DepthOfFieldEffect")

	self.Blur.Size        = 0
	self.DOF.Enabled      = false

	-- Audio muffle: reduce highs and mids the drunker you get
	local eq = SoundService:FindFirstChild("DS_DrunkEQ")
	if not eq or not eq:IsA("EqualizerSoundEffect") then
		if eq then eq:Destroy() end
		eq = Instance.new("EqualizerSoundEffect")
		eq.Name      = "DS_DrunkEQ"
		eq.HighGain  = 0
		eq.MidGain   = 0
		eq.LowGain   = 0
		eq.Parent    = SoundService
	end
	self.EQ = eq
	self.DOF.FarIntensity = 0
	self.DOF.NearIntensity= 0
	self.DOF.FocusDistance= 12
	self.DOF.InFocusRadius= 8

	-- Remove any leftover effects from old sessions.
	for _, name in { "DS_DrunkColor", "DS_DrunkBloom", "DS_DrunkSunRays" } do
		local e = Lighting:FindFirstChild(name)
		if e then e:Destroy() end
	end
	local gui = player:FindFirstChild("PlayerGui")
	if gui then
		local vig = gui:FindFirstChild("DS_DrunkVignette")
		if vig then vig:Destroy() end
	end

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
	if not soundId then return end
	local character  = self.Player.Character
	local parentPart = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	local sound = Instance.new("Sound")
	sound.SoundId       = "rbxassetid://" .. tostring(soundId)
	sound.Volume        = 0.7
	sound.PlaybackSpeed = 0.92 + math.random() * 0.18
	sound.Parent        = parentPart or SoundService
	sound:Play()
	sound.Ended:Once(function() sound:Destroy() end)
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

function DrinkEffectsClient:_clearEffects()
	self:_resetCamera()
	self.Blur.Size   = 0
	self.DOF.Enabled = false
	self.EQ.HighGain = 0
	self.EQ.MidGain  = 0
end

function DrinkEffectsClient:Update(dt: number)
	local cam = workspace.CurrentCamera
	if not cam then return end

	local drunkness = self:_getDrunkness()

	-- DisplayDrunkness: gradual rise and slow fall — no instant spikes on sip.
	if self.DisplayDrunkness < drunkness then
		self.DisplayDrunkness = math.min(drunkness, self.DisplayDrunkness + self.VisualRisePerSecond * dt)
	else
		self.DisplayDrunkness = math.max(drunkness, self.DisplayDrunkness - self.VisualFallPerSecond * dt)
	end

	local t          = math.clamp(self.DisplayDrunkness / math.max(self.VisualMaxDrunkness, 1), 0, 1)
	local effectiveT = t

	if t <= 0 then
		self:_clearEffects()
		return
	end

	local time       = os.clock()
	local moveAlpha  = self:_getMoveAlpha()
	local collapsed  = self:_isCollapsed()
	local motionBoost = math.clamp(moveAlpha * 0.6 + (collapsed and 0.45 or 0), 0, 1)

	-- ─── CAMERA WOBBLE ─────────────────────────────────────────────────────
	-- Amplitudes are deliberately punchy — you should FEEL every sip.
	local primaryAmp = (0.04 + 0.18 * effectiveT + 0.06 * motionBoost) * self.Intensity

	local ox = (math.sin(time * self.WobbleSpeed)              + math.sin(time * self.WobbleSpeed * 1.73) * 0.42) * primaryAmp
	local oy = (math.sin(time * self.WobbleSpeed * 0.77)       + math.cos(time * self.WobbleSpeed * 1.19) * 0.28) * primaryAmp * 0.9

	local roll = (0.03 + 0.16 * effectiveT + 0.05 * motionBoost) * self.Intensity
	local yaw  = (0.01 + 0.06 * effectiveT)                       * self.Intensity

	local offset = CFrame.new(ox, oy, 0) * CFrame.Angles(
		0,
		math.sin(time * self.WobbleSpeed * 0.47) * yaw,
		math.sin(time * self.WobbleSpeed * 0.88) * roll
	)

	-- ─── FOV BREATHING ─────────────────────────────────────────────────────
	local fovOffset = 0
	if effectiveT > 0.2 then
		local breathAlpha = (effectiveT - 0.2) / 0.8
		fovOffset = math.sin(time * 0.55) * (6 * breathAlpha * self.Intensity)
	end

	cam.CFrame      = cam.CFrame * self.LastOffset:Inverse() * offset
	self.LastOffset = offset
	cam.FieldOfView = cam.FieldOfView - self.LastFovOffset + fovOffset
	self.LastFovOffset = fovOffset

	-- ─── BLUR ──────────────────────────────────────────────────────────────
	self.Blur.Size = math.min(14, (1.5 + 7 * effectiveT + 2.5 * motionBoost) * self.Intensity)

	-- ─── AUDIO MUFFLE ──────────────────────────────────────────────────────
	-- Cuts highs up to -12dB and mids up to -5dB. Subtle at low drunkness,
	-- noticeably muffled when wasted. Kicks in after 20% drunk.
	local muffleAlpha = math.clamp((effectiveT - 0.2) / 0.8, 0, 1)
	self.EQ.HighGain  = -12 * muffleAlpha
	self.EQ.MidGain   = -5  * muffleAlpha

	-- ─── DEPTH OF FIELD ────────────────────────────────────────────────────
	-- Two slow, out-of-phase oscillators drive focus distance so it drifts
	-- between near and far in an irregular, swimmy way.
	-- InFocusRadius narrows as drunkness rises so the sharp band gets thin —
	-- like your drunk eyes can't agree on what to focus on.
	if effectiveT > 0.15 then
		local dofAlpha = math.clamp((effectiveT - 0.15) / 0.85, 0, 1)

		-- Primary focus drift: lazy near↔far swing (~7s cycle)
		local focusSwing = math.sin(time * 0.28) * (5 * dofAlpha)
		-- Secondary drift: slightly faster, smaller amplitude (~4.5s cycle), out of phase
		local focusDrift = math.sin(time * 0.45 + 1.8) * (2.5 * dofAlpha)
		local focusDist  = math.clamp(10 + focusSwing + focusDrift, 2, 24)

		-- Sharp band: wide when sober-ish, narrow when wasted (0.5→6 studs wide)
		local inFocusRadius = math.max(0.5, 6 - 5.5 * dofAlpha)
		-- Add a small pulse to the radius so it breathes (~3s cycle)
		inFocusRadius = inFocusRadius + math.sin(time * 0.65 + 0.9) * (1.2 * dofAlpha)
		inFocusRadius = math.max(0.5, inFocusRadius)

		self.DOF.Enabled       = true
		self.DOF.FocusDistance = focusDist
		self.DOF.InFocusRadius = inFocusRadius
		self.DOF.FarIntensity  = math.clamp(0.3 + 0.65 * dofAlpha, 0, 1)
		self.DOF.NearIntensity = math.clamp(0.2 + 0.55 * dofAlpha, 0, 1)
	else
		self.DOF.Enabled = false
	end

	-- ─── HICCUP ────────────────────────────────────────────────────────────
	if effectiveT >= 0.20 and time >= self.NextHiccupAt then
		self:_playHiccup()
		local baseInterval = 9 - 5 * math.min(effectiveT, 1)
		self.NextHiccupAt = time + math.max(2, baseInterval + (-1 + math.random() * 2.4))
	end

	if self.DebugEnabled and (time - self.LastDebugAt) >= self.DebugInterval then
		self.LastDebugAt = time
		print(
			"[DrinkSystem][FX]",
			"d=", math.floor(drunkness + 0.5),
			"t=", string.format("%.2f", t),
			"eff=", string.format("%.2f", effectiveT),
			"blur=", string.format("%.1f", self.Blur.Size)
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
	self:_clearEffects()
end

return DrinkEffectsClient
