--[[
	Boosters — speed pads.

	Tag a part in Studio's Tag Editor and driving over it fires a boost.
	No per-pad scripts. Detection is TagZones — see there for why it's an
	overlap query and not .Touched.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")

local Config = require(BloxKart:WaitForChild("Config"))
local TagZones = require(BloxKart:WaitForChild("TagZones"))

local B = Config.Boosters

local Boosters = {}
Boosters.__index = Boosters

function Boosters.new()
	local self = setmetatable({
		pads = {},
		nextAllowed = 0,
	}, Boosters)

	for _, def in B.Pads do
		table.insert(self.pads, {
			def = def,
			zone = TagZones.new(def.Tag, {
				cooldown = B.Cooldown,
				forceQueryable = B.ForceQueryable,
			}),
		})
	end

	return self
end

-- Returns the pad definition we just drove into, or nil.
function Boosters:Check(sim)
	local now = os.clock()
	if now < self.nextAllowed then
		return nil
	end

	local cf, size = sim.hitbox.CFrame, sim.hitbox.Size
	for _, entry in self.pads do
		if entry.zone:Touch(cf, size) then
			-- Global guard, so a row of overlapping pads can't stack
			-- into one enormous boost.
			self.nextAllowed = now + B.GlobalCooldown
			return entry.def
		end
	end
	return nil
end

function Boosters:Destroy()
	for _, entry in self.pads do
		entry.zone:Destroy()
	end
	table.clear(self.pads)
end

return Boosters
