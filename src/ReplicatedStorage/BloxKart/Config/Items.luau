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
	-- FORWARD and BACKWARD, as a pair.
	--
	-- E rather than a mouse button: right mouse is already free-look and
	-- left would mean the aiming hand doing two jobs — you could never
	-- fire while looking around, which is exactly when you want to throw
	-- backwards. E sits next to W, so it's the same left hand that's
	-- already on WASD + Space + Shift + Q, and Q/E as a pair is the usual
	-- convention for one action with two variants.
	--
	-- NOTE: E is also Input.ExitKeys, which only binds when AllowExit is
	-- on — i.e. in test mode. Change one of them if you turn that on.
	UseKeys = { Enum.KeyCode.Q, Enum.KeyCode.ButtonX },
	UseBackKeys = { Enum.KeyCode.E, Enum.KeyCode.ButtonB },

	-- Firing while look-back is held throws backwards whichever key you
	-- pressed. Kart games have done this forever and it's nice because
	-- you're aiming at what you can actually see.
	LookBackAims = true,

	-- Where a forward throw STARTS, just clear of the kart's own nose.
	-- It travels from here; see ThrowSpeed below.
	ThrowAhead = 6,

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

	-- Folder in ServerStorage holding hazard/pickup art. An item's
	-- Hazard.Model names a Model inside it; without one the hazard is
	-- just the coloured part its Hazard spec describes.
	HazardModelFolder = "Powerups",

	--== DROPPED ITEMS =================================================
	-- Getting spun scatters your stack onto the track instead of deleting
	-- it. Someone else can pick it up — including the person who hit you,
	-- which is a nice reward, and including you if you recover fast
	-- enough, which turns a spinout into something you can partly undo.
	--
	-- A dropped item grants exactly what it is, unlike a box, which rolls.
	DropTag = "KartDroppedItem",
	DropLifetime = 15, -- long enough for the pack to reach it, short
	-- enough that a busy lap doesn't carpet the track
	DropSpread = 5, -- studs between them when a full stack scatters
	DropSize = 3,
	DropBillboard = 4.5, -- studs across, the icon shown above it
	DropBob = 0.6,
	DropBobRate = 2.4,

	--== PROJECTILE REPLICATION ========================================
	-- Missiles are simulated on the server for hits and drawn by each
	-- client for looks (see ProjectileService / KartClient.Projectiles).
	-- These govern how the two are kept in step.
	--
	-- How often the server sends an authoritative position. This is the
	-- entire network cost of a projectile in flight, so it wants to be as
	-- slow as drift allows — both ends run identical guidance, so this is
	-- a correction, not the thing driving the motion.
	-- Draws what a missile is actually doing: a line to whatever it's
	-- steering at, green while following the checkpoint route and red once
	-- it commits to a chase, plus a marker at every route node and a
	-- flash where obstacle avoidance fires. The server logs why each one
	-- died.
	--
	-- On while there's still a missile bug to find; off for players.
	ProjectileDebug = true,
	ProjectileDebugWidth = 0.35,
	ProjectileDebugRoute = Color3.fromRGB(80, 220, 120),
	ProjectileDebugHome = Color3.fromRGB(255, 90, 90),
	ProjectileDebugAvoid = Color3.fromRGB(255, 200, 60),
	ProjectileDebugNode = Color3.fromRGB(90, 170, 255),
	ProjectileDebugNodeSize = 3,

	ProjectileSyncInterval = 0.2,
	-- How fast a client eases onto a correction. Spread over a few frames
	-- so a correction reads as the missile adjusting rather than jumping.
	ProjectileCorrectRate = 6,
	-- Past this much error, easing would look like the missile sliding
	-- sideways through the air, so it snaps and accepts one visible jump.
	ProjectileSnapDistance = 25,
	-- Seconds before your OWN hazard can hit you. Others can trigger it
	-- the instant it exists — that asymmetry is the whole point.
	HazardOwnerGrace = 1.5,

	-- Or never. Throwing something forward and then driving into it is
	-- the most annoying way to lose a race, and no amount of grace fixes
	-- it — the trap is ahead of you and you are driving at it.
	--
	-- Off makes the timer above the only protection.
	HazardOwnerImmune = true,

	--== THROWING ======================================================
	-- A forward throw travels instead of appearing 22 studs ahead. Same
	-- reason a thrown shell arcs in any kart game: an item that teleports
	-- into position doesn't read as having been thrown.
	--
	-- Server-animated, so everyone sees the same throw.
	ThrowSpeed = 165, -- studs/s at release, comfortably faster than a kart
	ThrowDrag = 190, -- studs/s^2. Ends up roughly 70 studs out
	ThrowTime = 0.9, -- hard stop, so it can't drift off down a straight

	-- Box appearance, built for any tagged part that has no art of its
	-- own. Purely cosmetic and entirely client-side.
	BoxSize = 4,
	BoxSpin = 60, -- degrees per second
	BoxBob = 0.6, -- studs of float
	BoxBobRate = 1.4,
}
