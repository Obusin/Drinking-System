# DrinkSystem Codebase Map

## What This Repo Currently Implements

The code that is actually implemented in this checkout is centered on a bartender / drink-mixing game loop.

The `Sky Catcher` design doc in `docs/Sky_Gameplay_Design.md` reads like a future or alternate game design, not the main implemented runtime in source right now.

The current source-of-truth gameplay system is:

- `src/ServerScriptService/DrinkSystem/*`
- `src/ReplicatedStorage/DrinkSystem/*`
- `src/StarterPlayer/StarterPlayerScripts/DrinkSystemClient/*`

Current hierarchy organization:

- `ServerScriptService/DrinkSystem`
  - root:
    - `DrinkSystemController.luau`
    - `DrinkSystemServerMain.server.luau`
  - `Managers/`
  - `Services/`
- `StarterPlayerScripts/DrinkSystemClient`
  - `Core/`
  - `Effects/`
  - `Interaction/`
  - `Presentation/`

## High-Level Runtime Flow

```text
START
  ->
Player approaches interactable object
  ->
Client hover controller detects:
  Glass / Bottle / Shaker / Finished Drink
  ->
Client sends ByteNet request packet
  ->
Server DrinkSystemController validates:
  cooldown
  distance
  ownership / tool state
  recipe / session state
  ->
If pickup:
  give glass or shaker tool
  ->
If pour:
  resolve ingredient from bottle tags / attributes
  update mix state
  update guidance
  ->
If mix is complete:
  finalize immediately
  OR start shaker flow
  ->
DrinkCreationManager stamps drink attributes onto glass tool
  ->
Player can:
  consume drink
  or place drink on a tagged table surface
  ->
If consumed:
  server applies drunkness
  client applies camera / lighting FX
  ->
END / make another drink
```

## Main Server Authority

### `src/ServerScriptService/DrinkSystem/DrinkSystemController.luau`

This is the central state machine.

It owns:

- per-player drink sessions
- per-glass mix state
- interaction rate limiting
- distance validation
- ingredient tracking
- recipe selection
- suggested recipes / guidance
- recipe completion detection
- shaker sequencing
- outcome + score calculation
- packet wiring

Important behavior:

- one ingredient with no selected recipe becomes a straight drink
- exact recipe ingredient match can auto-finalize
- overfilling beyond max ingredients can produce `Toxication`
- the server recomputes guidance continuously and sends it to the client

## Supporting Server Modules

### `Managers/DrinkCreationManager.luau`

Responsible for converting a glass tool into a drink tool by stamping attributes like:

- `DS_Drink`
- `DS_DrinkName`
- `DS_Strongness`
- `DS_RecipeName`
- `DS_BaseIngredient`
- `DS_SipsMax`
- `DS_SipsRemaining`
- `DS_Outcome`
- `DS_Score`

Also stores pending drinks while shaker animation is running.

### `Managers/PickupManager.luau`

Responsible for:

- picking up glass models into tools
- picking up shaker models into tools
- picking up finished world drinks back into tools
- keeping a per-player multi-glass inventory

Notable behavior:

- glass world models stay on the table when picked up
- finished drink world models are destroyed when picked up

### `Managers/PlacementManager.luau`

Responsible for placing finished drinks back into the world.

Placement depends on tagged / attributed surfaces:

- `DS_Surface`
- `DS__Surface`

It looks for open `Attachment` slots first, then falls back to nearest valid placement on the surface.

### `Managers/ConsumptionManager.luau`

Responsible for:

- validating drink ownership
- validating that the tool is a drink
- splitting strongness across sip count
- consuming one sip at a time
- destroying the tool when empty

### `Services/DrinkEffectsService.luau`

Server-authoritative drunkness manager.

It creates / updates a `NumberValue` named `Drunkness` under the player and replicates that value to clients.

Current config defaults mean drunkness does **not** decay over time unless changed in settings.

### `Services/GamepassManager.luau`

Simple cached `UserOwnsGamePassAsync` wrapper for bartender access checks.

## Shared Replicated Modules

### `src/ReplicatedStorage/DrinkSystem/SharedModules/Network.luau`

Defines the ByteNet namespace and packet contract for the entire drink system.

Main packets:

- `RequestPickupItem`
- `RequestPourIngredient`
- `RequestFinalizeMix`
- `RequestSelectRecipe`
- `ShakerFinished`
- `PlaceDrink`
- `ConsumeDrink`
- `StartBottlePour`
- `StartShakerSequence`
- `MissingShakerNotify`
- `GuidanceUpdate`
- `DrinkOutcome`

This is the shared protocol between client and server.

### `IngredientRegistry.luau`

Maps bottle / ingredient names to:

- `Strongness`
- `Color`

These names must match `DS_IngredientName` used on world bottle objects.

### `RecipeRegistry.luau`

Recipe matching is currently based on unordered ingredient set equality.

It also supports partial compatibility lookups to generate "next ingredient" suggestions.

### `Utility.luau`

Currently mostly used for averaging colors across ingredients.

### `GlassClass.luau`

Per-glass helper that animates the `DrinkPart` fill level and blended color.

This is more visual / object-oriented support than core authority.

## Client Controllers

### `Interaction/HoverInteractionController.client.luau`

Main interaction frontend.

It handles:

- hover detection
- interactable type detection
- recommended / required target highlighting
- pickup requests
- pour requests
- finalize requests
- recipe select / clear requests

This is the main local "player interaction" layer.

### `Core/ClientStateController.client.luau`

Handles:

- tool consume hook-up
- local consume animation and sound
- `PlaceDrink` hotkey
- sending consume requests to the server

### `Effects/DrinkEffectsClient.luau`

Reads replicated `player.Drunkness` and applies visual effects:

- camera wobble
- camera roll
- blur
- color correction
- depth of field

This is client presentation only. The drunkness number itself comes from the server.

### `Presentation/DrinkVisualController.client.luau`

Handles pouring visuals:

- bottle hand clone
- pour animation
- pour particles
- fill color / fill level visuals

### `Presentation/ShakerController.client.luau`

Handles shaker animation flow after the server tells the client to start it.

When the animation finishes, it sends `ShakerFinished` back to the server.

### `Effects/DrunkBarController.client.luau`

Intended to drive the drunkness UI bar.

Current behavior:

- it now reads the real replicated drunk state
- it is mainly a debug / tuning UI for current intoxication testing

## Config and Content Shape

### `src/ReplicatedStorage/DrinkSystem/Config/Settings.luau`

Main knobs include:

- `MaxIngredientsPerMix`
- `GlassToolNames`
- `ShakerToolName`
- `MaxInteractDistance`
- `ActionCooldown`
- `GuidanceUpdateInterval`
- `MaxDrinkTime`
- `PlaceKey`
- `DrunknessMax`
- `DrunknessRecoveryPerSecond`
- client controller enable flags

### `src/ReplicatedStorage/DrinkSystem/Config/Recipes.luau`

Recipes define:

- `DisplayName`
- `Ingredients`
- `OutputColor`
- `RequireShaker`
- `StrongnessOverride`
- `Steps`

Recipes currently configured in source:

- `Blue Screen`
  - ingredients: `Vodqa` + `Coolnag` + `Soda Water`
  - shaker required: `no`
  - garnish: `Lime`
- `Debt Collector`
  - ingredients: `JacklineDale` + `Maple Syrup` + `Creamora`
  - shaker required: `yes`
  - garnish: `Orange`
- `Heatstroke`
  - ingredients: `Biljin` + `Tropica` + `Sugar`
  - shaker required: `no`
  - garnish: `Orange`
- `Dealer's Choice`
  - ingredients: `Almendra` + `Chocoluxe` + `Creamora`
  - shaker required: `yes`
  - garnish: `Cherry`

## Current Craftable Drinks

If you want the "what can players actually make right now?" answer from the current code/config, it is:

### Recipe drinks

- `Blue Screen` = `Vodqa` + `Coolnag` + `Soda Water`
- `Debt Collector` = `JacklineDale` + `Maple Syrup` + `Creamora` + shaker
- `Heatstroke` = `Biljin` + `Tropica` + `Sugar`
- `Dealer's Choice` = `Almendra` + `Chocoluxe` + `Creamora` + shaker

### Non-recipe outputs that still work

- any single ingredient poured into an empty glass with no selected recipe becomes a straight drink
  - examples: `Vodqa`, `JacklineDale`, `Biljin`, `Almendra`, etc.
- custom multi-ingredient mixes can still be finalized even if they do not match a recipe
- if the mix exceeds `MaxIngredientsPerMix`, the controller can output `Toxication`

### Bottle / ingredient names currently referenced by recipes

- `Vodqa`
- `Coolnag`
- `Soda Water`
- `JacklineDale`
- `Maple Syrup`
- `Creamora`
- `Biljin`
- `Tropica`
- `Sugar`
- `Almendra`
- `Chocoluxe`

### Registered ingredients not currently used by any recipe

- `Absmith`
- `Barcandy`
- `Bukonelle`
- `Double Time`
- `Fonador`
- `Nguermo`
- `Vermix`
- `Caffemo`
- `Calliamo`
- `Cochoco`
- `Water`
- `Beer Tap`
- `Beer Can`
- `Sgm Jinn`
- `Mintverde`

Important implementation note:

- `RecipeRegistry` matches recipes by unordered ingredient set equality
- `DrinkSystemController` also uses `Steps` and `RequireShaker` for guidance, sequencing, and scoring
- so bottle hookup should primarily match the exact strings in `DS_IngredientName`

## Required Tags / Attributes

The system is strongly attribute/tag driven.

Important attributes / tags include:

- `DS_Glass`
- `DS__Glass`
- `DS_Shaker`
- `DS__Shaker`
- `DS_Drinks`
- `DS_IngredientName`
- `DS_Drink`
- `DS_DrinkTool`
- `DS_GlassTool`
- `DS_ShakerTool`
- `DS_Strongness`
- `DS_DrinkName`
- `DS_BaseIngredient`
- `DS_Surface`
- `DS__Surface`

If world assets are missing these, the system will not behave correctly.

## Important Missing / Studio-Only Dependencies

The code expects non-code content that is not fully represented in source here.

Expected runtime assets include:

- `ReplicatedStorage/DrinkSystem/GlassTemplates`
- `ReplicatedStorage/DrinkSystem/ShakerTemplates`
- `ReplicatedStorage/DrinkSystem/Animations`
- `StarterGui/DrunkUI`
- world bottles with `DS_IngredientName`
- world glasses / shakers with the expected attributes
- table or bar surfaces tagged / attributed as `DS_Surface`

So the code is only part of the system. Some required content appears to live in Studio objects or is missing from source.

## Current Architectural Summary

Think about the current game as three layers:

### 1. Server authority layer

Owned by `DrinkSystemController` and the server managers.

This layer decides:

- what the player is allowed to do
- what ingredients were actually mixed
- whether a recipe was completed
- what drink was produced
- what score / outcome it gets
- how much drunkness is applied

### 2. Shared protocol layer

Owned by ByteNet + `Network.luau`.

This layer defines:

- request packets from client to server
- visual / guidance packets from server to client

### 3. Client presentation layer

Owned by the client controllers.

This layer handles:

- hover and input
- animations
- local sound
- local visual fill
- camera wobble / blur / color effects
- drunk bar UI

## Bottom Line

The codebase currently reads as:

**server-authoritative drink state machine + ByteNet packet contract + client-side bartender presentation stack**

The `DrinkSystem` is the clearest and most complete gameplay subsystem in this checkout.

The broader repo still contains other systems and docs, but if re-orienting quickly later, this is the implemented gameplay loop to start from.
