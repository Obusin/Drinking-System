--[[
	Boosters — speed pads in the world.

	Tag any part with one of the tags below (CollectionService, via the
	Tag Editor in Studio) and driving over it fires a boost.

	The pads are expected to be CanCollide = false — you drive THROUGH
	them, not into them. Detection is an overlap query rather than a
	.Touched event or a collision, so it doesn't care.

	Add a tier by adding a row. Nothing else needs to change.
--]]

return {
	-- Per-pad retrigger guard, seconds. Stops one pad firing every frame
	-- while you're sitting on it.
	Cooldown = 0.6,

	-- Global guard, seconds. Stops a row of overlapping pads stacking
	-- into one enormous boost.
	GlobalCooldown = 0.25,

	-- Force CanQuery on tagged parts client-side. A pad authored with
	-- CanQuery off is invisible to spatial queries, which would make it
	-- silently do nothing. This is a local-only fix and costs nothing.
	ForceQueryable = true,

	--== THE LADDER ====================================================
	-- THE NUMBER IN THE TAG IS THE TIER. `SpeedBooster2` is a tier-2
	-- boost, and it looks like one — blue, orange, purple, the same
	-- palette as the drift charge and the nitro tank, so a pad tells you
	-- how big it is before you reach it.
	--
	-- That was NOT true before: there was only `SpeedBooster1` and it was
	-- set to `Tier = 3`, so the one pad in the game fired the strongest
	-- effect off the weakest-sounding name. With three of them that
	-- mismatch stops being a curiosity and starts being a trap while
	-- laying out a track.
	--
	-- SIZED AGAINST WHAT ALREADY EXISTS, so a pad is comparable to the
	-- other ways of going fast rather than a number picked in isolation:
	--
	--   top speed              95
	--   nitro stage 1/2/3      +18 / +45 / +80   (so 113 / 140 / 175)
	--   flip ramp landing      140
	--   glide ramp launch      155
	--
	-- Tier 2 deliberately matches the flip ramp's 140 and tier 3 sits
	-- just above the glide launch — so PAIRING A PAD WITH A RAMP adds to
	-- it rather than being swallowed by it, which is the whole point of
	-- putting one in front of a jump.
	--
	-- Duration falls as speed rises. A big boost that also lasted longest
	-- would make the small ones pointless; the trade is punch against
	-- how long you have to hold it straight.
	Pads = {
		{
			Tag = "SpeedBooster1",
			Speed = 140, -- speed the boost pins you to, studs/s
			Duration = 1.4, -- seconds it holds
			Tier = 1, -- which FX colour / note / FOV punch to reuse
		},
		{
			Tag = "SpeedBooster2",
			Speed = 160,
			Duration = 1.2,
			Tier = 2,
		},
		{
			Tag = "SpeedBooster3",
			Speed = 190,
			Duration = 1.0,
			Tier = 3,
		},
	},
}
