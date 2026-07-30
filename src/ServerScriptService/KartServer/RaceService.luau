--[[
	RaceService — relays race progress so every client can see the field.

	Clients own their own simulation, so each one knows exactly where IT
	is and nothing about anyone else. Attributes written by a client
	don't replicate, so progress comes up over a RemoteEvent and the
	server writes it onto the kart, where it replicates to everyone.

	Deliberately thin: the server does not yet verify that a reported
	score is achievable. This is the seam where anti-cheat goes when the
	race stops being a placeholder — one function, one place.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Standings = require(BloxKart:WaitForChild("Standings"))
local Names = require(BloxKart:WaitForChild("Names"))
local Config = require(BloxKart:WaitForChild("Config"))
local Match = require(BloxKart:WaitForChild("Match"))
local Items = require(BloxKart:WaitForChild("Items"))
local MatchService = require(script.Parent.MatchService)
local KartService = require(script.Parent.KartService)

local RaceService = {}

-- "X hit Y with Z", to everyone. A hit is a spectacle: half the value of
-- a well-timed missile is the lobby seeing it land, and in a race you
-- rarely even see the person you hit.
--
-- Server-side because only the server knows both ends — the attacker's
-- client can't be trusted to name its own victim, and the victim's client
-- doesn't know who fired.
function RaceService.announce(itemId: string?, by: Player?, victim: Player?)
	if not (RaceService.feed and victim and itemId) then
		return
	end
	local item = Items.byId(itemId)
	RaceService.feed:FireAllClients({
		item = if item then item.Name else itemId,
		-- Nil `by` is normal: a mine kills long after its owner drove off,
		-- and a missile fired at nobody still hits whoever it runs into.
		by = if by then by.DisplayName else nil,
		victim = victim.DisplayName,
	})
end

local remote: RemoteEvent
local itemRemote: RemoteEvent
local hitRemote: RemoteEvent

--=====================================================================
--  FLIGHT  (thrown hazards and scattered drops)
--
--  Handed to Roblox's physics rather than integrated by hand, which is
--  the opposite of what the kart and the missile do — and right for the
--  same reason those are wrong.
--
--  A thrown item is plain ballistics with nobody steering it. It needs
--  no determinism, no route and no feel, so the only thing that matters
--  is that everyone SEES it thrown. Moving an anchored part from a
--  server loop replicates as bare position updates with no interpolation
--  — over a 0.6s arc that's a dozen steps and it reads as a stutter or a
--  teleport. Exactly what was wrong with the missile before it was
--  rendered client-side.
--
--  An unanchored part with a velocity on it is interpolated by Roblox's
--  own replication, so it arcs smoothly for everybody at no cost in code
--  or bandwidth.
--
--  TRADE: physics gravity is world-down, so an item thrown ON A LOOP
--  falls off it rather than arcing onto the ceiling. Everything else in
--  this game is surface-relative, and this deliberately isn't — a
--  hand-integrated arc was surface-correct and looked broken, which is
--  the worse of the two.
--=====================================================================
local settling = {}

local function launch(part: BasePart, vel: Vector3, lifetime: number)
	-- Collidable while airborne or it falls through the road; back off
	-- on landing so it never blocks anyone. Karts ignore it either way —
	-- hazards are in the trigger filter.
	part.Anchored = false
	part.CanCollide = true
	part.AssemblyLinearVelocity = vel
	-- A little spin, so it tumbles rather than sliding through the air
	-- facing one way.
	part.AssemblyAngularVelocity = Vector3.new(math.random() * 8 - 4, math.random() * 8 - 4, math.random() * 8 - 4)

	table.insert(settling, {
		part = part,
		-- Settled when it stops moving, or when this runs out — a throw
		-- off the edge of the map would otherwise never settle.
		stop = os.clock() + math.min(Config.Items.ThrowTime, lifetime),
	})
end

-- Freeze anything that has come to rest, so a hazard doesn't get nudged
-- around the track by whatever brushes it afterwards.
local function stepSettling()
	local now = os.clock()
	for i = #settling, 1, -1 do
		local f = settling[i]
		local part = f.part
		if not part.Parent then
			table.remove(settling, i)
			continue
		end
		if now >= f.stop or part.AssemblyLinearVelocity.Magnitude < 3 then
			part.Anchored = true
			part.CanCollide = false
			table.remove(settling, i)
		end
	end
end

function RaceService.start()
	remote = Instance.new("RemoteEvent")
	remote.Name = Standings.REMOTE
	remote.Parent = BloxKart

	remote.OnServerEvent:Connect(function(player, score)
		if typeof(score) ~= "number" or score ~= score then
			return -- NaN or garbage
		end
		local kart = KartService.kartFor(player)
		if kart then
			-- TODO: validate the jump against the last known score before
			-- trusting it. Cheap to add here, impossible to add later if
			-- everything reads the attribute directly instead.
			kart:SetAttribute(Standings.ATTRIBUTE, score)
		end
	end)

	----------------------------------------------------------------
	-- ITEM BOXES
	--
	-- The server owns box state. If clients owned it, the leader would
	-- collect a box and it would still be sitting there for everyone
	-- else — or vanish inconsistently for each of them.
	----------------------------------------------------------------
	itemRemote = Instance.new("RemoteEvent")
	itemRemote.Name = "KartItemPickup"
	itemRemote.Parent = BloxKart

	local IT = Config.Items
	local rng = Random.new()

	itemRemote.OnServerEvent:Connect(function(player, box)
		-- Only during the race itself. Players are free to drive around
		-- between rounds, so without this they could hoover up every box
		-- on the track during the intermission and arrive on the grid
		-- holding a full stack.
		if not Match.isDriving(MatchService.phase()) then
			return
		end
		if typeof(box) ~= "Instance" or not box:IsA("BasePart") then
			return
		end
		if not box.Parent then
			return
		end

		-- A dropped item, not a box: grant exactly what it is rather than
		-- rolling. Somebody already paid for this one by being spun.
		if CollectionService:HasTag(box, IT.DropTag) then
			local dropped = box:GetAttribute(Names.DROP_ITEM)
			local item = typeof(dropped) == "string" and Items.byId(dropped)
			if item then
				box:Destroy() -- one taker; destroyed before the reply so a
				-- second request in the same frame finds nothing
				itemRemote:FireClient(player, item.Id)
			end
			return
		end

		if not CollectionService:HasTag(box, IT.BoxTag) then
			return
		end
		-- Already taken and waiting to respawn.
		if box:GetAttribute(Names.TAKEN) then
			return
		end

		-- Rolled server-side so the client can't choose its own item, and
		-- weighted by race position so trailers get better odds.
		local kart = KartService.kartFor(player)
		local place, field = 0, 0
		if kart then
			local order = Standings.order(CollectionService:GetTagged(Names.KART_TAG))
			place, field = Standings.placeOf(order, kart)
		end
		local item = Items.roll(rng, place, field)
		if not item then
			return
		end

		box:SetAttribute(Names.TAKEN, true)
		box.Transparency = 1
		box.CanQuery = false
		itemRemote:FireClient(player, item.Id)

		task.delay(IT.RespawnTime, function()
			if box.Parent then
				box:SetAttribute(Names.TAKEN, false)
				box.Transparency = 0
				box.CanQuery = true
			end
		end)
	end)

	----------------------------------------------------------------
	-- ITEM HITS
	--
	-- A client may never tell another client it was hit — it would be
	-- trivially forgeable. The firing client names a target, the server
	-- relays, and only the TARGET's own client applies the effect.
	----------------------------------------------------------------
	hitRemote = Instance.new("RemoteEvent")
	hitRemote.Name = "KartItemHit"
	hitRemote.Parent = BloxKart

	local feed = Instance.new("RemoteEvent")
	feed.Name = Names.FEED_REMOTE
	feed.Parent = BloxKart
	RaceService.feed = feed

	hitRemote.OnServerEvent:Connect(function(player, targetKart, payload)
		if typeof(targetKart) ~= "Instance" or not targetKart:IsA("Model") then
			return
		end
		if not CollectionService:HasTag(targetKart, Names.KART_TAG) then
			return
		end
		if typeof(payload) ~= "table" then
			return
		end
		local victimId = targetKart:GetAttribute(Names.OWNER)
		local victim = victimId and Players:GetPlayerByUserId(victimId)
		if victim and victim ~= player then
			-- tostring: it's a client-supplied table, and byId simply won't
			-- match anything that isn't a real id.
			RaceService.announce(tostring(payload.item), player, victim)
			-- Every field is re-derived and clamped here rather than passed
			-- through: this is a client-supplied table, and the only thing
			-- standing between it and another player's simulation.
			--
			-- Clamps are generous enough for any real item but finite, so a
			-- forged payload can't stun someone for a minute.
			hitRemote:FireClient(victim, {
				spin = math.clamp(tonumber(payload.spin) or 1, 0, 5),
				keep = math.clamp(tonumber(payload.keep) or 0.5, 0, 1),
				stun = math.clamp(tonumber(payload.stun) or 0, 0, 3),
				reverse = math.clamp(tonumber(payload.reverse) or 0, 0, 8),
				note = math.clamp(math.floor(tonumber(payload.note) or 1), 0, 3),
			})
		end
	end)

	----------------------------------------------------------------
	-- HAZARDS  (mines)
	--
	-- Server-spawned for two reasons: a client can't be trusted to place
	-- a world object that affects other players, and a dropper who
	-- disconnects shouldn't leave a phantom hazard behind.
	----------------------------------------------------------------
	local hazardRemote = Instance.new("RemoteEvent")
	hazardRemote.Name = "KartHazard"
	hazardRemote.Parent = BloxKart

	hazardRemote.OnServerEvent:Connect(function(player, action, arg, itemId, back, power)
		if action == "drop" then
			-- Racing only, same reason as the boxes. "hit" is deliberately
			-- NOT gated: a hazard left on the track when the round ended
			-- still has to be removable, or it sits there forever.
			if not Match.isDriving(MatchService.phase()) then
				return
			end
			if typeof(arg) ~= "CFrame" or typeof(itemId) ~= "string" then
				return
			end
			-- Appearance and lifetime come from the item module, so adding
			-- a hazard item never means editing this file.
			local item = Items.byId(itemId)
			if not (item and item.Scope == "world" and item.Hazard) then
				return
			end
			local spec = item.Hazard

			local hz = Instance.new("Part")
			hz.Name = item.Id
			hz.Size = spec.Size
			hz.CFrame = arg
			hz.Anchored = true
			hz.CanCollide = false
			hz.CanQuery = true -- clients detect it with a spatial query
			hz.Color = spec.Color
			hz.Material = spec.Material
			hz.Transparency = spec.Transparency
			-- Stamped so a dropper doesn't immediately drive into their own
			-- hazard, nobody can claim someone else's, and the victim's
			-- client knows which effect to apply.
			hz:SetAttribute(Names.OWNER, player.UserId)
			hz:SetAttribute(Names.ARM_AT, os.clock() + IT.HazardOwnerGrace)
			hz:SetAttribute(Names.HAZARD_ITEM, item.Id)
			-- Optional art. The part above stays the trigger volume and goes
			-- invisible; the model is decoration welded to it, and must never
			-- be queryable or it would read as a wall to a kart's sweep.
			if spec.Model then
				local folder = ServerStorage:FindFirstChild(IT.HazardModelFolder)
				local template = folder and folder:FindFirstChild(spec.Model)
				-- A Model OR a single Part. Art is just as often one
				-- MeshPart with decals on it as a whole model, and rejecting
				-- that was a silent fallback to the grey box.
				if template and (template:IsA("Model") or template:IsA("BasePart")) then
					hz.Transparency = 1
					local art = template:Clone()
					art.Name = "Visual"
					art.Parent = hz
					if art:IsA("Model") then
						art:PivotTo(hz.CFrame)
					else
						art.CFrame = hz.CFrame
					end
					local parts = if art:IsA("BasePart") then { art } else {}
					for _, d in art:GetDescendants() do
						if d:IsA("BasePart") then
							table.insert(parts, d)
						end
					end
					for _, d in parts do
						-- WELDED, not anchored. The hazard part is unanchored
						-- while it's in the air, and anchored art would stay
						-- hanging where it was created while the thing it
						-- decorates arcs away without it.
						d.Anchored = false
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
						d.Massless = true
						local weld = Instance.new("WeldConstraint")
						weld.Part0, weld.Part1 = hz, d
						weld.Parent = hz
					end
				else
					warn(
						("[RaceService] %s wants %q in ServerStorage.%s — no Model or Part by that name, using the plain part."):format(
							item.Id,
							spec.Model,
							IT.HazardModelFolder
						)
					)
				end
			end

			hz.Parent = workspace
			CollectionService:AddTag(hz, IT.HazardTag)

			-- Thrown forward: it leaves the kart and travels. Dropped
			-- backwards it just sits where it was put.
			-- Thrown forward: it arcs out of the kart. Dropped backwards it
			-- just sits where it was put.
			if not back then
				-- Wind-up scales the FORWARD speed only. Lift stays put, so
				-- a weak throw is a short lob at the same height rather than
				-- a sad little hop — it's how far it goes that the player is
				-- choosing, not how high.
				--
				-- Clamped here because it arrived from a client.
				local charge = math.clamp(tonumber(power) or 1, 0, 1)
				local reach = IT.ThrowSpeed * (IT.ThrowMinPower + (1 - IT.ThrowMinPower) * charge)
				launch(hz, arg.LookVector * reach + arg.UpVector * IT.ThrowLift, item.Lifetime)
			end

			task.delay(item.Lifetime, function()
				if hz.Parent then
					hz:Destroy()
				end
			end)
		elseif action == "spill" then
			-- Someone was spun and scattered their stack. Server-spawned for
			-- the same reason hazards are: a client can't be trusted to
			-- create a world object other players can collect, and the
			-- victim disconnecting mid-spin shouldn't leave phantoms.
			if typeof(arg) ~= "CFrame" or typeof(itemId) ~= "table" then
				return
			end
			for i, id in itemId do
				if typeof(id) ~= "string" or i > IT.MaxHeld then
					continue
				end
				local item = Items.byId(id)
				if not item then
					continue
				end

				local drop = Instance.new("Part")
				drop.Name = "Dropped" .. item.Id
				drop.Size = Vector3.one * IT.DropSize
				-- Spread sideways from where they span, so a full stack
				-- doesn't land as one unpickable pile.
				-- All spawned ON the victim and thrown apart, rather than
				-- placed in a tidy row: they were knocked out of a kart, so
				-- they should look like it.
				drop.CFrame = arg
				drop.Anchored = true -- launch() unanchors it
				drop.CanCollide = false
				drop.CanQuery = true -- clients find it with a spatial query
				drop.Transparency = 1 -- the billboard IS the visual
				drop:SetAttribute(Names.DROP_ITEM, item.Id)
				drop.Parent = workspace

				local bb = Instance.new("BillboardGui")
				bb.Size = UDim2.fromScale(IT.DropBillboard, IT.DropBillboard)
				bb.AlwaysOnTop = false
				bb.LightInfluence = 0
				bb.Parent = drop

				-- Just the icon, floating. No panel behind it: on a track
				-- these sit among scenery and a solid tile reads as a UI
				-- element someone left lying about rather than as a thing
				-- in the world.
				local hasIcon = (item.Icon or "") ~= ""
				if hasIcon then
					local icon = Instance.new("ImageLabel")
					icon.Size = UDim2.fromScale(1, 1)
					icon.BackgroundTransparency = 1
					icon.Image = item.Icon
					icon.Parent = bb
				else
					-- Fallback ONLY when there's no art yet. Without it an
					-- item with no icon would be an invisible pickup, which
					-- is worse than an ugly one.
					local tile = Instance.new("Frame")
					tile.Size = UDim2.fromScale(0.7, 0.7)
					tile.Position = UDim2.fromScale(0.5, 0.5)
					tile.AnchorPoint = Vector2.new(0.5, 0.5)
					tile.BackgroundColor3 = item.Tint or Color3.fromRGB(200, 200, 200)
					tile.BackgroundTransparency = 0.2
					tile.BorderSizePixel = 0
					tile.Parent = bb
					local round = Instance.new("UICorner")
					round.CornerRadius = UDim.new(0.2, 0)
					round.Parent = tile
				end

				-- Fanned across the road, evenly either side of the victim,
				-- so a full stack doesn't land as one unpickable pile.
				local fan = (i - (#itemId + 1) * 0.5) / math.max(#itemId, 1)
				launch(
					drop,
					arg.RightVector * (fan * 2 * IT.DropScatter)
						+ arg.UpVector * IT.DropPop
						-- A little backwards, so they land behind the spinout
						-- rather than in the path of whoever caused it.
						- arg.LookVector * IT.DropScatter * 0.4,
					IT.DropLifetime
				)

				CollectionService:AddTag(drop, IT.DropTag)
				task.delay(IT.DropLifetime, function()
					if drop.Parent then
						drop:Destroy()
					end
				end)
			end
		elseif action == "hit" then
			-- The victim reports driving into it; the server removes it so
			-- it can't be triggered twice.
			if typeof(arg) == "Instance" and arg:IsA("BasePart") and CollectionService:HasTag(arg, IT.HazardTag) then
				-- Read BEFORE destroying, or the attribution goes with it.
				local ownerId = arg:GetAttribute(Names.OWNER)
				local owner = ownerId and Players:GetPlayerByUserId(ownerId)
				RaceService.announce(arg:GetAttribute(Names.HAZARD_ITEM), owner, player)
				arg:Destroy()
			end
		end
	end)

	RunService.Heartbeat:Connect(stepSettling)

	Players.PlayerRemoving:Connect(function(player)
		local kart = KartService.kartFor(player)
		if kart then
			kart:SetAttribute(Standings.ATTRIBUTE, nil)
		end
	end)
end

return RaceService
