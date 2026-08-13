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

-- Cosmetic identity only. A bot can borrow this user's avatar/name for
-- display, but it is not ownership and must never be trusted as a player.
Names.BOT_AVATAR_USER_ID = "BotAvatarUserId"

-- WHICH VEHICLE THIS IS. Stamped by KartFactory, read by whoever builds
-- the Simulation — the client owns its own kart's controller, so the
-- kind has to replicate rather than be passed in a call it never sees.
--
-- The handling itself is NOT replicated: both ends look the kind up in
-- Config.Vehicles, which is shared. Sending the numbers would be a
-- second copy that can disagree with the first.
Names.VEHICLE_KIND = "VehicleKind"

Names.OWNER = "OwnerUserId"
-- Server -> affected player only. A place change is computed against the
-- complete server field, so it remains meaningful when the opponent's model
-- is outside this client's streaming radius.
Names.OVERTAKE_REMOTE = "KartRivalSpotlight"

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

-- Client-local handoff from ReplicatedFirst's splash to the normal client.
-- The intermission cinematic must not advance behind an opaque loading screen;
-- it begins only once the wipe has completely revealed the game.
Names.SPLASH_DISMISSED = "BloxKartSplashDismissed"

Names.PLAYER_STATE = "BloxKartState"
Names.PLAYER_STATE_REASON = "BloxKartStateReason"
Names.STATE_LOADING = "Loading"
Names.STATE_CHARACTER_LOADING = "CharacterLoading"
Names.STATE_LOBBY = "Lobby"
Names.SEA_CLOCK = "SeaClock" -- one clock, so hull and field agree
Names.WAVE_RISE = "WaveRise" -- studs/s the sea is rising under the kart
Names.SWIMMING = "Swimming" -- 0..1, eased, so visuals can fade in
Names.BOOST_TIER = "BoostTier" -- 0 none, 1-3 the tier that is burning
Names.BOOSTING = "Boosting" -- any boost source: pad, drift release, item
Names.GLIDING = "Gliding" -- published so OTHER people's gliders animate
Names.GLIDE_PITCH = "GlidePitch" -- -1 float .. +1 dive
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

-- The driver's raw steering INTENT, before the kart's own steering
-- weight is applied. Published because a motorcycle's lean has to
-- anticipate the turn — chasing the smoothed steer leans it after the
-- corner, which reads as the bike sliding rather than carving.
Names.STEER_INPUT = "KartSteerInput"

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
Names.RAINBOW_ACTIVE = "RainbowActive"
Names.RAINBOW_UNTIL = "RainbowUntil"
Names.RAINBOW_HELD = "RainbowHeld"
Names.LIVE_STANDINGS_REMOTE = "KartLiveStandings"

--== REMOTES ==========================================================

-- Client -> server, once per join.  This is deliberately only a lifecycle
-- acknowledgement: the server still owns spawning, seating and every racing
-- decision.  It prevents the initial race kart from being seated before this
-- client's essential kart systems have installed their listeners.
Names.CLIENT_READY_REMOTE = "KartClientReady"
-- Client -> server after Simulation has attached to the exact kart the
-- server seated it in. Unlike CLIENT_READY_REMOTE this is per-kart and lets
-- the lifecycle distinguish "client booted" from "player can actually drive".
Names.KART_ATTACHED_REMOTE = "KartClientKartAttached"
-- On ReplicatedStorage.BloxKart, set once the server has created every
-- gameplay remote/service for this place. Clients use it only as a boot
-- barrier; it carries no authority.
Names.SERVER_READY = "BloxKartServerReady"

-- Server -> everyone: "X hit Y with Z". Broadcast rather than sent to
-- the two people involved, because a hit is a spectacle — the whole
-- point of landing one is that the lobby sees it.
Names.FEED_REMOTE = "KartFeed"
-- Both ways: client fires it empty to sound its horn, server rebroadcasts
-- with the player who did it. NO PAYLOAD FROM THE CLIENT — there is
-- nothing it could tell us that we would believe, and the kart position
-- everyone needs is already replicated. Rate-limited server-side; a horn
-- is a broadcast, and a broadcast a client can trigger is a spam vector.
Names.HORN_REMOTE = "KartHorn"
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
-- Race place only: client requests the one server-owned destination,
-- the lobby.  There is deliberately no place id in this request.
Names.RETURN_REMOTE = "KartReturnLobby"

-- Garage: client asks to equip a part, server validates and saves. Also
-- pushes the player's current `equipped` back on join so the garage opens
-- showing what they are actually wearing.
Names.GARAGE_REMOTE = "KartGarage"

-- Client says "I drove into that prop", server decides and animates it.
-- Detection has to be client-side because only the client simulates its
-- own kart; the CONSEQUENCE is server-side so every player sees the same
-- cone fly.
Names.PROP_REMOTE = "KartProp"

return Names
