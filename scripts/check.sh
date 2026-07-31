#!/usr/bin/env bash
# Type-check everything we wrote. Run from the repo root.
#
# TWO EXCLUSIONS, both deliberate:
#
#   Packages/   vendored third-party code. It is not ours to fix, and
#               editing it is invisible at update time and silently
#               reverted. ProfileStore raises a handful of generic
#               inference complaints that are harmless and not our
#               business.
#
#   Unknown *   the Roblox type definitions are not loaded here, so
#               every Instance, service and global is "unknown". That is
#               the checker missing context, not the code being wrong.
#
# WHAT THIS DOES NOT CATCH: a call to a method that does not exist.
# luau-analyze cannot see through the module boundary without those type
# definitions, so after any change to a module's shape, grep the call
# sites. That gap has cost this project a session more than once.
set -uo pipefail

cd "$(dirname "$0")/.."

out=$(luau-analyze --mode=nonstrict $(find src -name '*.luau' -not -path '*/Packages/*') 2>&1 \
  | grep -vE "Unknown global|Unknown require|Unknown type|Unknown symbol")

if [ -z "$out" ]; then
  echo "ALL CLEAN"
  exit 0
fi

echo "$out"
# The inference-budget warning is a soft limit, not a defect. It fails
# nothing; it means one module has grown past what Luau will analyse in
# full. MatchService is currently over it and wants splitting.
if echo "$out" | grep -qv "inference failed"; then
  exit 1
fi
exit 0
