--[[
	Names — every string that crosses a boundary, in one place.

	Tags and attribute names are how the client and server talk about the
	same object without sharing memory. Written as raw literals they're
	invisible to the analyser, invisible to a rename, and a typo in one of
	five copies fails silently: the tag simply never matches, so a kart
	stops being found or a hazard stops arming, with no error anywhere.

	`OwnerUserId` was in five files. The `Kart` tag was in five. This file
	is one require and one autocomplete instead.

	WHAT BELONGS HERE
	-----------------
	Strings both ends must agree on. Tunables don't — those are Config,
	because you change them to change behaviour. Nothing here should ever
	be changed to tune anything; changing a name here only renames it.

	(Standings and Match own their own names, because those come with
	protocol rules the name alone doesn't convey. Don't move them here.)
--]]

local Names = {}

--== TAGS ==============================================================
Names.KART_TAG = "Kart"

--== ATTRIBUTES ========================================================

-- On a kart. Maps a model back to the player who owns it, which is how
-- every system that starts from a kart finds the human.
-- Set while a finished player's kart is being driven by the AI.
--
-- Read by three places that would otherwise undo the takeover: the
-- ownership watchdog (which re-grants a driver their kart every couple
-- of seconds), KartService's seat handler, and the driver's own client,
-- which has to stop simulating a kart it no longer owns.
Names.AI_DRIVEN = "AiDriven"

-- DEVELOPER SPEED OVERRIDE, set by the console on a KART model.
--
-- A multiplier on MaxSpeed, absent or 1 meaning normal. It is on the
-- kart rather than the player so it replicates to whoever is simulating
-- that kart, and so it dies with the kart — a dev override cannot
-- outlive the thing it was applied to.
Names.DEV_SPEED_SCALE = "DevSpeedScale"

-- Who is driving, as text. Players resolve through OWNER, but a bot has
-- no UserId and no existence on the client at all, so anything that has
-- to DISPLAY a name reads this instead of guessing.
Names.RACER_NAME = "RacerName"

Names.OWNER = "OwnerUserId"

-- On a Player. Server-owned lifecycle state, so join/respawn/kart
-- failures are visible instead of being inferred from several objects.
-- Set by the client once the MENU STAGE KART is wearing the saved look.
--
-- The loading screen waits on it, so the whole dress-in happens BEHIND the
-- splash and the player never sees a stock kart at all. An attribute rather
-- than a remote because both ends are the same client — nothing crosses the
-- wire, and ReplicatedFirst cannot require anything under KartClient anyway.
--
-- Fails OPEN: the loading screen times out and shows the menu regardless, so
-- a profile that never loads costs a stock kart, never a stuck splash.
Names.PREVIEW_READY = "BloxKartPreviewReady"

Names.PLAYER_STATE = "BloxKartState"
Names.PLAYER_STATE_REASON = "BloxKartStateReason"
Names.STATE_LOADING = "Loading"
Names.STATE_CHARACTER_LOADING = "CharacterLoading"
Names.STATE_LOBBY = "Lobby"
Names.STATE_KART_SPAWNING = "KartSpawning"
Names.STATE_LOBBY_DRIVING = "LobbyDriving"
Names.STATE_RACE_LOADING = "RaceLoading"
Names.STATE_RACE_DRIVING = "RaceDriving"
Names.STATE_RECOVERING = "Recovering"

-- Where a freshly-called lobby kart belongs, as a CFrame attribute.
-- NOT written by moving the part — see PlayerVehicleService for why a
-- server-side PivotTo on a kart with a seated player loses to the
-- client's own Simulation the instant it constructs, the same race
-- assignGrid's own comment warns about for the starting grid. The
-- client reads this once, on attach, and calls Simulation:RespawnAt —
-- the same single door every other teleport in this game uses.
Names.VEHICLE_SPAWN_CF = "VehicleSpawnCF"

-- On a power-up box. Server-owned: set when collected, cleared when it
-- respawns. Clients read it to avoid asking for a box already taken.
Names.TAKEN = "Taken"

-- On a dropped hazard. The time it becomes dangerous to its own dropper,
-- so driving away from your own mine doesn't spin you.
Names.ARM_AT = "ArmAt"

-- On a dropped hazard. Which item it is, so one code path serves mines,
-- oil, fake boxes and anything added later.
Names.HAZARD_ITEM = "HazardItem"

-- On a road wheel's Motor6D. True for the front pair, which steer as
-- well as roll.
Names.WHEEL_FRONT = "IsFront"

-- On a kart, written by its own driver's client. Steering as the DRIVER
-- knows it, which on a touch device the VehicleSeat never sees — see
-- Rider. Client-set, so it does NOT replicate; remote karts fall back to
-- SteerFloat, which is correct for anyone on a keyboard.
Names.STEER = "KartSteer"

-- On a kart, written by its own driver's client alongside STEER. The
-- visual drift angle in radians — how far the body is yawed away from
-- where it's actually travelling. The front wheels cancel it so they
-- stay pointed down the road; see Rider.
Names.DRIFT = "KartDrift"

-- On a road wheel's Motor6D, both in the JOINT's frame.
--
-- Worked out per wheel at build time rather than assumed, because an
-- imported mesh keeps whatever orientation it was modelled in — so "roll
-- about X, steer about Y" is true of a Roblox Cylinder and of nothing
-- else. Getting it wrong spins the wheel flat like a helicopter rotor.
Names.ROLL_AXIS = "RollAxis"
Names.STEER_AXIS = "SteerAxis"

-- On a dropped item lying on the track. Which item it is, so picking it
-- up grants THAT one rather than a fresh roll.
Names.DROP_ITEM = "DroppedItem"

--== REMOTES ==========================================================

-- Server -> everyone: "X hit Y with Z". Broadcast rather than sent to
-- the two people involved, because a hit is a spectacle — the whole
-- point of landing one is that the lobby sees it.
Names.FEED_REMOTE = "KartFeed"
Names.REWARD_REMOTE = "KartReward"
Names.XP_REMOTE = "KartXp"
Names.STATS_REMOTE = "KartStats"
Names.QUEST_REMOTE = "KartQuests"
-- Lobby only: "spawn" / "despawn" in, a result string back. The client
-- sends an INTENT and never a position — see PlayerVehicleService.
Names.VEHICLE_REMOTE = "KartVehicle"
-- Lobby only: "play" in, a result string back. The client never names a
-- destination — see QueueService.
Names.QUEUE_REMOTE = "KartQueue"
-- Server -> client: presentational scene/teleport transitions. The
-- server decides when a teleport is actually in flight; the client only
-- owns the wipe that hides it.
Names.TRANSITION_REMOTE = "KartTransition"

-- Garage: client asks to equip a part, server validates and saves. Also
-- pushes the player's current `equipped` back on join so the garage opens
-- showing what they are actually wearing.
Names.GARAGE_REMOTE = "KartGarage"

return Names
