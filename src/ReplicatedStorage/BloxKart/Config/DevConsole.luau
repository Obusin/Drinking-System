--[[
	DevConsole — the only console setting a client is allowed to know.

	DELIBERATELY ALMOST EMPTY. Everything that decides WHO may use the
	console, WHAT they may do and HOW OFTEN lives server-side in
	KartServer/DeveloperConsole and is never replicated. See
	DevRoster's note on why publishing a roster is free reconnaissance.

	A hotkey is safe to share: knowing which key opens a window you are
	not permitted to have is worth nothing.
--]]

return {
	-- F4. Chosen because the game binds no function keys — drift is
	-- Space/R1, items Q/E, quests are on Config.Level.QuestOpenKey, and
	-- the garage is menu-driven. Nothing here can collide with driving.
	--
	-- The bind respects `gameProcessed`, so it does nothing while a text
	-- box has focus.
	Hotkey = Enum.KeyCode.F4,
}
