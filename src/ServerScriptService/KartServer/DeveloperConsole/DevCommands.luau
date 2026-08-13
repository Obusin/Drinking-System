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
local Moderation = require(script.Parent.adapters.Moderation)
local Tuning = require(script.Parent.adapters.Tuning)
local MatchControl = require(script.Parent.adapters.Match)
local BotBrain = require(script.Parent.Parent.BotBrain)
local Economy = require(script.Parent.adapters.Economy)

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

-- WHAT HAVE THE BOTS LEARNED ON THIS TRACK?
--
-- A learner you cannot inspect is indistinguishable from one that is
-- merely accumulating, and both look like "nothing is happening" from
-- the driver's seat. This answers the two questions actually being
-- asked: is anything being written down, and which corners are teaching
-- them something.
--
-- Worst nodes first. Sixty-one rows in index order is data; the five
-- that keep hurting is an answer.
Commands.botbrain = {
	permission = "VIEW_SERVER",
	rate = { burst = 10, per = 5 },
	validate = function(p)
		return DevSchema.shape(p, {})
	end,
	run = function()
		local Route = require(game:GetService("ReplicatedStorage").BloxKart.Route)
		local status = BotBrain.status()
		local rows = BotBrain.summary(12)
		local pathNodes = #Route.path()
		local done = BotBrain.progress(pathNodes)

		-- A BAR, because "0.62" and "62%" both need reading and a bar
		-- does not. Twenty cells is enough to see movement between two
		-- checks a minute apart, which is the only comparison anyone
		-- actually makes here.
		local cells = 20
		local filled = math.floor(done * cells + 0.5)
		local bar = string.rep("#", filled) .. string.rep("-", cells - filled)

		local head = ("[%s] %.0f%% learned  ·  %s · %s · %d node(s) · %d incident(s) · %d clean%s"):format(
			bar,
			done * 100,
			if status.enabled then "learning ON" else "learning OFF",
			if status.persisted then "saved to " .. tostring(status.key) else "SESSION ONLY (no datastore)",
			status.nodes,
			status.incidents,
			status.cleans,
			if status.unsaved then " · unsaved changes" else ""
		)
		return true, Code.OK, head, { status = status, nodes = rows, progress = done, pathNodes = pathNodes }
	end,
}

-- Forget this track. Needed because editing a map invalidates learning
-- that would otherwise keep applying to corners that no longer exist.
-- SHOW ME THE PATH. Pushed to the CALLER and nobody else.
--
-- The markers used to be built on the server, in workspace, which means
-- every player in the round saw a track covered in floating dots. A part
-- is a part — there is no per-player visibility on one — so the only way
-- to show this to an admin alone is for the admin's own client to draw
-- it. This just says "you may".
Commands.showpath = {
	permission = "VIEW_SERVER",
	rate = { burst = 6, per = 5 },
	validate = function(p)
		return DevSchema.shape(p, { on = DevSchema.optional(DevSchema.boolean()) })
	end,
	run = function(ctx, p)
		local DevConsoleService = require(script.Parent.DevConsoleService)
		DevConsoleService.push(ctx.player, "path", { on = p.on })
		return true, Code.OK, "path view toggled for you only", { on = p.on }
	end,
}

Commands.botbrainwipe = {
	permission = "EDIT_WORLD",
	rate = { burst = 2, per = 30 },
	validate = function(p)
		return DevSchema.shape(p, {})
	end,
	run = function()
		BotBrain.wipe()
		return true, Code.OK, "bot learning wiped for this place", {}
	end,
}

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
			tunables = Tuning.list(),
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
--  MATCH — owner-only because these controls affect every racer.
--=====================================================================

Commands.match_restart = {
	permission = "MODIFY_CONFIG",
	rate = { burst = 2, per = 20 },
	destructive = true,
	validate = function(p)
		return DevSchema.shape(p, {})
	end,
	run = function()
		return MatchControl.restart()
	end,
}

Commands.match_finish = {
	permission = "MODIFY_CONFIG",
	rate = { burst = 2, per = 20 },
	destructive = true,
	validate = function(p)
		return DevSchema.shape(p, {})
	end,
	run = function()
		return MatchControl.finish()
	end,
}

Commands.match_set_laps = {
	permission = "MODIFY_CONFIG",
	rate = { burst = 6, per = 10 },
	validate = function(p)
		return DevSchema.shape(p, { laps = DevSchema.intRange(1, 20) })
	end,
	run = function(_, p)
		return MatchControl.setLaps(p.laps)
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

Commands.inspect_dressing = {
	permission = "VIEW_PLAYERS",
	rate = { burst = 8, per = 5 },
	validate = function(p)
		return DevSchema.shape(p, { targetUserId = DevSchema.userId() })
	end,
	run = function(_, p)
		local data = Inspect.dressing(p.targetUserId)
		if not data then
			return false, Code.NOT_FOUND, "That player is not in this server."
		end
		return true, Code.OK, "ok", data
	end,
}

Commands.inspect_profile = {
	permission = "VIEW_PROFILE",
	-- Cheap (an in-memory read), so the limit is about the UI polling
	-- politely rather than about protecting the DataStore.
	rate = { burst = 8, per = 5 },
	validate = function(p)
		return DevSchema.shape(p, { targetUserId = DevSchema.userId() })
	end,
	run = function(_, p)
		local data = Inspect.profile(p.targetUserId)
		if not data then
			return false, Code.NOT_FOUND, "That player is not in this server."
		end
		return true, Code.OK, "ok", data
	end,
}

-- TELEPORT. The server resolves WHERE — the part a client must not be
-- trusted with — and pushes it to the target's own client, which applies
-- it through Simulation:RespawnAt.
--
-- It does not move the kart itself. A driven kart's position is owned by
-- its player's client, and FINDINGS is explicit that a second writer
-- produces the "sinks then teleports" bug.
Commands.teleport = {
	permission = "MODIFY_PLAYER",
	rate = { burst = 6, per = 10 },
	validate = function(p)
		return DevSchema.shape(p, {
			targetUserId = DevSchema.userId(),
			kind = DevSchema.oneOf({ "player", "checkpoint" }),
			index = DevSchema.optional(DevSchema.intRange(1, 200)),
			toUserId = DevSchema.optional(DevSchema.userId()),
		})
	end,
	run = function(_, p)
		local Players = game:GetService("Players")
		local target = Players:GetPlayerByUserId(p.targetUserId)
		if not target then
			return false, Code.NOT_FOUND, "That player is not in this server."
		end
		local cf, err = Tuning.resolveDestination(p.kind, p.index, p.toUserId)
		if not cf then
			return false, Code.NOT_FOUND, err or "Could not resolve a destination."
		end
		local Service = require(script.Parent.DevConsoleService)
		Service.push(target, "teleport", { cf = cf })
		return true, Code.OK, ("Sent %s to that %s."):format(target.Name, p.kind)
	end,
}

--=====================================================================
--  TUNING — registered keys only, never arbitrary attributes
--=====================================================================

Commands.set_tunable = {
	permission = "MODIFY_CONFIG",
	-- Generous: this is a slider, and a stingy limit makes live tuning
	-- feel broken rather than safe.
	rate = { burst = 20, per = 5 },
	validate = function(p)
		return DevSchema.shape(p, {
			targetUserId = DevSchema.userId(),
			key = DevSchema.inRegistry(function(k)
				return if Tuning.isKey(k) then k else nil
			end),
			-- Range is re-checked per key in the adapter; this is the
			-- outer sanity bound so a NaN or an absurd value never
			-- reaches it.
			value = DevSchema.numberRange(-1000, 1000),
		})
	end,
	run = function(_, p)
		return Tuning.set(p.targetUserId, p.key, p.value)
	end,
}

Commands.reset_tunable = {
	permission = "MODIFY_CONFIG",
	rate = { burst = 10, per = 5 },
	validate = function(p)
		return DevSchema.shape(p, {
			targetUserId = DevSchema.userId(),
			key = DevSchema.inRegistry(function(k)
				return if Tuning.isKey(k) then k else nil
			end),
		})
	end,
	run = function(_, p)
		return Tuning.reset(p.targetUserId, p.key)
	end,
}

--=====================================================================
--  ECONOMY
--=====================================================================

Commands.adjust_currency = {
	permission = "EDIT_CURRENCY",
	-- Harsh, like ban. Each press is a separate ledger row, so a slow
	-- limit costs a developer a few seconds and costs a runaway script
	-- or a stolen session almost everything it wanted.
	rate = { burst = 3, per = 30 },
	destructive = true,
	validate = function(p)
		return DevSchema.shape(p, {
			targetUserId = DevSchema.userId(),
			kind = DevSchema.oneOf(Economy.KINDS),
			-- Signed: positive grants, negative takes. Bounded both ways
			-- so a typo cannot be a million, and zero is rejected because
			-- an adjustment of nothing is a mistake, not a no-op.
			amount = DevSchema.intRange(-Economy.MAX_PER_CALL, Economy.MAX_PER_CALL),
			confirm = DevSchema.boolean(),
		})
	end,
	run = function(ctx, p)
		if p.confirm ~= true then
			return false, Code.BAD_PAYLOAD, "Currency changes require confirm = true."
		end
		if p.amount == 0 then
			return false, Code.BAD_PAYLOAD, "Amount must not be zero."
		end
		return Economy.adjust(ctx.player.Name, p.targetUserId, p.kind, p.amount)
	end,
}

--=====================================================================
--  MODERATION
--
--  Every one of these goes through DevPermissions.canModerate as well as
--  its declared capability. That check is what stops a developer kicking
--  an owner, and stops anyone moderating themselves — see its note on
--  why a compromised account must not be able to remove the people who
--  could revoke it.
--=====================================================================

Commands.kick_player = {
	permission = "KICK_PLAYER",
	rate = { burst = 4, per = 20 },
	destructive = true,
	validate = function(p)
		return DevSchema.shape(p, {
			targetUserId = DevSchema.userId(),
			reason = DevSchema.optional(DevSchema.string(200)),
		})
	end,
	moderates = true,
	run = function(ctx, p)
		return Moderation.kick(p.targetUserId, p.reason, ctx.player.Name)
	end,
}

Commands.ban_player = {
	permission = "BAN_PLAYER",
	-- Deliberately harsh. Banning is not something anyone needs to do
	-- three times in ten seconds, and a slow limit turns a runaway script
	-- or a stolen session into a nuisance rather than a catastrophe.
	rate = { burst = 2, per = 60 },
	destructive = true,
	validate = function(p)
		return DevSchema.shape(p, {
			targetUserId = DevSchema.userId(),
			-- 0 or below means permanent; bounded above so a typo cannot
			-- become a thousand-year ban.
			durationDays = DevSchema.numberRange(0, Moderation.MAX_DURATION_DAYS),
			reason = DevSchema.optional(DevSchema.string(200)),
			privateNote = DevSchema.optional(DevSchema.string(200)),
			includeAlts = DevSchema.optional(DevSchema.boolean()),
			-- EXPLICIT CONFIRMATION, required by the schema itself.
			--
			-- A stray click, a replayed payload or a half-built request
			-- simply fails validation. The UI asks twice; this is what
			-- makes that ask load-bearing rather than decorative.
			confirm = DevSchema.boolean(),
		})
	end,
	moderates = true,
	run = function(_, p)
		if p.confirm ~= true then
			return false, Code.BAD_PAYLOAD, "Ban requires confirm = true."
		end
		return Moderation.ban(p.targetUserId, p.durationDays, p.reason, p.privateNote, p.includeAlts == true)
	end,
}

Commands.unban_player = {
	permission = "UNBAN_PLAYER",
	rate = { burst = 4, per = 60 },
	validate = function(p)
		return DevSchema.shape(p, {
			targetUserId = DevSchema.userId(),
			confirm = DevSchema.boolean(),
		})
	end,
	-- NOT `moderates`. Unbanning is the RECOVERY path: requiring the
	-- actor to outrank the target would make a mistaken ban on a fellow
	-- owner permanently unfixable from here, which is the opposite of
	-- what the rank check is for.
	run = function(_, p)
		if p.confirm ~= true then
			return false, Code.BAD_PAYLOAD, "Unban requires confirm = true."
		end
		return Moderation.unban(p.targetUserId)
	end,
}

-- Frozen so a runtime write cannot add a command or loosen one. Anything
-- that wants a new command edits this file and restarts the server,
-- which is the only way a command should ever come into existence.
return table.freeze(Commands)
