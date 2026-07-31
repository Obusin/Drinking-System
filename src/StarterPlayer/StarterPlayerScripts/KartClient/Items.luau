--[[
	Items — pickup, hold one, fire it at the racer ahead.

	Boxes are server-owned (see RaceService): the client asks, the server
	decides whether the box was still there and which item you got.
	Rolling client-side would let a client pick its own item.

	Hits are relayed too. A client naming its own victim and telling them
	directly would be trivially forgeable — only the TARGET's client ever
	applies an effect to itself.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")

local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))
local TagZones = require(BloxKart:WaitForChild("TagZones"))
local Registry = require(BloxKart:WaitForChild("Items"))
local Standings = require(BloxKart:WaitForChild("Standings"))

local IT = Config.Items

local Items = {}
Items.__index = Items

--=====================================================================
--  BOX ANIMATION
--
--  Spin and bob are client-side. Every client animating its own copy
--  costs nothing to replicate and looks identical for everyone, so
--  there's no reason to do it on the server.
--
--  Runs for every tagged box in the world whether or not you're
--  driving, so boxes are alive while you're walking around too.
--=====================================================================
function Items.startBoxes()
	local RunService = game:GetService("RunService")
	local home = {} -- original CFrame per box, so bob is relative

	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		for _, box in CollectionService:GetTagged(IT.BoxTag) do
			if box:IsA("BasePart") and box.Parent then
				if not home[box] then
					home[box] = box.CFrame
					box.Anchored = true
					box.CanCollide = false
					box.CanQuery = true -- or the pickup query can't see it
					box.Massless = true
					if box.Size.Magnitude < 0.5 then
						box.Size = Vector3.one * IT.BoxSize
					end
				end
				local base = home[box]
				local bob = math.sin(t * IT.BoxBobRate) * IT.BoxBob
				box.CFrame = base
					* CFrame.new(0, bob, 0)
					* CFrame.Angles(0, math.rad(IT.BoxSpin) * t, 0)
			end
		end
	end)
end

function Items.new(kart: Model)
	local self = setmetatable({
		kart = kart,
		boxes = TagZones.new(IT.BoxTag, { cooldown = IT.PickupCooldown, forceQueryable = true }),
		-- Up to IT.MaxHeld slots, used first-in-first-out. Each is either
		-- resolved ({ item = module }) or still spinning
		-- ({ result = module, ... }). A spinning slot occupies space but
		-- can't be fired.
		held = {},
		pickup = BloxKart:WaitForChild("KartItemPickup"),
		hit = BloxKart:WaitForChild("KartItemHit"),
		incoming = nil, -- a hit waiting to be applied next frame
		hazards = TagZones.new(IT.HazardTag, { cooldown = 0.5, forceQueryable = true }),
		drops = TagZones.new(IT.DropTag, { cooldown = 0.5, forceQueryable = true }),
		-- Boxes we've asked the server about and haven't heard back on.
		pending = {},
		hazardRemote = BloxKart:WaitForChild("KartHazard"),
		projectileRemote = BloxKart:WaitForChild("KartProjectile"),
		conns = {},
		gained = 0,
	}, Items)

	table.insert(
		self.conns,
		self.pickup.OnClientEvent:Connect(function(id)
			table.clear(self.pending)
			local item = Registry.byId(id)
			-- Re-checked here as well as before requesting: the server may
			-- have granted while a slot was filling.
			if item and #self.held < IT.MaxHeld then
				-- COUNTED HERE, because this is the only place that learns
				-- a box was actually ours: the request goes up hopefully
				-- and the server has the final say. Read and cleared by
				-- Update, so it reaches the frame's event table like
				-- everything else does.
				self.gained += 1
				-- The server already decided WHAT you got. The roulette is
				-- purely presentation over a settled result — it never picks
				-- anything, so it can't disagree with the server.
				local now = os.clock()
				table.insert(self.held, {
					result = item,
					startedAt = now,
					endsAt = now + IT.RouletteTime,
					nextTick = now,
					showIndex = 1,
				})
			end
		end)
	)
	table.insert(
		self.conns,
		self.hit.OnClientEvent:Connect(function(payload)
			self.incoming = payload
		end)
	)
	return self
end

-- Everything you were holding, gone. Called only on a LANDED hit, so a
-- shield protects your stack as well as your speed — which is most of
-- what makes holding one worth the slot.
--
-- Slots mid-roulette go too. Keeping a reveal alive through a spinout
-- would mean an item arriving seconds after the hit that took it.
function Items:_dropAll(events, sim)
	if not IT.DropOnHit or #self.held == 0 then
		return
	end
	events.dropped = #self.held

	-- Scattered onto the track rather than deleted. Somebody paid for
	-- these by being spun, so somebody should be able to pick them up —
	-- including the person who landed the hit, and including you if you
	-- recover fast enough.
	--
	-- Only resolved slots: one still spinning has no item yet, and the
	-- roulette is about to be thrown away with it.
	local ids = {}
	for _, slot in self.held do
		if slot.item then
			table.insert(ids, slot.item.Id)
		end
	end
	if #ids > 0 and sim then
		self.hazardRemote:FireServer("spill", CFrame.lookAt(sim.pos, sim.pos + sim.forward, sim.up), ids)
	end

	table.clear(self.held)
end

-- Wipe the stack with no event and no punishment. Used between rounds:
-- carrying items over would mean whoever finished last round holding a
-- missile starts the next one already armed.
--
-- Distinct from _dropAll, which is the penalty for being hit and has to
-- announce itself.
function Items:Clear()
	table.clear(self.held)
	table.clear(self.pending)
end

-- Interval between names, growing as the spin progresses so it decays
-- instead of stopping dead.
local function tickInterval(t: number): number
	local eased = math.clamp(t, 0, 1) ^ (1 / IT.RouletteEase)
	return IT.RouletteTickFast + (IT.RouletteTickSlow - IT.RouletteTickFast) * eased
end

-- Advances any spinning slots. Emits `ticks` (how many names went past
-- this frame) and `landed` so the caller owns the sound, keeping this
-- module free of any Audio dependency.
function Items:_spin(events)
	local now = os.clock()
	for _, slot in self.held do
		if slot.result then
			if now >= slot.endsAt then
				-- Land on what the server actually rolled.
				slot.item = slot.result
				slot.result = nil
				events.landed = slot.item.Id
			elseif now >= slot.nextTick then
				local t = (now - slot.startedAt) / IT.RouletteTime
				slot.nextTick = now + tickInterval(t)
				slot.showIndex += 1
				events.ticks = (events.ticks or 0) + 1
			end
		end
	end
end

-- Returns events: { used = id, failed = reason, hit = payload,
-- ticks = n, landed = id }
function Items:Update(sim, input): { [string]: any }
	local events = {}
	self:_spin(events)

	if self.gained > 0 then
		events.gained = self.gained
		self.gained = 0
	end

	-- Pickup. The server has the final say on whether the box was still
	-- there, so this is only a request.
	if #self.held < IT.MaxHeld then
		-- Dropped items first: someone already paid for those, and a box
		-- will still be there next lap.
		local box = self.drops:Touch(sim.hitbox.CFrame, sim.hitbox.Size)
			or self.boxes:Touch(sim.hitbox.CFrame, sim.hitbox.Size)
		-- `Taken` is set by the SERVER, so there's a round-trip window where
		-- we'd happily ask again for a box we already claimed — and get
		-- granted twice. Two boxes filling three slots was this.
		if box and not box:GetAttribute(Names.TAKEN) and not self.pending[box] then
			self.pending[box] = true
			self.pickup:FireServer(box)
		end
	end

	-- Use.
	-- First slot that has finished spinning. A slot mid-roulette holds
	-- space but can't be fired, so you can't jump the reveal.
	local readyIndex = nil
	for i, slot in self.held do
		if slot.item then
			readyIndex = i
			break
		end
	end

	-- Both keys drained every frame, whichever fired, so a queued press
	-- can't go off later in the wrong direction.
	local fireFwd = input.consumeItemUse()
	local fireBack = input.consumeItemBack()
	-- Looking back aims back, whichever key you pressed — you're throwing
	-- at what you can actually see.
	local back = fireBack or (IT.LookBackAims and input.lookingBack and fireFwd)

	if (fireFwd or fireBack) and readyIndex then
		local order = Standings.order(Standings.allKarts())
		-- Read before ctx so `fire` below can stamp the payload with it.
		local item = self.held[readyIndex].item
		local ctx = {
			sim = sim,
			kart = self.kart,
			-- Which way this one was thrown. Each item decides what that
			-- means for it — a hazard flips where it lands, a missile flips
			-- who it hunts.
			back = back,
			-- 0..1 wind-up. Backward drops are instant, so they're always
			-- at full — there's nothing to charge when you're placing
			-- something under your own back wheels.
			charge = if fireBack then 1 else input.itemCharge,
			aheadOf = function(k)
				return Standings.ahead(order, k)
			end,
			-- The racer this throw is aimed at, in whichever direction.
			-- Saves every targeting item repeating the same branch.
			victimOf = function(k)
				return if back then Standings.behind(order, k) else Standings.ahead(order, k)
			end,
			-- Everyone in the direction this was thrown, GEOMETRICALLY.
			--
			-- Not from the standings. Those only contain karts whose
			-- progress has replicated, so a racer who hasn't reported yet
			-- simply isn't in them — and neither are you, in which case
			-- your own place comes back 0 and "everyone ahead of me" is an
			-- empty list. That's why Lightning appeared to do nothing.
			--
			-- A dot product needs nothing replicated and can't be empty for
			-- a reason nobody can see.
			everyone = function()
				local out = {}
				local sign = if back then -1 else 1
				for _, k in Standings.allKarts() do
					local hb = k.PrimaryPart
					if k ~= self.kart and hb and (hb.Position - sim.pos):Dot(sim.forward) * sign > 0 then
						table.insert(out, k)
					end
				end
				return out
			end,
			dropHazard = function(cf, itemId, power)
				self.hazardRemote:FireServer("drop", cf, itemId, back, power)
			end,
			fireProjectile = function(itemId)
				self.projectileRemote:FireServer(itemId, nil, back)
			end,
			fire = function(target, payload)
				-- Stamped here, so no item module has to remember to include
				-- it and none of them can disagree about their own name. The
				-- server uses it for the hit feed.
				payload.item = item.Id
				self.hit:FireServer(target, payload)
			end,
		}
		-- Only removed if it actually fired, so an item that couldn't do
		-- anything stays in your hand rather than being silently binned.
		local ok, reason = item.Use(ctx)
		if ok ~= false then
			table.remove(self.held, readyIndex)
			events.used = item.Id
		else
			events.failed = reason
		end
	end

	-- Hazards. Detected locally and applied to OURSELVES only, same rule
	-- as everything else: no client ever tells another client it was hit.
	local hz = self.hazards:Touch(sim.hitbox.CFrame, sim.hitbox.Size)
	if hz then
		local armAt = hz:GetAttribute(Names.ARM_AT)
		local mine = hz:GetAttribute(Names.OWNER) == Players.LocalPlayer.UserId
		-- Your own mine can't hit you until it's armed, so dropping one at
		-- speed doesn't spin the person who dropped it.
		-- Your own hazard, if the rule says so, never hits you at all.
		--
		-- A timer alone can't fix a forward throw: the trap is ahead of
		-- you and you are driving at it, so any grace period just delays
		-- the moment you hit your own item. Others still trigger it the
		-- instant it exists, which is the asymmetry that matters.
		-- GetServerTimeNow, matching what the server stamped. os.clock()
		-- was being compared against a server os.clock(), and those are
		-- process uptimes on two different machines — the check was
		-- meaningless in both directions.
		local live = not mine
			or (
				not IT.HazardOwnerImmune
				and not (typeof(armAt) == "number" and workspace:GetServerTimeNow() < armAt)
			)
		if live then
			-- Which hazard this is comes off the part, so one code path
			-- serves mines, oil and anything added later.
			local item = Registry.byId(hz:GetAttribute(Names.HAZARD_ITEM) or "Mine")
			if item then
				local landed = sim:Spinout(item.SpinTime, item.SpeedKeep, item.StunTime)
				events[if landed then "hit" else "blocked"] = {
					hazard = true,
					note = item.HitNote or 1,
					-- Named, so a hazard can have its own hit sound the same
					-- way a relayed item does. Nothing has one yet; without
					-- this, nothing ever could without a second mechanism.
					item = item.Id,
				}
				if landed then
					self:_dropAll(events, sim)
				end
				self.hazardRemote:FireServer("hit", hz)
			end
		end
	end

	-- Being hit is applied here rather than in the remote handler, so it
	-- lands inside the frame loop with everything else.
	if self.incoming then
		local payload = self.incoming
		self.incoming = nil
		local landed = sim:Spinout(payload.spin, payload.keep, payload.stun)
		-- Scramble carries no spin, so Spinout reports nothing landed and
		-- the shield check has to be asked separately — otherwise a
		-- zero-spin hit would bypass a shield entirely.
		if payload.reverse and payload.reverse > 0 and not sim:HasShield() then
			sim:Scramble(payload.reverse)
			landed = true
		end
		events[if landed then "hit" else "blocked"] = payload

		-- Landing a hit costs the victim their stack — but only if it
		-- actually SPUN them. Scramble carries no spin: it inverts your
		-- steering, and taking three items as well for that would make the
		-- cheapest item in the pool the most punishing.
		--
		-- Hazards already do this in their own branch below; this is the
		-- relayed path, which is every missile and every Lightning, and it
		-- was quietly not doing it at all.
		if landed and (payload.spin or 0) > 0 then
			self:_dropAll(events, sim)
		end
	end

	return events
end

-- What each slot should display, front first. Spinning slots cycle
-- through the whole pool so the reveal reads as a roulette.
function Items:HeldSlots(): { { name: string, icon: string, rolling: boolean } }
	local out = {}
	local pool = Registry.All
	for _, slot in self.held do
		-- A spinning slot shows whichever item it's cycling past, icon and
		-- all, so the reveal is something you watch rather than read.
		local shown = slot.item or pool[(slot.showIndex - 1) % #pool + 1]
		table.insert(out, {
			name = shown.Name,
			icon = shown.Icon or "",
			tint = shown.Tint,
			rolling = slot.item == nil,
		})
	end
	return out
end

function Items:Destroy()
	for _, c in self.conns do
		c:Disconnect()
	end
	self.boxes:Destroy()
	self.hazards:Destroy()
	self.drops:Destroy()
end

return Items
