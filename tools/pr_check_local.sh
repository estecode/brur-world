#!/usr/bin/env bash
# Runs only relevant local real-data preparation, then opens the exact PR runtime only when human visual review remains meaningful.
# Dependencies: changed-file scope and explicit PR merge-decision review contract from pr_check.sh, existing local world_data, and source/build tools only for scopes that require them.
set -euo pipefail

WORKTREE="${BRUR_PR_CHECK_WORKTREE:?}"
WORLD_DATA="${BRUR_PR_CHECK_WORLD_DATA:?}"
PYTHON="${PYTHON_BIN:?}"
GODOT="${GODOT_BIN:?}"
CHANGED_FILES="${BRUR_PR_CHECK_CHANGED_FILES:-}"
MANUAL_REVIEW="${BRUR_PR_CHECK_MANUAL_REVIEW:-none}"
CACHE="$WORKTREE/.poc_runtime/world_showcase"
RUNTIME_WORLD_DATA="$WORKTREE/.poc_runtime/pr_check_world_data"
TRAFFIC_INTERSECTION_DATA="$WORKTREE/.poc_runtime/traffic_intersections"

case "$MANUAL_REVIEW" in required|none) ;; *) printf 'PR_CHECK=FAIL invalid BRUR_PR_CHECK_MANUAL_REVIEW=%s\n' "$MANUAL_REVIEW" >&2; exit 70 ;; esac
scope_decision() { local scope="$1" decision; decision="$(printf '%s\n' "$CHANGED_FILES" | "$PYTHON" "$WORKTREE/tools/pr_check_scope.py" "$scope")"; case "$decision" in required|skip) printf '%s\n' "$decision" ;; *) printf 'PR_CHECK=FAIL invalid %s scope decision: %s\n' "$scope" "$decision" >&2; return 70 ;; esac; }
ROUTE_GEOMETRY_SCOPE="$(scope_decision route-geometry)"; ROAD_LOD_SCOPE="$(scope_decision road-lod)"; CITY_LIGHT_SCOPE="$(scope_decision city-lights)"; WORLD_SHOWCASE_SCOPE="$(scope_decision world-showcase)"; BUILDING_TILE_SCOPE="$(scope_decision building-tiles)"
TRAFFIC_INTERSECTION_SCOPE="skip"; DRIVING_VISUAL_SCOPE="skip"; DRIVE_HUD_VISUAL_SCOPE="skip"; GEODOT_POC_SCOPE="skip"
if printf '%s\n' "$CHANGED_FILES" | grep -Eq '(^|/)(traffic_intersections\.py|check_traffic_intersections_real_data\.py|test_traffic_intersections\.py)$'; then TRAFFIC_INTERSECTION_SCOPE="required"; fi
if printf '%s\n' "$CHANGED_FILES" | grep -Eq '^(harness/driving/|scripts/(route_driving_policy|vehicle_route_follower|vehicle_dynamics|player_vehicle|player_vehicle_controller)\.gd$|scenes/player_vehicle\.tscn$)'; then DRIVING_VISUAL_SCOPE="required"; fi
if printf '%s\n' "$CHANGED_FILES" | grep -Eq '^(scripts/(drive_hud|drive_hud_adapter|speed_limit_sign|road_speed_limit_query)\.gd|scenes/main\.tscn)$'; then DRIVE_HUD_VISUAL_SCOPE="required"; fi
if printf '%s\n' "$CHANGED_FILES" | grep -Eq '^(scripts/geodot_|scenes/geodot_poc\.tscn$|tests/godot/test_geodot_|tools/(setup_geodot_poc\.sh|check_geodot_gpkg\.py)$|\.github/workflows/geodot-poc-validation\.yml$)'; then GEODOT_POC_SCOPE="required"; fi
if [[ "$ROUTE_GEOMETRY_SCOPE" == "skip" ]]; then printf 'PR_CHECK=SKIP_E6_BJARRED_ROUTE pr=%s reason=unrelated-changes\n' "${BRUR_PR_CHECK_PR:?}"; fi
if [[ "$ROAD_LOD_SCOPE" == "skip" ]]; then printf 'PR_CHECK=SKIP_ROAD_LODS pr=%s reason=unrelated-changes\n' "${BRUR_PR_CHECK_PR:?}"; fi
if [[ "$CITY_LIGHT_SCOPE" == "skip" ]]; then printf 'PR_CHECK=SKIP_CITY_LIGHT_REAL_DATA pr=%s reason=unrelated-changes\n' "$BRUR_PR_CHECK_PR"; fi
if [[ "$WORLD_SHOWCASE_SCOPE" == "skip" ]]; then printf 'PR_CHECK=SKIP_WORLD_SHOWCASE_PREP pr=%s reason=unrelated-changes\n' "$BRUR_PR_CHECK_PR"; fi
if [[ "$BUILDING_TILE_SCOPE" == "skip" ]]; then printf 'PR_CHECK=SKIP_BUILDING_MESH_LOD pr=%s reason=unrelated-changes\n' "$BRUR_PR_CHECK_PR"; fi
if [[ "$TRAFFIC_INTERSECTION_SCOPE" == "skip" ]]; then printf 'PR_CHECK=SKIP_TRAFFIC_INTERSECTIONS pr=%s reason=unrelated-changes\n' "$BRUR_PR_CHECK_PR"; fi
if [[ "$DRIVING_VISUAL_SCOPE" == "skip" ]]; then printf 'PR_CHECK=SKIP_DRIVING_VISUAL_REVIEW pr=%s reason=unrelated-changes\n' "$BRUR_PR_CHECK_PR"; fi
if [[ "$DRIVE_HUD_VISUAL_SCOPE" == "skip" ]]; then printf 'PR_CHECK=SKIP_DRIVE_HUD_VISUAL_REVIEW pr=%s reason=unrelated-changes\n' "$BRUR_PR_CHECK_PR"; fi
if [[ "$GEODOT_POC_SCOPE" == "skip" ]]; then printf 'PR_CHECK=SKIP_GEODOT_POC pr=%s reason=unrelated-changes\n' "$BRUR_PR_CHECK_PR"; fi
if [[ "$ROUTE_GEOMETRY_SCOPE" == "skip" && "$ROAD_LOD_SCOPE" == "skip" && "$CITY_LIGHT_SCOPE" == "skip" && "$WORLD_SHOWCASE_SCOPE" == "skip" && "$BUILDING_TILE_SCOPE" == "skip" && "$TRAFFIC_INTERSECTION_SCOPE" == "skip" && "$GEODOT_POC_SCOPE" == "skip" ]]; then printf 'PR_CHECK=NO_EXPENSIVE_LOCAL_PREPARATION pr=%s\n' "$BRUR_PR_CHECK_PR"; fi

resolve_sweden_pbf() {
  if [[ -n "${BRUR_WORLD_PBF:-}" ]]; then [[ -f "$BRUR_WORLD_PBF" ]] || { printf 'PR_CHECK=FAIL BRUR_WORLD_PBF does not exist\n' >&2; return 1; }; printf '%s\n' "$BRUR_WORLD_PBF"; return 0; fi
  local repo_parent candidate; repo_parent="$(cd "$(dirname "$WORLD_DATA")/.." && pwd)"; candidate="$(find "$repo_parent/syndicate/data" "$repo_parent/data" -maxdepth 1 -type f -name 'sweden-*.osm.pbf' -print 2>/dev/null | LC_ALL=C sort | tail -n 1)"
  if [[ -z "$candidate" ]]; then printf 'PR_CHECK=FAIL required real-data rebuild needs Sweden PBF; set BRUR_WORLD_PBF\n' >&2; return 1; fi; printf '%s\n' "$candidate"
}
resolve_geodot_gpkg() {
  if [[ -n "${BRUR_GEODOT_GPKG:-}" ]]; then [[ -f "$BRUR_GEODOT_GPKG" ]] || { printf 'PR_CHECK=FAIL BRUR_GEODOT_GPKG does not exist\n' >&2; return 1; }; printf '%s\n' "$BRUR_GEODOT_GPKG"; return 0; fi
  local checkout_root checkout_parent mapped_root candidate search_root; checkout_root="$(cd "$(dirname "$WORLD_DATA")" && pwd)"; checkout_parent="$(cd "$checkout_root/.." && pwd)"; mapped_root="${BRUR_PR_CHECK_MAPPED_ROOT:-$checkout_root}"
  for candidate in "$mapped_root/sweden-brur.gpkg" "$checkout_root/sweden-brur.gpkg" "$checkout_parent/sweden-brur.gpkg" "$checkout_parent/data/sweden-brur.gpkg" "$checkout_parent/brur-world/sweden-brur.gpkg"; do if [[ -f "$candidate" ]]; then printf '%s\n' "$candidate"; return 0; fi; done
  for search_root in "$mapped_root" "$checkout_root" "$checkout_parent"; do [[ -d "$search_root" ]] || continue; candidate="$(find "$search_root" -maxdepth 3 -type f -name 'sweden-brur.gpkg' -print 2>/dev/null | head -n1)"; if [[ -n "$candidate" && -f "$candidate" ]]; then printf '%s\n' "$candidate"; return 0; fi; done
  printf 'PR_CHECK=FAIL GeoDot POC requires sweden-brur.gpkg in the mapped BRUR checkout/data tree or BRUR_GEODOT_GPKG\n' >&2; return 1
}
ensure_routing_dataset_identity() { if "$PYTHON" "$WORKTREE/tools/check_routing_dataset.py" "$WORLD_DATA"; then printf 'PR_CHECK=REUSE_ROUTING_DATASET pr=%s reason=identity-match\n' "$BRUR_PR_CHECK_PR"; return 0; fi; local pbf; pbf="$(resolve_sweden_pbf)"; printf 'PR_CHECK=BUILD_ROUTING_DATASET pr=%s reason=identity-mismatch source=%s\n' "$BRUR_PR_CHECK_PR" "$(basename "$pbf")"; "$PYTHON" "$WORKTREE/tools/build_routing_dataset.py" "$pbf" --output "$WORLD_DATA"; "$PYTHON" "$WORKTREE/tools/check_routing_dataset.py" "$WORLD_DATA"; }
prepare_traffic_intersection_data() { if [[ -f "$WORLD_DATA/traffic_signals.json" ]]; then printf '%s\n' "$WORLD_DATA"; return 0; fi; local pbf; pbf="$(resolve_sweden_pbf)"; rm -rf "$TRAFFIC_INTERSECTION_DATA"; mkdir -p "$TRAFFIC_INTERSECTION_DATA"; ln -s "$WORLD_DATA/routing.brg" "$TRAFFIC_INTERSECTION_DATA/routing.brg"; printf 'PR_CHECK=BUILD_TRAFFIC_SIGNALS pr=%s reason=missing-runtime-data source=%s\n' "$BRUR_PR_CHECK_PR" "$(basename "$pbf")" >&2; "$PYTHON" "$WORKTREE/tools/build_traffic_signals.py" "$pbf" --output "$TRAFFIC_INTERSECTION_DATA" >&2; [[ -f "$TRAFFIC_INTERSECTION_DATA/traffic_signals.json" ]] || { printf 'PR_CHECK=FAIL traffic signal build did not produce traffic_signals.json\n' >&2; return 1; }; printf '%s\n' "$TRAFFIC_INTERSECTION_DATA"; }
prepare_road_runtime_data() {
  local pbf entry name; pbf="$(resolve_sweden_pbf)"; rm -rf "$RUNTIME_WORLD_DATA"; mkdir -p "$RUNTIME_WORLD_DATA"; for entry in "$WORLD_DATA"/*; do name="$(basename "$entry")"; case "$name" in lod0|lod1|lod2|manifest.json) continue ;; esac; ln -s "$entry" "$RUNTIME_WORLD_DATA/$name"; done; cp "$WORLD_DATA/manifest.json" "$RUNTIME_WORLD_DATA/manifest.json"; printf 'PR_CHECK=BUILD_ROAD_LODS pr=%s reason=relevant-changes source=%s\n' "$BRUR_PR_CHECK_PR" "$(basename "$pbf")"; "$PYTHON" "$WORKTREE/tools/build_roads.py" "$pbf" --output "$RUNTIME_WORLD_DATA"
  "$PYTHON" - "$RUNTIME_WORLD_DATA/manifest.json" <<'PY'
import json, sys
report=json.load(open(sys.argv[1],encoding='utf-8'))
print('PR_CHECK=ROAD_RUNTIME_DATA_OK')
PY
}
run_godot_test() { local scene="$1" marker="${2:-}" output; set +e; output="$(BRUR_WORLD_DATA="$WORLD_DATA" "$GODOT" --headless --path "$WORKTREE" --editor --quit-after 2 "$scene" 2>&1)"; local status=$?; set -e; printf '%s\n' "$output"; [[ $status -eq 0 ]] || return $status; if [[ -n "$marker" ]]; then printf '%s\n' "$output" | grep -Fq "$marker" || { printf 'PR_CHECK=FAIL missing marker: %s\n' "$marker" >&2; return 1; }; fi; }

if [[ "$ROUTE_GEOMETRY_SCOPE" == "required" ]]; then ensure_routing_dataset_identity; fi
if [[ "$TRAFFIC_INTERSECTION_SCOPE" == "required" ]]; then TRAFFIC_DATA="$(prepare_traffic_intersection_data)"; "$PYTHON" "$WORKTREE/tools/check_traffic_intersections_real_data.py" "$TRAFFIC_DATA"; fi
if [[ "$BUILDING_TILE_SCOPE" == "required" ]]; then printf 'PR_CHECK=CHECK_PRODUCTION_DRIVE_FPS_REAL_DATA pr=%s targets=avg33.4ms-p95_50ms-worst250ms\n' "$BRUR_PR_CHECK_PR"; run_godot_test res://tests/godot/test_production_fps_real_data.gd 'production Drive FPS real-data test: OK'; fi
if [[ "$ROAD_LOD_SCOPE" == "required" ]]; then prepare_road_runtime_data; printf 'PR_CHECK=CHECK_WORLD_STREAMING_HEADLESS pr=%s\n' "$BRUR_PR_CHECK_PR"; run_godot_test res://tests/godot/test_world_streaming_foundation.gd; printf 'PR_CHECK=CHECK_ROAD_SURFACE_REAL_DATA pr=%s\n' "$BRUR_PR_CHECK_PR"; run_godot_test res://tests/godot/test_road_surface_query_real_data.gd; fi
if [[ "$CITY_LIGHT_SCOPE" == "required" ]]; then [[ -d "$WORLD_DATA/poi_tiles" ]] || { printf 'PR_CHECK=FAIL missing runtime POI tiles for city-light density\n' >&2; exit 66; }; "$PYTHON" "$WORKTREE/tools/build_city_light_density.py" "$WORLD_DATA"; GODOT_BIN="$GODOT" bash "$WORKTREE/tools/test_city_lights_real_data.sh"; fi
if [[ "$WORLD_SHOWCASE_SCOPE" == "required" ]]; then "$PYTHON" "$WORKTREE/tools/prepare_world_showcase.py" "$WORLD_DATA" --output "$CACHE"; run_godot_test res://tests/godot/test_world_showcase.gd; fi
GEODOT_GPKG=""
if [[ "$GEODOT_POC_SCOPE" == "required" ]]; then
  GEODOT_GPKG="$(resolve_geodot_gpkg)"; printf 'PR_CHECK=GEODOT_GPKG path=%s\n' "$GEODOT_GPKG"; bash "$WORKTREE/tools/setup_geodot_poc.sh"; "$PYTHON" "$WORKTREE/tools/check_geodot_gpkg.py" "$GEODOT_GPKG"; printf 'PR_CHECK=CHECK_GEODOT_CONTRACTS pr=%s\n' "$BRUR_PR_CHECK_PR"; BRUR_GEODOT_GPKG="$GEODOT_GPKG" run_godot_test res://tests/godot/test_geodot_renderer_contracts.gd 'geodot renderer contracts: OK'; printf 'PR_CHECK=CHECK_GEODOT_REAL_DATA pr=%s\n' "$BRUR_PR_CHECK_PR"; BRUR_GEODOT_GPKG="$GEODOT_GPKG" run_godot_test res://tests/godot/test_geodot_real_data.gd 'geodot real-data test: OK'; printf 'PR_CHECK=GEODOT_OBJECTIVE_OK pr=%s\n' "$BRUR_PR_CHECK_PR"
fi
if [[ "$MANUAL_REVIEW" == "none" && "$DRIVING_VISUAL_SCOPE" == "skip" && "$DRIVE_HUD_VISUAL_SCOPE" == "skip" ]]; then printf 'PR_CHECK=SKIP_VISUAL_REVIEW pr=%s reason=no-subjective-check-remains\n' "$BRUR_PR_CHECK_PR"; exit 0; fi
printf 'PR_CHECK=VISUAL_REVIEW pr=%s revision=%s\n' "$BRUR_PR_CHECK_PR" "$(git -C "$WORKTREE" rev-parse --short=12 HEAD)"
if [[ "$GEODOT_POC_SCOPE" == "required" ]]; then printf 'PR_CHECK=VISUAL_REVIEW_TARGET scene=scenes/geodot_poc.tscn reason=geodot-poc\n'; printf 'PR_CHECK=VISUAL_REVIEW_EXPECT window=production-main renderer=geodot area=Lund\n'; printf 'PR_CHECK=VISUAL_REVIEW_INSTRUCTION use the normal BRUR controls in Lund; judge only perceptual density, scale, smoothness, long-distance presence and seamless LOD/streaming; close Godot when finished\n'; BRUR_GEODOT_GPKG="$GEODOT_GPKG" "$GODOT" --path "$WORKTREE" "$WORKTREE/scenes/geodot_poc.tscn"; exit 0; fi
if [[ "$DRIVE_HUD_VISUAL_SCOPE" == "required" ]]; then printf 'PR_CHECK=VISUAL_REVIEW_TARGET scene=scenes/main.tscn reason=drive-hud\n'; printf 'PR_CHECK=VISUAL_REVIEW_EXPECT window=production-main not=driving-harness\n'; printf 'PR_CHECK=VISUAL_REVIEW_INSTRUCTION this check must open the normal Brur World production Main scene, not DRIVING HARNESS. Enter Drive in that scene and inspect the ruta-1 HUD: Swedish speed-limit sign left, fixed-width current speed beside it, optional ETA on active route, and explicit unknown limit. If the window title/content says DRIVING HARNESS, close it and report launcher failure instead of judging the HUD.\n'; "$GODOT" --path "$WORKTREE" "$WORKTREE/scenes/main.tscn"; exit 0; fi
if [[ "$DRIVING_VISUAL_SCOPE" == "required" ]]; then printf 'PR_CHECK=VISUAL_REVIEW_TARGET scene=harness/driving/driving_harness.tscn reason=driving-feel\n'; printf 'PR_CHECK=VISUAL_REVIEW_INSTRUCTION use Follow route and compare Driving policy Normal, Aggressive and Maniac on the same loop; confirm they feel clearly distinct and ordered in assertiveness; close Godot when finished\n'; "$GODOT" --path "$WORKTREE" "$WORKTREE/harness/driving/driving_harness.tscn"; exit 0; fi
if [[ "$MANUAL_REVIEW" == "required" && "$BUILDING_TILE_SCOPE" == "skip" && "$ROAD_LOD_SCOPE" == "skip" && "$CITY_LIGHT_SCOPE" == "skip" && "$WORLD_SHOWCASE_SCOPE" == "skip" ]]; then printf 'PR_CHECK=VISUAL_REVIEW_TARGET scene=scenes/main.tscn reason=pr-merge-decision\n'; printf 'PR_CHECK=VISUAL_REVIEW_EXPECT window=production-main not=editor\n'; printf 'PR_CHECK=VISUAL_REVIEW_INSTRUCTION perform the concrete CHECK from the PR merge decision in the normal Brur World game; close Godot when finished\n'; "$GODOT" --path "$WORKTREE" "$WORKTREE/scenes/main.tscn"; exit 0; fi
if [[ "$BUILDING_TILE_SCOPE" == "required" ]]; then printf 'PR_CHECK=VISUAL_REVIEW_INSTRUCTION production Drive real-data FPS/building checks have already passed automatically; inspect only genuinely perceptual presentation quality if desired, then close Godot\n'; else printf 'PR_CHECK=VISUAL_REVIEW_INSTRUCTION inspect only the changed real-data presentation; close Godot when finished\n'; fi
"$GODOT" --path "$WORKTREE"
