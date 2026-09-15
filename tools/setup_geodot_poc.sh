#!/usr/bin/env bash
# Makes a preinstalled GeoDot addon available to the isolated POC without building third-party code.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$ROOT/addons/geodot"
EXTERNAL="${BRUR_GEODOT_ADDON:-$HOME/.local/share/brur/geodot}"

verify_external_addon() {
  local addon="$1"
  [[ -f "$addon/geodot.gdextension" ]] || {
    printf 'GEODOT_SETUP=FAIL preinstalled GeoDot missing at %s; set BRUR_GEODOT_ADDON to the installed addon directory\n' "$addon" >&2
    return 69
  }
  if [[ "$(uname -s)" == "Darwin" && -f "$addon/macos/libgeodot.dylib" ]] && command -v otool >/dev/null 2>&1; then
    local dependency dependency_name
    dependency="$(otool -L "$addon/macos/libgeodot.dylib" | awk '/@loader_path\/libgdal\./ {print $1; exit}')"
    if [[ -n "$dependency" ]]; then
      dependency_name="${dependency#@loader_path/}"
      [[ -f "$addon/macos/$dependency_name" ]] || {
        printf 'GEODOT_SETUP=FAIL incomplete external GeoDot bundle: missing %s beside libgeodot.dylib\n' "$dependency_name" >&2
        return 69
      }
    fi
  fi
}

if [[ -f "$TARGET/geodot.gdextension" && ! -L "$TARGET" ]]; then
  printf 'GEODOT_SETUP=READY target=%s\n' "$TARGET"
  exit 0
fi

verify_external_addon "$EXTERNAL"
mkdir -p "$ROOT/addons"
rm -f "$TARGET"
ln -s "$EXTERNAL" "$TARGET"
printf 'GEODOT_SETUP=EXTERNAL source=%s target=%s\n' "$EXTERNAL" "$TARGET"
