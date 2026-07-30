--[[
	PlaceholderVisual — a stand9-in kart body.

	Used only when ServerStorage has no `KartVisual` Model. Every part is
	Massless and non-colliding: it contributes nothing to the simulation.
--]]

local function cosmetic(parent: Model, name: string, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local PlaceholderVisual = {}

function PlaceholderVisual.build(): Model
	local visual = Instance.new("Model")
	visual.Name = "Visual"

	local red = Color3.fromRGB(196, 40, 28)
	local dark = Color3.fromRGB(27, 42, 53)

	local chassis = cosmetic(visual, "Chassis", Vector3.new(3.6, 0.8, 6.4), CFrame.new(0, 0.1, 0), red)
	visual.PrimaryPart = chassis
	cosmetic(visual, "Nose", Vector3.new(2.6, 0.5, 1.6), CFrame.new(0, 0.2, -3.4), red)
	cosmetic(visual, "SeatBack", Vector3.new(2, 1.6, 0.5), CFrame.new(0, 1.1, 1.6), dark)
	cosmetic(visual, "Bar", Vector3.new(2.4, 0.25, 0.25), CFrame.new(0, 1.0, -0.6), dark)

	-- Wheels are cosmetic too. The controller does not know they exist.
	local r, w = 1.1, 0.7
	for _, spec in
		{
			{ "WheelFL", -2.1, -2.3 },
			{ "WheelFR", 2.1, -2.3 },
			{ "WheelRL", -2.1, 2.3 },
			{ "WheelRR", 2.1, 2.3 },
		}
	do
		cosmetic(
			visual,
			spec[1],
			Vector3.new(w, r * 2, r * 2),
			CFrame.new(spec[2], -0.3, spec[3]),
			dark,
			Enum.PartType.Cylinder
		)
	end

	return visual
end

return PlaceholderVisual
