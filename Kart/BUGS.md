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

# 5. CAUSE FOUND — a joining player's kart art floats free

They drive normally; the bodywork drifts along behind. The kart's HITBOX
is fine — only the visual came loose.

**The skin swap.** `ApplyMesh` replaces a MeshPart's geometry, and a part
whose geometry has been replaced can leave its assembly: unwelded,
unanchored, free. The swap is asynchronous — `CreateMeshPartAsync`
fetches over the network — so it lands AFTER `KartFactory` has welded
everything, which is why nothing in the build path looked wrong.

A joining player shows it most because their kart is built while the
server is busy, so the race between the weld and the swap is at its
widest.

`Skins` now checks assembly identity after every swap and puts the part
back. Assembly rather than "does it have a weld", because a part
attached through several joints still shares a root with the hitbox and
only a genuinely loose one does not.

**Wheels get their Motor6D rebuilt, not a weld** — welding one back
gives a kart that drives with four locked tyres, which looks fixed until
somebody turns.

**WATCH — unproven.** It warns when it fires:
`[Skins] <part> came loose after the mesh swap`. If that line never
appears and the art still floats, the cause is in `KartFactory` and this
was the wrong tree.

---

# 5b. OPEN — a player joining mid-race gets no kart

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

# 9. FOUND BY INSPECTION — the track is cached by COUNT

Not reported by anyone. Found while auditing what a second map would
break, and it would break this immediately.

`Route.nodes()` is the single source for the racing line — bots steer by
it, missiles follow it round corners, the minimap is drawn from it. It
caches, and it invalidates the cache like this:

```lua
local parts = CollectionService:GetTagged(R.CheckpointTag)
if cache and cachedCount == #parts then
	return cache      -- Route.luau:129
end
```

**The number of checkpoints is not the identity of a track.** Swap map A
for map B with the same checkpoint count and every consumer keeps
steering to map A's coordinates. Bots drive at where the old corners
were; missiles curve toward a road that is not there.

It is also wrong without any map swap: MOVE a checkpoint in a live
server and nothing notices, because the count did not change.

**The fix is a generation number**, not a deeper comparison. Anything
that changes the track bumps it; the cache stores the generation it was
built from. One integer, and it is correct for edits, swaps and reloads
alike — a comparison can only ever be correct for the cases somebody
thought of.

### The same bug, again, on the client

`Minimap.luau:137`:

```lua
if #nodes < MIN_NODES or #nodes <= self.builtCount then
	return                -- only ever redraws when the count GROWS
end
```

A track with the same number of checkpoints, or fewer, leaves the old
outline on screen for the rest of the session.

**Two modules, one mistake, and it is PATTERN 1 — one question answered
in two places.** Both are asking "is this still the same track", and
neither can actually tell.

---

# 10. FOUND BY INSPECTION — a mid-race joiner is entered into the race

`KartService` does not know what phase it is. Not "gets it wrong" —
there is no reference to `MatchService.phase()` anywhere in the file.

So a player who joins during RACING is handed a kart at the spawn pad
and is in the round, on lap 0, two laps behind. Consequences, all real:

- They appear in the standings, last, and stay there.
- `stillRacing()` counts them, so the "everyone is in, settle fast" path
  can never fire for the rest of the round. The round now always runs
  the full `FinishGrace`.
- If they do cross the line they are given a finish place, a time, XP,
  and a Bolt payout for a race they were not in.

Nothing deadlocks, which is why it has never been reported. It is just
wrong every time it happens.

**The fix is the same shape as the matchmaking work**: a joiner should
be a spectator until the next GRID, which is the one place a round is
set up. `startGrid` already reloads and reseats everybody, so the entry
point exists — what is missing is anything saying "not yet".

---

# 11. CONFIRMED — Studio is writing to real profiles

`Config.Data.LiveInStudio = true`. It was turned on deliberately to
prove persistence survives a rejoin, and it was never turned back off.

Every Studio playtest is now reading and writing the REAL profile on
your account, with the same keys a published server uses. A test that
corrupts data is indistinguishable from a bug that does.

Turn it off. The mock store behaves identically in every way except
surviving, and the question it cannot answer has already been answered.

---

# 12. STRUCTURAL — two maps cannot share one place

Everything about the track is discovered by CollectionService tag:
`RaceStart`, `RaceEnd`, `Checkpoint`, `VoidZone`, `Surface`, boost pads,
item boxes, plus the SpawnLocation that `Placement.findSpawn` picks by
walking the workspace for the first enabled one.

Put two maps in one place and every one of those queries returns both
maps' parts. Checkpoint orders collide, the route becomes a line
stitched between two tracks, and the grid lands on whichever spawn pad
the descendant walk happened to reach first.

This is not a defect — the tag design is right, and it is why a track is
built by tagging rather than by wiring. It is a constraint: **one map
per place, or exactly one map parented into the workspace at a time.**
Which one is the decision in front of the matchmaking work.

---

# 13. STRUCTURAL — none of the content is in source control

`Drinking System.project.json` syncs ReplicatedStorage,
ServerScriptService, ServerStorage, StarterGui, StarterPack and
StarterPlayer. **There is no Workspace key**, and `src/ServerStorage` is
empty apart from a `.DS_Store`.

So git has every line of code and none of the content:

- the track — every road part, every tagged checkpoint, void zone,
  boost pad and item box
- the kart art model `KartFactory` clones
- the missile model `Assets` copies out

All of it exists in exactly one place: the `.rbxl`. A Studio sync has
already deleted the entire source tree once, and **git was the only copy
and it was enough** — that is in FINDINGS. It would not be enough now.
The code would come back and the track would not.

This has been survivable while there is one place. It stops being
survivable the moment a second place exists, because then the question
"which place has the good copy of the track" has two answers and no
authority.

**Fix it before duplicating anything.** Either sync Workspace and
ServerStorage as `.rbxmx`, or publish the track and the kart as Models
and reference them by asset id — the second is also what a map-per-place
setup wants anyway.

---

# 14. FIXED 2026-08-02 — the finish remote trusted the client's clock

Was: `finishRemote.OnServerEvent:Connect(function(player, totalTime) ...`
— validated only that `totalTime` was a real non-negative number.
`Config.Data.Enabled` went on 2026-08-01, so for a full day every finish
banked a real, persisted reward from a number the client picked.

Now the server computes elapsed time itself from
`MatchService.racingSince()`. The client no longer sends a time at all —
`finishRemote:FireServer()` with no argument — so there is nothing to
forge.

`Progress.luau`'s header comment claimed persistence did not exist yet,
which was true the day it was written and false for the day this bug
was live. Fixed alongside — see FINDINGS, "a comment asserting something
is not evidence it is true."

Full detail: `Kart/SECURITY.md` §4.1.

# 15. OPEN, DELIBERATELY NOT FIXED — a finish is never checked against

  actual race progress

Found while fixing #14. The clock is now honest; whether the racer
actually raced is not checked at all. `finishKart` requires only
`phase == Racing` and "hasn't already finished" — nothing ties a finish
claim to laps or checkpoints. A client can fire the finish remote at the
green light and claim first place.

The fix is bounded by data that already exists — `Standings.ATTRIBUTE`
is a replicated progress score, and "actually finished" is roughly
`score >= TotalLaps * 1e6`. Not shipped without playtesting: the score
is itself client-reported and can lag a crossing by a frame or two, and
a wrong tolerance rejects a legitimate finish silently, which is worse
than the hole it closes. Land it behind a generous tolerance, watch
several real races confirm cleanly, then tighten.

---

# 16. FIXED 2026-08-02 — the lobby could quietly farm quest progress

Items went live in the lobby for practice (BUGS is silent on this
because it was never a bug — it was the design). What came along for
free: `RaceService.relayHit`, `RaceService.creditVoidKill` and the
client's stats batch all feed `Progress` unconditionally, and none of
them ever asked what kind of server they were running on. A hit, a void
elimination, or a drift/boost tally in the practice ring paid exactly
the same XP, Bolt and quest progress as the identical thing on a track.

Gated the three entry points a lobby can actually reach —
`Progress.hit`, `Progress.eliminated`, `Progress.report` — behind
`Place.isRace()`. `Progress.finished` needed no equivalent guard:
`MatchService` never starts outside a race place, so there was never a
path to it from a lobby.

Zero behaviour change on a race place. `Place.isRace()` is a place-wide
constant, always true there, so this is purely an added gate on the
lobby side — nothing about when items are pickable during a real round
moved.

**Open question, not urgent:** should ANYTHING be earnable in the
lobby — a quest for calling your kart, or visiting the practice ring?
Nothing today is, and nothing asked for it. If one ever should be, it
wants a metric-level flag in `Config/Quests.luau` rather than another
exception carved into `Progress.luau` — the guard above is deliberately
one rule for all three entry points, not a per-metric one.

---

# 16b. FIXED 2026-08-02 — #16 closed the bank, not the display

Reported directly: drift progress still visibly climbed in the lobby
after #16 shipped. Correct — #16 gated the SERVER's book-keeping
(`Progress.report`), and never touched the CLIENT's own count.

`Tally:Add` was unconditional. Drifting in the lobby still incremented
`self.n.driftSeconds` locally; `Flush()` still sent the delta, marked it
`sent` regardless of whether the server did anything with it, and held
the bar up via `unacked` until the next quest sync. The number was real
on screen and fictional everywhere else — it would have sat there
until the next server push quietly took it back, which reads as a
scam-y bug rather than a rejected report.

`Tally:Add` now gates on the same `Place.isRace()` the server checks, so
the count never starts and the bar never moves in the first place. One
line, and it is the client half of "presentation must default to
correct" — a number should not be shown before it is true.

---

# 17. FIXED 2026-08-02 — a called kart spawned at the build position, not the player

Reported directly: calling a kart in the lobby put it at the
SpawnLocation rather than in front of the player.

`PlayerVehicleService` built the kart via the normal path — which
places it wherever a fresh kart is created — then called
`kart:PivotTo(cf)` to move it, on the reasoning that nothing had claimed
the part yet. Wrong: `KartService.spawnFor` also SEATS the player as its
last step, and seating changes the seat's Occupant, which fires
`bindOwnership` SYNCHRONOUSLY — unanchoring the hitbox and handing it to
the player's network ownership before the `PivotTo` line ever ran.

A server CFrame write on a kart owned that way is exactly the race
`KartService.assignGrid`'s own comment already warns about: it can lose
to the client's `Simulation` the instant that client constructs one,
which reads the hitbox's CFrame at whatever moment it happens to
observe it — sometimes the pre-request build position, sometimes the
pivot, depending on replication timing. That inconsistency is why it
looked like it "sometimes worked."

Fixed the same way the grid and every checkpoint respawn already do it:
an attribute (`Names.VEHICLE_SPAWN_CF`), never a direct move. The client
reads it once on attach and calls `Simulation:RespawnAt` itself — one
door every teleport in this game goes through, now including this one.
Attributes aren't subject to the ownership race at all: physics
properties are what network ownership governs, not attributes, so this
was never actually a hard problem — it was a `PivotTo` where an
attribute belonged.

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
4. **#13 before any second place exists.** The track is not in git.
   Everything below is safe to get wrong; this one is not recoverable.
5. **#11 first, it is one word.** Studio is writing live profile data.
6. **#9 before any second map exists.** A generation number on the route
   cache. Cheap now, and it is the thing that will make a map swap look
   like the bots have gone mad.
7. **#10 with the matchmaking work**, not before — the fix is the same
   fix, and doing it twice is Pattern 1 all over again.
8. **#15 next**, once there has been a chance to watch several real
   finishes land clean under the #14 fix — the completion check needs
   proof it will not reject a legitimate one.
9. **The remaining trust seam** (upward progress-score jump, SECURITY.md
   §4.4), then **the shop** — see the vault README. Everything built
   earns currency and nothing spends it.
