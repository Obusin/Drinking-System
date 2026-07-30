--[[
	Oil Spill — a slick dropped behind you. Spins AND briefly stuns.

	The same hazard machinery as Mine, with a different footprint and a
	harsher effect: wide and flat so it's hard to thread past, and it
	takes your steering for a moment rather than just your speed.

	Mine is a precise trap you can dodge. Oil is an area denial you
	mostly can't. Two rear-facing items that play differently is worth
	more than two that play the same.

	Reuse this file as the template for a Banana — copy it, shrink the
	footprint, change HitNote for a different sound.
--]]

return {
	Id = "OilSpill",
	Tint = Color3.fromRGB(150, 130, 200), -- fallback tile if Icon fails to load
	Icon = "rbxassetid://129542217375702", -- bomb
	Name = "OIL",
	Scope = "world",
	Weight = 70,

	DropBack = 10,
	Lifetime = 20,

	SpinTime = 1.6,
	SpeedKeep = 0.35,
	-- A full second of no control. Deliberately the only item that does
	-- this — if several did, races would stop feeling like driving.
	StunTime = 1.0,
	HitNote = 0, -- lower note than a Mine, so they sound distinct

	Hazard = {
		-- Wide and almost flat: a puddle, not an object.
		Size = Vector3.new(9, 0.2, 9),
		Color = Color3.fromRGB(12, 12, 16),
		Material = Enum.Material.Glass,
		Transparency = 0.2,
	},

	Use = function(ctx)
		local at = ctx.sim.pos - ctx.sim.forward * 10 + ctx.sim.up * 0.6
		ctx.dropHazard(CFrame.lookAt(at, at + ctx.sim.forward, ctx.sim.up), "OilSpill")
		return true
	end,
}
