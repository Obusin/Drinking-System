--[[
	Skins — what a kart can look like.

	INTERIM. Every racer is given a look at random and keeps it; the
	garage will replace the PICKER and nothing else. The pools, the way a
	skin is a set of mesh ids, and the fact that none of it touches
	handling are all already the shape the garage needs — see the vault
	note "BloxKart Kart Customization and Skinning".

	NOTHING HERE CAN AFFECT HOW A KART DRIVES. Simulation reads the
	Hitbox and the Seat and nothing else, so a body mesh and a wheel mesh
	are decoration by construction rather than by discipline.
--]]

return {
	Enabled = true,

	-- Bodies and wheels are drawn INDEPENDENTLY, so two ids each give
	-- four silhouettes rather than two. That matters while the pools are
	-- this small.
	Bodies = {
		"rbxassetid://72597967734984",
		"rbxassetid://89589911208680",
	},

	-- Front and rear are picked as a PAIR from here, not separately. A
	-- kart with mismatched axles reads as a bug rather than as a build,
	-- and it is the one combination nobody would choose in a garage.
	Wheels = {
		"rbxassetid://136481236962745",
		"rbxassetid://124866750857410",
	},

	--== PAINT =========================================================
	-- The palette itself stays in Rig.Colors, which is one colour per
	-- grid slot and chosen to stay distinct for the common
	-- colour-blindness types. That property is worth more than variety,
	-- so it is NOT randomised per racer — two people in the same round
	-- must never be hard to tell apart.
	--
	-- Instead the palette is ROTATED each round. Every racer still gets
	-- a colour nobody else has; which one they get changes. Variety
	-- across races, distinctness within one.
	RotatePaintPerRound = true,
}
