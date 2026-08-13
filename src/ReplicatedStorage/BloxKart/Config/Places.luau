--[[
	Places — which place is which, and what runs there.

	The experience is now more than one place, and every place runs the
	SAME code. This table is the only thing that tells them apart.

	WHY BY PLACE ID AND NOT BY WHAT IS IN THE WORLD
	----------------------------------------------
	The tempting version is "if there are checkpoints tagged, I am a
	race place". It reads well and it is a trap: it makes the role
	depend on whether the map has finished loading, it silently turns a
	lobby into a race server the moment somebody tags a decoration, and
	it is the same mistake as answering one question in two places.

	A place id is a fact. It is known before anything loads, it cannot
	drift, and it is the same number Roblox uses to teleport.

	ONLY THE LOBBY NEEDS DECLARING
	------------------------------
	Anything that is not the lobby is a race place. That means adding a
	third track needs no change here for the ROLE to be right — only for
	the lobby to know it can send people there.

	UNTIL LobbyPlaceId IS SET, EVERY PLACE IS A RACE PLACE, which is
	exactly what the game did before this file existed. Nothing changes
	until the number below is real.
--]]

return {
	--== THE ONE NUMBER THAT MATTERS =====================================
	-- The START PLACE. Where players land, where they spend, and the one
	-- place id you cannot change later — Roblox fixes the start place
	-- when the experience is created.
	--
	-- 0 means "not set up yet": every place behaves as a race place and
	-- the game runs exactly as it did before.
	--
	-- Find it in Studio: File > Game Settings, or the URL of the place
	-- on the Creator Dashboard. It is also printed by the startup line
	-- every server prints, which is where this one came from.
	--
	-- Set 2026-08-02 to "Go Karts! Go!". If this turns out to be the
	-- TRACK rather than the hub, change this number rather than anything
	-- else — it is the only place the distinction is made.
	LobbyPlaceId = 105460873162172,

	--== TESTING BEFORE THE IDS EXIST ====================================
	-- Force the role, ignoring the place id entirely.
	--
	--   ""        use LobbyPlaceId, which is the real rule
	--   "lobby"   pretend this is the hub
	--   "race"    pretend this is a track
	--
	-- STUDIO ONLY, and deliberately so. Its whole purpose is trying the
	-- hub out before the places are published and the ids are known; a
	-- published server must decide what it is from what it IS, not from
	-- a value somebody left set. Otherwise one forgotten line turns
	-- every track in the game into a lobby, and the failure is a race
	-- that never starts for anybody.
	--
	-- It says so loudly in the output whenever it is on.
	ForceRoleInStudio = "",

	--== WHERE THE LOBBY CAN SEND PEOPLE =================================
	-- One row per track. `placeId` is the place that holds that map.
	--
	-- The lobby reads this to build portals; a race place reads its OWN
	-- row to know what it is called and how long a race is. A track that
	-- is not listed still WORKS if you teleport to it directly — it just
	-- has no way in and falls back to the Race config defaults.
	--
	-- ORDER IS THE DISPLAY ORDER. Not alphabetical, not by id.
	Tracks = {
		{
			id = "track1",
			name = "Track One",
			-- Set 2026-08-02. DOUBLE-CHECK this against the URL of the
			-- place before relying on it — QueueService's whole reason
			-- for existing is that a wrong id here teleports players
			-- into somewhere that is not this game, and there is no way
			-- for the server to catch that on its own.
			placeId = 92989234226051,
			-- Per-track overrides. nil means "use Config.Race".
			laps = nil,
		},
		{
			id = "track2",
			name = "Track Two",
			placeId = 0,
			laps = nil,
		},
	},

	--== ARRIVING ========================================================
	-- Kick anyone who reaches a race place without coming through the
	-- lobby's teleport.
	--
	-- OFF until the lobby actually works, because turning it on first
	-- locks you out of your own race place — the only way in becomes a
	-- door that has not been built yet.
	--
	-- It is not security. A player who joins a race place directly is
	-- not cheating, they are just skipping the hub. This exists so the
	-- hub cannot be BYPASSED once the hub is where the money is.
	RequireLobbyEntry = false,

	--== LEAVING =========================================================
	-- Rounds to run in a race place before everybody goes back to the
	-- lobby. 0 means never — stay until you leave.
	--
	-- Sending people back is what makes the lobby the centre of the
	-- game rather than a loading screen they saw once.
	ReturnAfterRounds = nil,

	-- Seconds on the results board before the teleport fires, so a
	-- player sees what they earned before the screen changes.
	ReturnDelay = 6,

	--== WHAT RUNS WHERE =================================================
	-- The lobby is a place you can DRIVE, not a menu. You get your kart,
	-- you get power-ups, and the practice ring is where you learn what a
	-- missile feels like before it matters.
	--
	-- What it does NOT get is a ROUND: no grid, no countdown, no laps
	-- being banked, no AI field. Those are the two services below, and
	-- they are the whole difference between the two kinds of server.
	--
	-- Lap timing rides along with RaceService and does nothing, because
	-- a hub has no checkpoints tagged. Harmless, and it means a practice
	-- ring starts working the day one is.
	--
	-- Listed rather than hard-coded in the entry point so this file
	-- answers "what is the difference between the two" on its own.
	LobbyStarts = {
		WorldFilter = true, -- karts pass through each other
		Assets = true,
		KartService = true, -- you drive in the hub
		Skins = true,
		Ledger = true,
		DataService = true, -- the whole point: your profile is here
		QuestService = true,
		RaceService = true, -- item boxes and hazards
		ProjectileService = true, -- missiles

		MatchService = false, -- no round
		BotService = false, -- no field to fill
	},
}
