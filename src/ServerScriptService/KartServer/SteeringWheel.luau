--[[
	SteeringWheel
	--------------------------------------------------------------------
	The hub is joined to the hitbox with a Motor6D rather than a weld,
	because a Motor6D can be rotated at runtime and a weld can't. The rim
	is welded to the hub, so spinning the hub spins the whole assembly.

	Local axes: the wheel lies in its own XY plane and spins about Z.
	GripL / GripR sit at 9 and 3 o'clock and are what the hands aim for.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.BloxKart.Config)

local RIG = Config.Rig

local SteeringWheel = {}

-- Attach a Motor6D to an existing wheel part supplied by the artist.
function SteeringWheel.motorise(hitbox: BasePart, hub: BasePart)
	local motor = Instance.new("Motor6D")
	motor.Name = "WheelMotor"
	motor.Part0 = hitbox
	motor.Part1 = hub
	motor.C0 = hitbox.CFrame:ToObjectSpace(hub.CFrame)
	motor.C1 = CFrame.new()
	motor.Parent = hub
	return motor
end

function SteeringWheel.build(kart: Model, hitbox: BasePart): BasePart
	local hubCF = RIG.WheelOffset * CFrame.Angles(math.rad(RIG.WheelTilt), 0, 0)

	local hub = Instance.new("Part")
	hub.Name = "SteeringWheel"
	hub.Size = Vector3.new(0.28, 0.28, 0.22)
	hub.Color = RIG.WheelColor
	hub.Material = Enum.Material.SmoothPlastic
	hub.CanCollide = false
	hub.CanQuery = false
	hub.CanTouch = false
	hub.Massless = true
	hub.CFrame = hitbox.CFrame * hubCF
	hub.Parent = kart

	local motor = Instance.new("Motor6D")
	motor.Name = "WheelMotor"
	motor.Part0 = hitbox
	motor.Part1 = hub
	motor.C0 = hubCF
	motor.C1 = CFrame.new()
	motor.Parent = hub

	local function piece(name: string, size: Vector3, cf: CFrame)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = RIG.WheelColor
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CFrame = hub.CFrame * cf
		p.Parent = hub
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = hub, p
		w.Parent = hub
		return p
	end

	-- Rim: blocks laid tangentially around a circle.
	local r = RIG.WheelRadius
	local segs = RIG.WheelSegments
	local segLen = (2 * math.pi * r / segs) * 1.2 -- overlap so there are no gaps
	for i = 1, segs do
		local a = (i - 1) / segs * math.pi * 2
		piece(
			"Rim" .. i,
			Vector3.new(segLen, RIG.WheelThick, RIG.WheelThick),
			CFrame.new(math.cos(a) * r, math.sin(a) * r, 0) * CFrame.Angles(0, 0, a + math.pi / 2)
		)
	end

	-- Three spokes.
	for _, a in { math.pi, math.pi / 3, math.pi * 2 / 3 } do
		piece(
			"Spoke",
			Vector3.new(r, RIG.WheelThick * 0.7, RIG.WheelThick * 0.7),
			CFrame.new(math.cos(a) * r * 0.5, math.sin(a) * r * 0.5, 0) * CFrame.Angles(0, 0, a)
		)
	end

	-- Hand targets. 9 and 3 o'clock, rotating with the wheel.
	for name, x in { GripL = -r, GripR = r } do
		local att = Instance.new("Attachment")
		att.Name = name
		att.CFrame = CFrame.new(x, 0, 0)
		att.Parent = hub
	end

	return hub
end

return SteeringWheel
