--[[
	Economy — currency, THROUGH the module that owns it.

	IT DOES NOT WRITE `data.bolt`, AND THAT IS THE WHOLE POINT.
	----------------------------------------------------------
	DataService's own header is explicit:

	    "Progress owns balances and is the only thing that changes one;
	     this owns loading, saving and the shape of the record. Two
	     modules that both write a balance is the dupe this whole design
	     exists to avoid."

	A console that set `data.bolt` directly would be exactly that second
	writer. It would also skip the Ledger, so a developer-granted balance
	would be the one transaction in the game with no row behind it —
	invisible in an audit precisely where an audit matters most.

	So this calls `Progress.grant` and `Progress.spend`, the same calls a
	quest reward and a shop purchase use. Every console change lands in
	the Ledger with a `dev:` reason, next to the real ones.

	WHAT THAT BUYS, FOR FREE
	------------------------
	  - `spend` REFUSES to go below zero and returns false. A balance that
	    can go negative is one that has already been spent twice, and the
	    console inherits that guarantee rather than reimplementing it.
	  - the cap, the ledger row and the on-screen award toast all keep
	    working, because this is not a side door.

	NO "SET TO N". Only add and remove.
	-----------------------------------
	A set would have to write the field directly to force a value down,
	which is the second writer again. Add/remove composes to the same
	outcome through the front door — and it is the honest shape, because
	the ledger records a DELTA, not a decree.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Protocol = require(BloxKart.DeveloperConsole.Protocol)

local Progress = require(script.Parent.Parent.Parent.Progress)
local DataService = require(script.Parent.Parent.Parent.DataService)

local Economy = {}
local Code = Protocol.Code

Economy.KINDS = table.freeze({ "bolt", "crystals" })

-- Bounded per call, not per balance. A developer who wants a million
-- can press it ten times and every press is a separate ledger row, which
-- is a better record than one unbounded grant.
Economy.MAX_PER_CALL = 100000

function Economy.adjust(actorName: string, targetUserId: number, kind: string, amount: number): (boolean, string, string, any?)
	local player = Players:GetPlayerByUserId(targetUserId)
	if not player then
		return false, Code.NOT_FOUND, "That player is not in this server."
	end
	if kind ~= "bolt" and kind ~= "crystals" then
		return false, Code.BAD_PAYLOAD, "Unknown currency."
	end

	-- BEFORE, captured for the audit line. Recovering from a mistaken
	-- edit needs the previous value, and nothing else records it.
	local data = DataService.get(player)
	if not data then
		return false, Code.UNAVAILABLE, "That player has no loaded profile."
	end
	local before = (if kind == "bolt" then data.bolt else data.crystals) or 0

	-- The reason string reaches the Ledger, so a console grant is
	-- distinguishable from an earned one forever.
	local reason = ("dev:%s"):format(actorName)

	if amount > 0 then
		Progress.grant(player, kind, amount, reason)
	else
		local taken = math.abs(amount)
		-- Refuses rather than clamping. Silently taking "as much as they
		-- had" is a different action from the one that was asked for, and
		-- the caller should know which happened.
		if not Progress.spend(player, kind, taken, reason) then
			return false,
				Code.UNAVAILABLE,
				("%s only has %d %s."):format(player.Name, before, kind)
		end
	end

	local after = (if kind == "bolt" then data.bolt else data.crystals) or 0
	return true,
		Code.OK,
		("%s %s %+d  (%d -> %d)"):format(player.Name, kind, amount, before, after),
		{ before = before, after = after }
end

return Economy
