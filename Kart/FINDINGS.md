# FINDINGS — what BloxKart has taught us so far

An engineering log, not a spec. Everything here cost real debugging time,
and most of it is the kind of thing that gets silently re-broken by a
reasonable-looking change six months from now.

Rule for adding to this file: **write down the mechanism, not the fix.**
"Anchored the hitbox" is worthless in a year. "Exactly one thing may own
a part's position" survives.

---

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
