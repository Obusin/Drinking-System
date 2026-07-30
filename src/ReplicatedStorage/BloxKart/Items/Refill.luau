--[[
	Refill — fills every nitro tank.

	Leans on a system that already exists rather than adding a new one,
	which makes it read as part of the game instead of a bolted-on
	power-up. It's also the only item whose value depends on your own
	skill: worthless if you were already full from drifting well.
--]]

return {
	Id = "Refill",
	Tint = Color3.fromRGB(120, 255, 190), -- fallback tile if Icon fails to load
	Icon = "rbxassetid://134440372024922", -- nitro
	Name = "N2O REFILL",
	Scope = "self",
	-- Deliberately the rarest self item now. Nitro is already earned by
	-- drifting, so handing it out as a pickup competes with the mechanic
	-- the whole game is built around instead of adding to it.
	Weight = 18,

	Use = function(ctx)
		ctx.sim:FillNitro()
		return true
	end,
}
