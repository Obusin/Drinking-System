--[[
	Anchor — set AnchorPoint from a 3x3 grid, without the element jumping.

	AnchorPoint decides which part of the element sits at its Position.
	Changing it from (0,0) to (0.5,0.5) moves the element up and left by
	half its size, every time, and that jump is why people avoid touching
	it — even though centre-anchoring is exactly what you want for
	anything that has to sit in the middle of a phone screen.

	KEEP PUT compensates for it: shift Position by the same amount the
	anchor moved, and the element does not visibly move at all. You get
	the anchor you wanted and the layout you already had.

	    Position += (newAnchor - oldAnchor) * AbsoluteSize

	The compensation is written into the OFFSET component rather than the
	scale one, because it is a pixel quantity — it came from
	AbsoluteSize. Folding it into scale would be a different number on a
	different screen, which is the one thing this must not be.
--]]

local History = require(script.Parent.Parent.Core.History)
local Sel = require(script.Parent.Parent.Core.Sel)
local Theme = require(script.Parent.Parent.Core.Theme)
local Ui = require(script.Parent.Parent.Core.Ui)

local Anchor = {}

local POINTS = {
	{ 0, 0 },
	{ 0.5, 0 },
	{ 1, 0 },
	{ 0, 0.5 },
	{ 0.5, 0.5 },
	{ 1, 0.5 },
	{ 0, 1 },
	{ 0.5, 1 },
	{ 1, 1 },
}

function Anchor.build(page: Instance, ctx)
	local keepPut = true

	local sec = Ui.section(page, "Anchor point", "anchor1")
	Ui.label(sec, "Which part of the element sits at its position.", true)

	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, 0, 0, 96)
	grid.Parent = sec

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.32, 0, 0, 28)
	layout.CellPadding = UDim2.new(0.02, 0, 0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid


	local function apply(ax: number, ay: number)
		local objects = Sel.guis(false)
		if #objects == 0 then
			ctx.status("Nothing selected.")
			return
		end
		History.run("Set anchor point", function()
			for _, obj in objects do
				local old = obj.AnchorPoint
				local new = Vector2.new(ax, ay)
				if keepPut then
					local size = obj.AbsoluteSize
					local delta = new - old
					local p = obj.Position
					obj.Position = UDim2.new(
						p.X.Scale,
						math.round(p.X.Offset + delta.X * size.X),
						p.Y.Scale,
						math.round(p.Y.Offset + delta.Y * size.Y)
					)
				end
				obj.AnchorPoint = new
			end
		end)
		ctx.status(("Anchor set to (%.1f, %.1f) on %d."):format(ax, ay, #objects))
	end

	for i, point in POINTS do
		local button = Instance.new("TextButton")
		button.Text = ""
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.LayoutOrder = i
		button.Parent = grid

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = button

		-- A dot showing where the anchor lands on the box. Faster to read
		-- than nine labels saying "0, 0.5".
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(6, 6)
		dot.AnchorPoint = Vector2.new(point[1], point[2])
		dot.Position = UDim2.fromScale(point[1], point[2])
		dot.BorderSizePixel = 0
		dot.Parent = button

		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = UDim.new(1, 0)
		dotCorner.Parent = dot

		Theme.bind(button, function()
			button.BackgroundColor3 = Theme.color("Button")
			dot.BackgroundColor3 = Theme.ACCENT
		end)

		button.Activated:Connect(function()
			apply(point[1], point[2])
		end)
	end

	local keepBtn
	keepBtn = Ui.toggle(sec, "Keep it where it looks now", function()
		return keepPut
	end, function()
		keepPut = not keepPut
		Ui.repaint(keepBtn)
	end)

	--== CENTRING ======================================================
	local centre = Ui.section(page, "Centre", "anchor2")
	Ui.label(centre, "Anchor to the middle and move to the middle of the parent, in one go.", true)
	Ui.button(centre, "Centre in parent", function()
		local objects = Sel.guis(false)
		if #objects == 0 then
			ctx.status("Nothing selected.")
			return
		end
		History.run("Centre in parent", function()
			for _, obj in objects do
				obj.AnchorPoint = Vector2.new(0.5, 0.5)
				obj.Position = UDim2.fromScale(0.5, 0.5)
			end
		end)
		ctx.status(("Centred %d."):format(#objects))
	end)

	local axis = Ui.row(centre)
	Ui.button(axis, "Centre X", function()
		History.run("Centre X", function()
			for _, obj in Sel.guis(false) do
				obj.AnchorPoint = Vector2.new(0.5, obj.AnchorPoint.Y)
				obj.Position = UDim2.new(0.5, 0, obj.Position.Y.Scale, obj.Position.Y.Offset)
			end
		end)
	end, 0.5)
	Ui.button(axis, "Centre Y", function()
		History.run("Centre Y", function()
			for _, obj in Sel.guis(false) do
				obj.AnchorPoint = Vector2.new(obj.AnchorPoint.X, 0.5)
				obj.Position = UDim2.new(obj.Position.X.Scale, obj.Position.X.Offset, 0.5, 0)
			end
		end)
	end, 0.5)
end

return Anchor
