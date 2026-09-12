#!/usr/bin/env bash
# Validates the #168 production-building integration and launches the exact PR runtime for the remaining visual check.
# Dependencies: existing authoritative world_data/buildings.jsonl, derived production building tiles, Godot, and the #168 building tile builder when cache repair is needed.
set -euo pipefail

WORKTREE="${BRUR_PR_CHECK_WORKTREE:?}"
WORLD_DATA="${BRUR_PR_CHECK_WORLD_DATA:?}"
PYTHON="${PYTHON_BIN:?}"
GODOT="${GODOT_BIN:?}"

building_tiles_ready() {
  "$PYTHON" - "$WORLD_DATA/manifest.json" "$WORLD_DATA/building_tiles" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
tile_dir = Path(sys.argv[2])
try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except (OSError, ValueError):
    raise SystemExit(1)
features = manifest.get("features", {})
if features.get("building_tiles_dir") != "building_tiles":
    raise SystemExit(1)
if float(features.get("building_tile_size", 0.0)) != 2000.0:
    raise SystemExit(1)
if int(features.get("runtime_buildings_total", 0)) <= 0:
    raise SystemExit(1)
if not tile_dir.is_dir() or not next(tile_dir.glob("*.jsonl"), None):
    raise SystemExit(1)
PY
}

[[ -f "$WORLD_DATA/buildings.jsonl" ]] || {
  printf 'PR_CHECK=FAIL missing existing buildings.jsonl for production building tiles\n' >&2
  exit 66
}

if building_tiles_ready; then
  printf 'PR_CHECK=SKIP_BUILDING_TILES pr=%s reason=valid-existing-cache\n' "${BRUR_PR_CHECK_PR:?}"
else
  printf 'PR_CHECK=BUILD_BUILDING_TILES pr=%s reason=missing-or-stale-cache source=existing-buildings-jsonl\n' "${BRUR_PR_CHECK_PR:?}"
  "$PYTHON" "$WORKTREE/tools/build_building_tiles.py" "$WORLD_DATA"
  building_tiles_ready || {
    printf 'PR_CHECK=FAIL production building tile cache is invalid after rebuild\n' >&2
    exit 1
  }
fi

rm -rf "$WORKTREE/world_data"
ln -s "$WORLD_DATA" "$WORKTREE/world_data"

run_godot_test() {
  local script="$1" log status
  log="$(mktemp "${TMPDIR:-/tmp}/brur-world-test.XXXXXX.log")"
  set +e
  "$GODOT" --headless --path "$WORKTREE" --script "$script" 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  set -e
  if [[ $status -ne 0 ]] || grep -Eq 'SCRIPT ERROR:|Failed to load script|map-controls test failed:|world streaming foundation test failed:' "$log"; then
    printf 'PR_CHECK=FAIL Godot reported script/test errors for %s\n' "$script" >&2
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
}

printf 'PR_CHECK=CHECK_BUILDING_STREAM_HEADLESS pr=%s\n' "${BRUR_PR_CHECK_PR:?}"
run_godot_test res://tests/godot/test_world_streaming_foundation.gd
printf 'PR_CHECK=CHECK_MAP_CONTROLS_HEADLESS pr=%s\n' "$BRUR_PR_CHECK_PR"
run_godot_test res://tests/godot/test_map_controls.gd

printf 'PR_CHECK=VISUAL_REVIEW pr=%s revision=%s\n' "$BRUR_PR_CHECK_PR" "$(git -C "$WORKTREE" rev-parse --short=12 HEAD)"
printf 'PR_CHECK=VISUAL_REVIEW_INSTRUCTION confirm HUS starts OFF; turn HUS ON near street/city altitude and verify nearby buildings appear with acceptable playability; turn HUS OFF and verify they disappear; close Godot when finished\n'
"$GODOT" --path "$WORKTREE"
