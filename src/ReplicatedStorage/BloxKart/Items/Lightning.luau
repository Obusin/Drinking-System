--[[
	Lightning — hits EVERY racer ahead of you at once.

	The big swing. Rare, and position weighting makes it rarer still at
	the front, so in practice it's what last place occasionally gets to
	turn a race around.

	WHY IT ONLY HITS FORWARD
	------------------------
	Same rule as the missile: nothing ever hits backwards. Mario Kart's
	lightning zaps the whole field including the people behind you, which
	is only fair because it's near-impossible to roll while leading. Ours
	keeps the simpler guarantee — an item can never be used to extend a
	lead — because that one rule is most of what stops a kart item system
	feeling unfair.

	Hits nobody when you're already first, so it refuses to fire and stays
	in your hand rather than being wasted.
--]]

return {
	Id = "Lightning",
	Tint = Color3.fromRGB(255, 230, 90),
	Icon = "", -- falls back to the tinted tile until there's art
	Name = "LIGHTNING",
	Scope = "world", -- reaches other players, so the server relays it
	-- Deliberately low. It's the rarest thing in the pool, and position
	-- weighting pushes it further towards the back of the field.
	Weight = 30,

	--== ON HIT ========================================================
	-- Shorter spin than a mine: it lands on several people at once, so
	-- the same duration would be far more total disruption than any other
	-- item in the game.
	SpinTime = 1.1,
	SpeedKeep = 0.25,
	StunTime = 0.0, -- you keep steering; it's a stumble, not a stop
	HitNote = 3,

	Use = function(ctx)
		local targets = ctx.aheadAll(ctx.kart)
		if #targets == 0 then
			return false, "nobody ahead"
		end
		for _, kart in targets do
			ctx.fire(kart, {
				spin = 1.1,
				keep = 0.25,
				stun = 0.0,
				note = 3,
			})
		end
		return true
	end,
}
