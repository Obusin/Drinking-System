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
	-- Nobody dies in a kart racer; they spin, lose four seconds and carry
	-- on. This is that moment.
	XpPerTakedown = 25,

	-- Knocking someone into the void. The best thing you can do to
	-- another racer with an item, and priced accordingly — but it is
	-- still a tally and a reward, not a removal. They respawn at their
	-- last checkpoint exactly as they always have.
	XpPerElimination = 60,

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

	--== LEVELLING UP =================================================
	-- Bolt paid for reaching a new level. Flat, on purpose: a reward
	-- that scales with level pays most to the people who need it least,
	-- and the curve already makes later levels take longer. The reward
	-- for levelling is the level.
	--
	-- SESSION ONLY, like the XP itself. Nothing persists until
	-- DataService exists, and the results panel says so.
	BoltPerLevel = 150,

	--== THE TEMPORARY HUD =============================================
	-- Placeholder. Stacking toasts bottom-centre, and a banner on the
	-- level. Meant to be replaced wholesale by the real design — it is
	-- here so the numbers are visible while they are being tuned, which
	-- is the only way to find out whether they feel right.
	ToastHold = 1.5,
	ToastFade = 0.6,
	ToastRows = 4,
	ToastSize = 22,
	ToastRowHeight = 28,
	ToastPosition = UDim2.fromScale(0.5, 0.72),

	BannerHold = 2.2,
	BannerFade = 0.8,
	BannerSize = 52,
	BannerSubSize = 20,
	BannerPosition = UDim2.fromScale(0.5, 0.33),

	-- What each award is called on screen. The key is the `reason`
	-- string Progress already writes for its audit line, so the two
	-- cannot drift — a reason with no label here shows the reason.
	Labels = {
		hit = "HIT",
		takedown = "TAKEDOWN",
		elimination = "ELIMINATION",
	},

	--== PER-RACE STAT CAPS ============================================
	-- The driving counters — drifts, nitro, air, items used — can only
	-- be seen by the client, so the client is what reports them. It
	-- sends ONE batch at the flag rather than an event at a time, and
	-- every value is clamped here before it counts.
	--
	-- THIS IS A BOUND, NOT A FIX. A modified client can still claim the
	-- cap every race. The cap makes that worth roughly one very good
	-- race instead of unlimited, which is the difference between an
	-- exploit and a rounding error — and it stays that way only while
	-- none of this persists. Close the seams before it does.
	--
	-- Numbers are "a very good race, doubled". If an honest player ever
	-- hits one, the cap is wrong, not the player.
	StatCaps = {
		drifts = 200,
		driftBoosts = 120,
		driftTier3 = 40,
		driftSeconds = 240,
		nitroBurns = 40,
		nitroTanks = 60,
		itemsUsed = 40,
		-- Per-item keys are `itemsUsed_<Id>` and are capped by the
		-- `itemsUsed` entry above rather than needing one each. Adding an
		-- item to the catalogue must not also require editing this table.
		itemBoxes = 40,
		shieldBlocks = 12,
		hazardsDropped = 30,
		boostPads = 60,
		airSeconds = 90,
		landings = 80,
		topSpeedSeconds = 240,
		raceSeconds = 600,
		laps = 12,
		checkpoints = 200,
		respawns = 40,
		cleanRaces = 1,
		bestLap = 1,
	},

	--== QUEST PANEL ===================================================
	-- Left edge, under the leaderboard slot, after the reference. Rows
	-- carry their own reward and bar; the layer header carries the
	-- countdown, because a per-row timer would say the same thing three
	-- times.
	QuestPosition = UDim2.fromScale(0.012, 0.30),
	QuestWidth = 340,
	QuestRowHeight = 62,
	QuestHeaderHeight = 30,
	QuestTitleSize = 16,
	QuestTextSize = 15,
	QuestSmallSize = 13,
	QuestBarHeight = 6,
	QuestPanelColor = Color3.fromRGB(18, 18, 20),
	QuestPanelTransparency = 0.25,
	QuestDoneColor = Color3.fromRGB(120, 230, 130),

	-- Which layers the panel shows, in order. All three now that the
	-- panel is behind a button — the reason to cut Monthly was that
	-- three layers at once crowded the racing screen, and nothing is on
	-- the racing screen any more.
	QuestLayers = { "Daily", "Weekly", "Monthly" },

	-- The tab. Closed by default: a racing HUD should show what you need
	-- while driving, and a quest list is not that.
	QuestOpenKey = Enum.KeyCode.J,
	QuestButtonPosition = UDim2.fromScale(0.012, 0.30),
	QuestButtonSize = Vector2.new(132, 34),
	QuestButtonText = "MISSIONS",
	-- Shown on the tab when something is finished and unclaimed. The
	-- whole point of collapsing the panel is that you stop looking at
	-- it, so it has to be able to get your attention back.
	QuestBadgeColor = Color3.fromRGB(120, 230, 130),

	-- The layer switcher inside the panel. One frame, three tabs, and
	-- the rows below swap — rather than three stacked lists, which was
	-- the same information in three times the height.
	QuestTabHeight = 28,
	QuestTabActive = Color3.fromRGB(255, 196, 62),
	QuestTabIdle = Color3.fromRGB(48, 48, 54),
	QuestRows = 5, -- the widest layer; the pool is shared across tabs

	--== FEED ==========================================================
	-- The kill-feed line is "<attacker> [icon] <victim>". The icon
	-- carries the verb, which is why there is no word for it: an icon
	-- between two names reads as "did this to" in every game that has
	-- ever shipped one, and it survives translation.
	FeedIconSize = 26,
	FeedGap = 10,
}
