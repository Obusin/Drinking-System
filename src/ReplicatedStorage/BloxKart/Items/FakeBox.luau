--[[
	FakeBox — a decoy that looks like a power-up box and spins you out.

	Costs almost nothing to implement: it's an ordinary hazard whose
	Hazard spec happens to match what a real item box looks like. All the
	work is done by the player's own reflexes.

	WHY IT'S GOOD
	-------------
	It's the only item that makes people distrust the track itself. Every
	other hazard is avoided by looking where you're going; this one
	punishes the thing players do automatically, which is drive at
	anything box-shaped. One of these near a real cluster of boxes is
	worth far more than its spin time suggests.

	Deliberately NOT a perfect copy — see Hazard below.
--]]

local IT = require(script.Parent.Parent.Config).Items

return {
	Id = "FakeBox",
	Tint = Color3.fromRGB(150, 170, 190),
	Icon = "", -- falls back to the tinted tile until there's art
	Name = "FAKE BOX",
	Scope = "world",
	Weight = 60,

	DropBack = 10,
	-- Longer than a mine: the whole point is that it sits there looking
	-- innocent, and a decoy nobody has time to drive into is just a mine.
	Lifetime = 40,

	-- Mild. It trades damage for deception, and a decoy that hit as hard
	-- as a mine would make real boxes genuinely frightening to collect —
	-- which would break the item economy rather than spice it up.
	SpinTime = 1.0,
	SpeedKeep = 0.45,
	StunTime = 0.0,
	HitNote = 0,

	-- Box-shaped and box-sized, but a shade off and not spinning: real
	-- boxes rotate and bob (see Items.startBoxes), so a fake is spottable
	-- if you're paying attention. Being unfair to attentive players is a
	-- different thing from being funny.
	Hazard = {
		Size = Vector3.new(4, 4, 4),
		Color = Color3.fromRGB(170, 180, 195),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.25,

		-- Art from ServerStorage, in Config.Items.HazardModelFolder. The
		-- trigger part above stays the hitbox and turns invisible; the model
		-- is decoration welded to it.
		--
		-- Which is the whole point of a decoy: it has to be something a
		-- player wants to drive into.
		Model = "CurrencyDrop",
	},

	Use = function(ctx)
		-- Behind by default, lobbed ahead when thrown forward. Along the
		-- kart's own up so it lands on the track rather than inside it on
		-- a loop.
		local drop, lift = 10, 2.2
		local at = ctx.sim.pos + ctx.sim.forward * (if ctx.back then -drop else IT.ThrowAhead) + ctx.sim.up * lift
		ctx.dropHazard(CFrame.lookAt(at, at + ctx.sim.forward, ctx.sim.up), "FakeBox")
		return true
	end,
}
