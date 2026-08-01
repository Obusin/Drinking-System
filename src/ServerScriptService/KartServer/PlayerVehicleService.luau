--[[
	PlayerVehicleService — may this player have their kart right now?

	POLICY, NOT MECHANISM. KartService still owns how a kart is built,
	painted, skinned, owned and seated; this decides who is allowed to
	ask for one and where it is allowed to appear. Splitting them is what
	stops the lobby growing a second way to build a kart, which would be
	two places for ownership and paint to drift apart.

	It is also the only new inbound remote in the lobby, so it is the
	only new thing that has to treat its caller as hostile. Everything
	Kart/SECURITY.md asks of a remote is done here and in one place:

	  identity     implicit — RemoteEvent gives us the real Player
	  input types  the action string is checked against two values
	  game state   lobby only; a race hands karts out, it is not asked
	  cooldown     per player, ToggleCooldown
	  ownership    you may only ever act on your own kart
	  distance     n/a — nothing here names a position; the SERVER
	               chooses where the kart goes, from the character's own
	               replicated CFrame

	That last one is the important one. The client sends an INTENT
	("spawn", "despawn") and never a position, so there is no coordinate
	to forge. A client that asks for a kart in the sky is asking for a
	kart wherever the server can see it standing.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloxKart = ReplicatedStorage:WaitForChild("BloxKart")
local Config = require(BloxKart:WaitForChild("Config"))
local Names = require(BloxKart:WaitForChild("Names"))
local Place = require(BloxKart:WaitForChild("Place"))
local WorldFilter = require(BloxKart:WaitForChild("WorldFilter"))
local KartService = require(script.Parent.KartService)

local LOBBY = Config.Lobby

local PlayerVehicleService = {}

local remote: RemoteEvent
local lastAt: { [number]: number } = {}

--=====================================================================
--  IS THERE ROOM?
--
--  The price of a button instead of a pit lane: the player can be
--  standing anywhere, and a 7-stud kart has to fit. A doorway, a shop
--  interior, a gap between two props — all places somebody will
--  reasonably stand and press the button.
--
--  REFUSE RATHER THAN FORCE. A kart spawned into geometry is a kart
--  wedged forever, and that reads as a broken game rather than as a bad
--  place to stand. A refusal with a reason reads as a rule.
--=====================================================================
local clearance = OverlapParams.new()
clearance.FilterType = Enum.RaycastFilterType.Exclude
clearance.MaxParts = 1

local function roomAt(cf: CFrame, character: Model?): boolean
	-- The player's own body does not count as an obstruction, and
	-- neither does anything the karts already ignore — trigger volumes,
	-- item boxes, other karts.
	--
	-- Taken from WorldFilter's own list rather than assembled again
	-- here, so "is there room" and "may I drive here" cannot disagree.
	-- CLONED, never mutated: those params are shared with every query
	-- the controller makes, and adding a character to them would delete
	-- that character from the world the kart drives in.
	local ignore = table.clone(WorldFilter.overlapParams.FilterDescendantsInstances)
	if character then
		table.insert(ignore, character)
	end
	clearance.FilterDescendantsInstances = ignore

	local hits = workspace:GetPartBoundsInBox(cf, LOBBY.ClearanceSize, clearance)
	return #hits == 0
end

--=====================================================================
--  WHERE IT GOES
--
--  In front of the player, facing the way they are facing, lifted a
--  little so it settles onto the road rather than into it.
--
--  Taken from the character's replicated CFrame — a position the SERVER
--  can see — rather than from anything the client sends.
--=====================================================================
local function placementFor(character: Model): CFrame?
	local root = character.PrimaryPart
	if not root then
		return nil
	end

	-- Flattened: a character standing on a slope should not get a kart
	-- pitched into the ground. The controller settles it onto the
	-- surface on its first frame anyway.
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	flat = flat.Unit

	local at = root.Position + flat * LOBBY.SpawnAhead + Vector3.new(0, LOBBY.SpawnLift, 0)
	return CFrame.lookAt(at, at + flat)
end

--=====================================================================
--  THE REQUEST
--=====================================================================
local function onRequest(player: Player, action: unknown)
	-- A RACE PLACE DOES NOT TAKE REQUESTS. Karts are handed out there
	-- because a round is about to start, and a player who could put
	-- theirs away mid-race would leave the round counting a racer who
	-- cannot finish.
	if not Place.isLobby() then
		return
	end

	if action ~= "spawn" and action ~= "despawn" then
		return
	end

	local now = os.clock()
	if now - (lastAt[player.UserId] or -math.huge) < LOBBY.ToggleCooldown then
		return
	end
	lastAt[player.UserId] = now

	local has = KartService.kartFor(player) ~= nil

	if action == "despawn" then
		if has then
			KartService.despawnFor(player)
			remote:FireClient(player, "despawned")
		end
		return
	end

	-- SPAWN. Already having one is not an error, it is a stale button —
	-- two clients can disagree about the state for a frame. Say what is
	-- true rather than refusing.
	if has then
		remote:FireClient(player, "spawned")
		return
	end

	local character = player.Character
	if not character or not character.PrimaryPart then
		return -- between lives; the button will work in a moment
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local cf = placementFor(character)
	if not cf or not roomAt(cf, character) then
		remote:FireClient(player, "blocked")
		return
	end

	local kart = KartService.spawnFor(player)
	if not kart then
		remote:FireClient(player, "failed")
		return
	end

	-- Put it where we decided, rather than wherever the build path left
	-- it. The build is shared with the race path, which places karts on
	-- a starting grid; the lobby's answer is "in front of you".
	--
	-- Safe to move directly: it has not been seated yet from the
	-- client's point of view, so nothing is fighting us for it.
	kart:PivotTo(cf)

	remote:FireClient(player, "spawned")
end

--=====================================================================
--  START
--=====================================================================
function PlayerVehicleService.start()
	remote = Instance.new("RemoteEvent")
	remote.Name = Names.VEHICLE_REMOTE
	remote.Parent = BloxKart

	remote.OnServerEvent:Connect(onRequest)

	Players.PlayerRemoving:Connect(function(player)
		lastAt[player.UserId] = nil
	end)

	if LOBBY.Announce then
		print("[PlayerVehicle] lobby — players arrive on foot and call their kart.")
	end
end

return PlayerVehicleService
