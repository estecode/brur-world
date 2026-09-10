#!/usr/bin/env bash
# Runs production-composition city-light validation against the local authoritative Sweden runtime dataset.
# Dependencies: Godot 4, ignored world_data/manifest.json + background.brmap, tests/godot/test_city_lights_real_data.gd.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ -f "$ROOT/world_data/manifest.json" ]] || { echo "city light real-data tests: missing world_data/manifest.json" >&2; exit 66; }
[[ -f "$ROOT/world_data/background.brmap" ]] || { echo "city light real-data tests: missing world_data/background.brmap" >&2; exit 66; }

if [[ -n "${GODOT_BIN:-}" ]]; then
  GODOT="$GODOT_BIN"
elif command -v godot >/dev/null 2>&1; then
  GODOT="$(command -v godot)"
elif [[ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]]; then
  GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
else
  echo "city light real-data tests: Godot executable not found" >&2
  exit 69
fi

set +e
output="$($GODOT --headless --path "$ROOT" --script tests/godot/test_city_lights_real_data.gd 2>&1)"
status=$?
set -e
printf '%s\n' "$output"

if [[ $status -ne 0 ]]; then
  echo "city light real-data tests: Godot exited with status $status" >&2
  exit $status
fi
error_output="$(grep -E 'SCRIPT ERROR:|Parse Error:|Failed to load script|^ERROR:' <<<"$output" | grep -Ev '^ERROR: [0-9]+ resources still in use at exit' || true)"
if [[ -n "$error_output" ]]; then
  echo "city light real-data tests: Godot reported an error" >&2
  exit 1
fi
if ! grep -Fq 'godot city light real-data tests: OK' <<<"$output"; then
  echo "city light real-data tests: success marker missing" >&2
  exit 1
fi

echo "city light real-data automated tests: OK"
