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

	Pads = {
		{
			Tag = "SpeedBooster1",
			Speed = 150, -- speed the boost pins you to, studs/s
			Duration = 1.2, -- seconds it holds
			Tier = 3, -- which FX colour / note / FOV punch to reuse
		},
	},
}
