--[[
	GarageService — what you are wearing, and making it stick.

	THE SERVER DECIDES. The client sends "equip this id in this slot" and
	nothing more: no mesh id, no colour, no price. Everything real is read
	from Config.Garage here, so a client that lies about an asset id gets
	an unknown id rejected rather than a free skin.

	OWNERSHIP is checked against profile.parts, EXCEPT while
	Config.Garage.UnlockedForTesting is on — which is the flag that turns
	the garage from a showroom into a shop and is meant to be flipped once
	purchasing exists.

	WHY THE LOOK IS RESOLVED HERE AND NOT WHERE KARTS ARE BUILT
	-----------------------------------------------------------
	KartService asks for a look at spawn and must not care how it was
	chosen. Keeping the profile read in one place means the random dresser
	(Skins.randomFor) and a saved loadout are interchangeable, which is
	exactly what the garage was always meant to replace.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))
local Util = require(BloxKart:WaitForChild("Util"))
local DataService = require(script.Parent.DataService)

local G = Config.Garage
-- The part names live in ONE place for every dresser — see Config.Rig.
local RIG = Config.Rig
local log = Util.logger("GarageService", G.Debug)

local GarageService = {}

-- SOMEONE JUST CHANGED WHAT THEY ARE WEARING.
--
-- A hook rather than a require, for the same reason ProjectileService
-- has one for BotService: KartService requires THIS module, so this one
-- cannot require it back. Assigned in init.server.
--
-- It exists because equipping only wrote the profile. The kart you were
-- sitting in kept the old bodywork until it was despawned and rebuilt,
-- so the garage looked like it had not saved — you picked a part, shut
-- the menu, and your kart was unchanged.
GarageService.onEquipped = nil :: ((Player) -> ())?

local remote: RemoteEvent? = nil

-- Slots as the PROFILE stores them. `Wheels` is one choice in the UI but
-- two keys here, because front and rear are equipped as a pair — see the
-- pair note in Config.Garage.
local SLOT_KEYS = {
	Body = { "Body" },
	Rim = { "Rim" },
	Tire = { "Tire" },
	Paint = { "Paint" },
	-- LEGACY, still accepted so a client that has not reloaded cannot
	-- error. Writes the tyre, for the same reason the migration does.
	Wheels = { "Tire" },
}

local function catalogueFor(slot: string)
	if slot == "Body" then
		return G.Bodies
	elseif slot == "Rim" then
		return G.Rims
	elseif slot == "Tire" or slot == "Wheels" then
		return G.Tires
	elseif slot == "Paint" then
		return G.Paints
	end
	return nil
end

--=====================================================================
--  MIGRATION: ONE WHEEL BECOMES A RIM AND A TYRE
--
--  A profile saved before the split has `FWheel`/`RWheel` and no `Tire`.
--  Those ids came from a catalogue whose meshes were the WHOLE wheel,
--  and a whole wheel is mostly tyre — so the old choice becomes the
--  tyre and the rim starts stock.
--
--  THE IDS SURVIVE, so ownership does: `parts` is keyed by item id, and
--  "slick" is still "slick" in Config.Garage.Tires. Somebody who paid
--  200 for slicks still has slicks. Renaming the ids would have been
--  tidier and would have quietly deleted everyone's purchases.
--
--  IN PLACE AND ONCE. Reading a profile that has already been migrated
--  finds `Tire` set and does nothing, so this is safe on every load.
--=====================================================================
local function migrate(profile)
	local eq = profile.equipped
	if not eq or eq.Tire then
		return
	end
	local old = eq.FWheel or eq.RWheel
	eq.Tire = if old and old ~= "" then old else "stock"
	eq.Rim = eq.Rim or "stock"
	-- Left in place rather than cleared. They cost nothing, and a rollback
	-- to yesterday's build would otherwise find the wheels gone.
end

local function itemById(list, id: string)
	for _, item in list do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- Stock is always owned: it is what a kart is built as, so refusing it
-- would mean a player could equip their way into something they cannot
-- take off.
local function owns(profile, id: string): boolean
	if G.UnlockedForTesting or id == "stock" then
		return true
	end
	return profile.parts ~= nil and profile.parts[id] == true
end

--=====================================================================
--  WHAT SOMEONE IS WEARING
--=====================================================================

-- Resolved to what a kart actually needs: mesh ids and a colour. Returns
-- nil if there is no profile yet, so callers can fall back rather than
-- dress somebody in defaults they did not choose.
function GarageService.lookFor(player: Player): { [string]: any }?
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	local eq = profile.equipped or {}

	migrate(profile)

	local body = itemById(G.Bodies, eq.Body or "stock")
	local rim = itemById(G.Rims, eq.Rim or "stock")
	local tire = itemById(G.Tires, eq.Tire or "stock")

	-- MESH IDS ONLY. Skins.applyTo treats every key as a PART NAME to swap a
	-- mesh onto, so a colour in here would be looked up as a part called
	-- "Paint", found nowhere, and silently dropped — which is exactly how
	-- paint failed to appear on spawned karts. Colour goes through paintFor.
	--
	-- AND THE NAMES HAVE TO BE THE RIG'S, NOT INVENTED ONES.
	--
	-- This used to return the keys "FWheel" and "RWheel" literally. Those
	-- are two ALIASES in Rig.FrontWheelNames / RearWheelNames, not what
	-- the kart's parts are actually called — the real rig uses WheelFL,
	-- WheelFR, WheelRL, WheelRR. So `FindFirstChild("FWheel")` found
	-- nothing and the wheel swap did nothing, silently, on every kart.
	--
	-- Meanwhile the garage PREVIEW (KartDress) walked the whole name list
	-- and worked perfectly. That is the entire "it changes in the garage
	-- and not on my kart" bug: two dressing paths, two ideas of what the
	-- parts are called, and only one of them was right.
	--
	-- Every candidate name is emitted. A name the model does not have
	-- simply is not found, which costs one lookup and keeps this working
	-- across rigs that use different conventions.
	local look = {}
	if body and body.mesh and body.mesh ~= "" then
		-- Every candidate body name, for the same reason as the wheels:
		-- the ridden kart and the garage preview are DIFFERENT MODELS and
		-- need not name their bodywork alike. A name a model does not
		-- have is simply not found.
		for _, name in RIG.BodyNames do
			look[name] = body.mesh
		end
	end
	-- RIM AND TYRE ARE PART NAMES INSIDE THE WHEEL MODELS, so they need no
	-- front/rear spread: every wheel has one of each and they are all
	-- called the same thing. That is the whole reason the new rig is
	-- easier to dress than the old one.
	if rim and rim.mesh and rim.mesh ~= "" then
		for _, name in RIG.RimNames do
			look[name] = rim.mesh
		end
	end
	if tire and tire.mesh and tire.mesh ~= "" then
		for _, name in RIG.TireNames do
			look[name] = tire.mesh
		end
		-- AND the old whole-wheel parts, for karts still built the old way.
		-- A name a model does not have is simply not found, so this costs
		-- a few lookups and keeps every rig in the game dressable.
		for _, name in RIG.FrontWheelNames do
			look[name] = tire.mesh
		end
		for _, name in RIG.RearWheelNames do
			look[name] = tire.mesh
		end
	end
	return look
end

-- The equipped colour, or nil for the factory finish. Separate from lookFor
-- for the reason above.
function GarageService.paintFor(player: Player): Color3?
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	local eq = profile.equipped or {}
	local paint = itemById(G.Paints, eq.Paint or "stock")
	return paint and paint.colour or nil
end

-- The keys themselves, for pushing to the client so the garage opens on
-- what the player is already wearing.
local function equippedOf(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	local eq = profile.equipped or {}
	migrate(profile)
	return {
		Body = eq.Body or "stock",
		Rim = eq.Rim or "stock",
		Tire = eq.Tire or "stock",
		Paint = eq.Paint or "stock",
	}
end

--=====================================================================
--  EQUIPPING
--=====================================================================
-- EVERY REFUSAL SAYS WHY.
--
-- All five of these used to be a bare `return false`, and from the
-- garage they are indistinguishable from each other AND from a save that
-- worked into a mock store. That ambiguity is the whole reason
-- "customisation does not save" was so hard to pin down.
local function equip(player: Player, slot: unknown, id: unknown): boolean
	if type(slot) ~= "string" or type(id) ~= "string" then
		log("REFUSED %s: slot/id not strings (got %s / %s)", player.Name, typeof(slot), typeof(id))
		return false
	end
	local list = catalogueFor(slot)
	local keys = SLOT_KEYS[slot]
	if not list or not keys then
		log("REFUSED %s: unknown slot %q — not in SLOT_KEYS", player.Name, slot)
		return false -- unknown slot: a client inventing one gets nothing
	end
	local item = itemById(list, id)
	if not item then
		log("REFUSED %s: id %q is not in the %s catalogue", player.Name, id, slot)
		return false -- unknown id, including any asset id a client made up
	end

	local profile = DataService.get(player)
	if not profile then
		-- THE LIKELY ONE. Nothing is wrong with the pick; the profile is
		-- still loading, failed, or persistence is off entirely.
		log(
			"REFUSED %s: NO PROFILE (persistence enabled=%s). The pick was valid — nothing was saved because there is nowhere to save it.",
			player.Name,
			tostring(DataService.isEnabled())
		)
		return false
	end
	if not owns(profile, id) then
		log("REFUSED %s: does not own %q (UnlockedForTesting=%s)", player.Name, id, tostring(G.UnlockedForTesting))
		return false
	end

	-- Reconcile fills this from the template on load, but a profile that
	-- loaded before the field existed would still be missing it — and a nil
	-- here is a crash on the one path that has to be reliable.
	profile.equipped = profile.equipped or {}
	for _, key in keys do
		profile.equipped[key] = id
	end
	log("wrote %s.%s = %q", player.Name, table.concat(keys, "+"), id)
	return true
end

-- COMMIT A WHOLE LOADOUT AT ONCE.
--
-- The garage now previews locally and saves on Done, so what arrives is
-- the finished set rather than a write per click. Better in three ways:
-- one profile write instead of five, one re-dress of the live kart
-- instead of five mesh swaps, and Cancel becomes possible at all —
-- there is nothing to undo if nothing was written.
--
-- Partial success is deliberate. If one slot is refused the others still
-- land, and the authoritative reply tells the client exactly what stuck.
-- Refusing the whole set because one part was not owned would throw away
-- four good choices to punish one bad one.
local function commit(player: Player, picks: unknown): number
	if type(picks) ~= "table" then
		log("REFUSED %s: commit payload was %s, not a table", player.Name, typeof(picks))
		return 0
	end
	local wrote = 0
	for slot, id in picks :: { [string]: any } do
		if equip(player, slot, id) then
			wrote += 1
		end
	end

	if wrote > 0 and DataService.isMock() then
		-- THE ANSWER TO "IT DOES NOT SAVE", NINE TIMES OUT OF TEN.
		--
		-- The write succeeded. The store it went into is ProfileStore's
		-- mock, which Studio forces unless Config.Data.LiveInStudio is
		-- on, and it is discarded when the session ends. Said here, at
		-- the moment of saving, because the boot-time warning is long
		-- gone from Output by the time anyone is in the garage.
		warn(
			("[GarageService] %s: saved %d slot(s) to a MOCK store — this will NOT survive a restart. "):format(
				player.Name,
				wrote
			) .. "That is expected in Studio. Set Config.Data.LiveInStudio to test real persistence, and turn it back off after."
		)
	end
	return wrote
end

--=====================================================================
--  START
--=====================================================================
function GarageService.start()
	remote = ReplicatedStorage.BloxKart:FindFirstChild(Names.GARAGE_REMOTE)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = Names.GARAGE_REMOTE
		remote.Parent = ReplicatedStorage.BloxKart
	end

	remote.OnServerEvent:Connect(function(player, action, slot, id)
		-- ONE EXIT. Every action ends by sending the authoritative state
		-- back, whether it agreed or refused — a client that was refused
		-- must resync rather than keep showing something it never got.
		local function reply(why: string)
			local state = equippedOf(player)
			log("-> %s reply after %s: %s", player.Name, why, if state then table.concat({
				"Body=" .. tostring(state.Body),
				"Rim=" .. tostring(state.Rim),
				"Tire=" .. tostring(state.Tire),
				"Paint=" .. tostring(state.Paint),
			}, " ") else "NO PROFILE (nil)")
			remote:FireClient(player, "equipped", state)
		end

		if action == "commit" then
			-- `slot` carries the whole picks table for this action.
			log("<- %s commit", player.Name)
			local wrote = commit(player, slot)
			reply("commit")
			if wrote > 0 and GarageService.onEquipped then
				-- Put it on the kart they are sitting in RIGHT NOW, not
				-- only in the profile. Spawned because the mesh swap
				-- fetches over the network and this is a remote handler.
				task.spawn(GarageService.onEquipped, player)
			end
		elseif action == "equip" then
			-- Kept for anything still sending per-slot equips. The garage
			-- batches through "commit" now.
			log("<- %s equip %s=%s", player.Name, tostring(slot), tostring(id))
			local ok = equip(player, slot, id)
			if ok and DataService.isMock() then
				warn("[GarageService] " .. player.Name .. ": saved to a MOCK store — will not survive a restart (Studio default).")
			end
			reply("equip")
			if ok and GarageService.onEquipped then
				task.spawn(GarageService.onEquipped, player)
			end
		elseif action == "refresh" then
			log("<- %s refresh", player.Name)
			reply("refresh")
		else
			log("<- %s UNKNOWN action %q — ignored", player.Name, tostring(action))
		end
	end)

	-- Push on load so the garage can open on the right selection without
	-- having to ask.
	DataService.onLoaded(function(player)
		if remote then
			remote:FireClient(player, "equipped", equippedOf(player))
		end
	end)

	Players.PlayerRemoving:Connect(function() end)
end

return GarageService
