--[[
	Shield — blocks the next hit.

	Exists so missiles have counterplay. Without it, being hit is pure
	bad luck with no decision attached; with it, holding a shield is a
	real choice about whether you expect incoming fire.

	Timed rather than until-hit, so it can't be banked forever as a
	permanent immunity while you drive.
--]]

return {
	Id = "Shield",
	Tint = Color3.fromRGB(120, 170, 255), -- fallback tile if Icon fails to load
	Icon = "", -- no art yet; the HUD falls back to the name
	Name = "SHIELD",
	Scope = "self",
	Weight = 45,

	Duration = 7,

	Use = function(ctx)
		ctx.sim:GrantShield(7)
		return true
	end,
}
