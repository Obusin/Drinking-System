--[[
	Turbo — instant boost. The reliable one.

	Every item pool needs a filler that is never useless. Missiles are
	dead weight in first place and Mines are dead weight in last; a boost
	is worth having wherever you are, which is what stops a bad roll
	feeling like nothing happened.
--]]

return {
	Id = "Turbo",
	Tint = Color3.fromRGB(90, 210, 255), -- fallback tile if Icon fails to load
	Icon = "rbxassetid://134440372024922", -- nitro
	Name = "TURBO",
	Scope = "self",
	-- Highest weight: it's the floor of the pool, not the prize.
	-- Cut hard from 100. Between this and Refill the pool used to be over
	-- a third nitro, which made most boxes feel like the same box.
	Weight = 40,
	-- Flat weight regardless of position: this is the floor of the pool,
	-- the thing a leader can still usefully hold. See Items.roll.
	Filler = true,

	Speed = 165,
	Duration = 1.6,

	Use = function(ctx)
		ctx.sim:ApplyBoost(165, 1.6)
		return true
	end,
}
