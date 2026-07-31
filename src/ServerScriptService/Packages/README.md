# Packages — vendored server-side dependencies

Third-party modules live here, **not** in `KartServer/`. That folder is
code we wrote and maintain; this folder is code we accepted as-is and
should never edit. Keeping them apart means a diff on `KartServer/` is
always our own work, and updating a dependency is a folder swap rather
than an archaeology exercise.

Server-only on purpose: nothing here should ever be reachable from a
client, and `ServerScriptService` is the guarantee rather than a
convention.

## Expected contents

- `ProfileStore/` (or `ProfileStore.luau` if it ships as one file) —
  session-locked player profiles. See the vault note
  "BloxKart Data Security and Drops", Part 1, for why this and not a
  hand-rolled DataStore layer.

## Sandboxing

**Anything inserted from the toolbox or Creator Store arrives with
`Sandboxed = true`.** A sandboxed ModuleScript cannot be started without
the `RunServerScript` capability, so requiring it throws — and the throw
propagates through every require above it. ProfileStore did exactly this
and took the whole server script down with it.

Vendored code here is trusted by the act of vendoring it. Set
`Sandboxed = false` in the module's `.meta.json`, and check that first
when a newly added package will not load.

## Rules

**A dependency that lives only in Studio is not a dependency, it is a
liability.** Argon serves `src/ServerScriptService`, so a Studio-side
child with no counterpart on disk can be removed by the next full sync —
and this project has already lost its entire source tree to a Studio
sync once. Anything required to boot the game belongs on disk and in
git.

**Excluded from `scripts/check.sh`.** ProfileStore raises a handful of
generic type-inference complaints that are harmless and not ours to fix,
and letting them into the output trains everyone to ignore it — a check
nobody reads is worse than no check.

**Do not edit vendored code.** If something needs changing, wrap it in
`KartServer/` instead. A local patch here is invisible at update time
and will be silently reverted.
