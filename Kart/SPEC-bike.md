# SPEC — the motorcycle

A second vehicle on the same kinematic controller. **`Simulation` does not
know motorcycles exist.**

- Handling: `ReplicatedStorage/BloxKart/Config/Vehicles.luau` — `Kinds.bike`
- Look: `ReplicatedStorage/BloxKart/Config/Bike.luau`
- Placeholder art: `ServerScriptService/KartServer/BikeVisual.luau`
- Pose: `KartClient/BikeVisuals.luau` → `KartClient/Rider.luau`
- Lean, wheelie, stoppie: `Simulation.luau`, at the render write

> **Status 2026-08-14:** rideable and being tuned. Placeholder art. The
> lean, knee, wheelie, stoppie, tyre smoke and fork dive are all in.
> `Vehicles.ForceForPlayers = "bike"` is still ON — every human is on a
> motorcycle until that is cleared.

---

## The idea

**One controller, many vehicles.** A vehicle is a row in
`Config.Vehicles` listing only what it differs on, sitting on
`Config.Handling` through a metatable as `self.H`. Nothing in
`Simulation` branches on vehicle kind; the data decides.

That is why the stoppie needs no `isBike` check — `StoppieAngle`
defaults to 0 in `Config.Handling`, so a kart cannot do one because its
data says it cannot.

The Consistency Rule holds across vehicles exactly as it holds across
skins: `Simulation` reads the Hitbox and the Seat, and the hitbox is
forced to `hitboxSize` whatever the art is.

---

## Where each thing lives, and why

The single most expensive lesson of this work was **which layer a visual
belongs to**. There are three, and they are not interchangeable.

| Layer | Moves | Replicates | Used for |
|---|---|---|---|
| Render write (`Simulation`) | the whole assembly | **yes** | lean, wheelie, stoppie |
| `BodyMotor.Transform` | bodywork only | no | wobble, shiver, dip, drift yaw |
| Rider IK | the character | no | knee, hands, head |

**The lean belongs on the render write.** It turns the hitbox, so wheels,
bodywork and rider all go over together — and because it replicates,
other players see a leaning bike. A body-motor lean is client-local and
would leave everyone else watching an upright bike carve a 60° corner.

This was got wrong twice. Once by putting the lean on the body motor
alone (wheels stayed upright inside a leaning shell), and once by having
**both** layers apply it at once, which summed to ~120° of bodywork on a
60° bike.

---

## Lean

Grand-prix angles, and the pivot matters more than the number.

```
LeanLow  13     at 22% of top speed
LeanHigh 42     at 90%
LeanMax  60     hard ceiling
BankOnTurn 0.3  yaw-rate share on top -> ~55 in a committed corner
```

**About the contact patch, not the centre.** `Simulation` conjugates the
roll about a point `RideHeight` below the hitbox — that is what
`RideHeight` *means*, so no second number can drift out of step.
Rotating about the centre swings the machine sideways out of its own
wheels; invisible at 20°, and at 55° it reads as the model being tipped
over rather than a rider leaning.

**The rider leans more than the bike, not less.** `RiderLean` was 0.88 —
12% *more upright* than the machine, the classic counter-lean. It is
1.14 now, so the body hangs inside the bike's line.

---

## The knee

The inside knee swings out; the outside leg stays put. It is the most
legible thing a rider does — a lean seen from behind is foreshortened, a
knee out of the silhouette is not.

**One IK chain per leg, hip→foot, with a pole at the knee.** This took
two wrong turns to reach and both are worth remembering:

- **hip→foot with no pole** — two joints placing one point has an
  infinite family of solutions and the solver hops between them. This is
  the flopping-feet bug.
- **two single-bone aims** (hip→knee, knee→foot) — fixes the flopping and
  breaks the foot. An aim cannot *place* anything; it rotates a bone of
  fixed length. The foot overshot the peg by up to half a stud, and by a
  different amount at every knee angle.
- **hip→foot with a pole** — the target *places* the foot, the pole says
  which way the knee points. Moving the pole is the whole effect, and the
  foot cannot leave the peg because the peg is what the solve is for.

### Never target the world

The idle pose used to drop the inside boot to the road. It looked right
on a default avatar and broke on everyone else:

| avatar scale | leg | peg (1.09) | ground (1.99) |
|---|---|---|---|
| 0.6 | 1.44 | ok | **unreachable** |
| 0.7 | 1.68 | ok | **unreachable** |
| 1.0 | 2.40 | ok | ok |

Roblox scales characters per player. An IKControl that cannot reach
either stretches the limb or stops solving, so the result depended on
who joined the server.

> **Rule: IK on a player character targets things bolted to the VEHICLE,
> never to the world.** The vehicle is the only one of the two whose
> distance from the rider you control.

The foot is now pinned to the footpeg at every speed, and the peg
position is **measured off the art** (`Rig.FootPegNames`) rather than
derived from `Rig.SeatOffset` — the seat is where the seat is, not where
a seated Humanoid's hips end up, and a few tenths of error there is a
boot hovering beside its peg. The peg *part* is cached, not its position,
because the pegs are welded to bodywork that wobbles.

---

## Drift

**A drifting bike banks; it does not slide flat.** `DriftGrip` inherited
the kart's 2.9 — a proper powerslide, 27° of slip at speed. On a machine
whose whole appeal is the lean that reads as the bike getting away from
you.

```
DriftGrip      2.9 -> 7     slip at top speed 26.7 -> 11.0 deg
DriftLeanBonus 8   -> 16    the slide comes back as lean
DriftRearYaw   13  -> 5     yaw IS the sideways look; cut it
```

Bank-to-yaw ratio at 75 studs/s went **0.8 : 1 → 2.7 : 1**.

Cutting the yaw did more than raising the lean. Yawing the body is
precisely the sideways look the lean is supposed to replace, so at 13° the
two were competing.

### The slip gate had an off-by-a-bit

`SlipIgnore` was 0.14 rad (8.0°) and claimed to sit above ordinary
cornering. It did not — a full-lock corner at low speed holds
`turnRate/grip = 3.0/20 = 8.6°`, so **every tight slow corner tripped the
drift visuals while fully gripping**. Smoke off a planted tyre, which is
the one thing that gate exists to prevent. Now 0.175 / 0.32:

```
normal, worst case (low speed, full lock)    8.6 deg
SlipIgnore                                  10.0 deg
drift at top speed                          11.0 deg
SlipFull                                    18.3 deg
drift at low speed                          24.6 deg
```

---

## Wheelie and stoppie

Mirrors of each other at the render write. Both are pure rotations of the
art — `pos`, `forward`, `up`, the sweep and the ground probe are
untouched, so neither can clear an obstacle or change how the bike turns.

| | pivot | sign | trigger |
|---|---|---|---|
| Wheelie | rear axle (+Z) | positive = nose up | boost tier 2 and 3 |
| Stoppie | front axle (−Z) | negative = tail up | braking input |

**Sign convention:** a right-hand rotation about +X tilts the up vector
toward +Z, and forward is −Z, so **positive is nose-up**. The first
wheelie negated this and produced a stoppie. `self.pitch` on the line
above uses the opposite sign because it is an attitude, not a lift.

**The stoppie fades out with speed**, and that fall-off is the whole
effect — the tail rises while there is speed to scrub and settles as it
runs out, so the bike lands on both wheels exactly as it stops. No state,
nothing detecting "stopped".

**It rises ten times faster than the wheelie** (30/s vs 3.2/s). Not a
fudge: `BrakeRate` is 5.5, so a stop is effectively over in a third of a
second. Tuned like the wheelie the tail reached 5° of the 20 it was asked
for, because the target collapsed before the rotation could climb to it.

**Braking input, not measured deceleration.** Both stop the bike fast,
but only one is the rider's doing — decelerating into a wall would throw
the tail up as if it had been a beautifully judged stop.

---

## Camera

The bike gets a closer, lower camera and a small amount of roll.

**The number that causes nausea is angular SPEED, not angle.** Measured
peak roll rate:

```
share  cap  rate   peak deg/s
0.090  4.5    6       19.4     queasy
0.045  2.2    4        5.5     shipped
```

When the lean was raised to 60° the peak came back to 6.9°/s; sharing the
simulation's softer spring brought it to 5.5°/s with no retune needed.

It reads `sim.lean` directly. It used to decompose the body motor's
Transform, which worked only while the body motor *was* the lean — after
the move it would have ignored corners and twitched at potholes.

---

## Cross-cutting: things that bit more than once

**Two places computing the same thing.** The lean (twice), the drift
state, the seat offset (three copies), the peg position. Every one showed
up as a visual bug that looked like bad tuning.

**Units, not values.** `Accel` is an approach *rate* (3.4), not studs/s².
`Grip` is how fast travel catches the nose (9), not a 0–1 coefficient. Both
were set from the wrong unit and wrong by an order of magnitude.

**A maxed-out IKControl stops solving.** It does not stretch toward the
target — it gives up. Cost a session with the handlebars and again with
the knee.

**`:: any` on a loop head turns off checking for everything the loop
touches.** A malformed `for name, tint, y in {...}` passed every
`check.sh` run and crashed at runtime.

---

## Still open

- `pose.fork` drives a motorised lower fork; real art needs a two-part
  fork (`ForkUpper` + `Fork`) to keep it.
- Per-vehicle seat offset — `Rig.SeatOffset` is shared by all vehicles.
- Rider air tricks on ramps.
- Testing flags ON: `Vehicles.ForceForPlayers = "bike"`,
  `Match.IntermissionTime = 3` (was 8).
