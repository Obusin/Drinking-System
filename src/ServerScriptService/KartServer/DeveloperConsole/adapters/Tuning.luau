--[[
	Tuning — live, bounded, REGISTERED value tweaking.

	NOT AN ATTRIBUTE EDITOR. The brief was explicit and it is the right
	call: `SetAnyAttribute(instance, name, value)` is arbitrary code
	execution wearing a friendly name. Only keys in TUNABLES below can be
	written, each with its own type, range and target.

	Adding a new live-tweakable is ONE ENTRY here. That is the whole
	point — the alternative is editing Config, restarting the server, and
	losing the state you were testing.

	WHY AN ATTRIBUTE AND NOT A CONFIG WRITE
	---------------------------------------
	Config modules are required once per machine. Writing `H.MaxSpeed` on
	the server changes the SERVER's copy and nothing else — every client
	keeps its own. An attribute on a replicated instance is the only
	change that actually reaches the machine doing the simulating, which
	for a player's kart is that player's client.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Names = require(BloxKart.Names)
local Protocol = require(BloxKart.DeveloperConsole.Protocol)

local KartService = require(script.Parent.Parent.Parent.KartService)

local Tuning = {}
local Code = Protocol.Code

-- key -> { attribute, min, max, default, scope, label }
--
-- `scope` is "kart" (per player) today. A "global" scope writing to a
-- replicated folder is the obvious next step and needs no change here
-- beyond the branch in `set`.
Tuning.TUNABLES = table.freeze({
	speed = {
		attribute = Names.DEV_SPEED_SCALE,
		-- Bounded hard. Below 0.1 the kart cannot climb its own ramps;
		-- above 5 the collision sweep starts stepping further per frame
		-- than StepHeight, and the kart tunnels through walls. Those are
		-- physical limits of the movement model, not taste.
		min = 0.1,
		max = 5,
		default = 1,
		scope = "kart",
		label = "Speed multiplier",
	},
})

function Tuning.list(): { any }
	local out = {}
	for key, t in Tuning.TUNABLES do
		table.insert(out, { key = key, min = t.min, max = t.max, default = t.default, label = t.label })
	end
	table.sort(out, function(a, b)
		return a.key < b.key
	end)
	return out
end

function Tuning.isKey(key: string): boolean
	--=====================================================================
--  TELEPORT
--
--  ASKS THE TARGET'S CLIENT, it does not move the kart.
--
--  FINDINGS is explicit: exactly one thing may own a part's position,
--  and writing the CFrame of a part you do not own creates a freeze
--  loop. A driven kart is owned by its player's client, so a server
--  PivotTo would be two owners fighting — the exact bug that produced
--  "it sinks then teleports".
--
--  So the server resolves the destination (which is the part a client
--  must not be trusted with) and pushes it. The client applies it
--  through Simulation:RespawnAt, the same call the existing respawn and
--  grid placement use.
--=====================================================================

local CollectionService = game:GetService("CollectionService")

function Tuning.resolveDestination(kind: string, index: number?, toUserId: number?): (CFrame?, string?)
	if kind == "player" then
		local other = toUserId and Players:GetPlayerByUserId(toUserId)
		local kart = other and KartService.kartFor(other)
		local hitbox = kart and kart.PrimaryPart
		if not hitbox then
			return nil, "That player has no kart to teleport to."
		end
		-- Beside and behind, so arriving does not put two karts in the
		-- same volume.
		return hitbox.CFrame * CFrame.new(8, 3, 6), nil
	end

	if kind == "checkpoint" then
		local Config = require(ReplicatedStorage.BloxKart.Config)
		local tagged = CollectionService:GetTagged(Config.Race.CheckpointTag)
		if #tagged == 0 then
			return nil, "This place has no tagged checkpoints."
		end
		-- Sorted by name so the order matches the one the race uses,
		-- rather than CollectionService's arbitrary ordering.
		table.sort(tagged, function(a, b)
			return a.Name < b.Name
		end)
		local n = math.clamp(index or 1, 1, #tagged)
		local cp = tagged[n]
        if not cp:IsA("BasePart") then
			return nil, "Checkpoint is not a part."
		end
		return cp.CFrame * CFrame.new(0, 4, 0), nil
	end

	return nil, "Unknown destination."
end

return Tuning.TUNABLES[key] ~= nil
end

function Tuning.set(targetUserId: number, key: string, value: number): (boolean, string, string, any?)
	local t = Tuning.TUNABLES[key]
	if not t then
		return false, Code.BAD_PAYLOAD, "Unknown tunable."
	end
	-- Re-clamped at the boundary. The validator already range-checked,
	-- and this must not depend on it having run.
	local clamped = math.clamp(value, t.min, t.max)

	local player = Players:GetPlayerByUserId(targetUserId)
	if not player then
		return false, Code.NOT_FOUND, "That player is not in this server."
	end
	local kart = KartService.kartFor(player)
	if not kart then
		return false, Code.NOT_FOUND, "That player has no kart right now."
	end

	kart:SetAttribute(t.attribute, clamped)
	return true, Code.OK, ("%s = %.2f for %s."):format(t.label, clamped, player.Name), { value = clamped }
end

-- Back to stock. Clearing the attribute rather than writing the default
-- so the kart is genuinely untouched again — a kart carrying an explicit
-- 1 and a kart with no override should not be distinguishable.
function Tuning.reset(targetUserId: number, key: string): (boolean, string, string)
	local t = Tuning.TUNABLES[key]
	if not t then
		return false, Code.BAD_PAYLOAD, "Unknown tunable."
	end
	local player = Players:GetPlayerByUserId(targetUserId)
	local kart = player and KartService.kartFor(player)
	if not kart then
		return false, Code.NOT_FOUND, "That player has no kart right now."
	end
	kart:SetAttribute(t.attribute, nil)
	return true, Code.OK, ("%s reset for %s."):format(t.label, player.Name)
end

return Tuning
