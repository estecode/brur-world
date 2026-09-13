#!/usr/bin/env bash
# Runs one optional exact-PR local check while keeping machine status separate from human visual review.
# Dependencies: bash, gh/Python for stale-bootstrap review recovery, plus explicit worktree/runtime paths supplied by tools/pr_check.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKTREE="${1:-}"
PR="${2:-}"
WORLD_DATA="${3:-}"
PYTHON_BIN="${4:-}"
GODOT_BIN="${5:-}"

[[ -d "$WORKTREE" ]] || { printf 'PR_CHECK=FAIL invalid PR worktree\n' >&2; exit 66; }
[[ "$PR" =~ ^[1-9][0-9]*$ ]] || { printf 'PR_CHECK=FAIL invalid PR number for PR-owned check\n' >&2; exit 64; }
[[ -d "$WORLD_DATA" ]] || { printf 'PR_CHECK=FAIL invalid world_data path for PR-owned check\n' >&2; exit 66; }
[[ -n "$PYTHON_BIN" ]] || { printf 'PR_CHECK=FAIL missing Python path for PR-owned check\n' >&2; exit 69; }
[[ -n "$GODOT_BIN" ]] || { printf 'PR_CHECK=FAIL missing Godot path for PR-owned check\n' >&2; exit 69; }

HOOK="$WORKTREE/tools/pr_check_local.sh"
if [[ ! -f "$HOOK" ]]; then
  printf 'PR_CHECK=SKIP_PR_OWNED_OBJECTIVE_CHECKS pr=%s reason=no-hook\n' "$PR"
  exit 0
fi

STATUS_HELPER="$ROOT/tools/pr_check_status.py"
[[ -f "$STATUS_HELPER" ]] || { printf 'PR_CHECK=FAIL missing tools/pr_check_status.py\n' >&2; exit 66; }
WORKTREE_HEAD="$(git -C "$WORKTREE" rev-parse HEAD)"
WRAPPER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/brur-pr-check-godot.XXXXXX")"
SUCCESS_MARKER="$WRAPPER_DIR/objective-success-recorded"
GODOT_WRAPPER="$WRAPPER_DIR/godot"
cleanup() {
  rm -rf "$WRAPPER_DIR"
}
trap cleanup EXIT INT TERM

resolve_manual_review_contract() {
  case "${BRUR_PR_CHECK_MANUAL_REVIEW:-}" in
    required|none)
      return 0
      ;;
    "") ;;
    *)
      printf 'PR_CHECK=FAIL invalid BRUR_PR_CHECK_MANUAL_REVIEW=%s\n' "$BRUR_PR_CHECK_MANUAL_REVIEW" >&2
      return 70
      ;;
  esac

  command -v gh >/dev/null 2>&1 || {
    printf 'PR_CHECK=FAIL GitHub CLI (gh) is required to recover the PR merge decision\n' >&2
    return 69
  }
  local parser pr_body merge_decision
  parser="$ROOT/tools/pr_merge_decision.py"
  [[ -f "$parser" ]] || {
    printf 'PR_CHECK=FAIL current main has no tools/pr_merge_decision.py\n' >&2
    return 66
  }
  if ! pr_body="$(gh pr view "$PR" --repo estecode/brur-world --json body --jq .body)"; then
    printf 'PR_CHECK=FAIL unable to recover PR merge decision for stale bootstrap\n' >&2
    return 69
  fi
  if ! merge_decision="$(printf '%s' "$pr_body" | "$PYTHON_BIN" "$parser")"; then
    printf 'PR_CHECK=FAIL unable to parse authoritative PR merge decision for stale bootstrap\n' >&2
    return 70
  fi
  case "$merge_decision" in
    check)
      export BRUR_PR_CHECK_MANUAL_REVIEW=required
      printf 'PR_CHECK=MANUAL_REVIEW required pr=%s source=pr-merge-decision-fallback\n' "$PR"
      ;;
    merge)
      export BRUR_PR_CHECK_MANUAL_REVIEW=none
      printf 'PR_CHECK=MANUAL_REVIEW none pr=%s source=pr-merge-decision-fallback\n' "$PR"
      ;;
    block)
      printf 'PR_CHECK=FAIL PR merge decision is DO NOT MERGE; fix the blocker before running a human Safe Check\n' >&2
      return 78
      ;;
    *)
      printf 'PR_CHECK=FAIL invalid parsed merge decision: %s\n' "$merge_decision" >&2
      return 70
      ;;
  esac
}

cat > "$GODOT_WRAPPER" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  if [[ "$arg" == "--headless" ]]; then
    exec "$BRUR_PR_CHECK_REAL_GODOT" "$@"
  fi
done

if [[ ! -f "$BRUR_PR_CHECK_SUCCESS_MARKER" ]]; then
  "$BRUR_PR_CHECK_PYTHON" "$BRUR_PR_CHECK_STATUS_HELPER" record \
    --pr "$BRUR_PR_CHECK_PR" \
    --sha "$BRUR_PR_CHECK_HEAD" \
    --state success \
    --stage objective-checks-complete
  : > "$BRUR_PR_CHECK_SUCCESS_MARKER"
  printf 'PR_CHECK=STATUS success pr=%s revision=%s stage=before-visual-review\n' \
    "$BRUR_PR_CHECK_PR" "${BRUR_PR_CHECK_HEAD:0:12}"
fi

set +e
"$BRUR_PR_CHECK_REAL_GODOT" "$@"
visual_status=$?
set -e
if [[ "$visual_status" -ne 0 ]]; then
  printf 'PR_CHECK=VISUAL_REVIEW_WARNING Godot exited status=%s after objective success\n' "$visual_status" >&2
fi
exit 0
WRAPPER
chmod +x "$GODOT_WRAPPER"

run_owned_hook() {
  resolve_manual_review_contract
  printf 'PR_CHECK=RUN_PR_OWNED_OBJECTIVE_CHECKS pr=%s hook=tools/pr_check_local.sh\n' "$PR"
  (
    cd "$WORKTREE"
    BRUR_PR_CHECK_PR="$PR" \
    BRUR_PR_CHECK_WORKTREE="$WORKTREE" \
    BRUR_PR_CHECK_WORLD_DATA="$WORLD_DATA" \
    BRUR_PR_CHECK_HEAD="$WORKTREE_HEAD" \
    BRUR_PR_CHECK_MANUAL_REVIEW="$BRUR_PR_CHECK_MANUAL_REVIEW" \
    BRUR_PR_CHECK_REAL_GODOT="$GODOT_BIN" \
    BRUR_PR_CHECK_SUCCESS_MARKER="$SUCCESS_MARKER" \
    BRUR_PR_CHECK_STATUS_HELPER="$STATUS_HELPER" \
    BRUR_PR_CHECK_PYTHON="$PYTHON_BIN" \
    PYTHON_BIN="$PYTHON_BIN" \
    GODOT_BIN="$GODOT_WRAPPER" \
    bash "$HOOK"
  )
}

# New mapped checkouts are already fully tee'd by pr_check_entry.sh. Older mapped
# checkouts still bootstrap current main before this runner, so recover the stable
# mapped root through the world_data symlink and persist the objective hook here.
if [[ -n "${BRUR_PR_CHECK_LOG_PATH:-}" ]]; then
  run_owned_hook
  exit $?
fi

MAPPED_ROOT="${BRUR_PR_CHECK_MAPPED_ROOT:-}"
if [[ -z "$MAPPED_ROOT" ]]; then
  MAPPED_ROOT="$("$PYTHON_BIN" - "$WORLD_DATA" <<'PY'
import os
import sys
print(os.path.dirname(os.path.realpath(sys.argv[1])))
PY
)"
fi
LOG_DIR="$MAPPED_ROOT/safecommand-logs"
LOG_PATH="$LOG_DIR/pr-check-${PR}.log"
mkdir -p "$LOG_DIR"
: > "$LOG_PATH"
printf 'PR_CHECK=LOG_FALLBACK path=%s reason=stale-mapped-entrypoint\n' "$LOG_PATH" | tee -a "$LOG_PATH"
set +e
run_owned_hook 2>&1 | tee -a "$LOG_PATH"
status=${PIPESTATUS[0]}
set -e
printf 'PR_CHECK=LOG_FALLBACK_FINISHED pr=%s exit=%s path=%s\n' "$PR" "$status" "$LOG_PATH" | tee -a "$LOG_PATH"
exit "$status"
