#!/usr/bin/env bash
# Prepares and objectively validates current PR-owned real-data integration checks.
# Dependencies: existing local world_data, city-light density tooling, world showcase preparation, and Godot supplied by PR check.
set -euo pipefail

WORKTREE="${BRUR_PR_CHECK_WORKTREE:?}"
WORLD_DATA="${BRUR_PR_CHECK_WORLD_DATA:?}"
PYTHON="${PYTHON_BIN:?}"
GODOT="${GODOT_BIN:?}"
CACHE="$WORKTREE/.poc_runtime/world_showcase"

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
  log="$(mktemp "${TMPDIR:-/tmp}/brur-world-showcase-test.XXXXXX.log")"
  set +e
  "$GODOT" --headless --path "$WORKTREE" --script "$script" 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  set -e
  if [[ $status -ne 0 ]]; then
    printf 'PR_CHECK=FAIL Godot exited %d for %s\n' "$status" "$script" >&2
    rm -f "$log"
    return 1
  fi
  if grep -Eq 'SCRIPT ERROR:|Failed to load script|world (streaming foundation|showcase) test failed:' "$log"; then
    printf 'PR_CHECK=FAIL Godot reported script/test errors for %s\n' "$script" >&2
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
}

printf 'PR_CHECK=CHECK_WORLD_SHOWCASE_HEADLESS pr=%s\n' "${BRUR_PR_CHECK_PR:?}"
run_godot_test res://tests/godot/test_world_streaming_foundation.gd
run_godot_test res://tests/godot/test_world_showcase.gd

# Diagnostic #136: objective checks above use untouched production code. Only the
# disposable detached PR-check worktree is patched before the human hardware A/B.
"$PYTHON" - "$WORKTREE/scripts/main.gd" "$WORKTREE/scenes/main.tscn" <<'PY'
from pathlib import Path
import sys

main_path = Path(sys.argv[1])
scene_path = Path(sys.argv[2])
main = main_path.read_text(encoding="utf-8")
needle = "\t_create_ground()\n\t_load_background()\n\t_update_depth_layout(true)"
replacement = (
    "\t_create_ground()\n"
    "\t# Diagnostic #136: skip full-Sweden BRM2 background for hardware A/B.\n"
    "\t_update_depth_layout(true)"
)
if main.count(needle) != 1:
    print("PR_CHECK=FAIL combined diagnostic could not find exact background startup sequence")
    raise SystemExit(1)
main_path.write_text(main.replace(needle, replacement), encoding="utf-8")

scene = scene_path.read_text(encoding="utf-8")
cloud_node = '[node name="CloudField" type="MultiMeshInstance3D" parent="."]\nscript = ExtResource("13_clouds")'
cloud_replacement = cloud_node + '\nvisible = false\nprocess_mode = 4'
if scene.count(cloud_node) != 1:
    print("PR_CHECK=FAIL combined diagnostic could not find exact CloudField node")
    raise SystemExit(1)
scene_path.write_text(scene.replace(cloud_node, cloud_replacement), encoding="utf-8")
print("PR_CHECK=DIAGNOSTIC background=off clouds=off roads=production")
PY
