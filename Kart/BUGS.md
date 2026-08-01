# BUGS — what is broken, what is suspected, and why it keeps happening

Working log. `FINDINGS.md` is the permanent record of mechanisms learned;
this is the live list of things that are currently wrong.

**Read this before fixing anything.** Most of the bugs below were caused
by a fix for the one above it.

Last reviewed: 2026-08-02, after deleting kart retirement.

---

## How to use this file

Every entry is one of:

| | |
|---|---|
| **CONFIRMED** | reproduced, or a log line proves it |
| **SUSPECTED** | reported but not yet traced to a line |
| **WATCH** | fixed, but the fix is new and unproven |

A bug moves to `FINDINGS.md` when it is fixed **and** the mechanism is
worth remembering. It is deleted from here when it is fixed and boring.

**The loop trace is the primary instrument.** `Config.Match.LoopTrace`
prints one line per phase change:

```
[Loop] Racing  round 2 | people 1 | karts 5 (1 player) | finishers 0 | results 0
```

Every number decides something. `people` gates every transition, `karts`
is what the end condition counts, `(n player)` catches a kart going
missing, `finishers` ends a race early. A round that misbehaves is
diagnosable from these four without reading code — and that is the point,
because six of the bugs below were misdiagnosed by reading code.

---

# 1. CAUSE FOUND — bots leave the track constantly

**The biggest open problem, and the oldest.**

```
[BotService] Bolt2 left the track — 123 studs RIGHT of the racing line near node 1.2 (road is 120 wide)
[BotService] Rusty1 left the track — 69 studs RIGHT near node 2.0
[BotService] Nitro3 left the track — 243 studs RIGHT near node 13.5
```

Four bots off the track in ninety seconds, at four different nodes, in
both directions. The diagnostic's own conclusion is right: off-centre by
more than half the road means **steering off, not falling through**.

**Why it matters more than it looks.** Races drag — the field wanders
off, takes ages to get round, and a three-lap race runs the full
five-minute limit. Every "the race never ends" complaint traces back
here.

### Cause found 2026-08-02: bots ignored void zones entirely

A player gets three ways back — the `VoidZone` tag, freefall time, and a
world floor. **A bot only ever had the floor.** So a void that is a
PLANE at track level (water, lava, a shallow pit) never triggered, and
the bot drove straight through it and kept going outside the track until
it happened to fall far enough to trip `RespawnBelow`.

They were not leaving the track once. They were leaving it and
continuing to drive around out there, reported each time they eventually
dropped.

Bots now use the same tag and the same `TagZones` helper as the player.
It has to be the same one — a second answer to "where is the void" is
this project's oldest bug shape.

One instance shared by every bot, with **no cooldown of its own**:
`TagZones` remembers the last touch per PART, so a shared cooldown would
let the first bot into a pit swallow every other bot's touch of the same
pit. The wait is per bot instead.

**WATCH — unproven.** If bots still wander, the remaining candidates
are:

- The pure-pursuit lookahead against `cruise` speed — the controller was
  tuned for a speed range and `CruiseMin` has since risen to 0.92
- `lineBias` — bots deliberately drive off-centre; bias plus corner
  cutting may exceed the road width
- The route's own width data being wrong at those nodes

---

# 2. CONFIRMED — two currency icons are bad assets

```
[RewardHud] image still not loaded after 20s: rbxassetid://78484915579310
[RewardHud] image still not loaded after 20s: rbxassetid://107666490588324
```

Bolt and Nitro Crystals. **Not a code bug** — the 20-second poll is the
honest one and the wipe mark (`97017994154540`) loads fine through the
same path.

Either Decal ids where Image ids are needed, uploaded under an account
that is not this place's owner, or not yet approved. Insert each in
Studio, read back the `Texture` property, replace the ids in
`Config/Rewards.luau`.

---

# 3. SUSPECTED — spectating does not work properly

**Most likely the same cause as #4.** A frozen camera is what a stranded
takeover produces, and it was reported as "spectate doesn't work".
Re-test before investigating.

Reported, not yet traced. Every code path checks out on inspection:
starts on finish or at the flag, holds your own kart through the finish
shot, falls through when a subject disappears, releases the driving
bindings, excludes your own kart from cycling.

**Most of what was wrong was probably retirement** — your kart was
destroyed before the board appeared, so the camera had nothing to hold.
That is deleted; this needs re-testing before it is worth investigating.

**If it is still wrong, say WHICH:** the camera not moving, Q/E not
cycling, free cam not engaging, or the wrong subject. Those are four
different bugs.

---

# 4. CONFIRMED AND FIXED — takeover bots outlived the round

**This was the cause of the frozen camera, the wobbling immovable kart,
and most of what looked like disappearance.** Promoted from SUSPECTED by
a traced round, then fixed.

`releaseTakeOvers` required the kart to still exist AND still be
`AI_DRIVEN`. Anything failing either test stayed in `bots` forever —
stepped every frame, counted by the flying watchdog, one more stranded
entry per round:

```
23:37:44 [Loop] Intermission round 1
23:37:48 Racer (AI) recovered by the flying watchdog  ×4
```

Three consequences, all reported as separate bugs:

- **The kart welded to you that will not move.** `AI_DRIVEN` never
  cleared, so it stayed anchored and server-owned.
- **The frozen camera.** The client's `step()` returns early on
  `AI_DRIVEN`, and everything after that line — the camera included —
  stops running.
- **The wobble.** An anchored kart with a seated character, replicating
  at 20Hz and going nowhere.

Released on `takenOver` now, which is intrinsic to the entry, and dropped
from the list either way. `AI_DRIVEN` is an attribute anything can
clear, and keying the release on it meant one stray write stranded a
player for the life of the server.

**WATCH:** unproven, one session old.

---

# 4b. FIXED — Sit threw every watchdog sweep

```
Sit : param is not a Humanoid or humanoid is dead
```

A humanoid can be in the `Dead` state with `Health` still above zero for
a frame — mid-respawn, or as its character is replaced — and the seat
watchdog's `Health > 0` guard let it through. Sit then threw once per
sweep, forever.

Guarded on the state and pcall'd. A failed seating is a retry in two
seconds; a thrown error is a red line every two seconds for the life of
the server.

---

# 5. OPEN — a player joining mid-race gets no kart

Reported 2026-08-02, **not yet traced.** Reading the path found nothing:
`PlayerAdded` connects `CharacterAdded` and calls `reload`, which loads a
character, which spawns a kart, which seats them. Every link exists and
every failure is already pcall'd and warned.

So it is instrumented rather than guessed at. A join now prints three
lines, unconditionally:

```
[KartService] <name> joined — waiting for a character
[KartService] <name> character arrived
[KartService] <name> kart BUILT, seated yes
```

**Whichever line is missing is the answer, and they need different
fixes:**

| Missing | Means |
|---|---|
| "joined" | `PlayerAdded` never fired — the service started after they joined |
| "character arrived" | `LoadCharacter` did not produce one; autoloads are OFF, so nothing else will |
| "kart BUILT" | `spawnKartFor` threw — the warn above it names the error |
| `seated NO` | the kart exists and they are not in it; a seating problem, not a spawn one |

Note that a mid-race joiner is placed on the **grid**, because that is
where `createKart` puts a kart and `assignGrid` only runs at
`startGrid`. That is a separate question — where a late joiner SHOULD
start — and worth deciding once the kart itself appears.

---

# 6. OPEN — two client-authority seams

Marked in code, not bugs today, and blocking a lot.

| Seam | Where |
|---|---|
| Finish time is the client's word | `MatchService.luau:485` |
| Upward progress is unvalidated | `RaceService.luau:683` |
| Driving stats are client-reported, only clamped | `Progress.report` |

Today these are unfairness. They become **currency printers** the moment
persistence is trusted, and they block every Tier 2 leaderboard — a
0.001-second lap on a global board is permanent and public.

Both TODOs already describe their own fix.

---

# 7. OPEN — nine quests can never complete

`skinsEquipped`, `kartsRaced`, `partsOwned`, `craftsClaimed`,
`matchedSetRaces`, `friendsRaced`, `clubmatesRaced`, `fullLobbyRaces`,
`humansBeaten`.

The generator filters them out, so nobody is handed a dead bar — the
Weekly Social and Collection slots simply come up empty, which is what
the startup warning says. Five of the nine land the moment the garage
exists.

---

# 8. OPEN — MatchService is past Luau's inference budget

`BotService` is 2393 lines, `init.client` 1039, `RaceService` 987. Not
urgent, and it makes everything after it slower — including the analysis
that would catch the next bug in this file.

---

# WATCH — recently fixed, unproven

Each of these has run for at most one session. If something in this area
misbehaves, suspect the fix before anything else.

- **Retirement deleted.** Karts stay all round; the AI drives finished
  ones. Removed `scheduleRetire`, `RETIRE_AT`, `KartService.retire`,
  stash/unstash, `reviveRetired`, `awaitingRevive`.
- **Race ends on `stillRacing() == 0`**, not `finishers >= racerCount()`.
- **Ghost registry entries** cleared for any racer, and `fill` drops
  through `KartService.dropRacer`.
- **Rig collision** re-asserted on a poll instead of `Physics` state.
- **The personal board** gets its own reward payload on finish.
- **Character stash** — deleted along with retirement. If a player ever
  comes back invisible, this left something behind.

---

# THE PATTERNS

Six of the bugs above were caused by the fix for another. These are the
shapes, and they are worth more than any individual entry.

### 1. One question answered in two places
The oldest and most expensive. Trigger tags, device detection, ray
filters, road width, `orderOf`, the Standings third field, `finishers`
vs `racerCount`, two flags for one panel. **Extract the shared answer;
do not fix the copy you can see.**

### 2. Something assumes a Player behind the kart
Bots invulnerable for a session. Bots unable to finish. Names showing as
"Racer". **Ask what happens when there is nobody there.**

### 3. A feature added, then six fixes to contain it
Retirement caused: the respawn at the spawn point, the 0/1 deadlock, the
missing kart, the race ending a lap in, ghost registry entries, and
detached rigs. Every fix was real and every one was downstream.

**The rule: when a fix is downstream of something added within the last
few changes, question the addition before writing the fix.**

### 4. The clever mechanism over the boring one
`Physics` state to clear a collision flag — and it broke seating. A poll
was correct and is what it ended up as.

### 5. A watchdog racing the thing it watches
The no-kart sweep rebuilt karts that `CharacterAdded` was already
building. **A safety net must be slower than the path it is catching.**

### 6. Units and clocks
`os.clock()` across the wire. Throttle as a gate not a dial. A
probability rolled per step. A turn rate implying a turning circle.
Metres versus a fraction. Skill lerped by its raw value rather than its
range. **Write down what the number MEANS before tuning it.**

### 7. Config keys the type checker cannot see
`WarnedText` deleted by a slice edit froze the camera. `DodgeAt` put in
the wrong table errored every frame. **`scripts/check.sh` now runs
`config-keys.py`, which walks every alias and every direct read.**

---

# ORDER OF ATTACK

1. ~~Verify the loop closes.~~ **DONE 2026-08-02.** It does:
   `karts 5 (3 player)` held from Grid through Results into round 2,
   with three players. The trace also caught #4, which was the real
   cause of three separately-reported bugs.
2. **Bots leaving the track.** The biggest quality problem and entirely
   independent of the loop.
3. **The two trust seams.** Cheap, scoped, and they unblock leaderboards
   and safe persistence.
4. **Then the shop** — see the vault README. Everything built earns
   currency and nothing spends it.
