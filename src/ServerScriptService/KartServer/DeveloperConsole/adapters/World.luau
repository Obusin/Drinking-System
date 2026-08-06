--[[
	World — adapter for developer-spawned pickups and their cleanup.

	A developer pickup is a REAL item box: it carries the same
	`Config.Items.BoxTag` a level-authored box does, so RaceService's
	existing collection handler picks it up with no special case. The only
	difference is that this one is recorded in DevRegistry and can carry a
	forced item id.

	FORCING AN ITEM USES THE GAME'S OWN MECHANISM. RaceService already
	honours `Names.DROP_ITEM` on a box (that is how a dropped item grants
	exactly what it is rather than a fresh roll). Setting that attribute
	is reusing a feature, not adding a back door.

	CLEANUP CANNOT TOUCH AUTHORED BOXES. It walks DevRegistry, and a
	level-authored box was never added to it.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart.Config)
local Items = require(BloxKart.Items)
local Names = require(BloxKart.Names)
local Protocol = require(BloxKart.DeveloperConsole.Protocol)

local KartService = require(script.Parent.Parent.Parent.KartService)
local DevRegistry = require(script.Parent.Parent.DevRegistry)

local World = {}

local IT = Config.Items

-- Where to put it. A dev either drops it at their own kart or at a
-- target's — never at client-supplied coordinates, because a free
-- position is a way to place a collidable object anywhere in the map.
local function anchorFor(userId: number): CFrame?
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return nil
	end
	local kart = KartService.kartFor(player)
	local hitbox = kart and kart.PrimaryPart
	if hitbox then
		-- Slightly ahead and above, so it does not spawn inside them.
		return hitbox.CFrame * CFrame.new(0, 2, -12)
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.CFrame * CFrame.new(0, 2, -8)
	end
	return nil
end

-- Returns ok, code, message, data.
function World.spawnPickup(spawnedBy: number, atUserId: number, forcedItemId: string?): (boolean, string, string, any?)
	local cf = anchorFor(atUserId)
	if not cf then
		return false, Protocol.Code.NOT_FOUND, "Could not find a kart or character to spawn near."
	end
	if forcedItemId and not Items.byId(forcedItemId) then
		return false, Protocol.Code.BAD_PAYLOAD, "Unknown item id."
	end

	local box = Instance.new("Part")
	box.Name = "DevItemBox"
	box.Size = Vector3.new(5, 5, 5)
	box.CFrame = cf
	box.Anchored = true
	-- CanCollide off: the kart is kinematic and query-based, so a solid
	-- box would be a wall rather than a pickup. CanQuery off for the same
	-- reason — it must never register in the movement sweep.
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = true
	box.Transparency = 0.35
	box.Color = Color3.fromRGB(255, 198, 28)
	box.Material = Enum.Material.Neon

	-- The SAME tag an authored box carries, so the existing collection
	-- path handles it with no special case.
	CollectionService:AddTag(box, IT.BoxTag)
	if forcedItemId then
		-- The game's own "grant exactly this" mechanism.
		box:SetAttribute(Names.DROP_ITEM, forcedItemId)
	end

	box.Parent = workspace

	local id = DevRegistry.add("pickup", box, spawnedBy, { forcedItemId = forcedItemId })
	-- Stamped on the instance too, so a human poking around in the
	-- Explorer can tell a test object from a level one.
	box:SetAttribute("DevSpawned", true)
	box:SetAttribute("DevEntityId", id)
	box:SetAttribute("SpawnedByUserId", spawnedBy)

	return true,
		Protocol.Code.OK,
		if forcedItemId then ("Spawned a %s box."):format(forcedItemId) else "Spawned a random box.",
		{ entityId = id }
end

-- `spawnedBy` nil means "every developer's", which the router only
-- allows for CLEANUP_ALL.
function World.clearPickups(spawnedBy: number?): (boolean, string, string, any?)
	local removed = 0
	for _, entry in DevRegistry.list("pickup", spawnedBy) do
		if entry.instance then
			entry.instance:Destroy()
		end
		DevRegistry.remove(entry.id)
		removed += 1
	end
	return true, Protocol.Code.OK, ("Removed %d developer pickup(s)."):format(removed), { removed = removed }
end

return World
