--[[
	GapFill — close a gap with triangles.

	Roblox has no triangle primitive. What it has is the WedgePart, whose
	sloped face is a right triangle — so ANY triangle is drawable as two
	right triangles joined along the altitude dropped from the corner
	opposite the longest edge. That is the entire trick, and it is why
	every gap-filling plugin ever written produces wedges in pairs.

	THE LONGEST EDGE MUST BE THE HYPOTENUSE.
	----------------------------------------
	Drop the altitude from the corner opposite the longest edge and its
	foot lands INSIDE that edge, so the two right triangles tile the
	original exactly. Drop it from either other corner and the foot lands
	outside, so the two pieces overlap and stick out past the triangle
	you asked for. The swap below is not tidiness — it is the difference
	between a fill and a mess.

	DEGENERATE INPUT IS REFUSED, NOT DRAWN. Three points in a line have no
	plane, so the cross product is zero and `.Unit` is NaN. A NaN CFrame
	does not error — it produces a part at no position that you cannot
	select, cannot see, and cannot delete without finding it in the
	Explorer. Checked before it can happen.
--]]

local Ghost = require(script.Parent.Parent.Core.Ghost)
local History = require(script.Parent.Parent.Core.History)
local Sel = require(script.Parent.Parent.Core.Sel)
local Ui = require(script.Parent.Parent.Core.Ui)

local GapFill = {}

local MIN_AREA = 1e-4

-- Two wedges forming the triangle abc. Returns them, or nil if the three
-- points do not describe a real triangle.
local function triangle(a: Vector3, b: Vector3, c: Vector3, thickness: number, style: BasePart?): { WedgePart }?
	-- Twice the area. Zero means collinear, and no plane exists.
	if (b - a):Cross(c - a).Magnitude < MIN_AREA then
		return nil
	end

	-- Reorder so bc is the longest edge. See the note above.
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		a, c = c, a
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b

	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))

	local function wedge(size: Vector3, cf: CFrame): WedgePart
		local part = Instance.new("WedgePart")
		part.Anchored = true
		part.CanCollide = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		-- Inherits the look of whatever you selected, so a filled gap does
		-- not arrive as a grey slab in the middle of finished work.
		if style then
			part.Material = style.Material
			part.Color = style.Color
			part.Transparency = style.Transparency
			part.Reflectance = style.Reflectance
		end
		part.Size = size
		part.CFrame = cf
		return part
	end

	return {
		wedge(Vector3.new(thickness, height, math.abs(ab:Dot(back))), CFrame.fromMatrix((a + b) / 2, right, up, back)),
		wedge(Vector3.new(thickness, height, math.abs(ac:Dot(back))), CFrame.fromMatrix((a + c) / 2, -right, up, -back)),
	}
end

function GapFill.build(page: Instance, ctx)
	local thickness = 0.2
	local ghost = Ghost.new("GapFill")

	local sec = Ui.section(page, "Fill", "gap1")
	Ui.label(
		sec,
		"Select 3 parts to fill a triangle between their centres, or 4 for a quad. Order is the order you clicked them.",
		true
	)

	Ui.slider(sec, "Thickness", 0.05, 4, thickness, 0.05, function(v)
		thickness = v
	end)

	-- ONE BUILDER, USED BY THE PREVIEW AND THE COMMIT. If the preview had
	-- its own copy of this, the two would drift and the ghost would stop
	-- being a promise about what you are going to get.
	local function build(): { WedgePart }?
		local parts = Sel.parts(false)
		if #parts < 3 or #parts > 4 then
			ctx.status(("Select 3 or 4 parts — you have %d."):format(#parts))
			return nil
		end

		local points = {}
		for _, part in parts do
			table.insert(points, part.Position)
		end

		local created = {}
		local function emit(a, b, c): boolean
			local wedges = triangle(a, b, c, thickness, parts[1])
			if not wedges then
				return false
			end
			for _, w in wedges do
				w.Name = "Fill"
				table.insert(created, w)
			end
			return true
		end

		local ok = emit(points[1], points[2], points[3])
		-- A quad is two triangles sharing the 1-3 diagonal. Clicking the
		-- four corners in order round the shape gives the right split;
		-- clicking them crosswise gives a bowtie, which is why the hint
		-- above mentions order.
		if #points == 4 then
			ok = emit(points[1], points[3], points[4]) or ok
		end

		if not ok then
			for _, w in created do
				w:Destroy()
			end
			ctx.status("Those points are in a straight line — no triangle to draw.")
			return nil
		end
		return created
	end

	local function preview()
		if not ctx.visible() then
			return
		end
		local wedges = build()
		if wedges then
			ghost:showRaw(wedges)
			ctx.status(("Preview: %d wedge(s). Press Fill to keep it."):format(#wedges))
		else
			ghost:clear()
		end
	end

	Ui.button(sec, "Fill gap", function()
		local parts = Sel.parts(false)
		local made = History.run("Fill gap", function()
			local wedges = build()
			if not wedges then
				return nil
			end
			for _, w in wedges do
				w.Parent = parts[1].Parent
			end
			return wedges
		end)

		if made then
			ghost:clear()
			Sel.set(made)
			ctx.status(("Filled with %d wedge(s)."):format(#made), "ok")
		end
	end, nil, "primary")

	Ui.button(sec, "Clear preview", function()
		ghost:clear()
		ctx.status("Preview cleared.")
	end, nil, "quiet")

	-- Live. Picking the three corners IS the input, so the preview should
	-- appear as you pick them rather than after a button press.
	Sel.changed(function()
		task.defer(preview)
	end)

	ctx.onHide(function()
		ghost:clear()
	end)
	ctx.onShow(preview)
end

return GapFill
