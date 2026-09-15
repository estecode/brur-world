#!/usr/bin/env bash
# Dispatches #342 GeoDot validation while preserving the standard PR-owned check for all other scopes.
set -euo pipefail
WORKTREE="${BRUR_PR_CHECK_WORKTREE:?}"; WORLD_DATA="${BRUR_PR_CHECK_WORLD_DATA:?}"; PYTHON="${PYTHON_BIN:?}"; GODOT="${GODOT_BIN:?}"
MANUAL_REVIEW="${BRUR_PR_CHECK_MANUAL_REVIEW:-none}"; CHANGED_FILES="${BRUR_PR_CHECK_CHANGED_FILES:-}"
DRIVE_HUD_VISUAL_SCOPE="skip"; DRIVING_VISUAL_SCOPE="skip"
if printf '%s\n' "$CHANGED_FILES" | grep -Eq '^scripts/(drive_hud|drive_hud_adapter|speed_limit_sign|road_speed_limit_query)\.gd$|^scenes/main\.tscn$'; then DRIVE_HUD_VISUAL_SCOPE="required"; fi
if printf '%s\n' "$CHANGED_FILES" | grep -Eq '^(harness/driving/|scripts/(route_driving_policy|vehicle_route_follower|vehicle_dynamics|player_vehicle|player_vehicle_controller)\.gd$|scenes/player_vehicle\.tscn$)'; then DRIVING_VISUAL_SCOPE="required"; fi
if ! printf '%s\n' "$CHANGED_FILES" | grep -Eq '(^|/)(geodot[^/]*|test_geodot[^/]*)'; then
  STANDARD_HOOK="$WORKTREE/tools/pr_check_standard.sh"
  if [[ ! -f "$STANDARD_HOOK" && -n "${GITHUB_WORKSPACE:-}" && -f "$GITHUB_WORKSPACE/tools/pr_check_standard.sh" ]]; then STANDARD_HOOK="$GITHUB_WORKSPACE/tools/pr_check_standard.sh"; fi
  if [[ ! -f "$STANDARD_HOOK" && -f "$(pwd)/tools/pr_check_standard.sh" ]]; then STANDARD_HOOK="$(pwd)/tools/pr_check_standard.sh"; fi
  if [[ -f "$STANDARD_HOOK" ]]; then exec bash "$STANDARD_HOOK"; fi
  if [[ "$DRIVE_HUD_VISUAL_SCOPE" == "required" ]]; then printf 'PR_CHECK=VISUAL_REVIEW_TARGET scene=scenes/main.tscn reason=drive-hud\n'; printf 'PR_CHECK=VISUAL_REVIEW_EXPECT window=production-main not=driving-harness\n'; "$GODOT" --path "$WORKTREE" "$WORKTREE/scenes/main.tscn"; exit 0; fi
  if [[ "$DRIVING_VISUAL_SCOPE" == "required" ]]; then "$GODOT" --path "$WORKTREE" "$WORKTREE/harness/driving/driving_harness.tscn"; exit 0; fi
  exit 0
fi
run_stage(){ local stage="$1"; shift; local status=0; printf 'PR_CHECK=STAGE_BEGIN stage=%s pr=%s\n' "$stage" "$BRUR_PR_CHECK_PR"; "$@" || status=$?; if [[ $status -eq 0 ]]; then printf 'PR_CHECK=STAGE_OK stage=%s pr=%s\n' "$stage" "$BRUR_PR_CHECK_PR"; return 0; fi; printf 'PR_CHECK=STAGE_FAIL stage=%s pr=%s status=%s\n' "$stage" "$BRUR_PR_CHECK_PR" "$status" >&2; return "$status"; }
run_godot_test(){ local script="$1" marker="${2:-}" log status; log="$(mktemp "${TMPDIR:-/tmp}/brur-geodot-test.XXXXXX.log")"; set +e; "$GODOT" --headless --path "$WORKTREE" --script "$script" 2>&1 | tee "$log"; status=${PIPESTATUS[0]}; set -e; if [[ $status -ne 0 ]] || grep -Eq 'SCRIPT ERROR:|Failed to load script|ASSERT FAILED:|test failed:' "$log"; then printf 'PR_CHECK=FAIL Godot failed clean-exit test %s status=%s\n' "$script" "$status" >&2; rm -f "$log"; return 1; fi; if [[ -n "$marker" ]] && ! grep -Fq "$marker" "$log"; then printf 'PR_CHECK=FAIL missing completion marker for %s: %s\n' "$script" "$marker" >&2; rm -f "$log"; return 1; fi; rm -f "$log"; }
resolve_gpkg(){ local candidate; for candidate in "${BRUR_GEODOT_GPKG:-}" "$WORLD_DATA/../sweden-brur.gpkg" "$(dirname "$WORLD_DATA")/sweden-brur.gpkg" "$HOME/Dropbox/Code/brur-world/sweden-brur.gpkg"; do [[ -n "$candidate" && -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }; done; candidate="$(find "$(dirname "$WORLD_DATA")" "$HOME/Dropbox/Code" -maxdepth 4 -type f -name 'sweden-brur.gpkg' -print 2>/dev/null | head -n1 || true)"; [[ -n "$candidate" ]] || { printf 'PR_CHECK=FAIL sweden-brur.gpkg not found\n' >&2; return 1; }; printf '%s\n' "$candidate"; }
GPKG="$(resolve_gpkg)"; printf 'PR_CHECK=GEODOT_GPKG path=%s\n' "$GPKG"
run_stage geodot-setup bash "$WORKTREE/tools/setup_geodot_poc.sh"
run_stage geodot-gpkg-contract "$PYTHON" "$WORKTREE/tools/check_geodot_gpkg.py" "$GPKG"
export BRUR_GEODOT_GPKG="$GPKG"
run_stage geodot-renderer-contracts run_godot_test res://tests/godot/test_geodot_renderer_contracts.gd
run_stage geodot-view-coverage run_godot_test res://tests/godot/test_geodot_view_coverage.gd
run_stage geodot-streaming-policy run_godot_test res://tests/godot/test_geodot_streaming_policy.gd
run_stage geodot-streaming-transition run_godot_test res://tests/godot/test_geodot_streaming_transition.gd
run_stage geodot-cell-geometry run_godot_test res://tests/godot/test_geodot_cell_geometry.gd
run_stage geodot-lod-continuity run_godot_test res://tests/godot/test_geodot_lod_continuity.gd
run_stage geodot-composition run_godot_test res://tests/godot/test_geodot_composition_contract.gd
run_stage geodot-failure-contract run_godot_test res://tests/godot/test_geodot_failure_contract.gd
run_stage geodot-real-data run_godot_test res://tests/godot/test_geodot_real_data.gd 'geodot real-data test: OK'
printf 'PR_CHECK=GEODOT_OBJECTIVE_OK pr=%s clean_exit=true\n' "$BRUR_PR_CHECK_PR"
if [[ "$MANUAL_REVIEW" != "required" ]]; then printf 'PR_CHECK=SKIP_VISUAL_REVIEW pr=%s reason=no-subjective-check-remains\n' "$BRUR_PR_CHECK_PR"; exit 0; fi
printf 'PR_CHECK=VISUAL_REVIEW pr=%s revision=%s\n' "$BRUR_PR_CHECK_PR" "$(git -C "$WORKTREE" rev-parse --short=12 HEAD)"; printf 'PR_CHECK=VISUAL_REVIEW_TARGET scene=scenes/geodot_poc.tscn reason=geodot-perceptual-lund\n'; printf 'PR_CHECK=VISUAL_REVIEW_EXPECT window=production-brur-with-geodot not=editor\n'; printf 'PR_CHECK=VISUAL_REVIEW_INSTRUCTION inspect only density, scale, smoothness and seamless pan/zoom/Drive around Lund; objective GeoDot checks already passed cleanly in this same Safe Check\n'
BRUR_GEODOT_GPKG="$GPKG" "$GODOT" --path "$WORKTREE" "$WORKTREE/scenes/geodot_poc.tscn"
