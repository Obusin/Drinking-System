--[[
	Missile — a homing projectile aimed at the racer ahead.

	Actually flies now, rather than resolving instantly. Server-owned and
	kinematically integrated (see ProjectileService), so it's dodgeable:
	HomingRate caps how hard it can turn, which is the difference between
	a weapon and a guaranteed hit.

	FIRES EVEN WITH NO TARGET
	-------------------------
	With nobody ahead — first place, or an empty server — it launches
	straight and can still hit anyone it runs into. An item that refuses
	to fire reads as broken, and "useless in first place" is a worse
	problem than "occasionally misses".

	WHY ONLY FORWARD
	----------------
	It targets the racer ahead and never behind, so items stay a catch-up
	tool rather than a way to extend a lead. That single restriction is
	most of what stops a kart item system feeling unfair.
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
	HomingRate = 3.2, -- how hard it can steer toward the target. Higher
	-- is harder to dodge; uncapped would be unavoidable
	-- RANGE = Speed x Lifetime. At 210 studs/s, 5s was only 1050 studs —
	-- three or four checkpoints — so a missile aimed at someone further
	-- round the track simply expired mid-route and vanished, which looks
	-- exactly like it hit something invisible.
	Lifetime = 12, -- ~2500 studs of range

	HitRadius = 7,

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

	-- Final approach: inside this it leaves the rails and flies straight
	-- at the target, because by then the road and the straight line agree.
	-- Too small and it sails past someone parked beside the centreline.
	StrikeRange = 45,

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
		-- Target is a hint. Nil is fine — it flies the route and hits
		-- whoever it runs into.
		ctx.fireProjectile("Missile", ctx.victimOf(ctx.kart))
		return true
	end,
}
