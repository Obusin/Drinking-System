--[[
	Scaler — offset to scale, which is the whole mobile problem.

	WHY THIS MATTERS MORE THAN IT SOUNDS
	------------------------------------
	A UI laid out in OFFSET is laid out in pixels. It looks right on the
	monitor you built it on and wrong on every phone, because the phone
	has a different number of pixels — the button does not shrink, the
	screen does. A UI laid out in SCALE is a fraction of its parent, so it
	is the same proportion of every screen.

	The conversion is one line of arithmetic and everybody does it by
	hand, badly, one element at a time. That is all this is, applied to a
	whole tree at once.

	THE ARITHMETIC, BECAUSE IT IS WORTH KNOWING
	-------------------------------------------
	A UDim is {Scale, Offset}. To convert, fold the offset into the scale
	using the PARENT's absolute size:

	    newScale = scale + offset / parentAbsoluteSize

	That works regardless of AnchorPoint, layout, or how the two units
	were already mixed — it is the same total, expressed in one unit
	instead of two. It is not an approximation.

	IT RUNS BOTTOM-UP. Converting a parent changes its children's
	absolute sizes, so converting a parent first and a child second would
	measure the child against a parent that had already moved. Deepest
	first means every element is measured against a parent that has not
	been touched yet.
--]]

local History = require(script.Parent.Parent.Core.History)
local Sel = require(script.Parent.Parent.Core.Sel)
local Ui = require(script.Parent.Parent.Core.Ui)

local Scaler = {}

local function depth(inst: Instance): number
	local n, cur = 0, inst
	while cur.Parent do
		n += 1
		cur = cur.Parent
	end
	return n
end

-- Deepest first. See the note above — this ordering is load-bearing.
local function bottomUp(list: { GuiObject }): { GuiObject }
	local sorted = table.clone(list)
	table.sort(sorted, function(a, b)
		return depth(a) > depth(b)
	end)
	return sorted
end

local function parentSize(obj: GuiObject): Vector2?
	local parent = obj.Parent
	if not parent or not parent:IsA("GuiBase2d") then
		return nil
	end
	local size = (parent :: any).AbsoluteSize
	-- A zero-sized parent makes the division meaningless. Skipped rather
	-- than guessed at: a NaN written into a UDim2 is unrecoverable and
	-- does not look like a bug until much later.
	if size.X < 1 or size.Y < 1 then
		return nil
	end
	return size
end

local function convert(objects: { GuiObject }, toScale: boolean, doSize: boolean, doPos: boolean): number
	local touched = 0
	for _, obj in bottomUp(objects) do
		local ps = parentSize(obj)
		if not ps then
			continue
		end

		if doSize then
			local s = obj.Size
			obj.Size = if toScale
				then UDim2.fromScale(s.X.Scale + s.X.Offset / ps.X, s.Y.Scale + s.Y.Offset / ps.Y)
				else UDim2.fromOffset(
					math.round(s.X.Scale * ps.X + s.X.Offset),
					math.round(s.Y.Scale * ps.Y + s.Y.Offset)
				)
		end

		if doPos then
			local p = obj.Position
			obj.Position = if toScale
				then UDim2.fromScale(p.X.Scale + p.X.Offset / ps.X, p.Y.Scale + p.Y.Offset / ps.Y)
				else UDim2.fromOffset(
					math.round(p.X.Scale * ps.X + p.X.Offset),
					math.round(p.Y.Scale * ps.Y + p.Y.Offset)
				)
		end

		touched += 1
	end
	return touched
end

function Scaler.build(page: Instance, ctx)
	local deep = true
	local doSize, doPos = true, true

	local sec = Ui.section(page, "Scale", "scale1")
	Ui.label(sec, "Folds pixel offsets into scale so the UI keeps its proportions on every screen.", true)

	local opts = Ui.section(page, "Apply to", "scale2")
	local deepBtn, sizeBtn, posBtn

	deepBtn = Ui.toggle(opts, "Include children", function()
		return deep
	end, function()
		deep = not deep
		Ui.repaint(deepBtn)
	end)

	local pair = Ui.row(opts)
	sizeBtn = Ui.toggle(pair, "Size", function()
		return doSize
	end, function()
		doSize = not doSize
		Ui.repaint(sizeBtn)
	end, 0.5)
	posBtn = Ui.toggle(pair, "Position", function()
		return doPos
	end, function()
		doPos = not doPos
		Ui.repaint(posBtn)
	end, 0.5)


	local function run(toScale: boolean)
		local objects = Sel.guis(deep)
		if #objects == 0 then
			ctx.status("Nothing selected that has a size.")
			return
		end
		if not doSize and not doPos then
			ctx.status("Turn on Size or Position first.")
			return
		end
		local n = History.run("Convert UI units", function()
			return convert(objects, toScale, doSize, doPos)
		end) or 0
		ctx.status(
			("%d converted to %s%s."):format(
				n,
				if toScale then "scale" else "offset",
				if n < #objects then (", %d skipped"):format(#objects - n) else ""
			),
			if n > 0 then "ok" else "warn"
		)
	end

	local convertRow = Ui.section(page, "Convert", "scale3")
	local buttons = Ui.row(convertRow, 28)
	Ui.button(buttons, "→ Scale", function()
		run(true)
	end, 0.5, "primary")
	Ui.button(buttons, "→ Offset", function()
		run(false)
	end, 0.5)

	--== ASPECT RATIO ==================================================
	local aspect = Ui.section(page, "Aspect ratio", "scale4")
	Ui.label(
		aspect,
		"Locks the shape so it cannot stretch on a different screen. Ratio is measured from how it looks now.",
		true
	)
	Ui.button(aspect, "Lock current ratio", function()
		local objects = Sel.guis(deep)
		if #objects == 0 then
			ctx.status("Nothing selected.")
			return
		end
		local n = History.run("Lock aspect ratio", function()
			local count = 0
			for _, obj in objects do
				local size = obj.AbsoluteSize
				if size.X < 1 or size.Y < 1 then
					continue
				end
				local existing = obj:FindFirstChildOfClass("UIAspectRatioConstraint")
				local constraint = existing or Instance.new("UIAspectRatioConstraint")
				constraint.AspectRatio = size.X / size.Y
				constraint.Parent = obj
				count += 1
			end
			return count
		end) or 0
		ctx.status(("Locked %d ratio(s)."):format(n))
	end)
	Ui.button(aspect, "Remove ratio locks", function()
		local objects = Sel.guis(deep)
		local n = History.run("Remove aspect ratio", function()
			local count = 0
			for _, obj in objects do
				local existing = obj:FindFirstChildOfClass("UIAspectRatioConstraint")
				if existing then
					existing:Destroy()
					count += 1
				end
			end
			return count
		end) or 0
		ctx.status(("Removed %d."):format(n))
	end)

	--== TEXT ==========================================================
	-- TextScaled alone gives you text that is enormous on a big screen.
	-- The size constraint is what makes it usable, which is why these are
	-- one button and not two.
	local text = Ui.section(page, "Text", "scale5")
	Ui.label(text, "Scaled text with a ceiling, so it shrinks on phones without ballooning on monitors.", true)

	-- `Ui.slider`, not `Ui.number` — there has never been a `Ui.number`,
	-- and calling it threw on the plugin's FIRST BUILD, which is why the
	-- whole window failed to open rather than just this row.
	local maxSize = 32
	Ui.slider(text, "Max text size", 8, 96, maxSize, 1, function(v)
		maxSize = math.max(1, math.floor(v))
	end)

	Ui.button(text, "Make text responsive", function()
		local labels = {}
		for _, obj in Sel.guis(deep) do
			if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
				table.insert(labels, obj)
			end
		end
		if #labels == 0 then
			ctx.status("No text objects selected.")
			return
		end
		History.run("Responsive text", function()
			for _, obj in labels do
				local writable = obj :: any
				writable.TextScaled = true
				local existing = obj:FindFirstChildOfClass("UITextSizeConstraint")
				local constraint = existing or Instance.new("UITextSizeConstraint")
				constraint.MaxTextSize = maxSize
				constraint.Parent = obj
			end
		end)
		ctx.status(("%d text object(s) set to scale, capped at %d."):format(#labels, maxSize))
	end)
end

return Scaler
