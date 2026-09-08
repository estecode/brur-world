#!/usr/bin/env bash
set -euo pipefail

# Runs the issue #4 correctness contracts that do not require manual gameplay input.
# Dependencies: Python 3, a C++20 compiler, and Godot (GODOT_BIN can override macOS default).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"

cd "$ROOT"

python -m unittest \
  tests.test_gps_routing \
  tests.test_gps_search \
  tests.test_routing_graph_view \
  tests.test_gps_snap_index \
  tests.test_gps_astar \
  tests.test_gps_bidirectional \
  tests.test_gps_ch \
  tests.test_gps_bch \
  tests.test_routing_runtime_contract \
  tests.test_native_route_plan

bash tools/build_native_gps.sh

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "Godot not found at: $GODOT_BIN" >&2
  echo "Set GODOT_BIN to a Godot 4 executable." >&2
  exit 2
fi

set +e
GODOT_OUTPUT="$($GODOT_BIN --headless --path "$ROOT" --script tests/godot/test_gps_route_model.gd 2>&1)"
GODOT_STATUS=$?
set -e
printf '%s\n' "$GODOT_OUTPUT"

if [[ $GODOT_STATUS -ne 0 ]] || grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed to load script' <<<"$GODOT_OUTPUT"; then
  echo "issue #4 Godot GPS tests: FAILED" >&2
  exit 1
fi

if ! grep -Fq 'godot gps route-model tests: OK' <<<"$GODOT_OUTPUT"; then
  echo "issue #4 Godot GPS tests did not reach the success marker" >&2
  exit 1
fi

echo "issue #4 automated GPS tests: OK"
