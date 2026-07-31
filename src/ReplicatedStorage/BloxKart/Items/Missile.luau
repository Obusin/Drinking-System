--[[
	Missile — a homing projectile aimed at the racer ahead.

	Actually flies now, rather than resolving instantly. Server-owned and
	kinematically integrated (see ProjectileService), so it's dodgeable:
	HomingRate caps how hard it can turn, which is the difference between
	a weapon and a guaranteed hit.

	IT HUNTS WHOEVER IS IN THE WAY
	------------------------------
	Not whoever the standings say is next. It rides the checkpoint route
	and locks the first kart that gets in front of it, wherever they are
	in the race — which is both simpler and better to play against. The
	old version would fly straight through somebody because they weren't
	the racer one place ahead.

	FIRES EVEN WITH NOBODY THERE
	----------------------------
	It always launches. An item that refuses to fire reads as broken, and
	"useless in first place" is a worse problem than "occasionally
	misses". With nobody about it rides the route and expires.

	FORWARD OR BACKWARD
	-------------------
	Q throws it down the track, E sends it back up. It rides the same
	rails either way and locks whoever it meets.
--]]

return {
	Id = "Missile",
	Tint = Color3.fromRGB(255, 130, 60), -- fallback tile if Icon fails to load
	Icon = "rbxassetid://140037887012524", -- rocket
	Name = "MISSILE",
	Scope = "world", -- affects another player, so the server owns it
	Weight = 90,

	--== FLIGHT ========================================================
	Speed = 210, -- studs/s. Comfortably faster than a boosting kart
	-- HomingRate is a turn RATE, and Speed / HomingRate is the tightest
	-- circle the missile can fly. At 210 studs/s, the old 3.2 meant a
	-- 66-stud turning circle against a 7-stud kill radius — it could not
	-- physically reach a target it had not already lined up on.
	--
	-- Simulated across bearings from 0 to 180 degrees and ranges from 15
	-- to 60 studs: 3.2 failed to terminate 11 of 65 engagements, circling
	-- until it expired, and missed a target directly behind it by 60
	-- studs. At 9 all 65 terminate. 9 gives a 23-stud circle.
	HomingRate = 9, -- how hard it can steer toward the target. Higher
	-- is harder to dodge; uncapped would be unavoidable
	-- RANGE = Speed x Lifetime. At 210 studs/s, 5s was only 1050 studs —
	-- three or four checkpoints — so a missile aimed at someone further
	-- round the track simply expired mid-route and vanished, which looks
	-- exactly like it hit something invisible.
	Lifetime = 12, -- ~2500 studs of range

	HitRadius = 7,

	-- PROXIMITY FUZE. Detonates the moment the range to the locked target
	-- stops closing while inside this, because that instant IS the
	-- closest approach.
	--
	-- Without it a missile that misses turns around and tries again, and
	-- again — the back-and-forth. That is inherent to pursuit guidance,
	-- not a tuning fault: steering at the target's current bearing needs
	-- an ever-tighter turn as the range drops, and past some point no
	-- turn rate is enough. Raising HomingRate moves where it starts and
	-- never removes it.
	--
	-- Bigger than HitRadius on purpose: a near miss should count. Worst
	-- observed detonation distance at 14 is about 13 studs, which reads
	-- as a hit rather than as a missile giving up.
	FuzeRadius = 14,

	--== HEIGHT ========================================================
	-- Held above whatever road is under the racing line, probed each
	-- frame rather than taken from the checkpoint's own height — a
	-- checkpoint volume can sit well above the tarmac.
	-- Low enough to read as skimming the road rather than flying over it,
	-- high enough to clear kerbs and the kart's own bodywork. The hitbox
	-- centre sits about 1.2 above the road, so this stays well inside
	-- HitRadius vertically.
	CruiseHeight = 3, -- studs above the surface
	CruiseProbe = 80, -- how far down to look for road. Needs to exceed
	-- any drop it should fly over rather than dive into
	ClimbRate = 7, -- how hard it corrects its height. Too high and it
	-- snaps to the road like a magnet; too low and it clips crests


	--== ON THE RAILS ==================================================
	-- The missile rides the checkpoint spline rather than steering toward
	-- it, so it physically cannot cut a corner into the scenery or orbit
	-- a waypoint it can't turn tightly enough to reach. See Ballistics.
	--
	-- There is deliberately no obstacle avoidance any more. Nothing to
	-- avoid: it never leaves the road.

	-- How far across the road it will slide to line up with its target.
	-- Roughly half a track width — beyond that it's aiming at someone on
	-- a different piece of road.
	MaxLateral = 18,
	LateralRate = 2.2, -- how fast it drifts across. Snapping sideways
	-- reads as a bug; drifting across is what a real one does

	--== ACQUISITION ===================================================
	-- It hunts WHOEVER gets in the way, not whoever the standings say is
	-- next. Simpler, and much better to play against: a missile that only
	-- ever wanted the person one place ahead ignored the racer it was
	-- flying straight through.
	--
	-- Once it locks, it never lets go.
	AcquireRange = 60, -- how close a kart has to be to get locked
	AcquireArc = 0.3, -- must be roughly in FRONT of the missile's travel
	-- (dot product). 0 would let it lock something it has already passed

	-- Seconds to settle from the launch point onto the racing line. Long
	-- enough that it visibly leaves the kart, short enough that it's on
	-- the rails before the first corner.
	RailBlend = 0.35,

	Projectile = {
		Size = Vector3.new(1.3, 1.3, 3.6),
		Color = Color3.fromRGB(255, 120, 60),
		Material = Enum.Material.Neon,
		Offset = 8, -- studs ahead of the shooter, so it clears own hitbox
	},

	--== ON HIT ========================================================
	SpinTime = 1.6,
	SpeedKeep = 0.3,
	StunTime = 0.0, -- spins you, but you keep steering
	HitNote = 2,

	Use = function(ctx)
		-- No target named. It rides the route and locks whoever gets in
		-- the way — see ProjectileService. Direction is the only choice
		-- the player makes, and it always fires.
		ctx.fireProjectile("Missile")
		return true
	end,
}
