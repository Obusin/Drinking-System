--[[
	TagZones — "did the kart drive through a part with this tag?"

	Shared by boost pads and race triggers, because both are the same
	problem: non-collidable parts you drive THROUGH.

	Why an overlap query rather than .Touched or collision:
	  - the parts are CanCollide = false, so there is no collision
	  - the kart's hitbox is CFrame-driven every frame rather than
	    physically simulated, and .Touched fires unreliably for parts
	    that teleport

	An Include-filtered GetPartBoundsInBox is deterministic, frame-rate
	independent, and doesn't care about either.
--]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Read straight from Config rather than through Triggers, which requires
-- this module's siblings and would make the graph circular.
local SURFACE_TAG = require(ReplicatedStorage:WaitForChild("BloxKart"):WaitForChild("Config")).Race.SurfaceTag

local TagZones = {}
TagZones.__index = TagZones

export type Options = {
	cooldown: number?, -- per-part retrigger guard, seconds
	maxParts: number?,
	forceQueryable: boolean?,
}

function TagZones.new(tag: string, opts: Options?)
	local o = opts or {}
	local self = setmetatable({
		tag = tag,
		cooldown = o.cooldown or 0.5,
		forceQueryable = o.forceQueryable ~= false,
		parts = {},
		lastHit = {},
		connections = {},
		params = OverlapParams.new(),
	}, TagZones)

	self.params.FilterType = Enum.RaycastFilterType.Include
	self.params.MaxParts = o.maxParts or 4

	local function add(inst: Instance)
		if not inst:IsA("BasePart") then
			return
		end
		-- A trigger authored with CanQuery off is invisible to spatial
		-- queries and would silently do nothing. Local-only fix.
		if self.forceQueryable then
			inst.CanQuery = true
		end

		-- And a trigger authored SOLID is a wall.
		--
		-- Our own movement ignores these — WorldFilter filters them out —
		-- but Roblox physics doesn't, and anything physically simulated
		-- gets caught on them: an unanchored bot kart, a seated rig's
		-- limbs, a player on foot. A fresh Part defaults to CanCollide on,
		-- so this is the state a checkpoint is in unless somebody
		-- remembered to turn it off.
		--
		-- Except a road that's also a trigger, which is solid on purpose.
		if not CollectionService:HasTag(inst, SURFACE_TAG) then
			inst.CanCollide = false
		end
		table.insert(self.parts, inst)
		self.params.FilterDescendantsInstances = self.parts
	end

	local function remove(inst: Instance)
		local i = table.find(self.parts, inst)
		if i then
			table.remove(self.parts, i)
			self.params.FilterDescendantsInstances = self.parts
			self.lastHit[inst] = nil
		end
	end

	for _, inst in CollectionService:GetTagged(tag) do
		add(inst)
	end
	table.insert(self.connections, CollectionService:GetInstanceAddedSignal(tag):Connect(add))
	table.insert(self.connections, CollectionService:GetInstanceRemovedSignal(tag):Connect(remove))

	return self
end

function TagZones:isEmpty(): boolean
	return #self.parts == 0
end

-- Returns the part we just entered, or nil. Respects the per-part
-- cooldown, so sitting on a trigger fires once rather than every frame.
function TagZones:Touch(cf: CFrame, size: Vector3): BasePart?
	if #self.parts == 0 then
		return nil
	end
	local now = os.clock()
	for _, part in workspace:GetPartBoundsInBox(cf, size, self.params) do
		local last = self.lastHit[part]
		if not last or now - last >= self.cooldown then
			self.lastHit[part] = now
			return part
		end
	end
	return nil
end

-- Every tagged part currently overlapping, ignoring cooldowns.
--
-- Touch() answers "which trigger did I just enter", which is right for a
-- boost pad but wrong when the caller needs a SPECIFIC part: it returns
-- whichever the spatial query happened to list first and consumes that
-- part's cooldown doing it.
--
-- Checkpoints need this instead. When the road segments themselves are
-- the checkpoints you overlap one continuously and two at every seam, so
-- "whichever came back first" is a coin flip between the one you just
-- left and the one you want.
function TagZones:Overlapping(cf: CFrame, size: Vector3): { BasePart }
	if #self.parts == 0 then
		return {}
	end
	return workspace:GetPartBoundsInBox(cf, size, self.params)
end

function TagZones:Destroy()
	for _, conn in self.connections do
		conn:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.parts)
	table.clear(self.lastHit)
end

return TagZones
