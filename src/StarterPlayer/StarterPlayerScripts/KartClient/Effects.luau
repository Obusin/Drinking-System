--[[
	Effects — drift trails and boost speed lines.

	Created client-side, so they cost nothing to replicate. The flip side
	is only the driver sees their own; multiplayer would need a server
	signal.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))

local FX = Config.Effects
local H = Config.Handling

local Effects = {}
Effects.__index = Effects

function Effects.new(hitbox: BasePart)
	local created = {}
	local function make(class: string, props, parent: Instance?)
		local inst = Instance.new(class)
		for k, v in props do
			inst[k] = v
		end
		inst.Parent = parent or hitbox
		table.insert(created, inst)
		return inst
	end

	-- A Trail draws a ribbon between two attachments, so the gap between
	-- them IS the width. Sitting them just above the ground at each rear
	-- corner gives a tyre-mark ribbon that curves with the slide.
	local function driftTrail(xSign: number)
		local x = FX.TrailInset * xSign
		local low = -H.RideHeight + 0.06
		local a0 = make("Attachment", {
			Name = "_TrailLow",
			Position = Vector3.new(x, low, FX.TrailBack),
		})
		local a1 = make("Attachment", {
			Name = "_TrailHigh",
			Position = Vector3.new(x, low + FX.TrailWidth, FX.TrailBack),
		})
		return make("Trail", {
			Name = "_DriftTrail",
			Attachment0 = a0,
			Attachment1 = a1,
			Enabled = false,
			Lifetime = FX.TrailLifetime,
			MinLength = 0.05,
			FaceCamera = true,
			LightInfluence = 0,
			-- Solid at the tyre, fading and narrowing behind.
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(0.3, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			}),
			WidthScale = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.35, 0.8),
				NumberSequenceKeypoint.new(1, 0),
			}),
		})
	end

	local lineAtt = make("Attachment", { Name = "_LineAtt", Position = Vector3.new(0, 0.4, 2.6) })
	local speedLines = make("ParticleEmitter", {
		Name = "_SpeedLines",
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Enabled = false,
		Rate = 70,
		Lifetime = NumberRange.new(0.16, 0.3),
		Speed = NumberRange.new(45, 75),
		SpreadAngle = Vector2.new(8, 8),
		LightEmission = 0.6,
		LightInfluence = 0,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, lineAtt)

	return setmetatable({
		created = created,
		trails = { driftTrail(-1), driftTrail(1) },
		speedLines = speedLines,
	}, Effects)
end

-- `on` is separate from `tier` because the trails show from the moment
-- the drift starts (neutral grey) and only take a tier colour once the
-- charge reaches one.
function Effects:SetTrails(on: boolean, tier: number)
	local color = if tier > 0 then FX.TierColors[math.clamp(tier, 1, #FX.TierColors)] else FX.TrailBaseColor
	for _, trail in self.trails do
		trail.Enabled = on
		trail.Color = ColorSequence.new(color)
		-- Charged tiers glow; the uncharged ribbon is just rubber.
		trail.LightEmission = if tier > 0 then 1 else 0.15
		trail.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, if tier > 0 then 1.15 else 1),
			NumberSequenceKeypoint.new(0.35, 0.8),
			NumberSequenceKeypoint.new(1, 0),
		})
	end
end

function Effects:Boost(_tier: number)
	self.speedLines.Enabled = true
end

function Effects:Update(_dt: number, sim)
	if not sim.boosting and self.speedLines.Enabled then
		self.speedLines.Enabled = false
	end
end

function Effects:Destroy()
	for _, inst in self.created do
		inst:Destroy()
	end
	table.clear(self.created)
end

return Effects
