--[[
	Rewards — the end-of-race results and payout screen.

	Layout follows the reference: a slanted stack of dark panels over the
	frozen world, results on the left, progression on the right, payout
	bottom right, and one loud CONTINUE.

	THIS IS THE PRESENTATION HALF ONLY.

	`RewardHud:Show(payload)` renders whatever table it is handed. It
	knows nothing about where the numbers came from, which is the whole
	point: when `DataService` and the single grant path exist, the server
	sends a real payload and not one line of layout changes.

	Until then `Preview = true` fills the payload from what the client
	can already see — finishing order off the kart attributes, a payout
	from the placement curve below. Those numbers are NOT banked
	anywhere, and the panel says so.
--]]

return {
	--== SEAM ==========================================================
	-- Flip to false the day the server sends a real payload. When false,
	-- a race with no payload shows the board with no payout rather than
	-- inventing one — silence is correct, a made-up number is not.
	Preview = true,

	-- The line printed under the payout while Preview is on, so nobody
	-- mistakes a placeholder for a balance.
	PreviewNote = "PREVIEW · not saved yet",

	--== CURRENCY ======================================================
	-- Uploaded 2026-08-01. Image ids, not Decal ids — the first pair
	-- were Decals and rendered nothing, which is what Util.verifyImage
	-- exists to say out loud rather than leaving a blank square.
	--
	-- NOTE: the Bolt id is UNCHANGED from the pair that failed. If it
	-- still warns, the cause is not decal-vs-image — check that the
	-- asset is approved and owned by the place owner.
	BoltIcon = "rbxassetid://78484915579310",
	NitroIcon = "rbxassetid://107666490588324",

	BoltColor = Color3.fromRGB(255, 196, 62),
	NitroColor = Color3.fromRGB(120, 214, 255),

	--== PLACEMENT PAYOUT (preview only) ================================
	-- Bolt for finishing Nth. INDEX 1 IS FIRST.
	--
	-- The tail matters more than the head: last place still pays, which
	-- is the economy rule that losing must still progress you. Tune the
	-- gap, never the floor to zero.
	BoltForPlace = { 240, 190, 155, 130, 110, 95, 85, 80 },
	BoltFloor = 70, -- anyone past the end of the table

	-- Overtakes are the reference's bonus line, and the one reward that
	-- pays for racing rather than for winning.
	BoltPerOvertake = 14,

	-- Crystals do NOT drop per race. They come from weeklies and events,
	-- so that monthly income is a number a player can compute. Present
	-- on the panel only when the payload actually contains some.

	--== LOOK ==========================================================
	-- How far the world behind is darkened.
	--
	-- LIGHT ON PURPOSE. The track is still running behind this — karts
	-- lapping, items going off — and that is the ending. Dim it enough
	-- to read the board and no further; at 0.45 the shot it was sitting
	-- on top of may as well not have been there.
	Dim = 0.22,
	PanelColor = Color3.fromRGB(24, 24, 26),
	PanelTransparency = 0.06,
	AccentColor = Color3.fromRGB(255, 196, 62),
	TextColor = Color3.fromRGB(255, 255, 255),
	DimTextColor = Color3.fromRGB(168, 168, 176),

	-- The reference's panels sit a degree or two off square. Enough to
	-- read as deliberate, little enough that text stays comfortable.
	PanelTilt = -1.2,

	TitleSize = 34,
	RowSize = 21,
	SubSize = 13,
	BigSize = 62,
	ValueSize = 26,

	--== GEOMETRIC WIPE ================================================
	-- An angled band sweeps the screen, and each panel is uncovered as
	-- it passes. One gesture, not four separate tweens, so the screen
	-- resolves rather than assembling itself.
	WipeAngle = -14, -- degrees off vertical
	WipeTime = 0.42, -- seconds for the band to cross
	WipeColor = Color3.fromRGB(255, 196, 62),

	-- THE BAND ITSELF. Solid, and it needs to stay that way: the band is
	-- what hides the cut. At 1 it is invisible and the grid teleport and
	-- the results panel opening are both visible again, because there is
	-- nothing between the player and the change — the transition becomes
	-- decoration rather than a cover.
	--
	-- The MARK's own background is separate and already fully
	-- transparent, so a PNG with alpha shows no plate behind it.
	WipeBandTransparency = 0,

	-- Art carried on the band, shown at the moment it covers the screen.
	-- A wipe with a mark on it is a stinger; a wipe without one is a
	-- coloured rectangle passing by.
	--
	-- Kept UPRIGHT while the band is angled — a logo rotated 14 degrees
	-- reads as a mistake, not as style.
	WipeImage = "rbxassetid://97017994154540",
	WipeImageSize = 560, -- pixels on the long edge
	-- Held briefly at full cover so the mark is legible rather than
	-- glimpsed. Costs this much on top of WipeTime.
	WipeImageHold = 0.18,
	PanelStagger = 0.07, -- delay between panels landing
	PanelSlide = 0.34, -- how far each panel travels in, as a fraction
	PanelTime = 0.38,

	-- Counters roll up rather than appearing. Cheap, and it is most of
	-- why a results screen feels like a reward.
	CountUpTime = 0.7,
}
