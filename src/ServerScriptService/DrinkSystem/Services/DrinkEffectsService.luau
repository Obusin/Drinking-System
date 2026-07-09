local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local DrinkEffectsService = {}

type Config = {
	DrunknessMax: number?,
	DrunknessRecoveryPerSecond: number?,
	DrunkStageThresholds: { Buzzed: number?, Drunk: number?, Wasted: number? }?,
	DrunkCollapseThreshold: number?,
	DrunkCollapseDuration: number?,
	DrunkCollapseCooldown: number?,
	DrunkCollapseRecoveryRatio: number?,
	DrunkMovementMaxAlpha: number?,
	DrunkWalkSpeedMultipliers: { [string]: number }?,
	DrunkJumpPowerMultipliers: { [string]: number }?,
	DrunkStumbleThreshold: number?,
	DrunkStumbleChancePerSecondMin: number?,
	DrunkStumbleChancePerSecondMax: number?,
	DrunkStumbleDuration: number?,
	DrunkStumbleCooldown: number?,
	EnableDrunkDebug: boolean?,
}

type DrinkEffects = {
	Player: Player,
	MaxDrunkness: number,
	RecoveryPerSecond: number,
	DrunknessValue: NumberValue,
	StageValue: StringValue,
	MovementValue: NumberValue,
	CollapsedValue: BoolValue,
	Character: Model?,
	Humanoid: Humanoid?,
	BaseWalkSpeed: number,
	BaseJumpPower: number,
	CollapsedUntil: number,
	LastCollapseAt: number,
	LastStage: string,
	Apply: (self: DrinkEffects, amount: number) -> (),
	Tick: (self: DrinkEffects, dt: number, now: number) -> (),
	BindCharacter: (self: DrinkEffects, character: Model?) -> (),
	Destroy: (self: DrinkEffects) -> (),
}

local DrinkEffects = {}
DrinkEffects.__index = DrinkEffects

local states: { [Player]: DrinkEffects } = {}

local config: Config = {
	DrunknessMax               = 100,
	DrunknessRecoveryPerSecond = 0.15,
	DrunkStageThresholds = {
		Buzzed = 0.20,
		Drunk  = 0.45,
		Wasted = 0.72,
	},
	DrunkCollapseThreshold     = 0.92,
	DrunkCollapseDuration      = 5,
	DrunkCollapseCooldown      = 60,
	DrunkCollapseRecoveryRatio = 0.78,
	DrunkMovementMaxAlpha      = 1,
	DrunkWalkSpeedMultipliers = {
		Sober     = 1,
		Buzzed    = 0.92,
		Drunk     = 0.75,
		Wasted    = 0.50,
		Collapsed = 0,
	},
	DrunkJumpPowerMultipliers = {
		Sober     = 1,
		Buzzed    = 0.92,
		Drunk     = 0.72,
		Wasted    = 0.42,
		Collapsed = 0,
	},
	DrunkStumbleThreshold          = 0.72,
	DrunkStumbleChancePerSecondMin  = 0.12,
	DrunkStumbleChancePerSecondMax  = 0.45,
	DrunkStumbleDuration            = 2.2,
	DrunkStumbleCooldown            = 4,
	EnableDrunkDebug                = false,
}

local function getOrCreateValue<T>(player: Player, name: string, className: string, initialValue: T)
	local value = player:FindFirstChild(name)
	if value and value:IsA(className) then
		return value
	end
	if value then value:Destroy() end
	local created = Instance.new(className)
	created.Name   = name
	created.Value  = initialValue
	created.Parent = player
	return created
end

local function normalized(current: number, maxDrunkness: number): number
	return math.clamp(current / math.max(maxDrunkness, 1), 0, 1)
end

local function computeStage(current: number, maxDrunkness: number, collapsed: boolean): string
	if collapsed then return "Collapsed" end
	local t = normalized(current, maxDrunkness)
	local th = config.DrunkStageThresholds or {}
	if t >= (th.Wasted or 0.72) then return "Wasted" end
	if t >= (th.Drunk  or 0.45) then return "Drunk"  end
	if t >= (th.Buzzed or 0.20) then return "Buzzed" end
	return "Sober"
end

local function computeMovementAlpha(current: number, maxDrunkness: number, collapsed: boolean): number
	if collapsed then return 0 end
	local t = normalized(current, maxDrunkness)
	local th = config.DrunkStageThresholds or {}
	local startT = (th.Buzzed or 0.20) + (((th.Drunk or 0.45) - (th.Buzzed or 0.20)) * 0.3)
	local maxAlpha = config.DrunkMovementMaxAlpha or 1
	if t <= startT then return 0 end
	return math.clamp((t - startT) / math.max(1 - startT, 0.001), 0, 1) * maxAlpha
end

local function getWalkMultiplier(stage: string): number
	return (config.DrunkWalkSpeedMultipliers or {})[stage] or 1
end

local function getJumpMultiplier(stage: string): number
	return (config.DrunkJumpPowerMultipliers or {})[stage] or 1
end

local function setHumanoidJumpPower(humanoid: Humanoid, jumpPower: number)
	if humanoid.UseJumpPower then
		humanoid.JumpPower = jumpPower
	else
		humanoid.JumpHeight = math.max(0, jumpPower / 7.2)
	end
end

local function getHumanoidJumpPower(humanoid: Humanoid): number
	if humanoid.UseJumpPower then return humanoid.JumpPower end
	return humanoid.JumpHeight * 7.2
end

function DrinkEffects.new(player: Player): DrinkEffects
	local self = setmetatable({}, DrinkEffects)
	self.Player          = player
	self.MaxDrunkness    = config.DrunknessMax or 100
	self.RecoveryPerSecond = config.DrunknessRecoveryPerSecond or 0
	self.DrunknessValue  = getOrCreateValue(player, "Drunkness",      "NumberValue", 0)     :: NumberValue
	self.StageValue      = getOrCreateValue(player, "DrunkStage",     "StringValue", "Sober") :: StringValue
	self.MovementValue   = getOrCreateValue(player, "DrunkMoveAlpha", "NumberValue", 0)     :: NumberValue
	self.CollapsedValue  = getOrCreateValue(player, "DrunkCollapsed", "BoolValue",   false)  :: BoolValue
	self.Character       = nil
	self.Humanoid        = nil
	self.BaseWalkSpeed   = 16
	self.BaseJumpPower   = 50
	self.CollapsedUntil  = 0
	self.LastCollapseAt  = -math.huge
	self.LastStumbleAt   = -math.huge
	self.IsStumble       = false
	self.NextHiccupAt    = 0
	self.LastSipAt       = -math.huge  -- sober-grace: decay pauses after a sip
	self.LastStage       = "Sober"
	return self
end

function DrinkEffects:BindCharacter(character: Model?)
	self.Character = character
	self.Humanoid  = nil
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	self.Humanoid = humanoid
	-- Capture the base speed only while sober: if a drunk-stage tick touched
	-- this humanoid before binding, its CURRENT speed is already reduced and
	-- capturing it would make the reduction permanent.
	if self.StageValue.Value == "Sober" then
		self.BaseWalkSpeed = humanoid.WalkSpeed
		self.BaseJumpPower = getHumanoidJumpPower(humanoid)
	end
end

function DrinkEffects:Apply(amount: number)
	if amount == 0 then return end
	-- A real drink (not water) refreshes the sober-grace window: drunkness
	-- holds steady for SoberGraceSeconds after your last sip before decaying.
	if amount > 0 then
		self.LastSipAt = os.clock()
	end
	self.DrunknessValue.Value = math.clamp(self.DrunknessValue.Value + amount, 0, self.MaxDrunkness)
end

function DrinkEffects:_setCollapsed(active: boolean, now: number, duration: number?, isStumble: boolean?)
	if self.CollapsedValue.Value == active then return end
	self.CollapsedValue.Value = active
	if active then
		self.IsStumble = isStumble == true
		self.CollapsedUntil = now + (duration or config.DrunkCollapseDuration or 5)
		-- Stumbles and full collapses track SEPARATE cooldowns. Sharing one
		-- meant frequent stumbles kept resetting the collapse timer, so a
		-- player stumbling their way up could never trigger the max-drunkness
		-- ragdoll at all.
		if self.IsStumble then
			self.LastStumbleAt = now
		else
			self.LastCollapseAt = now
		end
	else
		self.CollapsedUntil = 0
		-- Only a full collapse sobers you toward the recovery ratio on wake.
		-- Stumbles are just trips — they must not cut drunkness back down,
		-- or drinking toward max keeps getting undone.
		if not self.IsStumble then
			local recoveryRatio  = config.DrunkCollapseRecoveryRatio or 0.78
			local target = self.MaxDrunkness * recoveryRatio
			if self.DrunknessValue.Value > target then
				self.DrunknessValue.Value = target
			end
		end
		self.IsStumble = false
	end
end

function DrinkEffects:_updateMovement(stage: string)
	local humanoid = self.Humanoid
	if not humanoid then return end
	humanoid.WalkSpeed = math.max(0, self.BaseWalkSpeed * getWalkMultiplier(stage))
	setHumanoidJumpPower(humanoid, math.max(0, self.BaseJumpPower * getJumpMultiplier(stage)))
	humanoid.AutoRotate = stage ~= "Collapsed"
end

-- Bubbles particle above the head while drunk. Server-created → replicated,
-- so the whole bar can see who's hammered.
function DrinkEffects:_updateBubbles(t: number)
	if config.DrunkBubblesEnabled ~= true then return end
	local char = self.Character
	local head = char and char:FindFirstChild("Head")
	if not head then return end

	local emitter = head:FindFirstChild("DS_DrunkBubbles")
	local buzzedT = (config.DrunkStageThresholds and config.DrunkStageThresholds.Buzzed) or 0.20

	if t >= buzzedT then
		if not emitter then
			emitter = Instance.new("ParticleEmitter")
			emitter.Name = "DS_DrunkBubbles"
			emitter.Texture = "rbxassetid://" .. tostring(config.DrunkBubblesTexture or 249902641)
			emitter.Color = ColorSequence.new(Color3.fromRGB(255, 236, 167))
			emitter.LightEmission = 0.05
			emitter.Orientation = Enum.ParticleOrientation.FacingCamera
			emitter.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0.2),
				NumberSequenceKeypoint.new(1, 0),
			})
			emitter.Speed = NumberRange.new(1.5)
			emitter.Lifetime = NumberRange.new(3)
			emitter.SpreadAngle = Vector2.new(25, 25)
			emitter.Rate = 0
			emitter.Parent = head
		end
		-- Rate ramps with drunkness: light fizz when buzzed → steady stream wasted
		emitter.Rate = 0.5 + 3 * math.clamp((t - buzzedT) / math.max(1 - buzzedT, 0.001), 0, 1)
	elseif emitter then
		emitter.Rate = 0
	end
end

function DrinkEffects:Tick(dt: number, now: number)
	-- Passive recovery only when not collapsed, and only after the sober-grace
	-- window — actively drinking players keep their buzz.
	local graceSeconds = config.SoberGraceSeconds or 0
	if self.RecoveryPerSecond > 0
		and self.DrunknessValue.Value > 0
		and not self.CollapsedValue.Value
		and (now - (self.LastSipAt or -math.huge)) >= graceSeconds then
		self.DrunknessValue.Value = math.clamp(
			self.DrunknessValue.Value - self.RecoveryPerSecond * dt,
			0, self.MaxDrunkness
		)
	end

	-- Auto-recover from collapse when timer expires.
	if self.CollapsedValue.Value and self.CollapsedUntil > 0 and now >= self.CollapsedUntil then
		self:_setCollapsed(false, now)
	end

	local t = normalized(self.DrunknessValue.Value, self.MaxDrunkness)
	local collapseThreshold  = config.DrunkCollapseThreshold  or 0.92
	local collapseCooldown   = config.DrunkCollapseCooldown    or 60
	local stumbleThreshold   = config.DrunkStumbleThreshold    or 0.72
	local stumbleDuration    = config.DrunkStumbleDuration     or 2.2
	local stumbleCooldown    = config.DrunkStumbleCooldown     or 4

	-- Seated players never trip or collapse from thresholds — fighting a seat
	-- weld glitches badly. (forceCollapse from special drinks still applies.)
	local isSeated = self.Humanoid ~= nil and self.Humanoid.Sit == true

	if not self.CollapsedValue.Value and not isSeated then
		if t >= collapseThreshold and (now - self.LastCollapseAt) >= collapseCooldown then
			-- Full collapse at 92%+ (own cooldown — stumbles don't delay it)
			self:_setCollapsed(true, now, config.DrunkCollapseDuration or 5, false)
		elseif t >= stumbleThreshold
			and (now - self.LastStumbleAt) >= stumbleCooldown
			and (now - self.LastCollapseAt) >= stumbleCooldown then
			-- Random stumble in the wasted range
			local chanceAlpha = math.clamp(
				(t - stumbleThreshold) / math.max(1 - stumbleThreshold, 0.001),
				0, 1
			)
			local chanceMin = config.DrunkStumbleChancePerSecondMin or 0.12
			local chanceMax = config.DrunkStumbleChancePerSecondMax or 0.45
			local chance    = chanceMin + (chanceMax - chanceMin) * chanceAlpha
			-- Trip-when-running: moving drunk players trip much more than
			-- standing ones. MovementValue is our replicated move alpha.
			local moveScale = 0.3 + 1.2 * math.clamp(self.MovementValue.Value, 0, 1)
			if math.random() < (chance * moveScale * dt) then
				self:_setCollapsed(true, now, stumbleDuration, true)
			end
		end
	end

	-- Hiccups: server-played so nearby players hear them too. Frequency ramps
	-- with drunkness; suppressed while collapsed.
	local hiccupId = config.DrunkHiccupSoundId
	if hiccupId and t >= 0.20 and not self.CollapsedValue.Value and now >= self.NextHiccupAt then
		DrinkEffectsService.playCharacterSound(self.Player, hiccupId, 0.6, 0.92 + math.random() * 0.18)
		local baseInterval = 9 - 5 * math.min(t, 1)
		self.NextHiccupAt = now + math.max(2, baseInterval + (-1 + math.random() * 2.4))
	end

	local stage = computeStage(self.DrunknessValue.Value, self.MaxDrunkness, self.CollapsedValue.Value)
	self.StageValue.Value   = stage
	self.MovementValue.Value = computeMovementAlpha(self.DrunknessValue.Value, self.MaxDrunkness, self.CollapsedValue.Value)
	self:_updateMovement(stage)

	-- Drunk bubbles above the head — SERVER-side so everyone at the bar sees
	-- who's had too many. Rate scales with drunkness; silent below Buzzed.
	self:_updateBubbles(t)

	-- Fly-away safety net: ragdoll physics occasionally launches characters.
	-- If the root ends up absurdly far out, drag them back to spawn.
	local char = self.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		local pos = root.Position
		if math.abs(pos.X) > 10000 or math.abs(pos.Y) > 10000 or math.abs(pos.Z) > 10000 then
			local spawnCF = CFrame.new(0, 50, 0)
			local spawnLoc = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
			if spawnLoc then
				spawnCF = spawnLoc.CFrame + Vector3.new(0, 4, 0)
			end
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.CFrame = spawnCF
			if self.CollapsedValue.Value then
				self:_setCollapsed(false, now)
			end
			warn("[DrinkSystem] Rescued", self.Player.Name, "from out-of-bounds position")
		end
	end

	if config.EnableDrunkDebug == true and stage ~= self.LastStage then
		print(
			"[DrinkSystem][Stage]",
			self.Player.Name,
			"→", stage,
			"| Drunkness =", math.floor(self.DrunknessValue.Value + 0.5)
		)
	end
	self.LastStage = stage
end

function DrinkEffects:Destroy()
	self.Character = nil
	self.Humanoid  = nil
end

local function waitForCharacterMotors(character: Model)
	character:WaitForChild("HumanoidRootPart", 10)
	local upperTorso = character:WaitForChild("UpperTorso", 10)
	if upperTorso then upperTorso:WaitForChild("Waist", 10) end
	task.wait()
end

function DrinkEffectsService.configure(newConfig: Config?)
	if type(newConfig) ~= "table" then return end
	for key, value in pairs(newConfig) do
		config[key] = value
	end
end

function DrinkEffectsService.get(player: Player)
	local state = states[player]
	if not state then
		state = DrinkEffects.new(player)
		states[player] = state

		player.CharacterAdded:Connect(function(character)
			if states[player] == state then
				task.spawn(function()
					waitForCharacterMotors(character)
					if states[player] == state then
						state:BindCharacter(character)
					end
				end)
			end
		end)

		if player.Character then
			task.spawn(function()
				waitForCharacterMotors(player.Character)
				if states[player] == state then
					state:BindCharacter(player.Character)
				end
			end)
		end
	end
	return state
end

function DrinkEffectsService.applyDrink(player: Player, amount: number)
	DrinkEffectsService.get(player):Apply(amount)
end

-- Force a full collapse regardless of drunkness (special drink effects like
-- Sin Obu). Bypasses thresholds and cooldowns.
function DrinkEffectsService.forceCollapse(player: Player, duration: number?)
	local state = DrinkEffectsService.get(player)
	state:_setCollapsed(true, os.clock(), duration or 10, false)
end

-- Spatial sound on the player's character — server-created so EVERYONE nearby
-- hears it (client-created sounds are local-only). Low rolloff keeps it subtle.
function DrinkEffectsService.playCharacterSound(player: Player, soundId: (number | string)?, volume: number?, playbackSpeed: number?, maxDistance: number?)
	if not soundId then return end
	local char = player.Character
	local part = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
	if not part then return end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. tostring(soundId)
	sound.Volume = volume or 0.5
	sound.PlaybackSpeed = playbackSpeed or 1
	sound.RollOffMode = Enum.RollOffMode.Linear  -- stays audible across the range, then cuts
	sound.RollOffMaxDistance = maxDistance or 45
	sound.RollOffMinDistance = 8
	sound.Parent = part
	sound:Play()
	sound.Ended:Once(function() sound:Destroy() end)
	task.delay(10, function()
		if sound.Parent then sound:Destroy() end
	end)
end

function DrinkEffectsService.start()
	for _, player in ipairs(Players:GetPlayers()) do
		DrinkEffectsService.get(player)
	end

	Players.PlayerAdded:Connect(function(player)
		DrinkEffectsService.get(player)
	end)

	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for _, state in pairs(states) do
			state:Tick(dt, now)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local state = states[player]
		if state then state:Destroy() end
		states[player] = nil
	end)
end

return DrinkEffectsService
