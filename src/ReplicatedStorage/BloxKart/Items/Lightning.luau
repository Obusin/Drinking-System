--[[
	Lightning — hits EVERY racer ahead of you at once.

	The big swing. Rare, and position weighting makes it rarer still at
	the front, so in practice it's what last place occasionally gets to
	turn a race around.

	EVERYONE IN THE DIRECTION YOU THREW IT
	--------------------------------------
	Q hits everybody in front, E everybody behind. Worked out from a dot
	product against where you're pointing, not from the standings — those
	only contain racers whose progress has replicated, so anyone who
	hasn't reported yet is invisible to them, and so is your own place.
	That made this item silently do nothing.

	Hits nobody when there's nobody that way, in which case it refuses to
	fire and stays in your hand rather than being wasted.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local IT = require(ReplicatedStorage:WaitForChild("BloxKart"):WaitForChild("Config")).Items

return {
	Id = "Lightning",
	Tint = Color3.fromRGB(255, 230, 90),
	Icon = "rbxassetid://125335826328787", -- lightning
	Name = "LIGHTNING",
	Scope = "world", -- reaches other players, so the server relays it
	-- Deliberately low. It's the rarest thing in the pool, and position
	-- weighting pushes it further towards the back of the field.
	-- RARE, not removed. At 30 it came up about one box in sixteen, and
	-- an item that hits everybody ahead at once should be a thing that
	-- happens to a race rather than a thing that happens every lap —
	-- half the field spinning is memorable the first time and tiresome
	-- the fourth.
	--
	-- 14 puts it near one box in thirty-three. Still the second rarest
	-- thing in the pool after Refill, and still reachable often enough
	-- that holding one feels like luck rather than a bug.
	Weight = 14,

	--== ON HIT ========================================================
	-- Shorter spin than a mine: it lands on several people at once, so
	-- the same duration would be far more total disruption than any other
	-- item in the game.
	SpinTime = 1.1,
	SpeedKeep = 0.25,
	StunTime = 0.0, -- you keep steering; it's a stumble, not a stop
	HitNote = 3,

	Use = function(ctx)
		local targets = ctx.everyone()
		if #targets == 0 then
			return false, if ctx.back then "nobody behind" else "nobody ahead"
		end
		for _, kart in targets do
			ctx.fire(kart, {
				spin = 1.1,
				keep = 0.25,
				stun = 0.0,
				note = 3,
				-- WIND-UP. Lightning used to land the instant it was
				-- used, which meant being spun with nothing to see and
				-- nothing that could have warned you. The delay is not
				-- for balance — it is so the warning has somewhere to
				-- live. The server holds the effect and tells the victim
				-- first.
				windUp = IT.LightningWindUp,
			})
		end
		return true
	end,
}
