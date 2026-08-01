# BloxKart — the whole system, for someone with no context

Written for a reader who has never seen this codebase: a new
collaborator, or a language model being handed the project cold.
Everything here is true as of 2026-08-02. Where something is broken or
unfinished it says so, because a document that only describes the happy
path is worse than no document.

Companion files in this folder: `BUGS.md` (what is broken right now),
`FINDINGS.md` (the permanent engineering log), `GAME-LOOP.md` (the round
loop in detail), and four `SPEC-*.md` files.

---

# 1. What it is

**BloxKart** — an arcade kart racer in Roblox. The feel is Mario Kart /
Garena Speed Drifters: hop-drift, charged boost tiers, power-ups, no
realism. It is not a driving simulator and nothing in it tries to be.

Roughly 28,000 lines of Luau across 96 files. Solo play works today: one
human is enough to start a round and the rest of the field is AI.

---

# 2. The two rules that explain most of the decisions

If you only read two things, read these. Almost every design choice in
the codebase follows from one of them.

## 2.1 The controller is kinematic. Roblox physics never gets a vote.

A kart's position, forward vector, up vector and speed are integrated by
hand every frame in `Simulation.luau`, and the result is written to the
hitbox as a CFrame. There are no BodyVelocities, no VectorForces, no
constraint assemblies doing the driving.

An earlier build used real constraint physics. It was thrown away
because handling changed whenever the art changed, and because
Roblox's solver produces behaviour you cannot tune toward a *feel*.

Consequences that will otherwise surprise you:

- **`CanQuery` is the collision flag here, not `CanCollide`.** Movement
  is done with raycasts and `GetPartBoundsInBox`, so whether a part
  participates is decided by whether queries can see it. A part with
  `CanCollide = false` and `CanQuery = true` is *solid* to a kart.
- **Gravity is measured along the kart's own `up`, not world Y.** This
  is what makes loops and banked walls work.
- **Anything that teleports the kart goes through one function**
  (`Simulation:RespawnAt`), so there is exactly one way a kart moves
  without driving there.

## 2.2 The controller reads exactly two things off the kart model.

**The `Hitbox` and the `Seat`.** Never wheel size, never mass, never
part positions, never the art.

This is not tidiness. It is the guarantee the entire economy rests on:
**a cosmetic has nowhere for a stat to live.** Skins can be sold
because they provably cannot affect handling. Any change that makes the
controller measure the art destroys that claim and reintroduces the
problem that killed the physics build.

---

# 3. Repo and build

- Working copy: `~/Documents/Roblox Development`, branch `bloxkart`.
- Published to `https://github.com/Obusin/BloxKart-Prototype` via a
  remote *also* called `bloxkart`. `origin` is a different project
  (Drinking-System) that shares the folder. **Push to `bloxkart`, not
  `origin`.**
- Synced into Studio with **Argon** (a Rojo-compatible tool) using
  `Drinking System.project.json`.

The project file maps `src/ReplicatedStorage`, `src/ServerScriptService`,
`src/ServerStorage`, `src/StarterGui`, `src/StarterPack`,
`src/StarterPlayer`.

**It does NOT map Workspace, and `src/ServerStorage` is empty.** So git
holds every line of code and *none* of the content: the track geometry,
the kart art model and the missile model exist only inside the `.rbxl`
place file. This is a known and serious gap — see `BUGS.md` #13.

`./scripts/check.sh` runs `luau-analyze` (excluding `Packages/`) plus
`scripts/config-keys.py`. See §16 for why the second one exists.

---

# 4. Place architecture

The experience is more than one place, and **every place runs identical
code**. `Config/Places.luau` + `Place.luau` are the only things that
tell them apart.

| | Lobby | Race place |
|---|---|---|
| What it is | social hub, garage, queue, practice ring | one track |
| Round loop | no | yes |
| AI bots | no | yes |
| Karts | yes | yes |
| Power-ups | **yes** | yes |
| Lap timing | present but inert (no checkpoints tagged) | yes |

`Place.isLobby()` / `Place.isRace()` resolve **once, at require time**,
by comparing `game.PlaceId` against `Config.Places.LobbyPlaceId`.

Deliberately *not* by sniffing the world for checkpoints: that would
make the role depend on load order and would flip a hub into a race
server the moment someone tagged a decoration.

**`LobbyPlaceId = 0` means "not set up yet" and every place behaves as a
race place** — which is exactly what the game did before the split. It
is currently 0.

Only two services differ: `MatchService` and `BotService` do not start in
a lobby. Everything else does, including items.

The start place of a Roblox experience **cannot be changed after
creation**, so the original place has to become the lobby and tracks move
out to new places. DataStores are scoped per *universe*, so the places
must be in the same experience — a separate experience cannot see the
player's profile.

---

# 4b. The code must be a shared package, not a copy per place

**NOT DONE YET. This is a note, not a description of what exists.**

Every place runs identical code — that is the whole premise of §4, and
`Place.luau` only works because it is true. Right now nothing enforces
it. One Argon session syncs `src/` into whichever place happens to be
open in Studio, so keeping N places identical is N manual acts, and the
failure mode is silent: the lobby gets a fix, the race place does not,
and the bug you are chasing exists in one server and not the other.

**Drift between places is going to be the most confusing class of bug
this project can have**, because every symptom will look like a
place-specific problem and none of them will be.

## What "shared package" can mean here, and which one is right

**Roblox Packages** (right-click → Convert to Package) are the native
answer for sharing instances across places in an experience, with an
update badge and optional auto-update. They are *not* the right answer
here: Packages store their linkage in `PackageLink` instances inside the
tree, and Argon overwrites that tree on every sync. The two mechanisms
both claim to own the same instances.

**The source tree is already the shared package.** `src/` is the single
definition of every script in the game, and git is its registry. What is
missing is not a package format — it is **a repeatable way to push one
version of it into every place**, plus a way to *see* when a place is
stale.

So the work is a deploy step, not a restructure:

1. **A version stamp. DONE.** `Config/Build.luau`, printed by both
   entry points at startup:

   ```
   [BloxKart] 2026-08-02a (places split: lobby vs race) — LOBBY place, id 0
   [BloxKart] client 2026-08-02a — LOBBY place
   ```

   Bumped **by hand at publish**, not stamped from git. The obvious
   automatic version chases its own tail: stamping writes a tracked
   file, committing that changes HEAD, and the stamp is stale again
   immediately. The stamp belongs to the deploy step in item 3, where
   it is written once per publish and cannot lag.

   It prints before any service starts, so a server that dies on
   startup still says which code died.
2. **A place list.** `Config.Places.Tracks` already holds the place ids.
   A deploy script reads the same table rather than a second copy of it.
3. **Build once, publish N times.** `argon build` produces a place file
   from `src/`; Open Cloud can upload a place file to a place id. That
   makes "ship the code" one command against a list, instead of opening
   each place in Studio and remembering to sync.

Until step 3 exists, the manual rule is: **sync and publish every place
in the same sitting, and check the version stamps match before
debugging anything.**

## The constraint that shapes it

Content and code have to be separated for any of this to work. A deploy
that overwrites a place wholesale would destroy that place's *map* —
which is currently the only copy of the map (§3, and `BUGS.md` #13).

That makes §3 a hard prerequisite rather than good hygiene: **the track
and kart art have to leave the `.rbxl` before code can be deployed
automatically.** Publish them as Models referenced by asset id, or sync
them as `.rbxmx` alongside the code. Either way the place file stops
being where anything irreplaceable lives.

# 5. Code layout

**Single Script Architecture.** Exactly one `Script` on the server and
one `LocalScript` on the client. Everything else is a ModuleScript that
those two start, in a deliberate order. Nothing else auto-runs.

```
ReplicatedStorage/BloxKart/
  Config/           20+ modules, one per concern, aggregated by Config/init
  Items/            one module per power-up + init registry
  Simulation        THE movement code — shared by players AND bots
  Route             the track as ordered waypoints, derived from checkpoints
  TagZones          "did the kart drive through a part with this tag?"
  Triggers          which tags are trigger volumes
  WorldFilter       the raycast exclusion list (karts, triggers)
  Standings         race position from progress scores
  Match             shared phase names + timing helpers
  Place             lobby or race?
  Names, Util, Device, Ballistics

ServerScriptService/KartServer/
  init.server       the ONLY server entry point
  KartService       kart lifecycle: build, own, seat, respawn, registry
  KartFactory       assembles the kart model
  Placement         SpawnLocation lookup + start-grid maths
  Assets            copies server-only models into ReplicatedStorage
  Skins             runtime mesh swapping
  SteeringWheel     the Motor6D wheel assembly
  MatchService      the round loop
  RaceService       checkpoints, laps, item boxes, hazards
  BotService        AI racers + takeover of finished players (~2400 lines)
  ProjectileService missiles
  Progress          XP, currency, stats — the single grant path
  DataService       ProfileStore profiles
  Ledger            an append-only record of every balance change
  QuestService      daily/weekly/monthly

StarterPlayerScripts/KartClient/
  init.client       the ONLY client entry point (~1050 lines)
  Simulation is required from shared — the client owns movement
  CameraRig, Effects, Audio, Input, Rider, Boosters, Respawn
  Race, Match, Items, Projectiles, Spectate, Tally
  RemoteKarts, RemoteAudio          other players' karts
  Minimap, RaceHud, MatchHud, SpeedHud, ItemHud, FeedHud,
  RewardHud, QuestHud, XpHud, ControlsHud, TouchHud, Transition, Music
```

Cross-service wiring is done with **hooks assigned in `init.server`**,
not with requires. For example `RaceService.onNonPlayerHit =
BotService.applyHit`. This keeps the dependency graph one-directional:
`RaceService` never learns that `BotService` exists.

---

# 6. Who owns what — the authority model

This is the single most bug-prone area of the project, so it is worth
stating precisely.

| Kart kind | Anchored? | Who writes its CFrame |
|---|---|---|
| A player's kart | unanchored, network-owned by that player | **that player's client**, in `Simulation` |
| A bot's kart | anchored | **the server**, in `BotService` |
| A finished player's kart, taken over by AI | anchored | the server |

**One authority per part, always.** A server-side `PivotTo` on a kart a
client owns is overwritten by that client's very next frame — which is
why the starting grid is published as an *attribute* (`GRID_CF`) and the
client teleports itself, rather than the server moving anybody.

Anchored CFrame writes do not interpolate and land at roughly 20 Hz, so
`RemoteKarts.luau` smooths other people's karts on each viewer's client.

**Trust seams (open, known, marked in code):** the client is
authoritative on its own **finish time** and on **upward progress**.
Both are TODOs with the fix described next to them. They must be closed
before any global leaderboard, because a leaderboard makes an exploit
public and permanent.

---

# 7. The world is tag-driven

Nothing about a track is wired up by hand. You build geometry in Studio
and apply CollectionService tags in the Tag Editor. The code discovers
everything.

| Tag | Means |
|---|---|
| `RaceStart` | crossing starts the clock |
| `RaceEnd` | crossing banks a lap, if the lap was valid |
| `Checkpoint` | must be passed in order for a lap to count |
| `TrackSurface` | "this trigger is also road you drive on" — stays solid |
| `VoidZone` | touching it respawns you at the last checkpoint |
| `PowerUps` | an item box |
| `KartHazard` | a dropped mine/oil slick |
| `KartDroppedItem` | an item in flight or on the ground |
| `KartPaint` | kart parts that take the per-racer colour |
| `KartWheelFront` / `KartWheelRear` | steers-and-rolls / rolls only |
| `SpeedBooster1`… | boost pads (per-tier tags) |

Checkpoint **order** comes from an `Order` number attribute, falling back
to trailing digits in the part name (`Checkpoint3`). Unnumbered
checkpoints all collapse to order 0, which silently breaks lap
validation — the game shouts about this at startup.

**Consequence: two maps cannot share one place.** Every tag query would
return both maps' parts. And note `CollectionService:GetTagged` returns
tagged instances anywhere in the DataModel *including ServerStorage*, so
parking a map out of Workspace does not hide it.

---

# 8. Route — the racing line

`Route.luau` turns the tagged checkpoints into an ordered list of nodes.
One node per distinct `Order` (several parts can share an order — a wide
gate built from two slabs averages to the middle of the road).

Each node is **dropped onto the road beneath it** by raycast, because a
checkpoint gate is usually a tall slab whose centre floats several studs
above the tarmac. Taken literally, a racing line built from gate centres
hangs in the air, which tilts every tangent and makes bots brake for a
corner that is not there.

Node width is *felt for with rays* to either side rather than read off
the gate volume, because gates routinely overhang the tarmac.

Route is consumed by: bot steering, missile guidance (missiles follow the
road round corners), lap/wrong-way logic, and the minimap.

**Known bug:** the node cache invalidates on the *count* of tagged
checkpoint parts. A count is not a track identity — move a checkpoint,
or swap to a map with the same number, and the stale line is kept. The
minimap repeats the same mistake independently. Both need a generation
number. See `BUGS.md` #9.

---

# 9. The round loop

Five phases, run by `MatchService`. Full detail is in `GAME-LOOP.md`.

```
WAITING ─(≥1 human)─► INTERMISSION ─(timer│all ready)─► GRID
                          ▲                              │ (GridTime)
                          │                              ▼
                      RESULTS ◄──(all in │ time up)── RACING
                          │
                 (no humans) └──► WAITING
```

**One rule holds it together: a phase change is the only thing that may
move a kart, build one, or take one away.**

- **GRID** is the only place a round is set up, and the order matters:
  release AI-held karts → top the bot field up → clear finishes →
  clear hazards → assign grid slots → enter the phase. Release before
  fill, or the field is sized against a bot count that is about to
  shrink.
- **RACING** ends when `stillRacing() == 0` — counting who is *left*,
  never `finishers` against a racer count. Those two move independently
  and comparing them once ended races a lap in.
- Crossing the line: place, time, XP, ledger row, personal board sent,
  and **the AI takes over your kart** for the rest of the round.
- **RESULTS** hands every remaining kart to the AI so the board plays
  over a moving track. `isRolling` is true here; `isDriving` is not.

**NOTHING IS DESTROYED AND NOTHING RESPAWNS.** A kart exists from the
moment it is built until the player leaves. This is load-bearing:
"retirement" — destroying a finished racer's kart — was tried and caused
six separate bugs before being deleted. If a kart must leave mid-round,
park it.

`Config.Match.LoopTrace` prints one line per phase change with the four
numbers that decide the next one. It is on, and it settled in one round
what several sessions of code-reading had got wrong.

---

# 10. Kart lifecycle

- `Players.CharacterAutoLoads = false`. **We decide when a player
  spawns, not the engine.** With it on, destroying a character makes
  Roblox respawn it at a SpawnLocation — which was the source of "the
  race ends, then the player drives off again".
- `KartService` is the only thing that builds or destroys a *player's*
  kart. `BotService` owns bot karts and nothing else. A taken-over kart
  is still a player's.
- A watchdog sweep rebuilds a kart for a player who has none. It has a
  grace period (`spawningAt`) so it does not race the normal spawn path
  — an earlier version declared a perfectly normal spawn missing and
  rebuilt it underneath itself.
- Grid slots recycle: a leaver's slot is reused rather than pushing the
  next joiner another row back. Slot decides both grid position and
  paint colour.

**Known bug:** `KartService` contains no reference to the match phase at
all, so a player joining mid-race is entered into it on lap 0 — in the
standings, counted by `stillRacing()`, and paid if they cross the line.
See `BUGS.md` #10.

---

# 11. Bots

`BotService`, ~2400 lines, the largest module.

- Bots drive the **same `Simulation`** players do. They are not a
  separate movement model. This is deliberate: two movement models
  would diverge, and every divergence looks like an AI bug.
- Steering is feed-forward (curvature of the road ahead) plus
  pure-pursuit (aim at a point down the line).
- They use items with judgement: shield when threatened, hold fire with
  no target ahead, and a skill-scaled hop dodge against missiles. The
  brief was *"make it humane — it shouldn't be perfect"*, so the worst
  bots miss dodges and waste items on purpose.
- **Bots get every recovery rule a player gets**, out of the same
  helper. They previously had only the world floor, not the `VoidZone`
  tag — so a void that is a *plane at track level* never fired for them
  and they drove out past the track and kept going.
- **A takeover is not a bot.** A finished player's kart joins the bot
  list, and anything that trims that list must skip it. `fill()`
  trimming by destroying from the end of that list is what once deleted
  a player's kart mid-round.

---

# 12. Items

One module per item in `ReplicatedStorage/BloxKart/Items/`, plus a
registry. Adding an item means adding a module, not editing the systems.

Current set: Missile, Lightning, Mine, OilSpill, Shield, Scramble,
Turbo, Refill, FakeBox.

- **Missiles** are server-simulated (`ProjectileService`), have a
  proximity fuze, follow the racing line round corners, carry a thruster
  loop and explode wherever they end.
- **You can hop to dodge one.** That is what makes the incoming warning
  actionable rather than just stressful.
- **Lightning has a wind-up** purely so a warning can exist — an instant
  hit has nowhere to put one.
- Warnings share **one alert slot**. Two alarms stacked in the centre of
  the screen is worse than either alone, so the caller has to decide
  what matters most. The blink *rate* is the countdown.
- Whether items may be picked up at all is one function,
  `MatchService.itemsLive()`. On a track: only while a round is running,
  so nobody stockpiles during the intermission. In a lobby: always,
  because there is no grid to arrive at.

---

# 13. Progression, currency and persistence

- **XP** for hits, takedowns, eliminations and finishes. 20 levels,
  curve in `Config/Level.luau`. Bolt paid per level.
- **Two currencies.** **Bolt** — earned from racing, quests and events,
  buys parts. **Nitro Crystals** — premium, deliberately harder to
  earn, for premium skins.
- **96 quests** across daily/weekly/monthly; 87 are live. The rest are
  blocked on systems that do not exist yet (a shop, and any social
  layer). Nested so one race ticks every layer.
- **`Progress.luau` is the single grant path.** `award` / `grant` /
  `spend`. Everything goes through it; that is the anti-dupe design.
- **`DataService`** wraps **ProfileStore** (session-locked profiles).
  `Ledger` writes an append-only row for every balance change into a raw
  DataStore — a receipt log, kept out of the profile on purpose, because
  an index does not belong inside the record it indexes.
- If a profile has not loaded yet, `Progress` banks into a session table
  and **merges it into the profile on arrival**, so a race finished
  during the load is not lost.

**Nothing spends currency yet.** `Progress.spend` has never been called;
there is no shop and no garage. Everything earns and nothing sinks,
which is the single biggest gap in the game right now.

---

# 14. Presentation

- **Speed is sold entirely through the camera** — FOV escalation,
  pull-back, drop, lag, shake and blur. Screen-space streak effects were
  built and then deliberately removed; they read as clutter, and real
  kart games do this with the camera.
- **A geometric wipe** (angled band + an upright logo mark) covers every
  hard cut: the grid teleport, the results screen opening. The band is
  solid on purpose — the band is what hides the cut, and a transparent
  one turns the transition into decoration.
- **Finishing is a beat**, not a freeze frame: `FINISH · P3`, a
  three-second cinematic shot, the wipe, then the board.
- **Spectator mode** after you finish: free orbit camera with smoothed
  heading.
- **Minimap** drawn from the same Route nodes the bots drive, so it
  cannot disagree with the track. North-up; heading-up is written and
  waiting on a settings menu.

---

# 15. Config

**Every tunable value and all content lives in
`ReplicatedStorage/BloxKart/Config/*`** — one module per concern,
aggregated by `Config/init.luau`. Read as `Config.Handling.MaxSpeed`.

Modules: Handling, Rig, Bots, Camera, Audio, Effects, Nitro, Boosters,
Race, Match, Respawn, Items, Rider, Input, Touch, Haptics, Music,
Spectate, Rewards, Level, Quests, Data, Minimap, Skins, Hud, Places.

The config modules carry heavy prose comments explaining *why* a number
is what it is, including several that record a bug the value caused.
Treat those comments as part of the code.

**`luau-analyze` cannot see through `Config.Hud.WarnedText`.** A config
module is a plain table read by string, so a renamed, deleted or
misplaced key is a `nil` that surfaces on the exact frame something
needs it. This has cost the project a frozen camera and a missile that
errored sixty times a second.

`scripts/config-keys.py` walks every declared alias (`local IT =
Config.Items`) and every direct `Config.X.Y` read across the whole tree
and checks each key exists. `check.sh` runs it. **Run `check.sh` after
any config edit.**

---

# 16. Known open problems

Full list with evidence in `BUGS.md`. In rough priority:

1. **The track and kart art are not in source control** (#13). Git has
   the code and none of the content.
2. **Route/minimap cache by count, not identity** (#9). Blocks a second
   map.
3. **A mid-race joiner is entered into the running race** (#10).
4. **Two client-authority seams** — finish time, upward progress (#6).
5. **Nothing spends currency.** No shop, no garage.
6. **`MatchService` is past Luau's inference budget**; `BotService` is
   ~2400 lines. Neither urgent, both slow everything after them.
7. Bot void-zone recovery, stranded takeovers and floating skin art are
   all recently fixed and **unproven over a long session**.

---

# 17. Recurring bug shapes

These are worth more than any individual bug. From `BUGS.md`:

1. **One question answered in two places.** The oldest and most
   expensive. Two producers of "race progress" disagreeing; a rule
   written out at three call sites.
2. **Something assumes a Player behind the kart.** Bots and takeovers
   break it every time.
3. **A feature added, then six fixes to contain it.** If a fix is
   downstream of something added recently, question the addition.
4. **The clever mechanism over the boring one.** Using humanoid
   `Physics` state as a signal instead of a poll; inferring a place's
   role from world contents instead of its id.
5. **A watchdog racing the thing it watches.** A recovery sweep must be
   slower than the path it is recovering.
6. **Units and clocks.** Metres vs a 0–1 fraction; `os.clock` vs
   `workspace:GetServerTimeNow`.
7. **Config keys the type checker cannot see.**

And one about process: **git protects what it has already seen.** A
modified file always comes back from HEAD; a file git has never seen
cannot come back from anywhere. Commit new files immediately.

---

# 18. Vocabulary

| Term | Means |
|---|---|
| **Hitbox** | the one part the controller moves. All handling is defined against it. |
| **Rig** | the player's avatar, seated in the kart |
| **Takeover** | the AI driving a finished player's kart until the next grid |
| **`isDriving`** | "does this count" — laps, items, finishes |
| **`isRolling`** | "do karts move" — true in Results, when `isDriving` is false |
| **`stillRacing()`** | how many karts have no finish place yet |
| **Bank / tier** | drift charges nitro; longer drifts bank higher tiers |
| **Void zone** | a tagged volume that respawns you at your last checkpoint |
| **Trust seam** | a place the client is believed and could lie |
