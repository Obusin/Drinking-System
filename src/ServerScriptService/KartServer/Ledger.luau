--[[
	Ledger — every balance mutation, written down.

	WHY THIS EXISTS BEFORE ANY OF IT PERSISTS
	-----------------------------------------
	A balance with no history behind it is unfalsifiable: no dispute is
	answerable and no exploit is traceable. The fix is to record the
	transactions, and the thing about records is that you cannot add them
	retroactively. Data not written down is gone, so this goes in first
	and stays quiet until it is needed.

	TWO SINKS, NEITHER OF THEM EXTERNAL
	-----------------------------------
	  1. AnalyticsService — free, built in, and purpose-built for
	     currency. Gives Creator Dashboard charts for where Bolt comes
	     from and where it goes. Answers "is the economy healthy" and
	     never "what did this account do".

	  2. A DataStore ledger, keyed <userId>_<day>. Answers the second
	     question for one player at a time. It cannot answer anything
	     ACROSS players — there is no WHERE and no sort — which is the
	     known cost of not having Postgres yet, and is why the row shape
	     below is exactly the table Supabase will want. Migration is then
	     a copy rather than a translation.

	RULES THIS FILE WILL NOT BREAK
	------------------------------
	  * Fire and forget. A failed ledger write is a lost row, never a
	    lost race. Nothing here is allowed to yield the caller or throw
	    into it.
	  * Batched. One UpdateAsync per player per flush, never one per
	    event — the ledger competes with profile saves for the same
	    request budget, and losing saves to win logs is a bad trade.
	  * userId only. Roblox is a minors' platform: log the id and the
	    event, never a display name, never anything identifying a person
	    off-platform.
--]]

local AnalyticsService = game:GetService("AnalyticsService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Ledger = {}

local STORE_NAME = "BloxKart_Ledger_v1"
local FLUSH_EVERY = 60
-- A day's rows for one player, far under the 4MB key limit but finite
-- so a pathological session cannot make a key unwritable.
local MAX_ROWS_PER_KEY = 400

-- userId -> { rows }
local pending: { [number]: { any } } = {}
local store = nil
local disabled = false

local function today(): number
	return math.floor(os.time() / 86400)
end

-- Studio has no DataStore access unless it is switched on, and a
-- published place can still be throttled. Either way this must go quiet
-- rather than erroring on a path the economy runs through.
local function ensureStore(): boolean
	if disabled then
		return false
	end
	if store then
		return true
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok and result then
		store = result
		return true
	end
	disabled = true
	warn("[Ledger] no DataStore access — history will not be written. Enable API access for Studio testing.")
	return false
end

--=====================================================================
--  WRITE
--=====================================================================

-- One mutation. `delta` is signed: awards positive, spends negative.
--
-- THE ROW SHAPE IS THE FUTURE POSTGRES TABLE. Do not add a field here
-- without adding it there, and do not rename one to be tidier — the
-- whole point of matching is that the eventual migration is a copy.
function Ledger.record(player: Player?, kind: string, delta: number, balanceAfter: number, reason: string, matchId: string?)
	if not player or delta == 0 then
		return
	end

	local row = {
		at = os.time(),
		kind = kind, -- "bolt" | "crystals" | "xp"
		delta = delta,
		balanceAfter = balanceAfter,
		reason = reason,
		matchId = matchId,
		-- Answers "did the update cause this", which is the question
		-- everybody forgets to make answerable.
		placeVersion = game.PlaceVersion,
	}

	local list = pending[player.UserId]
	if not list then
		list = {}
		pending[player.UserId] = list
	end
	table.insert(list, row)

	-- ANALYTICS IS SEPARATE AND IMMEDIATE. It is aggregate-only, so
	-- there is nothing to batch and nothing to lose by sending it now.
	--
	-- pcall'd because the signature is Roblox's and a mismatch must not
	-- take the economy down with it — this is instrumentation, and
	-- instrumentation that can break the thing it measures is worse than
	-- no instrumentation.
	pcall(function()
		AnalyticsService:LogEconomyEvent(
			player,
			if delta > 0 then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink,
			kind,
			math.abs(delta),
			balanceAfter,
			Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
			reason
		)
	end)
end

--=====================================================================
--  FLUSH
--=====================================================================

local function flushPlayer(userId: number)
	local rows = pending[userId]
	if not rows or #rows == 0 then
		return
	end
	pending[userId] = nil

	if not ensureStore() then
		return
	end

	local key = ("%d_%d"):format(userId, today())
	-- UpdateAsync, not SetAsync: two servers can hold the same player in
	-- the same day across a rejoin, and last-write-wins would drop one
	-- of their sessions entirely.
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(old)
			local list = old or {}
			for _, row in rows do
				if #list >= MAX_ROWS_PER_KEY then
					break
				end
				table.insert(list, row)
			end
			return list
		end)
	end)
	if not ok then
		-- Dropped, and said once per failure rather than retried. A
		-- retry loop here would compete with profile saves for budget,
		-- which is exactly the trade this file refuses to make.
		warn("[Ledger] flush failed for " .. tostring(userId) .. ": " .. tostring(err))
	end
end

function Ledger.flushAll()
	for userId in pending do
		task.spawn(flushPlayer, userId)
	end
end

function Ledger.start()
	-- Jittered so a full server does not flush on one tick and exhaust
	-- the request budget in a single spike.
	task.spawn(function()
		while true do
			task.wait(FLUSH_EVERY + math.random() * 10)
			Ledger.flushAll()
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		flushPlayer(player.UserId)
	end)

	-- Last chance. Without this, up to a minute of history dies with
	-- every server shutdown, which over a day is most of it.
	game:BindToClose(function()
		Ledger.flushAll()
		-- Studio closes instantly and the spawned flushes never land.
		if not RunService:IsStudio() then
			task.wait(3)
		end
	end)
end

return Ledger
