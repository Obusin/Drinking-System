--[[
	Bots — AI racers, so a lobby is never empty.

	THEY DRIVE THE SAME KART YOU DO
	-------------------------------
	A bot runs the same Simulation, reading its controls off the same
	table your keyboard fills in. It has no special physics, no hidden
	speed, and no ability to corner harder than the kart allows.

	That's the important bit. The usual way to make bots competitive is to
	cheat their handling, and it always shows: they hold lines no player
	can hold, and losing to one feels arbitrary. Here a bot can only be
	quick by driving well, and every mistake it makes is a mistake you
	could have made.

	SO HOW ARE THEY BEATABLE?
	-------------------------
	By being deliberately imperfect, not by being slowed down:

	  - they lift for corners, and how early is a per-bot trait
	  - they take a slightly wrong line, and drift off it over time
	  - they react to items on a human-ish delay
	  - they miss drift opportunities they "should" take

	Skill is one number per bot, rolled at spawn. It scales all of the
	above together, so a low-skill bot isn't a fast bot with a handicap —
	it's a worse driver.
--]]

return {
	--== FIELD =========================================================
	-- Filled up to this many RACERS in total, humans included. Three
	-- means solo practice is a four-kart race.
	-- Counts HUMANS TOO, so this is the size of the field and not the
	-- number of bots. Five means solo practice is you plus four bots, and
	-- a four-player lobby only gets one.
	FillTo = 5,
	MaxBots = 7, -- never more than the grid has slots for

	-- When a player crosses the line, the AI takes their kart over for
	-- the rest of the round.
	--
	-- Without it a finished racer's kart simply parks on the track and
	-- everyone still racing loses a rival — the field thins out exactly
	-- when the fight for the remaining places is at its most interesting.
	--
	-- It inherits the position and lap it had at the flag rather than
	-- starting fresh, so it carries on from where its driver left it
	-- instead of dropping to last.
	TakeOverOnFinish = true,

	--== IDLE  (rig test) ==============================================
	-- Parks the bots and just wags the wheel, so you can look at the
	-- driver: rig seated, hands on the wheel, arms following the
	-- steering. Nothing drives, nothing races.
	--
	-- Also drops the checkpoint requirement — a parked bot needs no
	-- racing line, and the whole point is to check the rig on a track
	-- that isn't finished.
	Idle = false,
	IdleSteerRate = 1.1, -- wags per second
	IdleSteerAmount = 1, -- 1 is lock to lock

	-- Every frame, and it has to be.
	--
	-- Their karts are unanchored so motion replicates smoothly, which
	-- means physics runs on them at 60Hz. Writing their CFrame at 30
	-- meant physics extrapolated them along their velocity for a frame
	-- and then got snapped back by the next write — visible as a flicker.
	-- Matching the physics rate makes each correction tiny.
	--
	-- The controller is frame-rate independent, so lowering this doesn't
	-- change how bots DRIVE. It trades smoothness for server cost, and
	-- smoothness is the thing you notice.
	StepRate = 60,

	--== SKILL =========================================================
	-- Rolled per bot at spawn, and scales everything below. Kept away
	-- from 1 at the top: a perfect bot is a boring one.
	SkillMin = 0.45,
	SkillMax = 0.92,

	--== DODGING A MISSILE =============================================
	-- Bots hop missiles too, or players work out inside one session that
	-- the dodge only ever works against AI — and a mechanic that applies
	-- to one half of the field is worse than no mechanic.
	--
	-- Scaled by skill, so a poor bot is genuinely easier to hit rather
	-- than uniformly lucky. The chance is rolled ONCE per missile, not
	-- per step: rolled per step at 60Hz it is a certainty, which this
	-- project has already paid to learn about nitro.
	DodgeChanceMin = 0.15, -- at SkillMin
	DodgeChanceMax = 0.75, -- at SkillMax
	-- NOTE: how close a missile has to be before its target is told
	-- lives in Config.Items as DodgeWarnRange. It is a fact about the
	-- projectile, and ProjectileService — which measures it — must not
	-- be reading bot config.

	--== CRUISE — the "I can't even chase it" dial =====================
	-- The speed a bot settles at on a straight, as a fraction of
	-- Handling.MaxSpeed. Worst-skill bot gets CruiseMin, best gets
	-- CruiseMax. THIS IS THE KNOB for how catchable they are.
	--
	-- It works as a LIFT, not as a reduced throttle, because Simulation
	-- reads throttle as a gate rather than a dial:
	--
	--     elseif throttle > 0.05 then target = H.MaxSpeed
	--
	-- Any throttle at all targets full speed, so scaling throttle down
	-- does nothing at all until it crosses 0.05 and then does everything.
	-- There is no middle, which is why "just make the bots use less
	-- throttle" cannot work. Above cruise they come off the power and
	-- coast; below it they get back on.
	--
	-- It limits the DRIVER, not the kart. Grip, top speed, turn rate and
	-- acceleration are identical to yours — a bot simply chooses not to
	-- use all of it, the same way it already lifts early for corners. So
	-- a bot still cannot do anything you couldn't, and you catch one by
	-- carrying more speed rather than by waiting for a handicap.
	--
	-- At MaxSpeed 95 these are about 65 and 76 studs/s, against your 95.
	-- Lowered once already: the first pass was too close to your own top
	-- speed to leave any closing rate worth the name.
	-- CALIBRATED AGAINST A LAP, not by feel.
	--
	-- 0.68-0.80 was a serious over-correction. On a 1500-stud lap it
	-- handed you 527 studs on an average bot EVERY LAP — a third of the
	-- circuit, before items. That is not a slow rival, it is no rival.
	--
	-- 0.92-1.00 puts the best bot level with your top speed and the worst
	-- 7.6 studs/s down, which is about 60 studs a lap: a kart is 7 studs
	-- long, so that is a gap you close over several corners rather than
	-- one straight.
	--
	-- The top of the band being 1.00 is deliberate and is NOT a cheat.
	-- The kart is identical to yours; a bot at full cruise is simply one
	-- that never lifts on a straight, which you can also do. It is beaten
	-- by carrying more speed through corners, using nitro better, and
	-- landing items — not by out-dragging it.
	CruiseMin = 0.92,
	CruiseMax = 1.00,

	-- Fraction of cruise below which full power comes back. Stops a bot
	-- chattering on the threshold; it settles into a speed instead.
	CruiseBand = 0.94,

	-- Drivers. NOTHING TO SET UP: without a model of this name in
	-- ServerStorage, Roblox builds a default R15 rig and that gets sat in
	-- the seat instead.
	--
	-- Requiring an authored rig was the wrong default — a rig you have to
	-- make is a rig that doesn't exist yet, and every failure to produce
	-- one looked like a bug in the seating rather than a missing asset.
	--
	-- Put a Model with a Humanoid here to dress them properly; "" for
	-- empty karts. Rider puts hands on the wheel either way, and doesn't
	-- care that the driver isn't a player.
	RigName = "BotRig",

	Names = {
		"Rusty",
		"Bolt",
		"Nitro",
		"Vex",
		"Dash",
		"Cinder",
		"Blitz",
	},

	--== DRIVING =======================================================
	-- How far up the racing line it aims. THE most important number
	-- here: too short and it saws at the wheel chasing a point it's
	-- almost on top of, too long and it cuts every corner.
	--
	-- Scaled by speed, because at 120 studs/s a fixed 20-stud lookahead
	-- is a sixth of a second of warning.
	--
	-- THIS WAS THE REMAINING SWERVE, and it is not a matter of taste.
	--
	-- Pure pursuit is stable only while the lookahead is comfortably
	-- LONGER than the distance the kart travels during its own control
	-- lag. Add up the lag: 0.19s of reaction, ~1/9s of SteerSlew, ~1/7s
	-- of the Simulation's SteerSmoothing — about 0.44s, which at 100
	-- studs/s is 44 studs of road. The old lookahead at that speed was
	-- 18 + 0.28*100 = 46 studs. Forty-six against forty-four: it sat
	-- exactly on the stability boundary, so it swerved down a straight
	-- and no gain anywhere else could have stopped it.
	--
	-- Measured, released 5 studs off a straight at 100 studs/s:
	--   lookahead  30 -> half-amplitude 50 studs, never settles
	--   lookahead  46 -> half-amplitude 30 studs, never settles  (old)
	--   lookahead  60 -> half-amplitude 16 studs, never settles
	--   lookahead  80 -> settles
	--   lookahead 108 -> settles                                 (now)
	--
	-- A long lookahead used to be unaffordable because chasing a distant
	-- point cuts every apex. FeedForward is what pays for it: the corner
	-- is handled by knowing its curvature, so the pursuit term is free to
	-- look far enough ahead to be stable. The two changes only work
	-- together.
	LookaheadBase = 18,
	LookaheadPerSpeed = 0.9, -- extra studs per stud/s of speed

	-- And a hard floor under all of it, in case the numbers above are
	-- edited without the lag being reconsidered. Total control lag in
	-- seconds, times the margin, times speed.
	ControlLag = 0.45, -- reaction + SteerSlew + Handling.SteerSmoothing
	LookaheadLagMargin = 2, -- below ~1.5 it starts to hunt again

	-- How much a corner SHORTENS the lookahead, 0..1. Kept small now:
	-- FeedForward is what actually stops apex-cutting, and shortening the
	-- lookahead is exactly how the swerve above was created. It can never
	-- reach below the lag floor.
	LookaheadTighten = 0.25,

	--== THE STEERING CONTROLLER =======================================
	-- Everything here works in CURVATURE (1/studs) and is converted to a
	-- steering input at the end using the kart's own numbers: yaw rate is
	-- steer*TurnRate, a path of curvature k at speed v needs k*v rad/s,
	-- so the lock is k*v/TurnRate. No fudge factor — it's the inverse of
	-- what the kart actually does.
	--
	-- WHY IT'S BUILT THIS WAY. The old controller steered proportional to
	-- the heading error toward a point up the road. A loop like that has
	-- to PRODUCE error to have anything to act on: it drifts off, hauls
	-- back, overshoots because nothing damps it, repeats. Add the 190ms
	-- reaction delay that used to sit inside the same loop and it is a
	-- textbook oscillator — delay plus gain plus no damping. That was the
	-- swerve, and it could not have been tuned out.

	-- FEED-FORWARD: steer the corner because it's there.
	--
	-- The most important number here. With it, a bot's inputs stop being
	-- apologies for errors it already made. On a straight it contributes
	-- exactly zero, which is why a straight is now quiet.
	--
	-- 1 is geometrically correct. Below 1 it under-turns and leans on
	-- feedback; above 1 it turns in early like someone being brave.
	FeedForward = 1,

	-- FEEDBACK: pure pursuit toward the aim point, as k = 2y/L² — the arc
	-- that actually passes through it. Only has to cover what
	-- feed-forward doesn't, so it stays small and can't dominate.
	PursuitGain = 0.9,

	-- Yaw damping: asks for a rotation rate and trims what it doesn't
	-- get. The term that was missing entirely, and the reason nothing
	-- ever settled — two position terms with nothing watching the RATE
	-- always cross the line rather than arrive at it.
	--
	-- Also quietly absorbs whatever the model doesn't know about: a
	-- drift, a bump, a kerb. It doesn't care why the kart isn't turning
	-- as asked, only that it isn't.
	--
	-- HONEST NOTE ON THE VALUE: in a kinematic sim of this controller,
	-- varying this from 0 to 0.5 moved tracking error by under a stud
	-- either way. It is NOT what fixed the swerve — feed-forward and
	-- moving the reaction delay off the feedback loop did that.
	--
	-- It's kept at a modest setting because its real job is rejecting
	-- what that sim doesn't model: a kerb, a bump, a drift, another kart.
	-- Raise it if bots feel vague after contact; there's no evidence here
	-- that raising it helps ordinary lap driving.
	YawDamp = 0.25,
	YawAuthority = 0.4, -- never more than this much lock, so one bad
	-- measurement can't throw the kart

	SteerMinSpeed = 25, -- floor on the speed used in the conversion. At a
	-- crawl the true answer is a huge lock, and a bot creeping out of a
	-- spin should not be at full opposite lock while it does

	LedgeRecover = 0.004, -- curvature per stud off-line when there's no
	-- road ahead. Deliberately blunt: this is the emergency path

	-- LineCorrect and LineDamp are GONE, not moved. They were a separate
	-- proportional-plus-derivative loop on cross-track error, sitting
	-- alongside another proportional loop on heading, with the two free
	-- to disagree. That's what a bot fighting its own racing line looks
	-- like from the outside.
	--
	-- There's one loop now. The aim point already carries the chosen line
	-- offset, so pure pursuit toward it corrects being off the line and
	-- follows the line with the same term — see FeedForward above.

	SteerSlew = 9, -- how fast its steering input can move. This is what
	-- stops a bot flicking to full lock instantly, which no human can do

	--== DRIVING LIKE A PERSON =========================================
	-- What makes a bot READ as a bot isn't its line, it's the input. A
	-- computed steering value is exact, instant and updated sixty times a
	-- second, and nothing alive drives like that.
	--
	-- None of this makes them slower. It makes the signal human-shaped:
	-- late, approximate, and corrected in bursts rather than continuously.

	-- Sees the world as it was this long ago. Human visual-motor lag is
	-- roughly 150-250ms and it's the single biggest tell — a bot with
	-- zero reaction time starts turning before a corner is visible.
	ReactionTime = 0.19,

	-- SteerDeadzone is GONE. It held the last steering input until the
	-- computed one differed by 0.07, which is hysteresis inside a
	-- feedback loop — a limit-cycle generator, and worse once the
	-- lookahead grew.
	--
	-- With a 108-stud lookahead the correct input for being five studs
	-- off the line is about 0.049, which is BELOW the 0.108 threshold a
	-- typical bot ended up with. So the correction was thrown away every
	-- frame and the bot drove parallel to the racing line forever,
	-- perfectly steadily, never coming back. Measured: settles 5.00 studs
	-- off with the deadzone, 0.00 without it.
	--
	-- The "doesn't micro-adjust" feel it was there for now comes from
	-- SteerSlew and SteerNoise, which shape the input without ever
	-- discarding information.

	-- Slow wandering error on top. Not noise per frame — that reads as a
	-- broken servo — but a drifting bias that has to be corrected for.
	SteerNoise = 0.06,
	SteerNoiseRate = 1.6,

	-- How much of that survives when the bot isn't doing anything.
	--
	-- It used to be all of it, unconditionally, which meant bots were
	-- told to weave down straight roads: a sine wave added to the output
	-- of a loop that then tried to correct it. Part of the swerve wasn't
	-- the controller failing, it was this working as written.
	--
	-- Nobody drifts about on a straight; they hold it, and get untidy
	-- through corners where the kart is moving around underneath them.
	NoiseOnStraight = 0.15,
	NoiseFullSteer = 0.5, -- steering input counted as "working hard"

	-- Throttle isn't a smooth function of anything for a human. They
	-- lift, reapply, and hold it slightly wrong the whole time.
	ThrottleJitter = 0.05,
	ThrottleJitterRate = 0.9,

	-- Corners. The bot measures how much the road bends between here and
	-- its lookahead point, and lifts off proportionally.
	CornerLookahead = 2.2, -- nodes ahead to measure the bend over
	CornerBrake = 0.85, -- how much of a sharp bend translates to lifting
	MinCornerSpeed = 0.42, -- never lifts below this fraction of top speed

	--== LINE ==========================================================
	-- Bots don't drive the centreline exactly; each holds an offset and
	-- wanders it. This is most of what makes them look driven rather
	-- than railed, and it's why they're overtakeable.
	-- HOW FAR APART BOTS SIT, as a fraction of the road available.
	--
	-- Was a stud count, clamped to the tarmac afterwards — so on a narrow
	-- section every bot's chosen line collapsed onto the same two edges
	-- and they drove through each other in a heap. They cannot actually
	-- collide, since a bot's hitbox is anchored, but a stack of
	-- overlapping karts reads as nothing else.
	--
	-- As a fraction the spread scales with whatever road there is: a
	-- tight section packs them closer rather than piling them up.
	--
	-- Under 1 so the outermost bot still has margin to the edge; the
	-- clamp is a backstop, not the thing choosing the line.
	LineSpread = 0.75,
	LineWander = 0.35, -- and the wander on top, same units

	-- LineOffset is GONE, not renamed. It was a stud count, and the line
	-- is chosen as a fraction of the road now (LineSpread / LineWander
	-- above). Leaving a plausible-looking studs value in here is how it
	-- got multiplied INTO the fraction by mistake — nine times too large,
	-- pinning every bot to an edge.
	LineDrift = 0.35, -- how fast the offset wanders

	-- Same fix as SteerNoise, one level up: the lateral TARGET used to
	-- wander unconditionally too, so bots were aiming at a weaving point
	-- even on a straight. A controller cannot refuse an instruction to
	-- swerve, however good it is.
	WanderOnStraight = 0.2,
	WanderFullBend = 0.3, -- bend counted as a proper corner

	-- Moving over for traffic. Karts pass through each other by design,
	-- but two on one line drive as a single overlapping lump, which reads
	-- as bumping even though nothing collides.
	AvoidRadius = 26, -- studs, and only counts karts AHEAD
	AvoidStrength = 11, -- studs of offset at closest range

	-- Studs a bot may drift from its grid slot before the server puts it
	-- back, while the match is NOT racing.
	--
	-- Hold() only stops a kart being driven; it does not stop a kart
	-- being moved by something else, and something else was moving them —
	-- bots wandered off the grid through the warm-up and the countdown.
	-- Rather than chase every possible nudge, the match asserts where a
	-- bot belongs between rounds.
	--
	-- Big enough that a kart settling onto the pad under gravity is left
	-- alone; small enough that leaving the slot is corrected immediately.
	GridHoldTolerance = 3,

	--== FLYING WATCHDOG ===============================================
	-- A NET, NOT A CURE. Bots occasionally take off and the cause is not
	-- known; this bounds the damage rather than pretending to fix it.
	--
	-- Both thresholds sit well beyond any legitimate jump, so a real ramp
	-- is never interrupted. When one trips, the log says which and how
	-- far the bot got — that is the evidence for diagnosing it properly.
	--
	-- Two tests, because they catch different failures. A long air time
	-- catches a slow floater that never comes down; height above the
	-- racing line catches one launched hard, which can be back on the
	-- ground quickly and a very long way up in between.
	MaxAirTime = 4, -- seconds off the ground before it is put back
	MaxAboveRoute = 60, -- studs above the racing line, same

	-- Studs of road to leave between the bot's chosen line and the edge.
	--
	-- LineOffset, the wander and AvoidStrength can add up to nearly thirty
	-- studs of sideways offset, and until the road had a measured width
	-- nothing stopped that landing off the track. A bot that rolled a
	-- positive bias drove off the right-hand side every single lap.
	--
	-- Raise it if bots still clip the edge; the room they're clamped to is
	-- the checkpoint volume's half-width minus this.
	EdgeMargin = 4,

	--== NOT DRIVING OFF THE EDGE ======================================
	-- The cached road widths describe the centreline, which is right
	-- until a bot gets knocked off, spun or respawned somewhere the line
	-- doesn't run. Then it's steering over ground nothing ever checked.
	--
	-- So it also looks where it's going: a ray under the point it's
	-- steering at, and one just ahead of its own nose.
	LedgeLook = 10, -- studs ahead of the nose to probe
	LedgeLookPerSpeed = 0.22, -- plus this much per stud/s. At speed you
	-- need to see further, for the same reason the lookahead scales
	LedgeThrottle = 0.35, -- throttle cap while there's nothing ahead.
	-- Allowed below MinCornerSpeed — that floor stops bots crawling round
	-- corners and must not stop one slowing for a drop
	LedgeHold = 0.4, -- seconds to stay in the correction after the ground
	-- comes back, so a bot skimming an edge doesn't flicker

	-- JUMPS. A gap is not automatically a mistake — tracks are built with
	-- ramps you're meant to take flat out, and the first version of the
	-- ledge check lifted to LedgeThrottle on the approach to every one of
	-- them. That is the single input guaranteed to turn a jump you'd have
	-- cleared into a fall. The bots were braking for the ramp.
	--
	-- The racing line settles it: the line is where the designer says to
	-- drive, so if the ROUTE carries on across the gap and there is road
	-- on the far side, this is a jump. Line up, stay on the power.
	JumpSpan = 1.2, -- node units past the aim point to look for landing
	JumpThrottle = 1, -- and commit. Overrides corner braking, which reads
	-- a ramp's approach as a bend

	--== NOT FIGHTING THE LINE =========================================
	-- LineDeadband is GONE too, and for a subtler reason than the others.
	--
	-- It zeroed the pursuit term when the aim point was nearly straight
	-- ahead. But in pure pursuit that quantity is not cross-track error —
	-- it mixes position and heading, and it goes to zero whenever the
	-- kart is POINTING at the target, including while running parallel to
	-- the line several studs off it. Deadbanding it therefore told the
	-- bot to ignore exactly the situation it most needed to fix, and
	-- measurably parked bots five studs wide of their own racing line.
	--
	-- Not being fussy about small errors is a real goal and it belongs on
	-- the input, not in the geometry. SteerSlew and SteerNoise do it.

	--== LEARNING FROM GOING OFF =======================================
	-- One number per checkpoint, up when the bot leaves the track there,
	-- decaying on a clean lap. High means drive this bit nearer the
	-- middle and slower.
	--
	-- Not clever, and doesn't need to be: a bot doesn't go off "in
	-- general", it goes off at turn four the same way every lap. One
	-- number attached to turn four fixes turn four.
	CautionMax = 4, -- ceiling, or a bad stretch eventually stops it dead
	CautionDecay = 0.5, -- shed per clean lap past that checkpoint
	CautionPull = 0.22, -- how much of the road width it gives up per point
	CautionLift = 0.12, -- throttle shed per point
	CautionLiftMax = 0.4, -- and never more than this in total

	--== DRIFTING ======================================================
	-- Drifts when the corner is sharp enough and it's quick enough to
	-- benefit, same as a player would.
	-- Drifts are PLANNED, not reacted to. The bot scans ahead for the
	-- sharpest bend, commits to it once, and holds the drift through the
	-- corner — rather than asking every frame whether the road under its
	-- wheels is bendy enough.
	--
	-- That difference is visible from across the track: a reactive bot
	-- always initiates a beat late and spends the exit straightening up,
	-- where a driver is already sideways on the way in.
	DriftScanAhead = 2.4, -- nodes to look for a corner worth drifting
	DriftEntry = 0.55, -- nodes BEFORE the corner to start, scaled by
	-- skill — a good driver commits earlier and carries more through
	DriftHold = 0.8, -- nodes past it to stay committed, so it doesn't
	-- unwind halfway round

	DriftBend = 0.32, -- bend required before it considers a drift
	DriftMinSpeed = 55,
	DriftChance = 0.85, -- rolled per corner, scaled by skill. A bot that
	-- takes every drift perfectly is one you can't out-drive

	--== NITRO =========================================================
	-- Spent on straights, which is where a player would. Waiting for a
	-- full three tanks is optimal and inhuman; they mostly don't.
	NitroStraight = 0.18, -- bend below this counts as a straight
	NitroMinTanks = 1,

	-- Odds PER SECOND of spending a tank once on a straight with one
	-- banked. Not per step — the old version rolled every frame, so a
	-- "40% chance to hold" was a 40% chance to hold for one seventy-fifth
	-- of a second and bots burned nitro the moment they had any.
	--
	-- That mattered more than any other number here, because a burn sets
	-- the speed target directly and so ignores the cruise cap completely:
	-- stage 1 is MaxSpeed + 18, stage 3 is MaxSpeed + 80. Permanent nitro
	-- is exactly "I can't chase them".
	--
	-- 0.3 means a bot on a long straight usually spends one within a few
	-- seconds, and often doesn't bother at all on a short one.
	-- Raised with the cruise band. Nitro is the only thing that takes a
	-- bot ABOVE its cruise, so it is where the pressure comes from — a
	-- rival that never boosts is one you pass once and never see again.
	-- At 0.55/s a bot spends one within a couple of seconds of reaching a
	-- straight with a tank banked.
	NitroUsePerSecond = 0.55,
	NitroCooldown = 4, -- seconds before it will consider another, so a bot
	-- can't chain three tanks down one straight

	--== ITEMS =========================================================
	-- Reaction time before using what it picks up. The single biggest
	-- lever on how nasty they feel.
	ItemDelayMin = 0.6,
	ItemDelayMax = 2.4,
	-- Odds it throws forward rather than dropping behind, when the item
	-- can do both. A bot in the lead defending is more interesting than
	-- one that always lobs everything up the road.
	ForwardChance = 0.65,

	-- WHAT THE COLOURS MEAN
	--
	--   blue balls    your checkpoints, dropped onto the road
	--   yellow trail  the spline between them. THIS is the path bots
	--                 follow — checkpoints are only the control points
	--   green pairs   the road edge, measured from your checkpoint
	--                 volumes. Bots are clamped inside these
	--   white line    where that bot is steering RIGHT NOW
	--   bar above     throttle. Red means it thinks it's cornering
	--
	-- READ THEM IN THIS ORDER, because each one only makes sense if the
	-- one before it is right:
	--
	-- 1. Does GREEN sit on the tarmac? If it's out in the scenery, a gate
	--    volume is wider than the road and bots will drive off there. If
	--    it's well inside the kerb, they'll drive a needlessly tight line.
	--    Nothing below matters until this is right — it's the box every
	--    bot is confined to.
	--
	-- 2. Does YELLOW stay on the road? If the spline itself cuts a corner,
	--    no amount of bot tuning helps: that's RouteTension, or more
	--    checkpoints on that bend.
	--
	-- 3. Does WHITE point somewhere sensible? If it aims across an apex,
	--    the lookahead is too long for that corner. If it saws side to
	--    side, that's PursuitGain or YawDamp. If it turns in too late for
	--    corners, that's FeedForward.
	--
	-- Cheap enough to leave on while testing; turn it off before anyone
	-- else plays, because everything it draws is a real part.
	Debug = false,
}
