local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local RagdollService = require(script.Parent:WaitForChild("RagdollService"))

local DrinkEffectsService = {}

type Config = {
	DrunknessMax: number?,
	DrunknessRecoveryPerSecond: number?,
	DrunkStageThresholds: {
		Buzzed: number?,
		Drunk: number?,
		Wasted: number?,
	}?,
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
	DrunknessMax = 100,
	DrunknessRecoveryPerSecond = 0,
	DrunkStageThresholds = {
		Buzzed = 0.18,
		Drunk = 0.42,
		Wasted = 0.72,
	},
	DrunkCollapseThreshold = 0.93,
	DrunkCollapseDuration = 3.5,
	DrunkCollapseCooldown = 12,
	DrunkCollapseRecoveryRatio = 0.78,
	DrunkMovementMaxAlpha = 0.85,
	DrunkWalkSpeedMultipliers = {
		Sober = 1,
		Buzzed = 0.96,
		Drunk = 0.82,
		Wasted = 0.67,
		Collapsed = 0,
	},
	DrunkJumpPowerMultipliers = {
		Sober = 1,
		Buzzed = 0.95,
		Drunk = 0.8,
		Wasted = 0.55,
		Collapsed = 0,
	},
	DrunkStumbleThreshold = 0.7,
	DrunkStumbleChancePerSecondMin = 0.025,
	DrunkStumbleChancePerSecondMax = 0.14,
	DrunkStumbleDuration = 2.5,
	DrunkStumbleCooldown = 9,
	EnableDrunkDebug = false,
}

local function getOrCreateValue<T>(player: Player, name: string, className: string, initialValue: T)
	local value = player:FindFirstChild(name)
	if value and value:IsA(className) then
		value.Value = value.Value
		return value
	end

	if value then
		value:Destroy()
	end

	local created = Instance.new(className)
	created.Name = name
	created.Value = initialValue
	created.Parent = player
	return created
end

local function normalizedDrunkness(current: number, maxDrunkness: number): number
	return math.clamp(current / math.max(maxDrunkness, 1), 0, 1)
end

local function computeStage(current: number, maxDrunkness: number, collapsed: boolean): string
	if collapsed then
		return "Collapsed"
	end

	local normalized = normalizedDrunkness(current, maxDrunkness)
	local thresholds = config.DrunkStageThresholds or {}

	if normalized >= (thresholds.Wasted or 0.72) then
		return "Wasted"
	end
	if normalized >= (thresholds.Drunk or 0.42) then
		return "Drunk"
	end
	if normalized >= (thresholds.Buzzed or 0.18) then
		return "Buzzed"
	end

	return "Sober"
end

local function computeMovementAlpha(current: number, maxDrunkness: number, collapsed: boolean): number
	if collapsed then
		return 0
	end

	local normalized = normalizedDrunkness(current, maxDrunkness)
	local thresholds = config.DrunkStageThresholds or {}
	local buzzedThreshold = thresholds.Buzzed or 0.18
	local drunkThreshold = thresholds.Drunk or 0.42
	local startThreshold = buzzedThreshold + ((drunkThreshold - buzzedThreshold) * 0.45)
	local maxAlpha = config.DrunkMovementMaxAlpha or 0.85
	if normalized <= startThreshold then
		return 0
	end

	return math.clamp((normalized - startThreshold) / math.max(1 - startThreshold, 0.001), 0, 1) * maxAlpha
end

local function getWalkMultiplier(stage: string): number
	local multipliers = config.DrunkWalkSpeedMultipliers or {}
	return multipliers[stage] or 1
end

local function getJumpMultiplier(stage: string): number
	local multipliers = config.DrunkJumpPowerMultipliers or {}
	return multipliers[stage] or 1
end

local function setHumanoidJumpPower(humanoid: Humanoid, jumpPower: number)
	if humanoid.UseJumpPower then
		humanoid.JumpPower = jumpPower
	else
		humanoid.JumpHeight = math.max(0, jumpPower / 7.2)
	end
end

local function getHumanoidJumpPower(humanoid: Humanoid): number
	if humanoid.UseJumpPower then
		return humanoid.JumpPower
	end
	return humanoid.JumpHeight * 7.2
end

function DrinkEffects.new(player: Player): DrinkEffects
	local self = setmetatable({}, DrinkEffects)
	self.Player = player
	self.MaxDrunkness = config.DrunknessMax or 100
	self.RecoveryPerSecond = config.DrunknessRecoveryPerSecond or 0
	self.DrunknessValue = getOrCreateValue(player, "Drunkness", "NumberValue", 0) :: NumberValue
	self.StageValue = getOrCreateValue(player, "DrunkStage", "StringValue", "Sober") :: StringValue
	self.MovementValue = getOrCreateValue(player, "DrunkMoveAlpha", "NumberValue", 0) :: NumberValue
	self.CollapsedValue = getOrCreateValue(player, "DrunkCollapsed", "BoolValue", false) :: BoolValue
	self.Character = nil
	self.Humanoid = nil
	self.BaseWalkSpeed = 16
	self.BaseJumpPower = 50
	self.CollapsedUntil = 0
	self.LastCollapseAt = -math.huge
	self.LastStage = "Sober"
	return self
end

function DrinkEffects:BindCharacter(character: Model?)
	if self.Character and self.Character ~= character then
		RagdollService.clearCharacter(self.Character)
	end

	self.Character = character
	self.Humanoid = nil

	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	self.Humanoid = humanoid
	self.BaseWalkSpeed = humanoid.WalkSpeed
	self.BaseJumpPower = getHumanoidJumpPower(humanoid)
	RagdollService.rigCharacter(character)
	if self.CollapsedValue.Value == true then
		RagdollService.setRagdolled(character, true)
	end
end

function DrinkEffects:Apply(amount: number)
	if amount <= 0 then
		return
	end

	local newValue = math.clamp(self.DrunknessValue.Value + amount, 0, self.MaxDrunkness)
	self.DrunknessValue.Value = newValue
end

function DrinkEffects:_setCollapsed(active: boolean, now: number, durationOverride: number?)
	if self.CollapsedValue.Value == active then
		return
	end

	self.CollapsedValue.Value = active
	if active then
		local duration = durationOverride or config.DrunkCollapseDuration or 3.5
		self.CollapsedUntil = now + duration
		self.LastCollapseAt = now
	else
		self.CollapsedUntil = 0
		local recoveryRatio = config.DrunkCollapseRecoveryRatio or 0.78
		local targetAfterCollapse = self.MaxDrunkness * recoveryRatio
		if self.DrunknessValue.Value > targetAfterCollapse then
			self.DrunknessValue.Value = targetAfterCollapse
		end
	end

	if self.Character then
		RagdollService.setRagdolled(self.Character, active)
	end
end

function DrinkEffects:_updateMovement(stage: string)
	local humanoid = self.Humanoid
	if not humanoid then
		return
	end

	local walkSpeed = self.BaseWalkSpeed * getWalkMultiplier(stage)
	local jumpPower = self.BaseJumpPower * getJumpMultiplier(stage)

	humanoid.WalkSpeed = math.max(0, walkSpeed)
	setHumanoidJumpPower(humanoid, math.max(0, jumpPower))
	humanoid.AutoRotate = stage ~= "Collapsed"
end

function DrinkEffects:Tick(dt: number, now: number)
	if self.RecoveryPerSecond > 0 and self.DrunknessValue.Value > 0 then
		local decay = self.RecoveryPerSecond * dt
		self.DrunknessValue.Value = math.clamp(self.DrunknessValue.Value - decay, 0, self.MaxDrunkness)
	end

	if self.CollapsedValue.Value and self.CollapsedUntil > 0 and now >= self.CollapsedUntil then
		self:_setCollapsed(false, now)
	end

	local normalized = normalizedDrunkness(self.DrunknessValue.Value, self.MaxDrunkness)
	local collapseThreshold = config.DrunkCollapseThreshold or 0.93
	local collapseCooldown = config.DrunkCollapseCooldown or 12
	local stumbleThreshold = config.DrunkStumbleThreshold or 0.7
	local stumbleCooldown = config.DrunkStumbleCooldown or collapseCooldown

	if
		not self.CollapsedValue.Value
		and normalized >= collapseThreshold
		and (now - self.LastCollapseAt) >= collapseCooldown
	then
		self:_setCollapsed(true, now)
	elseif
		not self.CollapsedValue.Value
		and normalized >= stumbleThreshold
		and (now - self.LastCollapseAt) >= stumbleCooldown
	then
		local chanceAlpha = math.clamp(
			(normalized - stumbleThreshold) / math.max(1 - stumbleThreshold, 0.001),
			0,
			1
		)
		local chanceMin = config.DrunkStumbleChancePerSecondMin or 0.025
		local chanceMax = config.DrunkStumbleChancePerSecondMax or 0.14
		local stumbleChance = chanceMin + ((chanceMax - chanceMin) * chanceAlpha)
		if math.random() < (stumbleChance * dt) then
			self:_setCollapsed(true, now, config.DrunkStumbleDuration or 2.5)
		end
	end

	local stage = computeStage(self.DrunknessValue.Value, self.MaxDrunkness, self.CollapsedValue.Value)
	self.StageValue.Value = stage
	self.MovementValue.Value = computeMovementAlpha(self.DrunknessValue.Value, self.MaxDrunkness, self.CollapsedValue.Value)
	self:_updateMovement(stage)

	if config.EnableDrunkDebug == true and stage ~= self.LastStage then
		print(
			"[DrinkSystem][DrunkStage]",
			self.Player.Name,
			"Stage=", stage,
			"Drunkness=", math.floor(self.DrunknessValue.Value + 0.5),
			"Collapsed=", self.CollapsedValue.Value
		)
	end
	self.LastStage = stage
end

function DrinkEffects:Destroy()
	if self.Character then
		RagdollService.setRagdolled(self.Character, false)
		RagdollService.clearCharacter(self.Character)
	end
	self.Character = nil
	self.Humanoid = nil
end

function DrinkEffectsService.configure(newConfig: Config?)
	if type(newConfig) ~= "table" then
		return
	end

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
				state:BindCharacter(character)
			end
		end)

		if player.Character then
			state:BindCharacter(player.Character)
		end
	end
	return state
end

function DrinkEffectsService.applyDrink(player: Player, amount: number)
	local state = DrinkEffectsService.get(player)
	state:Apply(amount)
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
		if state then
			state:Destroy()
		end
		states[player] = nil
	end)
end

return DrinkEffectsService
