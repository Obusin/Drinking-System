--[[
	Powerups — adapter over the existing item system.

	IT REUSES THE REAL GRANT PATH.
	------------------------------
	A real item box does exactly one thing when collected: the server
	fires `KartItemPickup` at the collector with an item id, and the
	client's Items controller puts it in a slot. This adapter fires the
	same remote with the same payload.

	That matters more than it sounds. A console that granted items by its
	own route would be testing a code path players never use — so it
	would pass while the real one was broken, and it would drift the
	moment the real one changed. Reusing the remote means if granting
	works here, it works in the game.

	WHAT THIS CANNOT DO, AND WHY IT SAYS SO
	---------------------------------------
	Item slots live on the CLIENT (`KartClient/Items.luau`). The server
	rolls and announces; it does not track. So:

	  give     -> authoritative. The same message a real box sends.
	  clear    -> ADVISORY. There is no server-side clear, so this asks
	              the client to drop its slots and the client obliges.
	  read     -> unavailable. The server does not know.

	Making these authoritative means moving item state server-side, which
	is a gameplay change (see BUGS #6, "two client-authority seams"), not
	a console feature. Until then the console labels them honestly rather
	than pretending.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Items = require(BloxKart.Items)
local Protocol = require(BloxKart.DeveloperConsole.Protocol)

local Powerups = {}

-- The live grant remote, resolved lazily.
--
-- RaceService creates it during start(), so a require-time lookup would
-- race it. Looked up per call and cached, and a miss is reported rather
-- than assumed — in the lobby it genuinely may not exist.
local grantRemote: RemoteEvent? = nil
local function remote(): RemoteEvent?
	if grantRemote and grantRemote.Parent then
		return grantRemote
	end
	local found = BloxKart:FindFirstChild("KartItemPickup")
	grantRemote = if found and found:IsA("RemoteEvent") then found else nil
	return grantRemote
end

-- The selector's contents, straight from the game's own registry.
--
-- Never a second hand-written list: an item added to Items/ appears here
-- with no console change, and one removed stops being grantable
-- immediately.
function Powerups.catalogue(): { any }
	local out = {}
	for _, item in Items.All do
		table.insert(out, {
			id = item.Id,
			name = item.Name,
			scope = item.Scope,
			icon = item.Icon,
		})
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

-- Used by the schema validator, so an unknown or hidden id is refused
-- before any handler runs.
function Powerups.exists(id: string): boolean
	return Items.byId(id) ~= nil
end

-- Grant. Returns ok, code, message.
function Powerups.give(userId: number, itemId: string): (boolean, string, string)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return false, Protocol.Code.NOT_FOUND, "That player is not in this server."
	end
	local item = Items.byId(itemId)
	if not item then
		-- Belt and braces: the validator already checked, and this is the
		-- boundary that must not depend on it having run.
		return false, Protocol.Code.BAD_PAYLOAD, "Unknown item id."
	end
	local r = remote()
	if not r then
		return false,
			Protocol.Code.UNAVAILABLE,
			"The item system is not running here (KartItemPickup remote missing — lobby?)."
	end
	r:FireClient(player, item.Id)
	return true, Protocol.Code.OK, ("Gave %s to %s."):format(item.Id, player.Name)
end

-- Clear. ADVISORY — see the module note.
--
-- Sends a sentinel the client's console listener understands. The client
-- is being ASKED, and an exploiter ignoring the request only affects
-- their own screen, which is already true of everything client-owned.
Powerups.CLEAR_SENTINEL = "__DEV_CLEAR__"

function Powerups.clear(userId: number): (boolean, string, string)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return false, Protocol.Code.NOT_FOUND, "That player is not in this server."
	end
	local r = remote()
	if not r then
		return false, Protocol.Code.UNAVAILABLE, "The item system is not running here."
	end
	r:FireClient(player, Powerups.CLEAR_SENTINEL)
	return true, Protocol.Code.OK, ("Asked %s's client to clear its slots (advisory)."):format(player.Name)
end

return Powerups
