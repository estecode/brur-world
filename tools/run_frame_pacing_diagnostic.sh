#!/usr/bin/env bash
# Runs objective local frame-pacing measurements and persists them to the diagnostic PR.
# Dependencies: exact PR worktree, local Godot, authenticated GitHub CLI, and production world_data linked by pr_check.sh.
set -euo pipefail

WORKTREE="${BRUR_PR_CHECK_WORKTREE:?}"
GODOT="${GODOT_BIN:?}"
PR="${BRUR_PR_CHECK_PR:?}"
LOG="$(mktemp "${TMPDIR:-/tmp}/brur-frame-pacing.XXXXXX.log")"
trap 'rm -f "$LOG"' EXIT

run_mode() {
  local mode="$1"
  printf 'PR_CHECK=FRAME_PACING mode=%s\n' "$mode"
  BRUR_PERF_MODE="$mode" "$GODOT" --path "$WORKTREE" --scene res://harness/perf_diagnostic/frame_pacing.tscn 2>&1 | tee -a "$LOG"
}

run_mode light
run_mode main

RESULTS="$(grep '^FRAME_PACING ' "$LOG" || true)"
[[ -n "$RESULTS" ]] || { printf 'PR_CHECK=FAIL frame pacing diagnostic produced no measurements\n' >&2; exit 1; }

if command -v gh >/dev/null 2>&1; then
  BODY_FILE="$(mktemp "${TMPDIR:-/tmp}/brur-frame-pacing-comment.XXXXXX.md")"
  {
    printf '### Automated frame-pacing diagnosis for PR #%s\n\n' "$PR"
    printf 'No manual FPS judgment was used. The exact PR revision measured both a lightweight window and production main on the local Mac.\n\n```text\n'
    printf '%s\n' "$RESULTS"
    printf '```\n'
  } > "$BODY_FILE"
  gh pr comment "$PR" --repo estecode/brur-world --body-file "$BODY_FILE"
  rm -f "$BODY_FILE"
fi

# pr_check.sh launches the project once more after objective checks. Redirect that
# final launch to an immediate-exit scene so this diagnostic needs no human step.
python_bin="${PYTHON_BIN:?}"
"$python_bin" - "$WORKTREE/project.godot" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = 'run/main_scene="res://scenes/main.tscn"'
new = 'run/main_scene="res://harness/perf_diagnostic/auto_quit.tscn"'
if old not in text:
    raise SystemExit("PR_CHECK=FAIL unable to redirect final diagnostic launch")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY

printf 'PR_CHECK=FRAME_PACING_COMPLETE pr=%s\n' "$PR"
