# BloxKart

**Before changing anything, read `BUGS.md`** — what is currently broken,
what is only suspected, and the patterns that keep producing it. Most of
the bugs in it were caused by the fix for another one.

**`LOBBY.md` is the lobby-vs-race split** — every service that only
runs on one side, the kart-placement attribute pattern and the race it
replaced, and the two-layer guard that stops the lobby's practice items
from paying out like a real race.

**`SECURITY.md` is the trust surface** — every inbound remote, what it
actually checks, and why the server can only referee a client-simulated
kart rather than own it. Read before adding a RemoteEvent.

**`SYSTEM.md` explains the whole thing from zero** — architecture, the
authority model, the tag-driven world, the round loop, and the two rules
that explain most of the decisions. Hand that to anyone (or anything)
arriving without context.

`FINDINGS.md` is the permanent record of mechanisms this project has
learned. `BUGS.md` is the live list. **`GAME-LOOP.md` is what the round
loop is supposed to do** — the five phases, what each owns, and the six
invariants. Read it before touching `MatchService`, `KartService` or
takeovers; every loop bug so far has been a violation of one of them.

Arcade kart. Mario Kart feel, not vehicle simulation.

Single Script Architecture — one `Script`, one `LocalScript`, everything
else a module underneath.

| Path | Becomes |
|---|---|
| `src/ServerScriptService/KartServer/` | **Script** + modules — spawning, the match loop, items, projectiles |
| `src/StarterPlayer/StarterPlayerScripts/KartClient/` | **LocalScript** + modules — movement, camera, HUD |
| `src/ReplicatedStorage/BloxKart/` | Config, shared contracts, item definitions |

Press Play. You spawn already seated; the match starts on its own.

| Input | Does |
|---|---|
| `W` / `S` | Throttle / brake-reverse |
| `A` / `D` | Steer |
| `Space` (or `R1` / `L1`) | **Hop-drift.** Tap to hop; hold with steering to drift; release to bank nitro |
| `Shift` (or `L2`) | Nitro — one tap per tank |
| `Q` | Use item |
| `R` | Reset to last checkpoint (when stuck) |
| `F` | Ready up during the intermission |
| Hold right mouse | Free-look. Recentres when released |
| Right stick | Free-look on gamepad |
| `C` (or `R3`) | Look back |
| `E` (or `Y`) | Get out — test mode only |

### Docs

| | |
|---|---|
| [`SETUP.md`](SETUP.md) | what to tag in Studio to get a working track |
| [`FINDINGS.md`](FINDINGS.md) | **what we've learned the hard way — read before changing bot steering, replication or the racing line** |
| [`SPEC-match.md`](SPEC-match.md) | the round loop: grid, countdown, results |
| [`SPEC-bots.md`](SPEC-bots.md) | AI racers, and the twelve-layer plan audited |
| [`SPEC-hop-drift.md`](SPEC-hop-drift.md) | the drift state machine |
| [`SPEC-nitro.md`](SPEC-nitro.md) | tanks and burn stages |
| [`SPEC-glide.md`](SPEC-glide.md) | the glider: ramps, wings, and why there is no landing guarantee |
| [`SPEC-swim.md`](SPEC-swim.md) | swim mode: a floor at the waterline, and the sea drawn on top |
| [`SPEC-trick.md`](SPEC-trick.md) | flip ramps: visual rotation, and why the root turns rather than a list |
| [`SPEC-packaging.md`](SPEC-packaging.md) | running the kart in more than one place: code via git, art via Packages |
| [`SPEC-bike.md`](SPEC-bike.md) | the motorcycle: one controller two vehicles, and which layer a visual belongs to |

---

## The consistency rule

**The controller reads exactly two things off the kart: the `Hitbox` and
the `Seat`.** It never measures wheel size, mass, part positions or
anything else about the art. Swap the visual for a bus, a shopping
trolley or a banana and the handling is bit-for-bit identical.

This is the whole reason the old hinge-and-wheel rig was thrown away.
Under constraint physics the handling *is* a product of the geometry —
wheel radius set the gearing, mass distribution set the balance, friction
set the grip. Every art change was silently a handling change. It also
meant the kart drove like a default Roblox car, because it was one.

To use your own art: put a Model named `KartVisual` in ServerStorage. It
should face `-Z` and sit around the origin. It gets welded on as dead
weight — non-colliding, massless, no say in anything.

```
Kart (Model, PrimaryPart = Hitbox)
├── Hitbox   Part, invisible, CanCollide false, 4 x 2.4 x 7   <- the only part that matters
├── Seat     VehicleSeat, welded. An input device, nothing more
└── Visual   Model, welded on, purely cosmetic
```

`Seat.MaxSpeed`, `Torque` and `TurnSpeed` are all 0 — the built-in
VehicleSeat driving would fight the controller.

---

## How movement works

No forces. No constraints. No rigid body. We own the state and integrate
it ourselves:

```
heading  += turnRate * dt            -- where the kart is GOING
speed     = lerp(speed, target)      -- how fast
pos      += forward(heading) * speed * dt
hitbox.CFrame = pos * yaw(heading + driftAngle) * lean
```

The gap between `heading` and `heading + driftAngle` **is** the drift.
The body is rotated up to 30° into the turn while the kart keeps
travelling along `heading`. Nothing is sliding; it just looks like it is.

Collision is swept and resolved by us — a `Blockcast` along the frame's
movement, then project the remainder along the wall and scrub speed.
Roblox's solver never gets a vote, which is what makes handling identical
across machines and frame rates.

The hitbox is anchored while idle and unanchored while driven. A client
can only replicate CFrame changes on a part it owns, and it can't own an
anchored one.

---

## Surface gravity — loops, walls, ceilings

**"Down" is the track's surface normal, not the world's.** `up` chases
whatever the ground probe reports, and gravity always pulls along `-up` —
which on a loop means *into* the road.

The consequence is the important bit: **there is no falling off a loop.**
You leave the track by driving off an edge or jumping, never by running
out of speed. Stop dead upside-down at the top of a loop and you stay
there. This is how Mario Kart's anti-gravity, Sonic's loops and F-Zero
all work — none of them use centripetal force, they rotate gravity.

Everything is measured as a distance **along up** rather than as a world
Y coordinate. That single change is what makes ceilings work at all.

| Dial | Does |
|---|---|
| `SurfaceAlignRate` | how fast gravity rotates onto the track. Too slow and tight loops shed the kart |
| `AirAlignRate` | how fast up returns to world-up once airborne, so you land level |
| `StickTime` | grace period after losing contact before world gravity resumes. Bridges seams and panel gaps |
| `MaxSlopeDot` | measured against **our** up, so a loop wall is road rather than an obstacle |

### The camera

Roblox's default camera is locked to world-up, so it would stay upright
while the kart rolled around a loop — unwatchable. `CamEnabled` swaps it
for a `Scriptable` chase cam that **rolls with the track normal**, so the
whole world tips as you go round.

Two details that matter:

- **`CamRollRate` is slower than `SurfaceAlignRate` on purpose.** The
  camera lagging behind the kart's roll is what sells a loop; matching
  them exactly makes the world feel bolted to your head.
- **`CamDriftFollow = 0.35`** keeps the camera mostly behind your
  direction of *travel* rather than the drifted body, so a drift reads as
  genuinely sideways on screen. Set 1 and the camera swings round with
  the kart, which kills the effect.

`CamCollide` pulls the camera in when scenery gets between it and the
kart — this matters far more than usual here, because on a loop the track
itself is frequently behind you.

The camera is restored to `Custom` on unseat, on death, and in
`destroyKart`, so there's no way to get stranded in a Scriptable camera
on foot.

### Stairs and uneven ground

Five probes, used for two different things:

- **Position** takes the *highest* hit — that climbs a step immediately
  without clipping into it.
- **Orientation** takes the *averaged* normal (`StairSmoothing`) — that
  stops each stair riser reading as a vertical wall. It turns a staircase
  into a ramp.

Combined with `StepHeight` on the collision sweep, anything shorter than
that is ignored by collision entirely and climbed by the ground snap.

---

## How to tune

Everything is in one `TUNE` table and nothing in it depends on the art.

**The feel dials, in the order worth touching:**

1. **`Accel`** — approach rate to top speed. It's a lerp rate, not a
   force, so it's mass-independent. Higher = snappier launch.
2. **`TurnRate` / `TurnRateTop`** — steering authority at low and top
   speed. The gap between them is your speed-sensitivity.
3. **`DriftTurnBase`** — must stay **above** `TurnRate` or drifting is
   pointless. A drift turning tighter than steering is the entire reward.
4. **`DriftVisualAngle`** — how sideways it *looks*. Cosmetic only;
   changing it cannot affect your line.
5. **`DriftSpeedKeep`** — per-frame speed retention while drifting. Keep
   it near 1.0 so drifting is always the fast line. This is the
   "minimal speed-scrub" target.
6. **`BoostTier1/2/3Speed`** — boost pins you to a speed rather than
   pushing you. Predictable, and it can't be eaten by drag.

**Symptom → dial:**

| It feels like | Change |
|---|---|
| Sluggish off the line | Raise `Accel` |
| Steering is vague | Raise `TurnRate`, lower `TurnRampSpeed` |
| Spins on the spot at low speed | Raise `TurnRampSpeed` |
| Drifting is pointless | Raise `DriftTurnBase` above `TurnRate` |
| Drift doesn't look sideways | Raise `DriftVisualAngle` (cosmetic, free) |
| Drifting loses you speed | Raise `DriftSpeedKeep` toward 1.0 |
| Boost is underwhelming | Raise tier speeds, or `BoostFovPunch` — half of "fast" is camera |
| Hops feel heavy | Lower `Gravity` (ours, not Roblox's) |
| Doesn't feel fast at speed | Raise `FovAtTopSpeed` |
| Body snaps over bumps | Lower `SlopeAlignRate` |
| Rides too low/high | `RideHeight` |

Set `TUNE.ShowState = true` to print state / speed / heading / tier while
driving. `CONFIG.DEBUG` in KartRig traces the spawn.

### Test mode vs. real mode

Two flags, **flip them together**:

| | `CONFIG.TEST_MODE` (KartRig) | `TUNE.AllowExit` (KartControl) |
|---|---|---|
| **Testing** (current) | `true` — one kart on the pad, walk into it | `true` — `E` gets you out |
| **Real** | `false` — one per player, spawned seated | `false` — no exit at all |

In real mode players are locked in: jump disabled server-side, Space sunk
client-side, and the server re-seats anyone whose seat empties.

---

---

## Steering wheel and hand IK

`KartRider.client.luau`. Cosmetic only — it never touches movement.

The wheel hub is joined to the hitbox with a **Motor6D**, not a weld,
because a Motor6D can be rotated at runtime. The rim and spokes weld to
the hub, so spinning the hub spins the assembly. `GripL` / `GripR`
attachments sit at 9 and 3 o'clock and rotate with it.

Arms use **two-bone analytic IK** — law of cosines to find the elbow,
then both bones are oriented onto the grips. R15 limbs run along their
own `-Y` and bend about `X`, which is why the basis is built with
`-bone` as Y and the bend-plane normal as X. R6 falls back to simply
aiming the single arm bone.

It runs for **every** kart, not just yours, keyed off
`VehicleSeat.SteerFloat` — which Roblox already replicates from the
driver. So you see other players steering with no custom networking. It's
bound at `RenderPriority.Character + 1` so the default sit animation
can't overwrite the joints.

| Dial | Does |
|---|---|
| `MaxWheelAngle` | degrees of wheel rotation at full lock |
| `WheelSmoothing` | how fast the wheel chases input |
| `ElbowSign` | **flip to -1 if elbows bend backwards** |
| `PoleDown` / `PoleOut` | where the elbows point |
| `MaxReach` | stops the shoulder popping when the grip is out of range |

To use your own wheel art: name a part `SteeringWheel` inside your
`KartVisual`. It gets the Motor6D instead of the built-in one, and its
children weld to it. Add `GripL` / `GripR` attachments for the hands.

---

## Known gaps
- **Sparks and speed lines are client-local** — only the driver sees
  their own. Fine for testing, needs a server signal for multiplayer.
- **Karts don't collide with each other.** The hitbox is non-colliding by
  design; kart-vs-kart needs adding to the sweep.
- **`BoostSoundId` is a placeholder** (`rbxasset://sounds/action_falling.mp3`).
