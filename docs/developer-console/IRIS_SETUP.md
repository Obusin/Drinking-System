# Iris setup

## Installation method: **vendored source**

The project has **no dependency manager**. Checked and absent:

| convention | present? |
|---|---|
| Wally (`wally.toml`) | no |
| Rokit / Aftman / Foreman | no |
| Git submodules (`.gitmodules`) | no |
| Rojo/Argon package mapping | no package section |

`.gitignore` *anticipates* Wally (`/Packages`, `/ServerPackages`,
`/DevPackages` are ignored at the repo root) but no manifest exists, and
the one existing third-party dependency — **ProfileStore** — is vendored
as a committed file at `src/ServerScriptService/Packages/ProfileStore.luau`.

**So the existing convention is vendoring under `src/**/Packages/`, and
Iris follows it.** Note the ignore rules are root-relative (`/Packages`),
so they do not affect `src/.../Packages` — the vendored files commit
normally.

## What was installed

| | |
|---|---|
| Source | https://github.com/SirMallard/Iris |
| Version | **2.5.1** |
| Commit | `d40343b03726ad75f684e9d3449a4525df3f6dac` (2026-07-15) |
| License | MIT (`LICENSE.txt` retained alongside the source) |
| Files | 25 (24 source + licence), ~604 KB |

Only the library's `lib/` directory was taken — the upstream repo's
`demo.project.json`, `dev.project.json`, `docs/` and `assets/` are build
and documentation scaffolding for Iris itself and are not needed here.

## Path

```
src/ReplicatedStorage/Packages/Iris/     ->  ReplicatedStorage.Packages.Iris
```

The project's Rojo/Argon tree maps `src/ReplicatedStorage` straight to
`ReplicatedStorage`, so no mapping change was required.

```lua
local Iris = require(game.ReplicatedStorage.Packages.Iris)
```

## Not done, deliberately

- **No runtime installation.** Iris is committed source; nothing is
  fetched over HTTP while the game runs.
- **No Toolbox asset.** Nothing depends on an uncommitted model.
- **No Iris internals modified.** The vendored tree is byte-identical to
  upstream `lib/`, so it can be replaced wholesale on upgrade.

## Upgrading

```bash
git clone --depth 1 https://github.com/SirMallard/Iris.git /tmp/iris
rm -rf src/ReplicatedStorage/Packages/Iris
cp -R /tmp/iris/lib src/ReplicatedStorage/Packages/Iris
cp /tmp/iris/LICENSE.txt src/ReplicatedStorage/Packages/Iris/
./scripts/check.sh
```

Then update the version and commit hash in this file. Because no console
code lives inside the package directory, a replacement cannot clobber
project-owned code — that separation is the reason for the split.

## Type checking

`scripts/check.sh` excludes `*/Packages/*` and only globs `*.luau`; Iris
ships `.lua`, so it is doubly excluded. Iris warnings are not this
project's to fix, matching the existing stance on ProfileStore.
