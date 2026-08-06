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

# 18. FIXED 2026-08-02 — depenetration trusted a BOUNDS test

Two reports, one cause: a kart on a one-piece Blender road slid sideways
off it, and a kart passing under an arch "bugged out". Neither had
anything to do with normals, `CollisionFidelity` or the meshes.

`Simulation` section 6 pushes the kart out of anything it is already
inside, because a `Blockcast` starting inside geometry returns nothing
and one frame of penetration would let the kart pass through walls
forever. It found candidates with `GetPartBoundsInBox` and pushed away
from `part.Position`.

**`GetPartBoundsInBox` is broad-phase.** It returns anything whose
BOUNDING BOX overlaps — not anything touching. Treating that as final
was survivable only while every road was a small part: the part beneath
the kart had its centre directly below, so `away` came out
near-parallel to `up`, flattened to nothing by the surface-plane
projection, and failed the `> 1e-3` test. **No push ever happened — by
luck, not by design.**

Two kinds of authored geometry break that luck, and each produces a
different-looking symptom:

- **A one-piece meshed road.** One MeshPart whose bounding box spans
  the whole circuit, overlapping every frame wherever the kart is, with
  a `Position` in mid-air inside the layout. `away` became a long
  horizontal vector from track-centre outward, normalised, times
  `Depenetrate` = **55 studs/s** — against a `MaxSpeed` of 95. Constant,
  outward, every frame: "it literally slides off."
- **An arch, tunnel or gateway.** Anything you drive *through* has a
  bounding box covering its opening, so the kart is "overlapping" the
  entire time it passes under while touching nothing at all. A shove
  out of thin air, which is the "bugs out going through an arch".

Fixed by demoting the bounds query to what it actually is — a filter —
and asking the geometry the real question:
`part:GetClosestPointOnSurface(self.pos)`. If the nearest actual
surface is further away than the kart's own hull radius, there is
nothing to be inside of (an arch's opening, the empty middle of a
track's bounding box) and nothing happens. Roblox returns the input
point unchanged when genuinely inside a part, which is the
stuck-in-a-wall case this block exists for, so that branch still falls
back to the centre and wall recovery is unchanged.

## What to learn from how long this took

Three wrong guesses came first — inverted mesh normals, a missing
`TrackSurface` tag, and then a partial fix that corrected the push
DIRECTION without questioning whether there should be a push at all.
The partial fix silenced the road case (surface underfoot → vertical →
flattens to zero) while leaving the arch case fully broken, which would
have read as "fixed one thing, broke another."

The tell, available from the first report and not acted on: **"parts
worked, one mesh doesn't" is a statement about part COUNT AND SIZE, not
about mesh data.** Inverted normals would break a ten-piece mesh road
exactly as readily as a one-piece one. The only thing that actually
changed was that a single part's bounding box now covered the map.

And the second tell, which arrived with the arch: **a symptom that
appears both when standing ON something and when passing THROUGH a hole
in something is not about surfaces at all — it is about a volume test.**
Two failures that different sharing one cause means looking for what
they have in common, not fixing them separately.

Also worth stating plainly, since an earlier answer here got it wrong:
`CollisionFidelity` genuinely does affect raycasts — it determines the
collision geometry rays hit. It simply had no bearing on this bug,
because the culprit was a bounds query that ignores collision geometry
entirely.

---

# 19. FIXED 2026-08-02 — curved meshes jittered because the ground snap

  was instantaneous

Follow-on from #18. With the depenetration bug fixed the kart stopped
sliding off, but still "bugged out on certain curves or surfaces that
are not flat."

**A curved MeshPart is not smooth to a raycast.** Roblox builds
collision geometry for a mesh out of convex hulls, so a road that looks
perfectly smooth is a chain of flat FACETS underneath. Driving along it,
consecutive frames hit different facets and read heights a few tenths of
a stud apart.

The ground snap put the kart at exactly `RideHeight` above whatever the
centre probe hit, **every frame, instantly**:

```lua
self.pos += self.up * (highest + H.RideHeight)
```

On flat parts that number never moves, so an instant snap is invisible
and correct — which is why this was never a problem before meshed
roads. On a faceted curve it is a hard jolt at every facet boundary.

Small corrections are now eased (`GroundSmooth`, `GroundSmoothRate`);
large ones still snap, so landing and genuine step-climbing stay
immediate rather than going floaty. Airborne frames are excluded via
`wasGrounded` — easing a touchdown would sink the kart into the road.

**This cannot be fixed in the model.** The faceting is in Roblox's
collision build, not the mesh, so no amount of care in Blender removes
it. The controller has to tolerate a noisy ground signal.

## Checked and ruled out: curvature reading as a STEP

The step-detection logic promotes an outer probe that sits above the
centre probe's own tangent plane. Curvature does deviate from that
plane, so this was the other candidate — but the numbers say it only
fires on very tight curvature:

    deviation ≈ ProbeSpread² / 2R  =  4.84 / 2R

Against `StepTolerance = 0.35`, that needs **R < 6.9 studs** to trigger.
Normal road curvature is far gentler, so the step logic is innocent for
this report and was left alone. Worth keeping in mind for genuinely
tight concave geometry — a sharp valley or gutter — where it WOULD
fire.

---

# 20. PARTLY FIXED, PARTLY A CONTENT PROBLEM — convex decomposition at

  pinch points and forks

Follow-on from #18 and #19. Reported with a screenshot of Studio's
decomposition view: at forks, pinch points and tight bends, the
collision hulls are large angular slabs that **do not follow the road at
all**, bulging above and beside the visible surface.

`PreciseConvexDecomposition` approximates a mesh with CONVEX pieces.
A road is a long, thin, concave ribbon — close to the worst possible
input. Where the road narrows, forks or bends tightly, the decomposer
spans the concavity with a hull that covers the gap, so the kart's
probes hit geometry that is nowhere near the visible tarmac.

**No controller change can fully fix this.** The raycasts are hitting
exactly what Roblox told them is there. If a hull sits a stud above the
road, the kart rides a stud above the road, correctly.

## What was fixed in code

A single bulging hull under ONE SIDE probe used to promote itself as a
step and yank the whole kart up onto it for a frame, then drop it. Step
promotion is now restricted to probes in the direction of travel:
climbing something you are driving INTO is a step; something higher
beside you is a kerb you are passing, or a lump.

Measured against `travel` rather than `forward`, so it still works in
reverse and mid-drift. On flat parts this changes nothing — the ground
under all five probes was the same slab.

## What has to be fixed in the content

In rough order of effort against payoff:

1. **Give the road real thickness.** A near-zero-thickness ribbon
   decomposes terribly. A slab with a couple of studs of depth gives the
   decomposer something convex to work with and fixes most of this on
   its own.
2. **Split the track into several meshes.** Still meshes, not parts —
   decomposition quality collapses with mesh size and complexity, and
   6–10 road segments decompose far better than one circuit. Split at
   natural breaks; forks especially want to be their own piece.
3. **Separate the collision surface from the art**, which is the real
   answer and the one this codebase's own philosophy already points at.
   The visual road gets `CanQuery = false` and becomes purely art; a
   simplified, thicker, invisible mesh underneath carries
   `CanQuery = true` and is what the kart actually drives on.

   **This needs no code change.** A part with `CanQuery = false` is
   already invisible to every raycast the controller makes, and the
   proxy is picked up automatically. It is the same rule the kart itself
   follows — `Simulation` reads the `Hitbox`, never the art — applied to
   the track.

---

# 21. FIXED 2026-08-02 — two of my own fixes were the remaining bugs

The track's decomposition was rebuilt with thickness and segmentation
and came back clean — hulls hugging the ribbon segment by segment. With
the content side genuinely good, everything still wrong on bends and
descents was code, and both causes were introduced by earlier fixes in
this same run.

## The downhill oscillation was #19's smoothing

#19 eased ground corrections under `GroundSmooth` to damp facet noise,
and eased them in BOTH directions. On any descent the ground drops away
a little every frame, so the correction is permanently negative — easing
it left the kart hovering, the gap grew until it passed the threshold,
then it snapped. Hover, snap, hover, snap, for the whole slope.

At 95 studs/s even a **5° slope drops 0.14 studs per frame**, and the
window was 0.75 — so every descent in the game oscillated. #19 made
downhills worse than doing nothing.

Easing is now UPWARD only. Spurious lift is the noise worth filtering; a
road going down is not noise, it is the road.

## The bend push was #20's hull radius

#18/#20 gated depenetration on the nearest surface being within the
kart's own hull radius. That sounds conservative and is not. A decomposed
road is a CHAIN of hulls, so on any bend there is a seam a couple of
studs to the side and its nearest face is lateral — firing the 55
studs/s push sideways while driving along good road.

Now it pushes only when the kart's centre is genuinely INSIDE a part,
which is the one state the block exists to escape (a `Blockcast` that
starts overlapping returns nothing, and the kart passes through walls
from then on). `GetClosestPointOnSurface` returning the input point is a
precise test for exactly that, rather than a distance guess.

## The pattern

Three fixes in a row, each of which silenced the case in front of it and
created or left another: direction without asking whether to push at all
(#18), then a radius that fired on seams (#20), then symmetric easing
that broke descents (#19). This is FINDINGS' *"two reasoned fixes in a
row that don't land means stop reasoning"* — the signal was there after
#19 and was not acted on until the numbers were actually computed.

**Compute the failure before shipping the fix.** One line of arithmetic
against a 5° slope would have caught #19 before it ever went in.

---

# 22. FIXED 2026-08-06 — the drift hop had a rise and no fall

Found while recalibrating the drift, not by report. The hop was described
as "a discrete state change" and it turned out to be literally that.

`HopSpeed = 18` against `Gravity = 150` gives an apex of **1.08 studs**.
`GroundSnap` is **3.0**. The snap only declines to act while the kart is
still rising (`vertVel <= 0` gates it), so the very first frame vertical
velocity crossed zero — **the apex itself** — the gap was 1.08, well
inside 3.0, and the ground reclaimed the kart in a single frame.

Measured, at 60fps:

| | air time | apex reached | landing speed |
|---|---|---|---|
| before | 133 ms | 0.93 studs | **2.0 studs/s** |
| after | 200 ms | 0.93 studs | 12.0 studs/s |

A landing speed of 2 studs/s is the tell: the kart was not landing, it
was being switched off at the top of its arc. Half the hop did not exist,
and no amount of easing the *visuals* would have recovered it, because
there was no descent to put visuals on.

Fixed with `HopSnap = 0.35` — while the hop state is live the snap
distance shrinks so only a genuine touchdown counts. `GroundSnap` exists
to follow the road across dips, seams and kerb nosings; a jump the player
deliberately asked for is not one of those, and the two cases wanted
different numbers all along.

Air time stays deterministic (200ms at 30 and 60fps, 217 at 120), which
matters because the hop is the gate the drift is timed off.

## What to learn from this one

**A constant that is right for one caller is not a constant.**
`GroundSnap` was tuned for road-following and then silently applied to a
jump. Nothing was wrong with either value; the bug was one number
answering two questions — which is *pattern 1* in this file, showing up
for the fourth time.

**The symptom named the wrong layer.** "The hop feels like a state
change, make it fluid" points straight at presentation, and three of the
four things queued for it (arc pitch, hop lean, landing spring) were
cosmetic. None of them would have fixed anything. The arithmetic —
apex 1.08 vs snap 3.0 — took one line and found the real cause.

---

# 23. FIXED 2026-08-06 — drifting cost half your speed, and more on a better monitor

Reported as *"it goes slow really quick then go fast"*, asked as a
balancing question. It was not balancing.

`Simulation` applied the drift scrub as a **per-frame** multiplier:

```lua
self.speed *= H.DriftSpeedKeep * Util.sampleCurve(H.DriftScrubCurve, driftAge)
```

`0.995 * 0.980` reads like a 2% trim. Compounded 60 times a second it is
`0.9751^60` = **22% of your speed surviving per second**. Against the
accel curve pulling the other way, measured:

| | trough | as % of top speed |
|---|---|---|
| 30 fps | 74.8 | 79% |
| 60 fps | 65.0 | **68%** |
| 144 fps | 46.7 | **49%** |

So the dip and recovery the player described were real and were this
curve's intended shape with a 20x magnifier on it. Worse, the fast line
was the slow line on better hardware — a drift on a 144Hz monitor cost
half your speed. Every other rate in the module takes `dt`; this one line
did not.

Now `retain ^ dt`, with the curve redefined as retention PER SECOND and
retuned to `{1.0, 0.90, 0.84, 0.86, 0.93, 0.99, 1.00}`. Result: a trough
of 88.5 (93% of top speed) at 1.4s, recovering to ~94.6, and **identical
at 30, 60, 144 and 240fps**.

`DriftSpeedKeep` is now 1.0 and is the single dial for whether drifting
is faster or slower than driving straight.

# 24. FIXED 2026-08-06 — a missile has never been dodgeable

Reported as a feature request — *"rocket should be dodgeable too"*. It
was already built, `DodgeEnabled = true`, and it could not fire.

```
hop apex          HopSpeed^2 / 2*Gravity  =  18^2/300  =  1.08 studs
hitbox clearance  RideHeight + apex       =  1.4 + 1.08 =  2.48
IT.DodgeHeight required                                 =  4.5
```

Short by two studs, always. `HopSpeed` would have to be **30.5** instead
of 18 for the old threshold to be reachable. Nothing errored: you hop,
the missile hits you, and it reads as a mistimed dodge rather than an
impossible one.

`DodgeHeight = 2.2` sits between the 1.4 the kart rides at and the 2.48
it peaks at — a 122ms window opening 59ms into a 200ms hop. `GroundSmooth`
cannot manufacture false clearance, because easing applies to UPWARD
corrections only and so can only leave the kart lower than nominal.

`DodgeWarnRange` went 26 -> 65 in the same breath, **but note what it
actually feeds**: `ProjectileService.onMissileNear` ->
`BotService.missileNear`, and nothing else. It is the BOT's cue. A human
is warned by `Projectiles.threatTo()` on the client, held for
`Hud.IncomingHold` and shown from `Hud.IncomingLead` (3.0s) out — a
different signal on a different clock, and already generous.

26 studs was 124ms of lead at 210 studs/s, against a hop that does not
clear for 59ms and a `Bots.ReactionTime` of 190ms: bots were told to
dodge well after the last moment they could act, on top of a height they
could never clear. 65 studs is ~310ms, which fits both.

So the player's side of this was only ever the height. The warning was
never the problem — it has been arriving three seconds out the whole
time, for a dodge that could not be performed.

## What to learn from both of these

**A rate applied per frame is not a rate.** #23 is the same shape as
FINDINGS' *"a probability rolled per step is not a probability"*, which
this project has already paid for once in bot nitro. Anything of the form
`x *= k` or `if rand() < p` inside a per-frame loop needs `dt` in it or
it is secretly a frame-rate setting.

**A dependency across two config tables has nothing checking it.**
`Items.DodgeHeight` is only meaningful against `Handling.HopSpeed`,
`Handling.Gravity` and `Handling.RideHeight`. Nothing links them,
`config-keys.py` cannot see it, and the type checker certainly cannot.
Both numbers were individually plausible and jointly impossible.

**Neither was reported as a bug.** One arrived as a balancing question
and one as a feature request. Both took a single line of arithmetic to
find. **When a feel complaint has a specific shape to it, compute the
mechanism before tuning anything** — three sessions of tuning the scrub
curve would never have found a missing `^dt`.

---

# 25. FIXED 2026-08-06 — a kart could spawn before its owner's profile loaded, and nothing went back

Reported as "customisation only saves per session — I customise it then
have to re-customise". **Two different things produce that symptom and
only one of them is a bug.**

## Not a bug: Studio always mocks

`DataService.start()`:

```lua
local useMock = D.Mock or (RunService:IsStudio() and not D.LiveInStudio)
```

With `Mock = false` and `LiveInStudio = false`, Studio uses ProfileStore's
mock store, so nothing survives a Studio restart. It says so in the
output — `[DataService] MOCK store — nothing written here survives the
session.` To actually test persistence, `Config.Data.LiveInStudio = true`,
play, rejoin, check, **turn it off again** (see #11 — it was left on once
and every playtest read and wrote real profile data).

The write path itself was verified sound: `GarageService` is the only
writer of `equipped`, it writes into the live `profile.Data` table that
ProfileStore autosaves and flushes on `EndSession`, and
`ReconcileTable` is **additive only** — it never strips keys, so nothing
was being deleted on load.

## The actual bug: the dressing had no second chance

`createKart` dressed a kart like this, and the comment admitted the race
without resolving it:

> *"bots (and anyone whose profile has not loaded) keep the stable random
> dresser, so a kart is never undressed while waiting on a profile."*

That is fine as far as it goes — the kart is never naked. But nothing
ever came back. If `GarageService.lookFor` returned nil because the
profile was still loading, the player raced the entire round in a
randomly dressed kart, **and from the seat that is indistinguishable
from customisation not having saved.**

The race is not rare and it is worst where it matters most. Arriving in a
RACE place, the kart is built as the round starts while
`StartSessionAsync` is still doing a DataStore round trip — possibly
waiting on the lobby server to release the session lock first. The lobby
is the forgiving case; the race is not, and the race is the one people
see.

Fixed by pulling the dressing out into `KartService.dressKart(player,
kart)` and calling it from `DataService.onLoaded` as well as from spawn.
Costs one extra mesh swap for a player who was already dressed correctly,
and nothing at all for a player whose profile beat their kart.

`equipped.Paint` was also missing from the profile TEMPLATE. Harmless —
Reconcile is additive and every caller defaults it to `"stock"` — but
the template is the schema, and a slot the code writes that the schema
does not name is a field nobody can find by reading it.

## What to learn from this one

**A fallback with no retry is a permanent wrong answer.** The random
dresser is the right thing to do while waiting; the bug was that
"while waiting" had no end. Any code shaped *"use the good value, or a
default if it is not ready yet"* needs to say what happens when it
becomes ready — otherwise the default is not a fallback, it is the
outcome.

**Two causes, one symptom, and the harmless one is louder.** The Studio
mock explanation is true, documented, and would have closed this report.
It was also not the whole story, and stopping there would have shipped
the real bug. When a known non-bug explains a report, check whether it
explains ALL of it.

---

# 26. FIXED 2026-08-06 — below 20fps the kart was LITERALLY slower, not juddery

Reported as "kart feels super slow now" after a HUD change. The handling
was not touched and simulates 23% FASTER through a corner than before
(avg 74.1 -> 91.4 studs/s). The slowness was real anyway.

`Simulation.Step` opens with `dt = math.min(dt, H.MaxTimestep)` and
MaxTimestep is 1/20. That clamp is right — a huge frame integrated in one
go tunnels the sweep through walls. But the client called `Step` **once
per Heartbeat with the raw dt**, so every frame longer than 50ms silently
discarded the excess:

| frame rate | integrated | kart runs at |
|---|---|---|
| 30 fps | 33ms of 33ms | 100% |
| 15 fps | 50ms of 66ms | **75%** |
| 10 fps | 50ms of 100ms | **50%** |

Discarded time is lost MOTION. The kart does not stutter — it goes slow,
smoothly, and the speedometer agrees with it, because the simulation
genuinely is moving that slowly. From the seat it reads as the handling
having been nerfed, which is the last thing anyone would investigate.

Fixed by sub-stepping: a long frame is integrated as several capped
steps. `Handling.MaxSubSteps = 4` bounds the catch-up, because fully
repaying a one-second hitch costs a second of simulation on the next
frame and turns one hitch into a spiral. Real-time coverage is now 100%
down to 5fps.

## What dropped the frame rate in the first place — my own HUD

Two defects in the new `ThreatHud`, both mine, both from the same
session:

1. **A thumbnail request storm.** `headshotFor` cleared its in-flight
   flag and stored nothing on failure, so a headshot that would not load
   was re-requested **every frame** — sixty web calls a second, for as
   long as that racer stayed on your bumper. The comment above it
   claimed the failure was cached. It was not: only success was ever
   recorded, and the failure path was indistinguishable from "never
   asked". Now a failure is stored as `false` and never retried.
2. **A per-frame `GetTagged` scan** over every kart, for a display whose
   answer changes over tenths of a second. Now scanned at `RearScanHz`
   (12Hz) with the drawn value eased toward the reading, so it still
   sweeps smoothly.

## What to learn from this one

**A clamp is not a budget.** `math.min(dt, cap)` protects the integrator
and silently loses time unless the caller loops. The module cannot
enforce that on its callers, so the requirement has to live where the
constant does — it now does.

**A comment asserting the safe behaviour is not the safe behaviour.**
FINDINGS already says "a comment asserting something is not evidence it's
true", and here the comment and the code disagreed in the same five
lines, written at the same moment, by the same author. The comment
described the intent; the code did the opposite.

**A performance regression can present as a gameplay regression.** Nobody
reports "my frame rate dropped" when the symptom is a slow kart. Any time
a feel complaint follows a rendering change, check the frame budget
before touching a handling dial — tuning would have made it genuinely
worse, on top of a bug.

---

# 27. FIXED 2026-08-06 — the garage saved fine; the DRESSER was looking for parts that do not exist

Reported three times as "the kart doesn't save". It always saved. The
server log, once `Config.Garage.Debug` existed, settled it in one run:

```
[GarageService] wrote Obus1n.FWheel+RWheel = "slick"
[GarageService] wrote Obus1n.Paint = "purple"
[GarageService] wrote Obus1n.Body  = "brute"
-> reply after commit: Body=brute Wheels=slick Paint=purple
```

Three good writes, on a live server, with no MOCK warning. The profile
had the loadout the whole time.

## The actual bug: two dressers, two ideas of the part names

`Config.Rig.FrontWheelNames = { "WheelFL", "WheelFR", "FWheel", "WheelF" }`
— a list of CANDIDATE names, of which the real rig uses `WheelFL` /
`WheelFR` / `WheelRL` / `WheelRR`.

- `KartDress` (garage preview) walked the whole list, found them, swapped
  them. **Worked.**
- `GarageService.lookFor` hard-coded the two strings `"FWheel"` and
  `"RWheel"` as part names. `Skins.applyTo` does
  `FindFirstChild("FWheel", true)`, found nothing, and swapped nothing —
  **silently, on every kart ever spawned.**

So it changed in the garage and never on the kart, which reads exactly
like customisation not persisting. Three sessions were spent on the
persistence path because the symptom pointed there.

Fixed by making `lookFor` emit the rig's own names for every candidate,
and adding `Config.Rig.BodyName` so the body name has one home too. The
full rule is written up in the vault under *"THE RULE: dressing a kart is
setting properties on parts found BY NAME"*.

## Why it stayed hidden

`Skins.diagnose` — which exists precisely to name missing parts — is only
wired into the RANDOM dress path, never into `applyTo`. So the garage
path had no diagnostic at all.

`Skins.applyTo` now returns `(ok, found, changed)`, because the boolean
cannot tell apart two failures that need opposite fixes:

- **found 0** — the NAMES are wrong; no swap was attempted
- **found n, changed 0** — names right, mesh loads failed; an asset problem

`found == 0` now warns by name.

## What to learn from this one

**A list of candidate names is not a name.** `FrontWheelNames` is a
compatibility list; treating any single entry as "the" name is a
coin-flip that happened to lose. If a config field is plural, iterating
it is not optional.

**The same job in two places will diverge — the only question is when.**
Root cause #1 in this file, again. The preview and the server were both
"dress a kart", written at different times, and only one of them was
told where the parts were.

**A silent no-op imitates the failure one layer down.** Nothing errored,
so the symptom surfaced as the nearest visible system — persistence —
and three rounds of work went into a subsystem that was already correct.
The fix that mattered was not code, it was the log line that made the
no-op audible.

---

# 28. THE KEY FACT, learned 2026-08-06: THE PREVIEW KART AND THE RIDDEN KART ARE DIFFERENT MODELS

Reported directly, and it reframes every entry below it:

> the kart asset of the player is completely different from the garage

The garage previews the authored **MenuStage** kart. The player rides one
built by **KartFactory**. They are separate assets and are under no
obligation to name their parts alike — and they do not.

**This is why the garage visibly changed and the real kart never did.**
Every dresser reads ONE set of names out of `Config.Rig`, so a single
name can only ever be correct for one of the two models. The preview
happened to be the one that matched.

## What that means for the config

Every name field must be a CANDIDATE LIST holding the union of both
models' names, and every dresser must walk the whole list:

| field | was | now |
|---|---|---|
| `BodyName` | one string, `"Body"` | **`BodyNames`**, a list |
| `FrontWheelNames` / `RearWheelNames` | already lists | unchanged |
| `PaintParts` | already a list | unchanged |

A name a model does not have is simply not found, at the cost of one
lookup. That is the whole mechanism, and it is why the wheels were
written as a list in the first place — the lesson was already in the
file, applied to one field and not the others.

**DO NOT RENAME ART TO MATCH CODE.** Add the name to the list.

## Finding the names without opening Studio

`Config.Garage.Debug` + the **Server** tab. `KartService/dress` prints,
per kart:

```
<name>: <kart path> -> found N, swapped M | HAS [...] | MISSING [...]
```

`MISSING` is the answer: those are the candidate names this particular
kart does not have. If `found` is 0 it also warns with the kart's REAL
MeshPart names, and separately lists any part that has the right name but
the wrong class (a Part or Union cannot take a mesh).

---

# 28c. FIXED 2026-08-06 — THE ROOT CAUSE. The start-line kart skipped the dresser entirely.

**Diagnosed by the reporter, from one log line**, after four sessions of
looking in the wrong layer:

> maybe that is what its wrong when it tries never try again when kart is
> spawned in that mightve been the problem all this time

`spawnKartFor` has TWO ways to produce a kart:

```lua
if unclaimed and unclaimed.Parent and slot == 0 and not ownArt then
    kart = unclaimed          -- claimed as-is. createKart NEVER runs.
else
    kart = createKart(...)    -- and createKart is where dressKart lived
end
```

The pre-built start-line kart is handed to **slot 0**. Slot 0 is the first
player to join — so in any solo test that is **always you**. That kart
never went through `createKart`, so nothing ever dressed it.

Everything else was working: the garage saved, the profile was correct,
the reply carried the right loadout, and the mesh swap provably worked
(the cycle test changed meshes on the same kart). The one kart actually
being ridden was the one kart nothing had ever dressed.

## The fix, and the shape of it

Dressing moved OUT of `createKart` — which builds a kart and has no
business deciding what it wears — and into its callers, **after** the
branch:

| caller | dresses |
|---|---|
| `spawnKartFor` | once, after `karts[player] = kart`, so BOTH branches are covered |
| `addBot` | once, explicitly (bots land on the random dresser) |

Placing it after the branch is the whole point: no new path through
`spawnKartFor` can silently skip it, which is exactly how this survived.

## What to learn from this one

**A conditional that produces the same THING by two routes must converge
before anything acts on it.** The bug is not that the claim path forgot
to dress — it is that dressing lived inside one of the two branches at
all. Anything that must happen to "the kart" belongs after the `if`, not
inside a leg of it.

**The cheap path was always the same one.** Five bugs wore this disguise
and every one was found by making a silent step audible, never by
reasoning. The line that cracked it —
`re-dress requested, but they have NO KART spawned` — existed only
because the previous round added it.

---

# 28b. SUPERSEDED by #28c — on rejoin the kart loads DEFAULT.

**Still broken as of 2026-08-06. Reported four times. Do not touch the
persistence path — it is correct and has been proven correct.**

The profile saves and loads. The server log shows the writes landing and
the reply carrying them back. What is broken is that **the look is
applied at moments that happen BEFORE the profile is ready, and only one
of the three consumers ever retries.**

## The requirement, in the reporter's own words

> when player joins it should load the data and then load the kart to the
> preview, to the garage, and also to the kart that i ride

So there are **three sinks** for one look, and all three must be fed
after the profile resolves:

| # | sink | who owns it | retries after profile load? |
|---|---|---|---|
| 1 | MenuStage preview kart | `MainMenuHud` / `GarageHud` | **NO** |
| 2 | garage selection state | `GarageHud.ApplyEquipped` | partly — only if the push arrives |
| 3 | the kart the player drives | `KartService.dressKart` | yes, via `DataService.onLoaded` |

## The evidence, from the client log

```
18:18:08 [GarageHud] server sent no equipped state — the profile is not
                     loaded, so nothing can be saved yet.      <- push #1
18:18:08 [GarageHud] <- server: Body=brute Wheels=slick Paint=purple  <- push #2
```

Two pushes, ~0 seconds apart. The FIRST is `GarageService.start()`'s
`refresh` reply, fired before the profile exists, and it carries `nil`.
The second is the real one. So the ordering already loses the race on
join, every join, and only the garage recovers.

**Nothing re-dresses the MenuStage preview when push #2 lands** unless
the garage happens to be open — `ApplyEquipped` re-dresses
`opts.getKart()`, and at 18:18:08 the stage rig was still being built
(`[MainMenuHud] Built Obus1n's R15 avatar onto MenuStage.Rig` at the same
second).

## What to build — one ordering, one broadcast

Do NOT add a fourth ad-hoc call site. The shape that fixes this is:

1. `DataService.onLoaded` is the ONLY trigger. Nothing dresses anything
   off join, character-added, or menu-built.
2. On that event the server sends the authoritative `equipped` once.
3. The client applies it to **the preview and the garage** on receipt,
   and re-applies whenever the MenuStage kart is (re)built — the stage
   rig is created asynchronously and can miss the push, which is failure
   #1 above.
4. The server applies it to the ridden kart via `KartService.redressFor`,
   which already exists and already handles "no kart yet".

The missing piece is a **client-side cache of the last `equipped`
payload** so a stage kart built *after* the push can ask for it instead
of waiting for another one. Everything else is wired.

## Check these first, in this order

1. Turn on `Config.Garage.Debug` and read the **Server** tab. If
   `[KartService/dress]` shows `found 0`, it is still a naming problem
   (#27) and the warn will print the kart's real part names.
2. If `dress` shows `re-dress requested, but they have NO KART`, the
   ordering is the whole bug and the fix is above.
3. If neither line appears at all, `DataService.onLoaded` is not firing —
   check that `KartService.start()` runs after `DataService.start()`.

## Do not re-investigate

`ProfileStore`, `DataService`, `GarageService.equip/commit`, session
locking, `Reconcile`. All verified correct. Four separate bugs (#25, #27,
the missing re-dress hook, and the paint-set mismatch) have already worn
this same disguise; the fifth is not going to be in the store either.

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
- **Drift recalibration + hop** (2026-08-06, all in `Simulation` and
  `Config/Handling` / `Config/Effects`). `DriftGrip` 3.5 -> 2.9 with
  `MaxSlip` 32 -> 38 as a set; grip is now a chased value rather than a
  per-state switch; `HopSnap` restored the hop's descent (#22); landing
  compression is scaled by impact and rung out by a damped spring.
  If drifts start running wide or the kart feels like it pogos on
  landing, suspect these before anything else.
- **The drift button must now be held ~70ms longer** — the hop lasts
  200ms instead of 133ms, and the drift is still gated on the button
  being down at touchdown. Intended, but it is the most likely thing to
  be reported as "drift sometimes doesn't engage".

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
