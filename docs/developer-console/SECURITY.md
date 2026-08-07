# Developer console — security

> No Roblox remote system can honestly be called non-exploitable. This one
> is **server-authoritative, narrowly permissioned, validated, rate-limited,
> audited and fail-closed.** That is a different and achievable claim.

## Threat model

Assume an attacker can read every client script, discover the remotes, fire
them by hand with arbitrary arguments, modify local UI and state, replay
requests, spam, and spoof anything displayed on their own screen.

Therefore: **the client is never trusted, and hiding the window is not
security.** The console UI is a convenience for the permitted; the server
behaves identically whether it exists or not.

## Identity

Authorisation is by **`Player.UserId`**, read on the server from the
authenticated session. Never by username — names are mutable and
re-registerable, so a name check is an account takeover waiting for someone
to rename themselves.

| role | may |
|---|---|
| `owner` | everything, incl. clearing *other* developers' entities |
| `developer` | grant, spawn, inspect, clear their own entities |
| `viewer` | read only |

Roles are ranked; a command declares a **capability** (`GRANT_ITEM`), never a
role. An unregistered capability **denies and warns**, so a typo in a command
declaration cannot invent a privilege.

### The roster is server-only

`DevRoster` lives in `ServerScriptService`. The brief suggested a shared
module; anything in `ReplicatedStorage` is readable by an exploiter, and
publishing the list of privileged accounts is free reconnaissance — it names
exactly whose account is worth stealing. The client learns **one bit about
itself** (may I open the UI), never the list.

## Request path

Every request walks the same order. **Authorisation is checked before the
command name is even looked up**, so an unauthorized caller gets an identical
answer whatever they send and cannot enumerate commands by comparing errors.

```
1 authorized at all?   2 command registered?   3 holds its capability?
4 requestId fresh?     5 within rate limit?    6 payload validates?
7 elevation check      8 run                   → audit either way
```

`NOT_AUTHORIZED` deliberately covers *not on the roster*, *insufficient role*
and *no such command* — three truths, one reply.

## Validation

- Every command declares a shape; **unknown fields are rejected**, not ignored
- Payload **depth and breadth are capped before any field validator runs**, so
  an adversarial payload cannot burn CPU inside validation itself
- NaN and infinity are rejected explicitly — a range check alone passes NaN
- The handler receives a **rebuilt** table containing only validated values,
  so it can never be handed something a validator did not pass
- Ids are checked against the **live registry** at call time

## No arbitrary anything

Not accepted from a client, at all: **Instances**, property names, module
paths, method names, service names, remote names, code strings, require ids,
world coordinates.

The client sends a UserId, a registered item id, an enum value, or a
server-generated entity id. The server resolves every one of those itself.

## Entity resolution

Developer-spawned objects get a **server-generated id** prefixed with the
JobId, recorded in `DevRegistry`. `get(id, kind)` checks the kind too — without
that, "remove this pickup" would accept an AI's id.

**Cleanup walks the registry.** A legitimate match bot was never added to it,
so it cannot be removed — a structural guarantee, not a check somebody has to
remember.

## Rate limiting

Sliding window, **per player per command**. Fixed buckets let 2× through across
a boundary. Rejected attempts are **not** counted, or a spammer could extend
their own lockout — a rate limit turned into a denial of service against a
legitimate developer. **A command with no declared rate is denied, not
unlimited.**

`AI.MaxDevAI` is a separate hard ceiling: the limiter bounds how *fast*, the
cap bounds how *many*.

## Replay

Request ids are remembered per user for 120s and duplicates rejected. **This is
not a security boundary** — an attacker generates a fresh id. It stops a
retrying or buggy client double-applying an action, which for "spawn AI" is
the difference between one kart and five.

## Audit

In-memory ring buffer, accepted **and** rejected. Payloads are *summarised*,
never stored: a log the caller can grow without bound is a memory-exhaustion
bug wearing a security feature's clothes. Denials from non-roster accounts also
go to server output, because nobody is watching the console for the request
that matters.

Identity in the log comes from the authenticated `Player`, never from the
payload — a caller cannot forge whose name is recorded.

## Fail closed

Malformed roster entry, unknown capability, missing rate, validator that
throws, handler that throws, unresolvable target, absent gameplay service —
**all reject.** The router pcalls both the validator and the handler; the real
error goes to the server log, never to the caller, because it can carry file
paths and internal state.

## Moderation (kick / ban / unban)

Added 2026-08-07. These are the only actions here that reach **beyond the
current server**, so they carry two protections nothing else needs.

### Rank immunity

`DevPermissions.canModerate` is enforced **by the router**, not by the
handlers, for the same reason permissions are: a check written per command is
one that will eventually be forgotten in one of them — and this is the one
where forgetting it means a developer can ban the owner.

- **Never yourself.** Kicking yourself is silly; banning yourself is
  unrecoverable without a second owner.
- **Never an equal or senior.** A developer cannot touch an owner or another
  developer. Without this, one compromised developer account can remove
  everyone able to revoke it — turning a small breach into a total one.

The refusal is deliberately vague (`Permission denied.`) so the reply cannot
be used to discover who is on the roster. The audit log records the real
reason.

### Confirmation is in the schema, not the UI

`ban_player` and `unban_player` require `confirm = true` as a **validated
field**. The UI's two-click arming is therefore load-bearing rather than
decorative: a stray click, a replayed payload or a hand-built remote call that
omits it fails validation on the server.

Arming is per (action, target) and clears on tab or selection change, so an
arm left sitting cannot fire at whoever happens to be selected later.

### Capability split

| action | capability | why |
|---|---|---|
| kick | `KICK_PLAYER` (developer) | annoying, reversible by rejoining, useful mid-playtest |
| ban | `BAN_PLAYER` (**owner**) | persists, reaches absent accounts, not undoable by the target |
| unban | `UNBAN_PLAYER` (**owner**) | — |

**`unban_player` is deliberately NOT rank-checked.** It is the recovery path:
requiring the actor to outrank the target would make a mistaken ban on a
fellow owner permanently unfixable from here, which is the opposite of what
rank immunity is for.

### Uses Roblox's native ban API

`Players:BanAsync` / `UnbanAsync` — enforced by Roblox at join, persistent
without a store of our own, and able to cover known alts. A hand-rolled ban
list would need its own DataStore and a secured join-time check, which is
more persistent surface reachable (indirectly) from a remote.

- `ApplyToUniverse = false` — this experience only. A universe-wide ban from a
  debug console is a larger blast radius than this tool should have.
- `ExcludeAltAccounts` is passed **explicitly** rather than left to the API
  default: whether a ban reaches alts is a policy decision and should be
  visible in the code that makes it.
- Duration is bounded (0 = permanent, max 365 days), so a typo cannot become a
  thousand-year ban.
- Reasons are length-capped and stripped of control characters — **not text
  filtered**, since they are authored by an owner and filtering would mostly
  mangle legitimate wording.
- Rate limit is harsh (2 per 60s), so a runaway script or stolen session is a
  nuisance rather than a catastrophe.

**BanAsync does not work in Studio** — it needs a published, running
experience. The adapter reports `UNAVAILABLE` rather than swallowing the
error, so a test cannot silently look successful.

## Profile inspection

Read-only, `VIEW_PROFILE` (**developer**, not viewer — currency, ownership and
progression are the closest thing in this game to real player value, and a QA
account that only watches races has no business reading balances).

**Cost:** `DataService.get` returns the already-loaded in-memory table for a
player in this server. No DataStore request, no yield, no quota. Reading an
**offline** player would be a real request against a shared per-minute budget,
which is why this only ever looks at people present.

**Bounded output.** `parts` and `karts` are open-ended dictionaries; counts are
exact but lists are capped at 40 and flagged when trimmed. Shipping a profile
wholesale would put an unbounded table through a remote and into a UI that
redraws every frame.

### Currency editing (added 2026-08-07)

Owner-only (`EDIT_CURRENCY`), confirmation-gated, rate limited to 3 per 30s,
and bounded to +/-100,000 per call. Grouped with ban because it is the other
action with **no undo** — a ban has `UnbanAsync`; deleted currency has nothing.

**It goes through `Progress.grant` / `Progress.spend`, never `data.bolt`.**
DataService's header is explicit that *"Progress owns balances and is the only
thing that changes one... two modules that both write a balance is the dupe
this whole design exists to avoid."* A console writing the field directly
would be exactly that second writer, and it would skip the **Ledger** — making
a developer-granted balance the one transaction in the game with no row behind
it, invisible in an audit precisely where an audit matters most.

Routing through the front door inherits three guarantees for free:

- `spend` **refuses to go below zero** and returns false, rather than clamping.
  Silently taking "as much as they had" is a different action from the one
  requested, and the caller is told which happened.
- the ledger row, the cap and the on-screen award toast all keep working
- every console change carries a `dev:<name>` reason, so it stays
  distinguishable from an earned amount forever

**No "set to N".** Only add and remove. A set would have to write the field
directly to force a value down — the second writer again. Add/remove composes
to the same outcome through the front door, and it is the honest shape because
the ledger records a delta, not a decree.

Audit records the **before and after** value, which is what a mistaken edit
needs to be recoverable.

**Still no editing of anything else** — parts, karts, quests, pass and drops
remain read-only. Those have no `Progress`-equivalent single owner, so a
console write would be the second-writer problem all over again.

The response always carries `mockStore`, and the UI prints it first and
loudly. In Studio the store is mocked, so every value is a fresh default and a
restart wipes it — without that line a reset profile reads as lost data, which
this project has already misdiagnosed five times.

## Known limitations

1. **Item slots are client-authoritative.** `give` reuses the real grant path
   and is authoritative. `clear` is **advisory** — the client is asked and
   obliges — and reading slots is **unavailable**. Fixing this means moving
   item state server-side (BUGS #6), a gameplay change, not a console feature.
2. **The audit log does not survive the server.** Persisting it means a
   DataStore write path reachable from a remote; that is a larger surface than
   the log is currently worth.
3. **No global/cross-server anything.** Current server only, by design.
4. **A compromised developer account has developer powers.** Rate limits and
   the audit trail bound and record the damage; they do not prevent it.
5. **A ban is only as good as Roblox's enforcement.** Determined evasion via
   new accounts is outside what any in-experience tool can prevent;
   `ExcludeAltAccounts = false` covers alts Roblox already knows about.
6. **Private servers are not treated specially.** `PrivateServerOwnerId` is
   reported but confers nothing — owning a private server does not grant
   console access.
