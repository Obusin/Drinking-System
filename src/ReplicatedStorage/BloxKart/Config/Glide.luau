--[[
	Glide — wings out, off a ramp, across a gap.

	MARIO KART'S GLIDER IS NOT ON RAILS, and understanding why is the
	whole design. Nintendo gives you very little air authority for a very
	short time, so the set of places you can reach is smaller than the
	landing zone. They do not fence you in — they make the fence
	unnecessary. A bad line costs you time, never the race.

	THAT DOES NOT PORT DIRECTLY, AND HERE IS THE ARITHMETIC.
	-------------------------------------------------------
	A constant turn rate is a circular arc of radius v/w, so drift off the
	ideal line after time T is R*(1 - cos(wT)). At 80 studs/s:

	      turn      1.5s    2.5s    4.0s
	      5 deg/s      8      22      55   studs off-line
	      8 deg/s     13      35      87
	     12 deg/s     19      51     126
	     20 deg/s     31      82     189

	A track here is 40-60 studs wide. Twelve degrees a second over a
	two-and-a-half second glide is already off the road. Mario Kart's
	karts are slower relative to their track width than ours are; copying
	their numbers would put players in the void.

	SO THERE IS A CORRIDOR.
	-----------------------
	Inside CorridorHalf of the line from ramp to landing zone you have
	full control and feel nothing. Outside it, a yaw nudge pushes you back,
	scaled by how far out you are.

	The player never notices the correction because it only exists where
	they were already going wrong, and it is a NUDGE ON THE NOSE rather
	than a shove on the position — so the kart turns back like it was
	flown back, not like it hit glass. An invisible wall reads as a bug;
	this reads as the wings biting.

	NOTHING HERE TOUCHES THE GROUND GAME. Glide is a state the kart enters
	and leaves; the Hitbox and the Seat are still the only things the
	controller reads, and the wings that appear are cosmetic like the
	wheels are.
--]]

return {
	Enabled = true,

	--== THE WORLD ====================================================
	-- Tag a part with this and driving over it launches you. The PART'S
	-- OWN ORIENTATION is the launch direction, the same trick the arc
	-- tool uses — so a ramp is aimed in Studio by rotating it, not by
	-- typing numbers into a config nobody can see from the viewport.
	RampTag = "GlideRamp",

	-- Tag the place you are meant to come down. The nearest one AHEAD of
	-- the ramp becomes the corridor's far end.
	--
	-- Optional: with no landing zone there is no corridor and the glide
	-- is free flight, which is the Mario Kart behaviour and fine for a
	-- short hop across a gap you cannot miss.
	LandTag = "GlideLand",

	--== THE LAUNCH ===================================================
	-- Below this you are not going fast enough to fly, and the ramp is
	-- just a bump. Stops a kart that rolled onto it backwards from
	-- getting a free flight.
	MinSpeed = 34,

	-- Studs/s of upward kick, along the RAMP's up rather than the world's,
	-- so a ramp on a banked section throws you along the bank.
	LaunchUp = 46,

	-- MINIMUM TIME IN THE AIR BEFORE A GLIDE MAY END, exactly like the
	-- drift hop's HopMinAir and for exactly the same reason.
	--
	-- The launch kick lifts the kart 0.77 studs in one frame, which is
	-- well inside GroundSnap. So the frame after launching it was still
	-- `grounded`, the glide ended immediately, the ramp was still
	-- underneath, and it launched again — a loop that re-boosted every
	-- other frame and left the wings permanently out because `Gliding`
	-- was being set back to true as fast as it was cleared.
	MinAirTime = 0.35,

	-- Multiplies the speed you arrived with. Slightly over 1 so a glide
	-- rewards arriving fast, which is what makes people take the ramp
	-- properly rather than trickling onto it.
	LaunchSpeedScale = 1.05,

	--== THE LAUNCH IS A BOOST, NOT A NEW KIND OF EVENT ===============
	-- Hitting the ramp fires a real boost through Simulation:ApplyBoost
	-- and reports it as `boostFired`, which is the same event a drift
	-- release uses.
	--
	-- That is the whole trick and it is why there is no deploy sound in
	-- this file: the boost sound, the boost VFX and the side-thruster
	-- flare are ALREADY wired to that event. A separate "glide deploy"
	-- sound would be a second thing to keep in sync with the first, and
	-- the first is the one people already recognise as "you just got
	-- fast".
	--
	-- It also gives the launch the right shape — a hard shove off the
	-- ramp that decays into the glide, rather than a constant cruise.
	LaunchBoostSpeed = 155,
	LaunchBoostTime = 1.3,
	-- Tier only picks the pitch and the VFX size. 3 is the top drift
	-- tier: a glide ramp should feel like the best boost in the game.
	LaunchBoostTier = 3,

	--== THE FLIGHT ===================================================
	-- Against Handling.Gravity of 150. This is the single number that
	-- decides whether a glide is a long float or a lob.
	Gravity = 24,

	-- Speed bleed per second in the air, as a fraction kept. Wings have
	-- drag; without this you land faster than you took off.
	--
	-- 0.88 was far too aggressive once the launch arc was fixed and glides
	-- got long: over a 7.5s float it compounds to 0.38, and combined with
	-- the float pitch penalty the kart landed at 5 studs/s — stationary.
	-- Floating is meant to be a TRADE, not a trap.
	SpeedKeep = 0.97,

	-- And a hard floor under all of it. Whatever you do with the pitch,
	-- you land able to drive away. A glider that can strand you is a
	-- mechanic players learn to never touch.
	MinFlightSpeed = 48,

	-- Rad/s of yaw at full stick. 0.35 is 20 deg/s — deliberately a
	-- quarter of the ground rate. See the table above for why it cannot
	-- be much more than this without a corridor.
	TurnRate = 0.35,

	--== PITCH: THE ONLY REAL DEPTH IN A GLIDER =======================
	-- Mario Kart's whole glider skill is one axis: nose down lands you
	-- sooner and faster, nose up stretches the flight. Throttle is the
	-- stick here — forward dives, back floats — because it is the input
	-- your thumb is already on and it does nothing else mid-air.
	SinkFloat = 8, -- studs/s of descent holding back
	SinkDive = 40, -- and holding forward
	SinkNeutral = 18, -- hands off

	-- Diving trades height for speed, which is what makes the choice a
	-- choice: studs/s of speed gained per stud/s of extra sink.
	DiveToSpeed = 0.55,
	-- Above LaunchBoostSpeed, or the launch boost is silently clipped and
	-- the dial does not mean what it says. Any ceiling here must clear the
	-- fastest thing allowed to push against it.
	DiveSpeedCap = 165, -- however hard you dive, this is the ceiling

	-- A glide cannot go on forever. Backstop only — if this ever fires
	-- the ramp is aimed at nothing and that is a level bug worth seeing.
	-- Longer than the flight itself, because the glide now continues
	-- while the kart descends onto whatever is actually below the pad.
	-- Backstop only — if this fires, a ramp is aimed at nothing.
	MaxTime = 14,

	--== THE CORRIDOR =================================================
	-- Studs either side of the ramp-to-landing line where you are free.
	CorridorHalf = 16,

	-- Rad/s of extra yaw at full correction, added on top of your own
	-- steering rather than replacing it — so you can still fight it, you
	-- just cannot win against it forever.
	--
	-- MEASURED, NOT GUESSED. The first pair (0.6 / 20) sounded reasonable
	-- and did not hold: a player leaning on full lock for four seconds
	-- still reached 62 studs off-line — better than the 190 they manage
	-- with no corridor at all, and still off the road.
	--
	-- Worst case is always "hold full lock the whole way", so that is what
	-- these were tuned against, at 80 studs/s over a 4s glide:
	--
	--      pull  ramp   full lock   half lock
	--       0.6    20      62          37
	--       0.9    10      34          26
	--       1.2    10      30          24     <- here
	--       1.6     6      24          21     (stiff, starts to shove)
	--
	-- 1.2 over 10 keeps the worst case inside 30 studs — half a 60-wide
	-- road — while hands-off flies dead straight and half lock still
	-- moves you a useful 24 studs across. That last part matters: a
	-- corridor that pins you to the centreline has taken the toy away.
	CorridorPull = 1.2,

	-- How many studs past the corridor edge before the pull is at full
	-- strength. Ramped rather than switched: a step change in yaw is
	-- exactly what makes a correction feel like a wall.
	CorridorRamp = 10,

	--== GUIDANCE, NOT CONTROL =======================================
	-- WHERE YOU LAND IS YOURS. This used to force it: a position funnel
	-- that lerped the kart onto an ideal line, a glide slope that dictated
	-- the descent rate, and a heading clamp that would not let the nose
	-- turn away. Each was added to fix the last one's side effects, and
	-- together they were the reason it felt like being grabbed.
	--
	-- Mario Kart does none of that. It gives you very little air authority
	-- for a very short time and lets the LEVEL do the rest — the ramp is
	-- aimed at the landing area, and the set of places you can reach is
	-- small enough that you arrive somewhere sensible whatever you do. A
	-- bad line costs you time, not the race.
	--
	-- All that survives is the corridor: a gentle nudge on the NOSE when
	-- you stray wide of the line to the landing zone. It suggests. It
	-- cannot make you do anything, and if you insist on flying somewhere
	-- else, you get to.
	--
	-- The landing marker is now optional and purely a hint for that nudge.
	-- With none, the glide is free flight, which is fine for any gap you
	-- cannot really miss.

	--== THE FLARE, OFF THE GROUND ITSELF =============================
	-- A glider levelling out just before it touches down. Measured with
	-- one downward ray rather than against a landing marker, so it works
	-- over any surface, on any track, with or without a pad — and it
	-- cannot be aimed at the wrong thing.
	--
	-- This is the only part of the old approach worth keeping. It was the
	-- bit that made touchdown feel like landing instead of arriving.
	FlareHeight = 26, -- studs above the ground where it starts
	FlareSink = 9, -- descent rate it eases to
	FlareRate = 6, -- how briskly the wings take it up

	--== LANDING ======================================================
	-- Speed kept on touchdown. A glide should not be a free boost, but
	-- landing at a dead stop is worse than not gliding at all.
	LandSpeedKeep = 0.92,

	--== THE WINGS SNAP OUT, THEY DO NOT FADE IN ======================
	-- Fading transparency reads as a rendering glitch — the wings look
	-- like they were always there and the engine was slow to draw them.
	-- Scaling reads as DEPLOYING, because something growing is something
	-- being put there on purpose.
	--
	-- And it overshoots. easeOutBack goes past 1 and settles back, which
	-- is the difference between a part appearing and a part being thrown
	-- open. It costs one extra term and it is the whole effect.
	--
	--     f(t) = 1 + c3*(t-1)^3 + c1*(t-1)^2      c3 = c1 + 1
	--
	-- DeployBounce IS c1 — larger overshoots harder. Around 1.7 is the
	-- textbook value and looks like a spring; past 3 it looks broken.
	DeployTime = 0.22, -- seconds to open
	DeployBounce = 2.2, -- overshoot, ~13% past full at this value
	RetractTime = 0.14, -- and to close, faster and with no bounce

	-- Below this the wings are also made invisible, because a part scaled
	-- to nearly nothing is still a visible speck.
	DeployHideBelow = 0.04,

	--== WIND AND TRAILS ==============================================
	-- Lives here rather than in Config.Audio for the same reason the prop
	-- knock does: it is played BY the glide system, at the kart, and it
	-- starts and stops with a state nothing else knows about.
	-- One-shot when the wings come out, ON TOP of the boost sound the
	-- launch already fires. The boost says "you got fast"; this says
	-- "and you are flying now" — two different facts, so two sounds.
	DeploySoundId = "rbxassetid://9117235033",
	DeployVolume = 0.7,

	WindSoundId = "rbxassetid://96481249",
	WindVolume = 0.55, -- at full speed
	WindMinSpeed = 30, -- below this you hear nothing; a stall is quiet
	WindPitchMin = 0.85,
	WindPitchMax = 1.25,
	WindFade = 2.5, -- per second, so it swells rather than snapping on

	-- Ribbons off the wing tips. Off on the ground, in for the glide.
	--
	-- THE RIBBON'S WIDTH IS THE GAP BETWEEN ITS TWO ATTACHMENTS, times
	-- WidthScale. That was 0.3 studs times 0.5 — a fifteen-hundredths-of-
	-- a-stud ribbon, which is a hairline and read as a stray line rather
	-- than as a wing trail. A kart wheel is 1.7 studs across for scale.
	--
	-- The gap is taken from the WING'S OWN THICKNESS now, so a chunky wing
	-- gets a chunky ribbon and a thin one stays elegant, with a floor so a
	-- paper-thin mesh still shows something.
	TrailSpreadMin = 0.9, -- studs, floor on the attachment gap
	TrailSpreadScale = 1.4, -- multiplier on the wing's thickness

	-- Pulled back from the tip toward the trailing edge, as a fraction of
	-- the wing's depth. A ribbon that starts at the leading edge appears
	-- to pass THROUGH the wing.
	TrailBackset = 0.35,

	TrailWidth = 1,
	TrailLife = 0.45,
	TrailColor = Color3.fromRGB(196, 226, 255),
	TrailTransparency = 0.35,

	Debug = false,
}
