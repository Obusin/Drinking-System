--[[
	Ghost — see it before you build it.

	The difference between a tool you tune and a tool you gamble with. An
	arc you cannot see until you commit means place, look, undo, retype,
	place again. A ghost means you drag a slider and watch it.

	IT LIVES UNDER THE CAMERA, AND THAT IS THE WHOLE TRICK.
	------------------------------------------------------
	Anything parented to workspace.CurrentCamera renders normally but is
	NOT part of the saved place — it does not serialise, it does not
	appear in your published game, and Studio wipes it when you press
	play. So a preview cannot leak into the level no matter how the
	plugin exits, which is the one failure a preview system must not have.

	Contrast the obvious version: a folder in Workspace. That saves. Close
	Studio mid-preview and forty translucent cones are in the place file
	forever, and they look exactly like real ones.

	POOLED, NOT REBUILT. Sliders fire continuously while dragged, so
	rebuilding forty clones per frame would make the very control it
	exists to serve feel terrible. Existing ghosts are re-posed and only
	the difference is created or destroyed.

	COMMIT RE-CLONES FROM THE TEMPLATE rather than promoting the ghosts.
	Ghosts have had their transparency, collision and query flags
	rewritten; handing those to the user would mean the parts they get
	are subtly not the part they picked.
--]]

local Ghost = {}
Ghost.__index = Ghost

local ALPHA = 0.6

export type Ghost = typeof(setmetatable(
	{} :: {
		holder: Folder,
		items: { Instance },
		template: Instance?,
		poses: { CFrame },
	},
	Ghost
))

local function partsOf(inst: Instance): { BasePart }
	local out = {}
	if inst:IsA("BasePart") then
		table.insert(out, inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

local function setPivot(inst: Instance, cf: CFrame)
	if inst:IsA("BasePart") then
		inst.CFrame = cf
	elseif inst:IsA("Model") then
		inst:PivotTo(cf)
	end
end

-- Strips everything that would let a preview behave like a real object.
local function spectralise(inst: Instance)
	for _, part in partsOf(inst) do
		part.Transparency = part.Transparency + (1 - part.Transparency) * ALPHA
		part.CanCollide = false
		part.CanQuery = false -- so the brush and the mouse look straight through it
		part.CanTouch = false
		part.Anchored = true
		part.CastShadow = false
		part.Locked = true
	end
	-- A preview that could run code would be a preview with side effects.
	for _, d in inst:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy()
		end
	end
end

local PREFIX = "__ObuGhost_"

-- SWEEPS UP AFTER A PREVIOUS LIFE.
--
-- Rebuilding the plugin reloads it without running anything's cleanup,
-- so every `./build.sh` while a preview was on screen would strand a
-- holder under the Camera. They are invisible in the Explorer's usual
-- places and never referenced again, so they accumulate silently until
-- the viewport is full of translucent cones nothing owns.
--
-- Called once at startup, before any tool makes its own.
function Ghost.sweep()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	for _, child in camera:GetChildren() do
		if child:IsA("Folder") and child.Name:sub(1, #PREFIX) == PREFIX then
			child:Destroy()
		end
	end
end

function Ghost.new(name: string): Ghost
	local holder = Instance.new("Folder")
	holder.Name = PREFIX .. name
	-- Belt and braces on top of the Camera trick: Archivable false means
	-- it is skipped by Clone and by save even if it somehow moves.
	holder.Archivable = false
	holder.Parent = workspace.CurrentCamera

	return setmetatable({ holder = holder, items = {}, template = nil, poses = {} }, Ghost)
end

-- The one call a tool makes. Give it the template and where the copies
-- go; it works out what to create, move and destroy.
function Ghost:update(template: Instance?, poses: { CFrame })
	self.template = template
	self.poses = poses

	if not template or not template.Parent or #poses == 0 then
		self:clear()
		return
	end

	-- A changed template invalidates every existing ghost.
	if self.holder:GetAttribute("Source") ~= template:GetFullName() then
		self:clear()
		self.holder:SetAttribute("Source", template:GetFullName())
	end

	-- Grow.
	while #self.items < #poses do
		local clone = template:Clone()
		spectralise(clone)
		clone.Parent = self.holder
		table.insert(self.items, clone)
	end
	-- Shrink.
	while #self.items > #poses do
		local last = table.remove(self.items)
		if last then
			last:Destroy()
		end
	end
	-- Re-pose. The common path while a slider is moving: no allocation.
	for i, pose in poses do
		setPivot(self.items[i], pose)
	end
end

-- For tools whose output is not "N copies of one template" — GapFill
-- makes wedges whose sizes are all different, so there is nothing to
-- pose. It hands over finished instances and this takes ownership.
--
-- These are NOT committable: the caller rebuilds real ones from the same
-- inputs, for the same reason `commit` re-clones rather than promoting.
function Ghost:showRaw(instances: { Instance })
	self:clear()
	for _, inst in instances do
		spectralise(inst)
		inst.Parent = self.holder
		table.insert(self.items, inst)
	end
end

function Ghost:clear()
	for _, item in self.items do
		item:Destroy()
	end
	table.clear(self.items)
	self.holder:SetAttribute("Source", nil)
end

-- Real parts, from the template, at the poses the ghost is showing.
-- Returns them so the caller can select them.
function Ghost:commit(parent: Instance?): { Instance }
	local template = self.template
	if not template or not template.Parent then
		return {}
	end
	local made = {}
	for _, pose in self.poses do
		local clone = template:Clone()
		setPivot(clone, pose)
		clone.Parent = parent or template.Parent
		table.insert(made, clone)
	end
	return made
end

function Ghost:destroy()
	self:clear()
	self.holder:Destroy()
end

return Ghost
