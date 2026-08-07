--[[
	Props — scenery you can knock over. Traffic cones, essentially.

	COSMETIC BY CONSTRUCTION. A prop never affects handling: it is made
	non-queryable, so the kart's movement sweep cannot see it at all. It
	cannot slow you, stop you, or bounce you — the collision it appears to
	have is entirely the animation playing afterwards.

	That is deliberate and it is the only safe design here. A prop that
	COULD affect movement would be art with an opinion about handling,
	which is exactly what the Consistency Rule exists to prevent.

	DETECTED LOCALLY, VALIDATED BY THE SERVER, DRAWN BY EVERYONE.
	------------------------------------------------------------
	Only your client knows your kart drove into something, so only it can
	report the hit. The server checks the tag, the distance and the rate,
	then broadcasts a direction, a power and a seed — and every client
	animates from those three numbers.

	The server never moves a prop itself. Anchored CFrame writes do not
	interpolate, so a server-animated cone arrives in visible network
	steps; drawing it locally is both smoother and a fraction of the
	traffic.
--]]

return {
	-- Tag a Model (or a bare BasePart) with this and it becomes flingable.
	--
	-- "Props", PLURAL. It was "Prop" and the world uses "Props", so
	-- nothing matched: adopt() never ran, CanQuery stayed true, and the
	-- cones were solid walls that also produced no log. One character,
	-- both symptoms.
	--
	-- This string is the ONE place the tag is written. Triggers reads it
	-- to keep props out of the movement sweep and the Props module reads
	-- it to animate them, so the two can never disagree about what a prop
	-- is called.
	Tag = "Props",

	-- How close the kart's centre must get. Generous, because the sweep
	-- never touches these — this radius IS the collision.
	HitRadius = 7,

	-- Belt and braces on discovery. What actually keeps props out of the
	-- movement sweep is Config.Props.Tag being in Triggers.TAGS.
	ForceNonQueryable = true,

	--== THE KNOCK =====================================================
	-- A TIMELINE, NOT A SIMULATION. Every value below is a function of
	-- `t` (0..1) and the cone's HOME, recomputed from scratch each frame.
	--
	-- This replaced an integrated arc — velocity, gravity, ground rays,
	-- bounce, roll, resting state — and every bug this feature had came
	-- from that: cones hovering because a tumbling bounding box kept
	-- moving the "floor", cones freezing when a phase never advanced,
	-- cones restoring crooked because the position had drifted from any
	-- known reference.
	--
	-- Nothing accumulates now, so nothing can drift. At any instant the
	-- cone is exactly where the formula says, and at t=1 it is exactly
	-- home. There is no state that can be wrong.
	-- The server sends the kart's raw speed; this is what counts as a
	-- full-strength hit. Just under Handling.MaxSpeed (95), so flat out is
	-- a proper launch and a slow nudge is a nudge. A hit is never weaker
	-- than a quarter strength — a cone that barely twitches reads as a bug.
	MaxPower = 90,

	KnockTime = 1, -- seconds from clipped to settled
	KnockDistance = 16, -- studs it travels at full speed
	KnockHeight = 7, -- peak of the FIRST hop at full speed

	-- THE MARIO KART CONE, AS CURVES.
	--
	-- Pops hard, tumbles end over end, bounces a couple of times and
	-- skids to a stop. The earlier version was one clean parabola at a
	-- constant spin, which is why it read as an object being animated
	-- rather than an object being hit.
	--
	-- Nothing here is integrated. A bounce is not a collision response,
	-- it is |sin| — a run of arcs — and the decay is what makes each one
	-- lower than the last.
	--
	-- MUST BE A WHOLE NUMBER. |sin(pi*n*t)| is zero at t=1 only for
	-- integer n, and that zero is what puts the prop on the ground at the
	-- end of the knock instead of frozen in mid-air. Floored in code, but
	-- do not set 2.5 and expect half a bounce.
	Bounces = 2,

	-- How sharply the launch and the tumble bleed off. Higher is snappier:
	-- more of the distance covered in the first moments, more of the spin
	-- done early, so it slows into its resting pose rather than stopping
	-- dead. 1 would be a linear slide.
	SettleEase = 2.2,

	-- Whole tumbles before it settles. The FINAL orientation is chosen
	-- first (see RestLean) and these spins are added on top of it, so the
	-- cone can rotate as much as it likes and still arrive exactly at the
	-- pose it was always going to land in.
	SpinTurns = 2.5,

	--== HOW IT COMES TO REST ==========================================
	-- KNOCKED OVER, AND NEVER THE SAME WAY TWICE.
	--
	-- A cone that always settles identically reads as an animation
	-- playing. The randomness is the point: it should look like something
	-- fell over, not like something was replayed.
	--
	-- Around 82° from upright — just past lying flat, so it is unambiguous
	-- at a glance — with a wide jitter either side. It is seated on the
	-- ground by measurement, so any angle in this range rests ON the road
	-- rather than floating over it or sinking through it.
	RestLean = 82, -- degrees off upright it comes to rest
	RestLeanJitter = 38, -- +/- on that, so 44°..120°: leaning to fully over

	-- IT SITS THERE LONG ENOUGH TO BE READ.
	--
	-- This was 0.35s, which was long enough to see the cone move and not
	-- long enough to see that it had BEEN moved — it was already fading
	-- before you could look at where it landed. The knock is the event;
	-- this is the evidence, and the evidence is the useful part. Two
	-- seconds is roughly a corner's worth of "somebody clipped that".
	--
	-- Holding it this long is what forced the resting pose to be real.
	-- At 0.35s a wrong tilt was invisible; held for two seconds, a cone
	-- floating over the road or buried in it is the first thing you see.
	HoldAfter = 2, -- lies where it landed before disappearing

	-- Slower than the knock on purpose. A quick pop-out reads as a glitch;
	-- a visible dissolve reads as the game tidying up after you.
	FadeOut = 0.45,
	FadeIn = 0.35,

	-- Local only, so the same cone is not reported every frame while you
	-- are inside its radius. PER CONE, not per player.
	ReportDebounce = 0.5,

	-- FLOOD GUARD, per player per second.
	--
	-- This replaced a fixed 0.25s gap between reports, which was per
	-- PLAYER — so driving through a row of cones 8 studs apart reported
	-- one every 0.13s and the server refused all but the first. You heard
	-- every hit and saw one cone move.
	--
	-- A budget per second is the right shape: it stops a client flooding
	-- without punishing somebody legitimately mowing down a line of them.
	MaxReportsPerSecond = 12,

	-- Extra distance allowed per stud/s of kart speed, on top of the
	-- radius check.
	--
	-- The client hits the cone at ITS position; the server checks against
	-- a hitbox that is one network hop behind. At 95 studs/s and 70ms
	-- that is nearly 7 studs of disagreement about where you were —
	-- entirely normal, and refusing it would make fast hits the ones that
	-- fail.
	ReportLagAllowance = 0.2, -- seconds of travel to forgive

	-- The knock. Lives here rather than in Config.Audio because it is
	-- played AT the prop by the prop system, not by the kart's audio rig.
	HitSoundId = "rbxassetid://9119637036",
	HitSoundVolume = 0.7,
	HitSoundRange = 160,
	PitchMin = 0.9,
	PitchMax = 1.35,

	Debug = true, -- prints what got adopted and what got flung. Turn off for release.
}
