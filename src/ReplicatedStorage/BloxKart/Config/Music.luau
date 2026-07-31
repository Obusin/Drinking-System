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

return {
	--== PLAYLISTS =====================================================
	-- Played during the countdown and the race itself. The countdown is
	-- included deliberately: the music should already be going when the
	-- lights go out, or the start feels like the music missed its cue.
	Race = {},

	-- Waiting, intermission and results. Quieter, calmer, and allowed to
	-- be a shorter list — nobody is in the lobby long enough to notice a
	-- loop, and they are in the race long enough to notice everything.
	Lobby = {},

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
