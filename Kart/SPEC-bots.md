# SPEC — bots you can't pick out of a field

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
