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

run_godot_test() {
  local script="$1"
  local marker="$2"
  set +e
  local output
  output="$($GODOT --headless --path "$ROOT" --script "$script" 2>&1)"
  local status=$?
  set -e
  printf '%s\n' "$output"

  if [[ $status -ne 0 ]]; then
    echo "sun tests: Godot exited with status $status for $script" >&2
    exit $status
  fi
  if grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed to load script|^ERROR:' <<<"$output"; then
    echo "sun tests: Godot reported an error for $script" >&2
    exit 1
  fi
  if ! grep -Fq "$marker" <<<"$output"; then
    echo "sun tests: success marker missing for $script" >&2
    exit 1
  fi
}

run_godot_test tests/godot/test_sun_position.gd 'godot astronomical sun tests: OK'
run_godot_test tests/godot/test_sun_runtime_integration.gd 'godot sun runtime integration tests: OK'

echo "sun automated tests: OK"
