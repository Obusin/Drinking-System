--[[
	Align — line things up and space them evenly.

	The most-used tool in any building suite and the least interesting to
	write. Two operations:

	ALIGN moves every selected part so it shares an edge or a centre with
	the group's bounding box on one axis.

	DISTRIBUTE spreads them evenly between the two outermost, which are
	left alone — they define the span, so moving them would change the
	thing being divided.

	BOTH USE POSITION, NOT CFRAME, so a rotated part keeps its rotation.
	Aligning should never quietly straighten something.
--]]

local History = require(script.Parent.Parent.Core.History)
local Sel = require(script.Parent.Parent.Core.Sel)
local Ui = require(script.Parent.Parent.Core.Ui)

local Align = {}

-- AN ARRAY, NOT A DICTIONARY. `{ X = 1, Y = 2, Z = 3 }` iterates in hash
-- order, so the three panels came out in a different order on every
-- launch — which reads as the plugin being broken long before anyone
-- works out it is only cosmetic. Order in a UI is information.
local AXES = {
	{ name = "X", index = 1 },
	{ name = "Y", index = 2 },
	{ name = "Z", index = 3 },
}

local function component(v: Vector3, axis: number): number
	return if axis == 1 then v.X elseif axis == 2 then v.Y else v.Z
end

local function withComponent(v: Vector3, axis: number, value: number): Vector3
	if axis == 1 then
		return Vector3.new(value, v.Y, v.Z)
	elseif axis == 2 then
		return Vector3.new(v.X, value, v.Z)
	end
	return Vector3.new(v.X, v.Y, value)
end

-- mode: "min" | "centre" | "max"
local function alignTo(parts: { BasePart }, axis: number, mode: string)
	if #parts < 2 then
		return 0
	end

	local lo, hi = math.huge, -math.huge
	for _, part in parts do
		local half = component(part.Size, axis) / 2
		local centre = component(part.Position, axis)
		lo = math.min(lo, centre - half)
		hi = math.max(hi, centre + half)
	end

	for _, part in parts do
		local half = component(part.Size, axis) / 2
		local target
		if mode == "min" then
			target = lo + half
		elseif mode == "max" then
			target = hi - half
		else
			target = (lo + hi) / 2
		end
		part.Position = withComponent(part.Position, axis, target)
	end
	return #parts
end

local function distribute(parts: { BasePart }, axis: number)
	if #parts < 3 then
		return 0
	end
	local sorted = table.clone(parts)
	table.sort(sorted, function(a, b)
		return component(a.Position, axis) < component(b.Position, axis)
	end)

	-- The ends define the span and are deliberately untouched.
	local first = component(sorted[1].Position, axis)
	local last = component(sorted[#sorted].Position, axis)
	local step = (last - first) / (#sorted - 1)

	for i = 2, #sorted - 1 do
		sorted[i].Position = withComponent(sorted[i].Position, axis, first + step * (i - 1))
	end
	return #sorted - 2
end

function Align.build(page: Instance, ctx)

	for _, entry in AXES do
		local name, axis = entry.name, entry.index
		-- Keyed BY AXIS. One shared key meant collapsing X collapsed all
		-- three, since they are the same call site in a loop.
		local sec = Ui.section(page, name .. " axis", "align_" .. name)
		local row = Ui.row(sec)
		for _, mode in { "min", "centre", "max" } do
			Ui.button(row, mode, function()
				local parts = Sel.parts(true)
				if #parts < 2 then
					ctx.status("Select at least two parts.")
					return
				end
				local n = History.run(("Align %s %s"):format(name, mode), function()
					return alignTo(parts, axis, mode)
				end) or 0
				ctx.status(("Aligned %d on %s."):format(n, name))
			end, 1 / 3)
		end
		Ui.button(sec, "Distribute evenly", function()
			local parts = Sel.parts(true)
			if #parts < 3 then
				ctx.status("Distributing needs at least three parts.")
				return
			end
			local n = History.run("Distribute " .. name, function()
				return distribute(parts, axis)
			end) or 0
			ctx.status(("Spaced %d evenly on %s."):format(n, name))
		end)
	end
end

return Align
