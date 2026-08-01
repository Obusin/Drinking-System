--[[
	Warp — the world going past, in screen space.

	Field of view widens the frame; nothing IN the frame moves any
	differently until something like this does. Streaks fly outward from
	the centre of the screen, born near the middle and accelerating as
	they go, which is what reads as depth rather than as lines drawn on
	glass.

	DRIVEN BY THE LIVE BURN STAGE, not by the event that started it —
	same as the camera, so the two escalate together. Three systems each
	deciding for themselves how fast things currently are is three
	systems that will eventually disagree.

	Streaks are pooled and recycled. Each carries its own phase, so they
	do not pulse together; a wave of streaks arriving in step reads as a
	strobe rather than as speed.

	Nothing here feeds back into movement. It is allowed to be wrong for
	a frame and nothing breaks.
--]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))

local FX = Config.Effects

local Warp = {}
Warp.__index = Warp

local rng = Random.new()

function Warp.new()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BloxKartWarp"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- UNDER every readout. This is atmosphere, and atmosphere that
	-- covers the lap counter is a bug.
	gui.DisplayOrder = 1
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local streaks = {}
	for i = 1, FX.WarpStreaks do
		local f = Instance.new("Frame")
		f.Name = "Streak" .. i
		f.BackgroundColor3 = FX.WarpColor
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(FX.WarpThickness, FX.WarpLength)
		f.BackgroundTransparency = 1
		f.Parent = gui
		table.insert(streaks, {
			frame = f,
			-- Spread across the whole cycle at birth so the first burn
			-- does not begin with every streak stacked on the centre.
			phase = rng:NextNumber(),
			angle = rng:NextNumber() * math.pi * 2,
			speed = rng:NextNumber(0.75, 1.3),
		})
	end

	-- One blur, created once and left in Lighting. Toggled rather than
	-- added and removed: churning post-processing instances is a hitch
	-- every time a boost starts.
	local blur = Instance.new("BlurEffect")
	blur.Name = "BloxKartWarpBlur"
	blur.Size = 0
	blur.Enabled = false
	blur.Parent = Lighting

	return setmetatable({ gui = gui, streaks = streaks, blur = blur, intensity = 0 }, Warp)
end

function Warp:Update(dt: number, sim)
	if not FX.WarpEnabled then
		return
	end

	----------------------------------------------------------------
	-- How fast does the world currently look?
	----------------------------------------------------------------
	local target = 0
	if sim then
		local burn = sim.burnStage or 0
		if burn > 0 then
			target = FX.WarpPerStage[math.min(burn, #FX.WarpPerStage)] or 0
		end
		-- Flat out with no nitro still gets a little, so top speed is
		-- never completely still. `math.max`, not additive: a boost
		-- should not be worth more merely because you were already fast.
		local fast = math.max((sim.speedFrac or 0) - 0.9, 0) / 0.1
		target = math.max(target, fast * FX.WarpAtTopSpeed)
	end

	local rate = if target > self.intensity then FX.WarpRise else FX.WarpFall
	self.intensity = Util.approach(self.intensity, target, rate, dt)

	local on = self.intensity > 0.01
	if self.gui.Enabled ~= on then
		self.gui.Enabled = on
	end
	if self.blur.Enabled ~= on then
		self.blur.Enabled = on
	end
	if not on then
		return
	end

	self.blur.Size = FX.WarpBlur * self.intensity

	----------------------------------------------------------------
	-- Streaks
	----------------------------------------------------------------
	local span = FX.WarpOuterRadius - FX.WarpInnerRadius
	for _, s in self.streaks do
		s.phase += dt * FX.WarpSpeed * s.speed * self.intensity
		if s.phase >= 1 then
			s.phase -= 1
			-- A NEW ANGLE EACH LAP of the cycle. Recycling the same
			-- angle makes the streaks read as fixed spokes on a wheel
			-- rather than as things flying past.
			s.angle = rng:NextNumber() * math.pi * 2
			s.speed = rng:NextNumber(0.75, 1.3)
		end

		local p = s.phase
		-- Squared, so it accelerates outward. Linear travel looks like a
		-- zoom; accelerating looks like depth.
		local radius = FX.WarpInnerRadius + span * p * p
		local cos, sin = math.cos(s.angle), math.sin(s.angle)

		local f = s.frame
		f.Position = UDim2.fromScale(0.5 + cos * radius * 0.5, 0.5 + sin * radius * 0.5)
		-- A Frame's long axis is vertical, so it is turned to lie ALONG
		-- the radius rather than across it.
		f.Rotation = math.deg(s.angle) + 90
		f.Size = UDim2.fromOffset(FX.WarpThickness, FX.WarpLength * self.intensity * (0.35 + p))

		-- In quickly, out slowly, so streaks appear from nothing and
		-- leave at the edge rather than being cut off.
		local alpha = math.min(p * 4, 1) * (1 - p) * (1 - p)
		f.BackgroundTransparency = 1 - (1 - FX.WarpTransparency) * alpha * self.intensity
	end
end

function Warp:Destroy()
	self.blur:Destroy()
	self.gui:Destroy()
end

return Warp
