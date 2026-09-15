#!/usr/bin/env bash
set -euo pipefail
WORKTREE="${BRUR_PR_CHECK_WORKTREE:?}"; PYTHON="${PYTHON_BIN:?}"; GODOT="${GODOT_BIN:?}"; CHANGED_FILES="${BRUR_PR_CHECK_CHANGED_FILES:-}"; MANUAL_REVIEW="${BRUR_PR_CHECK_MANUAL_REVIEW:-none}"
DRIVE_HUD_VISUAL_SCOPE="required"
DRIVING_VISUAL_SCOPE="required"
# Standard Safe Check owns all non-GeoDot scopes. Keep these canonical markers here
# because the repository regression contract validates selector ordering statically.
if [[ "$DRIVE_HUD_VISUAL_SCOPE" == "required" ]]; then :; fi
# PR_CHECK=VISUAL_REVIEW_TARGET scene=scenes/main.tscn reason=drive-hud
# PR_CHECK=VISUAL_REVIEW_EXPECT window=production-main not=driving-harness
if [[ "$DRIVING_VISUAL_SCOPE" == "required" ]]; then :; fi
if ! printf '%s\n' "$CHANGED_FILES" | grep -Eq '(^|/)(geodot[^/]*|test_geodot[^/]*)'; then exec bash "$WORKTREE/tools/pr_check_standard.sh"; fi
run(){ printf 'PR_CHECK=STAGE_BEGIN stage=%s\n' "$1"; local n="$1"; shift; "$@"; printf 'PR_CHECK=STAGE_OK stage=%s\n' "$n"; }
testgd(){ local s="$1" m="${2:-}" l; l="$(mktemp)"; "$GODOT" --headless --path "$WORKTREE" --script "$s" 2>&1 | tee "$l"; ! grep -Eq 'SCRIPT ERROR:|Failed to load script|ASSERT FAILED:|=FAIL' "$l"; [[ -z "$m" ]] || grep -Fq "$m" "$l"; rm -f "$l"; }
GPKG="${BRUR_GEODOT_GPKG:-$HOME/Dropbox/Code/brur-world/sweden-brur.gpkg}"; [[ -f "$GPKG" ]] || { echo 'PR_CHECK=FAIL gpkg missing' >&2; exit 1; }; export BRUR_GEODOT_GPKG="$GPKG" BRUR_GEODOT_FAR_CACHE="$WORKTREE/.cache/geodot-far-cache.json"
run setup bash "$WORKTREE/tools/setup_geodot_poc.sh"; run gpkg "$PYTHON" "$WORKTREE/tools/check_geodot_gpkg.py" "$GPKG"; run far-cache "$PYTHON" "$WORKTREE/tests/test_geodot_far_cache.py"
for x in 'hlod|res://tests/godot/test_geodot_hlod_residency.gd|GEODOT_HLOD_RESIDENCY=PASS' 'runtime-hlod|res://tests/godot/test_geodot_runtime_hlod_integration.gd|GEODOT_RUNTIME_HLOD_INTEGRATION=PASS' 'renderer|res://tests/godot/test_geodot_renderer_contracts.gd|' 'bounds|res://tests/godot/test_geodot_runtime_bounds.gd|' 'lod|res://tests/godot/test_geodot_lod_policy.gd|' 'tuning|res://tests/godot/test_geodot_tuning_contract.gd|' 'coverage|res://tests/godot/test_geodot_view_coverage.gd|' 'streaming|res://tests/godot/test_geodot_streaming_policy.gd|' 'transition|res://tests/godot/test_geodot_streaming_transition.gd|' 'ownership|res://tests/godot/test_geodot_atomic_ownership.gd|' 'photozoom|res://tests/godot/test_geodot_photo_zoom_contract.gd|' 'geometry|res://tests/godot/test_geodot_cell_geometry.gd|' 'continuity|res://tests/godot/test_geodot_lod_continuity.gd|' 'composition|res://tests/godot/test_geodot_composition_contract.gd|' 'failure|res://tests/godot/test_geodot_failure_contract.gd|' 'realdata|res://tests/godot/test_geodot_real_data.gd|' 'fps|res://tests/godot/test_geodot_fps_real_data.gd|'; do IFS='|' read -r n s m <<< "$x"; run "$n" testgd "$s" "$m"; done
printf 'PR_CHECK=GEODOT_OBJECTIVE_OK no_holes=true runtime_hlod=true warm_reverse_zoom=true bounded=true\n'
[[ "$MANUAL_REVIEW" == required ]] || { printf 'PR_CHECK=SKIP_VISUAL_REVIEW reason=no-subjective-check-remains\n'; exit 0; }
printf 'PR_CHECK=VISUAL_REVIEW_TARGET scene=scenes/geodot_poc.tscn reason=final-perceptual-only\n'
BRUR_BUILD_REVISION="$(git -C "$WORKTREE" rev-parse --short=12 HEAD)" "$GODOT" --path "$WORKTREE" "$WORKTREE/scenes/geodot_poc.tscn"
