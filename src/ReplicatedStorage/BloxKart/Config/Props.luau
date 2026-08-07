--[[
	Props — scenery you can knock over. Traffic cones, essentially.

	COSMETIC BY CONSTRUCTION. A prop never affects handling: it is made
	non-queryable, so the kart's movement sweep cannot see it at all. It
	cannot slow you, stop you, or bounce you — the collision it appears to
	have is entirely the animation playing afterwards.

	That is deliberate and it is the only safe design here. A prop that
	COULD affect movement would be art with an opinion about handling,
	which is exactly what the Consistency Rule exists to prevent.

	CLIENT-SIDE, AND WHAT THAT COSTS
	--------------------------------
	The fling is local: your client animates it, and other players do not
	see your cone fly. That is the same trade the drift sparks already
	make, and it buys perfect smoothness with zero replication.

	If props ever need to agree between players, that is a server change
	and a real one — not a tweak to this file.
--]]

return {
	-- Tag a part (or a model's parts) with this and it becomes flingable.
	Tag = "Prop",

	-- How close the kart's centre must get. Generous, because the sweep
	-- never touches these — this radius IS the collision.
	HitRadius = 7,

	-- CARRIED, NOT CONSTANT. A cone brushed at a crawl should barely
	-- move; one hit at full speed should leave the postcode. Scaled by
	-- the kart's speed as a fraction of top speed.
	MinLaunch = 22, -- studs/s at a crawl
	MaxLaunch = 90, -- ...and at top speed
	Lift = 0.55, -- how much of the launch goes upward. Purely how it
	-- looks: too little and it skids, too much and it rockets vertically.
	Spin = 14, -- radians/sec of tumble, randomised per hit

	Gravity = 120, -- for the arc. Not Handling.Gravity — a cone is light
	-- and should hang a little longer than a kart does.

	-- Back to where it started, so a track is not slowly stripped bare
	-- over a long session.
	RestoreAfter = 6, -- seconds airborne before it returns
	FadeBack = 0.4, -- seconds to ease home, so it does not snap

	-- Belt and braces: a prop is forced non-queryable on discovery. An
	-- artist who forgets cannot accidentally turn scenery into a wall.
	ForceNonQueryable = true,

	Debug = true, -- prints what got adopted and what got flung. Turn off for release.
}
