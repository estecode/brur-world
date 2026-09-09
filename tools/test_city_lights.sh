#!/usr/bin/env bash
# Runs deterministic/headless city-light model and renderer validation.
# Dependencies: Godot 4 and tests/godot/test_city_lights.gd.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -n "${GODOT_BIN:-}" ]]; then
  GODOT="$GODOT_BIN"
elif command -v godot >/dev/null 2>&1; then
  GODOT="$(command -v godot)"
elif [[ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]]; then
  GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
else
  echo "city light tests: Godot executable not found" >&2
  exit 1
fi

set +e
output="$($GODOT --headless --path "$ROOT" --script tests/godot/test_city_lights.gd 2>&1)"
status=$?
set -e
printf '%s\n' "$output"

if [[ $status -ne 0 ]]; then
  echo "city light tests: Godot exited with status $status" >&2
  exit $status
fi
error_output="$(grep -E 'SCRIPT ERROR:|Parse Error:|Failed to load script|^ERROR:' <<<"$output" | grep -Ev '^ERROR: [0-9]+ resources still in use at exit' || true)"
if [[ -n "$error_output" ]]; then
  echo "city light tests: Godot reported an error" >&2
  exit 1
fi
if ! grep -Fq 'godot city light tests: OK' <<<"$output"; then
  echo "city light tests: success marker missing" >&2
  exit 1
fi

echo "city light automated tests: OK"
