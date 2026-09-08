#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -n "${GODOT_BIN:-}" ]]; then
  GODOT="$GODOT_BIN"
elif command -v godot >/dev/null 2>&1; then
  GODOT="$(command -v godot)"
elif [[ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]]; then
  GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
else
  echo "sun tests: Godot executable not found" >&2
  exit 1
fi

set +e
OUTPUT="$($GODOT --headless --path "$ROOT" --script tests/godot/test_sun_position.gd 2>&1)"
STATUS=$?
set -e
printf '%s\n' "$OUTPUT"

if [[ $STATUS -ne 0 ]]; then
  echo "sun tests: Godot exited with status $STATUS" >&2
  exit $STATUS
fi

if grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed to load script|^ERROR:' <<<"$OUTPUT"; then
  echo "sun tests: Godot reported an error" >&2
  exit 1
fi

if ! grep -Fq 'godot astronomical sun tests: OK' <<<"$OUTPUT"; then
  echo "sun tests: success marker missing" >&2
  exit 1
fi

echo "sun automated tests: OK"
