# Developer Operations Console — architecture

## The one idea

Everything the console can **see** is a **probe**. Everything it can
**do** is a **command**. Both are table entries in a registry, and the UI
is generated from those registries rather than written per feature.

That is the whole extensibility story:

| to add | you write | you do NOT touch |
|---|---|---|
| a new monitor | one probe entry | UI, remotes, router, permissions |
| a new action | one command entry | UI, remotes, router, permissions |
| support for a new game system | one adapter | anything else |

If adding a feature ever requires editing the router, the remote layer or
a tab's rendering code, the design has failed and that is the signal to
fix it rather than work around it.

---

## Layers, and what each is allowed to know

```
  StarterPlayerScripts/KartClient/DeveloperConsole/     ← VIEW ONLY
    DevConsoleClient      remote plumbing, request ids, response routing
    ConsoleState          last snapshot + last responses (a cache, nothing more)
    Windows/Tabs          Iris rendering, driven by the registries
                                    │
                          ─────── remotes ───────
                                    │
  ServerScriptService/KartServer/DeveloperConsole/      ← AUTHORITY
    DevConsoleService     owns the remotes, the ONLY entry point
    DevCommandRouter      permission → rate limit → replay → validate → run
    DevCommands           the command registry
    DevProbes             the probe registry
    DevPermissions        the single authorisation API   ✅ built
    DevRoster             the UserId allowlist           ✅ built
    DevRateLimiter        per player, per command, per window
    DevAudit              in-memory ring buffer
    DevRegistry           developer-spawned entity tracking
    adapters/
      PowerupAdapter      the only thing that knows about Items/RaceService
      AIAdapter           the only thing that knows about BotService/KartService
      WorldAdapter        pickups, cleanup
      PlayerAdapter       player + kart + race inspection
      ServerAdapter       place, job, uptime, counts
                                    │
  ReplicatedStorage/BloxKart/DeveloperConsole/          ← SHARED CONTRACT
    Protocol              remote names, response codes, envelope shape
                          (NO roster, NO permissions — see SECURITY.md)
```

**The rule that keeps this honest:** an adapter is the only module that
imports a gameplay service. If `DevCommands` ever requires `BotService`
directly, the isolation is gone and an upgrade to the AI system breaks
the console in a place nobody thinks to look.

---

## Request lifecycle

Every request, without exception, walks the same path:

```
client fires  { requestId, command, payload }
   │
   1. is the sender authorized AT ALL?        DevPermissions.isAuthorized
   2. is the command registered?              DevCommands[name]
   3. does the sender hold its permission?    DevPermissions.can
   4. is this requestId fresh?                replay window
   5. is the sender within rate limits?       DevRateLimiter
   6. does the payload validate?              command.validate
   7. does the target resolve?                adapter, server-side only
   8. run                                     command.run
   │
   audit (accepted or rejected, with the failure code)
   │
respond      { requestId, success, code, message, data }
```

Steps 1–6 are generic and live in the router. **A command never
re-implements any of them.** A command author writes a validator and a
handler; everything else is declared.

Order matters and is deliberate: authorisation is checked before the
command name is even looked up, so an unauthorized caller cannot use
error messages to enumerate which commands exist.

---

## The command registry

```lua
DevCommands.give_item = {
    permission  = "GRANT_ITEM",
    rate        = { burst = 5, per = 10 },     -- 5 per 10s
    destructive = false,
    validate    = function(p)                   -- returns ok, err
        return Schema.shape(p, {
            targetUserId = Schema.userId,
            itemId       = Schema.oneOfRegistry(Items),
            slot         = Schema.intRange(1, IT.MaxHeld),
        })
    end,
    run = function(ctx, p)                      -- ctx = { player, role, ... }
        return PowerupAdapter.give(p.targetUserId, p.itemId, p.slot)
    end,
}
```

Declared, not coded: permission, cost, validation and destructiveness are
data. That is what lets the router enforce them uniformly and what lets
`COMMANDS.md` be generated from the registry rather than hand-maintained
and wrong.

## The probe registry

```lua
DevProbes.server = {
    permission = "VIEW_SERVER",
    every      = 1,                             -- seconds; 0 = on request
    read       = function() return ServerAdapter.snapshot() end,
}
```

The client asks for a **snapshot**; the router runs every probe the
caller is permitted to see and returns them keyed by name. A viewer gets
fewer keys than an owner — the filtering happens server-side, so an
unauthorized field is never sent rather than sent and hidden.

Adding a monitor is one entry. The Iris tab renders whatever keys the
snapshot contains, so a new probe appears in the UI with no UI work.

---

## Integration with what already exists

These are the seams found by inspection, and the adapters wrap exactly
these. Nothing else is touched.

| system | existing entry point | adapter use |
|---|---|---|
| Items | `Items.All`, `Items.byId`, `Items.roll` | populate the selector; validate ids |
| Grant | `KartItem` remote → `FireClient(player, id)` | reuse verbatim — this is how a real box grants |
| Pickups | `IT.BoxTag` / `IT.DropTag` + `RaceService` | spawn tagged boxes; collection stays server-validated |
| AI | `KartService.addBot` + `BotService` | reuse; dev bots tagged separately |
| Karts | `KartService.kartFor(player)` | inspection, respawn, reset |
| Race | `Standings.order/placeOf`, `MatchService` | placement, lap, phase |
| Profile | `DataService.get` | read-only. **No editing in this milestone.** |

### Two constraints found during inspection

**1. Item slots are client-authoritative.** The server rolls an item and
fires it to the client; `KartClient/Items.luau` owns the slots. So:

- **give** reuses the real grant path and is genuinely authoritative ✅
- **clear** and **read slots** have no server-side truth. They are
  implemented as a client-obeyed instruction and a client-reported
  snapshot, **labelled `advisory` in the UI**, never presented as fact.

This is the honest option. The alternative — the console inventing its
own idea of a player's inventory — would make the console lie whenever it
disagreed with the game, which is worse than saying "unavailable". Making
this authoritative means moving item state server-side, which is a
gameplay change (BUGS #6, "two client-authority seams") and out of scope.

**2. `BotService` is race-only** (`if racing then` in `init.server`).
In the lobby there is no AI system running:

- **static AI** works in both places (it is a kart, not a bot)
- **driving AI** is race-only, and the command declares
  `places = { "race" }` so the router rejects it in the lobby with
  `WRONG_PLACE` rather than half-spawning something inert

---

## Developer entity tracking

Nothing the console spawns is ever addressed by Instance. Each spawn gets
a server-generated id and a record:

```lua
{ id, kind = "pickup"|"ai", instance, spawnedBy, spawnedAt, meta }
```

The client may only ever send an **id**. The server resolves it, confirms
it is in the registry, and confirms it belongs to this server. That is
what makes "remove all developer AI" safe: cleanup iterates the registry,
so it **cannot** touch a legitimate match bot, because a match bot was
never in it.

Cleanup triggers: explicit command, spawner disconnects (configurable),
round end, server shutdown.

---

## UI

Iris is the view layer and nothing else. A tab may render cached data,
collect input, and submit a request. A tab may **not** call a gameplay
service, mutate state, or hold an opinion about permissions.

Tabs: **Server · Players · Power-Ups · AI · World · Logs**

The client self-gates the UI as a convenience — an unauthorized player
never builds the window — but that is cosmetic. The server rejects every
request regardless of whether the UI exists, which is the only statement
that matters.

---

## Build order

Each stage is independently testable, and each is useless to an attacker
without the next.

1. **Spine** — Protocol, router, rate limiter, replay, audit, one
   trivial `ping` command. Proves the whole security path end to end
   before anything can mutate state. ✅ ← *next*
2. **Read-only** — Server + Logs tabs. Still nothing mutable.
3. **Players** — inspector, respawn, reset kart.
4. **Power-ups** — give self, give other, clear, slots.
5. **World** — pickups, cleanup.
6. **AI** — static, driving, freeze, remove.

Stopping after any stage leaves a working, secure console with fewer
features — never a half-wired one.

---

## Explicitly out of scope for milestone 1

Persistent data editing · global announcements · cross-server commands ·
arbitrary attributes · arbitrary code execution · a full runtime config
editor · moderation actions · external dashboards.
