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

--=====================================================================
--  BRIDGING — THE PREDICTIVE HALF.
--
--  Picking three corners by hand is fine for one hole and useless for a
--  track. A curve laid out with Arc leaves a wedge-shaped gap between
--  EVERY consecutive pair of segments, and there may be sixty of them.
--
--  So this works out the corners itself: given two parts, it takes the
--  face on each that points at the other and lofts one to the other.
--  Nothing is clicked, and it is right for any orientation because the
--  faces are chosen by direction rather than by name.
--=====================================================================

-- The four world-space corners of the face whose outward normal is most
-- aligned with `dir`. Six candidates — three axes, two signs.
local function faceCorners(part: BasePart, dir: Vector3): { Vector3 }
	local cf = part.CFrame
	local axis = { cf.RightVector, cf.UpVector, cf.LookVector }
	local half = { part.Size.X * 0.5, part.Size.Y * 0.5, part.Size.Z * 0.5 }

	local bestAxis, bestSign, bestDot = 1, 1, -math.huge
	for i = 1, 3 do
		for _, sign in { 1, -1 } do
			local d = axis[i]:Dot(dir) * sign
			if d > bestDot then
				bestDot, bestAxis, bestSign = d, i, sign
			end
		end
	end

	-- The other two axes span the face.
	local ui = bestAxis % 3 + 1
	local vi = (bestAxis + 1) % 3 + 1
	local n = axis[bestAxis] * bestSign
	local u, v = axis[ui] * half[ui], axis[vi] * half[vi]
	local centre = part.Position + n * half[bestAxis]
	return { centre + u + v, centre + u - v, centre - u - v, centre - u + v }
end

-- NEAREST-NEIGHBOUR CHAIN, so selection ORDER DOES NOT MATTER. Dragging
-- a box over a curved run gives you the parts in whatever order Studio
-- felt like, and asking a level designer to click sixty segments in
-- sequence is not a tool, it is a punishment.
--
-- Starts from the part furthest from the centroid, which on any open run
-- is an end. A closed loop has no end, so it starts somewhere arbitrary
-- and simply leaves the last gap — press again with those two selected.
local function chain(parts: { BasePart }): { BasePart }
	if #parts < 3 then
		return parts
	end
	local centre = Vector3.zero
	for _, p in parts do
		centre += p.Position
	end
	centre /= #parts

	local startIdx, far = 1, -1
	for i, p in parts do
		local d = (p.Position - centre).Magnitude
		if d > far then
			far, startIdx = d, i
		end
	end

	local left = table.clone(parts)
	local out = { table.remove(left, startIdx) :: BasePart }
	while #left > 0 do
		local last = out[#out]
		local bestIdx, bestD = 1, math.huge
		for i, p in left do
			local d = (p.Position - last.Position).Magnitude
			if d < bestD then
				bestD, bestIdx = d, i
			end
		end
		table.insert(out, table.remove(left, bestIdx) :: BasePart)
	end
	return out
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

	--== BRIDGE ========================================================
	local bridgeSec = Ui.section(page, "Bridge", "gap2")
	Ui.label(
		bridgeSec,
		"Select a run of parts and it fills every gap between them. Order does not matter. Built for curves laid out with Arc.",
		true
	)

	-- TOP ONLY IS THE DEFAULT, and the reason is arithmetic. Lofting all
	-- four sides is 8 triangles and therefore 16 WEDGES per gap; a
	-- sixty-segment corner would be 960 parts. The drivable surface is 2
	-- triangles and 4 wedges, which is what a kart actually touches.
	local mode = "Top only"
	Ui.choice(bridgeSec, { "Top only", "All sides" }, mode, function(v)
		mode = v
	end)

	local function buildBridge(): { WedgePart }?
		local picked = Sel.parts(false)
		if #picked < 2 then
			ctx.status(("Select 2 or more parts — you have %d."):format(#picked))
			return nil
		end

		local run = chain(picked)
		local created = {}
		local function emit(a, b, c)
			local wedges = triangle(a, b, c, thickness, picked[1])
			if wedges then
				for _, w in wedges do
					w.Name = "Bridge"
					table.insert(created, w)
				end
			end
		end

		for i = 1, #run - 1 do
			local a, b = run[i], run[i + 1]
			local delta = b.Position - a.Position
			if delta.Magnitude > 1e-4 then
				local dir = delta.Unit
				local fa = faceCorners(a, dir)
				local fb = faceCorners(b, -dir)

				-- PAIRED BY PROXIMITY, not by index. The two faces point at
				-- each other, so their winding is opposite and matching
				-- 1-to-1 would cross the quad into a bowtie. Nearest corner
				-- is right however either part happens to be rotated.
				local mate = {}
				for j, pa in fa do
					local best, bestD = 1, math.huge
					for k, pb in fb do
						local d = (pa - pb).Magnitude
						if d < bestD then
							bestD, best = d, k
						end
					end
					mate[j] = fb[best]
				end

				if mode == "Top only" then
					-- The face edge highest along world up is the one the
					-- kart drives on. Found rather than assumed, so a banked
					-- or inverted section still fills the surface you meant.
					local topJ, topY = 1, -math.huge
					for j = 1, 4 do
						local y = (fa[j] + fa[j % 4 + 1]).Y * 0.5
						if y > topY then
							topY, topJ = y, j
						end
					end
					local j = topJ % 4 + 1
					emit(fa[topJ], fa[j], mate[j])
					emit(fa[topJ], mate[j], mate[topJ])
				else
					for j = 1, 4 do
						local k = j % 4 + 1
						emit(fa[j], fa[k], mate[k])
						emit(fa[j], mate[k], mate[j])
					end
				end
			end
		end

		if #created == 0 then
			ctx.status("Nothing to bridge — the parts may be touching already.")
			return nil
		end
		return created
	end

	local function previewBridge()
		if not ctx.visible() then
			return
		end
		local wedges = buildBridge()
		if wedges then
			ghost:showRaw(wedges)
			ctx.status(("Preview: %d gap(s), %d wedge(s)."):format(#Sel.parts(false) - 1, #wedges))
		else
			ghost:clear()
		end
	end

	Ui.button(bridgeSec, "Bridge the run", function()
		local picked = Sel.parts(false)
		local made = History.run("Bridge gaps", function()
			local wedges = buildBridge()
			if not wedges then
				return nil
			end
			for _, w in wedges do
				w.Parent = picked[1].Parent
			end
			return wedges
		end)
		if made then
			ghost:clear()
			Sel.set(made)
			ctx.status(("Bridged with %d wedge(s)."):format(#made), "ok")
		end
	end, nil, "primary")

	-- ONE PREVIEW HOOK FOR BOTH SECTIONS. Which one draws depends on how
	-- many parts are selected: 3 or 4 is ambiguous, so the corner fill
	-- wins there and the bridge takes everything else.
	Sel.changed(function()
		task.defer(function()
			local n = #Sel.parts(false)
			if n >= 3 and n <= 4 then
				preview()
			else
				previewBridge()
			end
		end)
	end)

	ctx.onHide(function()
		ghost:clear()
	end)
	ctx.onShow(preview)
end

return GapFill
