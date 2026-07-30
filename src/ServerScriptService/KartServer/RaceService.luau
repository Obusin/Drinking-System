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
		if not CollectionService:HasTag(box, IT.BoxTag) or not box.Parent then
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

	hazardRemote.OnServerEvent:Connect(function(player, action, arg, itemId)
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

			task.delay(item.Lifetime, function()
				if hz.Parent then
					hz:Destroy()
				end
			end)
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

	Players.PlayerRemoving:Connect(function(player)
		local kart = KartService.kartFor(player)
		if kart then
			kart:SetAttribute(Standings.ATTRIBUTE, nil)
		end
	end)
end

return RaceService
