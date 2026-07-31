--[[
	Level — XP, and what earns it.

	XP is the one progression number that pays for PLAYING rather than
	for winning. Every award below is available to somebody finishing
	last, which is the same rule the currency design runs on: losing
	still progresses you, or a bad night is a wasted one.

	NOTHING HERE PERSISTS YET. `Progress` holds it for the session and
	says so. The curve and the awards are the part worth settling now,
	because they are what the numbers have to feel like — the storage is
	a `DataService` problem and a solved one.
--]]

return {
	--== AWARDS ========================================================
	-- Landing an item on someone. The most common award by far, so it is
	-- small: a hit is worth noticing, not worth farming.
	XpPerHit = 12,

	-- A hit that actually takes someone out of the race for a moment —
	-- a spin or a stun, not a graze.
	--
	-- THE GAME HAS NO ELIMINATION. Nobody dies in a kart racer; they
	-- spin, lose four seconds and carry on. This is that moment, and it
	-- is the closest honest thing to a takedown. Called out because
	-- "eliminated" in the feed means exactly this and nothing more.
	XpPerTakedown = 25,

	-- Finishing at all. INDEX 1 IS FIRST.
	--
	-- The tail is deliberately shallow. A first place is worth about
	-- twice a last place, not ten times — steepen this and the only way
	-- to progress is to already be winning, which is how a progression
	-- system starts punishing the players who most need it to be kind.
	XpForPlace = { 220, 190, 170, 155, 145, 135, 128, 120 },
	XpFloor = 110, -- anyone past the end of the table

	-- Finishing a race you were losing badly still pays this. It is the
	-- floor above, and it exists on purpose.

	--== CURVE =========================================================
	-- XP needed to go from level N to N+1: Base + Step * (N - 1).
	--
	-- Linear, not exponential. An exponential curve means the twentieth
	-- level costs a week, and the honest version of that is a shorter
	-- ladder rather than a punishing one. If levels need to last longer,
	-- add levels.
	Base = 500,
	Step = 120,
	MaxLevel = 20,

	--== FEED ==========================================================
	-- The kill-feed line is "<attacker> [icon] <victim>". The icon
	-- carries the verb, which is why there is no word for it: an icon
	-- between two names reads as "did this to" in every game that has
	-- ever shipped one, and it survives translation.
	FeedIconSize = 26,
	FeedGap = 10,
}
