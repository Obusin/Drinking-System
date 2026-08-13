# SPEC — bots

## They plateau. That is the design.

**No, they do not keep getting better the more you play.** Every counter
is capped and the speed bonus has a hard ceiling, so learning converges
and then stops:

| clean passes | confidence | corner limit used |
|---|---|---|
| 1 | 1% | 88.1% |
| 30 | 30% | 91.3% |
| 60 | 60% | 94.5% |
| **90** | **90%** | **97.9%** |
| 300 | 90% | 97.9% |

**Ninety clean passes and a corner is fully learned.** Everything after
that changes nothing, and a corner they *always* get wrong saturates
too, so no stretch accumulates unbounded fear either.

### They learn from players too

A person carrying speed cleanly through a corner is **proof it works**.
Bots spend ninety laps discovering what a good driver demonstrates on
their second, so a clean player pass counts for several bot ones
(`LearnPlayerWorth`).

**OBSERVED ON THE SERVER, never reported by the client.** The kart's
position replicates anyway, so the route position is computed
server-side and there is no message to forge.

That distinction is the whole safety argument. This feeds behaviour that
gets **saved** — a client-reported version would let one modified player
teach every bot on the server to drive into a wall, permanently. The
player's `Simulation` runs on their own machine and owns their hitbox;
nothing it says is trusted here.

It watches for three things, the same three bots report about
themselves:

| observed | learned |
|---|---|
| crossed a node cleanly, unboosted | **clean pass**, worth several bot laps |
| position jumped a long way backwards | **went off** — they were put back |
| took far longer than the segment should | **slow** — bots stop being clever there |

The backward jump is the neat one: a respawn needs no client message,
because the position change *is* the report. Guarded against the lap
wrap, which is also a large negative step and means the opposite.

Two filters:

- **boost disqualifies the crossing** — a player through a corner at 160
  on a nitro is not proof the corner is takeable at 160, and crediting it
  would teach bots to arrive somewhere they cannot physically turn
- credited into the **same counter** as bot experience, not a parallel
  channel — a second channel needs its own ceiling, decay and collapse
  rule, and the two can then disagree about one corner

And the physics clamp is the backstop: confidence only ever raises the
corner margin **toward** `vLimit`, which is derived from the kart's own
steering model. Even a wildly wrong observation cannot ask for a corner
speed the kart could not hold.

### Watching it happen

`botbrain` on the F4 console draws a bar:

```
[############--------] 62% learned · learning ON · saved to bots_v1_… ·
41 node(s) · 87 incident(s) · 512 clean
```

Averaged over every node the path **has**, not every node with a row —
otherwise one fully-learned corner on an untouched track reports 100%.

### A respawn loop is not a difficult corner

Sometimes a bot comes back, fails immediately, comes back again, and
keeps going. Every cycle reports the **same node**, so within a minute
one stretch has fifty incidents against it and the brain concludes the
corner is lethal — when what is broken is the place it is being *put
back*, which may be inside geometry, under the road, or facing a wall.

That is the data being corrupted by the recovery rather than by the
track, and the damage is durable: a poisoned node vetoes drifting and
tames the line for every bot, permanently, from evidence that describes
a bug.

Three failures at one node inside `ReviveLoopWindow` and it:

- **stops recording** — a loop teaches nothing true
- **moves the recovery point** `ReviveLoopSkip` nodes further along
- says so in Output, naming the node to go and look at

### It is kept per map, and per Studio

Keyed on `game.PlaceId`, so every place learns separately and nothing
carries over from a track with different corners in different places.
Sunset Circuit's brain is Sunset Circuit's alone.

Studio uses its own key (`..._studio`). A build session is not a race —
you drive bots into walls on purpose, half the track does not exist yet,
and you restart mid-lap twenty times an hour. All of that is evidence and
all of it is wrong.

### EDITING THE PATH DISCARDS IT, on purpose

A node is identified by its **index along the path**, not by its authored
`Order` — `math.floor(u)` is a position in a sorted array. So inserting
one `BotPath` node in the middle shifts every node after it, and every
lesson past that point silently reattaches to the **wrong corner**.

While a map is being built that is not an edge case, it is Tuesday. And
it fails *quietly*: bots would drive one corner cautiously because of
something that happened somewhere else, and nothing would look broken.

So the node count is stored with the learning and checked every round.
Change the path and the brain is discarded rather than misapplied, with
a line saying so. **Moving** a node is fine — indices do not shift —
which is why the count is enough.

`botbrainwipe` on the F4 console does it by hand.

### What confidence actually buys

**Margin, not speed** — and it cannot be otherwise. A naive bot aims at
88% of the corner's physical limit because it needs steering left over
to correct with; one that has never got that corner wrong runs to 99%.

A speed *multiplier* was the obvious reading and it is a trap: 0.9 there
would ask a 50-stud corner to be taken at 161 studs/s when the kart tops
out at 85 — the bot would understeer into the wall, faster than before.
**The limit is physics and no amount of learning moves it.**

| radius | limit | naive (0.88) | learned (0.99) |
|---|---|---|---|
| 200 | 173 | 152 | 171 |
| 80 | 114 | 100 | 113 |
| 50 | 85 | 75 | 84 |

12.5% more corner speed everywhere, worth seconds a lap, and still
inside what the kart can actually turn.

**One incident at a node returns it to zero.** Ninety laps to earn, one
mistake to lose.

The ceiling is the shape of the arithmetic, not a tuning value:

- `LearnMax` (25) caps every counter
- `LearnConfidenceMax` (0.12) caps the speed bonus
- confidence collapses to **zero** on any meaningful incident rate —
  slow to earn, instant to lose
- `LearnDecay` (0.98) ages evidence, so a corner you widen is forgiven

So a server that has run your track five hundred times fields bots
roughly 12% quicker through corners they have never once got wrong, and
that is the end of it. **They converge on "clean and quick", not on
"unbeatable".**

They also gain nothing a player does not have — same grip, same speeds,
same road. They just choose better.


## Bots drive `BotPath`, not `Checkpoint`

**Checkpoints are validation geometry.** They prove a lap, so they are
placed to be impossible to miss — wide, sparse, and routinely hanging
over the edge of the road. That makes them a poor *driving* line, and it
was most of why bots looked stupid: they were following the officiating
rather than the road.

Tag parts **`BotPath`** to describe where to actually drive. Same `Order`
attribute, same trailing-digit fallback, same fork support. Put down as
many as you like — more nodes is a smoother line, and unlike a checkpoint
a dense one costs nothing.

**Leave none tagged and bots fall back to the checkpoints**, so an
existing track keeps working untouched.

Everything else — progress, standings, missiles, respawn, lap validation
— still means `Checkpoint`. `Route.nodes()` is the gates; `Route.path()`
is the line.

### One lap rule for everyone

Placement sorts on a single packed score, so bots and players have to be
answering the same question. They were not.

| | lap rule | progress packed |
|---|---|---|
| player (before) | finish line + 80% of route | `cpPassed` (0–24) |
| bot (before) | every path node index **in order** | `floor(u)` (0–61) |
| **both (now)** | **finish line / start node + 80% of route** | **`floor(u)` on the path** |

Two bugs lived in that gap. The scores were **different quantities on
different rulers**, so a denser path made bots outrank players for free.
And the bot rule needed 61 exact index hits per lap — one miss from a
knock, a respawn, or a windowed `nearestU` stepping over it and the
counter stalled, so a bot driving perfectly sat a whole lap behind.

That was the placement being wrong, and it was never about the driving.

### The five things that were making them look stupid

All root causes, none tuning. Recorded because each one presented as
"the bots are bad" and none of them was a bad driver.

**1. No racing line.** It was a random bias per bot plus a sine wander —
a personality, not a plan. It took no notice of where the corners were,
so a bot would sit outside through an apex and cut the exit for no
reason. Now it is geometric: outside in, apex, run wide out, read off
`Route.curvatureAt`, which is signed so `sign(k)` is already "which side
is the inside".

**2. Corner braking ignored speed.** `throttle = 1 − bend × CornerBrake`
lifted by how SHARP a corner was and never asked how FAST the bot was
going, so a kart at 95 and one at 40 got the same lift. And this kart
has a hard limit — at 95 it can only hold an 86-stud radius, so a
50-stud hairpin is *impossible* at speed. They arrived at corners they
could not physically turn through.

The kart's own model gives the limit with no grip constant to invent:

```
turn(v) = TurnRate + (TurnRateTop − TurnRate)·v/MaxSpeed
v ≤ TurnRate / (k + (TurnRate − TurnRateTop)/MaxSpeed)
```

It only bites when genuinely over — below the limit they are flat out,
which fixes the other half of the old rule.

**3. Ramps never fired.** `bot.jumping` means "the route crosses a gap",
but a FlipRamp is usually a bump on solid road — so no throttle override
applied, the bot read the approach as a bend, lifted, arrived under
`Trick.MinSpeed` and drove over a launcher that did nothing. They were
never *starting* a trick, let alone failing one.

**4. Boost pads did nothing.** `Boosters` lives in StarterPlayerScripts,
so it is client-only and the server never ran it. On any track with pads
bots were slower than a player for reasons unrelated to driving.

**5. Respawns sent them miles back.** `safeU` only updated while
`|offset| <= room`, and in a tube `room` is measured by rays that hit the
wall curving upward — so a bot is never "safe" for the whole tunnel,
`safeU` freezes at the entrance, and a fall at the far end returns it to
before the tunnel. It was never about where they fell; it was about the
last point that qualified. Now it asserts `Route.hasGround`, which is
the thing actually being claimed.

### Why they circled

They were never orbiting a node. `Route.nearestU` took the **global**
minimum over the whole lap, every frame — and on a big track the line
passes near itself: a hairpin, a bridge, two straights side by side. The
nearest point flips to a distant stretch, `u` jumps, the bot turns to
chase it, the flip reverses. **Oscillation between two equally valid
answers**, which from outside looks like driving in circles.

Sparse nodes make it worse, because the spline bulges further from the
road between them and there is more chance some other stretch is closer
than the one you are on.

The per-frame call now passes the previous `u` as a hint, so the search
is a window (`RouteSearchSpan`, 1.5 nodes) and `u` cannot teleport.
Everything else — respawn, grid placement, recovery — stays global on
purpose: those genuinely do not know where they are, and a window round
a stale `u` would strand them.

It is also much cheaper. Global was `n × 8` spline evaluations per bot
per frame:

| nodes | global | windowed | |
|---|---|---|---|
| 30 | 121k/s | 18k/s | 7× |
| 60 | 236k/s | 18k/s | 13× |
| 120 | 467k/s | 18k/s | 26× |

Which matters now that a dense path is the recommended way to lay one
out. The window is 1.5 nodes against ~0.006 nodes of travel per frame on
a long segment — hundreds of times more headroom than needed, and still
13× on an 8-stud segment.

**A second bug hid in the same function.** Its refine pass called
`Route.pointAt(u)` without the node source, so a bot searching the
`BotPath` indexed path nodes while measuring distance against the
**checkpoint** spline. Introduced when the second source was threaded
through, silent, and invisible to the type checker.

### It is never solid

`BotPath` is in `Triggers.TAGS`, so it is out of the kart's movement
sweep **and** out of Route's own ground probes — which matters, because a
dense path would otherwise have nodes dropping onto each other.

The server also forces `CanCollide`, `CanTouch`, `CanQuery` and
`CastShadow` off on every tagged part, and on anything tagged later. The
tag list alone is not enough: a player on foot, a dropped item, or any
raycast not using the shared exclude list still sees a solid part. And
since there is every reason to place these densely, leaving them solid
litters the road with invisible walls.

**`CanQuery` is the flag that hides it from raycasts** — `CanCollide`
only stops things resting on it. Route finds these by tag, never by ray,
so nothing needs it.

**Transparency is deliberately left alone**, so whether you can see your
own path while building is your call.

### Forks

**Two parts sharing an `Order` is a split**, not one wide gate. The node
keeps both as `branches`; `position` stays the centroid for anything
needing a single reference.

This was the bug: the centroid of a left way and a right way is the wall
*between* them, and every bot drove at it. Each bot now commits to one
branch, randomised per bot so the field spreads, re-rolled each lap so
the same bot does not take the same line all race.

Widths are measured **from each gate**, not from the centroid — which on
a fork is not road at all.
 you can't pick out of a field

Where the AI is, what still gives it away, and the order to fix it in.

---

## The rule everything else hangs off

**A bot drives the kart you drive.** Same `Simulation`, same five inputs,
same physics. No hidden grip, no private top speed, no cornering the kart
can't do.

This isn't purity for its own sake. The usual way to make bots
competitive is to cheat their handling, and it always shows: they hold
lines no player can hold, and losing to one feels arbitrary rather than
earned. Everything below makes bots *better drivers* or *more human*, and
nothing below makes their kart faster.

If a change would need the bot's kart to behave differently from yours,
it's the wrong change.

---

## What actually gives a bot away

Roughly in order of how quickly a person spots it.

| # | Tell | Status |
|---|---|---|
| 1 | Perfect, instant input | **done** — reaction lag, deadzone, drifting bias |
| 2 | Reacting to corners instead of anticipating them | **done** — drifts are planned ahead and committed |
| 3 | Weaving down straights | **done** — PD damping; P alone always oscillates |
| 4 | Never makes a mistake | *open* |
| 5 | Doesn't race *you* — ignores who's next to it | *open* |
| 6 | Identical between bots | partly — skill and line bias vary, style doesn't |
| 7 | Recovers from a spin perfectly | *open* |

Note what's **not** on the list: the racing line. Bots have followed a
decent line for a while, and it was never what made them read as bots.

---

## 4. Mistakes

A driver who never errs is the clearest tell left, and it's the cheapest
thing to add convincingly.

Not random spinouts — **plausible** errors, the kind you'd forgive
yourself for:

- **Missed braking point.** Lift late into a corner, run wide, correct.
  Costs a length or two.
- **Botched drift.** Enter too early or hold too long, straighten up
  badly, lose the exit.
- **Target fixation.** While chasing someone close, briefly hold their
  line rather than the racing line — the mistake a real player makes
  constantly.

Rate scales inversely with skill, and each one should cost time without
being fatal. A bot that spins out unprompted looks broken, not human.

---

## 5. Racing you, not the track

The biggest behavioural gap. Right now a bot drives the same lap whether
it's alone or three-wide into a hairpin.

- **Defending.** Leading and pressured: hold the inside line into a
  corner, which is slower and correct.
- **Overtaking.** Faster than the kart ahead: pick a side, commit, take
  the alternative line rather than sitting in its slipstream.
- **Backing out.** Half-alongside and running out of road: lift. A bot
  that never yields is a bot.
- **Item pressure.** Someone close behind holding something: defend by
  weaving slightly, or spend an item to break the tow.

This is what turns a moving obstacle into an opponent, and it's the
single biggest remaining item.

---

## 6. Personality

Skill varies; *style* doesn't. Two bots at 0.7 drive identically.

Give each a persona rolled at spawn, each a different trade rather than a
different level:

| | drives like |
|---|---|
| **Aggressive** | brakes late, drifts everything, makes more mistakes |
| **Smooth** | early on the brakes, rarely drifts, very consistent |
| **Erratic** | wide skill swings lap to lap, unpredictable lines |
| **Defensive** | slower alone, very hard to pass |

Cheap to build — they're weightings on numbers that already exist — and
it stops a grid feeling like one bot copy-pasted.

---

## 7. Recovery

After a spin a bot resumes perfectly. A person is rattled: rejoins
cautiously, over-corrects for a corner or two, sometimes rushes and makes
it worse. A few seconds of degraded skill after any incident.

---

## Deliberately not doing

**Rubber-banding.** Speed that scales with your position is the thing
players resent most, and they always notice. Difficulty belongs in
*tiers* chosen before the race, not in a rubber band during it.

**Machine learning.** Reinforcement learning needs thousands of offline
episodes, can't train at runtime, and produces something you cannot tune:
when a trained bot corners badly there's no line to change, only a
retrain. Everything above is a handful of numbers you can reason about.

The useful half of "learn from a human" is **recording a lap as the
racing line** — that's a day's work, kills the checkpoint-placing chore,
and is worth doing on its own merits.

---

## Order

1. **Mistakes** — biggest gain per line of code
2. **Racing you** — biggest gain overall, and the most work
3. **Personality** — cheap, makes a grid feel like a grid
4. **Recovery** — polish

Test the same way throughout: watch a replay and try to pick the bot out.
If you can, the reason is on the table above.

---

# The twelve-layer plan, audited

Mark's layered design, checked against what's actually in the repo. Kept
as a scoreboard because the useful information isn't the list — it's
which entries are already done, which are cheap, and which cost real time
for something nobody will notice.

## Already built

**Layer 2 — car controller.** This is the whole architecture and it's
been true since bots existed. `BotService` writes a controls table;
`Simulation` reads exactly five fields off it and cannot tell a bot from
a keyboard. Bots have no separate physics, no speed bonus, and no ability
to corner harder than the kart allows. Everything else on this list is
only worth building *because* this is true.

**Layer 1 — racing line with lookahead.** `Route` is the line;
`LookaheadBase`/`LookaheadPerSpeed` aim up the road rather than at the
node underfoot. `LineCorrect`/`LineDamp` hold the line without weaving.

*But the waypoints are dumb.* They store position, nothing else. Every
frame the bot re-derives the bend ahead and re-decides its speed. Mark's
version — each node storing **recommended speed, brake distance, drift
yes/no, lookahead** — is better for two reasons: the decision is made
once instead of sixty times a second, and it gives Layer 8 somewhere to
write. **This is the prerequisite for half the list and should go first.**

**Layer 3 — skill stats.** Exists, but as *one scalar*. `Skill` scales
reaction, line error, drift odds and corner speed together. Splitting it
into named axes is Layer 6's job, below.

**Layer 7 — intentional mistakes.** Partly. `SteerNoise`,
`ThrottleJitter`, `SteerDeadzone` and `ReactionTime` are all in and all
tuned to be human-shaped rather than random-per-frame. Missing: the
*discrete* mistakes — a botched drift, a missed braking point, a
forgotten nitro. Those are the ones you actually see.

## Worth building, in this order

**Layer 6 — personality.** Highest visible payoff per line on the entire
list. One scalar makes a grid of bots that are the same driver at
different volumes; named archetypes make a grid that feels like people.
Coward / Aggressive / Speedrunner / Chaos / Rookie is the right set, and
it's a table of multipliers over numbers that already exist.

**Layer 12 — race director.** Cheap, and it's what makes a race feel
close. The spec above says "deliberately not doing rubber-banding" and
that still stands *for handling* — a bot must never get grip or top speed
it hasn't earned, because that's the version players resent and always
detect.

What a director may touch: **inputs and decisions.** A bot 20 seconds
clear lifts a little earlier, takes fewer drifts, spends nitro lazily. A
bot far back drives closer to its own limit. That's a driver easing off
or pushing — not a car that changed. Cap it, and cap it visibly in
config, or it becomes the thing it was excluded for.

**Layer 8 — adaptive optimisation.** The best idea in the list, and
correctly *not* machine learning: record entry speed and outcome per
corner, back the speed off after a crash, keep the gain when a drift is
faster. It's a hill-climb over a handful of numbers, it's debuggable, and
it needs Layer 1's waypoint table and nothing else.

**One caveat that decides the design:** a race is three laps, so a bot
gets *two* attempts per corner. That is not enough to converge on
anything. Either the learned table persists across races (per track, in
`DataService`), or this is a feature nobody will ever observe. Persist
it — and then a track's bots genuinely are faster in week two.

**Layer 5 — tactical tick.** Item and overtake decisions on a ~0.2s
cadence rather than per-frame. Currently only item use has a delay. Cheap
and tidies up where decisions live.

**Layer 11 — named lines.** `LineOffset` already wanders, which covers
most of it. Naming lines — inside / outside / recovery — and switching
deliberately is a real upgrade for defending and overtaking, and it's the
natural partner to §5 "Racing you, not the track".

## Not worth it

**Layer 4 — raycast vision.** The instinct is right: bots shouldn't have
information a player couldn't have. But a fan of rays is a lot of work
for something invisible, because **what gives a bot away is reaction
time, not sensing method**. A bot that queries a hazard list and then
waits `ReactionTime` before responding is indistinguishable from one that
saw it — and it can't get stuck because a ray happened to miss.

Worth keeping from this layer: bots should only react to things *ahead
and in range*, which is a cone test, not a raycast fan.

**Layer 9 — heatmap.** This is Layer 8's data indexed by grid square
instead of by corner. If waypoints record their own outcomes, the heatmap
is the same information stored twice — and the corner is the more useful
key, because that's what a bot actually decides about.

**Layer 10 — opponent memory.** Genuinely fun, and nobody will notice. It
needs many races against the same player to gather anything, and the
resulting behaviour change is a small bias on a decision that's already
noisy. Revisit if bots ever become the main attraction.

## Scoreboard

| Layer | State | Verdict |
|---|---|---|
| 1 Racing line | line yes, waypoint data no | **do first** — unblocks 8 |
| 2 Car controller | done | the foundation |
| 3 Skill | one scalar | absorbed into 6 |
| 4 Vision | no | skip; keep the cone test |
| 5 Tactical tick | items only | cheap tidy-up |
| 6 Personality | no | **best payoff** |
| 7 Mistakes | continuous yes, discrete no | finish it |
| 8 Learning | no | **best idea**; needs persistence |
| 9 Heatmap | no | redundant with 8 |
| 10 Opponent memory | no | defer indefinitely |
| 11 Dynamic line | wander only | pairs with §5 |
| 12 Race director | no | cheap; inputs only, never grip |
