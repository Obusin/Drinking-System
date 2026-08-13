--[[
	Effects — drift trails and boost speed lines.

	Created client-side, so they cost nothing to replicate. The flip side
	is only the driver sees their own; multiplayer would need a server
	signal.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))
local Util = require(BloxKart:WaitForChild("Util"))

local FX = Config.Effects
local H = Config.Handling

local Effects = {}
Effects.__index = Effects

function Effects.new(hitbox: BasePart, model: Model?)
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

	--=================================================================
	--  ONE RIBBON PER REAR TYRE, AND THE VEHICLE SAYS HOW MANY.
	--
	--  A kart lays two, 2 studs out each side. A motorcycle has a single
	--  rear wheel, and the default pair drew two parallel marks four
	--  studs apart with the one tyre between them touching neither.
	--
	--  Read from Config.Vehicles rather than branched on here, the same
	--  way handling, slots and the steering wheel are — Effects should
	--  not have to know that motorcycles exist, only that a vehicle can
	--  describe its own trails.
	--=================================================================
	local kind = model and model:GetAttribute(Names.VEHICLE_KIND)
	local vehicle = Config.Vehicles.Kinds[kind or Config.Vehicles.Default] or Config.Vehicles.Kinds.kart
	local layout = vehicle.trails
	local back = if layout and layout.Back then layout.Back else FX.TrailBack

	-- A Trail draws a ribbon between two attachments, so the gap between
	-- them IS the width. Sitting them just above the ground at each rear
	-- corner gives a tyre-mark ribbon that curves with the slide.
	local function driftTrail(xSign: number)
		local x = FX.TrailInset * xSign
		local low = -H.RideHeight + 0.06
		local a0 = make("Attachment", {
			Name = "_TrailLow",
			Position = Vector3.new(x, low, back),
		})
		local a1 = make("Attachment", {
			Name = "_TrailHigh",
			Position = Vector3.new(x, low + FX.TrailWidth, back),
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

	local self = setmetatable({
		created = created,
		trails = (function()
			local out = {}
			for _, xSign in (layout and layout.Xs or { -1, 1 }) do
				table.insert(out, driftTrail(xSign))
			end
			return out
		end)(),
		speedLines = speedLines,
		shieldParts = {},
		shieldAlpha = 1,
	}, Effects)

	-- Authored art rather than anything built here, so it's looked up
	-- rather than created — and if the kart has no bubble, everything
	-- below is a no-op on an empty list.
	self:_findShield(model)
	return self
end

-- `on` is separate from `tier` because the trails show from the moment
-- the drift starts (neutral grey) and only take a tier colour once the
-- charge reaches one.
--=====================================================================
--  SHIELD BUBBLE
--
--  Authored art, not built here: a Model named after FX.ShieldName
--  anywhere inside the kart. Found by name so the artist can nest and
--  rename around it freely.
--
--  Faded rather than toggled, because a bubble that pops into existence
--  reads as a glitch while one that swells reads as a shield coming up.
--
--  Collision is forced off on every part of it here as well as in
--  KartFactory. Belt and braces on purpose: the factory only touches art
--  that came through the KartVisual path, and a bubble welded on by hand
--  would otherwise be a solid ball around the kart.
--=====================================================================
function Effects:_findShield(model: Model?)
	self.shieldParts = {}
	self.shieldAlpha = 1 -- 1 = fully invisible
	if not model then
		return
	end
	local root = model:FindFirstChild(FX.ShieldName, true)
	if not root then
		return
	end
	local parts = if root:IsA("BasePart") then { root } else {}
	if not root:IsA("BasePart") then
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
	end
	for _, part in parts do
		part.CanCollide = false
		part.CanQuery = false -- never a wall to anyone's movement sweep
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		part.Transparency = 1 -- starts down
	end
	self.shieldParts = parts
end

function Effects:SetTrails(on: boolean, tier: number)
	-- COLOUR AND GLOW ONLY. Width moved to Update, because it now tracks
	-- the slip angle, which changes continuously — and this is called
	-- only when the tier changes.
	local color = if tier > 0 then FX.TierColors[math.clamp(tier, 1, #FX.TierColors)] else FX.TrailBaseColor
	self.trailTier = tier
	for _, trail in self.trails do
		trail.Enabled = on
		trail.Color = ColorSequence.new(color)
		-- Charged tiers glow; the uncharged ribbon is just rubber.
		trail.LightEmission = if tier > 0 then 1 else 0.15
	end
end

function Effects:Boost(_tier: number)
	self.speedLines.Enabled = true
end

function Effects:Update(dt: number, sim)
	if not sim.boosting and self.speedLines.Enabled then
		self.speedLines.Enabled = false
	end

	--=================================================================
	--  THE RIBBON'S SIZE IS THE SLIP ANGLE.
	--
	--  How hard the kart is actually sliding, right now — the thing the
	--  driver controls moment to moment with opposite lock, and which
	--  previously had no readout anywhere. A lazy drift and a balanced
	--  one on the edge of MaxSlip looked exactly the same.
	--
	--  Colour still means charge. Two facts, two channels; sharing one
	--  would make a wide ribbon ambiguous between "nearly boosting" and
	--  "sliding hard", which are different things to know.
	--=================================================================
	local slip = math.abs(sim.driftAngle or 0)
	local span = math.max(H.MaxSlip - FX.TrailSlipFloor, 1)
	local hard = math.clamp((math.deg(slip) - FX.TrailSlipFloor) / span, 0, 1)
	self.slipNow = Util.approach(self.slipNow or 0, hard, FX.TrailSlipRate, dt)

	local tier = self.trailTier or 0
	local base = if tier > 0 then 1.15 else 1
	local width = base * (1 + (FX.TrailSlipWidth - 1) * self.slipNow)
	for _, trail in self.trails do
		if trail.Enabled then
			trail.WidthScale = NumberSequence.new({
				NumberSequenceKeypoint.new(0, width),
				NumberSequenceKeypoint.new(0.35, width * 0.8),
				NumberSequenceKeypoint.new(1, 0),
			})
			trail.LightEmission = (if tier > 0 then 1 else 0.15) + FX.TrailSlipGlow * self.slipNow
		end
	end

	-- Shield bubble. Driven off the same HasShield the hit logic reads, so
	-- what you see and what actually protects you can never disagree.
	if #self.shieldParts > 0 then
		local target = if sim:HasShield() then FX.ShieldTransparency else 1
		self.shieldAlpha = Util.approach(self.shieldAlpha, target, FX.ShieldFadeRate, dt)
		for _, part in self.shieldParts do
			part.Transparency = self.shieldAlpha
		end
	end
end

function Effects:Destroy()
	for _, inst in self.created do
		inst:Destroy()
	end
	table.clear(self.created)
end

return Effects
