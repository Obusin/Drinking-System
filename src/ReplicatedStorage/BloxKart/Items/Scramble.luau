--[[
	Scramble — inverts the steering of the racer ahead of you.

	The cruel one. It doesn't slow anybody down or knock them about, so on
	paper it's the weakest item in the pool; in practice it's the most
	disruptive, because a corner taken with reversed steering is a corner
	you drive straight off.

	WHY THIS RATHER THAN MORE STUNS
	-------------------------------
	Spins and stuns all feel the same after a while: you stop, you carry
	on. This takes nothing away and instead makes the player fight their
	own hands, which is funnier to be hit by and much funnier to land.

	It also never takes control away, which matters — being unable to
	steer at all is frustrating, whereas steering badly is a problem you
	can actually work at.
--]]

return {
	Id = "Scramble",
	Tint = Color3.fromRGB(190, 120, 255),
	Icon = "rbxassetid://105654076631080", -- scramble
	Name = "SCRAMBLE",
	Scope = "world",
	Weight = 65,

	--== ON HIT ========================================================
	-- No spin at all. Stacking a spinout on top would just make it
	-- another mine with extra steps.
	SpinTime = 0,
	SpeedKeep = 1,
	StunTime = 0,
	ReverseTime = 3.5, -- seconds of inverted steering. Long enough to
	-- ruin a corner, short enough not to be a death sentence on a straight
	HitNote = 2,

	Use = function(ctx)
		-- Works both ways: scrambling the racer behind you as they line up
		-- an overtake is at least as funny as doing it to the leader.
		local target = ctx.victimOf(ctx.kart)
		if not target then
			return false, if ctx.back then "nobody behind" else "nobody ahead"
		end
		ctx.fire(target, {
			-- No spin, no speed loss: the steering IS the payload.
			spin = 0,
			keep = 1,
			stun = 0,
			reverse = 3.5,
			note = 2,
		})
		return true
	end,
}
