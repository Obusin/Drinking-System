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
	-- FULL WIDTH, HARD AGAINST THE BOTTOM EDGE.
	--
	-- A centred 220px pill read as a UI element the player was meant to
	-- look at. Pinned edge-to-edge along the very bottom it reads as
	-- chrome — the browser-tab convention — which is what a background
	-- task should look like. It is a status line, not a modal: the menu
	-- is fully usable the whole time it runs.
	BarHeight = 3,
	BarBottom = 0, -- flush with the edge

	-- Small, bottom LEFT, sat just above the bar. Left because that is
	-- where the eye rests when nothing is asking for it, and the middle
	-- of the screen belongs to the kart.
	BarText = "INITIALIZING",
	-- Swapped in at 100%, so the last thing on screen is not a stale
	-- "INITIALIZING..." on a bar that has already finished.
	BarDoneText = "READY",
	BarTextSize = 11,
	BarTextColor = Color3.fromRGB(232, 234, 238),
	BarTextInset = 20, -- px from the left edge
	BarTextBottom = 10, -- px above the bar

	-- Trailing dots, so the label is visibly ALIVE even on a batch that
	-- takes a while. A bar that has not moved for ten seconds and a game
	-- that has hung look identical without this.
	BarDotRate = 2.5, -- dot changes per second

	--== LOOK ==========================================================
	BarTrackColor = Color3.fromRGB(255, 255, 255),
	BarTrackTransparency = 0.9, -- barely there until it fills
	BarFillColor = Color3.fromRGB(255, 255, 255), -- white, per the brief

	-- The fill fades out toward its TAIL rather than being a solid block,
	-- so it reads as a sweep with a bright leading edge instead of a
	-- growing rectangle. This is the whole difference between "a bar" and
	-- "something is happening".
	BarGradientTail = 0.75, -- transparency at the far left of the fill

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
