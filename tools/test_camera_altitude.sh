#!/usr/bin/env bash
set -euo pipefail

# Runs deterministic camera altitude model and Godot adapter contracts.
# Dependencies: Godot 4 (GODOT_BIN can override the default executable lookup).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -n "${GODOT_BIN:-}" ]]; then
  GODOT="$GODOT_BIN"
elif command -v godot >/dev/null 2>&1; then
  GODOT="$(command -v godot)"
elif [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
  GODOT=/Applications/Godot.app/Contents/MacOS/Godot
else
  echo "Godot 4 executable not found. Set GODOT_BIN or install godot." >&2
  exit 2
fi

SCRIPT="tests/godot/test_camera_altitude.gd"
MARKER="godot camera-altitude tests: OK"

set +e
output="$($GODOT --headless --path "$ROOT" --script "$SCRIPT" 2>&1)"
status=$?
set -e
printf '%s\n' "$output"

if [[ $status -ne 0 ]] || grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed to load script|(^|[[:space:]])ERROR:' <<<"$output"; then
  echo "camera altitude Godot tests: FAILED ($SCRIPT)" >&2
  exit 1
fi

if ! grep -Fq "$MARKER" <<<"$output"; then
  echo "camera altitude tests did not reach success marker: $MARKER" >&2
  exit 1
fi

echo "camera altitude automated tests: OK"
