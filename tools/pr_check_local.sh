#!/usr/bin/env bash
# PR-local dispatcher: keeps the standard project checks intact and adds GeoDot-specific real-data validation for #342.
set -euo pipefail

WORKTREE="${BRUR_PR_CHECK_WORKTREE:?}"
WORLD_DATA="${BRUR_PR_CHECK_WORLD_DATA:?}"
PYTHON="${PYTHON_BIN:?}"
GODOT="${GODOT_BIN:?}"
CHANGED_FILES="${BRUR_PR_CHECK_CHANGED_FILES:-}"
MANUAL_REVIEW="${BRUR_PR_CHECK_MANUAL_REVIEW:-none}"
BASE="$WORKTREE/tools/pr_check_local_standard.sh"

if ! printf '%s\n' "$CHANGED_FILES" | grep -Eq '^(scripts/geodot_|scenes/geodot_poc\.tscn$|tests/godot/test_geodot_|tools/(setup_geodot_poc\.sh|check_geodot_gpkg\.py)$|\.github/workflows/geodot-poc-validation\.yml$)'; then
  exec bash "$BASE"
fi

printf 'PR_CHECK=GEODOT_POC pr=%s\n' "${BRUR_PR_CHECK_PR:?}"
# Run every ordinary project-owned objective check, but suppress its generic main-scene visual launch.
BRUR_PR_CHECK_MANUAL_REVIEW=none BRUR_PR_CHECK_MANUAL_CHECK="" bash "$BASE"

resolve_gpkg() {
  if [[ -n "${BRUR_GEODOT_GPKG:-}" ]]; then
    [[ -f "$BRUR_GEODOT_GPKG" ]] || { printf 'PR_CHECK=FAIL BRUR_GEODOT_GPKG does not exist\n' >&2; return 1; }
    printf '%s\n' "$BRUR_GEODOT_GPKG"
    return 0
  fi
  local mapped_root candidate
  mapped_root="$(cd "$(dirname "$WORLD_DATA")" && pwd)"
  candidate="$mapped_root/sweden-brur.gpkg"
  if [[ -f "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  candidate="$(find "$mapped_root" "$(dirname "$mapped_root")" -maxdepth 2 -type f -name 'sweden-brur.gpkg' -print 2>/dev/null | head -n1)"
  [[ -n "$candidate" && -f "$candidate" ]] || {
    printf 'PR_CHECK=FAIL GeoDot POC requires sweden-brur.gpkg beside/near the mapped checkout or BRUR_GEODOT_GPKG\n' >&2
    return 1
  }
  printf '%s\n' "$candidate"
}

GPKG="$(resolve_gpkg)"
printf 'PR_CHECK=GEODOT_GPKG path=%s\n' "$GPKG"

bash "$WORKTREE/tools/setup_geodot_poc.sh"
"$PYTHON" "$WORKTREE/tools/check_geodot_gpkg.py" "$GPKG"

run_headless() {
  local script="$1" marker="$2" log status
  log="$(mktemp "${TMPDIR:-/tmp}/brur-geodot.XXXXXX.log")"
  set +e
  BRUR_GEODOT_GPKG="$GPKG" "$GODOT" --headless --path "$WORKTREE" --script "$script" 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  set -e
  if [[ $status -ne 0 ]] || grep -Eq 'SCRIPT ERROR:|Failed to load script|ASSERT FAILED:' "$log" || ! grep -Fq "$marker" "$log"; then
    printf 'PR_CHECK=FAIL GeoDot headless check failed: %s\n' "$script" >&2
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
}

run_headless res://tests/godot/test_geodot_renderer_contracts.gd 'geodot renderer contracts: OK'
run_headless res://tests/godot/test_geodot_real_data.gd 'geodot real-data test: OK'
printf 'PR_CHECK=GEODOT_OBJECTIVE_OK pr=%s\n' "$BRUR_PR_CHECK_PR"

if [[ "$MANUAL_REVIEW" == "required" ]]; then
  printf 'PR_CHECK=VISUAL_REVIEW_TARGET scene=scenes/geodot_poc.tscn renderer=geodot area=Lund\n'
  BRUR_GEODOT_GPKG="$GPKG" "$GODOT" --path "$WORKTREE" "$WORKTREE/scenes/geodot_poc.tscn"
else
  printf 'PR_CHECK=SKIP_GEODOT_VISUAL_REVIEW pr=%s reason=no-subjective-check-remains\n' "$BRUR_PR_CHECK_PR"
fi
