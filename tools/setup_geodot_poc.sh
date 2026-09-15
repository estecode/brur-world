#!/usr/bin/env bash
# Makes a preinstalled GeoDot addon available to the isolated POC without building third-party code.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$ROOT/addons/geodot"
EXTERNAL="${BRUR_GEODOT_ADDON:-$HOME/.local/share/brur/geodot}"

if [[ -f "$TARGET/geodot.gdextension" ]]; then
  printf 'GEODOT_SETUP=READY target=%s\n' "$TARGET"
  exit 0
fi

[[ -f "$EXTERNAL/geodot.gdextension" ]] || {
  printf 'GEODOT_SETUP=FAIL preinstalled GeoDot missing at %s; set BRUR_GEODOT_ADDON to the installed addon directory\n' "$EXTERNAL" >&2
  exit 69
}

mkdir -p "$ROOT/addons"
ln -s "$EXTERNAL" "$TARGET"
printf 'GEODOT_SETUP=EXTERNAL source=%s target=%s\n' "$EXTERNAL" "$TARGET"
