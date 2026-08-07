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

function Props.new()
	local self = setmetatable({
		-- part -> { home = CFrame, vel = Vector3, spin = Vector3, at = number }
		flying = {},
		known = {},
		conns = {},
	}, Props)

	local function adopt(part: Instance)
		if not part:IsA("BasePart") or self.known[part] then
			return
		end
		self.known[part] = true
		if P.ForceNonQueryable then
			-- THE IMPORTANT LINE. Without it the sweep treats a cone as a
			-- wall and the kart stops dead against scenery.
			part.CanQuery = false
			part.CanCollide = false
		end
		part.Anchored = true
	end

	for _, part in CollectionService:GetTagged(P.Tag) do
		adopt(part)
	end
	table.insert(self.conns, CollectionService:GetInstanceAddedSignal(P.Tag):Connect(adopt))
	table.insert(
		self.conns,
		CollectionService:GetInstanceRemovedSignal(P.Tag):Connect(function(part)
			self.known[part] = nil
			self.flying[part] = nil
		end)
	)

	return self
end

-- Called every frame with the live simulation.
--
-- `sim` may be nil (on foot, spectating) — the flying props still need
-- stepping, so the arc continues rather than freezing mid-air.
function Props:Update(sim, dt: number)
	local now = os.clock()

	if sim and sim.pos then
		local speedFrac = math.clamp(math.abs(sim.speed) / Config.Handling.MaxSpeed, 0, 1)
		local radiusSq = P.HitRadius * P.HitRadius

		for part in self.known do
			if part.Parent and not self.flying[part] then
				local toward = part.Position - sim.pos
				if toward.Magnitude * toward.Magnitude < radiusSq or toward.Magnitude < P.HitRadius then
					-- LAUNCHED ALONG TRAVEL, not along the offset from the
					-- kart. A cone should go where you were going; using
					-- the offset would fire it sideways whenever you
					-- clipped one with a corner of the kart.
					local power = P.MinLaunch + (P.MaxLaunch - P.MinLaunch) * speedFrac
					local dir = sim.travel
					if dir.Magnitude < 1e-3 then
						dir = sim.forward
					end
					local vel = dir.Unit * power + sim.up * (power * P.Lift)

					self.flying[part] = {
						home = part.CFrame,
						vel = vel,
						spin = Vector3.new(
							(math.random() - 0.5) * 2 * P.Spin,
							(math.random() - 0.5) * 2 * P.Spin,
							(math.random() - 0.5) * 2 * P.Spin
						),
						at = now,
					}
					log("knocked %s at %.0f studs/s", part.Name, power)
				end
			end
		end
	end

	-- Step everything in the air, whether or not there is a kart.
	for part, state in self.flying do
		if not part.Parent then
			self.flying[part] = nil
			continue
		end
		local age = now - state.at

		if age >= P.RestoreAfter then
			-- EASED HOME, not snapped. A cone that teleports back reads
			-- as a glitch; one that settles reads as the track tidying
			-- itself up.
			local t = math.clamp((age - P.RestoreAfter) / math.max(P.FadeBack, 1e-3), 0, 1)
			part.CFrame = part.CFrame:Lerp(state.home, t)
			if t >= 1 then
				part.CFrame = state.home
				self.flying[part] = nil
			end
			continue
		end

		state.vel -= Vector3.new(0, P.Gravity, 0) * dt
		part.CFrame = CFrame.new(part.Position + state.vel * dt)
			* (part.CFrame - part.CFrame.Position)
			* CFrame.Angles(state.spin.X * dt, state.spin.Y * dt, state.spin.Z * dt)
	end
end

function Props:Destroy()
	for _, c in self.conns do
		c:Disconnect()
	end
	-- Put everything back, so leaving a race does not leave the scenery
	-- scattered for whoever looks at it next.
	for part, state in self.flying do
		if part.Parent then
			part.CFrame = state.home
		end
	end
	table.clear(self.flying)
	table.clear(self.known)
end

return Props
