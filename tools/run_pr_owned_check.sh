#!/usr/bin/env bash
# Runs one optional exact-PR local check while keeping machine status separate from human visual review.
# Non-headless Godot launches requested by a PR hook are deferred until every objective hook step has returned green.
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
STATUS_HELPER="$ROOT/tools/pr_check_status.py"
[[ -f "$STATUS_HELPER" ]] || { printf 'PR_CHECK=FAIL missing tools/pr_check_status.py\n' >&2; exit 66; }
WORKTREE_HEAD="$(git -C "$WORKTREE" rev-parse HEAD)"
WRAPPER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/brur-pr-check-godot.XXXXXX")"
SUCCESS_MARKER="$WRAPPER_DIR/objective-success-recorded"
VISUAL_REQUEST="$WRAPPER_DIR/visual-request"
GODOT_WRAPPER="$WRAPPER_DIR/godot"
cleanup() { rm -rf "$WRAPPER_DIR"; }
trap cleanup EXIT INT TERM

resolve_manual_review_contract() {
  case "${BRUR_PR_CHECK_MANUAL_REVIEW:-}" in
    required) [[ -n "${BRUR_PR_CHECK_MANUAL_CHECK:-}" ]] || { printf 'PR_CHECK=FAIL manual review is required but BRUR_PR_CHECK_MANUAL_CHECK is empty\n' >&2; return 70; }; return 0 ;;
    none) export BRUR_PR_CHECK_MANUAL_CHECK=""; return 0 ;;
    "") ;;
    *) printf 'PR_CHECK=FAIL invalid BRUR_PR_CHECK_MANUAL_REVIEW=%s\n' "$BRUR_PR_CHECK_MANUAL_REVIEW" >&2; return 70 ;;
  esac
  command -v gh >/dev/null 2>&1 || { printf 'PR_CHECK=FAIL GitHub CLI (gh) is required to recover the PR merge decision\n' >&2; return 69; }
  local parser pr_body merge_decision manual_check
  parser="$ROOT/tools/pr_merge_decision.py"
  [[ -f "$parser" ]] || { printf 'PR_CHECK=FAIL current main has no tools/pr_merge_decision.py\n' >&2; return 66; }
  pr_body="$(gh pr view "$PR" --repo estecode/brur-world --json body --jq .body)" || { printf 'PR_CHECK=FAIL unable to recover PR merge decision for stale bootstrap\n' >&2; return 69; }
  merge_decision="$(printf '%s' "$pr_body" | "$PYTHON_BIN" "$parser")" || { printf 'PR_CHECK=FAIL unable to parse authoritative PR merge decision for stale bootstrap\n' >&2; return 70; }
  case "$merge_decision" in
    check)
      manual_check="$(printf '%s' "$pr_body" | "$PYTHON_BIN" "$parser" --field check)" || { printf 'PR_CHECK=FAIL unable to parse authoritative PR manual CHECK for stale bootstrap\n' >&2; return 70; }
      export BRUR_PR_CHECK_MANUAL_REVIEW=required BRUR_PR_CHECK_MANUAL_CHECK="$manual_check"
      printf 'PR_CHECK=MANUAL_REVIEW required pr=%s source=pr-merge-decision-fallback\n' "$PR"
      printf 'PR_CHECK=MANUAL_CHECK %s\n' "$manual_check" ;;
    merge) export BRUR_PR_CHECK_MANUAL_REVIEW=none BRUR_PR_CHECK_MANUAL_CHECK=""; printf 'PR_CHECK=MANUAL_REVIEW none pr=%s source=pr-merge-decision-fallback\n' "$PR" ;;
    block) printf 'PR_CHECK=FAIL PR merge decision is DO NOT MERGE; fix the blocker before running a human Safe Check\n' >&2; return 78 ;;
    *) printf 'PR_CHECK=FAIL invalid parsed merge decision: %s\n' "$merge_decision" >&2; return 70 ;;
  esac
}

cat > "$GODOT_WRAPPER" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  [[ "$arg" != "--headless" ]] || exec "$BRUR_PR_CHECK_REAL_GODOT" "$@"
done
printf '%s\0' "$@" > "$BRUR_PR_CHECK_VISUAL_REQUEST"
printf 'PR_CHECK=VISUAL_REVIEW_DEFERRED pr=%s reason=objective-chain-not-complete\n' "$BRUR_PR_CHECK_PR"
exit 0
WRAPPER
chmod +x "$GODOT_WRAPPER"

record_objective_success() {
  [[ ! -f "$SUCCESS_MARKER" ]] || return 0
  "$PYTHON_BIN" "$STATUS_HELPER" record --pr "$PR" --sha "$WORKTREE_HEAD" --state success --stage objective-checks-complete
  : > "$SUCCESS_MARKER"
  printf 'PR_CHECK=STATUS success pr=%s revision=%s stage=objective-checks-complete\n' "$PR" "${WORKTREE_HEAD:0:12}"
}

read_visual_request() {
  VISUAL_ARGS=()
  [[ -f "$VISUAL_REQUEST" ]] || return 1
  while IFS= read -r -d '' arg; do VISUAL_ARGS+=("$arg"); done < "$VISUAL_REQUEST"
  return 0
}

launch_deferred_visual() {
  local -a args=("$@")
  set +e
  "$GODOT_BIN" "${args[@]}"
  local visual_status=$?
  set -e
  if [[ "$visual_status" -ne 0 ]]; then
    printf 'PR_CHECK=VISUAL_REVIEW_WARNING Godot exited status=%s after objective success\n' "$visual_status" >&2
  fi
}

complete_objectives_and_gate_handoff() {
  local -a VISUAL_ARGS=()
  if [[ "$BRUR_PR_CHECK_MANUAL_REVIEW" == "required" ]]; then
    [[ -n "${BRUR_PR_CHECK_MANUAL_CHECK:-}" ]] || { printf 'PR_CHECK=FAIL handoff gate reached without concrete manual CHECK\n' >&2; return 70; }
    record_objective_success
    if ! read_visual_request; then
      [[ -f "$WORKTREE/scenes/main.tscn" ]] || { printf 'PR_CHECK=FAIL manual review is required but PR revision has no scenes/main.tscn\n' >&2; return 66; }
      VISUAL_ARGS=(--path "$WORKTREE" "$WORKTREE/scenes/main.tscn")
      printf 'PR_CHECK=FORCE_VISUAL_REVIEW pr=%s reason=authoritative-manual-review-not-launched-by-pr-hook\n' "$PR"
      printf 'PR_CHECK=VISUAL_REVIEW_TARGET scene=scenes/main.tscn reason=manual-review-contract-fallback\n'
      printf 'PR_CHECK=VISUAL_REVIEW_EXPECT window=production-main not=editor\n'
    fi
    printf 'PR_CHECK=HANDOFF_READY pr=%s revision=%s objective_checks=success\n' "$PR" "${WORKTREE_HEAD:0:12}"
    printf '\nSAFE CHECK — MANUAL CHECK REQUIRED\n'
    printf 'Inspect exactly this: %s\n' "$BRUR_PR_CHECK_MANUAL_CHECK"
    printf 'PASS: close Godot, then report: test ok #%s\n' "$PR"
    printf 'FAIL: close Godot, then report: test fail #%s — <what failed>\n\n' "$PR"
    launch_deferred_visual "${VISUAL_ARGS[@]}"
    return 0
  fi

  if read_visual_request; then
    # Preserve legacy close-only visual launches, but only after the complete hook
    # has returned green. This is not a human verification handoff.
    record_objective_success
    printf 'PR_CHECK=HANDOFF_READY pr=%s revision=%s manual=none objective_checks=success\n' "$PR" "${WORKTREE_HEAD:0:12}"
    printf '\nSAFE CHECK — NO MANUAL CHECK REQUIRED\n'
    printf 'No manual check is required. You do not need to test or inspect anything in Godot — just close Godot so Safe Check can finish.\n\n'
    launch_deferred_visual "${VISUAL_ARGS[@]}"
  else
    printf 'PR_CHECK=HANDOFF_READY pr=%s revision=%s manual=none\n' "$PR" "${WORKTREE_HEAD:0:12}"
  fi
}

run_owned_hook() {
  resolve_manual_review_contract
  rm -f "$SUCCESS_MARKER" "$VISUAL_REQUEST"
  if [[ -f "$HOOK" ]]; then
    printf 'PR_CHECK=RUN_PR_OWNED_OBJECTIVE_CHECKS pr=%s hook=tools/pr_check_local.sh\n' "$PR"
    local hook_status
    set +e
    (
      cd "$WORKTREE"
      BRUR_PR_CHECK_PR="$PR" BRUR_PR_CHECK_WORKTREE="$WORKTREE" BRUR_PR_CHECK_WORLD_DATA="$WORLD_DATA" \
      BRUR_PR_CHECK_HEAD="$WORKTREE_HEAD" BRUR_PR_CHECK_MANUAL_REVIEW="$BRUR_PR_CHECK_MANUAL_REVIEW" \
      BRUR_PR_CHECK_MANUAL_CHECK="${BRUR_PR_CHECK_MANUAL_CHECK:-}" BRUR_PR_CHECK_REAL_GODOT="$GODOT_BIN" \
      BRUR_PR_CHECK_VISUAL_REQUEST="$VISUAL_REQUEST" PYTHON_BIN="$PYTHON_BIN" GODOT_BIN="$GODOT_WRAPPER" bash "$HOOK"
    )
    hook_status=$?
    set -e
    if [[ "$hook_status" -ne 0 ]]; then
      rm -f "$VISUAL_REQUEST"
      printf 'PR_CHECK=HANDOFF_BLOCKED pr=%s reason=objective-hook-failed status=%s\n' "$PR" "$hook_status" >&2
      return "$hook_status"
    fi
  else
    printf 'PR_CHECK=SKIP_PR_OWNED_OBJECTIVE_CHECKS pr=%s reason=no-hook\n' "$PR"
  fi
  complete_objectives_and_gate_handoff
}

if [[ -n "${BRUR_PR_CHECK_LOG_PATH:-}" ]]; then run_owned_hook; exit $?; fi
MAPPED_ROOT="${BRUR_PR_CHECK_MAPPED_ROOT:-}"
if [[ -z "$MAPPED_ROOT" ]]; then
  MAPPED_ROOT="$("$PYTHON_BIN" - "$WORLD_DATA" <<'PY'
import os, sys
print(os.path.dirname(os.path.realpath(sys.argv[1])))
PY
)"
fi
LOG_DIR="$MAPPED_ROOT/safecommand-logs"
LOG_PATH="$LOG_DIR/pr-check-${PR}.log"
mkdir -p "$LOG_DIR"; : > "$LOG_PATH"
printf 'PR_CHECK=LOG_FALLBACK path=%s reason=stale-mapped-entrypoint\n' "$LOG_PATH" | tee -a "$LOG_PATH"
set +e
run_owned_hook 2>&1 | tee -a "$LOG_PATH"
status=${PIPESTATUS[0]}
set -e
printf 'PR_CHECK=LOG_FALLBACK_FINISHED pr=%s exit=%s path=%s\n' "$PR" "$status" "$LOG_PATH" | tee -a "$LOG_PATH"
exit "$status"
