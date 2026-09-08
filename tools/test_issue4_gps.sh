#!/usr/bin/env bash
set -euo pipefail

# Runs the issue #4 GPS correctness contracts plus native-core and Godot adapter regression coverage.
# Dependencies: Python 3, a C++20 compiler, and Godot (GODOT_BIN can override macOS default).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"

if [[ -x "$ROOT/.venv/bin/python" ]]; then
  PYTHON_BIN="$ROOT/.venv/bin/python"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python)"
else
  echo "Python 3 not found. Expected .venv/bin/python, python3, or python." >&2
  exit 2
fi

cd "$ROOT"

"$PYTHON_BIN" -m unittest \
  tests.test_gps_routing \
  tests.test_gps_search \
  tests.test_search_postcode_enrichment \
  tests.test_routing_graph_view \
  tests.test_gps_snap_index \
  tests.test_gps_astar \
  tests.test_gps_bidirectional \
  tests.test_gps_ch \
  tests.test_gps_bch \
  tests.test_routing_runtime_contract \
  tests.test_native_route_plan \
  tests.test_native_gps_core \
  tests.test_native_search_index

bash tools/build_native_gps.sh

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "Godot not found at: $GODOT_BIN" >&2
  echo "Set GODOT_BIN to a Godot 4 executable." >&2
  exit 2
fi

run_godot_contract() {
  local script="$1"
  local marker="$2"
  local output
  local status

  set +e
  output="$($GODOT_BIN --headless --path "$ROOT" --script "$script" 2>&1)"
  status=$?
  set -e
  printf '%s\n' "$output"

  if [[ $status -ne 0 ]] || grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed to load script' <<<"$output"; then
    echo "issue #4 Godot GPS tests: FAILED ($script)" >&2
    exit 1
  fi

  if ! grep -Fq "$marker" <<<"$output"; then
    echo "issue #4 Godot GPS tests did not reach success marker: $marker" >&2
    exit 1
  fi
}

run_godot_contract tests/godot/test_world_coordinates.gd "godot world-coordinate tests: OK"
run_godot_contract tests/godot/test_gps_route_model.gd "godot gps route-model tests: OK"
run_godot_contract tests/godot/test_gps_adapter_split.gd "godot gps adapter-split tests: OK"
run_godot_contract tests/godot/test_gps_harness_scene.gd "godot gps harness-scene tests: OK"
run_godot_contract tests/godot/test_gps_search_index.gd "godot gps search-index tests: OK"
run_godot_contract tests/godot/test_gps_search_route_adapter.gd "godot gps search-route adapter tests: OK"
run_godot_contract tests/godot/test_gps_search_native_adapter.gd "godot gps native-search adapter tests: OK"
run_godot_contract tests/godot/test_gps_failure_metrics.gd "godot gps failure-metrics tests: OK"

echo "issue #4 automated GPS tests: OK"
