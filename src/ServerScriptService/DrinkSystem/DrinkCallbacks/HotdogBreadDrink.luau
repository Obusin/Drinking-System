-- Hotdog Bread Drink: Bukonelle x2 + Soda Water → smoke rises from the
-- drinker's head for a while. Real Instance parented to their Head, so it
-- replicates to everyone automatically.
--
-- Optional Studio override: drop a custom ParticleEmitter at
--   ReplicatedStorage/DrinkSystem/VFX/Smoke
-- If it's missing, a generated grey-smoke default is used instead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DrinkSystem = ReplicatedStorage:WaitForChild("DrinkSystem")

local HotdogBreadDrink = {}

local function findSmokeTemplate(): ParticleEmitter?
	local vfx = DrinkSystem:FindFirstChild("VFX")
	local item = vfx and vfx:FindFirstChild("Smoke")
	if item and item:IsA("ParticleEmitter") then
		return item
	end
	return nil
end

local function buildDefaultSmoke(): ParticleEmitter
	local p = Instance.new("ParticleEmitter")
	p.Color = ColorSequence.new(Color3.fromRGB(200, 200, 200))
	p.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1.2),
	})
	p.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	p.Lifetime = NumberRange.new(1, 1.6)
	p.Rate = 12
	p.Speed = NumberRange.new(1.5, 2.5)
	p.SpreadAngle = Vector2.new(15, 15)
	p.Drag = 1
	p.Acceleration = Vector3.new(0, 4, 0)
	p.LightEmission = 0
	return p
end

-- ctx: { Player, Tool, Remaining, SipAmount, Services }
function HotdogBreadDrink.OnSip(ctx)
	local tool = ctx.Tool
	if tool then
		if tool:GetAttribute("DS_HotdogSmokeTriggered") == true then
			return
		end
		tool:SetAttribute("DS_HotdogSmokeTriggered", true)
	end

	local char = ctx.Player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then
		return
	end

	local template = findSmokeTemplate()
	local emitter = template and template:Clone() or buildDefaultSmoke()
	emitter.Name = "DS_HeadSmoke"
	emitter.Parent = head

	local Services = ctx.Services
	local duration = Services.Settings.HotdogSmokeDuration or 10
	task.delay(duration, function()
		if not emitter.Parent then
			return
		end
		emitter.Enabled = false
		-- let already-emitted puffs finish fading before destroying
		task.delay(math.max(emitter.Lifetime.Max, 2), function()
			if emitter.Parent then
				emitter:Destroy()
			end
		end)
	end)
end

return HotdogBreadDrink
