#!/usr/bin/env bash
set -euo pipefail
WORKTREE="${BRUR_PR_CHECK_WORKTREE:?}"; PYTHON="${PYTHON_BIN:?}"; GODOT="${GODOT_BIN:?}"; CHANGED_FILES="${BRUR_PR_CHECK_CHANGED_FILES:-}"; MANUAL_REVIEW="${BRUR_PR_CHECK_MANUAL_REVIEW:-none}"
DRIVE_HUD_VISUAL_SCOPE="skip"; DRIVING_VISUAL_SCOPE="skip"
if printf '%s\n' "$CHANGED_FILES" | grep -Eq '^(scripts/(drive_hud|drive_hud_adapter|speed_limit_sign|road_speed_limit_query)\.gd|scenes/main\.tscn)$'; then DRIVE_HUD_VISUAL_SCOPE="required"; fi
if printf '%s\n' "$CHANGED_FILES" | grep -Eq '^(harness/driving/|scripts/(route_driving_policy|vehicle_route_follower|vehicle_dynamics|player_vehicle|player_vehicle_controller)\.gd$|scenes/player_vehicle\.tscn$)'; then DRIVING_VISUAL_SCOPE="required"; fi
run(){ printf 'PR_CHECK=STAGE_BEGIN stage=%s\n' "$1"; local n="$1"; shift; "$@"; printf 'PR_CHECK=STAGE_OK stage=%s\n' "$n"; }
testgd(){ local s="$1" m="${2:-}" l status; l="$(mktemp)"; set +e; "$GODOT" --headless --path "$WORKTREE" --script "$s" 2>&1 | tee "$l"; status=${PIPESTATUS[0]}; set -e; if [[ $status -ne 0 ]] || grep -Eq 'SCRIPT ERROR:|Failed to load script|ASSERT FAILED:|=FAIL' "$l"; then rm -f "$l"; return 1; fi; if [[ -n "$m" ]] && ! grep -Fq "$m" "$l"; then printf 'PR_CHECK=FAIL Godot test exited without required completion marker for %s: %s\n' "$s" "$m" >&2; rm -f "$l"; return 1; fi; rm -f "$l"; }
if ! printf '%s\n' "$CHANGED_FILES" | grep -Eq '(^|/)(geodot[^/]*|test_geodot[^/]*)'; then
  if [[ -x "$WORKTREE/tools/pr_check_standard.sh" ]]; then exec bash "$WORKTREE/tools/pr_check_standard.sh"; fi
  # Minimal fixture-compatible fallback used by Safe Check's own E2E tests.
  if printf '%s\n' "$CHANGED_FILES" | grep -Eq '^scripts/camera_controller\.gd$'; then
    testgd res://tests/godot/test_world_streaming_foundation.gd
    testgd res://tests/godot/test_building_mesh_real_data.gd
    testgd res://tests/godot/test_map_controls.gd
    testgd res://tests/godot/test_production_fps_real_data.gd 'production Drive FPS real-data test: OK'
    if [[ "$MANUAL_REVIEW" == none ]]; then printf 'PR_CHECK=SKIP_VISUAL_REVIEW pr=%s reason=no-subjective-check-remains\n' "${BRUR_PR_CHECK_PR:?}"; fi
    exit 0
  fi
  if [[ "$DRIVE_HUD_VISUAL_SCOPE" == "required" ]]; then printf 'PR_CHECK=VISUAL_REVIEW_TARGET scene=scenes/main.tscn reason=drive-hud\n'; printf 'PR_CHECK=VISUAL_REVIEW_EXPECT window=production-main not=driving-harness\n'; exec "$GODOT" --path "$WORKTREE" "$WORKTREE/scenes/main.tscn"; fi
  if [[ "$DRIVING_VISUAL_SCOPE" == "required" ]]; then exec "$GODOT" --path "$WORKTREE" "$WORKTREE/harness/driving/driving_harness.tscn"; fi
  printf 'PR_CHECK=SKIP_VISUAL_REVIEW reason=no-geodot-or-visual-scope\n'; exit 0
fi
GPKG="${BRUR_GEODOT_GPKG:-$HOME/Dropbox/Code/brur-world/sweden-brur.gpkg}"; [[ -f "$GPKG" ]] || { echo 'PR_CHECK=FAIL gpkg missing' >&2; exit 1; }; export BRUR_GEODOT_GPKG="$GPKG" BRUR_GEODOT_FAR_CACHE="$WORKTREE/.cache/geodot-far-cache.json"
run setup bash "$WORKTREE/tools/setup_geodot_poc.sh"; run gpkg "$PYTHON" "$WORKTREE/tools/check_geodot_gpkg.py" "$GPKG"; run far-cache "$PYTHON" "$WORKTREE/tests/test_geodot_far_cache.py"
for x in 'hlod|res://tests/godot/test_geodot_hlod_residency.gd|GEODOT_HLOD_RESIDENCY=PASS' 'runtime-hlod|res://tests/godot/test_geodot_runtime_hlod_integration.gd|GEODOT_RUNTIME_HLOD_INTEGRATION=PASS' 'renderer|res://tests/godot/test_geodot_renderer_contracts.gd|' 'bounds|res://tests/godot/test_geodot_runtime_bounds.gd|' 'lod|res://tests/godot/test_geodot_lod_policy.gd|' 'tuning|res://tests/godot/test_geodot_tuning_contract.gd|' 'coverage|res://tests/godot/test_geodot_view_coverage.gd|' 'streaming|res://tests/godot/test_geodot_streaming_policy.gd|' 'transition|res://tests/godot/test_geodot_streaming_transition.gd|' 'ownership|res://tests/godot/test_geodot_atomic_ownership.gd|' 'photozoom|res://tests/godot/test_geodot_photo_zoom_contract.gd|' 'geometry|res://tests/godot/test_geodot_cell_geometry.gd|' 'continuity|res://tests/godot/test_geodot_lod_continuity.gd|' 'composition|res://tests/godot/test_geodot_composition_contract.gd|' 'failure|res://tests/godot/test_geodot_failure_contract.gd|' 'realdata|res://tests/godot/test_geodot_real_data.gd|' 'fps|res://tests/godot/test_geodot_fps_real_data.gd|'; do IFS='|' read -r n s m <<< "$x"; run "$n" testgd "$s" "$m"; done
printf 'PR_CHECK=GEODOT_OBJECTIVE_OK no_holes=true runtime_hlod=true warm_reverse_zoom=true bounded=true\n'
[[ "$MANUAL_REVIEW" == required ]] || { printf 'PR_CHECK=SKIP_VISUAL_REVIEW reason=no-subjective-check-remains\n'; exit 0; }
printf 'PR_CHECK=VISUAL_REVIEW_TARGET scene=scenes/geodot_poc.tscn reason=final-perceptual-only\n'
BRUR_BUILD_REVISION="$(git -C "$WORKTREE" rev-parse --short=12 HEAD)" "$GODOT" --path "$WORKTREE" "$WORKTREE/scenes/geodot_poc.tscn"
