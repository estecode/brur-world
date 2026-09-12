#!/usr/bin/env bash
# Prepares and objectively validates current PR-owned real-data integration checks, then opens the exact rebuilt PR runtime for visual review.
# Dependencies: existing local world_data, Sweden PBF, city-light density tooling, world showcase preparation, and Godot supplied by PR check.
set -euo pipefail

WORKTREE="${BRUR_PR_CHECK_WORKTREE:?}"
WORLD_DATA="${BRUR_PR_CHECK_WORLD_DATA:?}"
PYTHON="${PYTHON_BIN:?}"
GODOT="${GODOT_BIN:?}"
CACHE="$WORKTREE/.poc_runtime/world_showcase"
RUNTIME_WORLD_DATA="$WORKTREE/.poc_runtime/pr_check_world_data"

resolve_sweden_pbf() {
  if [[ -n "${BRUR_WORLD_PBF:-}" ]]; then
    [[ -f "$BRUR_WORLD_PBF" ]] || { printf 'PR_CHECK=FAIL BRUR_WORLD_PBF does not exist\n' >&2; return 1; }
    printf '%s\n' "$BRUR_WORLD_PBF"
    return 0
  fi

  local repo_parent candidate
  repo_parent="$(cd "$(dirname "$WORLD_DATA")/.." && pwd)"
  candidate="$(find "$repo_parent/syndicate/data" "$repo_parent/data" -maxdepth 1 -type f -name 'sweden-*.osm.pbf' -print 2>/dev/null | LC_ALL=C sort | tail -n 1)"
  if [[ -z "$candidate" ]]; then
    printf 'PR_CHECK=FAIL road LOD validation requires Sweden PBF; set BRUR_WORLD_PBF\n' >&2
    return 1
  fi
  printf '%s\n' "$candidate"
}

prepare_runtime_world_data() {
  local pbf entry name
  pbf="$(resolve_sweden_pbf)"
  rm -rf "$RUNTIME_WORLD_DATA"
  mkdir -p "$RUNTIME_WORLD_DATA"

  for entry in "$WORLD_DATA"/*; do
    name="$(basename "$entry")"
    case "$name" in
      lod0|lod1|lod2|manifest.json) continue ;;
    esac
    ln -s "$entry" "$RUNTIME_WORLD_DATA/$name"
  done
  cp "$WORLD_DATA/manifest.json" "$RUNTIME_WORLD_DATA/manifest.json"

  printf 'PR_CHECK=BUILD_ROAD_LODS pr=%s source=%s\n' "${BRUR_PR_CHECK_PR:?}" "$(basename "$pbf")"
  "$PYTHON" "$WORKTREE/tools/build_roads.py" "$pbf" --output "$RUNTIME_WORLD_DATA"

  "$PYTHON" - "$RUNTIME_WORLD_DATA/manifest.json" <<'PY'
import json
import sys

manifest = json.load(open(sys.argv[1], encoding="utf-8"))
policy = manifest.get("road_lod_policy", {})
if policy.get("max_class") != [4, 5, 6]:
    print(f"PR_CHECK=FAIL unexpected road LOD classes: {policy.get('max_class')}")
    raise SystemExit(1)
if policy.get("min_spacing_m") != [1200.0, 300.0, 0.0]:
    print(f"PR_CHECK=FAIL unexpected road LOD spacing: {policy.get('min_spacing_m')}")
    raise SystemExit(1)
lods = manifest.get("lods", [])
if len(lods) != 3 or any(int(item.get("segments", 0)) <= 0 for item in lods):
    print("PR_CHECK=FAIL rebuilt road LODs are empty")
    raise SystemExit(1)
if not (int(lods[0]["segments"]) < int(lods[1]["segments"]) < int(lods[2]["segments"])):
    print(f"PR_CHECK=FAIL road LOD segment counts are not progressively detailed: {lods}")
    raise SystemExit(1)
print(f"PR_CHECK=ROAD_LODS_REAL_DATA_OK lods={lods}")
PY

  rm -f "$WORKTREE/world_data"
  ln -s "$RUNTIME_WORLD_DATA" "$WORKTREE/world_data"
}

prepare_runtime_world_data

[[ -d "$WORLD_DATA/poi_tiles" ]] || { printf 'PR_CHECK=FAIL missing runtime POI tiles for city-light density\n' >&2; exit 66; }

printf 'PR_CHECK=BUILD_CITY_LIGHT_DENSITY pr=%s\n' "${BRUR_PR_CHECK_PR:?}"
"$PYTHON" "$WORKTREE/tools/build_city_light_density.py" "$WORLD_DATA"
printf 'PR_CHECK=CHECK_CITY_LIGHTS_REAL_DATA pr=%s\n' "$BRUR_PR_CHECK_PR"
GODOT_BIN="$GODOT" bash "$WORKTREE/tools/test_city_lights_real_data.sh"

printf 'PR_CHECK=PREPARE_WORLD_SHOWCASE pr=%s source=existing-runtime-data\n' "${BRUR_PR_CHECK_PR:?}"
"$PYTHON" "$WORKTREE/tools/prepare_world_showcase.py" "$WORLD_DATA" --output "$CACHE"

"$PYTHON" - "$CACHE/showcase_manifest.json" "$CACHE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
cache = Path(sys.argv[2])
report = json.loads(path.read_text(encoding="utf-8"))
if report.get("source_rebuilt") is not False:
    print("PR_CHECK=FAIL world showcase unexpectedly rebuilt source data")
    raise SystemExit(1)
if int(report.get("selected_records", 0)) <= 0 or int(report.get("tile_count", 0)) <= 0:
    print("PR_CHECK=FAIL world showcase building cache is empty")
    raise SystemExit(1)
missing = [name for name, count in report.get("selected_by_city", {}).items() if int(count) <= 0]
if missing:
    print("PR_CHECK=FAIL missing showcase city building data: " + ", ".join(missing))
    raise SystemExit(1)
background = report.get("background_triangles_by_city", {})
missing_background = [name for name in ("malmo", "goteborg", "stockholm") if int(background.get(name, 0)) <= 0]
if missing_background:
    print("PR_CHECK=FAIL missing showcase city background data: " + ", ".join(missing_background))
    raise SystemExit(1)
missing_files = [name for name in background if not (cache / f"background_{name}.brmap").is_file()]
if missing_files:
    print("PR_CHECK=FAIL missing local BRM2 files: " + ", ".join(missing_files))
    raise SystemExit(1)
print(
    "PR_CHECK=WORLD_SHOWCASE_REAL_DATA_OK "
    f"selected={report['selected_records']} tiles={report['tile_count']} "
    f"cities={report['selected_by_city']} background={background} "
    f"source_rebuilt={report['source_rebuilt']}"
)
PY

run_godot_test() {
  local script="$1"
  local log status
  log="$(mktemp "${TMPDIR:-/tmp}/brur-world-test.XXXXXX.log")"
  set +e
  "$GODOT" --headless --path "$WORKTREE" --script "$script" 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  set -e
  if [[ $status -ne 0 ]]; then
    printf 'PR_CHECK=FAIL Godot exited %d for %s\n' "$status" "$script" >&2
    rm -f "$log"
    return 1
  fi
  if grep -Eq 'SCRIPT ERROR:|Failed to load script|world (streaming foundation|showcase) test failed:|road-surface real-data test failed:' "$log"; then
    printf 'PR_CHECK=FAIL Godot reported script/test errors for %s\n' "$script" >&2
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
}

run_godot_window_test() {
  local script="$1"
  local log status
  log="$(mktemp "${TMPDIR:-/tmp}/brur-world-window-test.XXXXXX.log")"
  set +e
  "$PYTHON" - "$GODOT" "$WORKTREE" "$script" "$log" <<'PY'
import subprocess
import sys

command = [sys.argv[1], "--path", sys.argv[2], "--script", sys.argv[3]]
log_path = sys.argv[4]
try:
    with open(log_path, "w", encoding="utf-8") as log:
        proc = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, text=True, timeout=45)
    raise SystemExit(proc.returncode)
except subprocess.TimeoutExpired:
    print(f"PR_CHECK=FAIL Godot timed out after 45s for {sys.argv[3]}", file=sys.stderr)
    raise SystemExit(124)
PY
  status=$?
  cat "$log"
  set -e
  if [[ $status -ne 0 ]]; then
    printf 'PR_CHECK=FAIL Godot exited %d for %s\n' "$status" "$script" >&2
    rm -f "$log"
    return 1
  fi
  if grep -Eq 'SCRIPT ERROR:|Failed to load script|production FPS real-data test failed:' "$log"; then
    printf 'PR_CHECK=FAIL Godot reported script/test errors for %s\n' "$script" >&2
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
}

printf 'PR_CHECK=CHECK_WORLD_SHOWCASE_HEADLESS pr=%s\n' "${BRUR_PR_CHECK_PR:?}"
run_godot_test res://tests/godot/test_world_streaming_foundation.gd
run_godot_test res://tests/godot/test_world_showcase.gd
printf 'PR_CHECK=CHECK_ROAD_SURFACE_REAL_DATA pr=%s\n' "${BRUR_PR_CHECK_PR:?}"
run_godot_test res://tests/godot/test_road_surface_query_real_data.gd
printf 'PR_CHECK=CHECK_PRODUCTION_FPS_REAL_DATA pr=%s\n' "${BRUR_PR_CHECK_PR:?}"
run_godot_window_test res://tests/godot/test_production_fps_real_data.gd

printf 'PR_CHECK=VISUAL_REVIEW pr=%s revision=%s\n' "${BRUR_PR_CHECK_PR:?}" "$(git -C "$WORKTREE" rev-parse --short=12 HEAD)"
printf 'PR_CHECK=VISUAL_REVIEW_INSTRUCTION inspect roads around 43 km, 150 km, and 315 km; close Godot when finished\n'
"$GODOT" --path "$WORKTREE"
