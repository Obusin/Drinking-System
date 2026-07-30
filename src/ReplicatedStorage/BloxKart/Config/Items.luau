--[[
	Items — power-ups picked up by driving through a floating box.

	Tag parts `PowerUps` in the Tag Editor. Like every other trigger they
	should be CanCollide = false — you drive THROUGH them. If you don't
	have art yet, ItemService builds a spinning neon cube for any tagged
	part it finds, so a plain Part works.
--]]

return {
	BoxTag = "PowerUps",
	RespawnTime = 6, -- seconds before a collected box comes back
	PickupCooldown = 1.0,

	-- Stack up to three. Picked up first is used first (FIFO), so the
	-- order you collect in is the order you spend in — predictable, and
	-- it means driving over a box is never a decision you can get wrong.
	--
	-- Set to 1 for the stricter "spend before you collect" rule.
	MaxHeld = 3,
	UseKeys = { Enum.KeyCode.Q, Enum.KeyCode.ButtonX },

	-- Getting hit costs you everything you were holding.
	--
	-- Makes a hit hurt beyond the spin, and it's what gives Shield real
	-- value: blocking now protects your stack, not just your speed. A
	-- blocked hit drops nothing.
	--
	-- Items are lost rather than scattered on the track — scattering
	-- rewards whoever happens to be behind you, which punishes you twice
	-- for one mistake.
	DropOnHit = true,

	--== ROULETTE ======================================================
	-- Picking up doesn't hand you the item — it spins through the pool
	-- and lands on it, slot-machine style. The anticipation is most of
	-- what makes a box worth driving into.
	--
	-- Fast to slow: interval grows as the spin progresses, so it decays
	-- rather than stopping dead. Total is capped at RouletteTime so the
	-- reveal never outlives the corner you picked it up on.
	RouletteTime = 2.5,
	RouletteTickFast = 0.045, -- seconds between names at the start
	RouletteTickSlow = 0.30, -- ...and at the end
	RouletteEase = 2.2, -- how sharply it decelerates. Higher = later brake

	-- Hazards dropped into the world by items (Mine). Server-spawned and
	-- tagged; clients detect them the same way they detect boost pads.
	HazardTag = "KartHazard",

	--== PROJECTILE REPLICATION ========================================
	-- Missiles are simulated on the server for hits and drawn by each
	-- client for looks (see ProjectileService / KartClient.Projectiles).
	-- These govern how the two are kept in step.
	--
	-- How often the server sends an authoritative position. This is the
	-- entire network cost of a projectile in flight, so it wants to be as
	-- slow as drift allows — both ends run identical guidance, so this is
	-- a correction, not the thing driving the motion.
	ProjectileSyncInterval = 0.2,
	-- How fast a client eases onto a correction. Spread over a few frames
	-- so a correction reads as the missile adjusting rather than jumping.
	ProjectileCorrectRate = 6,
	-- Past this much error, easing would look like the missile sliding
	-- sideways through the air, so it snaps and accepts one visible jump.
	ProjectileSnapDistance = 25,
	HazardSize = 3,
	HazardColor = Color3.fromRGB(255, 90, 70),
	-- Grace before your own mine can hit you, so dropping one at speed
	-- doesn't immediately spin the person who dropped it.
	HazardOwnerGrace = 1.5,

	-- Box appearance, built for any tagged part that has no art of its
	-- own. Purely cosmetic and entirely client-side.
	BoxSize = 4,
	BoxColor = Color3.fromRGB(255, 255, 255),
	BoxSpin = 60, -- degrees per second
	BoxBob = 0.6, -- studs of float
	BoxBobRate = 1.4,
}
