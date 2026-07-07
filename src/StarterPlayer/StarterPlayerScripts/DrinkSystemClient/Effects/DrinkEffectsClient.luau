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
	self.SmoothedMotionBoost   = 0  -- exp-smoothed so stepwise server values can't jolt the camera
	self.EffectFade            = 0  -- master fade 0→1, eases all effects in/out smoothly

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

-- (hiccup sound moved server-side — see DrinkEffectsService.playCharacterSound)

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
	-- Fall rate scales with the gap so big drops (death reset, Water) fade out
	-- in ~2s instead of crawling down at the natural-recovery pace.
	if self.DisplayDrunkness < drunkness then
		self.DisplayDrunkness = math.min(drunkness, self.DisplayDrunkness + self.VisualRisePerSecond * dt)
	else
		local gap = self.DisplayDrunkness - drunkness
		local fallRate = math.max(self.VisualFallPerSecond, gap * 0.6)
		self.DisplayDrunkness = math.max(drunkness, self.DisplayDrunkness - fallRate * dt)
	end

	local t = math.clamp(self.DisplayDrunkness / math.max(self.VisualMaxDrunkness, 1), 0, 1)

	-- Master fade: eases all effects in when drunkness starts and out when it
	-- ends, so effects never pop on/off — they always blend.
	local targetFade = (t > 0) and 1 or 0
	self.EffectFade += (targetFade - self.EffectFade) * math.min(dt * 1.5, 1)

	if t <= 0 and self.EffectFade < 0.02 then
		self.EffectFade = 0
		self:_clearEffects()
		return
	end

	local effectiveT = t * self.EffectFade

	local time       = os.clock()
	local moveAlpha  = self:_getMoveAlpha()
	local collapsed  = self:_isCollapsed()

	-- Smooth motionBoost: the raw value comes from server-replicated steps and
	-- multiplies wobble amplitude — unsmoothed it jolts the camera on each update.
	local targetBoost = math.clamp(moveAlpha * 0.6 + (collapsed and 0.45 or 0), 0, 1)
	self.SmoothedMotionBoost += (targetBoost - self.SmoothedMotionBoost) * math.min(dt * 2.5, 1)
	local motionBoost = self.SmoothedMotionBoost

	-- ─── CAMERA WOBBLE ─────────────────────────────────────────────────────
	-- Amplitudes are deliberately punchy — you should FEEL every sip.
	-- Base constants are scaled by EffectFade so the wobble eases in from zero
	-- instead of popping to its floor amplitude on the first sip.
	local primaryAmp = (0.04 + 0.18 * effectiveT + 0.06 * motionBoost) * self.Intensity * self.EffectFade

	local ox = (math.sin(time * self.WobbleSpeed)              + math.sin(time * self.WobbleSpeed * 1.73) * 0.42) * primaryAmp
	local oy = (math.sin(time * self.WobbleSpeed * 0.77)       + math.cos(time * self.WobbleSpeed * 1.19) * 0.28) * primaryAmp * 0.9

	local roll = (0.03 + 0.16 * effectiveT + 0.05 * motionBoost) * self.Intensity * self.EffectFade
	local yaw  = (0.01 + 0.06 * effectiveT)                       * self.Intensity * self.EffectFade

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
	-- Ambient blur stays SUBTLE — the heavy lifting is the depth-of-field below,
	-- which keeps the avatar and nearby surroundings sharp and blurs only the
	-- distance. A slow pulse gives it waves-of-dizziness variance.
	local blurPulse = 0.65
		+ 0.28 * (0.5 + 0.5 * math.sin(time * 0.85))
		+ 0.07 * (0.5 + 0.5 * math.sin(time * 2.1 + 1.3))
	local blurBase = math.min(5.5, (0.4 + 2.4 * effectiveT + 0.8 * motionBoost) * self.Intensity)
	self.Blur.Size = blurBase * blurPulse * self.EffectFade

	-- ─── AUDIO MUFFLE ──────────────────────────────────────────────────────
	-- Cuts highs up to -12dB and mids up to -5dB. Subtle at low drunkness,
	-- noticeably muffled when wasted. Kicks in after 20% drunk.
	local muffleAlpha = math.clamp((effectiveT - 0.2) / 0.8, 0, 1)
	self.EQ.HighGain  = -12 * muffleAlpha
	self.EQ.MidGain   = -5  * muffleAlpha

	-- ─── DEPTH OF FIELD ────────────────────────────────────────────────────
	-- Focus is LOCKED on the character: the avatar and nearby surroundings stay
	-- sharp, only the distance blurs. The sharp bubble shrinks as drunkness
	-- rises and pulses slowly so the blur washes in and out.
	if effectiveT > 0.1 then
		local dofAlpha = math.clamp((effectiveT - 0.1) / 0.9, 0, 1)

		-- Focus at the character so the avatar is always crisp
		local char = self.Player.Character
		local focusPart = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
		local focusDist = 10
		if focusPart then
			focusDist = (cam.CFrame.Position - focusPart.Position).Magnitude
		end

		-- Sharp bubble around the player: ~20 studs sober-ish → ~8 wasted,
		-- pulsing ±3 so the blur breathes at the edges (~6s cycle).
		local inFocusRadius = 20 - 12 * dofAlpha
		inFocusRadius += math.sin(time * 0.55 + 0.9) * (3 * dofAlpha)
		inFocusRadius = math.max(6, inFocusRadius)

		self.DOF.Enabled       = true
		self.DOF.FocusDistance = focusDist
		self.DOF.InFocusRadius = inFocusRadius
		-- Far blur strong, near blur very light so the avatar never smears
		self.DOF.FarIntensity  = math.clamp(0.35 + 0.6 * dofAlpha, 0, 1) * self.EffectFade
		self.DOF.NearIntensity = math.clamp(0.05 + 0.15 * dofAlpha, 0, 0.3) * self.EffectFade
	else
		self.DOF.Enabled = false
	end

	-- Hiccups are played SERVER-side (DrinkEffectsService) so nearby players
	-- hear them spatially — no local hiccup here anymore.

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
