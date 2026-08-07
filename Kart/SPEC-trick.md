# SPEC — flip ramps

Hit a ramp, the kart throws a flip, you land with a boost. The Mario
Kart trick, and the reason it exists there: it turns every jump from a
gap you survive into a thing you *want* to hit.

- Config: `ReplicatedStorage/BloxKart/Config/Trick.luau`
- Launch + rotation: `Simulation.luau` — `StartTrick`, and the render
  write at the bottom of `Step`

---

## Setting one up

| step | what |
|---|---|
| 1 | Tag a part **`FlipRamp`**. Its **up is the launch direction** — aim it by rotating it in Studio, same as a glide ramp. |
| 2 | *Optional:* give the ramp a **`Trick` string attribute** (`frontflip`, `backflip`, `barrel`, `spin`, `double`) to force one. Without it, random. |
| 3 | Drive over it above `MinSpeed` (30 studs/s). |

`FlipRamp` is in `Triggers.TAGS`, so it is a launcher and never a wall.

---

## The flip is visual, and the kart lands level

**Nothing here rotates the simulation.** `up` and `forward` are
untouched, so the ground probe, the landing and the sweep behave exactly
as on any other jump — you come down level every time, however many
turns the art did.

Genuinely rotating the kart is a trap: the moment `up` is upside down,
surface gravity points at the sky, the ground probe looks the wrong way,
and a landing mid-rotation is undefined. All of that for something the
player only ever *sees*.

### It ends level by construction

The rotation is a **whole number of turns** spread across the expected
airtime, so at `t = 1` the angle is `turns × 2π` — which is the pose it
started in. It cannot land crooked however it is interrupted. Same
guarantee the props timeline gets, for the same reason.

Airtime comes from the arc (`2v/g`), not a fixed duration that would be
wrong on every ramp of a different height:

```
launch 62 studs/s, gravity 150
airtime 0.83s, apex 12.8 studs
flip window 0.68s — finishes 0.15s before touchdown
```

`Window` is under 1 deliberately. Landing mid-rotation reads as a crash
even when the maths is exact, because the eye wants the kart settled
before the wheels arrive.

---

## Rotate the root, not a list of parts

**This is the part worth remembering.** The flip was first built as
"apply this rotation to every `Motor6D`", and it missed a different part
on each attempt:

- the **bodywork**, because the body updater returns early when there is
  no body root
- the **seat and the driver**, because the seat hung off a
  `WeldConstraint` — which cannot be animated at all

Both were the same mistake. **A list of things to rotate can be wrong;
the thing they are all jointed to cannot be.**

It is now one line on the render write, and it turns the hitbox, the
seat, the player, the bodywork and every wheel together. Anything added
later is included without opting in.

Safe there specifically because that line is **already** the cosmetic
write — `pitch`, `lean`, `bob` and `squash` are visual offsets on top of
the true `pos`/`forward`/`up`, and the simulation reads none of them
back.

It also removed the cross-kart plumbing: **a rotated CFrame replicates
by itself**, so the attributes that existed to tell other clients about
the flip were never needed.

---

## The reward

Reported as **`boostFired`** — the same event a drift release uses — so
the sound, the VFX and the thruster flare all come for free and can
never drift out of sync with the originals.

Only fires if the flip **completed**. Landing early costs it, or the
ramp is a boost dispenser and the trick is decoration.

---

## Dials

| dial | value | decides |
|---|---|---|
| `LaunchUp` | 62 | how high, and therefore how long the flip has |
| `MinSpeed` | 30 | below this the ramp is just a bump |
| `MinAirTime` | 0.3 | stops the ramp re-triggering |
| `Tricks` | 5 entries | the shapes it can throw |
| `Window` | 0.82 | fraction of airtime the flip occupies |
| `Ease` | 1.6 | winds up and settles rather than spinning flat |
| `BoostSpeed` / `BoostTime` | 140 / 0.9 | the landing reward |

`axis` in a trick entry is in the **kart's** frame: X is its right (front
and back flips), Z its back (barrel roll), Y its up (flat spin).

---

## If it goes wrong

| symptom | cause |
|---|---|
| ramp fires repeatedly | the `grounded = false` + `MinAirTime` guard. A kick alone does not clear `GroundSnap` in one frame — the glide ramp learned this first. |
| only part of the kart rotates | something is not jointed to the hitbox. The flip turns the assembly, so anything separate is a rig problem. |
| lands crooked | should be impossible — the angle at `t=1` is a whole number of turns. If it happens, `trickTurns` is not an integer. |
| no boost on landing | `RequireLanding` — the flip did not complete before touchdown. Raise `LaunchUp` or lower `Window`. |
