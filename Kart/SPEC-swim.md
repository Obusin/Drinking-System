# SPEC — swim mode

The kart on water. **There is no buoyancy, no water plane and no second
movement mode.**

- Config: `ReplicatedStorage/BloxKart/Config/Swim.luau`
- State: `Simulation.luau` — `_updateSwim`, `Simulation.waveAt`
- Hop: `Simulation.luau` — `_updateSwim`, and the render write at the
  bottom of `Step`
- Other visuals: `KartClient/Rider.luau` — `updateRoadWheels`,
  `updateBody`, `updateGliderFx`
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
            ├── draws THE HOP on the whole assembly (render write)
            └── publishes  Swimming / SeaClock / WaveRise

Rider       ──  reads those attributes and draws the rest
                wheels sideways · bob · tilt · yaw · sounds
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
- **The water hop** is a **ballistic arc** on the whole assembly,
  drawn at the render write. It is the main motion — see below.
- **Yaw wander** — a kart's nose never moves on its own; a hull's does
  constantly. Turned down to 1.5° once the hop arrived, because two
  unrelated motions at similar strength read as *drunk* rather than
  playful.

**One clock.** `Simulation` owns `seaClock` and publishes it; `Rider`
reads it rather than advancing its own. Two clocks stepped by `dt` from
different moments are not one clock, and the crest the hull is drawn
riding would be a different wave from the hop meant to accompany it.

---

## The water hop, and why it replaced the bursts

The kart **skips over the swell like a stone**. It is a deliberate copy
of what the real hop looks like when you spam jump across a swim zone —
that already read better than any amount of tilt did, so it became the
reference rather than a coincidence.

**It moves the whole kart**, from the render write — the same line the
flip uses. Wheels, seat, driver and bodywork rise together, which is the
entire point: it is the hop you get from spamming jump, run
automatically off the wave field.

**Still purely visual.** `swimHop` is added to `visualPos` only, beside
`bob`, `squash` and `catch`. It never touches `pos`, `vertVel`,
`grounded`, the sweep or the ground probe. The kart drives dead flat on
the invisible floor the whole time.

### It was in Rider first, and it was invisible

Driven from `BodyMotor`, exactly like `bob` and the tilt. **A joint moves
what hangs below it and nothing else** — the wheels, the seat and the
driver hang off the *hitbox*, not off the body root. So the shell lifted
a stud off its own stationary wheels, which reads as nothing at all.

`Motor6D.Transform` is client-local as well, so none of it ever reached
another player's screen.

This is the flip's lesson for the third time: **move the thing they are
all jointed to, not a list of joints.** The render write does that in one
term and replicates by itself.

### The curve was wrong, not the numbers

The old **bursts** latched a value with `max()` and bled it off with
`exp()`. That is a spike-and-decay — *fastest at the start, slowest at
the end*. It has no rise and no top.

A hop is the opposite shape: it spends real time climbing, **hangs where
velocity crosses zero**, then accelerates into the landing. That hang is
the readable part, and no setting of a decay curve can produce one. So
the bursts were deleted rather than tuned.

Sized against the real hop, because "like the jump" is a testable claim:

| | apex | airtime |
|---|---|---|
| real hop (`HopSpeed` 18 / gravity 150) | 1.08 studs | — |
| water hop (13 / 62) | 1.36 studs | 0.42 s |

### The wave decides how BIG, never whether

This is the whole rhythm fix, and it was the second design.

The first launched only when the field was rising past a threshold, and
that produced *hop, hop, gap, hop, gap, hop, hop* — the gaps being every
moment the wave happened to be falling. **Spamming jump has no gaps**,
and looking like spamming jump is the entire brief, so a trigger that
can decline is the wrong shape however well it is tuned.

The launch is now unconditional while moving in water. The wave sets the
**size**: rise is mapped **symmetrically**, `-FullRise..+FullRise` onto
`MinScale..1`. A crest gives the full arc, a trough the smallest one,
and the smallest one is still a hop.

**The symmetry is load-bearing.** Mapping `0..FullRise` and clamping
looks equivalent and is not — the field falls half the time, so half of
all hops pinned to the floor and the mean apex came out at 0.5 studs
against the 1.0 the dials were solved for. Half the range was
unreachable.

Only **speed** stops it now (`WaveHopMinSpeed`, 12 studs/s). A moored
boat wallowing is right; a moored boat hopping four times a second is
not.

### The curve: why it is not ballistic

It was a real ballistic arc — impulse, gravity, hard stop at zero. That
arc has a **velocity discontinuity at both ends**: `0 → +v` at launch and
`−v → 0` at landing. **Those two corners are the snap**, and they cannot
be tuned out, because they are what a ballistic arc *is*. One jump gets
away with it; two a second does not.

The height is now driven from a **phase**, so the shape is chosen rather
than inherited. `WaveHopSmooth` blends parabola → `sin²`:

| smooth | launch slope | landing slope | |
|---|---|---|---|
| 0.0 | +4 | −4 | ballistic — a corner at each end |
| **0.85** | **+0.6** | **−0.6** | now |
| 1.0 | 0 | 0 | perfectly smooth |

Measured as jerk, which is what "snappy" actually is:

| | peak jerk |
|---|---|
| ballistic | 536 studs/s³ |
| **smooth 0.85** | **150** |
| smooth 1.0 | 153 |

**0.85 is already at the floor** — past it the peak jerk comes from
mid-curve, not the ends, so 1.0 buys nothing and only makes the launch
limper.

The landing squash follows for free: its impulse is the **arrival
slope**, which the blend drives toward zero. Smoothing the curve
silences the thump with no second dial to keep in step.

### The cadence is now exact, not measured

A phase cycle is `air + rest` **by construction**, whatever the hop's
size. There is no gap sd left to report — it is zero by definition, and
the wave varies only the height. That closes out the irregularity
complaint properly.

| speed | hops/s | aloft | peak | camera travel | kart in frame |
|---|---|---|---|---|---|
| 12 | 2.09 | 71% | 0.71 | 0.59 | 1.08 |
| 30 | 2.22 | 72% | 0.71 | 0.56 | 1.08 |
| 60 | 2.47 | 74% | 0.71 | 0.49 | 1.07 |
| 95 | 2.81 | 78% | 0.71 | 0.43 | 1.04 |

> Moving to a phase model **slowed the measured rate by a third** with
> the same dials. Under ballistics a smaller hop also had a shorter
> airtime, so the average cycle ran ahead of the arithmetic. The rest
> came down 0.24 → 0.15 to land back on the same 2–2.8/s.

### The arc is the real hop's arc; the REST is the dial

`HopSpeed` 18 against gravity 150 is 0.24 s of air — **14 frames**.
These give 12–16. That is the thing being copied, so **the arc should be
the last thing touched when the rhythm is wrong**; `WaveHopCooldown` is
the first.

Halving the rate means doubling the cycle, and that is either more air
or more rest:

| | hops/s | air | aloft | reads as |
|---|---|---|---|---|
| more air (v 8.5, g 25) | 1.7–2.7 | 20–31 frames | **91%** | hovering |
| **more rest (v 17, g 98)** | 2.0–2.8 | 14–16 frames | **57–68%** | skipping |

Around 60% aloft is a little more time in the air than on the water,
which is what clicking jump two to three times a second looks like.

**`WaveHopCooldown` has gone 0.05 → 0.30 → 0.24 across three retunes and
the *airtime* never moved once.** That is the intended division of
labour.

### Height and rhythm are separable

Worth knowing before touching either. At a fixed airtime, `apex` is
proportional to `v` — so scaling **`v` and `g` by the same factor**
lowers the hop and leaves the cadence alone. Measured identical at
2.01/2.53/2.78 hops/s and 14–16 frames across a 40% range of heights:

| | v / g | base apex | hops/s | air |
|---|---|---|---|---|
| original | 17 / 98 | 1.47 | 2.01–2.78 | 14–16 |
| **−30%** | **12 / 69** | **1.03** | **2.01–2.78** | **14–16** |
| −40% | 10.2 / 59 | 0.88 | 2.01–2.78 | 14–16 |

> **To change the height:** scale `v` and `g` together.
> **To change the rhythm:** move `WaveHopCooldown`.
> The two do not interfere.

The height is deliberately below the real hop's 1.08 studs, because this
fires two to three times a second where the real one fires when you ask
for it. **A regular rest
is a rhythm; an irregular one is a stutter** — the original complaint
was the second, so a large rest is not a regression.

### Pitch comes from the hop's own velocity

Not from a timer. Nose rises while climbing, passes through neutral
**exactly** at the apex because that is where velocity is zero, and
drops on the way down. It cannot fall out of step with the arc, because
it *is* the arc.

### The camera: lag, not shake

The camera takes **half the hop, a beat late**.

It took *none* of it first, on the reasoning that the eye should hold
still. That was wrong, and the reason is worth keeping: **a perfectly
rigid camera makes the kart read as a sprite sliding on glass.** Nothing
shares the weight, so the motion has no consequence. The kart's own
`LandDrop` already knew this — *"the camera drops with the kart, a beat
behind; that lag is the weight of the camera, and it is what makes the
landing feel shared rather than watched."*

**Shake and lag are not the same thing.** Shake is high-frequency noise
on the eye and it is exactly what you must never add to something firing
2–3 times a second. This is a smooth, partial, late follow.

The kart is drawn at `pos + swimHop`; the camera aims at
`pos + swimHop × Follow`, smoothed. The kart rises in frame by the
**difference**, and the camera hauls itself after it:

**It must be a SPRING, not a lerp.** A lerp only ever chases, so it can
only ever *subtract* from what is on screen — turning it up to feel it
more just cancels more of the hop. Gain and visibility were the same
dial pulling opposite ways, which is why the first version could not be
felt at any setting.

A spring has **its own phase**. Under-damped it overshoots, so when the
kart starts falling the camera is still rising and the two are briefly
moving *apart*:

| | camera travel | kart in frame |
|---|---|---|
| lerp 0.5 / rate 9 | 0.318 | 0.808 |
| **spring k=120, ζ=0.35, follow 0.7** | **0.59** | **1.08** |

**Nearly twice the camera motion and more visible hop**, because
out-of-phase motions add rather than cancel. ζ = 0.35 is deliberately
loose — critical damping is a lerp again.

Applied to the **eye and the aim together**, so the view translates
rather than tilts. Moving only the eye would swing the look direction
2–3 times a second — a nodding camera, and genuinely unpleasant.

The one camera *shake* that exists on landing is fired by
`events.bouncedLanding`, the **real** landing bounce. The water hop
never raises it, so a skip still cannot shake the view.

### The leap sound

Ramps and water skips share **one sound**, pitched by size — higher for
a small skip, lower for a ramp launch, because pitch reads as mass.
Fired at the **launch**: going up is the moment worth hearing, and the
landing already has the bump and the splash.

`Config.Audio.LeapSoundId`. The ramp side needed no new plumbing —
`trickStarted` and `glideStarted` already existed and nothing consumed
them.

The water side is quieter (`WaterLeapVolume`) and **gated**, because it
fires up to 2.9 times a second at top speed where a ramp fires once.

**The first gate value gated nothing.** It was set to 0.55, which is
also `WaveHopMinScale` — so the smallest possible hop already cleared it
and every skip played. *A threshold set to the floor of the thing it
filters is not a threshold.* Measured and moved to 0.80:

| speed | hops/s | sounds/s at 0.55 | at 0.80 |
|---|---|---|---|
| 20 | 1.18 | 1.18 | ~0.00 |
| 40 | 1.74 | 1.74 | ~0.10 |
| 60 | 2.23 | 2.23 | ~0.40 |
| 95 | 2.92 | 2.92 | ~1.40 |

It now escalates with speed on its own — near-silent at a cruise,
clearly leaping at full pelt. **Set `WaterLeapVolume` to 0 to keep the
ramps and silence the water**; that is the dial to reach for first if it
feels busy.

### Bow-up trim — the boat leans back

A hull below planing speed is **climbing its own bow wave**: nose high,
stern squatting. It is worst while *accelerating* through that hump and
settles once the boat is up and planing.

So it is two terms, and **the throttle one is the big one**:

```
bowUp = TrimOnThrottle · throttle · (1 − pace)  +  TrimAtSpeed · pace
```

| state | nose-up |
|---|---|
| parked | 0.0° |
| **pinning it from rest** | **8.0°** |
| half speed | 6.0° |
| flat out, planing | 4.0° |
| coasting at speed | 2.5° |

**A speed-only lean would be wrong in the exact moment the player looks
for it** — pinning the throttle from rest would do nothing at all until
the speed had already arrived, which is backwards.

**And the throttle term must fade** (`1 − pace`). The lift comes from
*climbing* the bow wave; once you are planing you are on it rather than
climbing it. Holding full bow-up at top speed is a boat permanently
stuck at its hump — nose to the sky down a flat-out straight, which is
the one place a real hull sits flattest.

Added to the kart's **existing accel-squat pitch** rather than being a
system of its own, so it inherits `FX.PitchRate` smoothing and the
render write, and composes with the hop's pitch instead of fighting it.
Reverse does not lift the bow — a boat backing up settles by the stern.

### Float and skip are both required

`bob` (the hull sprung against the wave field) never stops and is what
makes the kart look like it is **on** water. `swimHop` is the occasional
arc on top and is what makes it look like it is **skipping over** water.
Either alone is half the read: float without skip wallows, skip without
float is a kart pogoing on glass.

### Landing

Fed into **the squash spring the kart already has**, so a skip onto
water can never look like a different mechanism from a normal landing
and there is no second recovery rate to keep in step.

**Impulsed, never assigned** — assigning it is exactly how the kart's own
landing bounce ended up snapping, four diagnoses deep.

Sized to be clearly gentler than a real landing:

| event | push into the spring | peak dip |
|---|---|---|
| gentlest real landing | 6.1 | 0.22 studs |
| hardest real landing | 24.8 | 0.90 studs |
| **water skip** | **3.1** | **0.23 studs** |

It scales with the arc automatically, because the impulse is a fraction
of arrival speed — making the hop more aggressive made its landing more
aggressive too, with no second dial to remember.

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
| no bob, tilt or hop | no `BodyMotor` — the factory found no body root. It warns naming the parts it looked for. |
| sounds silent | almost certainly asset ownership, see BUGS #31. Every Sound warns after 5s if it never loaded. |
| the sea snaps or lurches | a per-frame contribution being written into smoothed persistent state. See FINDINGS. |
| `arithmetic on nil` in `waveAt` | the sea clock was not advanced — `_updateSwim` owns it. |
