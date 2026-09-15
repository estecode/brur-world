#!/usr/bin/env bash
set -euo pipefail
WORKTREE="${BRUR_PR_CHECK_WORKTREE:?}"; WORLD_DATA="${BRUR_PR_CHECK_WORLD_DATA:?}"; PYTHON="${PYTHON_BIN:?}"; GODOT="${GODOT_BIN:?}"
MANUAL_REVIEW="${BRUR_PR_CHECK_MANUAL_REVIEW:-none}"; CHANGED_FILES="${BRUR_PR_CHECK_CHANGED_FILES:-}"
DRIVE_HUD_VISUAL_SCOPE="skip"; DRIVING_VISUAL_SCOPE="skip"
if printf '%s\n' "$CHANGED_FILES" | grep -Eq '^scripts/(drive_hud|drive_hud_adapter|speed_limit_sign|road_speed_limit_query)\.gd$|^scenes/main\.tscn$'; then DRIVE_HUD_VISUAL_SCOPE="required"; fi
if printf '%s\n' "$CHANGED_FILES" | grep -Eq '^(harness/driving/|scripts/(route_driving_policy|vehicle_route_follower|vehicle_dynamics|player_vehicle|player_vehicle_controller)\.gd$|scenes/player_vehicle\.tscn$)'; then DRIVING_VISUAL_SCOPE="required"; fi
if ! printf '%s\n' "$CHANGED_FILES" | grep -Eq '(^|/)(geodot[^/]*|test_geodot[^/]*)'; then
  if [[ "$DRIVE_HUD_VISUAL_SCOPE" == "required" ]]; then
    printf 'PR_CHECK=VISUAL_REVIEW_TARGET scene=scenes/main.tscn reason=drive-hud\n'
    printf 'PR_CHECK=VISUAL_REVIEW_EXPECT window=production-main not=driving-harness\n'
    "$GODOT" --path "$WORKTREE" "$WORKTREE/scenes/main.tscn"; exit 0
  fi
  if [[ "$DRIVING_VISUAL_SCOPE" == "required" ]]; then
    printf 'PR_CHECK=VISUAL_REVIEW_TARGET scene=harness/driving/driving_harness.tscn reason=driving-feel\n'
    "$GODOT" --path "$WORKTREE" "$WORKTREE/harness/driving/driving_harness.tscn"; exit 0
  fi
  STANDARD_HOOK="$WORKTREE/tools/pr_check_standard.sh"
  if [[ ! -f "$STANDARD_HOOK" && -n "${GITHUB_WORKSPACE:-}" && -f "$GITHUB_WORKSPACE/tools/pr_check_standard.sh" ]]; then STANDARD_HOOK="$GITHUB_WORKSPACE/tools/pr_check_standard.sh"; fi
  if [[ ! -f "$STANDARD_HOOK" && -f "$(pwd)/tools/pr_check_standard.sh" ]]; then STANDARD_HOOK="$(pwd)/tools/pr_check_standard.sh"; fi
  if [[ -f "$STANDARD_HOOK" ]]; then exec bash "$STANDARD_HOOK"; fi
  exit 0
fi
run_stage(){ local stage="$1"; shift; local status=0; printf 'PR_CHECK=STAGE_BEGIN stage=%s pr=%s\n' "$stage" "$BRUR_PR_CHECK_PR"; "$@" || status=$?; if [[ $status -eq 0 ]]; then printf 'PR_CHECK=STAGE_OK stage=%s pr=%s\n' "$stage" "$BRUR_PR_CHECK_PR"; return 0; fi; printf 'PR_CHECK=STAGE_FAIL stage=%s pr=%s status=%s\n' "$stage" "$BRUR_PR_CHECK_PR" "$status" >&2; return "$status"; }
run_godot_test(){ local script="$1" marker="${2:-}" log status; log="$(mktemp "${TMPDIR:-/tmp}/brur-geodot-test.XXXXXX.log")"; set +e; "$GODOT" --headless --path "$WORKTREE" --script "$script" 2>&1 | tee "$log"; status=${PIPESTATUS[0]}; set -e; if [[ $status -ne 0 ]] || grep -Eq 'SCRIPT ERROR:|Failed to load script|ASSERT FAILED:|test failed:' "$log"; then rm -f "$log"; return 1; fi; if [[ -n "$marker" ]] && ! grep -Fq "$marker" "$log"; then rm -f "$log"; return 1; fi; rm -f "$log"; }
resolve_gpkg(){ local candidate; for candidate in "${BRUR_GEODOT_GPKG:-}" "$HOME/Dropbox/Code/brur-world/sweden-brur.gpkg"; do [[ -n "$candidate" && -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }; done; printf 'PR_CHECK=FAIL sweden-brur.gpkg not found\n' >&2; return 1; }
GPKG="$(resolve_gpkg)"; export BRUR_GEODOT_GPKG="$GPKG"; export BRUR_GEODOT_FAR_CACHE="$WORKTREE/.cache/geodot-far-cache.json"; printf 'PR_CHECK=GEODOT_GPKG path=%s\n' "$GPKG"
run_stage geodot-setup bash "$WORKTREE/tools/setup_geodot_poc.sh"; [[ -s "$BRUR_GEODOT_FAR_CACHE" ]] || exit 1
run_stage geodot-gpkg-contract "$PYTHON" "$WORKTREE/tools/check_geodot_gpkg.py" "$GPKG"; run_stage geodot-far-cache-contract "$PYTHON" "$WORKTREE/tests/test_geodot_far_cache.py"
for spec in 'geodot-hlod-residency|res://tests/godot/test_geodot_hlod_residency.gd|GEODOT_HLOD_RESIDENCY=PASS' 'geodot-renderer-contracts|res://tests/godot/test_geodot_renderer_contracts.gd|' 'geodot-runtime-bounds|res://tests/godot/test_geodot_runtime_bounds.gd|geodot runtime bounds: OK' 'geodot-lod-policy|res://tests/godot/test_geodot_lod_policy.gd|GEODOT_LOD_POLICY=PASS' 'geodot-tuning-contract|res://tests/godot/test_geodot_tuning_contract.gd|GEODOT_TUNING_CONTRACT=PASS' 'geodot-view-coverage|res://tests/godot/test_geodot_view_coverage.gd|' 'geodot-streaming-policy|res://tests/godot/test_geodot_streaming_policy.gd|' 'geodot-streaming-transition|res://tests/godot/test_geodot_streaming_transition.gd|' 'geodot-atomic-ownership|res://tests/godot/test_geodot_atomic_ownership.gd|GEODOT_ATOMIC_OWNERSHIP=PASS' 'geodot-photo-zoom|res://tests/godot/test_geodot_photo_zoom_contract.gd|GEODOT_PHOTO_ZOOM_CONTRACT=PASS' 'geodot-cell-geometry|res://tests/godot/test_geodot_cell_geometry.gd|' 'geodot-lod-continuity|res://tests/godot/test_geodot_lod_continuity.gd|' 'geodot-composition|res://tests/godot/test_geodot_composition_contract.gd|' 'geodot-failure-contract|res://tests/godot/test_geodot_failure_contract.gd|' 'geodot-real-data|res://tests/godot/test_geodot_real_data.gd|geodot real-data test: OK' 'geodot-fps-real-data|res://tests/godot/test_geodot_fps_real_data.gd|GeoDot Drive FPS real-data test: OK'; do IFS='|' read -r stage script marker <<< "$spec"; run_stage "$stage" run_godot_test "$script" "$marker"; done
printf 'PR_CHECK=GEODOT_OBJECTIVE_OK pr=%s clean_exit=true bounded_pipeline=true far_cache=true screen_space_lod=true frame_budget=true ram_budget=true no_holes=true single_owner=true warm_reverse_zoom=true\n' "$BRUR_PR_CHECK_PR"
if [[ "$MANUAL_REVIEW" != "required" ]]; then printf 'PR_CHECK=SKIP_VISUAL_REVIEW pr=%s reason=no-subjective-check-remains\n' "$BRUR_PR_CHECK_PR"; exit 0; fi
printf 'PR_CHECK=VISUAL_REVIEW pr=%s revision=%s\n' "$BRUR_PR_CHECK_PR" "$(git -C "$WORKTREE" rev-parse --short=12 HEAD)"
printf 'PR_CHECK=VISUAL_REVIEW_TARGET scene=scenes/geodot_poc.tscn reason=geodot-perceptual-tuning\n'
printf 'PR_CHECK=VISUAL_REVIEW_EXPECT window=geodot-poc not=editor\n'
printf 'PR_CHECK=VISUAL_REVIEW_INSTRUCTION inspect 500km->300km->75km->6km->3km and rapid reverse zoom; buildings must never leave an empty visible region and LOD ownership must not overlap/flicker\n'
BRUR_BUILD_REVISION="$(git -C "$WORKTREE" rev-parse --short=12 HEAD)" BRUR_GEODOT_GPKG="$GPKG" BRUR_GEODOT_FAR_CACHE="$BRUR_GEODOT_FAR_CACHE" "$GODOT" --path "$WORKTREE" "$WORKTREE/scenes/geodot_poc.tscn"
