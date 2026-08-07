# SPEC — swim mode

The kart on water. **There is no buoyancy, no water plane and no second
movement mode.**

- Config: `ReplicatedStorage/BloxKart/Config/Swim.luau`
- State: `Simulation.luau` — `_updateSwim`, `Simulation.waveAt`
- Visuals: `KartClient/Rider.luau` — `updateRoadWheels`, `updateBody`,
  `updateGliderFx`
- Audio: `KartClient/Audio.luau` — `Audio:Splash`

> **Status 2026-08-08:** handling works, visuals are wired but not
> visibly landing, audio is refused by Roblox. See `BUGS.md` #31–#33.

---

## The idea

**You put an invisible floor at the waterline and the kart drives on it
exactly as it drives on tarmac.**

That is the whole design. The sweep, the ground probe, surface gravity,
drift and the suspension all keep working unchanged, because from the
controller's point of view nothing has happened. Everything else is
decoration on top.

The alternative — replacing the ground probe with a water plane and
buoyancy — is a second movement mode with its own ride height, its own
landing rules and its own bugs, and every future handling change would
then need making twice.

The Consistency Rule holds: `Simulation` still reads only the `Hitbox`
and the `Seat`.

---

## Setting one up

| step | what |
|---|---|
| 1 | Build a floor at the waterline. Ordinary geometry; the kart drives on it. |
| 2 | Tag the water **volume** `SwimZone`. The body of water, not its surface — overlap is what matters, so make it as deep as the water looks. |
| 3 | Drive in. |

`SwimZone` is in `Triggers.TAGS`, so it is a marker and never something
the kart can hit.

**No Roblox terrain water is involved anywhere.** Detection is an
include-filtered `GetPartBoundsInBox` against tagged parts. Your visible
water can be a translucent part, a MeshPart, or nothing at all.

---

## Two halves, and they fail independently

```
Simulation  ──  detects the zone, changes speed, blocks drift
            └── publishes  Swimming / SeaClock / WaveRise

Rider       ──  reads those attributes and draws EVERYTHING
                wheels sideways · bob · tilt · bursts · yaw · sounds
```

This split is worth knowing when debugging: **handling working proves
nothing about the visuals.** They share only three attributes.

| symptom | half |
|---|---|
| speed drops, no drift | Simulation — runs regardless |
| wheels lie over, hull bobs | Rider — needs the whole gate in `updateKart` |

---

## Handling

Every dial is a **scalar on something that already exists**, so retuning
the kart retunes the boat and the two can never drift apart.

| | tarmac | water |
|---|---|---|
| top speed | 95 | ×0.78 |
| acceleration | — | ×0.7 |
| steering to full lock | 0.32s | **0.93s** |
| turning circle | 50 studs | **81 studs** |
| drift | yes | **disabled** |

The **steering delay is the biggest cue by a distance**. A kart answers
the stick instantly; a hull leans on the rudder and comes round a moment
later, and hands read that long before any visual does.

Drift is properly off: blocking new ones is not enough, so a drift
carried in off the tarmac is **ended** rather than left sliding on a
surface that cannot grip.

`swim` is a continuous **0..1**, not a boolean — crossing a shoreline as
a step change in top speed reads as hitting something.

---

## The sea

A wave field `h(x, z, t)`: three directional sines at unrelated
wavelengths and headings.

**Sampled at the kart's POSITION, not just over time.** That is the whole
difference between water and a vibrating kart — the swell exists in the
world, so you drive through it, take it at an angle, and the kart beside
you is on a different part of the same wave. A sine of time alone makes
every boat bob in unison.

- **Heave** is *sprung* against the surface, not welded to it. The
  overshoot is the bounce.
- **Pitch and roll are the SLOPE of the same field** — sampled fore/aft
  and left/right, and the difference *is* the tilt. One source, so heave
  and tilt can never disagree about which wave the hull is on.
- **Bursts** are the kick over a crest: visual lift plus a nose-up pitch,
  which **decays** rather than tracking, so each crest is an event with a
  shape.
- **Yaw wander** — a kart's nose never moves on its own; a hull's does
  constantly. Probably the strongest "not tarmac" cue there is.

**One clock.** `Simulation` owns `seaClock` and publishes it; `Rider`
reads it rather than advancing its own. Two clocks stepped by `dt` from
different moments are not one clock, and the crest the hull is drawn
riding would be a different wave from the burst meant to accompany it.

### Real impulses were tried and removed

They are a dead end in **both** directions:

- under `GroundSnap` (3.0 studs, needing 30 studs/s) they are swallowed
  by the ground probe and do nothing at all
- over it they are a literal jump — the kart leaving the surface, which
  is not what a boat does

**The feel is in the rotation.** A hull crossing a swell pitches, rolls
and yaws far more than it rises. Height alone is a lift; angle is a sea.

---

## The wheels

Lie over **82°** and spin at **45%** — paddles, not tyres. This is the
clearest mode signal because it changes the kart's *silhouette*, which
reads from further away and faster than any particle.

**Mirrored per side**, tops toward the centre. One shared angle tilts
every wheel the same way, which leans one pair in and the other *out* —
a kart falling over rather than a hull. The sign, derived once:

```
fwdAxis = rollAxis × steerAxis = (kart +X) × (kart +Y) = +Z
rotation about +Z sends +Y toward −X, leaning the wheel top LEFT
→ RIGHT wheel wants +angle, LEFT wheel −angle
```

Applied about the wheel's own forward axis, so roll and steer keep
working underneath.

---

## Dials worth knowing

| dial | value | decides |
|---|---|---|
| `SpeedScale` / `AccelScale` | 0.78 / 0.7 | how much slower |
| `SteerRateScale` | 0.35 | the rudder lag — the main cue |
| `TurnScale` | 0.62 | how wide it comes round |
| `Waves` | 3 entries | the sea itself |
| `WaveTilt` | 9 | degrees per stud of slope |
| `HeaveStiffness` / `HeaveDamping` | 55 / 10 | the bounce (ζ ≈ 0.67) |
| `WheelTilt` | 82 | how flat the wheels lie |
| `YawWander` | 2.6 | degrees of slew |

`WaveTilt` was tuned by **how often it hits the ceiling**, not by its
peak — a ceiling the system sits at is not a ceiling, it is the value.
At 26 every frame clamped; at 9 it is 0.6–2.7%.

---

## If it goes wrong

| symptom | cause |
|---|---|
| no visuals AND no audio at all | `updateKart` bailed — `Seat` must be a `VehicleSeat` and `SteeringWheel` a `BasePart`. It warns once per kart. |
| handling changes but nothing moves | Rider half only. Check the `Swimming` attribute is arriving. |
| no bob, tilt or bursts | no `BodyMotor` — the factory found no body root. It warns naming the parts it looked for. |
| sounds silent | almost certainly asset ownership, see BUGS #31. Every Sound warns after 5s if it never loaded. |
| the sea snaps or lurches | a per-frame contribution being written into smoothed persistent state. See FINDINGS. |
| `arithmetic on nil` in `waveAt` | the sea clock was not advanced — `_updateSwim` owns it. |
