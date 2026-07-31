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
--]]

-- THE MAIN THEME. One set of tracks for the whole session.
--
-- Declared once and handed to BOTH playlists ON PURPOSE, and the shared
-- table matters rather than being a tidiness thing: Music switches lists
-- by table identity, so two separate tables holding the same ids would
-- count as a change and restart the music on every phase transition.
-- Sharing one means the soundtrack plays straight through the lobby, the
-- countdown, the race and the results without ever cutting.
--
-- To give the race its own energy later, replace Race with its own list
-- and they start crossfading at the lights.
local MAIN = {
	"rbxassetid://102543294099617",
	"rbxassetid://125858112035500",
	"rbxassetid://116052568337332",
	"rbxassetid://125091741122022",
}

return {
	--== PLAYLISTS =====================================================
	-- Played during the countdown and the race itself. The countdown is
	-- included deliberately: the music should already be going when the
	-- lights go out, or the start feels like the music missed its cue.
	Race = MAIN,

	-- Waiting, intermission and results. The same set for now — see MAIN
	-- above for why they share one table rather than two copies.
	Lobby = MAIN,

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
