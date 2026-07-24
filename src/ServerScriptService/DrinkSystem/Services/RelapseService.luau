-- RelapseService: Relapse Drink secret. Movement stays completely free —
-- unlike Ice Cube, this never touches WalkSpeed/state. Instead it watches
-- for idling: standing still for RelapseIdleThreshold seconds re-plays the
-- stumble animation (+ a small drunkness bump), repeating at most once every
-- RelapseMinInterval seconds, for the whole RelapseEffectDuration window.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")
local ConfigFolder = DrinkSystem:WaitForChild("Config")
local Settings = require(ConfigFolder:WaitForChild("Settings"))

local DrinkEffectsService = require(script.Parent:WaitForChild("DrinkEffectsService"))

local RelapseService = {}

type ActiveState = {
	Conn: RBXScriptConnection,
	ExpiresAt: number,
	LastMoveAt: number,
	LastRelapseAt: number,
}

local active: { [Player]: ActiveState } = {}

local function playRelapseAnim(player: Player)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local animId = Settings.RelapseAnimationId
	if not animId then
		return
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(animId)
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track:Play()
	end
end

function RelapseService.IsActive(player: Player): boolean
	return active[player] ~= nil
end

function RelapseService.Stop(player: Player)
	local state = active[player]
	if not state then
		return
	end
	active[player] = nil
	state.Conn:Disconnect()
end

function RelapseService.Start(player: Player, duration: number?)
	if active[player] then
		return -- already relapsing, don't stack
	end
	local char = player.Character
	if not char then
		return
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local dur = duration or Settings.RelapseEffectDuration or 25
	local idleThreshold = Settings.RelapseIdleThreshold or 3
	local minInterval = Settings.RelapseMinInterval or 4
	local now = os.clock()

	playRelapseAnim(player) -- the initial gulp

	local state: ActiveState = {
		Conn = nil :: any,
		ExpiresAt = now + dur,
		LastMoveAt = now,
		LastRelapseAt = now,
	}

	state.Conn = RunService.Heartbeat:Connect(function()
		if not humanoid.Parent then
			RelapseService.Stop(player)
			return
		end
		local t = os.clock()
		if t >= state.ExpiresAt then
			RelapseService.Stop(player)
			return
		end
		if humanoid.MoveDirection.Magnitude > 0.1 then
			state.LastMoveAt = t
		end
		local idleFor = t - state.LastMoveAt
		if idleFor >= idleThreshold and (t - state.LastRelapseAt) >= minInterval then
			state.LastRelapseAt = t
			playRelapseAnim(player)
			local bump = Settings.RelapseDrunknessBump
			if bump and bump > 0 then
				DrinkEffectsService.applyDrink(player, bump)
			end
		end
	end)

	active[player] = state
end

function RelapseService.init()
	Players.PlayerRemoving:Connect(RelapseService.Stop)
end

return RelapseService
