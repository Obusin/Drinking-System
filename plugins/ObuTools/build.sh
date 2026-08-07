#!/usr/bin/env bash
# Build ObuTools straight into Studio's plugins folder.
#
# Argon's --plugin flag puts the result where Studio looks, so there is
# nothing to drag anywhere. Studio picks up the new file within a second
# or two; no restart needed.
#
#   ./build.sh          build once
#   ./build.sh watch    rebuild on every save
set -euo pipefail
cd "$(dirname "$0")"

if [ "${1:-}" = "watch" ]; then
	exec argon build --plugin --watch
fi

argon build --plugin
echo "Built. Studio will reload it automatically — look for the OBU tab on the toolbar."
