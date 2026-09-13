#!/usr/bin/env bash
# Starts the production-backed driving harness headless and fails on runtime script/load errors.
# Dependencies: Godot 4 plus the repository driving harness and production vehicle/camera scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-${BRUR_GODOT:-}}"
if [[ -z "$GODOT" ]]; then
  if command -v godot >/dev/null 2>&1; then
    GODOT="$(command -v godot)"
  elif [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
    GODOT=/Applications/Godot.app/Contents/MacOS/Godot
  else
    printf 'DRIVING_HARNESS_RUNTIME=FAIL Godot not found\n' >&2
    exit 69
  fi
fi
[[ -x "$GODOT" ]] || { printf 'DRIVING_HARNESS_RUNTIME=FAIL Godot is not executable: %s\n' "$GODOT" >&2; exit 69; }

LOG="$(mktemp "${TMPDIR:-/tmp}/brur-driving-harness.XXXXXX.log")"
trap 'rm -f "$LOG"' EXIT

set +e
timeout_cmd=()
if command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout 20s)
elif command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout 20s)
fi
"${timeout_cmd[@]}" "$GODOT" --headless --path "$ROOT" --quit-after 3 res://harness/driving/driving_harness.tscn >"$LOG" 2>&1
status=$?
set -e
cat "$LOG"

if [[ "$status" -ne 0 ]]; then
  printf 'DRIVING_HARNESS_RUNTIME=FAIL Godot exited %s\n' "$status" >&2
  exit "$status"
fi
if grep -Eq 'SCRIPT ERROR:|Invalid call\.|Failed to load script|Failed to load resource|Parse Error:' "$LOG"; then
  printf 'DRIVING_HARNESS_RUNTIME=FAIL runtime script/load error detected\n' >&2
  exit 1
fi
printf 'DRIVING_HARNESS_RUNTIME=PASS\n'
