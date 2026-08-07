# ObuTools

One dockable panel instead of nine plugin buttons. Not a replacement for
F3X — a replacement for the *pile* of single-purpose plugins that sit
around it.

```bash
./build.sh          # build into Studio's plugins folder
./build.sh watch    # rebuild on every save
```

Argon drops the result straight into `~/Documents/Roblox/Plugins/`, so
there is nothing to drag anywhere. Studio reloads it within a second or
two. Look for the **OBU** toolbar tab.

## Tabs

### Build

| Tool | Inspired by | What it does |
|---|---|---|
| **Align** | F3X | Align to min/centre/max on X/Y/Z, and distribute evenly. Uses `Position`, never `CFrame`, so rotation survives. |
| **Arc** | Archimedes | Repeat one part around a curve — curved walls, roundabouts, spiral ramps. Dial for total sweep, sliders for copies/radius/rise, X/Y/Z axis picker, **live ghost**. Nothing exists until you press Build. |
| **GapFill** | GapFill | Select 3 parts for a triangle, 4 for a quad. **Previews as you pick the corners.** Two `WedgePart`s per triangle, inheriting the first part's material and colour. |
| **Brush** | Brushtool | Drag to scatter copies onto surfaces. **Ghost follows the cursor.** Spacing, scale jitter, random yaw, follow-surface-angle. One stroke is one undo. |

**Previews live under `workspace.CurrentCamera`.** That renders normally
but does not serialise — a preview cannot leak into your saved place no
matter how the plugin exits. A folder in Workspace would save, and forty
translucent cones left in a place file look exactly like real ones.

### UI

| Tool | Inspired by | What it does |
|---|---|---|
| **Scaler** | AutoScale Lite | Offset ↔ scale for Size and Position, whole tree at once. Plus aspect-ratio locks and responsive text with a size ceiling. |
| **Anchor** | UI Tools | 3×3 anchor grid with *keep it where it looks now* compensation, so nothing jumps. Centre in parent, centre on one axis. |
| **Gradients** | — | Save a `UIGradient` as a named preset and apply it anywhere. Survives closing Studio. |

### Tags

Every `CollectionService` tag in the place with its population, plus
add/remove on the selection and **Select** to grab everything carrying a
tag.

This one is not a convenience. In a tag-driven game a *missing* tag is a
feature that silently does nothing — no error, no warning, just a lap
counter that never counts. `Checkpoint ×0` on a race track tells you in
a glance what twenty minutes of driving in circles would.

## The rules every tool follows

1. **One action is one undo.** Everything goes through `Core.History`. A
   brush stroke that placed sixty rocks undoes as one step.
2. **Nothing runs behind a closed panel.** Every tab gets a context with
   `visible()`, `onShow` and `onHide`, and anything that draws into the
   viewport clears itself on the way out — for *both* reasons a panel can
   go away, since a tool doesn't get to know which one happened.
3. **No hardcoded colours.** Every colour is asked for by name from the
   Studio theme, so light mode is not a second code path. Painters bind
   to the instance they paint with a **weak key**, so panels that rebuild
   don't leak them.
4. **It says what it did, in one place.** The status bar at the bottom is
   per-tab, so a background panel can't overwrite what the one you're
   looking at just told you. *"12 converted to scale, 3 skipped"* is a
   diagnostic; silence is not.
5. **Refuse rather than guess.** Degenerate input stops with a message.
   Three points in a line have no plane, and the resulting NaN `CFrame`
   produces a part you cannot see, select or delete.

## How it looks, and why

- **One grid.** Every gap, pad and height is a multiple of 4. Nothing is
  nudged by an odd pixel to make one panel look right — that's how a UI
  ends up feeling assembled rather than designed.
- **Three button weights, only three.** Primary is the thing you came
  here to do, and there is at most one per panel. Normal is everything
  else. Quiet is for clearing and cancelling. If every button is loud
  then none of them are.
- **Colour means something.** Accent is *active* or *primary* and nothing
  else; green and amber appear only in the status bar. A UI where colour
  is decoration can't use colour to tell you anything.
- **Toggles are switches, not lit rectangles.** A rectangle that changes
  colour is indistinguishable from a button you just pressed.
- **Tabs underline, they don't fill.** A filled tab competes with the
  primary button for "the loud thing on screen".
- **Sections collapse and remember.** Stored per section, so your layout
  survives closing Studio — otherwise you re-collapse the same six every
  launch and stop bothering.
- **The header shows the selection count.** Every tool here reads the
  selection, and "nothing happened" is nearly always "nothing was
  selected" — better answered before you press the button than after.

## Layout

```
src/
  init.server.luau     toolbar, widget, tab wiring
  Core/
    Theme.luau         Studio's palette, live on theme change
    Ui.luau            sections, rows, buttons, toggles, number fields
    History.luau       undo grouping — run() for actions, open/close for strokes
    Store.luau         plugin settings (gradients live here)
    Sel.luau           selection filtered to what a tool can act on
    Widget.luau        dock widget + tabs
  Tools/
    Align, Arc, GapFill, Brush, Scaler, Anchor, Gradients, Tags
```

Adding a tool is one file exporting `build(page)` plus one line in
`init.server.luau`.

## Not in here

Move/resize/rotate handles, material and surface painting, terrain,
welding. F3X already does all of that better than a from-scratch version
would, and the point of this was the gaps between the good plugins, not
a worse copy of one.
