# SECURITY — what the server owns, what it cannot, and every remote

Audited 2026-08-02 against a written security doctrine: *the client is
responsible for input and presentation only; the server is responsible
for validation and authority.*

This file covers **gameplay trust** — the remotes, and what a modified
client can do through them today. The **data** half (session locking,
idempotent grants, `UpdateAsync`, receipts, drops) is designed in the
vault note *BloxKart Data Security and Drops*, Rules 1–7. Two files
because they fail differently: one is exploited in a race, the other in
a DataStore.

Related: `SYSTEM.md` §6 (the authority model) · `BUGS.md` #6

---

# 1. The clause that cannot hold, and what replaces it

> *"Never trust positions."*

**A kart's position is decided by its owner's client, structurally.**
The controller is kinematic — the client integrates position, forward,
up and speed by hand and writes the result to the hitbox, which is
unanchored and network-owned by that player.

Making position server-authoritative means simulating every kart on the
server. That is not a fix to this codebase; it is a different codebase,
and it throws away the controller the whole game is built on.

So the doctrine needs one substitution, and everything else in it
survives intact:

> **The server is not the source of truth for position. It is the
> referee.**

The server *does* see every kart's replicated CFrame. That is enough to
do the three things that matter:

1. **Reject claims inconsistent with what it can see.** You say you took
   that box — are you near it? You say you hit that player — were you
   close, and did the server ever give you something to hit them with?
2. **Reject impossible movement.** Distance covered per tick against a
   speed ceiling. A teleport to the finish line is not a close call.
3. **Own the clock.** A lap time is server time minus when Racing
   started. Never a number the client chose.

This converts *trusting* the client into *bounding* it. It will not stop
a careful cheater from shaving a corner. It stops every cheat that
produces an impossible number, which is all of the ones that reach a
leaderboard or a balance.

**Perfect authority over position is not available at any price we are
willing to pay. Bounded dishonesty is, and it is cheap.**

---

# 2. What already complies

Worth stating precisely, because it is most of the doctrine and it means
the remaining work is small.

- **Items are rolled server-side**, weighted by race position. A client
  cannot choose its own item. (`RaceService`, `Items.roll`)
- **Box state is server-owned** — the `TAKEN` attribute, the
  transparency, the respawn timer. Clients cannot desync it.
- **Hazards and spilled items are server-spawned.** The reason in the
  code is the right one: a client cannot be trusted to create a world
  object that affects other players, and a dropper who disconnects
  should not leave a phantom behind.
- **The client never asks for a reward.** The reward remote is
  server→client only, with an explicit comment that nothing is listened
  for on it. The server decides what was earned.
- **One grant path.** `Progress.award` / `grant` / `spend`. No other
  script touches a balance.
- **Every balance change writes a `Ledger` row.**
- **Progress is monotonic and frozen after finishing.** A respawn cannot
  demote you; nothing after the flag can improve your placement.
- **The hit remote cannot target its own sender**, and is rate-limited.
- **Stats are clamped** against `Config.Level.StatCaps` per race.

---

# 3. Every inbound remote, and what it actually checks

Ten handlers on the server. This is the whole attack surface.

| Remote | The client decides | The server checks | Verdict |
|---|---|---|---|
| `KartFinish` | **the finish time** | NaN, negative, number | **worst offender** |
| progress relay | **the progress score** | monotonic, frozen after finish | jump upward unbounded |
| `statsRemote` | drift distance, boosts, hits | clamped to per-race caps | bounded, not honest |
| `KartItemPickup` | **which box** | tag, not taken, has parent, phase | **no distance check** |
| `KartHazard` (drop) | **where the mine goes** | types, item is a hazard, phase | **no distance check** |
| `KartHazard` (spill) | **where items scatter** | types, count ≤ MaxHeld | **no distance check** |
| `hitRemote` | **who was hit, and how** | is a kart, not self, 1s cooldown | **no distance, no holding check** |
| `voidRemote` | that it fell | — | low value to forge |
| `readyRemote` | that it is ready | phase | low value to forge |
| quest claim | which quest | server reads the reward from config | correct by design |

**None of the ten performs a distance check.** Every `Magnitude` call on
the server today is internal simulation, not validation of a claim.

## What that means concretely, today

A modified client can:

- **name any item box on the map from the start line** and collect the
  entire track's boxes without moving,
- **place a mine anywhere**, including on someone else's racing line
  across the map,
- **claim to have hit anyone from anywhere**, once a second, which now
  also grants XP — the code comment already names this: it turns
  griefing into farming, and farming gets automated,
- **report any finish time**, including one shorter than the race has
  been running.

None of this requires understanding the codebase. It requires firing a
RemoteEvent with plausible arguments.

---

# 4. The fixes, in order of value per line

## 4.1 The server owns the finish clock — DONE 2026-08-02

`MatchService.racingSince()` returns when Racing began. The finish
handler no longer receives a time from the client at all — the argument
was dropped from both ends, not just ignored — and computes elapsed
time itself: `workspace:GetServerTimeNow() - racingSince()`.

This was found urgent rather than merely overdue: `Config.Data.Enabled`
went on 2026-08-01, so from that date until this fix, every finish
banked a real, persisted reward from a client-chosen number. The
`Progress.luau` header comment claimed persistence didn't exist yet and
was itself stale by the same margin — fixed alongside this.

## 4.1b Found while fixing 4.1 — a finish is never checked against the

  race at all

The clock fix closes *how fast*. It does not touch *whether you raced*.
`finishKart` requires only that the phase is Racing and this kart has
not already finished — nothing ties a finish claim to lap or checkpoint
progress. A client can fire the finish remote the instant Racing starts
and claim first place, full XP and full Bolt, having driven zero studs.

The data to check this already exists: `Standings.ATTRIBUTE` is a
replicated progress score (`laps * 1e6 + checkpoints * 1e3 + fraction`),
so "has this kart actually finished" is `score >= TotalLaps * 1e6`
within some tolerance.

**Not fixed here, deliberately.** The score is itself client-reported
(Standings' own header says so plainly: *"the server isn't validating
times yet… it's the seam where that validation goes"*), the relay can
lag a frame or two behind an actual crossing, and a tolerance picked
without playtesting risks silently rejecting a legitimate finish — which
is worse than the exploit, because it fails quietly and looks like the
finish line stopped working. That shape — a fix that cannot be verified
without playing it — is exactly what FINDINGS calls out under *"two
reasoned fixes in a row that don't land means stop reasoning."* This one
needs a lap actually driven and watched before it ships.

**Order:** land this gated behind a generous tolerance, confirm a normal
finish still registers over several real races, then tighten it.

## 4.2 Distance checks — one idea, three remotes

The server has `KartService.kartFor(player)` and therefore the player's
replicated position. Every claim about a place in the world can be
tested against it:

- **box pickup** — reject unless within a few studs of the box
- **hazard drop / spill** — reject unless the CFrame is at the dropper
- **hit** — reject unless the two karts are within blast range

One helper, three call sites, and it closes the three exploits that are
trivially scriptable. **Highest value in the file.**

The tolerance has to allow for latency and for the fact that the
position the server sees is a frame or two old. Generous is fine —
"within 30 studs" still refuses "from across the map", and refusing the
impossible is the entire goal.

## 4.3 Idempotency keys on grants

Already designed as Rule 3 in the vault note, not yet built.

Server authority alone does not prevent a double payout. A player
finishes, the grant fires, a teleport races the profile save, and on
retry the server grants again — honestly, because nothing tells it that
it already did.

Every grant carries a unique id (`round-<jobId>-<round>-<userId>`), and
`Progress` refuses an id it has already seen. `Ledger` is already an
append-only record of every grant, so most of the storage exists.

**Cheap now. Awful once there are balances worth duplicating**, and the
cross-place teleport is exactly the situation that produces the retry.

## 4.4 Bound the upward progress jump

The TODO is already sitting in `RaceService` next to the monotonic
check, with the fix described. A score cannot rise faster than the
elapsed time allows.

## 4.5 The server owns which item you are holding

The server rolls the item and then forgets it. Nothing records that the
player still has it, so nothing can check that a claimed hit came from
an item that was ever granted.

This is the largest of these and the one that makes the hit remote
honest rather than merely bounded. Do it after 4.1–4.4.

## 4.6 Extend the Ledger

Purchases, reward claims, rare drops, and eventually admin actions.
**Into `Ledger`, not into a second log** — two audit trails is one
question answered in two places, and the one you check will be the one
that is missing the row.

---

# 5. What must be true before certain features ship

| Feature | Blocked on |
|---|---|
| Any global leaderboard | 4.1, 4.4 — a forged time on a board is permanent and public |
| Ranked | 4.1, 4.2, 4.5 |
| Robux purchases | `ProcessReceipt` idempotency (vault Part 4) |
| Trading or gifting | 4.3 and 4.5, without exception |
| Cross-place progression | 4.3 |

---

# 6. The principle to keep

**Do not build anti-cheat around detecting exploiters. Build systems
where exploiting achieves nothing.**

A detector is a race against someone with more time than you. A server
that calculates the reward, verifies the completion, owns the clock and
refuses the impossible does not care who is on the other end.

And the sharpest form of the rule, which decides every future case
without needing this document:

> **If changing a value would benefit the player, the client should
> never be the one deciding it.**
