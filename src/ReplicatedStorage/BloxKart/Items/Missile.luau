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

	--== TERRAIN FOLLOWING =============================================
	-- Fired straight down the kart's nose, a missile buries itself in the
	-- first dip or ramp it meets. It flies at a fixed height above the
	-- road instead, correcting every frame.
	CruiseHeight = 6, -- studs above the surface
	CruiseProbe = 80, -- how far down to look for road. Needs to exceed
	-- any drop it should fly over rather than dive into
	ClimbRate = 7, -- how hard it corrects its height. Too high and it
	-- snaps to the road like a magnet; too low and it clips crests

	-- What separates "the road" from "a wall". Dot of the surface normal
	-- against the missile's own up: 1 is flat floor, 0 is sheer wall.
	-- Anything above this is terrain to follow, and crucially NOT
	-- something to explode on — treating the floor as a wall is why the
	-- missile used to die on the first bump.
	FloorDot = 0.45,

	--== ROUTE FOLLOWING ===============================================
	-- Follows the checkpoint route round corners until the target is
	-- close enough to chase directly. Without this it flies into the
	-- outside wall of the first bend, which on a real track means it
	-- never reaches anybody.
	WaypointRadius = 22, -- how close before advancing to the next node
	WaypointTurnRate = 2.6, -- gentler than HomingRate: the route is a
	-- suggestion, and a missile that snaps between waypoints looks robotic
	HomingRange = 100, -- switch from route to direct chase inside this,
	-- but only once it's within a segment of the target — see Ballistics

	--== OBSTACLE AVOIDANCE ============================================
	-- The route says where to go; this stops it flying into things on the
	-- way. Without it, cutting the corner between two checkpoints works
	-- fine until the corner has a cliff in it.
	AvoidDistance = 48, -- how far ahead it looks. Roughly a quarter-second
	-- of flight, which is how long it needs to turn
	AvoidAngle = 40, -- degrees off-nose for the side probes
	AvoidStrength = 10, -- how hard it swerves clear. Higher is tighter but
	-- twitchier; too high and it wobbles down a straight corridor

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
		-- Target is a hint. Nil is fine — it flies straight.
		ctx.fireProjectile("Missile", ctx.aheadOf(ctx.kart))
		return true
	end,
}
