--[[
	DataService — the player profile.

	Session-locked, on ProfileStore. The plan and the reasoning live in
	the vault at "BloxKart Data Security and Drops"; this is the
	implementation of Parts 1 and 2.

	OFF BY DEFAULT, AND THAT IS THE POINT
	-------------------------------------
	`Config.Data.Enabled` gates whether any of this becomes the source of
	truth. The client is still authoritative on finish time and on upward
	progress, and currency saved from numbers a modified client can
	choose is an exploit with a database behind it. Storing it first and
	securing it later means the first thing the store contains is the
	exploit.

	So this is built, testable, and not yet trusted. `Config.Data.Mock`
	runs it against ProfileStore's mock store so a profile can be watched
	round-tripping in Studio without touching live player data.

	WHAT THIS DOES NOT DO
	---------------------
	It does not know what a Bolt is. `Progress` owns balances and is the
	only thing that changes one; this owns loading, saving and the shape
	of the record. Two modules that both write a balance is the dupe this
	whole design exists to avoid.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local ProfileStore = require(script.Parent.Parent.Packages.ProfileStore)

local D = Config.Data

local DataService = {}

--=====================================================================
--  THE TEMPLATE
--
--  Every field a profile can have, with its default. This IS the
--  schema: `Reconcile` fills missing keys from here on load, so adding
--  a field is adding a line and needs no migration step at all. That is
--  why it is flat and why nothing in it is computed.
--
--  Do not put anything unbounded here. Receipts have their own store
--  and the ledger has another, for exactly this reason — a profile that
--  grows forever eventually stops saving.
--=====================================================================
local TEMPLATE = {
	-- Migration marker. Reconcile handles additive changes; this is for
	-- structural ones, where a field changes meaning rather than
	-- appearing. Forward-only, run once at load.
	schema = 1,

	bolt = 0,
	crystals = 0,

	-- Owned PARTS, not skins. Buying a set writes three keys; equipping
	-- picks per slot. A set is never the unit of ownership, which is
	-- what makes mixing possible without a second system.
	parts = {},
	equipped = { Body = "stock", FWheel = "stock", RWheel = "stock" },

	karts = {},
	fragments = {},
	focus = "",

	xp = 0,
	stats = {},

	quests = {
		day = 0,
		d = { 0, 0, 0 },
		reroll = false,
		week = 0,
		w = { 0, 0, 0, 0, 0 },
		month = 0,
		m = 0,
	},

	pass = { season = 0, xp = 0, claimed = {} },
	drops = { pity = 0, opened = 0 },
}

DataService.Template = TEMPLATE

--=====================================================================
--  STATE
--=====================================================================
local store = nil
local profiles: { [Player]: any } = {}

-- Fired when a profile is ready, and again for anyone already loaded
-- when a listener attaches. Systems start in an order this module does
-- not control, so "tell me when it is ready" has to work regardless of
-- who got there first.
local listeners: { (Player, any) -> () } = {}

function DataService.onLoaded(fn: (Player, any) -> ())
	table.insert(listeners, fn)
	for player, profile in profiles do
		task.spawn(fn, player, profile.Data)
	end
end

--=====================================================================
--  MIGRATION
--
--  Additive changes need nothing — Reconcile covers them. This is only
--  for a field whose MEANING changed, which is rare and should stay
--  rare. Each step takes n to n+1 and runs once.
--=====================================================================
local migrations: { (any) -> () } = {
	-- [1] = function(data) ... end,  -- 1 -> 2
}

local function migrate(data)
	while data.schema < TEMPLATE.schema do
		local step = migrations[data.schema]
		if not step then
			-- A gap here means a schema bump without a migration. Louder
			-- than a silent skip, because the silent version corrupts
			-- quietly and this one just tells you.
			warn(("[DataService] no migration from schema %d — stopping."):format(data.schema))
			return
		end
		step(data)
		data.schema += 1
	end
end

--=====================================================================
--  LOAD / RELEASE
--=====================================================================
local function keyFor(player: Player): string
	return "Player_" .. tostring(player.UserId)
end

local function onPlayerAdded(player: Player)
	if not store then
		return
	end

	local profile = store:StartSessionAsync(keyFor(player), {
		-- Stop trying the moment they leave. Without this a player who
		-- joins and immediately leaves leaves a request retrying against
		-- a session that will never be wanted.
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if not profile then
		-- Another server holds the lock and would not give it up. Kicking
		-- is the correct answer and the kind one: the alternative is a
		-- session that silently saves nothing, and the player finds out
		-- when their progress is gone.
		player:Kick("Could not load your data. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId) -- GDPR association
	profile:Reconcile() -- fills anything the template gained since last save
	migrate(profile.Data)

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		-- Ended by another server taking the lock, or by us. Either way
		-- this server must stop writing, and the only safe way to
		-- guarantee that is to stop having them here.
		if player.Parent == Players then
			player:Kick("Your data was opened elsewhere. Please rejoin.")
		end
	end)

	if player.Parent ~= Players then
		-- Left while we were loading.
		profile:EndSession()
		return
	end

	profiles[player] = profile
	for _, fn in listeners do
		task.spawn(fn, player, profile.Data)
	end
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		profile:EndSession()
	end
end

--=====================================================================
--  READ
--=====================================================================

-- The live data table, or nil. NIL IS NORMAL and every caller must
-- handle it: the profile may still be loading, may have failed, or
-- persistence may simply be off. A caller that assumes a profile is a
-- caller that breaks the game when the DataStore has a bad minute.
function DataService.get(player: Player)
	local profile = profiles[player]
	if profile and profile:IsActive() then
		return profile.Data
	end
	return nil
end

function DataService.isEnabled(): boolean
	return store ~= nil
end

--=====================================================================
--  START
--=====================================================================
function DataService.start()
	if not D.Enabled then
		warn("[DataService] disabled — nothing persists. Config.Data.Enabled to turn it on.")
		return
	end

	local ok, result = pcall(function()
		return ProfileStore.New(D.StoreName, TEMPLATE)
	end)
	if not ok or not result then
		warn("[DataService] could not create the store: " .. tostring(result))
		return
	end

	-- MOCK IN STUDIO BY DEFAULT. A test that writes to a real profile is
	-- indistinguishable from a bug that does, and the mock store behaves
	-- the same in every way that matters here.
	if D.Mock or RunService:IsStudio() then
		store = result.Mock
		warn("[DataService] MOCK store — nothing written here survives the session.")
	else
		store = result
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- ProfileStore handles autosave and shutdown itself. Nothing here
	-- needs a BindToClose, and adding one would be a second thing
	-- deciding when a profile is written.
end

return DataService
