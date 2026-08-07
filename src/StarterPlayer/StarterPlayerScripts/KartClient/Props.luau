--[[
	Props — knock the scenery over. Client-local, cosmetic, safe.

	THE TRAP THIS AVOIDS
	--------------------
	The obvious build is "make the prop CanCollide false and let the kart
	push it". That does not work here for two reasons, and both are
	load-bearing:

	  1. CanCollide is not the flag. Movement in this game is QUERY based
	     — Simulation sweeps with a Blockcast — so a part with CanCollide
	     false and CanQuery TRUE is still a solid wall to the kart. A cone
	     would stop you dead while looking like it should not.

	  2. The kart is kinematic. There is no force to transfer, so nothing
	     would be "pushed" even if it could be.

	So a prop is made NON-QUERYABLE — invisible to movement entirely —
	and the hit is detected here by distance. The prop never affects
	handling, and the collision you appear to have is the animation.

	ANCHORED THROUGHOUT. Nothing is unanchored, so Roblox physics is
	never involved and cannot fight anyone for ownership. The arc is
	integrated here, the same way the kart's is.

	LOCAL ONLY. Your client animates it; other players do not see your
	cone fly. Same trade the drift sparks already make. A prop is scenery,
	and scenery disagreeing between clients costs nothing — whereas
	replicating every cone would cost a great deal.

	WRITES CFRAME ON A PART THE SERVER NEVER TOUCHES. That is what makes
	the local write safe: with no second writer there is nothing to fight,
	which is the same rule the kart's own ownership follows.

	TAG THE MODEL OR TAG THE PART — BOTH WORK.
	------------------------------------------
	A cone is almost always a Model, and tagging the Model is the natural
	thing to do. The first version only accepted BaseParts, so a tagged
	Model was skipped silently and nothing ever flew.

	A tagged unit is now whatever you tagged: a Model moves by PivotTo and
	a bare part by CFrame. Every BasePart underneath is made
	non-queryable either way, because it only takes ONE queryable part in
	a model to turn the whole cone back into a wall.
--]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Util = require(BloxKart:WaitForChild("Util"))

local P = Config.Props
local log = Util.logger("Props", P.Debug)

local Props = {}
Props.__index = Props

-- A tagged unit is a Model or a BasePart. These three functions are the
-- only places that care which, so nothing else has to branch.
local function pivotOf(unit: Instance): CFrame?
	if unit:IsA("Model") then
		local ok, cf = pcall(unit.GetPivot, unit)
		return if ok then cf else nil
	elseif unit:IsA("BasePart") then
		return unit.CFrame
	end
	return nil
end

local function setPivot(unit: Instance, cf: CFrame)
	if unit:IsA("Model") then
		unit:PivotTo(cf)
	elseif unit:IsA("BasePart") then
		unit.CFrame = cf
	end
end

-- Every BasePart under the unit. ONE queryable part is enough to turn a
-- cone back into a wall, so this has to reach all of them.
local function partsOf(unit: Instance): { BasePart }
	local out = {}
	if unit:IsA("BasePart") then
		table.insert(out, unit)
	end
	for _, d in unit:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

function Props.new()
	local self = setmetatable({
		flying = {}, -- unit -> { home, vel, spin, at }
		known = {}, -- unit -> true
		conns = {},
	}, Props)

	local function adopt(unit: Instance)
		if self.known[unit] then
			return
		end
		if not (unit:IsA("Model") or unit:IsA("BasePart")) then
			warn(("[Props] %s is tagged %q but is a %s — tag a Model or a BasePart."):format(
				unit:GetFullName(),
				P.Tag,
				unit.ClassName
			))
			return
		end
		local parts = partsOf(unit)
		if #parts == 0 then
			warn(("[Props] %s is tagged %q but has no BaseParts."):format(unit:GetFullName(), P.Tag))
			return
		end
		self.known[unit] = true
		for _, part in parts do
			if P.ForceNonQueryable then
				-- THE IMPORTANT LINE. Movement is query-based, so without
				-- this the sweep treats a cone as a wall and the kart
				-- stops dead against scenery.
				part.CanQuery = false
				part.CanCollide = false
			end
			part.Anchored = true
		end
		log("adopted %s (%d part(s))", unit:GetFullName(), #parts)
	end

	for _, unit in CollectionService:GetTagged(P.Tag) do
		adopt(unit)
	end
	table.insert(self.conns, CollectionService:GetInstanceAddedSignal(P.Tag):Connect(adopt))
	table.insert(
		self.conns,
		CollectionService:GetInstanceRemovedSignal(P.Tag):Connect(function(unit)
			self.known[unit] = nil
			self.flying[unit] = nil
		end)
	)

	return self
end

-- Called every frame with the live simulation.
--
-- `sim` may be nil (on foot, spectating) — flying props still need
-- stepping, so an arc continues rather than freezing mid-air.
function Props:Update(sim, dt: number)
	local now = os.clock()

	if sim and sim.pos then
		local speedFrac = math.clamp(math.abs(sim.speed) / Config.Handling.MaxSpeed, 0, 1)

		for unit in self.known do
			if unit.Parent and not self.flying[unit] then
				local cf = pivotOf(unit)
				if cf and (cf.Position - sim.pos).Magnitude < P.HitRadius then
					-- LAUNCHED ALONG TRAVEL, not along the offset from the
					-- kart. A cone should go where you were going; using
					-- the offset would fire it sideways whenever you
					-- clipped one with a corner of the kart.
					local power = P.MinLaunch + (P.MaxLaunch - P.MinLaunch) * speedFrac
					local dir = sim.travel
					if dir.Magnitude < 1e-3 then
						dir = sim.forward
					end
					self.flying[unit] = {
						home = cf,
						vel = dir.Unit * power + sim.up * (power * P.Lift),
						spin = Vector3.new(
							(math.random() - 0.5) * 2 * P.Spin,
							(math.random() - 0.5) * 2 * P.Spin,
							(math.random() - 0.5) * 2 * P.Spin
						),
						at = now,
					}
					log("flung %s at %.0f studs/s", unit.Name, power)
				end
			end
		end
	end

	-- Step everything in the air, whether or not there is a kart.
	for unit, state in self.flying do
		if not unit.Parent then
			self.flying[unit] = nil
			continue
		end
		local age = now - state.at
		local cf = pivotOf(unit)
		if not cf then
			self.flying[unit] = nil
			continue
		end

		if age >= P.RestoreAfter then
			-- EASED HOME, not snapped. A cone that teleports back reads as
			-- a glitch; one that settles reads as the track tidying itself
			-- up. This is what makes it a temporary knock rather than a
			-- track that erodes over a session.
			local t = math.clamp((age - P.RestoreAfter) / math.max(P.FadeBack, 1e-3), 0, 1)
			setPivot(unit, cf:Lerp(state.home, t))
			if t >= 1 then
				setPivot(unit, state.home)
				self.flying[unit] = nil
			end
			continue
		end

		state.vel -= Vector3.new(0, P.Gravity, 0) * dt
		local rot = cf - cf.Position
		setPivot(
			unit,
			CFrame.new(cf.Position + state.vel * dt)
				* rot
				* CFrame.Angles(state.spin.X * dt, state.spin.Y * dt, state.spin.Z * dt)
		)
	end
end

function Props:Destroy()
	for _, c in self.conns do
		c:Disconnect()
	end
	-- Put everything back, so leaving does not leave the scenery
	-- scattered for whoever looks at it next.
	for unit, state in self.flying do
		if unit.Parent then
			setPivot(unit, state.home)
		end
	end
	table.clear(self.flying)
	table.clear(self.known)
end

return Props
