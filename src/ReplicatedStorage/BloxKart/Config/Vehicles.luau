--[[
	Vehicles — what you can drive, and how each one differs.

	ONE CONTROLLER, MANY VEHICLES.

	`Simulation` is unchanged by anything in here. It reads `self.H`, which
	is this table's `handling` block with `Config.Handling` behind it on a
	metatable — so a vehicle lists ONLY what it differs on, and everything
	else resolves to the shared value.

	That is the whole design. The alternative — copying Config.Handling per
	vehicle and editing it — means every future dial has to be added in N
	places, and the day one gets missed is the day a vehicle silently keeps
	an old default nobody remembers setting.

	THE ART IS STILL COSMETIC. A vehicle may name a model in ServerStorage,
	or ask for a placeholder to be built in code, and neither changes how it
	drives — the hitbox is forced to `hitboxSize` whatever the art is. The
	Consistency Rule holds across vehicles exactly as it holds across skins:
	`Simulation` reads the Hitbox and the Seat and nothing else.

	ADDING ONE is a row here plus, optionally, a model. No new code path.
--]]

return {
	-- What anything gets if nothing says otherwise.
	Default = "kart",

	--=================================================================
	--  TESTING SWITCH: PUT EVERY HUMAN ON THIS VEHICLE.
	--
	--  Bots are deliberately NOT included. They keep the kart, so a race
	--  is bike-versus-kart and the difference is visible from the seat
	--  rather than having to be measured — which is the whole reason to
	--  test one vehicle against a field of the other.
	--
	--  It also keeps the bots' learning honest: `BotBrain` is tuned
	--  against kart cornering limits, and swapping the whole field to a
	--  vehicle with different grip would teach it about a track it is
	--  not going to race on.
	--
	--  "" turns it off. This is a switch, not a design — once a vehicle
	--  is chosen in the garage this should go.
	--=================================================================
	ForceForPlayers = "bike",

	Kinds = {
		--=============================================================
		--  THE KART. The baseline every dial in Config.Handling was
		--  tuned against, so its override table is deliberately EMPTY —
		--  "the kart is the default" should be a fact about the data,
		--  not a copy of it.
		--=============================================================
		kart = {
			name = "Kart",
			-- nil means Rig.VisualName, which is the existing behaviour.
			visual = nil,
			build = nil,
			handling = {},
			-- The factory builds one when the art has none.
			steeringWheel = true,

			-- DRIFT TRAILS: one ribbon per rear tyre. Nil means the
			-- default pair at Config.Effects.TrailInset, which is what
			-- every dial in Effects was tuned against.
			trails = nil,
			-- Cosmetic slots this vehicle actually has. The garage reads
			-- this so a bike is never offered a spoiler it cannot wear.
			slots = { "Body", "Rim", "Tire" },
		},

		--=============================================================
		--  THE MOTORCYCLE.
		--
		--  Same kinematic controller, different numbers. It leans hard,
		--  turns quicker, accelerates harder and has less grip to lose —
		--  which is what makes it feel light rather than merely fast.
		--
		--  NOT FASTER OVERALL. Top speed is a touch higher and grip a
		--  touch lower, so it is quicker in a straight line and harder
		--  to hold through a corner. That is a trade, and a trade is
		--  what makes a second vehicle worth having; a strictly better
		--  one just deletes the first.
		--=============================================================
		bike = {
			name = "Motorcycle",
			-- Set this to a Model name in ServerStorage once real art
			-- exists and the placeholder below is never built again.
			visual = "Motorcycle",
			-- Until then, built in code. See BikeVisual.
			build = "bike",

			handling = {
				--=====================================================
				--  EVERY NUMBER HERE IS A NUDGE ON THE KART'S, and that
				--  is not modesty — it is the only safe way to set them.
				--
				--  Two were wrong by more than an order of magnitude
				--  because the UNIT was assumed rather than read:
				--
				--    Accel is an approach RATE (kart 3.4), not studs per
				--    second squared. At 78 it reached top speed in a
				--    single frame — one tap and you were flat out.
				--
				--    Grip is HOW FAST TRAVEL CATCHES THE NOSE (kart 9),
				--    not a 0-1 coefficient. At 0.82 the bike had a tenth
				--    of the kart's grip and slid through everything.
				--
				--  Read the kart's value out of Config.Handling first,
				--  then move it a few percent.
				--=====================================================

				-- Lighter and revvier. Slightly quicker to speed, and a
				-- slightly higher top end.
				MaxSpeed = 102, -- kart 95
				Accel = 3.9, -- kart 3.4

				-- TURNS HARDER AT LOW SPEED, LESS AT HIGH. A bike steers
				-- by leaning, and a leaned bike at speed is committed —
				-- so the gap between these is wider than the kart's.
				TurnRate = 3.0, -- kart 2.5
				TurnRateTop = 1.35, -- kart 1.6

				--=====================================================
				--  GRIP IS WHY IT CARVES INSTEAD OF SLIDING.
				--
				--    travel = travel:Lerp(forward, grip * dt)
				--
				--  so the slip held through a constant corner is roughly
				--  turnRate / grip:
				--
				--    kart @ top speed   1.6 / 9   = 10.2 deg
				--    bike @ 20          1.35 / 20 =  3.9 deg
				--    bike @ 20, slow    3.0  / 20 =  8.6 deg
				--
				--  A trace of slip is left on purpose so it still has
				--  weight and is not on rails.
				--
				--  DriftGrip IS overridden now — see below.
				--=====================================================
				Grip = 20, -- kart 9. Carving, not sliding.

				--=================================================
				--  A DRIFTING BIKE BANKS. IT DOES NOT SLIDE FLAT.
				--
				--  This used to inherit the kart's 2.9, which is a
				--  proper flat powerslide — 27 degrees of slip at
				--  speed and nearly 60 at low. On a machine whose
				--  whole appeal is the lean, that reads as the bike
				--  getting away from you rather than as commitment.
				--
				--  At 7 the rear still steps out, plainly, and the
				--  slide is less than half what it was:
				--
				--    DriftGrip   low speed   top speed
				--        2.9        59.3d       26.7d
				--        7          24.6d       11.0d
				--
				--  The drama it gives up is paid back as lean — see
				--  DriftLeanBonus, which is raised to match. Banking
				--  is the satisfying part; the sliding was only ever
				--  how a kart expresses the same commitment.
				--=================================================
				DriftGrip = 7, -- kart 2.9

				-- Matched to the kart so the wheels sit ON the road: the
				-- placeholder's tyres are modelled to touch at exactly
				-- this height.
				RideHeight = 1.4,

				--=====================================================
				--  THE WHEELIE, BY BOOST TIER.
				--
				--  Nothing on tier 1, a hint on tier 2, the full thing
				--  on tier 3. Earning it is the point — a wheelie on
				--  every small boost stops being an event by lap two.
				--
				--  VISUAL. Simulation rotates the art about the rear
				--  axle at the render write; the hitbox stays flat, so
				--  it cannot clear anything or change how the bike
				--  turns.
				--
				--  Capped at 30: past about a third of a turn the nose
				--  covers the corner you are steering into, which is the
				--  one way a purely visual effect can still cost a race.
				--=====================================================
				WheelieByTier = { 0, 11, 30 },
				WheelieAxle = 1.75, -- studs back — the rear axle
				-- Up fast, down slow. The slow return is most of what
				-- makes it satisfying; slamming level reads as the
				-- effect being switched off rather than ending.
				WheelieRise = 3.2,
				WheelieFall = 0.9,

				--=====================================================
				--  THE STOPPIE. Grab the brake and the tail comes up.
				--
				--  SMALLER THAN THE WHEELIE, on purpose. 30 degrees of
				--  nose-up is a trick you pulled off; 30 degrees of
				--  tail-up is a crash you are halfway through. 20 reads
				--  as a hard, deliberate stop and stays the right side
				--  of that line.
				--
				--  The axle matches WheelF in BikeVisual, at z = -2.05.
				--  It has to: pivot anywhere else and the front tyre
				--  either sinks into the road or lifts off it, which is
				--  the one way this can look wrong rather than absent.
				--=====================================================
				StoppieAngle = 22,
				StoppieAxle = 2.05, -- studs forward — the front axle
				--=====================================================
				--  THESE TWO ARE SET BY HOW FAST THE BIKE ACTUALLY
				--  STOPS, and getting that backwards made the first
				--  version almost invisible.
				--
				--  BrakeRate is 5.5, so a full stop from top speed is
				--  effectively over in about a third of a second — 93
				--  studs/s down to 15. Tuned like the wheelie (rise
				--  3.2, fade below a third of top speed) the tail only
				--  ever reached 5 degrees of the 20 it was asked for,
				--  because the target collapsed before the rotation
				--  could climb to it.
				--
				--  So the rise is TEN TIMES the wheelie's. That is not
				--  a fudge: a wheelie builds as power arrives, a brake
				--  bites the instant it is touched, and they should
				--  not share a rate any more than they share a pivot.
				--
				--  Measured with the real brake curve:
				--
				--    rise  3.2, at 0.34 ->  5.5 deg   invisible
				--    rise 22.0, at 0.20 -> 12.3 deg
				--    rise 30.0, at 0.12 -> 15.3 deg   <- here
				--=====================================================
				StoppieAt = 0.12,
				StoppieRise = 30,
				-- Down over about half a second, so the tail settles as
				-- the bike arrives at a standstill rather than dropping
				-- once it is already parked.
				StoppieFall = 4.5,
			},

			-- LEAN IS THE WHOLE LOOK. Applied by Rider on the body root,
			-- so it costs nothing in the simulation and cannot affect
			-- where the bike actually goes.
			lean = {
				RollScale = 3.2, -- multiplier on the kart's body roll
				MaxLean = 38, -- degrees, hard cap
			},

			-- Narrower and shorter than a kart. The hitbox is what the
			-- controller collides with, so this is the one visual-sounding
			-- number that is not cosmetic.
			hitboxSize = Vector3.new(2.2, 2.4, 5.6),

			--=====================================================
			--  ONE TRAIL, ON THE CENTRELINE. A BIKE HAS ONE REAR
			--  TYRE.
			--
			--  The default is a ribbon per rear corner, 2 studs out
			--  each side — correct for a kart and nonsense here: two
			--  parallel tyre marks four studs apart, laid by a
			--  vehicle with a single wheel between them, and neither
			--  of them under it.
			--
			--  `Back` moves it to the bike's own rear axle as well.
			--  The kart's 2.3 is behind this machine entirely, so the
			--  ribbon would start in mid-air past the tail.
			--=====================================================
			trails = {
				Xs = { 0 }, -- lateral multipliers on Effects.TrailInset
				Back = 1.75, -- studs back — WheelR in BikeVisual
			},

			-- HANDLEBARS, NOT A WHEEL. Without this the factory's helpful
			-- fallback builds a steering wheel for it, floating in the
			-- rider's lap — right for a kart, absurd for anything else.
			steeringWheel = false,

			-- A bike has no spoiler and no four wheels to rim. It gets
			-- its own slots rather than being handed the kart's and told
			-- to ignore half of them.
			slots = { "Body", "Rim", "Tire", "Exhaust", "Handlebar" },
		},
	},
}
