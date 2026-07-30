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
local Triggers = require(BloxKart:WaitForChild("Triggers"))
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
--  Properly ballistic: a velocity, gravity, and a bounce on landing.
--
--  The first version slid the item along the floor at a decaying speed,
--  and it never read as a throw — an arc is the entire tell that
--  something was thrown rather than placed in front of you.
--
--  Gravity pulls along the THROWER'S up rather than the world's, so a
--  throw on a loop arcs onto the ceiling exactly as it would on flat
--  ground. Same reasoning as the kart's own surface gravity.
--
--  Server-side so everyone sees one throw, and so the thrower doesn't
--  get to decide where it ends up.
--=====================================================================
local flying = {}

local throwParams = RaycastParams.new()
throwParams.FilterType = Enum.RaycastFilterType.Exclude

local function refreshThrowFilter()
	-- Karts and triggers excluded, or a throw lands on the roof of the
	-- kart that threw it, or on top of a checkpoint volume.
	local skip = {}
	for _, kart in CollectionService:GetTagged(Names.KART_TAG) do
		table.insert(skip, kart)
	end
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(skip, plr.Character)
		end
	end
	Triggers.collect(skip)
	for _, f in flying do
		table.insert(skip, f.part)
	end
	throwParams.FilterDescendantsInstances = skip
end

local function stepThrows(dt: number)
	if #flying == 0 then
		return
	end
	refreshThrowFilter()

	local IT = Config.Items
	local now = os.clock()

	for i = #flying, 1, -1 do
		local f = flying[i]
		if not f.part.Parent or now >= f.stop then
			table.remove(flying, i)
			continue
		end

		f.vel -= f.up * IT.ThrowGravity * dt
		local step = f.vel * dt

		-- Cast a little past the step, by the item's own half-height, so
		-- it lands ON the road rather than with its middle in it.
		local reach = step.Magnitude + f.lift
		local dir = if step.Magnitude > 1e-4 then step.Unit else -f.up
		local hit = workspace:Raycast(f.part.Position, dir * reach, throwParams)

		if not hit then
			f.part.Position += step
			continue
		end

		f.part.Position = hit.Position + hit.Normal * f.lift

		-- Bounce, losing speed each time. A couple of hops sells the
		-- weight; more and it wanders somewhere neither player expects.
		if f.bounces > 0 and f.vel.Magnitude > 12 then
			f.bounces -= 1
			f.vel = (f.vel - 2 * f.vel:Dot(hit.Normal) * hit.Normal) * IT.ThrowBounce
			-- Landing re-references gravity to the surface it hit, so an
			-- item that lands on a banked corner settles into the bank.
			f.up = hit.Normal
		else
			table.remove(flying, i)
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

	hazardRemote.OnServerEvent:Connect(function(player, action, arg, itemId, back)
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
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
						d.Massless = true
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
			if not back then
				table.insert(flying, {
					part = hz,
					-- Forward AND up: the lift is what makes it an arc
					-- rather than a shove along the floor.
					vel = arg.LookVector * IT.ThrowSpeed + arg.UpVector * IT.ThrowLift,
					up = arg.UpVector,
					lift = spec.Size.Y * 0.5,
					bounces = IT.ThrowBounces,
					stop = os.clock() + IT.ThrowTime,
				})
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
				drop.Anchored = true
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

				-- Tinted tile behind the icon, so an item whose art hasn't
				-- been uploaded yet still reads as a coloured token rather
				-- than as nothing at all.
				local tile = Instance.new("Frame")
				tile.Size = UDim2.fromScale(1, 1)
				tile.BackgroundColor3 = item.Tint or Color3.fromRGB(200, 200, 200)
				tile.BackgroundTransparency = 0.25
				tile.BorderSizePixel = 0
				tile.Parent = bb
				local round = Instance.new("UICorner")
				round.CornerRadius = UDim.new(0.2, 0)
				round.Parent = tile

				local icon = Instance.new("ImageLabel")
				icon.Size = UDim2.fromScale(0.8, 0.8)
				icon.Position = UDim2.fromScale(0.5, 0.5)
				icon.AnchorPoint = Vector2.new(0.5, 0.5)
				icon.BackgroundTransparency = 1
				icon.Image = item.Icon or ""
				icon.Parent = bb

				-- Fanned across the road, evenly either side of the victim,
				-- so a full stack doesn't land as one unpickable pile.
				local fan = (i - (#itemId + 1) * 0.5) / math.max(#itemId, 1)
				table.insert(flying, {
					part = drop,
					vel = arg.RightVector * (fan * 2 * IT.DropScatter)
						+ arg.UpVector * IT.DropPop
						-- A little backwards, so they land behind the spinout
						-- rather than in the path of whoever caused it.
						- arg.LookVector * IT.DropScatter * 0.4,
					up = arg.UpVector,
					lift = IT.DropSize * 0.5,
					bounces = IT.ThrowBounces,
					stop = os.clock() + IT.ThrowTime,
				})

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

	RunService.Heartbeat:Connect(stepThrows)

	Players.PlayerRemoving:Connect(function(player)
		local kart = KartService.kartFor(player)
		if kart then
			kart:SetAttribute(Standings.ATTRIBUTE, nil)
		end
	end)
end

return RaceService
