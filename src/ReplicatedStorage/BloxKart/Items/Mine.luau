--[[
	Mine — dropped behind you, spins out whoever drives through it.

	THE ONLY ITEM THAT HELPS A LEADER
	---------------------------------
	Every other item in the pool is either neutral or aimed forward, so
	without this, being in first place is pure downside — you're the only
	target and nothing you hold defends you. A rear-facing hazard is what
	makes leading a position worth holding rather than just surviving.

	Spawned by the server (see RaceService): a client can't be trusted to
	place a world object that affects other players, and the leader's
	client vanishing shouldn't leave a phantom hazard behind.
--]]

local IT = require(script.Parent.Parent.Config).Items

return {
	Id = "Mine",
	Tint = Color3.fromRGB(255, 80, 70), -- fallback tile if Icon fails to load
	Icon = "rbxassetid://129542217375702", -- bomb
	Name = "MINE",
	Scope = "world",
	Weight = 70,

	DropBack = 12, -- studs behind the kart
	Lifetime = 25,

	-- What being hit does. Stun is short on purpose: losing control to
	-- something you drove into is fair, losing it for long isn't.
	SpinTime = 1.5,
	SpeedKeep = 0.3,
	StunTime = 0.0, -- mines spin you but leave you steering
	HitNote = 1, -- index into Audio.TierNotePitches, for variety

	-- Appearance is declared here, not in the server, so adding a hazard
	-- item never means editing RaceService.
	Hazard = {
		Size = Vector3.new(3, 1.2, 3),
		Color = Color3.fromRGB(255, 90, 70),
		Material = Enum.Material.Neon,
		Transparency = 0.15,
	},

	Use = function(ctx)
		-- Behind by default, lobbed ahead when thrown forward. Along the
		-- kart's own up so it lands on the track rather than inside it on
		-- a loop.
		local drop, lift = 12, 1.5
		local at = ctx.sim.pos + ctx.sim.forward * (if ctx.back then -drop else IT.ThrowAhead) + ctx.sim.up * lift
		ctx.dropHazard(CFrame.lookAt(at, at + ctx.sim.forward, ctx.sim.up), "Mine")
		return true
	end,
}
