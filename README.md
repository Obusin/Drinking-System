# DrinkSystem — Bartending Game

A Roblox bartending game where players mix drinks, serve customers, and deal with the consequences. Built with Argon for file sync.

---

## Setup

```bash
# Build the place file
argon build

# Sync with Roblox Studio (run this, then start Argon plugin inside Studio)
argon serve
```

> **Note:** Some assets live only in Studio (glass templates, shaker templates, animations, DrunkUI). See [Studio-Only Assets](#studio-only-assets) below.

---

## How to Play

### Bartender flow
1. Pick up a **glass** from the bar (click the world glass model)
2. Click **ingredient bottles** to pour — up to 4 ingredients per glass
3. If the recipe needs a shaker, pick up the **shaker** and the mix auto-shakes
4. **Click a table** while holding the finished drink to place it
5. Customers pick up the placed drink and click to consume it

### Customer flow
1. Pick up a placed **drink** from a table
2. Click to sip — each drink has 3 sips
3. Drunkness accumulates; screen distortion and stumbling kick in as it rises
4. Click/tap a **Water** part to sober up instantly (-35 drunkness)

### Mobile controls
- **Hold a drink near a tagged surface** → the surface glows (no ghost preview yet)
- **Tap the surface** → ghost preview appears at the exact tap spot + **Place** / **Cancel** buttons
- **Tap Place** → drink placed there; **tap Cancel or elsewhere** → dismissed
- **Tap anywhere that isn't a surface** → sip the drink
- Placement raycast uses `ScreenPointToRay` (GUI-inset corrected) — accurate at any camera angle.
  Front-face hits are projected onto the tabletop plane so forward-view taps don't land on the ledge.

---

## Recipes

| Name | Ingredients | Shaker | Garnish | Strength |
|---|---|---|---|---|
| Blue Screen | Vodqa, Coolnag, Soda Water | No | Lime | 100 ☠️ one-shot |
| Sgm Overdrive | Sgm Jinn, Vodqa, Caffemo | Yes | Lime | 85 |
| The Nguermo | Nguermo, Double Time, Barcandy | Yes | Cherry | 80 |
| Barcandy Bomb | Barcandy, Vermix, Maple Syrup | Yes | Cherry | 65 |
| Sgm Horizon | Sgm Jinn, Fonador, Simple Syrup | Yes | Orange | 60 |
| Calliamo Crush | Calliamo, Biljin, Creamora | Yes | Cherry | 55 |
| Debt Collector | JacklineDale, Maple Syrup, Creamora | Yes | Orange | 50 |
| Dealer's Choice | Almendra, Chocoluxe, Creamora | Yes | Cherry | 45 |
| Nguermo Noir | Nguermo, Chocoluxe, Maple Syrup | Yes | Cherry | 40 |
| Double Down | Double Time, Absmith, Sugar | No | Orange | 35 |
| Night Shift | Caffemo, Absmith, Simple Syrup | No | Cherry | 30 |
| Bukonelle Breeze | Bukonelle, Coolnag, Soda Water | No | Lime | 28 |
| Fonador Sling | Fonador, Tropica, Soda Water | No | Orange | 25 |
| Vermix Mule | Vermix, Soda Water, Mintverde | No | Lime | 20 |
| Dealer's Choice | Almendra, Chocoluxe, Creamora | Yes | Cherry | 45 |
| Heatstroke | Biljin, Tropica, Sugar | No | Orange | 15 |
| Minty Fresh | Mintverde, Soda Water, Simple Syrup | No | Lime | 8 |
| Tropicali | Tropica, Coolnag, Simple Syrup | No | Orange | 12 |
| Cocoa Rush | Cochoco, Creamora, Sugar | No | Cherry | 10 |

Strength is total drunkness added across all 3 sips. Drunkness max is 100.

### Water (sober-up)
Water is **not a recipe** — it's a direct-consume world object. Click/tap any part or model
with the attribute `DS_IngredientName = "Water"` (no glass needed, no `DS_Drinks` required)
and drunkness drops by `Settings.WaterSoberAmount` (default **-35**, ~1 medium drink).
Handled in `DrinkSystemController.onPour` before the glass check; guidance never blocks it.

---

## Drunkness Stages

| Stage | Threshold | Effect |
|---|---|---|
| Sober | 0–19 | Normal |
| Buzzed | 20+ | Slight walk speed reduction |
| Drunk | 45+ | Noticeable slowdown, screen starts wobbling |
| Wasted | 72+ | Heavy slowdown, random stumble ragdolls |
| Collapsed | 92+ | Full pass-out ragdoll for ~15s, once per 90s, wakes at 50% |

**Recovery:** 1.1 drunkness/second naturally (~90s to fully sober), or drink Water (-35 instantly).

---

## Visual Effects (drunk)

Screen distortion only — no darkening:
- **Camera sway** — slow sinusoidal drift simulating dizziness
- **Blur** — soft focus at higher drunkness
- **Depth of field** — focus distance oscillates (world "swims")
- **FOV breathing** — subtle pulse at Drunk+
- **Stumble** — ragdoll physics while still able to walk (floppy trippin)

---

## Tagging Guide (Studio)

Use **CollectionService tags** or **attributes** on world objects:

| Tag / Attribute | Type | Where to apply | Purpose |
|---|---|---|---|
| `DS_Glass` | string attribute | World glass model | Marks a pickupable glass. Value = glass type (`Glass`, `Highball`, `Lowball`, `Martini`) |
| `DS_Surface` | tag or bool attribute | BasePart | Valid drink placement surface |
| `DS_Table` | tag or bool attribute | Model or BasePart | Entire table is placeable — system auto-picks the highest part as the surface |
| `DS_Drinks` | bool attribute | Bottle model or descendant | Marks an ingredient bottle |
| `DS_IngredientName` | string attribute | Bottle model **or bare part** | Ingredient name (must match `IngredientRegistry`). Sufficient on its own — no `DS_Drinks` needed. A bare part with `DS_IngredientName = "Water"` becomes a sober-up station |
| `DS_Shaker` | bool attribute | Shaker world model | Marks a pickupable shaker |
| `DS_Garnish` | string attribute | Garnish model | Garnish name (e.g. `Lime`, `Cherry`) |

### Placing drinks on tables
Tag the table model with **`DS_Table`** via CollectionService. No need to add individual surface parts — the system finds the highest face automatically. Alternatively, tag/attribute specific parts with `DS_Surface` for manual control.

---

## Settings (`src/Shared/DrinkSystem/Config/Settings.luau`)

| Key | Default | Notes |
|---|---|---|
| `MaxIngredientsPerMix` | 4 | Max pours before glass is full |
| `MaxGlasses` | 5 | Max glasses a player can hold at once |
| `DefaultDrinkSips` | 3 | Sips per drink |
| `MaxInteractDistance` | 12 | Stud radius for pickup / placement |
| `WaterSoberAmount` | -35 | Drunkness change per direct Water drink |
| `DrunknessMax` | 100 | Drunkness ceiling |
| `DrunknessRecoveryPerSecond` | 1.1 | Natural sober-up rate (~90s from max) |
| `DrunknessVisualMax` | 70 | Visual effects hit full intensity here, not at 100 |
| `DrunkCollapseThreshold` | 0.92 | Fraction of max that triggers pass-out |
| `DrunkCollapseDuration` | 15 | Seconds knocked out |
| `DrunkCollapseCooldown` | 90 | Min seconds between collapses |
| `EnableGuidance` | true | Shows ingredient highlights to guide bartender |
| `EnableDrunkDebug` | false | Prints drunkness values to output |

---

## File Map

```
src/
  ServerScriptService/DrinkSystem/
    DrinkSystemController.luau       — Main server brain (sessions, packets, scoring, guidance loop)
    Managers/
      PickupManager.luau             — Glass/shaker/drink pickup, inventory (Settings.MaxGlasses)
      DrinkCreationManager.luau      — Finalizes glass → drink tool
      PlacementManager.luau          — Places drink on nearest DS_Surface/DS_Table (bounding-box distance)
      ConsumptionManager.luau        — Sip logic, applies drunkness (negative = sober-up)
    Services/
      DrinkEffectsService.luau       — Server drunkness accumulator, stages, collapse/stumble
      DrunkRagdollService.server.luau — BallSocket ragdoll, watches DrunkCollapsed (hooks per PLAYER, not per respawn)
      GamepassManager.luau           — Bartender gamepass gate (currently open access)

  ReplicatedStorage/DrinkSystem/
    Config/
      Recipes.luau                   — Recipe definitions
      Settings.luau                  — All tunable values
    SharedModules/
      Network.luau                   — ByteNet packet definitions
      IngredientRegistry.luau        — ~24 ingredients with Strongness + Color
      RecipeRegistry.luau            — Recipe lookup helpers
      GlassClass.luau                — OOP glass object
      GlassPresentation.luau         — Fill state, garnish, color visuals
      Utility.luau                   — averageColors, misc helpers

  StarterPlayer/StarterPlayerScripts/DrinkSystemClient/
    Core/
      ClientStateController.client.luau — Consume/place input, mobile TouchTap flow, Place/Cancel UI
    Placement/
      PlacementPreviewClient.luau    — Ghost preview (PC: cursor-follow; mobile: on-tap via showAtPosition)
    Effects/
      DrinkEffectsClient.luau        — Camera wobble, blur, DOF drunk effects (smooth ramp, no sip-kick)
      DrunkBarController.client.luau — Drunk UI bar
      DrunkMovementController.client.luau — Walk speed, stumble, sway
      DrunkRagdoll.client.luau       — Ragdoll client: CanCollide Heartbeat loop (DO NOT optimize), shuffle
    Interaction/
      HoverInteractionController.client.luau — Hover highlights, guidance, tooltip, click handler
    Presentation/
      DrinkVisualController.client.luau — Client drink visuals
      ShakerController.client.luau   — Shaker animation
```

### Security / dataflow notes
- Clients send **intents only** (pour X, place at Y, consume Z); the server owns all state
  (mix contents, drunkness, scoring, drink creation).
- Every client→server packet is rate-limited, distance-checked, and ownership-validated.
  Placement positions from the client are sanity-checked and clamped to the surface.
- Never trust a client-sent score/amount — outcomes are computed server-side (`computeOutcome`).
- The guidance loop wraps each session in `pcall` so one bad session can't kill guidance for everyone.

---

## Studio-Only Assets

These are not in source control. Export via Argon with **Only Code Mode off**, or manually export `.rbxm`:

- `ReplicatedStorage/DrinkSystem/GlassTemplates` — Tool templates per glass type
- `ReplicatedStorage/DrinkSystem/ShakerTemplates` — Shaker tool template
- `ReplicatedStorage/DrinkSystem/Animations` — Pour animation
- `StarterGui/DrunkUI` — HUD for drunkness bar

---

## Backlog

- **Drunkness UI checkpoints** — wire the drunkness value to the checkpoint-frame UI set up in Studio
- **Perf: cache tagged surfaces/bottles** — `findNearestSurface` (client, per-frame) and `collectNearestModels`
  (guidance, per 0.25s) walk `workspace:GetDescendants()`; switch to a CollectionService-tag cache.
  ⚠️ Requires tables/bottles to use real tags, not just attributes — verify Studio setup first
- **Consolidate duplicated helpers** — `isSurfacePart`/`isSurfaceHit` (4 copies) and `findGlassTool` (3 copies)
  into SharedModules

### Done (2026-07-06/07)
- Mobile placement: glow on proximity → tap surface → ghost preview at tap spot → Place/Cancel
- Mobile drinking: TouchTap owns place+drink (`Activated` gated for drink tools on mobile)
- Water sober-up: direct-consume via `DS_IngredientName = "Water"` part
- E-key ragdoll test removed (client keybind + server RemoteEvent — was an open endpoint)
- Ragdoll connections hook once per player (was stacking per respawn)
- Guidance loop pcall-protected; pending-drink cleanup wired to PlayerRemoving
