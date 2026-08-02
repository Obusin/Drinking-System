# BloxKart — Lobby State and Race State

Written 2026-08-02, the day the split went from designed to working.
Covers everything that changed once the game became more than one
place: who you are on foot, how a kart is called and put away, how you
leave for a race and come back, and what stops the two states from
bleeding into each other.

Related: `SYSTEM.md` §4/§4b (the place architecture this sits on top
of) · `SECURITY.md` (the remote-trust rules this follows) · `BUGS.md`
#14–#17 (every bug this section produced, in order)

---

# The two states, in one table

| | Lobby | Race place |
|---|---|---|
| You arrive | on foot | already seated |
| Kart | call it, put it away | always have one |
| Round loop, AI field | no | yes |
| Items, hit reactions, feed line | **yes** | yes |
| Progress bank (XP/Bolt/quest metrics) | **no** | yes |
| Music | Festival Town, Sunset Jazz | Sunday Morning Groove |
| The way out | the RACE prompt | automatic, after enough rounds |

One row is not "no" by policy — it's structural: `MatchService` and
`BotService` never start in a lobby at all, so there is no round to
join and no AI to fill it. Everything else on this page is either
config (`Config.Places`) or a guard that had to be written by hand.

---

# What decides which one you are

`Place.isLobby()` / `Place.isRace()`, resolved once at require time from
`game.PlaceId` vs `Config.Places.LobbyPlaceId` — full account in
`SYSTEM.md` §4. Nothing below re-derives this; everything reads it.

`Config.Places.ForceRoleInStudio` overrides it for testing, **Studio
only**, and warns loudly whenever it's on — see the config file for why
a published server must never take this route.

---

# Calling a kart — `PlayerVehicleService` / `VehicleHud`

Press the bound key (`G` by default) or the on-screen prompt. The
server decides everything; the client only asks.

**The remote (`KartVehicle`) doesn't exist on a race place at all** —
`PlayerVehicleService.start()` only runs inside the lobby branch of
`init.server.luau`. A modified client on a track firing this remote
finds nothing to fire at, not a refusal.

## Placement — an attribute, never a direct move

The server does **not** `PivotTo` the kart into place. It computes
where the kart belongs (in front of the player, flattened onto their
facing) and stamps it as a CFrame attribute, `Names.VEHICLE_SPAWN_CF`.
The client reads it once on attach and calls `Simulation:RespawnAt`
itself — the same door the starting grid and every checkpoint respawn
already use.

**This is not a style choice.** `KartService.spawnFor` seats the player
as its last internal step, and seating fires `bindOwnership`
synchronously — unanchoring the hitbox and handing it to the player's
*network ownership* before any line after `spawnFor` returns gets to
run. A server CFrame write after that races the client's own
`Simulation`, which reads the hitbox's position at whatever instant it
happens to construct. Sometimes that's the pre-request build spot,
sometimes the intended one — the race is real, not theoretical, and it
is exactly what `BUGS.md` #17 was. Attributes don't have this problem:
network ownership governs physics properties, never attributes, so a
server-set attribute always arrives.

**Applied once per kart *model***, not cleared server-side. The client
tracks which model it has already consumed
(`vehicleSpawnAppliedFor`) — matching how the grid's own CFrame
attribute is left in place and consumed once per round rather than
wiped. Without this, falling out of a lobby kart and being reseated
into the *same* one (`KartService`'s own recovery, `bindLockIn`) would
replay the teleport and yank the player back to wherever they first
called it.

## Clearance

A 7-stud kart has to fit wherever the player happens to be standing —
a doorway, a gap between props. The server tests a box
(`Config.Lobby.ClearanceSize`) against `WorldFilter`'s own exclusion
list before spawning, and **refuses with a reason** rather than
wedging a kart into geometry. `"blocked"` / `"failed"` / `"spawned"` /
`"despawned"` are the only replies; the client's label only ever
follows what the server actually did.

## Putting it away — `KartService.despawnFor`

Deregisters *before* destroying — this is what stops `bindLockIn`
re-seating the player into a kart that is already on its way out; that
guard reads `karts[player] ~= kart`, so the order matters.

Restores the jump. Seating a kart zeroes `JumpPower`/`JumpHeight` and
disables the `Jumping` state so nobody hops out at speed; undone here
from `StarterPlayer`'s own values, so it follows whatever the place is
actually configured for rather than a hard-coded number.

---

# The way out — `QueueService` / `QueueHud`

One prompt (`P` by default), one remote (`KartQueue`), same
lobby-only-existence guarantee as the vehicle remote.

**The client sends `"play"` and never a destination.** The server
picks a track at random from `Config.Places.Tracks` — random rather
than first, so a second track starts getting used the day it's filled
in rather than the day someone writes logic to choose between them.
This is a security rule, not a style one: a remote that accepts a
place id is a remote that will teleport your players into somebody
else's experience. See `SECURITY.md`.

Mode travels in `TeleportOptions:SetTeleportData` (`{ fromLobby = true,
mode = "casual", trackId = ... }`) rather than living on the track's
own row, because a track is a **map** and casual/ranked/time-trial are
**rules** — see `SYSTEM.md` for why that split matters for how many
places this game ever needs.

Failure is handled twice, because a teleport can fail twice:
`pcall` around `TeleportAsync` catches the synchronous refusal;
`TeleportService.TeleportInitFailed` catches the one that arrives
later. Skipping the second leaves a player staring at "FINDING YOU A
RACE…" forever — worse than an error, because it looks like it's still
working.

`Place.playableTracks()` already excludes any row whose `placeId` is
`0` or equals the lobby's own id, so an unconfigured second track
degrades to "not offered" rather than "offered and broken."

---

# Coming back — `ReturnService`

Race places only. After `Config.Places.ReturnAfterRounds` rounds (3),
waits `ReturnDelay` seconds (6) into Results — so the board is actually
seen — then batch-teleports everyone still in the server back to the
lobby. `ReturnAfterRounds = 0` means never, read literally: some
players want to sit on one track all night.

**Composed onto `MatchService.onResults`, not assigned to it.** That
hook is single-subscriber, and `BotService.takeOverAll` already needed
it — a second `MatchService.onResults = ReturnService.onResults` would
have silently replaced the first rather than adding to it. `init.server`
composes the two by hand:

```lua
MatchService.onResults = function()
	BotService.takeOverAll()
	ReturnService.onResults()
end
```

This exact shape — one hook, two unrelated systems both needing it —
is the concrete case `SYSTEM.md` §4b points at as the reason an event
bus is eventually needed. Until then, compose by hand at the call site
and say so in a comment, rather than let the second assignment win
silently.

A failed batch teleport leaves everyone exactly where they were — mid
race — rather than retrying. That's the honest fallback, not a
stranding: nobody is worse off than if `ReturnService` didn't exist.

---

# The economy only counts in a race

Items are deliberately live in the lobby — the whole point of a
practice ring is finding out what a missile feels like before it
matters. That meant every mechanism that produces a **reward** had to
be re-examined once mechanisms that produce *feel* stopped implying a
race was happening.

**Two layers, because there are two places the same mistake can hide.**

## The bank — `Progress.luau`

`Progress.hit`, `Progress.eliminated`, `Progress.report` — the three
entry points a lobby can actually reach — all gate on one shared
`inARace()` check (`Place.isRace()`). `Progress.finished` needs no
equivalent guard: `MatchService` never starts outside a race place, so
there was never a path to it from a lobby at all.

Zero behaviour change on an actual race place — `Place.isRace()` is a
place-wide constant, always true there. This only removed a path that
was exclusively open from the lobby side.

## The display — `Tally.luau`

Found the same day, by testing rather than reading: drift progress
still visibly climbed in the lobby *after* the bank was closed. The
server was correctly refusing to count it — but `Tally:Add`, the
client's own local counter feeding the quest panel's live progress bar,
had no such guard and kept incrementing regardless of place. The number
was real on screen and fictional everywhere else; it would have sat
there until the next real quest sync quietly took it back, which reads
as a bug rather than a rejected report.

`Tally:Add` now checks the same `Place.isRace()` the server does. The
count never starts, so the bar never moves and there is nothing to
give back later.

**The lesson, stated once so it doesn't need rediscovering:** closing a
grant path stops the *bank*. It does not stop the *display* unless the
display is checked separately — a client-side optimistic counter built
for responsiveness will happily keep counting toward a number the
server has already decided not to honour. Presentation must default to
correct; a security fix that leaves a lying number on screen is only
half done.

---

# What still shows in the lobby, on purpose

Hit reactions, the kill-feed line, and item pickup itself are
untouched by any of the above — only the *reward* calls are gated.
Practising still feels the same. It just doesn't pay.

The missile/lightning warning slot (`RaceHud`'s alert, not its
readouts) stays visible in the lobby too — `RaceHud:SetVisible` hides
only the lap/time/checkpoint panel. An incoming missile still has to
be able to shout at you in the practice ring, or the one place you'd
actually want to learn to dodge is the one place the warning never
fires.

---

# The driving HUD follows the kart, not the place

`ItemHud`, `ControlsHud` and `SpeedHud` are all gated on **having a
kart**, not on being in a lobby — that's the honest condition, and it's
one rule for both places: a race always has a kart, so the HUD is
always up there; a hub shows it exactly when a kart is called and hides
it exactly when it's put away. One `setDrivingHud(bool)` in
`init.client.luau`, called at attach, at detach, and once at startup —
nothing to keep in sync between two separate answers to "should this be
visible."

---

# Every lobby-relevant remote, and where it exists

| Remote | Exists on | Client sends | Server decides |
|---|---|---|---|
| `KartVehicle` | lobby only | `"spawn"` / `"despawn"` | placement, clearance, cooldown |
| `KartQueue` | lobby only | `"play"` | which track, mode |
| `KartFinish` | race only | nothing (no args since #14) | the elapsed time itself |
| `KartStats` | both | a driving-stat batch | gated to no-op outside a race |

"Exists on" is the strong guarantee — see `SECURITY.md` for why a
remote that isn't created at all beats a remote that exists and
refuses.

---

# Open, deliberately not built yet

- **`Config.Places.RequireLobbyEntry`** stays `false`. Turning it on
  before both places are independently stable locks out direct Studio
  testing of the race place — see the config's own comment.
- **No `NoKart` zones or garage** in the lobby yet — narrowed scope, per
  the "just the kart and the power-ups" decision. The practice ring has
  no boundary of its own today.
- **No void zones in the lobby.** `RaceService`'s void-elimination path
  is fully wired and fully gated (`Progress.eliminated` won't pay for
  it), but nothing is tagged `VoidZone` there yet, so it's dormant
  rather than tested.
- **The parked practice-ring track** (`Config.Music`, "Must Get Gud
  Enuf") has nowhere to plug in until the lobby has a notion of zones —
  `Music:Update` only ever asks "what phase," never "where in the
  world."
