# SPEC — packaging the kart across places

Edit the lobby, everything else picks it up. Two mechanisms, and the
whole design is **making sure they never own the same instance.**

---

## The two owners

| what | owner | how it travels |
|---|---|---|
| **code** — everything under `src/` | git → Argon | sync to each place |
| **shared art** — kart models, `BotRig`, `Powerups` | Roblox **Package** | publish in the lobby, update button everywhere else |
| **the track** — spawns, tagged parts, geometry | the place itself | never shared |

Argon syncs *text files*. A kart is a tree of MeshParts, welds,
attributes and pivots — there is no text file for that, and committing
an `.rbxmx` gives you an unmergeable blob that git can't diff. Packages
are Roblox's answer and they work across experiences, not just within a
universe.

---

## The landmine, defused

`Drinking System.project.json` used to map `ServerStorage`,
`StarterGui` and `StarterPack` to folders in `src/` that contained
**zero files** — while four services looked for models in ServerStorage.

Argon owning a folder whose contents it doesn't know about is how
`Config/Suspension.luau` got deleted four times. Pointed at your art it
would be worse, because a model isn't recoverable from git.

Those three mappings are **removed**. Argon now syncs only what git
actually holds. Studio owns ServerStorage outright, which is what makes
the Package safe to put there.

> **The rule:** if Argon syncs it, a Package must not contain it. Config
> lives in `ReplicatedStorage/BloxKart/Config` and is *code* — tune it in
> the repo, not in Studio, or the next sync overwrites you.

---

## Setup

### Once, in the lobby

| step | what |
|---|---|
| 1 | In `ServerStorage`, make a Folder — **`KartAssets`** |
| 2 | Move into it: every kart template, **`BotRig`**, the **`Powerups`** folder |
| 3 | Right-click the folder → **Convert to Package** |
| 4 | Set ownership to your group if the other places are the group's |

### Once, in each other place

| step | what |
|---|---|
| 5 | Toolbox → **Inventory** → **My Packages** → drag `KartAssets` into `ServerStorage` |

### Every time after

| step | what |
|---|---|
| 6 | Edit in the lobby → right-click → **Publish Changes to Package** |
| 7 | Other places show a blue badge → right-click → **Get Latest Package** |

Select the `PackageLink` and tick **AutoUpdate** to skip step 7 — the
place pulls the newest version when a session opens it.

---

## Nesting broke two lookups

Wrapping the art in a package folder puts it **one level deeper**, and
the four services that find it were not consistent about that:

| call site | was | now |
|---|---|---|
| `Assets.luau` — projectile art | recursive | unchanged |
| `KartFactory.luau` — kart template | recursive | unchanged |
| `BotService.luau` — `BotRig` | **top level only** | recursive |
| `RaceService.luau` — `Powerups` | **top level only** | recursive |

`Assets.luau` already carried the comment *"RECURSIVE, because art gets
filed"* — the lesson was learned once and never applied to the other
three sites. Both failures were silent: the bot fell through to the
default rig, the hazard fell back to a grey box, and neither said why.

**Requiring a specific parent is asking the human to remember an
implementation detail.** Every lookup now just goes and finds it, so the
art can be filed however makes sense to you.

---

## What must not go in the package

- **Anything Argon syncs** — two owners, and the loser is whoever wrote
  last
- **The track** — geometry, spawns, `GlideRamp` / `FlipRamp` / checkpoint
  parts. These are the *place*; sharing them means every place is the
  same place
- **Place-specific tuning** — it's config, so it's code, so it's git

---

## If it goes wrong

| symptom | cause |
|---|---|
| art vanished after a sync | Argon owns that folder. Check the project tree — it should not list `ServerStorage` |
| bots spawn with the default rig | `BotRig` not found. Now recursive, so the name doesn't match `Bots.RigName` |
| hazards are grey boxes | same, for `Powerups` / `Items.HazardModelFolder` |
| update badge never appears | the place has its own *copy*, not the package. Delete it and re-insert from My Packages |
| edits in one place don't stick | you edited a package instance without publishing — Studio treats it as a local override until you do |
