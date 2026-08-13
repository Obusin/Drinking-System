--[[ Rainbow — player-driven rainbow boost with ramp-aware speed control. ]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))
local Items = require(BloxKart:WaitForChild("Items"))

local Rainbow = {}
Rainbow.__index = Rainbow

local function rampAhead(sim, range: number): boolean
	for _, tag in { Config.Trick.RampTag, Config.Glide.RampTag } do
		for _, ramp in CollectionService:GetTagged(tag) do
			if ramp:IsA("BasePart") then
				local delta = ramp.Position - sim.pos
				-- Only ramps genuinely in front matter. A ramp beside/behind
				-- the kart must not mysteriously cut the boost.
				if delta:Dot(sim.forward) > 0 and delta.Magnitude <= range then
					return true
				end
			end
		end
	end
	return false
end

function Rainbow.new(kart: Model)
	return setmetatable({ kart = kart, item = Items.byId("Rainbow"), active = false }, Rainbow)
end

-- Rainbow deliberately has NO route follower. The player retains throttle,
-- braking, steering, drift, ramps and all normal physics; this module only
-- refreshes a short external boost while the server-authorized state lives.
function Rainbow:Update(sim, _dt: number): boolean
	local untilAt = self.kart:GetAttribute(Names.RAINBOW_UNTIL)
	local active = self.kart:GetAttribute(Names.RAINBOW_ACTIVE) == true
	if not active or typeof(untilAt) ~= "number" or workspace:GetServerTimeNow() >= untilAt then
		self.active = false
		sim:SetGuide(nil) -- clears any guide left by an older activation
		return false
	end
	if not self.item then return false end
	self.active = true
	sim:SetGuide(nil)

	if rampAhead(sim, self.item.RampApproach) then
		-- Let the authored ramp own the launch. A hard cap gives its lift
		-- room to work and prevents a 190-speed approach from overshooting.
		if sim.speed > self.item.RampSpeed then
			sim.speed = self.item.RampSpeed
		end
	else
		-- A brief refresh, not a second movement system. Releasing throttle
		-- and steering still behave exactly as normal Simulation controls.
		sim:ApplyBoost(self.item.DriveSpeed, self.item.BoostRefresh)
	end
	return true
end

function Rainbow:Destroy() end

return Rainbow
