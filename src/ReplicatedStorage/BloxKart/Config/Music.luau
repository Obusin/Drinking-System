--[[
	Music — the background playlists.

	PASTE IDS HERE AND NOTHING ELSE HAS TO CHANGE.

	Both lists may be empty; the player simply stays quiet. That is on
	purpose — ids arrive later than the code that plays them, and a music
	system that errors until it's populated is one that gets commented
	out and never comes back.

	Full asset strings rather than bare numbers, so a track is
	copy-pasteable to and from anywhere else in the codebase:

		Race = {
			"rbxassetid://1234567890",
			"rbxassetid://9876543210",
		},

	Each list is shuffled once per pass rather than picked at random per
	track. Random picking replays the same song back to back often enough
	to be noticed, and background music being noticed is the failure case.

	LOBBY VS RACE, NOT MATCH PHASE VS MATCH PHASE
	----------------------------------------------
	`Music:_listFor` picks `Race` during Grid/Racing and `Lobby`
	otherwise. In a LOBBY PLACE, `MatchService` never runs at all, so the
	phase is permanently `Waiting` and this resolves to `Lobby` for the
	entire session with no extra wiring — the two-place split and this
	playlist split line up for free.
--]]

return {
	--== PLAYLISTS =====================================================
	-- Played during the countdown and the race itself. The countdown is
	-- included deliberately: the music should already be going when the
	-- lights go out, or the start feels like the music missed its cue.
	--
	-- Set 2026-08-02.
	Race = {
		"rbxassetid://115138058496886", -- Sunday Morning Groove
	},

	-- The lobby, and everywhere that isn't Grid/Racing on a race place —
	-- waiting, intermission, results. Chosen to be talked over: the
	-- lobby is a social hub first, so this has to sit under a
	-- conversation rather than compete with one.
	--
	-- Set 2026-08-02.
	Lobby = {
		"rbxassetid://115138058496886", -- Upbeat Sunday Morning Groove for Lobby
		"rbxassetid://92891988699419", -- Festival Town
		"rbxassetid://95540214622796", -- Sunset Jazz
		
	},

	--== PARKED — has nowhere to plug in yet =============================
	-- Meant for the practice ring specifically, once the lobby has a
	-- notion of ZONES. Right now `Music:Update` only ever asks "what
	-- phase", never "where in the world" — there is no per-area music
	-- concept for it to join, only Lobby-the-whole-place and
	-- Race-the-whole-place. Stored here, unused, so the id survives
	-- until that exists rather than getting lost between now and then.
	--
	-- Practice = { "rbxassetid://114615679268173" }, -- Must Get Gud Enuf

	--== RETIRED ==========================================================
	-- The placeholder set both playlists shared before real tracks were
	-- picked. Kept rather than deleted — restore either by pasting an id
	-- back above.
	--
	-- local MAIN = {
	-- 	"rbxassetid://102543294099617",
	-- 	"rbxassetid://125858112035500",
	-- 	"rbxassetid://116052568337332",
	-- 	"rbxassetid://125091741122022",
	-- }

	--== LEVELS ========================================================
	-- Under the engine and well under the tyres. Music is the floor of
	-- the mix here, not the middle of it — a racing game where you can't
	-- hear your own kart over the soundtrack is one where you cannot hear
	-- when you're losing grip.
	Volume = 0.35,

	-- How fast it fades between playlists, per second. A crossfade rather
	-- than a cut, because a hard switch on a phase change draws attention
	-- to the phase change instead of to the race.
	FadeRate = 1.2,

	-- What Duck() drops to, as a fraction of Volume. For a countdown or a
	-- results screen, where something else has to be heard over it.
	DuckShare = 0.35,
}
