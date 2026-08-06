--[[
	DevCommands — the command registry. One entry per action.

	EVERY FIELD IS DATA, NOT CODE.
	------------------------------
	permission, rate, places and destructive are declared so the ROUTER
	enforces them uniformly. A command author writes a validator and a
	handler; they cannot forget a permission check, because they never
	write one.

	Adding a command is adding one entry here. It needs no change to the
	router, the remotes, the permission module or the UI.

	`run` receives (ctx, payload) and returns ok, code, message, data.
	  ctx = { player, userId, role }
	Payload is the CLEAN table the validator returned — never the raw
	one the client sent.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Protocol = require(BloxKart.DeveloperConsole.Protocol)

local DevSchema = require(script.Parent.DevSchema)
local Inspect = require(script.Parent.adapters.Inspect)
local Powerups = require(script.Parent.adapters.Powerups)
local World = require(script.Parent.adapters.World)
local AI = require(script.Parent.adapters.AI)

local Code = Protocol.Code
local Commands = {}

--=====================================================================
--  DIAGNOSTIC
--=====================================================================

-- The end-to-end proof. Cheapest possible command that still walks the
-- entire path: authorise, rate limit, replay, validate, run, audit.
-- Kept permanently — if this fails, nothing else is worth debugging.
Commands.ping = {
	permission = "VIEW_CONSOLE",
	rate = { burst = 10, per = 5 },
	validate = function(p)
		return DevSchema.shape(p, {})
	end,
	run = function(ctx)
		return true, Code.OK, ("pong — you are %s"):format(ctx.role), { role = ctx.role, at = os.time() }
	end,
}

--=====================================================================
--  READ
--=====================================================================

Commands.snapshot = {
	permission = "VIEW_SERVER",
	rate = { burst = 12, per = 5 }, -- the UI polls this
	validate = function(p)
		return DevSchema.shape(p, {})
	end,
	run = function()
		return true, Code.OK, "ok", {
			server = Inspect.server(),
			players = Inspect.playerList(),
			catalogue = Powerups.catalogue(),
			canDriveAI = AI.canDrive(),
		}
	end,
}

Commands.inspect_player = {
	permission = "VIEW_PLAYERS",
	rate = { burst = 12, per = 5 },
	validate = function(p)
		return DevSchema.shape(p, { targetUserId = DevSchema.userId() })
	end,
	run = function(_, p)
		local data = Inspect.player(p.targetUserId)
		if not data then
			return false, Code.NOT_FOUND, "That player is not in this server."
		end
		return true, Code.OK, "ok", data
	end,
}

Commands.logs = {
	permission = "VIEW_LOGS",
	rate = { burst = 8, per = 5 },
	validate = function(p)
		return DevSchema.shape(p, { limit = DevSchema.optional(DevSchema.intRange(1, 200)) })
	end,
	run = function(_, p)
		-- Required here rather than at the top: DevAudit requires nothing
		-- from this module, and keeping the edge one-way avoids a cycle.
		local DevAudit = require(script.Parent.DevAudit)
		return true, Code.OK, "ok", { entries = DevAudit.recent(p.limit or 100) }
	end,
}

--=====================================================================
--  POWER-UPS
--=====================================================================

Commands.give_item = {
	permission = "GRANT_ITEM",
	rate = { burst = 8, per = 10 },
	validate = function(p)
		return DevSchema.shape(p, {
			targetUserId = DevSchema.userId(),
			itemId = DevSchema.inRegistry(function(id)
				return if Powerups.exists(id) then id else nil
			end),
		})
	end,
	run = function(_, p)
		return Powerups.give(p.targetUserId, p.itemId)
	end,
}

Commands.clear_items = {
	permission = "CLEAR_ITEMS",
	rate = { burst = 6, per = 10 },
	validate = function(p)
		return DevSchema.shape(p, { targetUserId = DevSchema.userId() })
	end,
	run = function(_, p)
		return Powerups.clear(p.targetUserId)
	end,
}

--=====================================================================
--  WORLD
--=====================================================================

Commands.spawn_pickup = {
	permission = "SPAWN_PICKUP",
	rate = { burst = 5, per = 10 },
	validate = function(p)
		return DevSchema.shape(p, {
			targetUserId = DevSchema.userId(),
			-- Absent means "random", which is the normal roll a real box
			-- does. Present means force exactly this item.
			itemId = DevSchema.optional(DevSchema.inRegistry(function(id)
				return if Powerups.exists(id) then id else nil
			end)),
		})
	end,
	run = function(ctx, p)
		return World.spawnPickup(ctx.userId, p.targetUserId, p.itemId)
	end,
}

Commands.clear_pickups = {
	permission = "CLEANUP_OWN",
	rate = { burst = 4, per = 10 },
	destructive = true,
	validate = function(p)
		return DevSchema.shape(p, { all = DevSchema.optional(DevSchema.boolean()) })
	end,
	-- `all` widens the blast radius from "mine" to "everyone's", so it
	-- needs the higher permission. Declared here so the router can check
	-- it without the handler being trusted to.
	elevate = { all = "CLEANUP_ALL" },
	run = function(ctx, p)
		return World.clearPickups(if p.all then nil else ctx.userId)
	end,
}

--=====================================================================
--  AI
--=====================================================================

Commands.spawn_ai = {
	permission = "SPAWN_AI",
	rate = { burst = 3, per = 15 },
	validate = function(p)
		return DevSchema.shape(p, {
			mode = DevSchema.oneOf({ "static", "driving" }),
			targetUserId = DevSchema.userId(),
		})
	end,
	run = function(ctx, p)
		return AI.spawn(ctx.userId, p.mode, p.targetUserId)
	end,
}

Commands.clear_ai = {
	permission = "CLEANUP_OWN",
	rate = { burst = 4, per = 10 },
	destructive = true,
	validate = function(p)
		return DevSchema.shape(p, { all = DevSchema.optional(DevSchema.boolean()) })
	end,
	elevate = { all = "CLEANUP_ALL" },
	run = function(ctx, p)
		return AI.remove(if p.all then nil else ctx.userId)
	end,
}

--=====================================================================
--  PLAYER
--=====================================================================

Commands.respawn_player = {
	permission = "MODIFY_PLAYER",
	rate = { burst = 4, per = 10 },
	destructive = true,
	validate = function(p)
		return DevSchema.shape(p, { targetUserId = DevSchema.userId() })
	end,
	run = function(_, p)
		local Players = game:GetService("Players")
		local player = Players:GetPlayerByUserId(p.targetUserId)
		if not player then
			return false, Code.NOT_FOUND, "That player is not in this server."
		end
		-- Through LoadCharacter, which KartService's own respawn path
		-- watches. Destroying the character directly would race its
		-- watchdog — see KartService's note on four callers of
		-- LoadCharacter.
		local ok = pcall(function()
			player:LoadCharacter()
		end)
		if not ok then
			return false, Code.INTERNAL, "LoadCharacter failed."
		end
		return true, Code.OK, ("Respawned %s."):format(player.Name)
	end,
}

-- Frozen so a runtime write cannot add a command or loosen one. Anything
-- that wants a new command edits this file and restarts the server,
-- which is the only way a command should ever come into existence.
return table.freeze(Commands)
