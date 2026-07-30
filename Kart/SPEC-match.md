# SPEC — the match loop

How a race starts, ends, and starts again.

---

## The state machine

```
        ┌──────────────────────────────────────────┐
        ▼                                          │
   ┌─────────┐  enough    ┌──────────────┐         │
   │ Waiting │───────────▶│ Intermission │         │
   └─────────┘  racers    └──────────────┘         │
        ▲                        │ timer, or       │
        │ everyone               │ everyone ready  │
        │ left                   ▼                 │
        │                  ┌──────────┐            │
        │                  │   Grid   │  held      │
        │                  └──────────┘  3-2-1     │
        │                        │                 │
        │                        ▼                 │
        │                  ┌──────────┐            │
        └──────────────────│  Racing  │            │
                           └──────────┘            │
                                 │ all in, or      │
                                 │ grace expired   │
                                 ▼                 │
                           ┌──────────┐            │
                           │ Results  │────────────┘
                           └──────────┘
```

Server owns it. `MatchService` on a 0.2s tick — a match loop has no
business running per frame.

---

## The split: who owns what

This is the interesting part, and the reason the whole thing is only
~200 lines of server code.

| Owned by the **client** | Owned by the **server** |
|---|---|
| How the kart moves | Whether the race has started |
| Lap counting, checkpoints | Where each kart starts |
| Its own finish time | What place that finish is |
| Item pickup requests | Which item you get |

The simulation *has* to be client-side or it can't feel right — you
cannot put a round trip between the stick and the kart. But "has the
race started" cannot be a client's opinion, because two clients
disagreeing about that is two different races.

So: the client owns the *physics* of the gap between the lights and the
line. The server owns the lights and the line.

---

## The clock trick

The server never ticks a countdown over a remote. It publishes an
absolute deadline:

```lua
PhaseEndsAt = workspace:GetServerTimeNow() + duration
```

Clients subtract their own `GetServerTimeNow()`. That clock is
synchronised, so every screen shows the same number with **zero**
per-frame traffic, and a client that joins mid-countdown is instantly
correct instead of waiting for the next tick.

Ticking `3… 2… 1…` over a remote would drift, cost bandwidth, and land
on a different frame for every player.

### The release is local

The kart is released when the *client's* local clock passes the
deadline — not when the server says "go". No round trip between the
lights going out and control returning. The server transitions within a
tick either way, and it's still the only thing that decides whether a
finish counts, so nothing is given away by letting the client start
itself a few milliseconds early.

---

## Replication: attributes, not remotes

Two remotes total, both client→server (`Finish`, `Ready`). Everything
going the other way is an attribute.

**On a `MatchState` folder:**

| Attribute | Meaning |
|---|---|
| `Phase` | the state name |
| `PhaseEndsAt` | server time the phase ends, `0` for no deadline |
| `Racers` | how many karts the match owns |
| `Ready` | how many have readied |
| `Round` | increments per race; clients watch it to reset |

**On each kart:**

| Attribute | Meaning |
|---|---|
| `GridCF` | where this kart starts the round |
| `FinishPlace` | 1-based, absent until they finish |
| `FinishTime` | total elapsed |

Attributes replicate on join, so a late arrival sees the correct phase
and the current results board for free. A remote-based design would need
a "catch me up" round trip that this simply doesn't have.

The results board is *rebuilt from the karts in the world* rather than
from a list the server sent — there's no second copy to keep in sync.

---

## Why the server doesn't move the karts

`GridCF` is an attribute the **client** applies, via the same
`Simulation:RespawnAt` used for checkpoint respawns.

The server *can't* just `PivotTo` them: while a player is aboard, the
hitbox is network-owned by that player, so a server-side move is
overwritten by their very next simulation frame. Publishing the target
and letting the client put itself there means there's exactly one code
path that teleports a kart, not two that fight.

It's retried every frame until it lands, because `GridCF` and `Phase`
are separate attributes on separate instances — nothing guarantees the
CFrame arrives first.

---

## Hold vs. freeze

Two different things, deliberately separate fields:

| | `frozenUntil` | `held` |
|---|---|---|
| Set by | spinouts, stuns | the starting grid |
| Ends | at a known time | when told |
| Means | "you've been hit" | "you are not driving yet" |

Sharing one field would mean a stun expiring could release a kart the
match is still holding on the grid.

A held kart has `speed` zeroed every frame, not just its input ignored —
otherwise a boost that was live when the hold began would carry it off
the line. Gravity still applies, so karts settle onto the grid properly.

---

## Between-rounds free driving

Players **can** drive during `Waiting`, `Intermission` and `Results`.
Warming up on the track is how you learn it, and being frozen in place
for 18 seconds a round is miserable.

But nothing counts, and that needed four separate guards:

| Guard | Where | Why |
|---|---|---|
| `race.locked` | client | laps and checkpoints ignored |
| item boxes | **server** | else you'd hoover up the track and arrive holding three |
| hazard drops | **server** | no mining the grid before the lights |
| projectiles | **server** | a missile arriving while the field is pinned and can't dodge |

The three server-side ones are the real enforcement; the client-side
gate on `items:Update` exists so the HUD and sounds agree with the
server rather than showing a pickup the server refused.

Nitro and items are both wiped entering the grid. Carrying a missile
over from last round is a free hit on people who just joined.

---

## Where anti-cheat goes

`MatchService.recordFinish` is the one seam, and it's marked. The server
already knows two things it isn't yet checking:

1. **When `Racing` began** — a reported time shorter than the phase has
   been running is provably fake.
2. **The progress relay** — whether they ever reached the last
   checkpoint.

Both are a few lines *in that function*. The reason they're cheap to add
is that nothing else reads the finish attributes to decide a place —
only `recordFinish` writes them.

Same shape as `RaceService`'s progress relay: deliberately thin now,
with one obvious place to thicken.

---

## Known gaps

- **Times are still client-reported.** See above.
- **No hub.** This is one place, always the same track. A lobby that
  teleports into a race place is a different (later) problem — but the
  phase machine is exactly what the race place would run, so it's not
  wasted.
- **No bots**, so `MinRacers = 1` means a solo race against nobody.
- **No rematch grouping.** Everyone in the server is in the next round;
  there's no notion of a party staying together.
- **`TestMode` has no match** — the pad kart isn't owned by a player, so
  the count never reaches `MinRacers`.
