--[[
	DevConsoleController — the Iris window. View layer, nothing more.

	WHAT THIS IS ALLOWED TO DO
	--------------------------
	Render cached data. Collect input. Submit a request. Show the reply.

	WHAT IT MUST NEVER DO
	---------------------
	Call a gameplay service, mutate state, or decide a permission. If a
	tab ever needs to `require` something out of KartServer, the layering
	has broken.

	IRIS IS IMMEDIATE MODE: the whole tree is rebuilt every frame from
	`DevConsoleClient.cache`. That is why the client caches — a remote
	call per frame would be thousands a minute and the console would
	rate-limit itself.

	ONE CONNECTION, EVER. Iris.Init and Iris:Connect happen exactly once,
	guarded by `started`. Re-running either on every open is how an
	immediate-mode UI ends up drawing its tree N times per frame.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Iris = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Iris"))
local Client = require(script.Parent.DevConsoleClient)

local DevConsoleController = {}

-- Callbacks into init.client for LOCAL-ONLY overrides. The console never
-- touches gameplay itself; it asks the file that owns it. See the
-- setForceRace note there.
local localHooks: any = {}

local started = false
local visible = false
local role = "viewer"

-- Selection lives here, not on the server: it is UI state, and the
-- server is told which player to inspect on every request anyway.
local selected = { userId = nil :: number?, name = "" }
local chosenItem = 1
local tab = "Server"

local TABS = { "Server", "Players", "Power-Ups", "AI", "World", "Tune", "Moderate", "Logs" }

-- SPEED HISTORY, sampled locally for the graph.
--
-- Read from the live Simulation via a hook, not from a remote: a graph
-- wants ~30 samples a second and no server round trip survives that.
-- Purely a readout — the value it plots is the one the client is already
-- simulating with.
local SAMPLES = 120
local speedHistory: { number } = {}
local frameHistory: { number } = {} -- ms
local overBudget = 0 -- frames past MaxTimestep since the console opened
local lastSampleAt = 0
local lastFrameAt = 0

-- THE LINE THAT MATTERS. Simulation clamps dt to Handling.MaxTimestep,
-- so a frame longer than this is time the kart never integrates: it
-- moves slower than real time, smoothly, with the speedometer agreeing.
-- That cost a full round of debugging once (BUGS #26) because it reads
-- as nerfed handling rather than as frame rate. A graph with the budget
-- drawn on it makes it self-evident.
local BUDGET_MS = 1000 / 20

local function sampleSpeed()
	if not localHooks.getSpeed then
		return
	end
	local now = os.clock()
	if now - lastSampleAt < 1 / 30 then
		return
	end
	lastSampleAt = now
	table.insert(speedHistory, localHooks.getSpeed() or 0)
	while #speedHistory > SAMPLES do
		table.remove(speedHistory, 1)
	end
end

-- EVERY FRAME, unthrottled — a throttled frame-time graph would miss
-- exactly the spikes it exists to show.
local function sampleFrame()
	local now = os.clock()
	if lastFrameAt > 0 then
		local ms = (now - lastFrameAt) * 1000
		table.insert(frameHistory, ms)
		if ms > BUDGET_MS then
			overBudget += 1
		end
		while #frameHistory > SAMPLES do
			table.remove(frameHistory, 1)
		end
	end
	lastFrameAt = now
end

-- Local slider value per tunable, so dragging is smooth and only the
-- committed value crosses the wire.
local tuneValue: { [string]: number } = {}

-- ARMING IS LOCAL AND DELIBERATELY FRAGILE.
--
-- A ban button that fires on one click is a ban you will eventually
-- issue by accident. The first click arms, the second commits, and
-- changing target or tab disarms — so an arm left sitting from five
-- minutes ago cannot fire at whoever happens to be selected now.
--
-- This is UX, not security: the schema requires `confirm = true`, so a
-- request that skips the arming step fails validation on the server.
local armed = { action = nil :: string?, forUserId = nil :: number? }
local banDays = 0 -- 0 = permanent
local banReason = "Breaking the rules"

local function disarm()
	armed.action, armed.forUserId = nil, nil
end

local function armOrFire(action: string, userId: number, fire: () -> ())
	if armed.action == action and armed.forUserId == userId then
		disarm()
		fire()
	else
		armed.action, armed.forUserId = action, userId
	end
end

local function may(permission: string): boolean
	-- A COSMETIC check, and labelled as such. It greys out buttons the
	-- server would refuse anyway; it is not what stops anything.
	if role == "owner" then
		return true
	end
	if role == "developer" then
		return permission ~= "owner"
	end
	return permission == "viewer"
end

local function field(label: string, value: any)
	Iris.Text({ ("%s: %s"):format(label, tostring(if value == nil then "unavailable" else value)) })
end

--=====================================================================
--  TABS
--=====================================================================

local function drawServer()
	local snap = Client.cache.snapshot
	if not snap or not snap.server then
		Iris.Text({ "Loading..." })
		return
	end
	local s = snap.server

	Iris.SameLine()
	if Iris.Button({ "Refresh" }).clicked() then
		Client.cache.snapshotAt = 0
	end
	Iris.End()

	Iris.Separator()
	field("Place", ("%s (%d)"):format(tostring(s.place), s.placeId))
	field("JobId", if s.jobId == "" then "<studio>" else s.jobId)
	field("Private", s.isPrivate)
	if s.isPrivate then
		field("PrivateServerId", s.privateServerId)
		field("OwnerId", s.privateServerOwnerId)
	end
	field("Uptime", ("%ds"):format(s.uptimeSeconds))
	field("Players", ("%d / %d"):format(s.playerCount, s.maxPlayers))
	field("Karts", s.kartCount)
	field("Match phase", s.matchPhase)
	Iris.Separator()
	field("AI (all)", s.aiCount)
	field("AI (developer)", s.devAiCount)
	field("Pickups (developer)", s.devPickupCount)

	-- LOCAL OVERRIDES. Nothing here crosses the wire.
	if localHooks.getForceRace then
		Iris.Separator()
		local on = localHooks.getForceRace() == true
		Iris.Text({ ("Local: force race state — %s"):format(if on then "ON" else "off") })
		if Iris.Button({ if on then "Disable local race state" else "Enable local race state" }).clicked() then
			localHooks.setForceRace(not on)
		end
		Iris.Text({ "Lets THIS client use items outside a race (BUGS #29). Local only." })
	end

	Iris.Separator()
	Iris.SameLine()
	if Iris.Button({ "Clear my pickups" }).clicked() then
		Client.send("clear_pickups", {})
	end
	if Iris.Button({ "Clear my AI" }).clicked() then
		Client.send("clear_ai", {})
	end
	Iris.End()

	if may("owner") then
		Iris.SameLine()
		if Iris.Button({ "Clear ALL dev pickups" }).clicked() then
			Client.send("clear_pickups", { all = true })
		end
		if Iris.Button({ "Clear ALL dev AI" }).clicked() then
			Client.send("clear_ai", { all = true })
		end
		Iris.End()
	end
end

local function drawPlayers()
	local snap = Client.cache.snapshot
	local list = snap and snap.players or {}

	Iris.Text({ ("%d player(s)"):format(#list) })
	Iris.Separator()

	for _, p in list do
		local label = ("%s (%s)"):format(p.name, p.displayName)
		if Iris.Button({ label }).clicked() then
			selected.userId = p.userId
			selected.name = p.name
			disarm()
			Client.refreshPlayer(p.userId, true)
		end
	end

	if not selected.userId then
		return
	end

	Iris.Separator()
	Iris.Text({ ("Selected: %s"):format(selected.name) })

	Iris.SameLine()
	if Iris.Button({ "Refresh" }).clicked() then
		Client.refreshPlayer(selected.userId, true)
	end
	if may("developer") and Iris.Button({ "Respawn" }).clicked() then
		Client.send("respawn_player", { targetUserId = selected.userId })
	end
	if may("developer") and Iris.Button({ "Bring to me" }).clicked() then
		Client.send("teleport", {
			targetUserId = selected.userId,
			kind = "player",
			toUserId = Client.localUserId(),
		})
	end
	if may("developer") and Iris.Button({ "Go to them" }).clicked() then
		Client.send("teleport", {
			targetUserId = Client.localUserId(),
			kind = "player",
			toUserId = selected.userId,
		})
	end
	Iris.End()

	if may("developer") then
		Iris.Text({ "Teleport me to checkpoint" })
		Iris.SameLine()
		for _, n in { 1, 2, 3, 4, 5, 6 } do
			if Iris.Button({ tostring(n) }).clicked() then
				Client.send("teleport", {
					targetUserId = Client.localUserId(),
					kind = "checkpoint",
					index = n,
				})
			end
		end
		Iris.End()
	end

	local info = Client.cache.player
	if not info then
		Iris.Text({ "No data yet." })
		return
	end

	if Iris.Tree({ "Identity" }).state.isUncollapsed.value then
		for _, k in { "userId", "name", "displayName", "accountAge", "ping" } do
			field(k, info.identity and info.identity[k])
		end
	end
	Iris.End()

	if Iris.Tree({ "Kart" }).state.isUncollapsed.value then
		local k = info.kart or {}
		field("present", k.present)
		field("name", k.name)
		field("speed", k.speed)
		field("AI driven", k.aiDriven)
		field("drift", k.driftState)
		field("nitro", k.nitro)
	end
	Iris.End()

	if Iris.Tree({ "Race" }).state.isUncollapsed.value then
		local r = info.race or {}
		field("place", r.place)
		field("field", r.fieldSize)
		field("lap", r.lap)
	end
	Iris.End()

	if Iris.Tree({ "Profile (read-only)" }).state.isUncollapsed.value then
		if Iris.Button({ "Load profile" }).clicked() then
			Client.refreshProfile(selected.userId)
		end
		local pr = Client.cache.profile
		if pr and pr.loaded then
			-- FIRST, and loudly. In Studio the store is mocked, so every
			-- number below is a fresh default and a restart wipes it.
			-- Without this line a reset profile reads as lost data.
			if pr.mockStore then
				Iris.Text({ "*** MOCK STORE — these values do NOT persist. Studio default. ***" })
			end
			Iris.Text({ ("bolt %s   crystals %s   xp %s"):format(
				tostring(pr.currency and pr.currency.bolt),
				tostring(pr.currency and pr.currency.crystals),
				tostring(pr.progression and pr.progression.xp)
			) })
			local eq = pr.equipped or {}
			Iris.Text({ ("equipped: Body=%s FWheel=%s RWheel=%s Paint=%s"):format(
				tostring(eq.Body), tostring(eq.FWheel), tostring(eq.RWheel), tostring(eq.Paint)
			) })
			local own = pr.ownership or {}
			Iris.Text({ ("parts %d%s   karts %d%s"):format(
				own.partsCount or 0,
				if own.partsTrimmed then " (list capped)" else "",
				own.kartsCount or 0,
				if own.kartsTrimmed then " (list capped)" else ""
			) })
			if #(own.parts or {}) > 0 then
				Iris.Text({ ("  owned: %s"):format(table.concat(own.parts, ", ")) })
			end
			local q = pr.quests or {}
			Iris.Text({ ("quests: day %s  week %s  month %s"):format(
				tostring(q.day), tostring(q.week), tostring(q.month)
			) })
			local pa = pr.pass or {}
			local dr = pr.drops or {}
			Iris.Text({ ("pass s%s xp %s claimed %s   drops pity %s opened %s"):format(
				tostring(pa.season), tostring(pa.xp), tostring(pa.claimed),
				tostring(dr.pity), tostring(dr.opened)
			) })
			Iris.Text({ ("schema v%s"):format(tostring(pr.schema)) })
		elseif pr then
			Iris.Text({ ("Not loaded. persistence=%s  mock=%s"):format(
				tostring(pr.persistenceEnabled), tostring(pr.mockStore)
			) })
		else
			Iris.Text({ "Press Load profile." })
		end
		Iris.Text({ "Read-only. No editing from here, by design." })
	end
	Iris.End()

	-- THE PANEL THAT WOULD HAVE ENDED THE SKINNING SAGA IN ONE RUN.
	-- Asked-for names beside the parts that actually exist.
	if Iris.Tree({ "Dressing (why is my kart not changing)" }).state.isUncollapsed.value then
		if Iris.Button({ "Check dressing" }).clicked() then
			Client.refreshDressing(selected.userId)
		end
		local d = Client.cache.dressing
		if d and d.hasKart then
			Iris.Text({ ("asked for : %s"):format(table.concat(d.asked or {}, ", ")) })
			Iris.Text({ ("matched   : %s"):format(table.concat(d.matched or {}, ", ")) })
			Iris.Text({
				("MISSING   : %s"):format(
					if #(d.missing or {}) > 0 then table.concat(d.missing, ", ") else "none"
				),
			})
			Iris.Separator()
			Iris.Text({ ("kart has  : %s"):format(table.concat(d.meshParts or {}, ", ")) })
			Iris.Text({ ("paint want: %s"):format(tostring(d.paintWanted)) })
			Iris.Text({ ("paint is  : %s"):format(table.concat(d.paintActual or {}, "  ")) })
		elseif d then
			Iris.Text({ "No kart spawned." })
		else
			Iris.Text({ "Press Check dressing." })
		end
	end
	Iris.End()

	if Iris.Tree({ "Items" }).state.isUncollapsed.value then
		local i = info.items or {}
		field("slots", i.slots)
		field("max held", i.maxHeld)
		Iris.Text({ "Slots are client-owned; the server cannot read them." })
	end
	Iris.End()
end

local function itemNames(): { string }
	local snap = Client.cache.snapshot
	local out = {}
	for _, item in (snap and snap.catalogue) or {} do
		table.insert(out, item.id)
	end
	if #out == 0 then
		table.insert(out, "<none>")
	end
	return out
end

local function drawPowerups()
	local names = itemNames()
	chosenItem = math.clamp(chosenItem, 1, #names)

	Iris.Text({ "Item" })
	for i, name in names do
		if Iris.Button({ (if i == chosenItem then "> " else "  ") .. name }).clicked() then
			chosenItem = i
		end
	end

	local itemId = names[chosenItem]
	Iris.Separator()

	if not may("developer") then
		Iris.Text({ "Viewer role: granting is disabled." })
		return
	end

	Iris.SameLine()
	if Iris.Button({ "Give to me" }).clicked() then
		Client.send("give_item", { targetUserId = Client.localUserId(), itemId = itemId })
	end
	if selected.userId and Iris.Button({ ("Give to %s"):format(selected.name) }).clicked() then
		Client.send("give_item", { targetUserId = selected.userId, itemId = itemId })
	end
	Iris.End()

	Iris.SameLine()
	if Iris.Button({ "Clear mine" }).clicked() then
		Client.send("clear_items", { targetUserId = Client.localUserId() })
	end
	if selected.userId and Iris.Button({ "Clear theirs" }).clicked() then
		Client.send("clear_items", { targetUserId = selected.userId })
	end
	Iris.End()
	Iris.Text({ "Clearing is advisory — item slots live on the client." })
end

local function drawAI()
	local snap = Client.cache.snapshot
	local canDrive = snap and snap.canDriveAI

	field("Developer AI", snap and snap.server and snap.server.devAiCount)
	field("Driving AI available here", canDrive)
	if not canDrive then
		Iris.Text({ "BotService only runs in the race place." })
	end
	Iris.Separator()

	if not may("developer") then
		Iris.Text({ "Viewer role: spawning is disabled." })
		return
	end

	local target = selected.userId or Client.localUserId()
	Iris.Text({ ("Spawns near: %s"):format(if selected.userId then selected.name else "me") })

	Iris.SameLine()
	if Iris.Button({ "Spawn static" }).clicked() then
		Client.send("spawn_ai", { mode = "static", targetUserId = target })
	end
	if canDrive and Iris.Button({ "Spawn driving" }).clicked() then
		Client.send("spawn_ai", { mode = "driving", targetUserId = target })
	end
	Iris.End()

	if Iris.Button({ "Remove my AI" }).clicked() then
		Client.send("clear_ai", {})
	end
end

local function drawWorld()
	local names = itemNames()
	chosenItem = math.clamp(chosenItem, 1, #names)
	local target = selected.userId or Client.localUserId()

	field("Developer pickups", Client.cache.snapshot and Client.cache.snapshot.server and Client.cache.snapshot.server.devPickupCount)
	Iris.Separator()

	if not may("developer") then
		Iris.Text({ "Viewer role: spawning is disabled." })
		return
	end

	Iris.Text({ ("Spawns near: %s"):format(if selected.userId then selected.name else "me") })
	Iris.SameLine()
	if Iris.Button({ ("Spawn %s box"):format(names[chosenItem]) }).clicked() then
		Client.send("spawn_pickup", { targetUserId = target, itemId = names[chosenItem] })
	end
	if Iris.Button({ "Spawn random box" }).clicked() then
		Client.send("spawn_pickup", { targetUserId = target })
	end
	Iris.End()

	if Iris.Button({ "Remove my pickups" }).clicked() then
		Client.send("clear_pickups", {})
	end
end

local function drawTune()
	local snap = Client.cache.snapshot
	local tunables = (snap and snap.tunables) or {}
	local target = selected.userId or Client.localUserId()

	Iris.Text({ ("Target: %s"):format(if selected.userId then selected.name else "me") })
	Iris.Text({ "Applies to that player's CURRENT kart, and dies with it." })
	Iris.Separator()

	if not may("owner") then
		Iris.Text({ "Tuning is owner-only." })
		return
	end

	for _, t in tunables do
		local current = tuneValue[t.key] or t.default
		Iris.Text({ ("%s: %.2f  (%.1f - %.1f)"):format(t.label, current, t.min, t.max) })

		-- Stepped buttons rather than a drag widget: this has to commit a
		-- value over a remote, and a slider fires one request per pixel.
		Iris.SameLine()
		for _, step in { -0.5, -0.1, 0.1, 0.5 } do
			if Iris.Button({ ("%+.1f"):format(step) }).clicked() then
				tuneValue[t.key] = math.clamp(current + step, t.min, t.max)
				Client.send("set_tunable", { targetUserId = target, key = t.key, value = tuneValue[t.key] })
			end
		end
		Iris.End()

		Iris.SameLine()
		for _, preset in { 0.5, 1, 2, 3 } do
			if preset >= t.min and preset <= t.max and Iris.Button({ ("x%g"):format(preset) }).clicked() then
				tuneValue[t.key] = preset
				Client.send("set_tunable", { targetUserId = target, key = t.key, value = preset })
			end
		end
		if Iris.Button({ "reset" }).clicked() then
			tuneValue[t.key] = t.default
			Client.send("reset_tunable", { targetUserId = target, key = t.key })
		end
		Iris.End()
		Iris.Separator()
	end

	-- THE GRAPH. Local speed over the last few seconds.
	if #speedHistory > 1 then
		local peak = 0
		for _, v in speedHistory do
			peak = math.max(peak, v)
		end
		-- ARGUMENTS ARE (Text, Height, Min, Max, TextOverlay); the VALUES
		-- go in the states table, not the arguments. Getting that wrong
		-- silently plots the height as data.
		--
		-- `speedHistory` is mutated in place, so the state holds the same
		-- table across frames and `:set(v, true)` forces Iris to re-read
		-- it — that second argument is what makes a live graph update at
		-- all, since the reference never changes.
		local values = Iris.State(speedHistory)
		values:set(speedHistory, true)
		Iris.PlotLines({
			"Speed (studs/s)",
			80,
			0,
			math.max(peak * 1.1, 10),
			("%.0f"):format(speedHistory[#speedHistory]),
		}, { values = values })
	else
		Iris.Text({ "Speed graph: get in a kart." })
	end

	-- FRAME TIME, with the simulation budget called out.
	if #frameHistory > 1 then
		local last = frameHistory[#frameHistory]
		local peak = 0
		for _, v in frameHistory do
			peak = math.max(peak, v)
		end
		local overlay = ("%.1fms   budget %.0fms   over: %d"):format(last, BUDGET_MS, overBudget)
		local fValues = Iris.State(frameHistory)
		fValues:set(frameHistory, true)
		Iris.PlotLines(
			{ "Frame time (ms)", 70, 0, math.max(peak * 1.1, BUDGET_MS * 1.5), overlay },
			{ values = fValues }
		)
		if last > BUDGET_MS then
			Iris.Text({ "OVER BUDGET — the kart is moving slower than real time." })
		end
	end
end

local function drawModerate()
	if not selected.userId then
		Iris.Text({ "Select a player on the Players tab first." })
		return
	end
	Iris.Text({ ("Target: %s (%d)"):format(selected.name, selected.userId) })
	Iris.Text({ "You cannot moderate yourself or anyone at your rank or above." })
	Iris.Separator()

	if not may("developer") then
		Iris.Text({ "Viewer role: moderation is disabled." })
		return
	end

	-- KICK — developer level, reversible by rejoining.
	local kickArmed = armed.action == "kick" and armed.forUserId == selected.userId
	if Iris.Button({ if kickArmed then "CONFIRM KICK" else "Kick" }).clicked() then
		armOrFire("kick", selected.userId, function()
			Client.send("kick_player", { targetUserId = selected.userId, reason = banReason })
		end)
	end

	if not may("owner") then
		Iris.Separator()
		Iris.Text({ "Banning is owner-only." })
		return
	end

	Iris.Separator()
	Iris.Text({ ("Duration: %s"):format(if banDays <= 0 then "PERMANENT" else (banDays .. " day(s)")) })
	Iris.SameLine()
	for _, d in { 0, 1, 7, 30 } do
		if Iris.Button({ if d == 0 then "perm" else (d .. "d") }).clicked() then
			banDays = d
			disarm() -- changing the terms invalidates an existing arm
		end
	end
	Iris.End()

	local banArmed = armed.action == "ban" and armed.forUserId == selected.userId
	if Iris.Button({ if banArmed then "CONFIRM BAN — THIS PERSISTS" else "Ban" }).clicked() then
		armOrFire("ban", selected.userId, function()
			Client.send("ban_player", {
				targetUserId = selected.userId,
				durationDays = banDays,
				reason = banReason,
				includeAlts = false,
				confirm = true,
			})
		end)
	end

	local unbanArmed = armed.action == "unban" and armed.forUserId == selected.userId
	if Iris.Button({ if unbanArmed then "CONFIRM UNBAN" else "Unban" }).clicked() then
		armOrFire("unban", selected.userId, function()
			Client.send("unban_player", { targetUserId = selected.userId, confirm = true })
		end)
	end

	Iris.Text({ "Bans use Roblox BanAsync — they do not work in Studio." })
end

local function drawLogs()
	if Iris.Button({ "Refresh" }).clicked() then
		Client.refreshLogs(true)
	end
	Iris.Separator()
	local entries = Client.cache.logs
	if not entries or #entries == 0 then
		Iris.Text({ "No entries." })
		return
	end
	for _, e in entries do
		Iris.Text({
			("%s %s %s %s%s"):format(
				os.date("%H:%M:%S", e.at),
				tostring(e.name),
				tostring(e.command),
				if e.success then "OK" else ("FAIL/" .. tostring(e.code)),
				if e.summary and e.summary ~= "" then "  " .. e.summary else ""
			),
		})
	end
end

--=====================================================================
--  LIFECYCLE
--=====================================================================

function DevConsoleController.toggle()
	visible = not visible
end

function DevConsoleController.isOpen(): boolean
	return visible
end

-- `start` is called only after the server has confirmed this client may
-- use the console. An unauthorized player never reaches it, so Iris is
-- never even initialised for them.
function DevConsoleController.start(grantedRole: string, hotkey: Enum.KeyCode, hooks: any?)
	if started then
		return
	end
	started = true
	role = grantedRole
	localHooks = hooks or {}

	Iris.Init()

	Iris:Connect(function()
		if not visible then
			return
		end

		-- Cheap and throttled inside the client cache; safe to call every
		-- frame because it no-ops until the age threshold passes.
		sampleSpeed()
		sampleFrame()
		Client.refreshSnapshot(2)
		if tab == "Logs" then
			Client.refreshLogs()
		end

		Iris.Window({ ("Go Karts GO! — Dev Console  [%s]"):format(role) }, { size = Iris.State(Vector2.new(520, 460)) })

		Iris.SameLine()
		for _, name in TABS do
			if Iris.Button({ (if tab == name then "[" .. name .. "]" else name) }).clicked() then
				tab = name
				disarm()
			end
		end
		Iris.End()
		Iris.Separator()

		if tab == "Server" then
			drawServer()
		elseif tab == "Players" then
			drawPlayers()
		elseif tab == "Power-Ups" then
			drawPowerups()
		elseif tab == "AI" then
			drawAI()
		elseif tab == "World" then
			drawWorld()
		elseif tab == "Tune" then
			drawTune()
		elseif tab == "Moderate" then
			drawModerate()
		else
			drawLogs()
		end

		if Client.cache.lastMessage ~= "" then
			Iris.Separator()
			Iris.Text({ Client.cache.lastMessage })
		end

		Iris.End()
	end)

	-- BOUND HERE, NOT THROUGH KartClient's Input MODULE. Input releases
	-- its bindings whenever you stop driving, and a console you cannot
	-- open while out of a kart is the opposite of useful.
	--
	-- `gameProcessed` is respected so the hotkey does nothing while a
	-- text box has focus.
	UserInputService.InputBegan:Connect(function(input, typing)
		if not typing and input.KeyCode == hotkey then
			DevConsoleController.toggle()
		end
	end)
end

return DevConsoleController
