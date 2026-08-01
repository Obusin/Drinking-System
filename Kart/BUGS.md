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

# 1. CONFIRMED — bots leave the track constantly

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

**Not yet investigated.** Different nodes each time rules out one bad
corner. Candidates, in the order worth checking:

- The pure-pursuit lookahead against `cruise` speed — the controller was
  tuned against a specific speed range and `CruiseMin` has since been
  raised to 0.92
- `lineBias` — bots deliberately drive off-centre; if the bias plus the
  corner-cutting exceeds the road width, the line itself leaves the road
- The route's own width data (`leftWidth`/`rightWidth`) being wrong at
  those nodes, so the bot thinks it is on tarmac

**Start by drawing the racing line** (`Bots.Debug`) and watching one bot
through node 1–2 rather than guessing from the log.

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

# 4. SUSPECTED — takeover bots outlive the round

```
21:37:25 [Loop] Intermission round 1 | karts 1 (1 player)
21:37:29 [BotService] Racer (AI) recovered by the flying watchdog (x2)
21:37:29 [Loop] Grid round 2 | karts 5 (1 player)
```

Two `Racer (AI)` entries were still being stepped four seconds into
Intermission, after every bot kart had gone. `releaseTakeOvers` removes
a takeover only when its kart still exists AND is still `AI_DRIVEN`; a
takeover failing both is stranded in `bots` forever.

Retirement was destroying those karts, so this may be gone with it.
**Verify before fixing** — the whole point of this file.

---

# 5. OPEN — two client-authority seams

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

# 6. OPEN — nine quests can never complete

`skinsEquipped`, `kartsRaced`, `partsOwned`, `craftsClaimed`,
`matchedSetRaces`, `friendsRaced`, `clubmatesRaced`, `fullLobbyRaces`,
`humansBeaten`.

The generator filters them out, so nobody is handed a dead bar — the
Weekly Social and Collection slots simply come up empty, which is what
the startup warning says. Five of the nine land the moment the garage
exists.

---

# 7. OPEN — MatchService is past Luau's inference budget

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

1. **Verify the loop closes over three rounds.** Everything else is
   guesswork until the trace is clean — and two entries above are marked
   SUSPECTED precisely because retirement may already have taken them.
2. **Bots leaving the track.** The biggest quality problem and entirely
   independent of the loop.
3. **The two trust seams.** Cheap, scoped, and they unblock leaderboards
   and safe persistence.
4. **Then the shop** — see the vault README. Everything built earns
   currency and nothing spends it.
