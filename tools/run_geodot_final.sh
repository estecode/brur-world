#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-/Applications/Godot-4.7.2.app/Contents/MacOS/Godot}"
GPKG="${BRUR_GEODOT_GPKG:-$ROOT/sweden-brur.gpkg}"
[[ -x "$GODOT" ]] || { printf 'GEODOT_FINAL=FAIL Godot 4.7.2 not found at %s\n' "$GODOT" >&2; exit 69; }
[[ -f "$GPKG" ]] || { printf 'GEODOT_FINAL=FAIL sweden-brur.gpkg not found at %s\n' "$GPKG" >&2; exit 69; }
export BRUR_PR_CHECK_WORKTREE="$ROOT"
export BRUR_PR_CHECK_WORLD_DATA="$GPKG"
export BRUR_PR_CHECK_PR=343
export BRUR_PR_CHECK_MANUAL_REVIEW=required
export BRUR_PR_CHECK_CHANGED_FILES="scripts/geodot_poc_tuned_main.gd scripts/geodot_far_renderer.gd scripts/geodot_transition_policy.gd"
export BRUR_GEODOT_GPKG="$GPKG"
export PYTHON_BIN="${PYTHON_BIN:-$(command -v python3)}"
export GODOT_BIN="$GODOT"
exec bash "$ROOT/tools/pr_check_local.sh"
