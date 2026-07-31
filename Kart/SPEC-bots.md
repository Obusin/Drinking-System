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
