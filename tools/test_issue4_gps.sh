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

"$GODOT_BIN" --headless --path "$ROOT" --script tests/godot/test_gps_route_model.gd

echo "issue #4 automated GPS tests: OK"
