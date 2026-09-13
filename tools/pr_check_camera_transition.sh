#!/usr/bin/env bash
# Runs objective camera transition contracts, then opens production Main for the remaining cinematic-feel review.
# Dependencies: exact-PR worktree variables from run_pr_owned_check.sh and tools/test_camera_altitude.sh.
set -euo pipefail

WORKTREE="${BRUR_PR_CHECK_WORKTREE:?}"
GODOT="${GODOT_BIN:?}"

printf 'PR_CHECK=CHECK_CAMERA_TRANSITION_HEADLESS pr=%s scene=scenes/main.tscn presets=low,medium,high,max\n' "${BRUR_PR_CHECK_PR:?}"
GODOT_BIN="$GODOT" bash "$WORKTREE/tools/test_camera_altitude.sh"

printf 'PR_CHECK=VISUAL_REVIEW pr=%s revision=%s\n' "$BRUR_PR_CHECK_PR" "$(git -C "$WORKTREE" rev-parse --short=12 HEAD)"
printf 'PR_CHECK=VISUAL_REVIEW_TARGET scene=scenes/main.tscn reason=cinematic-map-to-manual-drive\n'
printf 'PR_CHECK=VISUAL_REVIEW_EXPECT window=production-main not=driving-harness\n'
printf 'PR_CHECK=VISUAL_REVIEW_INSTRUCTION in normal Brur World Main, try Manual Drive from both a close Map view and a very high Map view. Judge only whether the ~1.0 s move feels cinematic, smooth and intentional; timing, normalized final leg, final pose and below-world clearance are already headlessly asserted. Close Godot when finished.\n'
"$GODOT" --path "$WORKTREE" "$WORKTREE/scenes/main.tscn"
