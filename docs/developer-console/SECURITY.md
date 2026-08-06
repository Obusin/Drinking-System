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
5. **Private servers are not treated specially.** `PrivateServerOwnerId` is
   reported but confers nothing — owning a private server does not grant
   console access.
