--[[
	Loading — the "still loading" bar that lives under the menu.

	WHY A BAR AND NOT A LONGER SPLASH
	---------------------------------
	The splash covers what the player must NOT see: a half-built menu and
	a kart wearing the wrong thing. Everything after that — icons,
	banners, item art — can arrive late without hurting anything, and
	holding a black screen for it spends the player's time to avoid a
	cosmetic pop. So the menu opens on time and this reports the rest.

	IT SHOWS REAL PROGRESS: the fraction of assets ContentProvider has
	actually resolved, not a timer wearing a bar's clothes. A fake bar
	that finishes before the game does teaches the player the bar means
	nothing, and the one time something IS stuck they will not believe it.
--]]

return {
	--== PLACEMENT =====================================================
	-- Bottom edge, centred, deliberately small. It is a status line, not
	-- a modal — the menu is fully usable while it runs.
	BarWidth = 220,
	BarHeight = 4,
	BarBottom = 18, -- px above the bottom edge

	BarText = "LOADING CONTENT",
	BarTextSize = 11,
	BarTextColor = Color3.fromRGB(198, 197, 186),

	--== LOOK ==========================================================
	BarTrackColor = Color3.fromRGB(255, 255, 255),
	BarTrackTransparency = 0.82, -- barely there until it fills
	BarFillColor = Color3.fromRGB(245, 197, 66), -- the menu's gold

	--== TIMING ========================================================
	-- Tweened rather than snapped: batches land in chunks, and a bar that
	-- jumps in steps reads as broken even when the numbers are honest.
	BarEase = 0.25,

	-- How many assets per PreloadAsync call.
	--
	-- THIS IS WHY IT IS BATCHED AT ALL: PreloadAsync on one big list
	-- yields until the whole lot is done, so the bar would sit at zero
	-- and then snap to full. Smaller batches move it more often at the
	-- cost of more round trips.
	BarBatch = 4,

	-- Held at 100% before fading, because reaching full is the only
	-- confirmation the player gets that it FINISHED rather than gave up.
	BarHoldWhenDone = 0.6,
	BarFadeTime = 0.45,
}
