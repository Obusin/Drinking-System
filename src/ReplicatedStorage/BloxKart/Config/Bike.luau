--[[
	Bike — how the motorcycle LOOKS. None of it moves the motorcycle.

	THE ONE RULE: MAKE IT LOOK HARDER TO CONTROL THAN IT IS.
	--------------------------------------------------------
	Every number here rides the body motor, the rider's joints or the
	camera. `Simulation` never reads any of it, so a bike leaning 40
	degrees through a corner is going exactly where an upright one would.
	The drama is free, and being free is what lets it be this loud.

	That is also the acceptance test for anything added later. If a change
	makes the bike harder to place, twitchier, or more tiring to hold on
	line, it has crossed from visual into mechanical and it is wrong —
	however good it looks in a clip.

	WHAT IT MUST NEVER DO
	---------------------
	  - wobble when nothing caused it
	  - fall over, or need balancing
	  - fight the player at low speed, in the lobby or on the grid
	  - shake constantly at speed
	  - punish an imperfect landing

	Realism is not a goal anywhere in this file. Legibility is.
--]]

return {
	--== LEAN, WHICH IS THE WHOLE LOOK =================================
	-- Scaled by BOTH steering and speed, because leaning hard while
	-- crawling is what makes a bike look broken rather than fast.
	--
	-- ANCHORED ON TWO SPEEDS, not scaled by one. The first version
	-- multiplied by the speed fraction twice and the bike barely leaned
	-- until nearly flat out — 2 degrees at 25 studs/s where the brief
	-- asks for 5-12, and 14 at 60 where it asks for 15-28.
	--
	-- Measured against the brief:
	--
	--=================================================================
	--  GRAND PRIX ANGLES. A MotoGP bike corners at 55-64 degrees; this
	--  was topping out at 36 plus bank, which is a fast road bike.
	--
	--  THESE ARE THE ANGLES BEFORE BANKING. `BankOnTurn` adds up to 30%
	--  on top, so the number that actually appears in a corner is
	--  LeanHigh * 1.3 — and that is what LeanMax has to be set against,
	--  not LeanHigh itself:
	--
	--    42 * 1.3            = 55   a committed fast corner
	--    + DriftLeanBonus 8  = 63   clamped to LeanMax
	--
	--  So the cap only bites in a powerslide, and ordinary cornering
	--  keeps its full range of expression. Setting LeanHigh to the cap
	--  instead pins the bike at maximum lean through every fast corner
	--  and throws away the gradation between a quick one and a slow one.
	--
	--   25 studs/s   17 deg (with bank)
	--   40           27
	--   55           37
	--   75           49
	--  102           55
	--=================================================================
	LeanLow = 13, -- degrees at full lock, at LeanLowAt
	LeanHigh = 42, -- and at LeanHighAt
	LeanLowAt = 0.22, -- fraction of top speed
	LeanHighAt = 0.90,

	--=================================================================
	--  LEAN ABOUT THE CONTACT PATCH, NOT THE CHASSIS.
	--
	--  THIS IS WHAT MAKES A BIG ANGLE LOOK RIGHT, and without it no
	--  amount of extra degrees reads as a motorcycle.
	--
	--  Rotating about the body root swings the whole bike sideways out
	--  of its own wheels — at 20 degrees you barely notice, at 55 the
	--  chassis is somewhere beside the tyres and it reads as the model
	--  falling over rather than leaning. A real bike pivots about the
	--  line where its tyres meet the road: the contact patch stays put
	--  and the machine arcs over it.
	--
	--  Studs BELOW the body motor's origin. Derive it for new art as
	--
	--      -(RideHeight + bodyRootHeightAboveHitboxCentre)
	--
	--  which for the placeholder is -(1.4 + 0.15) = -1.55.
	--=================================================================
	LeanPivot = -1.55,

	--== BANKING =======================================================
	-- The lean also answers to the turn ACTUALLY HAPPENING, not only to
	-- the stick.
	--
	-- Input alone banks the instant the key goes down — before the bike
	-- has started turning — so the lean leads the corner rather than
	-- belonging to it, and a stab of steering that changes nothing still
	-- throws the bike over. Yaw rate builds the bank AS it comes round
	-- and holds it while it is round, which is what makes a long corner
	-- read as carved rather than merely entered.
	-- TURNED DOWN with the stiffer spring. Yaw rate is by definition
	-- late — it can only report a turn that is already happening — so
	-- with the lean now leading on intent this is the seasoning rather
	-- than the dish. Too much of it puts the lag straight back.
	BankOnTurn = 0.3, -- share of the lean the real turn contributes
	BankFullYaw = 2.2, -- rad/s treated as turning as hard as it can

	-- A SPRING, NOT A LERP, and deliberately a little under-damped.
	--
	-- The overshoot is what makes a chicane read as the bike being THROWN
	-- from side to side rather than rotated: it arrives, tips slightly
	-- past, and settles. A lerp cannot do that at any rate.
	--
	-- It also solves the "40 left to 40 right" problem for free — a
	-- spring has to travel through zero, so the bike stands up through the
	-- middle of a direction change without anything detecting one.
	--
	-- Damping is a RATE tied to stiffness, 2*sqrt(k)*zeta, the same form
	-- the suspension and the sea use.
	--
	-- STIFF, BECAUSE THE LEAN WAS ARRIVING AFTER THE CORNER.
	--
	-- Measured: at k=46 the lean settled in 0.63s, and it was chasing
	-- `sim.steer`, which is itself smoothed at SteerSmoothing 7 and
	-- takes 0.43s to reach the input. A full second to lean, against a
	-- 90-degree low-speed turn that takes 0.52s — the corner finished
	-- before the bike got there, so the bike changed heading while still
	-- upright. That is exactly what reads as sliding.
	--
	-- Now: chases the RAW intent (no 0.43s) and settles in 0.29s, so the
	-- lean arrives while the corner is still happening. A real bike leans
	-- BEFORE it turns, so leading is also the correct direction to err.
	LeanSpring = 260,
	LeanDamp = 21, -- 2*sqrt(260)*0.65 — commits hard, one soft overshoot
	-- The whole-bike pose uses a gentler spring than the visual helper
	-- above. It takes the edge off instant direction changes without
	-- making the motorcycle arrive after the corner.
	WholeLeanSpring = 105,
	WholeLeanDamp = 17, -- lightly under-damped: one small, natural settle
	-- Hard ceiling. Past this it reads as fallen over rather than leaning.
	-- 60 is about where a real one highsides, and with the pivot at the
	-- contact patch the bike still looks planted here rather than dropped.
	LeanMax = 60,

	--== THE RIDER =====================================================
	-- Fractions of the bike's lean. The head lags the torso on purpose:
	-- a rider whose head stays nearer level looks like they are LOOKING
	-- where they are going, and that tiny counterbalance is most of what
	-- separates a person riding from a mannequin bolted on.
	--=================================================================
	--  THE RIDER LEANS MORE THAN THE BIKE, NOT LESS.
	--
	--  This was 0.88, which held the rider 12% MORE UPRIGHT than the
	--  machine — the classic counter-lean, and the exact posture a sport
	--  rider is taught out of. It also fights the knee directly: you
	--  cannot get a knee down while sitting up off the inside of the
	--  bike, because the knee is reaching from a body leaning the other
	--  way.
	--
	--  Past 1 the body hangs INSIDE the bike's line, which is what every
	--  photograph of this actually looks like.
	--=================================================================
	RiderLean = 1.14,
	-- The rider follows most of the frame's bank, but not all of it. The
	-- remaining fraction is applied as a delayed counter-pose at the seat,
	-- keeping their upper body composed rather than welded to the bike.
	RiderFollowRate = 7,
	-- Rider posture, in the bike's local frame. The seat moves the whole
	-- character slightly toward the tank; the hand targets and elbow poles
	-- then make the arms bend naturally instead of reaching dead straight.
	RiderSeatForward = 0.26,
	RiderSeatDrop = 0.10,
	RiderForwardPitch = 9, -- degrees forward at a full tuck
	-- HANGING OFF, so this is a good deal more than a shuffle. The hips
	-- come right off the inside of the seat; without it the knee reaches
	-- down from a body still centred on the bike, which reads as a
	-- dropped leg rather than as a rider committed to a corner.
	RiderHipShift = 0.55, -- toward the inside of the corner, in studs
	RiderArmForward = 0.38,
	RiderArmDrop = 0.16,
	RiderElbowOut = 0.28,
	RiderElbowForward = 0.22,
	RiderHeadLean = 0.45,
	-- Shoulders shift toward the inside of the corner, in studs.
	RiderShift = 0.35,
	RiderRate = 12, -- how fast the body follows the bike

	--== HANDLEBARS AND THE FRONT WHEEL ================================
	-- LESS STEERING ANGLE AT SPEED, not more.
	--
	-- A real bike turns by leaning; the bars barely move. Showing full
	-- lock at 100 studs/s reads as a bicycle being wrestled, so the
	-- visible angle SHRINKS as the lean takes over the job.
	BarTurnLow = 26, -- degrees at full lock, low speed
	BarTurnHigh = 7, -- and at top speed
	BarRate = 14,
	-- A brief opposite-lock flick at turn-in. It is driven from the
	-- already-smoothed steering change, so holding a turn does not leave
	-- the bars counter-steered; only the entry gets the motorcycle cue.
	CounterSteerKick = 11, -- degrees at a sharp direction change
	CounterSteerFullRate = 5.5, -- steer units per second for full kick
	-- Placeholder bars face the opposite local direction to the kart's
	-- steering-wheel art. Keep this separate from Rider.InvertWheel,
	-- which is for a steering wheel rather than a steering head.
	InvertHandlebar = true,
	-- The front wheel follows the bars, so it gets the same treatment —
	-- expressed as a fraction of the kart's steering throw.
	WheelSteerLow = 1.0,
	WheelSteerHigh = 0.35,

	--== WEIGHT TRANSFER ===============================================
	-- Subtle on purpose. The player should FEEL the weight move without
	-- the horizon doing anything they have to think about.
	PitchOnPower = 3.5, -- degrees nose-up under acceleration
	PitchOnBrake = 4.5, -- and nose-down braking, slightly more
	PitchRate = 7,
	-- Fork travel, in studs. Reads as the front loading and unloading.
	ForkDive = 0.28,

	--== NITRO =========================================================
	-- "Holy shit this thing MOVES", with nothing actually changing about
	-- where it goes.
	TuckRate = 8, -- how fast the rider folds down
	TuckPitch = 14, -- degrees the rider's torso comes forward
	TuckDrop = 0.45, -- studs the head comes down
	BoostPitch = 7, -- degrees the BIKE pitches back
	-- A VISUAL front lift. Not a wheelie: the hitbox never moves, so this
	-- cannot become a handling change or a way to clear something.
	BoostLift = 0.55, -- studs the front rises
	BoostLiftRate = 6,

	--== DRIFT =========================================================
	-- A bike does not slide flat like a kart. The REAR steps out while
	-- the nose keeps pointing at the exit, which is what makes a
	-- powerslide read as controlled rather than as a crash in progress.
	-- WHERE A TURN STOPS BEING A TURN AND BECOMES A SLIDE.
	--
	-- With Grip at 20 a normal corner holds roughly 4 degrees of slip and
	-- a real powerslide holds many times that, so the two states separate
	-- cleanly on the slip angle alone — no flag, and nothing to keep in
	-- step with the simulation's own idea of drifting.
	--
	-- Everything that makes the bike LOOK like it is sliding hangs off
	-- this: below SlipIgnore the rear does not step out and the extra
	-- lean does not appear, so a planted corner can never be dressed up
	-- as a drift.
	--=================================================================
	--  RETUNED TO THE NEW DRIFT, AND ONE OF THEM WAS ALREADY WRONG.
	--
	--  SlipIgnore was 0.14 rad — 8.0 degrees — and claimed to sit above
	--  ordinary cornering. It did not: a full-lock corner at low speed
	--  holds turnRate/grip = 3.0/20 = 8.6 degrees, so every tight slow
	--  corner was already tripping the drift visuals while the bike was
	--  fully gripping. Smoke off a planted tyre, which is the one thing
	--  this gate exists to prevent.
	--
	--  With DriftGrip at 7 the two states now sit either side of a
	--  cleaner line:
	--
	--    normal, worst case (low speed, full lock)    8.6 deg
	--    SlipIgnore                                  10.0 deg
	--    drift at top speed                          11.0 deg
	--    SlipFull                                    18.3 deg
	--    drift at low speed                          24.6 deg
	--
	--  So gripping never trips it at any speed, and a drift always
	--  does.
	--=================================================================
	SlipIgnore = 0.175, -- radians (10 deg). Above the WORST normal corner.
	SlipFull = 0.32, -- (~18 deg) a committed powerslide

	-- THE DRIFT IS EXPRESSED AS BANK, NOT AS ANGLE.
	--
	-- With DriftGrip at 7 the bike gives up more than half its slide,
	-- and that drama has to come back somewhere. Lean is where it goes,
	-- because leaning is the part worth watching on a motorcycle —
	-- pointing sideways is how a KART shows the same commitment.
	--
	--   55 studs/s   34.6 -> 44.7
	--   75           45.5 -> 58.8
	--  102           54.6 -> clamped at 60
	DriftLeanBonus = 16, -- extra degrees of lean, on top of the corner's
	-- CUT HARD, and this is the other half of "make it look like
	-- banking". Yawing the body is precisely the sideways look the lean
	-- is supposed to replace: at 13 degrees the bike was still turning
	-- itself across the corner and the extra bank was competing with it
	-- rather than reading. A trace is kept so the rear still visibly
	-- steps out — it just no longer dominates the silhouette.
	DriftRearYaw = 5, -- degrees the BODY yaws, nose held toward the exit
	DriftYawRate = 9,
	DriftRiderTuck = 0.35, -- the rider commits further in

	--== KNEE DOWN =====================================================
	-- THE SINGLE MOST RECOGNISABLE THING A MOTORCYCLE RIDER DOES.
	--
	-- The INSIDE leg comes off the peg, the knee swings out and down
	-- toward the road, and it reads instantly as committed cornering
	-- from any camera angle — which is more than the lean itself manages,
	-- because a lean seen from directly behind is mostly foreshortened.
	--
	-- WHICH LEG IS DECIDED BY THE SIGN OF THE LEAN, so it swaps itself
	-- through a chicane with nothing to detect the change: the leg that
	-- is on the inside is the one whose side matches the way the bike has
	-- fallen. The other leg is left entirely alone on its peg.
	--
	-- GATED ON LEAN, BONUSED ON DRIFT. A knee out at walking pace with
	-- the bike upright is a rider dangling a leg, not a racer — so it
	-- only starts once the machine is genuinely over. A powerslide then
	-- pushes it the rest of the way out, which is where the real ones go.
	--=================================================================
	--  SET AGAINST THE LEAN THE BIKE ACTUALLY REACHES.
	--
	--  These were 22 and 52, and the bike does not corner anywhere near
	--  52 — the lean tops out at 42 and spends almost the whole race
	--  under 30. So the gate opened at a speed most corners never see
	--  and the IK weight sat at zero: the legs simply never moved.
	--
	--    studs/s   lean   old 22/52   new 8/32
	--         25   14.1        0%        25%
	--         40   20.3        0%        51%
	--         55   26.6       15%        78%
	--         75   35.0       43%       100%
	--
	--  8 is still above anything a straight produces, so the legs stay
	--  on the pegs when the bike is upright — which is the only thing
	--  the lower gate had to protect.
	--=================================================================
	KneeAt = 8, -- degrees of lean before the knee starts to move
	KneeFull = 32, -- and where it is all the way out
	-- Extra 0..1 of extension a full drift adds on top of the lean's, so
	-- a slide at a given angle always reads as more committed than a
	-- grip corner at the same angle.
	KneeDriftBonus = 0.35,

	--=================================================================
	--  STEERING ALONE PUTS THE KNEE OUT, WITH NO SPEED AT ALL.
	--
	--  Everything above is gated on LEAN, and lean is gated on speed —
	--  so a stationary bike on full lock did nothing, which makes the
	--  whole effect impossible to look at while tuning it.
	--
	--  It is not only a testing affordance. Every low-speed photograph
	--  of this — the underbone riders picking their way round a
	--  mountain hairpin — is a knee out at a speed where the machine is
	--  barely leaning at all. The leg goes out because the rider
	--  DECIDED to, and the decision is the steering input, not the
	--  physics.
	--
	--  Fraction of full extension that full lock produces on its own.
	--  Deliberately not 1: a knee fully down while stopped is a rider
	--  who has fallen off, and the lean still has to earn the rest.
	--=================================================================
	KneeFromSteer = 0.55,

	--=================================================================
	--  THE STANDSTILL POSE. A boot down, holding the bike up.
	--
	--  Same shape as the cornering knee, kept on whichever side the
	--  rider last steered toward. A stopped motorcycle with both feet
	--  neatly on the pegs is the one thing it must not look like —
	--  nothing would be holding it upright.
	--
	--  Under the full cornering extension on purpose: this is a foot
	--  down at a light, not a knee on the tarmac.
	--=================================================================
	KneeIdle = 0.6, -- fraction of full extension while stopped
	KneeIdleBelow = 0.05, -- fraction of top speed that counts as stopped

	--=================================================================
	--  THE BOOT NEVER LEAVES THE PEG. NOT EVEN STOPPED.
	--
	--  Reaching for the ground was tried and it cannot be made safe:
	--  Roblox avatars are scaled per player, and a ground target sits
	--  about 1.99 studs from the hip against roughly 2.40 studs of
	--  default-scale leg. A 0.7-scale character has 1.68 and simply
	--  cannot get there — so it stretches, or the IKControl gives up
	--  and stops solving, and which of those you get depends on who
	--  joined the server.
	--
	--  The peg is 1.09 studs away, which every scale clears with room
	--  to spare. So the idle pose is the same knee-out on the peg, and
	--  it only has to LOOK like a rider holding the bike up — which it
	--  does, because a leg swung out reads that way whether or not the
	--  boot is touching anything.
	--
	--  This is the general rule for anything IK on a player character:
	--  target things bolted to the VEHICLE, never to the world, because
	--  the vehicle is the only one of the two whose distance from the
	--  rider you control.
	--=================================================================

	--=================================================================
	--  THE KNEE ITSELF, NOT THE FOOT.
	--
	--  These are where the KNEE goes, because the IK now solves to the
	--  lower leg rather than the foot. Solving to the foot gave the
	--  chain two joints for one point and left the ankle unconstrained,
	--  so the foot arrived in whatever orientation fell out of the solve
	--  — the feet flapping about. One bone, one job: the hip aims the
	--  thigh and everything below keeps the animation's own pose.
	--
	--  BOTH TARGETS MUST SIT NEAR THE THIGH'S LENGTH (~1.2 studs). A
	--  single-bone solve can only rotate; it cannot lengthen. A target
	--  much nearer or further does not move the knee more, it just aims
	--  the same bone at a point it will never occupy, and the leg reads
	--  as detached from the hip.
	--
	--    peg (seated)   out 0.55  down 0.60  fwd 0.70   radius 1.07
	--    knee out       out 1.15  down 0.30  fwd 0.30   radius 1.23
	--
	--  OUT IS DOWN once leaned, which is the whole reason one lateral
	--  number is enough and nothing here has to find the road:
	--
	--    lean  0   knee 0.30 below the seat
	--    lean 27        0.79
	--    lean 42        0.99
	--    lean 50        1.07
	--
	--  It deliberately stops short of the tarmac now. Aiming the KNEE at
	--  the road put it through the road, because unlike the foot the
	--  knee is not the end of the limb — there is a shin and a boot
	--  hanging below it.
	--=================================================================
	--  SIDEWAYS, NOT FORWARD. Measured as the pole's angle around the
	--  hip-to-foot axis, where 0 is dead ahead and 90 is pure side:
	--
	--    1.15 / 0.30 / 0.30   ->  69 deg   knee reads as pushed forward
	--    1.60 / 0.35 / 0.05   ->  91 deg   <- here, straight out the side
	--
	--  Cheap to push, because this is a POLE and not a reach target. It
	--  only names the plane the knee bends in, so moving it further out
	--  costs nothing and can never pull the foot off the peg.
	KneeOut = 1.6, -- studs from the centreline at full extension
	KneeDrop = 0.35, -- studs below the seat
	KneeForward = 0.05, -- studs ahead of the seat

	-- Where the knees sit when not extended: the seated pose, thighs
	-- forward and slightly apart. Relative to the seat, so they do not
	-- have to be re-derived when the rider moves.
	PegOut = 0.55,
	PegDrop = 0.60,
	PegForward = 0.70,

	--=================================================================
	--  THE FOOT NEVER MOVES. IT IS STANDING ON THE PEG.
	--
	--  This is the whole trick, and it is why the idle pose already
	--  looked right: a planted foot reads as weight going through the
	--  leg. So the foot is PINNED here and only the knee travels —
	--  which is exactly what a rider does, because their boot is on a
	--  peg bolted to the motorcycle and it is not going anywhere.
	--
	--  The bend is then a CONSEQUENCE rather than something posed. As
	--  the knee swings out from a fixed foot the angle between thigh
	--  and shin has to close, so the leg tucks up on its own:
	--
	--    seated     bend 101 deg
	--    knee out   bend 108 deg
	--
	--  Interpolating the foot as well, which the first cut did, spent
	--  effort making the foot drift 0.03 studs and got a leg that
	--  looked unanchored for it.
	--
	--  ONLY THE DIRECTION MATTERS to the solve. Each control is a
	--  single bone, and a bone cannot lengthen — it rotates to point at
	--  the target. So this need not sit exactly a shin's length away.
	--
	--  `BikeVisual` builds the actual peg parts from these same three
	--  numbers, so the boot always lands on something visible.
	--=================================================================
	FootPegOut = 0.62, -- studs from the centreline
	FootPegDrop = 1.05, -- studs below the seat
	FootPegForward = 0.1, -- studs ahead of the seat
	KneeRate = 7, -- how fast it extends and comes back, per second
	-- FULL WEIGHT. Under 1 blends with the seated animation, which is
	-- nicer in principle and was competing with an animation that holds
	-- the legs firmly — at 0.85 the pose won only three-quarters of an
	-- argument it needed to win outright to be visible at all.
	KneeWeight = 1,
	KneeSmoothTime = 0.08,

	--== TYRE SMOKE ====================================================
	-- SMOKE, NOT SPARKS, and that is the whole point of having it.
	--
	-- Sparks read as something hard scraping the road — right for a kart
	-- dragging its floor pan, wrong for a bike, which has nothing down
	-- there but rubber. Smoke reads as a tyre being overworked, and it is
	-- most of what separates the two machines at a glance.
	--
	-- REAR ONLY. The front tyre of a bike that is still upright is doing
	-- its job; smoke from it means you have already crashed.
	--
	-- Driven by the SAME `sliding` 0..1 the rear step-out uses, so the
	-- smoke and the yaw can never disagree about whether this is a drift.
	-- Below SlipIgnore there is none at all — a planted corner must never
	-- be dressed up as a slide, and a permanent haze is exactly that.
	-- ONLY HOW MUCH. Lifetime, size, colour, drift and spread live on the
	-- emitter itself, which is part of the ART — the same split the splash
	-- and thruster effects use, where the authored Rate is read off the
	-- emitter rather than dictated here. Real bike art can restyle its own
	-- smoke completely without touching Config, and duplicating those
	-- properties here would only create a second copy to disagree with.
	SmokeRate = 85, -- particles/sec at full slip
	-- Scales with speed as well as slip: a slow pirouette in the pits
	-- should not produce the same cloud as a 90 studs/s powerslide.
	SmokePaceFloor = 0.25, -- fraction of the rate that survives at a crawl

	--== THINGS THAT HIT IT ============================================
	-- ONE WOBBLE CHANNEL, decaying, fed by landings, bad landings and
	-- impacts. Several sources, one amplitude, one decay — two wobble
	-- timers end up fighting over the same angle and the loser is
	-- whichever ran second.
	--
	-- IT ONLY EVER FIRES BECAUSE SOMETHING HAPPENED. There is no idle
	-- wobble, no balance, and nothing that oscillates on its own: an
	-- unexplained wobble is indistinguishable from the bike being broken.
	WobbleDecay = 5.5, -- per second
	WobbleSpeed = 19, -- oscillations per second
	WobbleMax = 16, -- degrees, ceiling
	-- What each event contributes.
	WobbleOnLand = 3.5, -- per 100 studs/s of impact
	WobbleOnBadLand = 7, -- landing while still yawed
	WobbleOnBump = 9, -- glancing a wall
	WobbleOnHit = 14, -- a real impact

	-- The fishtail that goes with it: the rear steps out briefly and
	-- comes back. Short, because a long one is a punishment.
	FishtailPerWobble = 0.9, -- degrees of yaw per degree of wobble
	FishtailDecay = 7,

	--== LANDINGS ======================================================
	-- Punchier than the kart, and over quickly. The player must be able
	-- to land and immediately keep racing — a recovery animation that
	-- outlasts the landing is a recovery animation that costs a corner.
	LandDip = 0.55, -- studs the body compresses
	LandDipRate = 22, -- down fast
	LandRiseRate = 8, -- up slower, so it reads as a rebound

	--== SPEED, AND FEELING IT =========================================
	-- A tiny high-frequency shiver at the top end. DELIBERATELY ALMOST
	-- INVISIBLE: this is the one effect that turns into motion sickness
	-- if it is loud enough to notice consciously.
	ShiverAt = 0.75, -- fraction of top speed before it starts
	Shiver = 0.35, -- degrees at full speed
	ShiverSpeed = 34,
	-- The rider tucks a little at speed even without nitro.
	SpeedTuck = 0.45, -- fraction of a full nitro tuck, at top speed

	--== IDLE ==========================================================
	-- Stopped, it must look ALIVE and STABLE. Anything that reads as
	-- balancing reads as about to fall over.
	IdleBob = 0.035, -- studs
	IdleBobSpeed = 9,

	--== CAMERA ========================================================
	-- Closer, lower, and hungrier for the road ahead than the kart's.
	-- PULLED BACK from -1.6. Angular flow scales with 1/distance, so a
	-- closer camera makes every degree of turning sweep further across
	-- the screen — the closeness was quietly amplifying the roll rather
	-- than being a separate choice.
	CamDistance = -0.9, -- studs, relative to the kart camera
	CamHeight = -0.6,
	CamLookAhead = 4,
	-- THE HORIZON BARELY MOVES. The bike can lean 40 degrees; the camera
	-- rolls a handful. Watching a bike lean is exciting, being rolled
	-- with it is nauseating, and the difference is the whole reason this
	-- number is small.
	--
	-- HALVED, AND SLOWED. It was 0.09 / 4.5 / rate 6 and it made people
	-- queasy through corners.
	--
	-- The number that actually causes that is not the ANGLE, it is the
	-- angular SPEED — a horizon that swims. At the old settings a hard
	-- corner rolled the view at up to 19 degrees a second; now it peaks
	-- near 6, which is present without being trackable.
	--
	--     share   cap   roll@36   rate   peak deg/s
	--     0.090   4.5     3.2       6       19.4     <- queasy
	--     0.045   2.2     1.6       4        6.5     <- here
	--
	-- Slowing the RATE is doing as much work as shrinking the angle, and
	-- it costs nothing visually: a roll that eases in still reads as the
	-- camera acknowledging the lean.
	-- LOOK OVER A WHEELIE. A 30-degree nose-up covers a chunk of the
	-- screen, and it is the part you are steering into — the one way a
	-- purely visual effect can still cost a race. Raising the eye is
	-- cheaper than shrinking the trick.
	WheelieCamAt = 30, -- degrees of wheelie that earns the full rise
	WheelieCamRise = 2.4, -- studs

	CamRollShare = 0.045, -- fraction of the lean the camera takes
	CamRollMax = 2.2, -- degrees, hard ceiling
	CamRollRate = 4,
}
