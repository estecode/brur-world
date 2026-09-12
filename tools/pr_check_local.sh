#!/usr/bin/env bash
# Runs only expensive local real-data checks whose owned subsystem changed, then opens the exact PR runtime for any requested human review.
# Dependencies: changed-file scope from pr_check.sh, existing local world_data, and source/build tools only for scopes that require them.
set -euo pipefail

WORKTREE="${BRUR_PR_CHECK_WORKTREE:?}"
WORLD_DATA="${BRUR_PR_CHECK_WORLD_DATA:?}"
PYTHON="${PYTHON_BIN:?}"
GODOT="${GODOT_BIN:?}"
CHANGED_FILES="${BRUR_PR_CHECK_CHANGED_FILES:-}"
CACHE="$WORKTREE/.poc_runtime/world_showcase"
RUNTIME_WORLD_DATA="$WORKTREE/.poc_runtime/pr_check_world_data"

scope_decision() {
  local scope="$1" decision
  decision="$(printf '%s\n' "$CHANGED_FILES" | "$PYTHON" "$WORKTREE/tools/pr_check_scope.py" "$scope")"
  case "$decision" in
    required|skip) printf '%s\n' "$decision" ;;
    *) printf 'PR_CHECK=FAIL invalid %s scope decision: %s\n' "$scope" "$decision" >&2; return 70 ;;
  esac
}

ROAD_LOD_SCOPE="$(scope_decision road-lod)"
CITY_LIGHT_SCOPE="$(scope_decision city-lights)"
WORLD_SHOWCASE_SCOPE="$(scope_decision world-showcase)"

if [[ "$ROAD_LOD_SCOPE" == "skip" ]]; then
  printf 'PR_CHECK=SKIP_ROAD_LODS pr=%s reason=unrelated-changes\n' "${BRUR_PR_CHECK_PR:?}"
fi
if [[ "$CITY_LIGHT_SCOPE" == "skip" ]]; then
  printf 'PR_CHECK=SKIP_CITY_LIGHT_REAL_DATA pr=%s reason=unrelated-changes\n' "$BRUR_PR_CHECK_PR"
fi
if [[ "$WORLD_SHOWCASE_SCOPE" == "skip" ]]; then
  printf 'PR_CHECK=SKIP_WORLD_SHOWCASE_PREP pr=%s reason=unrelated-changes\n' "$BRUR_PR_CHECK_PR"
fi

if [[ "$ROAD_LOD_SCOPE" == "skip" && "$CITY_LIGHT_SCOPE" == "skip" && "$WORLD_SHOWCASE_SCOPE" == "skip" ]]; then
  printf 'PR_CHECK=NO_EXPENSIVE_LOCAL_PREPARATION pr=%s\n' "$BRUR_PR_CHECK_PR"
fi

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
    printf 'PR_CHECK=FAIL required road LOD rebuild needs Sweden PBF; set BRUR_WORLD_PBF\n' >&2
    return 1
  fi
  printf '%s\n' "$candidate"
}

prepare_road_runtime_data() {
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
  printf 'PR_CHECK=BUILD_ROAD_LODS pr=%s reason=relevant-changes source=%s\n' "$BRUR_PR_CHECK_PR" "$(basename "$pbf")"
  "$PYTHON" "$WORKTREE/tools/build_roads.py" "$pbf" --output "$RUNTIME_WORLD_DATA"
  "$PYTHON" - "$RUNTIME_WORLD_DATA/manifest.json" <<'PY'
import json
import sys
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
policy = manifest.get("road_lod_policy", {})
lods = manifest.get("lods", [])
if policy.get("max_class") != [4, 5, 6] or policy.get("min_spacing_m") != [1200.0, 300.0, 0.0]:
    raise SystemExit("PR_CHECK=FAIL unexpected road LOD policy")
if len(lods) != 3 or any(int(item.get("segments", 0)) <= 0 for item in lods):
    raise SystemExit("PR_CHECK=FAIL rebuilt road LODs are empty")
if not (int(lods[0]["segments"]) < int(lods[1]["segments"]) < int(lods[2]["segments"])):
    raise SystemExit("PR_CHECK=FAIL road LOD segment counts are not progressively detailed")
print(f"PR_CHECK=ROAD_LODS_REAL_DATA_OK lods={lods}")
PY
  rm -f "$WORKTREE/world_data"
  ln -s "$RUNTIME_WORLD_DATA" "$WORKTREE/world_data"
}

run_godot_test() {
  local script="$1" log status
  log="$(mktemp "${TMPDIR:-/tmp}/brur-world-test.XXXXXX.log")"
  set +e
  "$GODOT" --headless --path "$WORKTREE" --script "$script" 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  set -e
  if [[ $status -ne 0 ]] || grep -Eq 'SCRIPT ERROR:|Failed to load script|test failed:' "$log"; then
    printf 'PR_CHECK=FAIL Godot reported script/test errors for %s\n' "$script" >&2
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
}

if [[ "$ROAD_LOD_SCOPE" == "required" ]]; then
  prepare_road_runtime_data
  printf 'PR_CHECK=CHECK_WORLD_STREAMING_HEADLESS pr=%s\n' "$BRUR_PR_CHECK_PR"
  run_godot_test res://tests/godot/test_world_streaming_foundation.gd
  printf 'PR_CHECK=CHECK_ROAD_SURFACE_REAL_DATA pr=%s\n' "$BRUR_PR_CHECK_PR"
  run_godot_test res://tests/godot/test_road_surface_query_real_data.gd
fi

if [[ "$CITY_LIGHT_SCOPE" == "required" ]]; then
  [[ -d "$WORLD_DATA/poi_tiles" ]] || { printf 'PR_CHECK=FAIL missing runtime POI tiles for city-light density\n' >&2; exit 66; }
  printf 'PR_CHECK=BUILD_CITY_LIGHT_DENSITY pr=%s reason=relevant-changes\n' "$BRUR_PR_CHECK_PR"
  "$PYTHON" "$WORKTREE/tools/build_city_light_density.py" "$WORLD_DATA"
  printf 'PR_CHECK=CHECK_CITY_LIGHTS_REAL_DATA pr=%s\n' "$BRUR_PR_CHECK_PR"
  GODOT_BIN="$GODOT" bash "$WORKTREE/tools/test_city_lights_real_data.sh"
fi

if [[ "$WORLD_SHOWCASE_SCOPE" == "required" ]]; then
  printf 'PR_CHECK=PREPARE_WORLD_SHOWCASE pr=%s reason=relevant-changes\n' "$BRUR_PR_CHECK_PR"
  "$PYTHON" "$WORKTREE/tools/prepare_world_showcase.py" "$WORLD_DATA" --output "$CACHE"
  "$PYTHON" - "$CACHE/showcase_manifest.json" <<'PY'
import json
import sys
report = json.load(open(sys.argv[1], encoding="utf-8"))
if report.get("source_rebuilt") is not False or int(report.get("selected_records", 0)) <= 0:
    raise SystemExit("PR_CHECK=FAIL invalid world showcase cache")
print(f"PR_CHECK=WORLD_SHOWCASE_REAL_DATA_OK selected={report['selected_records']} tiles={report['tile_count']}")
PY
  printf 'PR_CHECK=CHECK_WORLD_SHOWCASE_HEADLESS pr=%s\n' "$BRUR_PR_CHECK_PR"
  run_godot_test res://tests/godot/test_world_showcase.gd
fi

printf 'PR_CHECK=VISUAL_REVIEW pr=%s revision=%s\n' "$BRUR_PR_CHECK_PR" "$(git -C "$WORKTREE" rev-parse --short=12 HEAD)"
printf 'PR_CHECK=VISUAL_REVIEW_INSTRUCTION inspect only the changed real-data presentation; close Godot when finished\n'
"$GODOT" --path "$WORKTREE"
