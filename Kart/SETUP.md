# BloxKart — Studio setup

Everything you have to place by hand. All of it is **tagging parts** in
Studio's Tag Editor (`View → Tag Editor`); no scripts to wire up.

Trigger parts are volumes you drive *through*, so **`CanCollide` off** is
the tidy default (the kart ignores them either way, but a solid volume
still blocks players on foot). The one exception is a road that's also a
trigger — see `TrackSurface` in §1. Leave `CanQuery` alone; the code
forces it on where it needs it.

---

## 1. The track

| Tag | On what | Does |
|---|---|---|
| `RaceStart` | One part across the start line | Starts the clock |
| `RaceEnd` | Same part is fine | Banks a lap |
| `Checkpoint` | A gate at each point round the lap | Validates the lap, and is where you respawn |
| `TrackSurface` | Only alongside another tag | "this trigger is also road" — see §1 rule 3 |
| `VoidZone` | Big invisible slabs under gaps, water, pits | Falling in respawns you |
| `SpeedBooster1` | Floor pads | Instant boost |
| `PowerUps` | A floating part | Gives a power-up (hold up to 3) |

**Start and end on the same part is normal** for a circuit. The first
crossing starts the race without also banking a lap.

### Checkpoints — two rules that matter

**1. Order them. This is the one that catches everyone.**

Add a number `Order` attribute (Properties → Add Attribute → Number) —
1, 2, 3… Gaps are fine, so 10/20/30 works. Without an attribute, a
trailing number in the *name* is used, so naming them `Checkpoint1`,
`Checkpoint2` also works.

> ⚠️ **Unnumbered checkpoints all count as order 0**, which collapses
> them into a single checkpoint. Only the first one you touch registers;
> every other one silently does nothing, and from the driver's seat that
> looks exactly like a broken trigger.
>
> **Check the Output window.** At startup you get the whole table:
>
> ```
> [Race] 5 checkpoint parts, 1 distinct order(s):
>           order 0     Checkpoint, Checkpoint, Checkpoint, Checkpoint, Checkpoint
> [Race] ⚠ all 5 checkpoints share one order, so only ONE counts per lap…
> ```
>
> A correctly set up track prints one order per line. Silence it with
> `Config/Race.Debug = false` once the track is done.

**2. Point them down the track.**

You respawn facing whichever axis `Config/Race.CheckpointFacing` names,
using the move-handle arrow colours in Studio:

| Setting | Aim this arrow down the road |
|---|---|
| `"X"` / `"-X"` | **red** |
| `"Z"` / `"-Z"` | **blue** |
| `"Y"` / `"-Y"` | green — up, so almost never right |

Default is `"X"` — **aim the red arrow the way traffic flows.** A
checkpoint gate is a slab spanning the road, so its natural front face
points *across* the track; that's why this is a setting rather than just
using the part's front. Get one backwards and players respawn facing a
wall. The startup print tells you which axis is active.

**3. Zones are the default. Nothing extra to do.**

A `Checkpoint` part is treated as a volume you drive **through** — it's
filtered out of the kart's movement queries, so it never blocks you. Just
tag it and go. `CanCollide` is ignored by the kart, though turning it off
is tidy (a solid volume still blocks players on foot).

**Making the ROAD itself a checkpoint** is also supported, and is
sometimes nicer — no invisible gates to place, and road pieces are
already in track order. For that, tag the part **`TrackSurface`** as well
as `Checkpoint`:

| Tags | Behaviour |
|---|---|
| `Checkpoint` | volume — drive through it (default) |
| `Checkpoint` + `TrackSurface` | road — stays solid, drive **on** it |

> ⚠️ Why the extra tag: trigger parts *must* be excluded from movement
> queries or they act as invisible walls. But if that exclusion hits a
> road, **the road stops existing for the kart and it falls through the
> floor.** `TrackSurface` is how a part says "I'm both".
>
> This was briefly inferred from `CanCollide` instead. That was wrong —
> a fresh Part defaults to `CanCollide = true`, so every zone anyone made
> silently became a wall to bump into. Explicit opt-in keeps the default
> safe.

Trade-off if you tag roads: you respawn at the **centre of the segment**
you last entered, so long straights put you further back than a gate
would. Shorter segments = tighter respawns.

The startup print tells you which mode each checkpoint is in.

A lap only counts if you passed **every** checkpoint in order. That's
what stops reversing over the finish line. With no checkpoints tagged at
all it falls back to a minimum lap time.

### Two things you get free from checkpoints

**Wrong-way warning.** No setup. It reads the facing of the checkpoint
you're currently in, so it's already correct if you aimed the arrows.
Tune in `Config/Race`: `WrongWayDot`, `WrongWayTime`, `WrongWaySpeed`.

**Missiles follow the track.** They fly the checkpoint route round
corners until the target is within `HomingRange`, then chase directly.
Without checkpoints they fly straight, which on a bendy track means they
hit the first wall. More checkpoints = smoother missile path.

### Power-up boxes

Tag any part `PowerUps`. It gets anchored, made non-colliding, and
spins/bobs on its own — a plain 4×4×4 Part works. Collected boxes vanish
and come back after `RespawnTime`.

You can hold **3 power-ups** at once. They're used first-in-first-out, so
the order you drive over boxes is the order you spend them. `Q` fires the
leftmost slot.

Mines dropped by players are tagged `KartHazard` at runtime — you don't
place those.

---

## 2. Spawning

One `SpawnLocation` anywhere in Workspace. Karts spawn on a grid in
front of it, one per player, up to `MaxRacers` (8).

If you have no SpawnLocation the kart falls back to `(0, 10, 0)` and
warns in Output.

---

## 3. Optional: your own kart art

Put a Model named **`KartVisual`** in `ServerStorage`. It should face
`-Z` and sit around the origin. It gets welded on as decoration —
non-colliding, massless, no say in the handling.

- Parts named `Chassis` or `Nose`, or tagged `KartPaint`, get the
  racer's grid colour. Everything else keeps its authored colour.
- A part named `SteeringWheel` inside it is used as the wheel and gets
  the steering Motor6D. Add `GripL` / `GripR` attachments to it for the
  hands.
- **Road wheels**: tag them `KartWheelFront` (steer + roll) or
  `KartWheelRear` (roll only). Untagged parts named `WheelFL`/`WheelFR`/
  `WheelRL`/`WheelRR` work too. They get a Motor6D instead of a weld,
  because a weld can't be rotated at runtime.
  - Wheels rotate about **their own pivot**, so set the origin at the
    centre of the wheel in Blender. Anchored anywhere else it orbits that
    point instead of spinning, which looks like the wheel came off.
  - If they spin like plates instead of tyres, your mesh rolls about a
    different axis — set `Config/Rig.RoadWheelAxis` to `Vector3.zAxis`.
  - The fronts **counter-steer through a drift**, staying pointed down
    the road while the body slides. `Config/Rig.RoadWheelCounterSteer`
    (0.85); set 0 to have them just follow the body.

**Don't include a `Seat` or a part named `Hitbox`** — the factory builds
both and strips yours on clone, so a whole modelled kart is fine to drop
in as-is. It also forces `CanCollide`, `CanQuery` and `Massless`, so
don't bother setting those either.

**Per-player art**: `Config/Rig.VisualByPlayer` maps a username to a
model name for trying a new kart on one account. Cosmetic only — the
hitbox is forced to `HitboxSize` whatever the art is, so a bespoke kart
can never be a faster kart.

Without any of this a placeholder kart is built in code.

---

## 4. Controls

| Key | Does |
|---|---|
| `W` / `S` | Throttle / brake |
| `A` / `D` | Steer |
| `Space` | Hop-drift — hold with steering |
| `Shift` | Nitro. **One tap per tank**: 1 → 2 → 3 |
| `Q` | Use item |
| `R` | Reset to last checkpoint |
| `F` | Ready up (during the intermission) |
| `C` | Look back |
| Hold RMB | Free look |
| `H` | Hide / show the controls list |

---

## 5. Mobile

Nothing to set up. On a touch device with no keyboard, Roblox's default
controls are **disabled** and our own pad appears:

```
   ┌─────────────────────────────────────────────┐
   │                                             │
   │                                             │
   │  ┌──────┐                        ( ITEM )   │
   │  │BRAKE │                   (◎)             │
   │  └──────┘              ( N2O )   ╭───────╮  │
   │  ┌────┐┌────┐                    │ DRIFT │  │
   │  │ ◀  ││ ▶  │                    ╰───────╯  │
   │  └────┘└────┘                               │
   └─────────────────────────────────────────────┘
```

**Throttle is automatic.** You're always accelerating, so the left-hand
button is a **brake** instead — that's the input you actually make
decisions with, and a phone has no room for an accelerator you'd hold for
three minutes. Turn it off with `Config/Touch.AutoThrottle = false` if
you'd rather have a manual accelerator.

Everything is in `Config/Touch.luau`:

- **Move a button** — edit its `Position`
- **Add one** — add a row to `Buttons` plus a case in `TouchHud`'s
  `ACTIONS` table. Nothing else.
- **Test the layout on a PC** — set `Mode = "always"`

`Mode = "auto"` deliberately treats a **keyboard as disqualifying**
rather than a touchscreen as qualifying, so a touchscreen laptop still
gets the keyboard layout.

> ⚠️ The default controls are only disabled on touch. On desktop they
> *are* the driving input — the VehicleSeat reads WASD through them — so
> disabling them there stops the kart dead.

Touch steer and throttle are **added** to what the seat reports rather
than replacing it, so a device with both works with either and there's no
"which input wins" rule to get wrong. On desktop the touch values stay 0
and the behaviour is bit-for-bit unchanged.

---

## 6. Where the settings are

`ReplicatedStorage/BloxKart/Config/` — one module per concern.

| Module | Contains |
|---|---|
| `Handling` | speed, steering, drift, grip, acceleration curve |
| `Nitro` | tanks, fill rate, burn stages |
| `Items` | box tag, respawn time, use key |
| `Race` | tags, lap count, checkpoint rules |
| `Match` | field size, phase lengths, countdown, results board |
| `Respawn` | void tag, fall distance, reset key |
| `Rig` | kart build, grid, colours |
| `Camera`, `Audio`, `Effects`, `Hud`, `Rider`, `Input` | as named |

**Nothing in `Handling` is measured off the art.** Swap the visual model
and the driving is bit-for-bit identical — that's deliberate and it's the
one rule worth not breaking.

---

## 7. The match loop

Nothing to tag. It runs itself as soon as there's a player.

```
Waiting  →  Intermission  →  Grid  →  Racing  →  Results  →  ⤾
```

| Phase | What happens | Length |
|---|---|---|
| **Waiting** | Not enough racers. Status line shows `1 / 2`. | until `MinRacers` |
| **Intermission** | Countdown to the next race. `F` readies up; everyone ready skips the wait. | `IntermissionTime` (8s) |
| **Grid** | Karts teleported to their slots and **held still**. 3-2-1 on screen. | `GridTime` (4s) |
| **Racing** | Released, clock starts. | until everyone finishes |
| **Results** | Finishing order and times. | `ResultsTime` (10s) |

All of it in `Config/Match.luau`.

### Things worth knowing

- **You can drive between rounds.** Deliberate — warming up on the track
  is how you learn it. Nothing counts: laps are ignored, item boxes
  won't give you anything, and you can't fire.
- **Nitro and items don't carry over.** Both are wiped entering the grid.
- **The countdown is computed from a server deadline**, not ticked over a
  remote, so every screen shows the same number.
- **Once the leader finishes**, everyone else has `FinishGrace` (45s) to
  come in before the round is called.
- `MinRacers` is `1` so you can test alone. Raise it for a real lobby.

### Setting up a start line

The match teleports karts to the grid in front of your `SpawnLocation`,
so **the SpawnLocation is the start line** — point it down the track.
Tag the same part `RaceStart` + `RaceEnd` for a circuit.

---

## 8. Test mode

`Config/Rig.TestMode`:

- `true` — one kart on the pad, walk into it, `E` to get out
- `false` — one kart per player, spawned already seated, no exit

Pair it with `Config/Input.AllowExit`. Flip both together.

⚠️ **Test mode has no match.** The shared kart on the pad isn't assigned
to a player, so the match never leaves `Waiting` and you free-drive
forever. That's usually what you want from test mode — but the countdown
and results can only be tested with `TestMode = false`.
