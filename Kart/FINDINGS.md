# FINDINGS — what BloxKart has taught us so far

An engineering log, not a spec. Everything here cost real debugging time,
and most of it is the kind of thing that gets silently re-broken by a
reasonable-looking change six months from now.

Rule for adding to this file: **write down the mechanism, not the fix.**
"Anchored the hitbox" is worthless in a year. "Exactly one thing may own
a part's position" survives.

---

> **Currently broken things live in `BUGS.md`, not here.** This file is
> the permanent record of mechanisms learned; that one is the live list,
> and it carries the order of attack.

# 1. The invariants

These are load-bearing. Breaking any of them produces a class of bug
rather than a bug.

### The kart is kinematic. Roblox physics never gets a vote.
Position, forward, up and speed are integrated by hand in `Simulation`.
Physics is not a partner in this — it's a thing to be kept out. Every
time something has gone visibly wrong with kart motion, the root cause
has been physics being allowed an opinion.

### THE CONSISTENCY RULE: `Simulation` reads only `Hitbox` and `Seat`.
Never art. This is what makes a custom kart cosmetic rather than
pay-to-win, and it's why `KartFactory` strips `Seat`/`Hitbox`/the `Kart`
tag off cloned visuals. Two separate bugs came from art carrying a tag
the simulation then believed.

### `CanQuery` is the collision flag, not `CanCollide`.
Movement is query-based, so `WorldFilter`'s exclusion list *is* the
collision rule. `CanCollide` describes a physics interaction we don't
use.

### Everything is measured along `up`, never world Y.
`up` chases the surface normal. This is what makes loops and banked
corners work at all, and it's free as long as nobody writes `.Y`.

### Exactly one thing may own a part's position.
See §3. This one has bitten hardest.

---

# 2. Control theory — the expensive lessons

This section is the most valuable thing in the file. The bot's steering
was rewritten three times, and the first two rewrites failed because the
problem was never where it looked.

### A pure error-driven loop must PRODUCE error to have work to do.
The original controller steered proportional to heading error toward a
lookahead point, with a second P+D loop on cross-track error beside it.
On a perfectly straight, perfectly laid-out road it still swerved —
because a controller that only reacts to error has nothing to do until
there is error, and then overshoots creating more.

**The fix is feed-forward.** Compute the *road's own curvature* and steer
that amount open-loop; feedback only trims what's left. On a straight,
feed-forward is exactly zero and there is nothing to hunt.

### Pure pursuit is unstable if lookahead ≲ the control lag distance.
This was the single most costly finding and it is pure arithmetic.

Total lag in the loop:

| source | time |
|---|---|
| `Bots.ReactionTime` | 0.19 s |
| `Bots.SteerSlew` (9/s) | ~0.11 s |
| `Handling.SteerSmoothing` (7/s) | ~0.14 s |
| **total** | **~0.44 s** |

At 100 studs/s that is **44 studs of road**. The lookahead was
`18 + 0.28×100` = **46 studs**. Forty-six against forty-four — sitting
exactly on the stability boundary.

Measured, released 5 studs off a straight at 100 studs/s:

| lookahead | outcome |
|---|---|
| 30 | half-amplitude 50 studs, never settles |
| 46 (old) | half-amplitude 30 studs, never settles |
| 60 | half-amplitude 16 studs, never settles |
| 80 | settles |
| 108 (current) | settles |

**Lookahead now has a hard floor of `2 × speed × ControlLag`**, applied
*after* corner shortening — because shortening it for a bend is precisely
how you drop back under the limit.

**These two findings are a pair.** A long lookahead is normally
unaffordable because chasing a distant point cuts every apex.
Feed-forward is what pays for it. Neither change works alone.

### A delay inside a feedback loop is an oscillator.
The 190 ms reaction delay used to wrap the *finished steering output*.
Delay + gain + no rate feedback is the textbook recipe.

It was also the wrong model of a person. **Reaction time is how long you
take to respond to something new — not how long you take to hold a lane**,
which is a trained reflex an order of magnitude faster. Nobody weaves
down a straight road because of their reaction time.

The delay now wraps the *plan* (feed-forward + pursuit) and the
stabilising terms run current.

### Deadbands and hysteresis discard information. Both caused bugs.

**`LineDeadband`** zeroed the pursuit term when the aim point was nearly
straight ahead. But that quantity is *not* cross-track error — pure
pursuit's lateral term mixes position and heading, and falls to zero
whenever the kart is *pointing at* the target, **including while running
parallel to the line several studs wide of it**. It suppressed the
correction in exactly the case that needed one.

**`SteerDeadzone`** held the last input until the new one differed by
0.07. That's hysteresis inside a feedback loop — a limit-cycle generator
on its own. Worse after the lookahead grew: the correct input for being
5 studs off at a 108-stud lookahead is ≈0.049, *under* the 0.108
threshold a typical bot had. So it was discarded every frame and **the
bot drove parallel to its own racing line forever without rejoining it.**
Measured: settles 5.00 studs off with it, 0.00 without.

Both removed. Realism now comes from `SteerSlew` and `SteerNoise`, which
*shape* the input rather than throwing it away.

### Anything that adds a sine wave to the output is an instruction to swerve.
`SteerNoise` and the lateral-line `wander` were both applied
unconditionally. **A controller cannot refuse an instruction to weave,
however good it is.** Part of the "swerving" was not the controller
failing — it was these working as written. Both now scale with how hard
the bot is working, because people hold a straight and get untidy in
corners, not the reverse.

### `travel ⊥ up` means a tilted `up` is a climb gravity cannot see.
The single most confusing bug so far, and it follows directly from the
surface-relative design.

`travel` is always perpendicular to `up`. While `up` is a ramp's normal,
`travel * speed` points **uphill in world terms** — and that climb lives
entirely outside `vertVel`, which is the only thing gravity acts on. A
30° ramp at 100 studs/s produced a 50 studs/s rise with nothing opposing
it.

It never levelled either: the airborne branch settles `up` toward
whatever a 40-stud probe finds beneath, and just after a ramp that probe
still finds the ramp. **The tilt was self-sustaining.**

Fix: leaving the ground converts to a ballistic state — world velocity
preserved exactly, re-expressed as level speed plus a vertical rate.
No-op on flat ground by construction. Loops excluded by surface angle,
since there surface-relative *is* the truth.

**Surface-relative gravity is worth it, but it has one sharp edge:**
anything that leaves the surface must have its motion handed back to the
world frame, or it keeps obeying a frame it is no longer in.

### A kart in the air had an engine. Nothing checked `grounded`.
The speed calculation never asked whether the kart was touching
anything, so full throttle accelerated it in **mid-air** toward
`MaxSpeed`. Launch at 70 studs/s, two seconds airborne, land at 113.

Always true, always wrong, and invisible until something held the
throttle down through a flight — the bot ramp logic, which correctly
pins throttle to clear a gap. It kept accelerating for the whole jump.

Speed is **held** in the air now, not decayed: coasting to zero is
equally invented in the other direction and makes every jump feel like a
punishment. Boost and nitro stay live — thrust, not traction.

**The general lesson:** a missing precondition can sit for months
looking correct because nothing exercises it. The bug report will name
the feature that *exposed* it, not the one that contains it. "It was
working before" meant the old code accidentally hid the hole by lifting
off the throttle.

### Depenetration must use the nearest FACE, not the part's centre.
`pos - part.Position` is fine for a crate and meaningless for anything
large. A road slab or a track-surface zone can have its centre a hundred
studs away, so the push becomes a fixed sideways shove that moving can
never resolve — the kart keeps going that way at `Depenetrate` studs a
second, forever.

Correct version: transform the centre into the part's object space, and
if it's genuinely inside, leave along the **shortest axis** — the real
minimum-translation vector for a box. If the centre isn't inside the
solid, skip entirely; the bounds query is conservative and reports boxes
that merely touch, which is the sweep's job.

Also clamp the step to the depth actually being resolved. A fixed rate
can travel further in one frame than the penetration it's clearing,
which is how a nudge becomes a launch.

**Identical numbers across different actors are a signature.** Four bots
each sliding *exactly* 159.1 studs was the clue that cracked it: a push
of `dir.Unit * rate * dt` has the same magnitude whichever way it points,
so anything measuring distance sees the same total for everyone.

### Two proportional terms with nothing watching the RATE always overshoot.
They cross the line rather than arriving at it. Lowering the gains
doesn't fix it — same fight, slower.

### Grip does not set the drift radius. It only sets the entry.
The most natural wrong assumption about this kart, and it survived two
sets of design notes before anyone checked it.

`travel` chases `forward` proportionally, so in a **settled** drift travel
rotates at exactly the same rate as the nose — that is what settled
means. The arc the kart holds is therefore `speed / driftTurn` and
`DriftGrip` is nowhere in it. Grip decides how far travel *lags* and how
wide the kart washes on the way IN, and nothing else.

So "lower the grip, then raise something to stop drifts running wide" is
compensating for an effect that does not exist, and the compensation
silently changes what the fast line is. The vault carried a
`DriftInwardPull` dial for exactly this purpose for months; it was never
implemented, and working through the algebra showed it would have been
redundant with `DriftGrip` in steady state and a second answer to "how
tight is the drift line" — root cause #1 in this file.

### A clamp on a proportional lag has a THRESHOLD, and it moves.
`MaxSlip` caps how far travel may trail the nose. In a settled drift

    slip ≈ driftTurn / DriftGrip

so the cap is reached at some *fraction of full lock*, and that fraction
moves whenever either number does. Past it, extra steering still rotates
the kart but adds no visible slide: the drift feels like it hit a stop.

Dropping `DriftGrip` 3.5 -> 2.9 while leaving `MaxSlip` at 32 would have
pulled that threshold from 68% of lock down to **57%** — a wider dead
band, which is the exact opposite of the loosening the change was for.
The cap had to move to 38 just to stand still.

**Write the threshold down before tuning either half.** It is one line of
arithmetic and it is invisible from the driver's seat, because the
symptom of a clamp biting is not "it stops turning", it is "it stops
looking like it is turning".

---

# 3. Replication and authority

### Two owners of one part = "it sinks then teleports".
A bot's kart was unanchored (so Roblox gravity pulled it down) while the
server wrote its CFrame back 60×/s. Gravity down, correction back. It
wasn't driving anywhere — it was being argued over.

- **A player's kart is unanchored** because their *client* owns it, and
  nothing else writes to it. One authority.
- **A bot's kart has no owner**, so it must be **anchored** — the server
  is the only writer.

I flip-flopped on this twice before stating the rule properly. The rule
is what matters, not the flag.

### Writing the CFrame of a part you don't own creates a freeze loop.
`RemoteKarts` smoothed every kart the client didn't own — including other
**players**, whose karts are unanchored and network-owned by their
driver, and which Roblox already interpolates for free.

The loop: the local write lands *after* the incoming replication update,
so next frame reads back **its own value**, concludes nothing changed,
and never advances the target. The kart sits still forever — while its
driver races normally on their own screen, because their own kart is
excluded from the smoothing.

**Symptom: everyone sees everyone else parked, and each player is moving
fine locally.** That's this, running on every client at once.

**The rule:** only ever smooth **anchored, server-written** parts. An
unanchored network-owned part is already interpolated; touching it
replaces something that works with something that doesn't.

### Anchored CFrame writes don't interpolate. Client-side rendering is the fix.
An anchored part's CFrame replicates as a plain property update, roughly
20 Hz — about 6 studs per step at racing speed, which reads as
teleporting. Roblox interpolates *unanchored physics* parts, not property
writes.

The answer is the one the missiles already use: **server owns truth,
every client draws its own smoothed copy at full frame rate**
(`RemoteKarts.luau`, `Projectiles.luau`). Never move a kart anywhere the
server didn't say; just decide what to draw in between. Hits, items and
standings all read server state, so being drawn a few studs back can't
change who got hit.

### Sending more updates is not the fix.
You are always drawing between two updates. More traffic narrows the gap;
it doesn't remove it, and it scales with the number of racers — the wrong
direction.

---

# 4. The track and the racing line

### Checkpoint gates are WIDER than the road. Do not measure width from them.
This was a confidently wrong answer, which is worse than no answer.

Gates get drawn generously so nobody squeezes past one, so on real tracks
they **overhang the void at exactly the corners where being wrong is
fatal**. Measuring road width from gate geometry told bots there was
tarmac where there was nothing.

**Road width is now felt for with rays**: step outward from the
centreline, raycast down, stop where the floor stops. Cached per node.

- **Left and right separately.** A checkpoint is rarely centred on its
  road, and one averaged number is too tight where there's room and too
  generous over the drop — and it's the generous side that kills bots.
- **A hit far *below* the road counts as a gap** (`RouteEdgeStepDrop`), so
  a ledge with ground 30 studs down reads as a fall rather than as more
  track. A plain did-the-ray-hit test calls that drivable.

### A checkpoint's centre is not where the road is.
A gate volume's centre floats above the tarmac. A line built from those
centres hangs in the air, which tilts every tangent, so anything
measuring bend reads a permanent corner — bots brake for it and crawl,
missiles cruise at the wrong height. Hence `dropToRoad`, probing along the
*part's* up so it survives a loop.

### A gap the route crosses is a JUMP, not a ledge.
The first ledge check treated every missing floor as an emergency and
lifted to `LedgeThrottle` on the approach — the one input guaranteed to
turn a jump you'd have cleared into a fall. **It was braking for the
ramp.**

**The racing line is the authority on where the road goes.** If the route
carries on across the gap and there's road on the far side, line up and
stay on the power. Only a gap the route does *not* cross is a bot about
to leave the map. Airborne bots skip the check entirely — nothing can be
done mid-flight and lifting only shortens the landing.

### Where you fell is not where you were.
`revive()` projected the crash site onto the racing line
(`nearestU(pos)`). Drive off the outside of a right-hander and the
nearest point on the line is *the straight you were aiming at* — so bots
respawned at the checkpoint **after** the one they left.

Then respawning at the exact last-safe position replaced that with a
**loop**: the last place a bot was legally on the road is by definition
the last inch before it left, pointing at the same edge at the same
angle, so it drove off again forever. It looked like flying to the
checkpoint; it was a bot being helpfully returned to the scene of the
accident.

**Keep the progress (`u`), discard the position.** Respawn on the
centreline at that checkpoint.

### Learning from mistakes doesn't need to be clever.
One number per checkpoint, up when the bot leaves the track there,
decaying on a clean lap. High means drive that stretch nearer the middle
and slower.

That's enough because **the failure is entirely local** — a bot doesn't go
off "in general", it goes off at turn four the same way every lap, and
one number attached to turn four fixes turn four.

**Caveat that decides the design:** a race is 3 laps, so a bot gets *two*
attempts per corner. That will never converge. It survives race restarts
on purpose, and if it's ever persisted it must be keyed **per track**.

---

# 5. Roblox gotchas

- **Instances throw on unknown property access.** `player.Bot` crashes —
  it doesn't return nil. Anything that might be a Player *or* a table
  needs `typeof(x) == "table"`. Cost us a full spawn failure.
- **Anchored humanoids cannot `Sit`.** It fails *silently*. Unanchor,
  seat, then verify.
- **`luau-analyze` cannot catch missing methods on tables.** ALL CLEAN
  never means "no missing methods" — `camera:Snap()` shipped undefined
  three times. Regex-scan call sites after any data-shape change.
  A `local function` used before its definition line is nil at runtime;
  the analyzer reports it as *"never used"*, which is easy to skim past.
- **Studio names test players `Player1`/`Player2`**, not your username.
  Hence `Rig.StudioVisual`.
- **A fresh `Part` defaults to `CanCollide = true`**, so using CanCollide
  as a discriminator turned every trigger zone into a wall. Use an
  explicit opt-in tag (`TrackSurface`).

---

# 6. The two recurring root causes

Nearly every bug in this project has been one of these:

### 1. One question answered in two places.
Trigger tags, device detection, `orderOf`, ray filters, road width. The
two answers drift and the symptom appears somewhere else entirely.
Response: extract a shared module (`Triggers`, `Names`, `Device`, `Route`,
`Ballistics`) rather than fix the copy that happens to be visible.

### 2. Something assuming a Player behind the kart.
Bots were invulnerable for a whole session because every hit path
resolved `GetPlayerByUserId`, got nil, and silently dropped the hit —
they weren't AI, they were scenery. Same shape of bug in standings,
announcements, and the ready-skip (which compared ready-count against
*all* racers, so one human in a five-kart lobby could never start early).

**Test for it:** anywhere the code says "the player who owns this kart",
ask what happens when there isn't one.

**Third instance: client-only presentation.** The shield bubble is
authored art welded to the kart, and the only thing that ever hid it was
`Effects` — a client module that looks at *your* kart and nothing else.
So every other kart in the race wore a permanent shield. Bots made it
obvious, but remote players had it too.

**Rule:** anything a client draws for itself must have a default the
world already satisfies. Hide it at build; let the owner turn it on.
"Correct only because a client fixes it up" is wrong for everyone the
client isn't looking at.

### A tag answers one question. Being kart-shaped is not being a racer.
The `Kart` tag was doing double duty, and a spare kart parked in
Workspace was consequently a missile target, an obstacle for bot
avoidance, and a competitor padding the field that item odds weight by.

Split it: `KartFactory` — the only place a kart is ever built — stamps
`Names.RACER`, and `Standings.allKarts` requires it. Four separate
consumers were reading the raw tag directly, which is root cause #1
again.

The worst instance: **bots could not finish a race.** Finishing was
reachable through exactly one door — the client's `FINISH_REMOTE` — and a
bot has no client. So however fast one drove it never crossed the line,
never took a place, and never counted toward "everyone's in". The round
always ran to the time limit and the board could only list humans. Fixed
by splitting `finishKart(kart, …)` from the two thin routes into it, so a
bot's win is literally the same object as yours.

**Corollary:** when you split a path like that, the validation belongs on
the *client* route, not the shared function. The server calling it for a
bot is trusted by construction; leaving a "TODO: validate" in the shared
half implies the server doesn't trust itself.

---

# 7. Method notes

### Simulate before claiming.
The controller rewrite was verified against the *real* vehicle model
(`TurnRate`, `TurnRateTop`, `MaxSpeed`, `SteerSmoothing`, the reaction
delay) before shipping. That's how the lookahead/lag boundary was found —
it would not have been found by tuning in Studio.

### Know when your harness is invalid.
One experiment (a wobbling spline) parameterised the path by world *x*,
which stops being valid once heading leaves a few degrees. It hit 30° and
produced a confident 28-stud "instability" that was an artifact. **It was
discarded and nothing rests on it.** The straight-line and lookahead
results are from the small-angle regime where the harness holds.

### Don't put unmeasured numbers in a commit message.
A commit once claimed centripetal Catmull-Rom cut overshoot "25 → 9
studs". Measured: 11.9 vs 11.6 on even spacing, 18.5 vs 20.8 on uneven —
i.e. no real difference. The commit was amended and `RouteTension` added
as the actual lever.

### A comment asserting something is not evidence it's true.
`Hold()` zeroed speed and its comment claimed that "stops a boost that
was live when the hold began". It doesn't — speed is re-targeted 200
lines further down, where a nitro burn or boost pad sets the target
*regardless of throttle*, so the zeroing was undone within the same
`Step` and the kart accelerated out of the hold at boost speed.

I read that comment twice while hunting the bug and moved on both times.
**When a comment claims a guarantee, go and check the code that would
have to enforce it.**

### A turn RATE implies a turning CIRCLE. Write it down before tuning.
`Speed / HomingRate` is the tightest circle a homing projectile can fly.
The missile shipped with `210 / 3.2` — a **66-stud circle** against a
**7-stud kill radius**. It could not physically reach anything it wasn't
already lined up on, so it flew past, turned around, and flew past
again: the "goes back and forth instead of charging in" report.

Measured across bearings 0–180° and ranges 15–60 studs: at 3.2, **11 of
65 engagements never terminated**, and a target directly behind was
missed by 60 studs. At 9 (a 23-stud circle) all 65 terminated.

**But raising the rate is not the fix**, and the sweep proves it — even
at 14 the worst case still logged 10 fly-bys. Pursuit steers at the
target's *current* bearing, so the turn it needs tightens faster than any
fixed rate can follow as range drops. No value removes this; higher
rates only move the radius where it begins.

**The fix is a proximity fuze.** When the range to the target stops
closing, that instant *was* the closest approach — detonate there. Real
missiles carry one for exactly this reason. It converts "orbits forever"
into "near miss counts", which is both correct and better game feel.

**Generalises:** any chase controller — missile, bot, camera — has a
geometry limit that tuning cannot cross. Find the limit (turn radius,
lag distance, deadband) and design a *terminator* for the case where it's
exceeded, rather than tuning toward a value that cannot exist.

### Throttle is a GATE, not a dial. You cannot slow a kart with it.
```lua
elseif throttle > 0.05 then target, rate = H.MaxSpeed, H.Accel * powerBand
```
Any throttle above 0.05 targets **full speed**. Throttle magnitude
affects nothing else — so scaling a bot's `touchThrottle` down, the
obvious way to make it slower, changes *nothing* until it crosses 0.05
and then changes *everything*. There is no middle.

The way to make a driver slower is a **lift**: pick a cruise speed, come
off the power above it, get back on below it. That's also what a real
driver does, and it gives the throttle trace the on/off texture a real
one has.

**Generalises:** before tuning a value, check whether the code reads it
as a magnitude or as a threshold. A surprising amount of this codebase
reads thresholds.

**I then made this exact mistake while implementing the fix for it** —
the hysteresis band set throttle to `MinCornerSpeed` (0.42), which is
still wide open, so the speed cap barely applied. Knowing the rule is
not the same as applying it. Grep for every write to the value you just
learned is a threshold.

### A Studio sync can delete the entire source tree. Commit early.
It has happened twice. Argon syncing from a Studio session that doesn't
have the files removes them from disk — all 68 at once, silently,
mid-session.

**Both times git was the only thing that saved it.** Nothing else in the
setup keeps a copy.

### A NEW file has no recovery, and that is a different rule

2 Aug: `Config/Places.luau` and `Place.luau` were written, passed
`check.sh`, and were gone from disk by the time `git add -A` ran about a
minute later. The commit meant to add them contains six modifications
and zero additions — so `Config/init.luau` went in requiring
`script.Places` while `script.Places` existed nowhere. Every module
downstream of Config failed to load on both sides, which reads as a
total collapse and is one missing file.

**The cause was not established.** Argon was serving, and `move_to_bin`
should have put them in the Trash, which was empty — so it may not have
been the sync at all. Worth naming precisely rather than assuming,
because the rule that follows does not depend on knowing:

Git protects what it has already seen. A modified file can always come
back from HEAD; **a file git has never seen cannot come back from
anywhere.** The gap between writing a new file and committing it is the
only window in this project with no backup at all.

**So: commit a NEW file before doing anything else with it** — before
wiring it up, before type-checking, before touching Studio.

**Rules:**
- Commit as soon as a change compiles. Uncommitted work is one sync away
  from gone, and "I'll commit when it's tested" is how you lose an hour.
- If the tree disappears, **do not `git checkout` while the sync is
  live** — a running sync can re-delete the restore, or push the empty
  state back. Stop the sync first, then restore.
- `find src -name '*.luau' | wc -l` against
  `git ls-tree -r HEAD --name-only | grep -c src/` tells you instantly
  whether the tree is whole.

### A half-applied revert is worse than either side of it.
A revert kept `finishKart` but dropped `recordFinish`, which was still
being called by the remote handler. Every finish raised "attempt to call
a nil value", nothing was recorded, and the round could only end on the
time limit.

It presented as a **design** bug — "the match doesn't end even though
everyone finished" — and cost a full round of testing before anyone
opened the file.

**Luau resolves globals lazily, so the analyser cannot see this.** After
any revert or partial merge, grep every call site of the functions
involved. `luau-analyze` reporting clean means nothing here.

### A rate applied per frame is not a rate. Same bug as the one below.
`speed *= 0.98` inside the step loop is not a 2% trim, it is `0.98^fps`
per second — 30% surviving at 60fps, 5% at 144. The drift scrub shipped
like this and cost 32% of top speed at 60fps and **51% at 144fps**, so
the fast line was the slow line on better hardware.

The tell is that the number *looks* like a percentage. `0.995` reads as
"half a percent" and is 74% per second. Anything of the form `x *= k` in
a per-frame loop wants `k ^ dt`, and the config comment wants the word
PER SECOND in it, in capitals, because the next person will read the
number and not the loop.

### A clamp is not a budget. `math.min(dt, cap)` silently LOSES time.
`Simulation.Step` clamps dt to `MaxTimestep` so a huge frame cannot tunnel
the sweep through a wall. Correct — and a caller that calls Step ONCE per
frame throws away everything past the cap. Discarded time is lost MOTION:
at 15fps the kart ran at 75% speed, at 10fps 50%, smoothly, **with the
speedometer agreeing** because the simulation really was that slow.

From the seat that is indistinguishable from the handling being nerfed,
which is the last thing anyone investigates. A long frame must be
integrated as SEVERAL capped steps, bounded (`MaxSubSteps`) so repaying a
one-second hitch cannot cost a second of simulation on the next frame.

The module cannot enforce this on its callers, so the requirement lives
where the constant does.

### A fallback with no retry is a permanent wrong answer.
"Use the good value, or a default if it is not ready yet" is only half a
design. A kart spawned before its profile loaded got the random dresser —
correct — and nothing ever went back, so it raced the whole round in a
kart nobody chose. Any code of that shape must say what happens when the
value BECOMES ready, or the default is not a fallback, it is the outcome.

### A list of candidate names is not a name.
`Rig.FrontWheelNames` is a compatibility list. Treating any single entry
as "the" name is a coin flip, and it lost: `lookFor` hard-coded `FWheel`
while the rig used `WheelFL`/`WheelFR`. **If a config field is plural,
iterating it is not optional.**

This matters more than it sounds because the garage PREVIEW kart and the
RIDDEN kart are different models with no obligation to name parts alike.
One name can only ever be right for one of them.

### Remembering what you did is not knowing what is true.
A change-detector built on "what did I last apply" is correct only while
it is the sole writer. The moment anything else can touch the same
object — and something always can — the only reliable question is "is it
right NOW", asked of the object itself.

The menu preview was dressed once, in a guessed window, and anything that
rebuilt the kart afterwards won. Polling harder is a longer guess, not a
fix. Stamp the object with what it is wearing and compare.

### A cache key must record an OUTCOME, never an INTENTION.
The corollary, and it cost a full extra round. The verifier above was
sound and still failed, because the stamp was written whether or not the
mesh actually applied — and during loading it genuinely can fail
(`CreateMeshPartAsync` fetches over the network). A claim made at the
wrong moment was both wrong and PERMANENT: the verifier believed it and
never looked again.

**If a result gates a retry, that result has to be measured.** And "no
matching parts" is a FAILURE, not a no-op — reporting success there is
how a naming mismatch stays invisible.

### A success message that cannot be wrong is not a diagnostic.
`preview ready` printed, truthfully, every time — while dressing a kart
nobody could see. Any log line asserting work was done must name the
OBJECT it was done to, or it cannot tell success apart from doing the
work in the wrong place.

Corollary for silent pipelines: a wrong part name swaps nothing and says
nothing, which is indistinguishable from the data never having saved.
Five separate bugs wore that one disguise. **Print what was found, not
just what was attempted.**

### "It works" and "it is observable" are different claims.
The loading bar was built, filled, faded and destroyed itself — every
line correct — entirely behind a splash screen that had seconds left to
run. Never on screen for a frame. For anything whose job is to
COMMUNICATE, *when* it runs is part of whether it works at all, and
neither the type checker nor a log line can tell you that.

### A conditional that yields the same THING by two routes must converge.
`spawnKartFor` either claimed a pre-built kart or called `createKart` —
and the dressing lived inside `createKart`. So slot 0, which is the first
player to join and therefore always you in a solo test, rode the one kart
nothing had ever dressed.

The bug is not that the claim path forgot. It is that the work lived
inside one leg of a branch at all. **Anything that must happen to "the
kart" belongs after the `if`.**

### A probability rolled per step is not a probability.
```lua
if rng:NextNumber() > B.NitroHoldChance * (1 - bot.skill) then  -- every step
```
At 60Hz, "a 40% chance it holds the tank" is a 40% chance of holding it
for **one sixtieth of a second**. Chance of firing within one second:
**100%**. Bots spent nitro the instant they had it, permanently — which
is why they were uncatchable, since a burn sets the speed target
directly and bypasses every pace limit.

Any `rng` roll inside a per-frame update must either be **scaled by
`dt`** (odds per second) or guarded by a **cooldown / edge trigger**.
An unscaled one is a certainty wearing a percentage sign.

**Both of these are the same failure**: a number whose units were never
checked. Threshold vs magnitude, per-second vs per-step.

### THE BOTS-FLYING INCIDENT — a symptom chased into shared physics
The most expensive mistake in the project so far. Worth the space,
because the failure was in *method*, not in any one line of code.

**What happened.** The report was "bots move before the race starts."
That is a match-discipline bug. Chasing follow-on symptoms — bots flying
off ramps — I made two changes to `Simulation`, which **every player
shares**, on my own initiative:

- `AirKeepsSpeed` — no engine or brakes while airborne
- `BallisticLaunch` — convert a ramp's climb into a proper arc

Neither was ever asked for. Both were reasoned from code-reading, not
from a measurement. The flying continued throughout, so neither fixed
the reported problem, and the whole session had to be reverted.

**The analysis was probably still correct** — `travel` is perpendicular
to `up`, so a tilted `up` is a climb `vertVel` never sees; nothing checks
`grounded` before applying throttle. Both observations survive. But:

> A correct observation about code you were not asked to change is not a
> licence to change it.

**The measurement that should have ended it early.** Once written, a
faithful sim of the ramp exit using the real constants (11.4°, 120
studs/s, `Gravity 150`, `RideHeight 1.4`, `GroundSnap 3/8`,
`SurfaceAlignRate 14`, `AirAlignRate 2.5`, `StickTime 0.16`) showed
`BallisticLaunch` changing **nothing**: peak 15.1 studs either way, same
landing, same vertical speed. The fix I had argued hardest for was
provably inert.

**The question that would have saved an hour**, asked far too late:
*"does YOUR kart fly off the same ramp?"* Answer: no. One sentence,
and it eliminates every shared file — `Simulation` cannot be the cause
of something only bots do.

**Rules taken from this:**

1. **Scope is the deliverable.** When the ask is "bots ignore the match",
   a fix in shared physics is out of scope no matter how right it looks.
2. **Ask the isolating question first.** "Does it happen to X too" costs
   one sentence and can eliminate whole subsystems.
3. **Gate speculative changes behind a flag.** `AirKeepsSpeed` and
   `BallisticLaunch` were, and that made the revert one line each instead
   of a surgical unpick. This is the one thing that went right.
4. **A revert is cheap; a wrong model of the game is not.** "Ramps that
   already worked" beats "a tidier theory of ramps".

**Still open**: bots flying is *not* diagnosed. The cause is bot-only or
client-only, since players are unaffected. The untested suspects, in
order: `RemoteKarts` client interpolation (new that session, pure
rendering — fits "looks like it flies" while the server is fine), 75 Hz
sub-stepping, and the ledge/jump system. All three are bot-or-client, all
three were added the same session, none has been isolated.

### Two reasoned fixes in a row that don't land means stop reasoning.
"Bots move during the countdown" got two fixes derived by reading code —
the anchoring/authority one and the boost-suppression one. Both were real
bugs. Neither was *this* bug.

The third attempt shipped a diagnostic instead: distance moved sideways
while held, plus every value that could cause it (phase, speed, throttle,
steer, grounded, boosting, burning). It named the cause on the first run.

**The rule: after the second miss, stop inferring and go measure.** The
diagnostic cost less than either failed fix.

### Diagnostics beat guessing, but a diagnostic can lie.
The revive warning asserted "falling through the world, **not** driving
off it". It was driving off it. An assertion with no evidence behind it
sent us the wrong way for a session. Warnings should report *measurements*
— which side, how far off, how wide the road is there — not conclusions.

---

# 7b. The 2026-08-02 run — one feature, six bugs

Kept together rather than scattered, because the pattern is the finding.

### Destroying a thing means something has to rebuild it

Retiring a finished racer — destroying their kart and character — was
added to stop bots lapping the field after they finished. It caused, in
order:

1. **A respawn at the spawn point.** `CharacterAutoLoads` makes Roblox
   rebuild a destroyed character at a SpawnLocation, `CharacterAdded`
   fires, and `KartService` hands out a kart. The respawn was the
   engine's, not ours.
2. **A 0/1 deadlock.** `humanRacers` counted people by looking for a
   kart, so a retired player read as absent, the round fell to Waiting,
   and the only thing that hands avatars back runs on the way OUT of
   Intermission.
3. **A missing kart.** A taken-over kart joins `bots`; `fill` trims that
   list by destroying karts from the end.
4. **The race ending a lap in.** `finishers >= racerCount()` — a retired
   kart leaves the registry, so racerCount FALLS while finishers climbs.
5. **Ghost registry entries.** `fill` destroyed karts without
   deregistering them, and the dead-kart sweep sat below the bot skip.
6. **Detached rigs.** `Physics` state was used to stop a humanoid
   re-enabling CanCollide — and `Physics` is not `Seated`.

Every one was a real defect with a real fix. Every one was downstream of
a feature nothing needed.

**The rule: when a fix is downstream of something added in the last few
changes, question the addition.** It was deleted in the end, and the
deletion was smaller than any single fix.

### A watchdog must be slower than the path it watches

The no-kart sweep ran every two seconds; `onCharacterAdded` waits
`SeatDelay` then builds. The sweep declared a perfectly normal spawn
missing and rebuilt it underneath itself.

### Bots need every recovery rule a player has

Players get three ways out of the void: the `VoidZone` tag, freefall
time, and a world floor. Bots had only the floor — so a void that is a
PLANE at track level never triggered, and they drove through it and kept
driving outside the track until they happened to fall far enough.

They were not leaving the track once. They were leaving it and
continuing to drive out there. **Any rule that keeps a player on the
road has to be asked about bots too, from the same helper.**

### ApplyMesh can drop a part out of its assembly

A MeshPart whose geometry is replaced can come away unwelded and
unanchored. The kart drives perfectly while its bodywork drifts along
behind, because the hitbox is fine and only the visual came loose.

It is asynchronous — `CreateMeshPartAsync` fetches over the network — so
it lands AFTER the build has welded everything, which is why nothing in
the build path looks wrong.

**Re-assert assembly membership after any mesh swap**, and rebuild the
JOINT that part had: a road wheel welded back gives a kart that drives
with four locked tyres, which looks fixed until somebody turns.

### An identity must be intrinsic, not an attribute anything can clear

`releaseTakeOvers` keyed on the `AI_DRIVEN` attribute rather than on the
entry knowing it was a takeover. One stray write and a takeover was
stranded in `bots` forever — stepped every frame, accumulating one per
round, and leaving its kart anchored and server-owned.

That single fault produced three separate reports: a frozen camera (the
client's `step` returns early on `AI_DRIVEN`, and the camera updates
after that line), a kart welded to its player that would not move, and
"spectating is broken".

### Config keys are invisible to the type checker

`Config.Hud.WarnedText` deleted by a slice edit froze the camera.
`DodgeAt` written into the wrong config table errored sixty times a
second. Neither is visible to `luau-analyze`.

`scripts/config-keys.py` walks every declared alias and every direct
`Config.X.Y` read across the whole tree, and `scripts/check.sh` runs it.

### Instrument the loop, do not infer it

Six of the above were misdiagnosed at least once by reading code.
`Config.Match.LoopTrace` prints one line per phase change with the four
numbers that decide the next one, and it settled in a single round what
several sessions of reading had got wrong.

---

# 7c. The 2026-08-08 run — cosmetics, the glider, and guidance

One session, and almost every bug in it was the same species: a system
that was **guiding** something quietly turned into a system that was
**forcing** it, or a piece of state that nobody owned outright.

---

### Art is only cosmetic if the code that reads it says so.

Four separate wheels arrived as `FrontLeftWheel` **Models** holding a
`Rim` and a `Tire`. `KartFactory` only ever looked at `BasePart`s, so it
skipped the Models entirely and welded their contents to the hitbox as
scenery. Every wheel on the new kart was rigidly bolted to the chassis:
no spin, no steer, and nothing anywhere said so.

The Consistency Rule protects handling from art. It does not protect the
*cosmetic* pipeline from art being reorganised, and that pipeline has no
diagnostics of its own unless you build them.

**Anything that matches art by name or class must accept a container.**
Meshes get grouped. It is not a rare event.

---

### A comment that describes behaviour the code does not have is a lie with a fuse.

`KartFactory` said *"its children weld to the hub so they spin with it"*
and welded them to the hitbox. That was harmless for years because a
wheel was one bare part with no children — so the comment was never
wrong in practice, and it was never checked.

The first rig with children in a wheel detonated it. **A comment
describing an untested branch is untested documentation.**

---

### The right-hand rule is not optional, and the wrong sign is invisible.

Wheels spun backwards. The axle is the kart's `+X` (right), and a
positive rotation about `+X` carries the top of the wheel toward `+Z` —
but Roblox forward is `-Z`. Driving forward is a NEGATIVE rotation.

What made it survive review: **the wheels spun backwards at exactly the
correct speed.** It tracked acceleration, braking and reverse perfectly.
A wrong sign is the most convincing possible way to be wrong, because
every relationship still holds.

---

### `x ^ dt` is not a rate. It is a fraction kept, and at 60fps it is nearly 1.

Suspension damping was written `vel *= 0.82 ^ dt`, read as "keep 82% per
second". At 60fps that is `0.9967` per frame — very nearly no damping —
so the wheel oscillated indefinitely. It looked like a suspension bug and
was a units bug.

The framerate-independent form of "lose this much per second" is
`exp(-rate * dt)`. The same mistake had already been made once on the
drift scrub. **Every decay in the codebase should be greppable and every
one should be `exp` or `^dt` deliberately, never by accident.**

For springs, tie damping to stiffness rather than picking it: `damping =
2 * sqrt(stiffness) * zeta`, and state the zeta. Measured overshoot for
the kart: 0.45 → 19%, 0.60 → 7%, 0.75 → 1%.

---

### A cap is not a force. Something has to push against it.

Height correction on the glider saturated: raising the maximum sink rate
changed nothing at four different values. `sink` was only a CAP on how
fast the kart could fall, and gravity at 24 studs/s² was the only thing
accelerating it into that cap.

**Raising a limit nothing is pressing against does nothing.** The tell
was the numbers being *identical* across settings, not merely similar.

---

### A correction proportional to error is largest exactly where it is most felt.

Every version of the glider landing was error-driven — measure the
distance from the ideal, shove toward it. It always felt like being
grabbed, and no amount of retuning fixed it, because the shove is
biggest precisely when the player is furthest out and paying attention.

The fix was to stop correcting and start **flying an approach**:

```
sink = height above the target / time left to reach it
```

recomputed every frame from where the kart actually is. There is no
error term, so a disturbance becomes a slightly different slope instead
of a fight. This is what an aircraft does, and it is smooth by
construction rather than by tuning.

---

### Guidance that cannot be escaped is control, and it will be felt as control.

The glider ended up with three forcing mechanisms — a position funnel, a
dictated descent rate, and a heading clamp — each added to fix the
previous one's side effects. Together they were the reason it felt
wrong, and they were **257 lines that all came out again**.

Mario Kart gives you very little air authority for a very short time and
lets the LEVEL do the work. Research said so at the start and it took
five commits to trust it.

**When a guidance system needs a second guidance system to fix its side
effects, the first one is too strong.**

---

### Any guidance must release the moment its target is behind you.

Overshooting the landing pad whipped the camera round. It was not the
camera: the heading clamp keeps the nose within 55° of the target, and
past the pad the direction TO the target points BACKWARDS — so it
obediently turned the kart around. Measured at 235° of nose swing.

The funnel and the descent slope had the same bug in quieter form, both
computing against a target now behind. All three released through **one**
`glidePassed` helper; three separate copies of the same rule is exactly
how one of them gets left behind.

---

### A blend factor of 1 is a teleport.

`blend = 1 - (1 - weight) ^ (dt * 60)` reaches exactly 1 at full weight,
which erases the entire error in a single frame. That is not a strong
correction, it is a jump, and it reads as one.

**Rate-limit corrections in world units**, not just in blend factors. The
cap has to clear the fastest the target can legitimately move, or the
correction can never win — 75 studs/s here, because a 55° heading clamp
at 80 studs/s allows 65 studs/s sideways.

---

### A launch is not airborne until it says it is.

Hitting a glide ramp re-triggered every other frame: the launch kick
lifts the kart 0.77 studs in one frame, well inside `GroundSnap` of 3.0,
so the next ground probe still reported contact. The glide ended, the
ramp was still underneath, and it launched again — re-boosting
continuously and pinning the wings out.

The drift hop already solved this and the glide did not copy it:

```
HOP    vertVel = HopSpeed;  grounded = false;  hopUntil = now + HopMinAir
GLIDE  vertVel = LaunchUp   <- neither
```

**Any impulse that leaves the ground must clear `grounded` itself AND
refuse to believe a landing for a minimum time.** A kick is not enough;
the probe has a radius.

---

### Clear a published flag unconditionally; guard only the work.

`EndGlide` guarded its whole body on `state == STATE_GLIDE`. Anything
else that moved the kart out of that state — a respawn, a reset — left
the `Gliding` attribute true forever, and the wings with it.

**Flags that other systems read are cheap to clear and expensive to
miss.** Clear first, then return early.

---

### `LocalTransparencyModifier` is reset whenever `Transparency` is written.

The glider wings were hidden once, on a state change. `KartService`
writes `Transparency` across every kart part during the spawn fade-in,
which resets the modifier to 0 — so the wings popped visible on the next
spawn and stayed that way, because nothing set it again.

**Render-only overrides must be re-asserted, not set.** Cache the parts
and write every frame; a handful of property writes is far cheaper than
a bug that only appears after a respawn.

---

### Cache the authored value, because the live one is your own output.

Scaling the wings open reads the part's full size. Reading `part.Size`
back each frame would read whatever the animation last wrote, and the
wings would ratchet smaller on every deploy.

**Any animation that drives a property must own the baseline separately
from the property.** The same rule the transparency baseline follows in
`Props`, and the same rule `home` follows there.

---

### Derive a visual from the same source as the thing it describes.

Body roll is read entirely off the suspension the wheels already use.
Authoring it separately — from steering, from velocity — is the obvious
version and produces the uncanny one: a kart leaning left while its left
wheels are extended.

Deriving both from one source makes disagreement **impossible** rather
than merely unlikely. The same reason `lookFor` and `KartDress` had to
share a name list, and the same reason GapFill's preview and its commit
call one builder.

---

### The body moves against the wheels, not the wheels against the body.

The bodywork hangs off the hitbox on its own `Motor6D` and everything
non-wheel welds to THAT; the wheels keep their own motors on the hitbox
and never inherit the lean. Get that order backwards and the wheels
swing with the shell, which is the one thing real suspension never does.

Sign conventions, worked out once:

```
CFrame.Angles(0, 0, r)   about +Z (BACKWARD, since LookVector is -Z)
                         +X -> +Y, so positive roll lifts the RIGHT side
CFrame.Angles(p, 0, 0)   about +X (right)
                         +Y -> +Z, so positive pitch lifts the NOSE
```

Compression is positive — the wheel has been pushed UP into the arch,
so the ground is higher there and that side of the body rises with it.

---

### Scaling reads as deploying. Fading reads as a rendering bug.

A part that fades in looks like it was always there and the engine was
slow. A part that grows looks like it was put there on purpose. Add an
overshoot — `easeOutBack`, one extra term — and it looks *thrown* open:

```
f(t) = 1 + c3*(t-1)^3 + c1*(t-1)^2      c3 = c1 + 1
```

Resizing does not disturb a `Motor6D` built with `pivotJoint`, because
that joint is captured from the part's **CFrame**, and resizing moves
faces about the centre. Had the joint been derived from a face or a
corner, every deploy would have walked the wing sideways.

---

### Measure which end is the outside; do not assume it.

Wing-tip trails were placed at BOTH ends of each wing's long axis. That
is correct for one mesh spanning the whole kart and wrong for separate
left and right panels — on those, one end is INBOARD, so half the
ribbons streamed out of the middle of the bodywork.

Which case a rig is cannot be assumed, and the previous two attempts
(positive end only, then both ends) were each right for exactly one rig.
So it is measured: put a candidate at each end, see how far each lands
from the kart's centreline, keep the far one. **A tie means both ends
are outer edges** — which is precisely the full-width case.

```
left panel   (centre -5, half 4)    ends at 1.0 / 9.0   -> outer only
full-width   (centre  0, half 9)    ends at 9.0 / 9.0   -> both
```

The general form, and this is the third time it has come up on this rig:
**a rule that reads art must handle the shapes art actually takes.** Not
the shape it takes today.

---

### `Attachment.Position` is in local studs and does not follow `Size`.

Scaling the wings open broke the wing-tip trails. The attachments stayed
at the full-size tip offset while the part shrank to a speck, so at
scale 0.01 they sat nearly six studs outside a wing that was barely
there.

Anything positioned relative to a part's dimensions must be **rescaled
with it**, and the offsets have to be cached at creation for the same
reason the size is — the live value is the animation's own last write.

Second, quieter failure: **a Trail draws whatever its attachments do.**
Streaming while the wing grows smears the deploy itself into a ribbon.
Enable the trail only once the animation has settled, which is also the
only moment the tips are where the art says they are.

The general form: **an animation that moves geometry invalidates
everything anchored to that geometry.** Emitters, attachments, welds and
lights all have to be told.

---

### Reuse the event, not the asset.

The glide launch fires a real boost through `ApplyBoost` and reports
`boostFired` — the same event a drift release uses. The boost sound, the
boost VFX and the thruster flare were already wired to it, so all three
arrive for free and can never drift out of sync.

A bespoke "glide deploy" version of each would have been three more
things to keep aligned with the originals.

---

### Split what changes on different timescales.

Height and lateral correction shared one schedule and the result was a
choice between an accurate landing and a glider worth flying. Bleeding
90 studs of altitude takes seconds; lateral is fast and was already
bounded. Two schedules, and both problems went away.

---

### Sample the field at the POSITION, not the clock.

Water done as a sine of time alone gives a kart vibrating in place: it
bobs identically parked and at full speed, and two karts side by side
rise and fall in perfect unison, which reads as fake immediately.

A field `h(x, z, t)` means the swell exists in the WORLD. You drive
through it, you take it at an angle, and the kart beside you is on a
different part of the same wave. Same cost, completely different read.

Three directional waves at unrelated wavelengths and headings: one is a
ripple, two beat against each other, three stops the pattern being
findable.

**Pitch and roll come from the SLOPE of that field** — sample fore/aft
and left/right, and the difference IS the tilt. Deriving them from one
source means heave and tilt can never disagree about which wave the hull
is on. (The same rule as body roll off the suspension, and `lookFor`
sharing a name list with `KartDress`.)

---

### Deleting a block deletes everything in it, including what you still needed.

Stripping the real wave impulses out of `_updateSwim` took the
`seaClock` increment with them, because the increment happened to sit
inside the region being removed. `waveAt` then got `nil` for its clock
and threw sixty times a second.

**Cutting by region is not cutting by concern.** After removing a block,
the question is not "does it still compile" — it is "what else lived in
there". `check.sh` said ALL CLEAN, because a nil arithmetic is a runtime
fact and there is no static analysis that would have found it.

Cheap defence for the shape of thing that gets deleted: a function that
takes a clock should tolerate not getting one. A missing clock is a
wiring error either way, but it should produce a wrong-looking sea
rather than sixty log lines a second that bury everything else in
Output.

---

### Two clocks stepped by dt from different moments are not one clock.

Rider advanced its own `seaT` while Simulation advanced `seaClock`. Both
by `dt`, both every frame — and still not the same number, because they
started at different moments and one only ran while wet.

So the crest the hull was drawn riding and the burst meant to accompany
it were on different waves. The whole point of exporting `waveAt` was
one field; the clock has to be shared too, or it is two fields that
happen to use the same function.

---

### Rotate the thing they are attached to, not a list of the things.

The flip was first built as "apply this rotation to every Motor6D" and
missed a different part on each attempt: the bodywork, because the body
updater returned early when there was no body root; then the seat and
the DRIVER, because the seat hung off a WeldConstraint, which cannot be
animated at all.

Both were the same mistake. **A list of things to rotate can be wrong.
The thing they are all jointed to cannot be.** One line on the render
write turns the hitbox, the seat, the player, the bodywork and every
wheel together, and anything added later is included without opting in.

It is safe there specifically because that line is ALREADY the cosmetic
write — `pitch`, `lean`, `bob` and `squash` are visual offsets on top of
the true `pos`/`forward`/`up`, and the simulation reads none of them
back. The sweep and the ground probe build their own frames, so
collision is untouched however far upside down the art is.

It also deleted the cross-kart plumbing: a rotated CFrame replicates by
itself, so the attributes that existed to tell other clients about the
flip were never needed.

The general shape: **when a visual effect needs "all of X", look for the
node they hang from before enumerating them.**

---

### Never write a per-frame contribution into smoothed persistent state.

The wave tilt was added straight onto `s.bodyRoll` — which is a
PERSISTENT smoothed value — and then multiplied by `RollScale` on top:

```
bodyRoll = (bodyRoll + wave) * 1.6      every frame
```

So each frame added the wave to a number that already contained the
previous frame's wave, and scaled the lot. One degree became sixty in ten
frames, the smoothing yanked it back, and it climbed again. That
oscillation was the "snapping" — the wave field itself was fine.

**A contribution and a state are different things.** Give each its own
variable and its own rate, and combine them only at the point of use. A
multiplier belongs on the OUTPUT for the same reason: applied to the
state it compounds, applied to the output it scales.

The tell for this class of bug: a value that grows without any input
growing, and smoothing that makes it worse rather than better.

---

### An impulse smaller than the snap distance is a wasted impulse.

Wave launches were tuned to feel plausible and produced kicks of 1.8-3.0
studs/s. `GroundSnap` is 3.0 STUDS, which needs 30 studs/s to clear —
so the ground probe pulled the kart straight back on the next frame and
nothing happened at all.

**Any vertical impulse has to clear the snap distance or it does not
exist.** Either it is a real hop or it is not one; there is no small
version. The middle ground has to be done visually instead, which is
what the sprung heave is for.

So the launch became rare and real rather than constant and invisible:
0.5/sec cruising, 2.2/sec flat out, 2.6 studs high, 0.37s of air, with
the visual heave carrying the ride in between.

---

### A threshold with no proportional term above it is a cliff.

`rise > threshold` and then a fixed kick makes every launch identical,
so a wave that only just qualifies throws you exactly as hard as the
biggest one. Measuring the kick from the EXCESS above the threshold —
`(rise - min) * scale` — keeps the variety the threshold was filtering
for.

---

### A ceiling the system sits at is not a ceiling, it is the value.

The wave tilt was 26 degrees per stud against an 11-degree clamp, so
EVERY frame was clamped. Constant maximum tilt is not a rough sea, it is
a broken one — nothing varies, so nothing reads as motion.

Tuned by measuring how often the clamp fires, which is the only number
that matters here:

```
tilt/stud   frames clamped (moored / cruising / flat out)
   26         every frame
   14        21%   23%   23%
    9        2.7%  1.2%  0.6%   <- a backstop again
```

**Tune a clamped quantity by the clamp's hit rate**, not by the peak
value — the peak tells you nothing once it is pinned.

---

### Speed scales heave, not tilt.

Folding the speed multiplier into the wave TILT as well as the heave is
what kept it pinned however low the coefficient went. A faster boat
heaves harder over the same wave; it does not lie at a steeper angle to
it. Two effects that both felt like "more sea" turned out to be one that
was right and one that was wrong.

---

### Move the floor, not the movement code.

Swim mode is a floor at the waterline and nothing else. The kart drives
on it exactly as it drives on tarmac, so the sweep, the ground probe,
surface gravity, drift and the suspension all keep working unchanged —
from the controller's point of view nothing has happened.

The alternative, replacing the ground probe with a water plane and
buoyancy, is a **second movement mode**: its own ride height, its own
landing rules, its own bugs, and every future handling change now has to
be made twice.

The general form: **when a new mode can be expressed as different
geometry plus different dials, it should be.** New state in the
simulation is the expensive option and should be the last one reached
for. Compare the glider, which genuinely needed a state because gravity
and steering authority both change — and note that even there the
forcing machinery all came out again.

---

### A mode change should alter the silhouette, not just add particles.

The clearest signal that the kart has entered water is the wheels laying
flat. It reads from further away and faster than any effect, because it
changes the shape rather than adding to it.

Applied about the wheel's own FORWARD axis — the cross of the roll and
steer axes it already carries — so it lies over without disturbing
either, and both keep working underneath.

Two sines at unrelated rates for the bob, too. One reads as a machine;
two reads as water, for one extra term.

---

### A mode boundary must be a ramp, not a boolean.

Crossing a shoreline is a step change in top speed, and a step change in
top speed reads as hitting something. `swim` is a continuous 0..1 eased
at `BlendRate`, so every visual and every scalar fades together.

Use `Overlapping()` rather than `Touch()` for it: `Touch` answers "which
trigger did I just enter", which is right for a boost pad and wrong for
a state you are continuously in.

---

### Mid-drift, the stick does not mean "where the front wheels point".

Front-wheel counter-steer was ADDED to the player's steering, and at full
slip the two cancelled exactly: the tyres went from full lock to dead
straight and never crossed the centre. Which is the one thing opposite
lock is.

The error was treating the stick as a front-wheel command throughout. It
is not — on a straight it aims the kart, but mid-drift it means "how
much drift", and the front wheels are doing something else entirely:
catching the slide. **They crossfade as the slide develops rather than
summing.**

```
slip     summed        crossfaded
 0 deg   +26.0 deg     +26.0 deg
20 deg    +9.0 deg      -2.1 deg   <- crosses over
38 deg     0.0 deg     -18.2 deg
```

Corollary, and the same mistake one layer up: a damping factor on a
crossfade damps WHETHER something happens, not HOW FAR. Folding the
steering wheel's `WheelCounterSteer` into the blend stalled the driver's
hands at +8 degrees while the tyres were at -18 — hands and tyres
disagreeing, which that shared term exists to prevent. It belongs on the
term, not on the blend.

---

### One visual channel per fact, or the readout is ambiguous.

Drift trails encoded the TIER — how charged the drift is — in colour,
width and glow together. So a lazy 20-degree slide and a balanced
36-degree one on opposite lock looked identical, and the skill the
player was actually exercising had no readout anywhere.

Split: **colour is charge, width is slip angle.** Two facts the driver
needs at once, and sharing one channel makes a wide ribbon ambiguous
between "nearly boosting" and "sliding hard" — which call for opposite
inputs.

The general rule: if a player is controlling something moment to moment,
it needs its own channel. Counter-steering to hold a big angle was fully
modelled in the physics and completely invisible on screen, so it read
as a thing the kart did rather than a thing the player did.

---

### Two roles that look like variations of one idea usually are not.

The thrusters: the centre reads SPEED, the sides read BOOST and nothing
else. If everything glowed with speed there would be nothing left to
change when you actually boosted — the sides staying dark through a fast
lap is *what makes them land* when they fire.

---

### `check.sh` does not check `string.format` arity.

The rim/tyre rename left three `log()` calls with four `%s` and three
arguments, which errors at runtime. `ALL CLEAN` said nothing.

A ten-line audit over every `log(` in `src/` found them all. **Worth
re-running after any change to a data shape** — the same class as the
"luau-analyze misses missing methods" note above.

---

### A dial that is silently clipped is worse than one set wrong.

`LaunchBoostSpeed = 155` against `DiveSpeedCap = 140`. The boost was
quietly truncated, so the dial did not mean what it said and tuning it
did nothing. **Any ceiling must clear the fastest thing allowed to push
against it**, and that relationship belongs in a comment next to both.

---

### Argon deletes files you create while it is serving.

Two-way sync treats Studio as the source of truth. A file created on
disk that Studio has never seen gets removed on the next pass —
`Config/Suspension.luau` vanished four times. Files that are *edited*
are safe; only new ones are exposed.

`check.sh` catches it loudly because a missing config module fails hard.
The safe move when adding a config: write it and `git add` it in the same
command, so it is recoverable even if the working copy is eaten.

Also: Argon round-trips rename `.lua` to `.luau` and drop non-script
files. That is how Iris's `LICENSE.txt` disappeared. **Anything that must
survive a round-trip has to live inside a file that round-trips** — the
licence text now sits in a comment at the top of `init.luau`.

---

# 8. Open — stress test these

Current state: **works, still wonky.** Known-unresolved, roughly in
priority order.

### Smoothness
Not yet good enough. `RemoteKarts` interpolation is in but unproven under
load.

**Know which knob does what**, because this was got wrong once already:

| knob | affects |
|---|---|
| `Bots.StepRate` | integration accuracy. **Not smoothness.** |
| `Rig.RemoteSmoothing` | what you actually see |

Bot position replicates at roughly 20Hz *regardless* of `StepRate`, and
what a client renders is `RemoteKarts` interpolating between those
updates at its own frame rate. Raising `StepRate` to chase smoothness
buys raycast load and nothing visible.

Also: an accumulator that fires at most once per Heartbeat **silently
caps `StepRate` at 60** — 75 and 60 ran identically for a while. It
sub-steps properly now, with `MaxSubSteps` guarding the hitch spiral.

Open questions:
- Does `RemoteSmoothing = 14` hold up with 4 bots and a human?
- Does `RemoteSnapDistance = 30` ever mis-fire mid-race and cause a jump?
- Is `StepRate = 75` (≈25% more raycasts than 60) still fine at a full
  grid of eight? Watch server frame time, not the visuals.

### Boosts / nitro
Bot nitro logic **is** wired (`BotService.luau:836`: spends when
`tanks ≥ NitroMinTanks`, bend ≤ `NitroStraight`, not already burning) but
**has never been confirmed firing in play.** Verify before tuning. If it
isn't firing, suspect `sim.burnStage` or that bots never bank a tank
because they don't drift enough.

### Four bots on one line
`AvoidRadius`/`AvoidStrength` spread them laterally, but with four bots
and the line clamped to measured road width, they may stack into a queue
rather than a field. First thing likely to need tuning. `Bots.Debug`
shows it directly — each bot draws its own white aim line.

### Still unverified from the 12-layer plan
Ordered by payoff (full audit in `SPEC-bots.md`): **personality
archetypes**, **race director** (inputs only, never grip), **persisted
per-track learning**, tactical tick, named lines. Skipping raycast
vision, heatmap, opponent memory — reasons in the spec.

### Long-standing
- Missiles: much better, still hit scenery occasionally.
- Four items have no icon: Lightning, Scramble, FakeBox, Shield.
- Server-authoritative finish times — `MatchService.recordFinish` is the
  marked seam.
- `DataService` (currency, owned karts), the hub, rematch grouping.
- Record-a-lap racing line, which would kill manual checkpoint placement
  entirely.
