--[[
	AI — adapter for developer-spawned karts and bots.

	TWO MODES, AND THEY ARE GENUINELY DIFFERENT THINGS
	--------------------------------------------------
	  static   a kart built by KartFactory, anchored, no driver. A target,
	           an obstacle, a thing to look at. Works ANYWHERE.
	  driving  a real bot, driven by the existing BotService.

	BotService is started only in a RACE place (`if racing then` in
	init.server), so driving AI genuinely cannot exist in the lobby. The
	command declares that and the router refuses it there, rather than
	this adapter spawning something that silently never moves — a kart
	that looks like a failed bot is a bug report waiting to happen.

	DEVELOPER BOTS ARE TRACKED SEPARATELY FROM MATCH BOTS.
	------------------------------------------------------
	`BotService.fill()` creates the grid's bots and knows nothing about
	DevRegistry. Cleanup here walks DevRegistry only, so it cannot remove
	a racer the match is relying on — structurally, not by checking.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Place = require(BloxKart.Place)
local Protocol = require(BloxKart.DeveloperConsole.Protocol)

local KartService = require(script.Parent.Parent.Parent.KartService)
local DevRegistry = require(script.Parent.Parent.DevRegistry)

local AI = {}

-- Hard ceiling, independent of rate limiting.
--
-- The rate limiter bounds how FAST you can spawn; this bounds how many
-- can exist. Without it a patient developer reaches the same bad place
-- slowly, and a server full of test karts is indistinguishable from a
-- performance bug.
AI.MaxDevAI = 12

local function tryRequire(name: string): any?
	local module = script.Parent.Parent.Parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	return if ok then result else nil
end

function AI.canDrive(): boolean
	-- Both conditions: the place must be a race AND BotService must have
	-- actually loaded. The second is not implied by the first if a
	-- service failed to start.
	return Place.isRace() and tryRequire("BotService") ~= nil
end

-- Returns ok, code, message, data.
function AI.spawn(spawnedBy: number, mode: string, atUserId: number): (boolean, string, string, any?)
	if DevRegistry.count("ai") >= AI.MaxDevAI then
		return false,
			Protocol.Code.UNAVAILABLE,
			("Developer AI limit reached (%d). Remove some first."):format(AI.MaxDevAI)
	end

	if mode == "driving" and not AI.canDrive() then
		return false,
			Protocol.Code.WRONG_PLACE,
			"Driving AI needs the race place — BotService does not run in the lobby."
	end

	-- Named so it is obvious in the Explorer and in any scoreboard that
	-- this is not a real racer.
	local label = ("DEV_%s_%d"):format(mode:upper(), math.random(1000, 9999))

	local ok, racer, kart = pcall(function()
		return KartService.addBot(label)
	end)
	if not ok or not kart then
		return false, Protocol.Code.INTERNAL, "Could not build a kart for the AI."
	end

	if mode == "static" then
		-- addBot already anchors the hitbox (see its note on two owners
		-- of one part), so a static one needs nothing further — it simply
		-- is never handed to BotService's stepper.
		local id = DevRegistry.add("ai", kart, spawnedBy, { mode = mode }, racer)
		kart:SetAttribute("DevSpawned", true)
		kart:SetAttribute("DevEntityId", id)
		return true, Protocol.Code.OK, "Spawned a static kart.", { entityId = id }
	end

	-- DRIVING: hand it to the existing controller. No duplicate steering
	-- is written here — that is the entire point of reusing BotService.
	local bots = tryRequire("BotService")
	local attached = false
	if bots and type(bots.takeOver) == "function" then
		local good, result = pcall(bots.takeOver, kart, label)
		attached = good and result == true
	end
	if not attached then
		-- Do not leave an orphan kart standing on the track.
		KartService.dropRacer(racer)
		return false,
			Protocol.Code.UNAVAILABLE,
			"BotService would not take over the kart (is a round running?)."
	end

	local id = DevRegistry.add("ai", kart, spawnedBy, { mode = mode }, racer)
	kart:SetAttribute("DevSpawned", true)
	kart:SetAttribute("DevEntityId", id)
	return true, Protocol.Code.OK, "Spawned a driving AI.", { entityId = id }
end

function AI.remove(spawnedBy: number?): (boolean, string, string, any?)
	local removed = 0
	for _, entry in DevRegistry.list("ai", spawnedBy) do
		-- Through KartService, so its own bookkeeping (slots, karts map,
		-- ownership) is unwound properly rather than by destroying the
		-- model and leaving the service believing it still exists.
		if entry.racer then
			pcall(KartService.dropRacer, entry.racer)
		elseif entry.instance then
			entry.instance:Destroy()
		end
		DevRegistry.remove(entry.id)
		removed += 1
	end
	return true, Protocol.Code.OK, ("Removed %d developer AI."):format(removed), { removed = removed }
end

return AI
