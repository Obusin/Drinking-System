# BloxKart — The Game Loop

Written 2026-08-02, after a run of bugs each fixed downstream of the
last. Updated the same day, after deleting retirement and tracing a
healthy round. This is what the loop is SUPPOSED to do, so the code can be
checked against something rather than against memory.

Related: `README.md` · `BUGS.md` · `FINDINGS.md` · `SPEC-match.md`

---

## The five phases

```
        ┌──────────────────────────────────────────────┐
        │                                              │
        ▼                                              │
    WAITING ──(≥1 human)──► INTERMISSION ──(timer│ready)──► GRID
                                 ▲                          │
                                 │                     (GridTime)
                                 │                          ▼
                             RESULTS ◄──(time up│all in)── RACING
                                 │
                        (no humans) └──► WAITING
```

**One rule holds the whole thing together: a phase change is the ONLY
thing that may move a kart, build one, or take one away.** Everything
that has gone wrong in this loop has been something doing one of those
three at another time.

---

## What each phase owns

### WAITING
Nobody is here, or not enough people are.

- Bots: exist, parked, not driving
- Players: have a kart, can drive freely
- Leaves for INTERMISSION the moment `humanRacers() >= MinRacers` (1)

### INTERMISSION
The lobby. A countdown, and a ready-up.

- Karts the AI took over last round go back to their owners at the GRID,
  not here
- Bots: parked
- Players: have a kart
- Leaves for GRID on the timer, or when every human is ready

### GRID → `startGrid()`
The one place a round is set up. Order is load-bearing:

1. `round += 1`, paint palette rotates
2. **`onRelease`** — karts held by the AI go back to their owners
3. **`onGrid`** — bot field topped up to `FillTo - humans`
4. `clearFinishes()` — finish attributes, progress scores, the results
   record, and `finishers = 0`
5. `clearHazards()`
6. `assignGrid()` — every kart stamped with where it starts
7. `enter(GRID)` — clients apply the stamp and hold

Release before fill, or the field is sized against a bot count that is
about to shrink.

### RACING
- Karts move, laps count, items work
- A racer crossing the line: `finishKart` → place, time, XP, ledger row,
  their board sent, and **the AI takes their kart**
- **Ends when `stillRacing() == 0`**, or the clock runs out. Counting who
  is LEFT, never `finishers` against a racer count — those two move
  independently and comparing them ended races a lap in

### RESULTS
- **Every kart still driven by a person goes to the AI** (`takeOverAll`)
- The board is sent to every player
- Karts KEEP MOVING — `isRolling` is true here, `isDriving` is not
- Ends on `ResultsTime`, back to INTERMISSION

---

## What happens to one player, end to end

| Moment | Kart | Character | Camera | UI |
|---|---|---|---|---|
| Racing | theirs, they drive | seated | chase | HUD |
| Cross the line | **AI takes it** | seated | finish shot | `FINISH · P3` |
| +3s | AI still driving it | seated | spectator | **their board** |
| Flag | AI still driving it | seated | spectator | **final board** |
| Grid | **handed back** | seated | chase | lobby |

**NOTHING IS DESTROYED AND NOTHING RESPAWNS.** A kart exists from the
moment it is built until the player leaves. The AI borrows it; it is
handed back at the grid by `releaseTakeOvers`.

This is the single most important line in this document. Retirement —
destroying a finished racer's kart — was tried on 2026-08-02 and caused
**six** separate bugs: the respawn at the spawn point, the 0/1 deadlock,
the missing kart, the race ending a lap in, ghost registry entries, and
detached rigs. Each was real, each was fixed, and each was downstream of
a feature nothing needed. It is deleted rather than guarded.

**If a kart ever needs to leave mid-round, do not destroy it.** Park it,
hide it, or stop stepping it. The moment a kart is destroyed, something
has to rebuild it, and the rebuild is where every one of those six bugs
lived.

---

## The invariants

These are the things to check when the loop misbehaves. Each has been
violated at least once and each cost a session.

1. **Only `KartService` builds or destroys a player's kart.** `BotService`
   owns bot karts and nothing else. A taken-over kart is a player's.
2. **A phase change is the only thing that may move a kart.**
3. **`humanRacers()` counts people, not karts.** Someone between lives is
   still someone, or a solo lobby deadlocks.
4. **`finishers` resets in `clearFinishes`, which only `startGrid` calls.**
   If it survives a round, the next race ends the instant it starts.
5. **A takeover is not a bot.** It must never be trimmed, revived, or
   replaced by anything that manages the bot field.
6. **`isDriving` means "does this count". `isRolling` means "do karts
   move".** Results is rolling but not driving.

---

## What a healthy round looks like

Traced 2026-08-02, three players:

```
[Loop] Waiting      round 0 | people 0 | karts 0 (0 player) | finishers 0
[Loop] Intermission round 0 | people 1 | karts 3 (1 player) | finishers 0
[Loop] Grid         round 1 | people 3 | karts 5 (3 player) | finishers 0
[Loop] Racing       round 1 | people 3 | karts 5 (3 player) | finishers 0
[Loop] Results      round 1 | people 3 | karts 5 (3 player) | finishers 5
[Loop] Intermission round 1 | people 3 | karts 5 (3 player) | finishers 5
[Loop] Grid         round 2 | people 3 | karts 5 (3 player) | finishers 0
```

**Read it as four assertions:**

1. `karts` never drops between Grid and the next Grid. A fall means
   something destroyed one — and only `KartService` may.
2. `(n player)` equals the number of humans, always. If it falls, a
   player's kart went and they are about to be stuck.
3. `finishers` reaches the field size at Results and is **0 again at
   Grid**. Surviving the reset ends the next race instantly.
4. `people` never reads 0 while somebody is in the server. It gates
   every transition, and 0 is the deadlock.

Anything else — a bot off the track, a stranded takeover, art floating —
shows up in warnings, not here. The live list is `BUGS.md`.
