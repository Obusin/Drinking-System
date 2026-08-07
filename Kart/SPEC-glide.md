# SPEC — the glider

Ramp, wings, gap, landing. Modelled on Mario Kart's glider, including the
part everyone gets wrong: **it does not steer you to the landing zone.**

- Config: `ReplicatedStorage/BloxKart/Config/Glide.luau`
- Flight: `ReplicatedStorage/BloxKart/Simulation.luau` (`STATE_GLIDE`)
- Visuals: `StarterPlayerScripts/KartClient/Rider.luau` (`updateGlider`,
  `updateGliderFx`)
- Rig: `ServerScriptService/KartServer/KartFactory.luau` (`gliderKind`)

---

## Setting one up

| step | what |
|---|---|
| 1 | Tag a part **`GlideRamp`**. Its **UpVector is the launch direction** — aim it by rotating it in the viewport. |
| 2 | Optionally tag a part **`GlideLand`** past the gap. Optional: with none, the glide is free flight. |
| 3 | On the kart, set **`Aero`'s pivot to the hinge line**. The flap rotates about its own pivot; leave the pivot at the mesh centre and it scissors through the wing. |
| 4 | Drive over the ramp above `MinSpeed` (34 studs/s). |

Both tags are in `Triggers.TAGS`, so neither is ever solid and neither is
visible to the ground probe. **The landing marker is a hint, not a floor
and not a finish line.**

---

## The flight

```
ramp hit    → boost (sound + VFX + thruster flare) + launch kick
            → grounded = false, landing refused for MinAirTime
            → wings scale open with a bounce, deploy one-shot, wind in
flight      → reduced gravity, throttle = pitch, low-authority steer
            → corridor NUDGES the nose if you stray wide. That is all.
near ground → flare eases the descent to FlareSink
touchdown   → wings, trails, wind all off
```

| input | effect |
|---|---|
| steer | `TurnRate` 0.35 rad/s — a quarter of the ground rate |
| throttle forward | dive: lands sooner, faster |
| throttle back | float: longest airtime and distance |

Pitch trading altitude for speed is the entire skill of a glider, and it
is the only real depth in Mario Kart's version too.

---

## Why there is no landing guarantee

There was one, and it was removed. **257 lines came out.**

A constant turn rate is a circular arc of radius `v/w`, so drift off the
ideal line after time `T` is `R * (1 - cos(wT))`. At 80 studs/s:

| turn | 1.5s | 2.5s | 4.0s |
|---|---|---|---|
| 5°/s | 8 | 22 | 55 |
| 8°/s | 13 | 35 | 87 |
| 12°/s | 19 | 51 | 126 |
| 20°/s | 31 | 82 | 189 |

A track here is 40–60 studs wide, so 12°/s over 2.5s is already off the
road — Mario Kart's karts are slower relative to their track width than
ours are, and copying their numbers directly would put players in the
void.

The response was three forcing mechanisms, each added to fix the
previous one's side effects:

1. a **position funnel** that lerped the kart onto an ideal line
2. a **glide slope** that dictated the descent rate
3. a **heading clamp** that would not let the nose turn away

They worked — 0.00000 studs of miss under adversarial input — and they
felt like being grabbed, because **a correction proportional to error is
largest exactly where the player is most likely to notice it.**

What survives is a corridor: a gentle nudge on the *nose* when you stray
wide. It suggests; it cannot make you do anything. Where you land is
yours. See FINDINGS §7c, *"Guidance that cannot be escaped is control"*.

**If it now feels too loose, aim the ramp better before reaching for
`CorridorPull`.** That is what the level is for.

---

## The flare

The one piece of the forced approach worth keeping, and it is better for
being detached from the landing marker.

One ray straight down. Inside `FlareHeight` (26 studs) the descent eases
to `FlareSink` (9 studs/s), so the kart settles rather than driving into
the floor at whatever rate it happened to be falling.

Measured off the **ground**, so it works over any surface, with or
without a pad, and cannot be aimed at the wrong thing.

It needs no active pull: `sink` is a **cap** on descent and the flare
*lowers* it, which the clamp applies on the next frame. Slowing down is
free — only speeding up ever needed help.

---

## Landing and falling are the same thing

The glide ends when the **wheels touch something**, never on reaching the
pad. Ending it at the marker meant a kart arriving above a lower landing
area lost its wings in mid-air and fell the rest of the way under full
gravity:

| drop left | wings out | wings cut at pad |
|---|---|---|
| 10 studs | 18.0 studs/s | 55.0 — 3.1× |
| 35 studs | 18.0 studs/s | 102.5 — 5.7× |
| 60 studs | 18.0 studs/s | 135.0 — 7.5× |
| 90 studs | 18.0 studs/s | 165.0 — 9.2× |

With the wings out the descent is capped at the sink rate whatever the
drop.

---

## The rig

| part | job | how it is found |
|---|---|---|
| `Aero` | the flap — the only thing that moves | `AeroName` / `KartAero` |
| `Wing`, `Wing_1` | fixed; flutter and carry the trails | `WingNames` / `KartWing` |
| `CenterMesh` | thruster glow: **speed**, nitro colour | `ThrusterCenterNames` |
| `SideThrustMesh` | thruster glow: **boost only** | `ThrusterSideNames` |
| `Shield` | the shield power-up's art | `Config.Effects.ShieldName` |

The flap and the wings get `Motor6D`s because **a welded part cannot move
at all**. The flap's hinge axis is the *kart's* lateral axis converted
into the joint frame, so it is correct however the mesh was modelled —
only the pivot **position** needs setting.

### Deploy

Wings **scale** open with an `easeOutBack` overshoot (~15% past full,
0.22s), not a transparency fade. Scaling reads as deploying; fading reads
as the engine being slow to draw something that was always there.

Resizing does not disturb the joints, because `pivotJoint` captures the
part's **CFrame** and resizing moves faces about the centre.

The authored size is cached at discovery. Reading `part.Size` back each
frame would read the animation's own last write and ratchet the wings
smaller on every deploy.

### Thrusters

Centre reads speed, sides read boost, and that split is deliberate: if
everything glowed with speed there would be nothing left to change when
you actually boost.

---

## Cross-kart visibility

`Gliding` and `GlidePitch` are published as attributes so `Rider` can
animate every kart in the field — it runs for all of them, and only the
driver's own client has a `Simulation` to ask.

**Known limit:** attributes set on a client are local to that client, so
other players' gliders currently animate only if their state reaches this
machine another way. Wings default to hidden, so the failure is safe.

---

## Dials worth knowing

| dial | value | what it decides |
|---|---|---|
| `Gravity` | 24 | the whole shape of the arc |
| `LaunchUp` | 46 | how high the ramp throws you |
| `LaunchBoostSpeed` | 155 | the shove off the ramp |
| `MinAirTime` | 0.35 | stops the ramp re-triggering |
| `TurnRate` | 0.35 rad/s | air authority |
| `FlareHeight` / `FlareSink` | 26 / 9 | the touchdown |
| `CorridorPull` | 1.2 | how strongly it hints |

**Size the gap first, then pull `LaunchUp` and `Gravity` together.** They
are the two that set the arc; everything else trims it.

Any ceiling must clear the fastest thing allowed to push against it —
`DiveSpeedCap` is 165 because `LaunchBoostSpeed` is 155, and at 140 the
boost was silently clipped.

---

## If it goes wrong

| symptom | cause |
|---|---|
| `glide timed out in mid-air` in Output | a `GlideRamp` is aimed at nothing |
| camera whips after passing the pad | guidance not releasing — should be impossible now, see `glidePassed` |
| wings never retract | the glide is re-triggering on the ramp; check `MinAirTime` and whether the boost sound fires once or repeatedly |
| wings visible after a respawn | `LocalTransparencyModifier` reset by a `Transparency` write; it must be re-asserted, not set |
| thrusters dark | `Rider` warns once per kart with the counts it lit. Zero means the name does not match; non-zero and still dark means a `SurfaceAppearance` is overriding `Color` |
