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

	-- Multiplies the speed you arrived with. Slightly over 1 so a glide
	-- rewards arriving fast, which is what makes people take the ramp
	-- properly rather than trickling onto it.
	LaunchSpeedScale = 1.05,

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
	DiveSpeedCap = 140, -- however hard you dive, this is the ceiling

	-- A glide cannot go on forever. Backstop only — if this ever fires
	-- the ramp is aimed at nothing and that is a level bug worth seeing.
	MaxTime = 8,

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

	--== THE FUNNEL: ARRIVAL BY CONSTRUCTION ==========================
	-- A corridor makes straying HARD. This makes missing IMPOSSIBLE, and
	-- it is the same trick that finally fixed the props: if the end state
	-- is a pure function of progress, it cannot be wrong.
	--
	-- Progress along the ramp-to-landing line drives a blend between
	-- where you actually are and where the ideal arc says you should be.
	-- Early on the blend is zero and you fly the thing yourself. It rises
	-- to 1 at the pad, so the last stretch converges no matter what you
	-- did — including flying backwards into a wall.
	--
	-- YOU DO NOT FEEL IT, because it is a funnel and not a wall: the
	-- correction is smallest exactly where you have the most freedom to
	-- notice it, and largest where you are already pointed at the target
	-- anyway.
	Funnel = true,

	-- Fraction of the way across before the funnel starts to bite. Under
	-- half the flight is genuinely free.
	FunnelStart = 0.55,

	-- And the point where it is FULLY committed. Full weight only exactly
	-- at the pad left a player leaning on full lock 3.6 studs out — tiny,
	-- and still not the "lands perfectly whatever happens" this is for.
	-- Reaching 1 a little early makes the last stretch exact instead of
	-- merely close.
	FunnelLock = 0.92,

	-- YOU CANNOT TURN AROUND. Degrees the nose may stray from the line to
	-- the landing zone.
	--
	-- This is what makes arrival a guarantee rather than a strong
	-- tendency. Progress is measured ALONG the line, so a player holding
	-- full lock turns far enough that forward progress stops, the funnel
	-- never reaches its lock point, and the glide times out in mid-air.
	-- The blend was working perfectly; there was simply nothing advancing
	-- it any more.
	--
	-- Clamping the heading keeps the along-line component positive at all
	-- times, so progress only ever increases and the funnel always closes.
	-- 55 degrees still allows a very wide line — it only forbids flying
	-- backwards.
	FunnelMaxYaw = 55,

	-- Peak of the ideal arc, as a fraction of the gap length. Only used
	-- as the shape the funnel pulls TOWARD, so it needs to look like the
	-- path rather than be it.
	-- Small. A big arc holds the ideal path high above the chord, which
	-- for a pad well below the ramp is the funnel fighting the descent it
	-- is supposed to be helping. 0.03 keeps the shape without the fight.
	FunnelArc = 0.03,

	--== HEIGHT IS FLOWN, NOT TELEPORTED ==============================
	-- The funnel corrects ACROSS the line only. Height is corrected by
	-- leaning on the SINK RATE instead — the wings working a little
	-- harder or a little less.
	--
	-- Correcting height by moving the position was wrong twice over. It
	-- yanked the kart down onto the chord whenever the pad sat below the
	-- ramp, which is most ramps; and pulling it down into the terrain put
	-- it in a fight with depenetration, which reads as the kart sticking.
	--
	-- A sink bias cannot do either. It cannot teleport, it cannot push
	-- through geometry, and it is the same control the player has — so a
	-- correction looks like flying rather than like being grabbed.
	-- HEIGHT STARTS CORRECTING EARLY, LATERAL STARTS LATE, and they are
	-- deliberately on different schedules.
	--
	-- Height has a long time constant: bleeding 90 studs of altitude takes
	-- seconds, so it has to begin almost immediately. Lateral has a short
	-- one and the heading clamp already bounds it, so it can wait —
	-- which is what keeps the flight feeling like yours. Sharing one
	-- schedule meant choosing between an accurate landing and a glider
	-- worth flying.
	HeightStart = 0.2,

	HeightCorrect = 2.6, -- studs/s of sink change per stud of error
	HeightCorrectMax = 120, -- and the most it may ever contribute
	HeightClimb = 6, -- how far the bias may push into a climb

	-- How hard the wings pull the descent rate toward its target, per
	-- second, and ONLY while the funnel is active.
	--
	-- Without this the height bias saturated and did nothing past a
	-- point: the sink rate is only a CAP on how fast you may fall, and
	-- gravity at 24 studs/s^2 is what actually accelerates you into it.
	-- Raising a cap nothing is pushing against changes nothing.
	--
	-- Scaled by the funnel weight, so the launch arc is untouched — early
	-- in the flight the weight is zero and this does not exist.
	SinkFollow = 4.5,

	--== LANDING ======================================================
	-- Speed kept on touchdown. A glide should not be a free boost, but
	-- landing at a dead stop is worse than not gliding at all.
	LandSpeedKeep = 0.92,

	--== WIND AND TRAILS ==============================================
	-- Lives here rather than in Config.Audio for the same reason the prop
	-- knock does: it is played BY the glide system, at the kart, and it
	-- starts and stops with a state nothing else knows about.
	WindSoundId = "rbxassetid://96481249",
	WindVolume = 0.55, -- at full speed
	WindMinSpeed = 30, -- below this you hear nothing; a stall is quiet
	WindPitchMin = 0.85,
	WindPitchMax = 1.25,
	WindFade = 2.5, -- per second, so it swells rather than snapping on

	-- Ribbons off the wing tips. Off on the ground, in for the glide.
	TrailWidth = 0.5,
	TrailLife = 0.45,
	TrailColor = Color3.fromRGB(196, 226, 255),
	TrailTransparency = 0.35,

	Debug = false,
}
