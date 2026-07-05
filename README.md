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
| Still Water | Water | No | — | -30 (sobers up) |

Strength is total drunkness added across all 3 sips. Drunkness max is 100.

---

## Drunkness Stages

| Stage | Threshold | Effect |
|---|---|---|
| Sober | 0–29 | Normal |
| Buzzed | 30+ | Slight walk speed reduction |
| Drunk | 60+ | Noticeable slowdown, screen starts wobbling |
| Wasted | 80+ | Heavy slowdown, stumbling/tripping ragdoll |
| Collapsed | 95+ | Full pass-out ragdoll, can't move for ~4s |

**Recovery:** 0.3 drunkness/second naturally (~5.5 min to fully sober). Planned: Water drink to sober up faster.

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
| `DS_IngredientName` | string attribute | Bottle model | Ingredient name (must match `IngredientRegistry`) |
| `DS_Shaker` | bool attribute | Shaker world model | Marks a pickupable shaker |
| `DS_Garnish` | string attribute | Garnish model | Garnish name (e.g. `Lime`, `Cherry`) |

### Placing drinks on tables
Tag the table model with **`DS_Table`** via CollectionService. No need to add individual surface parts — the system finds the highest face automatically. Alternatively, tag/attribute specific parts with `DS_Surface` for manual control.

---

## Settings (`src/Shared/DrinkSystem/Config/Settings.luau`)

| Key | Default | Notes |
|---|---|---|
| `MaxIngredientsPerMix` | 4 | Max pours before glass is full |
| `DefaultDrinkSips` | 3 | Sips per drink |
| `MaxInteractDistance` | 12 | Stud radius for pickup / placement |
| `PlaceKey` | *(unused)* | Placement is now click-on-table |
| `DrunknessMax` | 100 | Drunkness ceiling |
| `DrunknessRecoveryPerSecond` | 0.3 | Natural sober-up rate |
| `DrunkCollapseThreshold` | 0.95 | Fraction of max that triggers pass-out |
| `EnableGuidance` | true | Shows ingredient highlights to guide bartender |
| `EnableDrunkDebug` | false | Prints drunkness values to output |

---

## File Map

```
src/
  Server/DrinkSystem/
    DrinkSystemController.luau       — Main server brain (sessions, packets, scoring, guidance)
    DrinkSystemServerMain.server.luau — Entry point
    Managers/
      PickupManager.luau             — Glass/shaker/drink pickup, inventory (max 5 glasses)
      DrinkCreationManager.luau      — Finalizes glass → drink tool
      PlacementManager.luau          — Places drink on nearest DS_Surface or DS_Table
      ConsumptionManager.luau        — Sip logic, applies drunkness
    Services/
      DrinkEffectsService.luau       — Server drunkness accumulator, stage, ragdoll trigger
      RagdollService.luau            — Motor6D/BallSocket ragdoll system
      GamepassManager.luau           — Bartender gamepass gate (currently open access)

  Shared/DrinkSystem/
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
    Effects/
      DrinkEffectsClient.luau        — Camera wobble, blur, DOF drunk effects
      DrunkBarController.client.luau — Drunk UI bar
      DrunkMovementController.client.luau — Walk speed, stumble, sway
    Interaction/
      HoverInteractionController.client.luau — Hover highlights, tooltip, click handler
    Presentation/
      DrinkVisualController.client.luau — Client drink visuals
      ShakerController.client.luau   — Shaker animation
```

---

## Studio-Only Assets

These are not in source control. Export via Argon with **Only Code Mode off**, or manually export `.rbxm`:

- `ReplicatedStorage/DrinkSystem/GlassTemplates` — Tool templates per glass type
- `ReplicatedStorage/DrinkSystem/ShakerTemplates` — Shaker tool template
- `ReplicatedStorage/DrinkSystem/Animations` — Pour animation
- `StarterGui/DrunkUI` — HUD for drunkness bar

---

## Backlog

- **TASK-1 (partial):** Mobile placement — ghost shows forward-projected position but tapping a table to confirm needs a `TouchTap` handler in `ClientStateController.client.luau` (currently only PC click is wired)
- **TASK-2:** Water drink — architecture supports negative strongness (`StrongnessOverride = -30`), just needs a world asset and recipe entry
