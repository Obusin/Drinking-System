--[[
	Sel — what you have selected, filtered to what a tool can act on.

	Two things worth knowing:

	INCLUDE DESCENDANTS IS THE DEFAULT FOR UI, and it has to be. You
	select a frame and mean "this and everything in it" — converting one
	element to scale while its children stay in offset is the exact
	half-done state that makes people give up on scaling their UI.

	ORDER IS THE ORDER YOU PICKED THEM. Selection:Get() preserves it, and
	tools like the arc and the triangle fill genuinely depend on that:
	"first, second, third" is how you say which corner is which.
--]]

local Selection = game:GetService("Selection")

local Sel = {}

function Sel.get(): { Instance }
	return Selection:Get()
end

-- Everything selected that is a `class`, optionally including
-- descendants. Never returns duplicates even if you selected a parent
-- and its child.
function Sel.ofClass(class: string, deep: boolean?): { Instance }
	local seen, out = {}, {}
	local function add(inst: Instance)
		if inst:IsA(class) and not seen[inst] then
			seen[inst] = true
			table.insert(out, inst)
		end
	end
	for _, inst in Selection:Get() do
		add(inst)
		if deep then
			for _, d in inst:GetDescendants() do
				add(d)
			end
		end
	end
	return out
end

function Sel.parts(deep: boolean?): { BasePart }
	return (Sel.ofClass("BasePart", deep) :: any) :: { BasePart }
end

function Sel.guis(deep: boolean?): { GuiObject }
	return (Sel.ofClass("GuiObject", deep) :: any) :: { GuiObject }
end

function Sel.set(list: { Instance })
	Selection:Set(list)
end

function Sel.changed(fn: () -> ()): RBXScriptConnection
	return Selection.SelectionChanged:Connect(fn)
end

-- The centre and extents of a set of parts, in world space. Used by
-- align, distribute and the arc pivot.
function Sel.bounds(parts: { BasePart }): (Vector3, Vector3)
	if #parts == 0 then
		return Vector3.zero, Vector3.zero
	end
	local min, max = parts[1].Position, parts[1].Position
	for _, part in parts do
		local half = part.Size / 2
		min = min:Min(part.Position - half)
		max = max:Max(part.Position + half)
	end
	return (min + max) / 2, max - min
end

return Sel
