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

	-- Authored rocket for the missile, by Model name in ServerStorage.
	--
	-- COPIED TO ReplicatedStorage AT STARTUP by KartServer/Assets, because
	-- missiles are drawn by each client locally and ServerStorage is
	-- server-only. Put the model in ServerStorage as normal; the server
	-- publishes it.
	--
	-- "" or a missing model falls back to the plain neon part below, so a
	-- missing asset is a missile that looks basic rather than one that
	-- doesn't appear.
	--
	-- The model should be art only: no scripts, and every part
	-- non-collidable. Both are enforced anyway — scripts are stripped on
	-- publish, and the client forces the parts inert — but a model that
	-- already obeys is one less surprise.
	ProjectileModel = "Rocket",

	-- Roll about its own nose, degrees per second. Nothing reads this but
	-- the visual: it does not steer, and it cannot, because the server
	-- owns where a missile goes.
	ProjectileSpin = 420,

	-- WHICH WAY THE ROCKET POINTS.
	--
	-- Worked out from the model itself: a missile is long and thin, so
	-- its longest bounding-box axis is its nose axis, and that axis is
	-- rotated onto lookAt's -Z. Whatever local axis the model was built
	-- along, it points where it is going.
	--
	-- This replaced a table of four hand-written rotations to choose
	-- between. That was a round trip per guess — launch, watch it fly
	-- sideways, change a number, launch again — and it had to be redone
	-- for every rocket anyone authored. One of the four was also written
	-- down backwards, which is the other reason worked examples lose to
	-- deriving it.
	--
	-- Set false to go back to picking ProjectileModelOffset by hand.
	ProjectileModelAutoFace = true,

	-- The one bit the geometry cannot supply: both ends of a long axis
	-- look identical to a bounding box, so nose and tail are
	-- indistinguishable. If the rocket flies tail-first, flip this.
	--
	-- ON for the current Rocket, which was authored pointing the opposite
	-- way down its long axis. This is the whole reason the boolean
	-- exists — the auto-facing got the axis right and had a one-in-two
	-- chance on the direction, which is exactly what it should be left to
	-- guess at.
	ProjectileModelFlip = true,

	-- Extra rotation applied AFTER the automatic facing, for a model that
	-- is off in some other way — built at a slant, or rolled so the fins
	-- sit wrong. Art only; the flight path never sees it.
	ProjectileModelOffset = CFrame.identity,

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
	DropSize = 3,
	DropBillboard = 4.5, -- studs across, the icon shown above it

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
	--
	-- 1.2 rather than forever, and the number comes from the throw:
	--
	--   tap    lands 26 studs out, which is BEHIND you already
	--   half   lands 59, still behind
	--   full   lands 92, and you reach it 0.76s after releasing
	--
	-- So 1.2 clears your own throw with margin and nothing else. Come
	-- back round on the next lap and it's live — you laid it, and it's
	-- fair that you have to remember where.
	HazardOwnerGrace = 1.2,

	-- Permanent immunity instead. Off by default now: never being able to
	-- hit your own item means the track fills with traps that are free to
	-- you and only dangerous to everyone else, which quietly makes the
	-- leader's position stronger the longer a race runs.
	HazardOwnerImmune = false,

	--== THROWING ======================================================
	-- A forward throw travels instead of appearing 22 studs ahead. Same
	-- reason a thrown shell arcs in any kart game: an item that teleports
	-- into position doesn't read as having been thrown.
	--
	-- Server-animated, so everyone sees the same throw.
	-- Properly ballistic: launched with a velocity and pulled down by
	-- gravity, rather than slid along the floor. Sliding is what it did
	-- first and it never read as a throw — the arc is the entire tell
	-- that something was thrown rather than placed.
	--
	-- Gravity is applied along the KART's up, not the world's, so a throw
	-- on a loop arcs onto the ceiling exactly as it would on the ground.
	-- Tuned against the arithmetic rather than by eye. At Roblox's default
	-- gravity (196):
	--
	--   lift 28 -> 0.29s airborne, 2 studs high. A flat shove.
	--   lift 60 -> 0.61s airborne, 9.2 studs high. A throw.
	--
	-- Speed has to beat the kart or the item never gets away from the
	-- thrower: 190 covers 116 studs in that 0.61s while the kart does 73,
	-- so it lands a clear 43 studs ahead.
	--
	-- Gravity and bounce are Roblox's now — the arc is real physics, not
	-- integrated here. Bounciness comes off the part's Material.
	ThrowSpeed = 150, -- studs/s forward at a FULL wind-up
	ThrowLift = 60, -- studs/s upward. This is the arc
	-- Forward speed the item inherits from the moving kart, on top of the
	-- wind-up. The arc used to be built as if it left a standing kart, so
	-- a "forward" throw barely outran the kart that threw it and landed
	-- almost underneath you.
	--
	-- Roughly a racer's real cruising speed. One constant for everyone
	-- rather than the kart's measured velocity, because a bot's kart is
	-- anchored and reports zero — measuring it would silently make bots
	-- throw shorter than players.
	ThrowLead = 70,

	-- Where a settling hazard looks for the floor. It is placed ON the
	-- surface beneath it rather than frozen wherever it happened to be:
	-- settling can fire on a timeout, and that used to anchor a bomb in
	-- mid-air if it was still flying when the clock ran out.
	SettleProbeUp = 5,
	SettleProbeDown = 300, -- generous: a throw off a high ledge should
	-- still find the road below rather than hang in the sky

	-- Extra seconds to keep FALLING after the throw timer expires, when
	-- the probe still can't see ground.
	--
	-- A hazard is only ever anchored once something is found to sit on.
	-- If nothing is, it is left falling and its lifetime collects it —
	-- because anchoring a thing that never landed is precisely how a
	-- bomb ends up stopped in mid-air over a gap.
	SettleGrace = 3,

	ThrowTime = 4, -- give up waiting for it to settle after this, so an
	-- item thrown off the edge of the map doesn't stay unanchored forever

	--== WIND-UP =======================================================
	-- Hold to charge, release to throw. A tap lobs it just ahead; a full
	-- hold sends it as far as it goes. Turns "which item" into "which
	-- item, and how far", which is a decision worth having on a straight.
	--
	-- Only the forward throw charges. Dropping something behind you is a
	-- defensive reflex, and making that wait for a wind-up would mean
	-- being hit while holding the button meant to save you.
	ThrowChargeTime = 0.65, -- seconds to a full wind-up
	ThrowMinPower = 0.28, -- a bare tap, as a fraction of ThrowSpeed. Not
	-- 0, or a mistimed press drops the item on your own bonnet

	--== SCATTER  (dropped items) ======================================
	-- Items knocked out of you burst outward rather than appearing in a
	-- neat row. Same flight code as a throw, just aimed differently.
	-- 55 gives 0.6s airborne and 8 studs high, so items visibly burst out
	-- of the kart. At 26 they barely left the floor.
	DropPop = 55, -- studs/s upward
	DropScatter = 18, -- studs/s sideways, fanned across the road. Ends up
	-- about 11 studs either side — spread enough to pick one, close
	-- enough to grab two on the way past

	-- Box appearance, built for any tagged part that has no art of its
	-- own. Purely cosmetic and entirely client-side.
	BoxSize = 4,
	BoxSpin = 60, -- degrees per second
	BoxBob = 0.6, -- studs of float
	BoxBobRate = 1.4,
}
