# SPEC — Banked nitro (IMPLEMENTED)

Replaces the automatic drift boost. Drifting now **banks** into a tank;
the player chooses when to spend it and how hard.

## Why

The old loop paid you automatically: drift, release, boost. No decision.
Banking turns it into one — save for the straight, dump it to defend a
corner, spend early to get out of traffic. It also makes the nitro tank
on the HUD load-bearing, where before it filled and emptied inside a
single drift and was effectively decoration.

## Flow

**Three discrete tanks.** Drifting fills them one at a time,
continuously — you watch a tank climb as you hold the slide rather than
being paid a lump on release.

```
drift ──────► tank 1 fills ──► tank 2 ──► tank 3     (~1.8s each)

tap SHIFT ──► commits ONE tank, lights stage 1
tap again ──► commits another, steps to stage 2
tap again ──► commits a third, stage 3
```

So "one shift, two shifts, three shifts" is literally how many tanks
you're spending. Each burn runs on a timer rather than a drain rate.

## The stages are deliberately inefficient

| Stage | Speed | Duration | Tanks | Per-tank value |
|---|---|---|---|---|
| 1 | +18 | 4.0s | 1 | **72** — cruise |
| 2 | +45 | 2.6s | 2 | **58** |
| 3 | +80 | 1.6s | 3 | **43** — burst |

Three separate stage-1 burns carry you furthest. A stage 3 wins you one
specific moment and you pay for it. **Peak power has to cost total
distance** — otherwise you'd always dump everything and there'd be no
decision. If you retune, keep per-tank value descending or the stages
become cosmetic.

Discrete tanks rather than a continuous bar because you can **count**
them. "Have I got enough for a stage 2?" is a peripheral-vision question
mid-corner; reading a percentage isn't.

## Input

Tap to commit a tank. No hold, no timing window — escalating just costs
another tank, and the burn ends on its own timer.

Taps are **queued** in `Input` and consumed one per frame by
`Simulation`, so a fast double-tap spends two tanks rather than being
collapsed by whichever frame sampled the key. Taps with no tank
available are consumed and discarded, or they'd fire later the instant a
drift banks — a burn nobody asked for.

Bound to `LeftShift` / `RightShift` / gamepad `ButtonL2`.

## Decisions taken

- **Drift release gives no instant kick.** Pure banking. Paying twice
  would make the reserve redundant. The drift still feels rewarded
  because the tank visibly fills *while* you hold it, and each tank
  clicking over plays a note.
- **Boost pads stay instant.** They're a positional reward; making them
  fill the tank means you can't use one when you're already full. A pad
  stronger than the current burn wins; otherwise the burn does.
- **Overflow is wasted** (`AllowOverflow = false`). Once all three are
  full, further drifting banks nothing. Spend-it-or-lose-it pressure
  rather than hoarding.
- **Can't burn below `MinBurnSpeed`** (8 studs/s), so you can't dump a
  full tank into a standstill.

## HUD

Three cells, one per tank. Full tanks sit at 100%; the one currently
being drifted into shows its partial fill, so progress is visible rather
than snapping empty-to-full. While burning the tank wears the **stage**
colour and the label reads `N2O 1/2/3`. The rim pulses when all three
are full (spend me) and throughout a burn, faster at higher stages.

The speedo's top-end scale is derived from `MaxSpeed + best stage` or
the fastest pad, whichever is higher, so the needle never pins.

## Files

| File | Role |
|---|---|
| `Config/Nitro.luau` | capacity, tier yields, stage table |
| `Simulation` | owns `nitro` / `burnStage`; banks, drains, applies speed |
| `Input` | Shift binding, `consumeNitroTap()` |
| `SpeedHud` | tank as reserve, stage readout |
| `init.client` | dispatches `nitroBanked` / `nitroStage` / `nitroEmpty` |

## Numbers are placeholders

A nitro economy is **lap-scale**, not moment-scale: the right capacity
depends on track length, how often you can drift, and whether you're
chasing or defending. These were set by feel on a test track. Retune
once there are real races.
