#!/usr/bin/env bash
set -euo pipefail

# Runs deterministic persistent-overlay structure, layout, collapse/restore, Lund-control, and debug-log contracts.
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

run_test() {
  local script="$1"
  local marker="$2"

  set +e
  local output
  output="$($GODOT --headless --path "$ROOT" --script "$script" 2>&1)"
  local status=$?
  set -e
  printf '%s\n' "$output"

  local error_output
  error_output="$(grep -E 'SCRIPT ERROR:|Parse Error:|Failed to load script|(^|[[:space:]])ERROR:' <<<"$output" | grep -Ev '^ERROR: [0-9]+ resources still in use at exit' || true)"
  if [[ $status -ne 0 ]] || [[ -n "$error_output" ]]; then
    echo "UI overlay Godot tests: FAILED ($script)" >&2
    exit 1
  fi

  if ! grep -Fq "$marker" <<<"$output"; then
    echo "UI overlay tests did not reach success marker: $marker" >&2
    exit 1
  fi
}

run_test "tests/godot/test_ui_overlays.gd" "godot UI overlay tests: OK"
run_test "tests/godot/test_lund_layout.gd" "godot Lund layout tests: OK"
run_test "tests/godot/test_debug_overlay_perf_log.gd" "godot debug overlay performance log tests: OK"

echo "UI overlay automated tests: OK"
