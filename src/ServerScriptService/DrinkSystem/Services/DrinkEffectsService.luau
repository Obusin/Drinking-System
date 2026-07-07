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
	self.LastStage       = "Sober"
	return self
end

function DrinkEffects:BindCharacter(character: Model?)
	self.Character = character
	self.Humanoid  = nil
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	self.Humanoid       = humanoid
	self.BaseWalkSpeed  = humanoid.WalkSpeed
	self.BaseJumpPower  = getHumanoidJumpPower(humanoid)
end

function DrinkEffects:Apply(amount: number)
	if amount == 0 then return end
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

function DrinkEffects:Tick(dt: number, now: number)
	-- Passive recovery only when not collapsed.
	if self.RecoveryPerSecond > 0 and self.DrunknessValue.Value > 0 and not self.CollapsedValue.Value then
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

	if not self.CollapsedValue.Value then
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
			if math.random() < (chance * dt) then
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

-- Spatial sound on the player's character — server-created so EVERYONE nearby
-- hears it (client-created sounds are local-only). Low rolloff keeps it subtle.
function DrinkEffectsService.playCharacterSound(player: Player, soundId: (number | string)?, volume: number?, playbackSpeed: number?)
	if not soundId then return end
	local char = player.Character
	local part = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
	if not part then return end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. tostring(soundId)
	sound.Volume = volume or 0.5
	sound.PlaybackSpeed = playbackSpeed or 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = 45
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
