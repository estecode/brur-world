#!/usr/bin/env bash
# Boots the PR-check launcher from current origin/main without mutating the mapped checkout.
set -euo pipefail
PR="${1:-}"
[[ "$PR" =~ ^[1-9][0-9]*$ ]] || { printf 'PR_CHECK=FAIL invalid PR number\n' >&2; exit 64; }
ROOT="$(git rev-parse --show-toplevel)"
LOG_DIR="$ROOT/safecommand-logs"; LOG_PATH="$LOG_DIR/pr-check-${PR}.log"
mkdir -p "$LOG_DIR"; : > "$LOG_PATH"
export BRUR_PR_CHECK_MAPPED_ROOT="$ROOT" BRUR_PR_CHECK_LOG_PATH="$LOG_PATH"
exec > >(tee -a "$LOG_PATH") 2>&1
printf 'PR_CHECK=LOG path=%s\n' "$LOG_PATH"
printf 'PR_CHECK=LOG_STARTED pr=%s started_at=%s\n' "$PR" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
[[ -d "$ROOT/world_data" ]] || { printf 'PR_CHECK=FAIL missing %s/world_data\n' "$ROOT" >&2; exit 66; }
command -v gh >/dev/null 2>&1 || { printf 'PR_CHECK=FAIL GitHub CLI (gh) is required\n' >&2; exit 69; }
LAUNCHER_TMP="$(mktemp -d "${TMPDIR:-/tmp}/brur-world-pr-check-main.XXXXXX")"; ADDED=0
cleanup() { status=$?; trap - EXIT INT TERM; [[ "$ADDED" -eq 1 ]] && git -C "$ROOT" worktree remove --force "$LAUNCHER_TMP" >/dev/null 2>&1 || true; rm -rf "$LAUNCHER_TMP"; printf 'PR_CHECK=LOG_FINISHED pr=%s exit=%s finished_at=%s path=%s\n' "$PR" "$status" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$LOG_PATH"; exit "$status"; }
trap cleanup EXIT INT TERM
printf 'PR_CHECK=BOOTSTRAP fetch-current-main\n'
git -C "$ROOT" fetch --quiet origin main:refs/remotes/origin/main || { printf 'PR_CHECK=FAIL unable to fetch current origin/main launcher\n' >&2; exit 69; }
MAIN_HEAD="$(git -C "$ROOT" rev-parse refs/remotes/origin/main)"
WORKING_BRANCH="$(git -C "$ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || printf 'DETACHED@%s' "$(git -C "$ROOT" rev-parse --short=12 HEAD)")"
export BRUR_PR_CHECK_MAIN_SHA="$MAIN_HEAD" BRUR_PR_CHECK_WORKING_BRANCH="$WORKING_BRANCH"
rm -rf "$LAUNCHER_TMP"
git -C "$ROOT" worktree add --quiet --detach "$LAUNCHER_TMP" "$MAIN_HEAD" || { printf 'PR_CHECK=FAIL unable to prepare current main launcher worktree\n' >&2; exit 70; }
ADDED=1
[[ -f "$LAUNCHER_TMP/tools/pr_check.sh" ]] || { printf 'PR_CHECK=FAIL current origin/main has no tools/pr_check.sh\n' >&2; exit 66; }
[[ -f "$LAUNCHER_TMP/tools/pr_merge_decision.py" ]] || { printf 'PR_CHECK=FAIL current origin/main has no tools/pr_merge_decision.py\n' >&2; exit 66; }
if [[ -x "$ROOT/.venv/bin/python" ]]; then META_PYTHON="$ROOT/.venv/bin/python"; elif command -v python3 >/dev/null 2>&1; then META_PYTHON="$(command -v python3)"; else printf 'PR_CHECK=FAIL Python 3 not found\n' >&2; exit 69; fi
PR_BODY="$(gh pr view "$PR" --repo estecode/brur-world --json body --jq .body)" || { printf 'PR_CHECK=FAIL unable to read PR merge decision\n' >&2; exit 69; }
MERGE_DECISION="$(printf '%s' "$PR_BODY" | "$META_PYTHON" "$LAUNCHER_TMP/tools/pr_merge_decision.py")" || { printf 'PR_CHECK=FAIL unable to parse authoritative PR merge decision\n' >&2; exit 70; }
case "$MERGE_DECISION" in
 check) MANUAL_CHECK="$(printf '%s' "$PR_BODY" | "$META_PYTHON" "$LAUNCHER_TMP/tools/pr_merge_decision.py" --field check)" || { printf 'PR_CHECK=FAIL unable to parse authoritative PR manual CHECK\n' >&2; exit 70; }; export BRUR_PR_CHECK_MANUAL_REVIEW=required BRUR_PR_CHECK_MANUAL_CHECK="$MANUAL_CHECK"; printf 'PR_CHECK=MANUAL_REVIEW required pr=%s source=pr-merge-decision\nPR_CHECK=MANUAL_CHECK %s\n' "$PR" "$MANUAL_CHECK" ;;
 merge) export BRUR_PR_CHECK_MANUAL_REVIEW=none BRUR_PR_CHECK_MANUAL_CHECK=""; printf 'PR_CHECK=MANUAL_REVIEW none pr=%s source=pr-merge-decision\n' "$PR" ;;
 block) printf 'PR_CHECK=FAIL PR merge decision is DO NOT MERGE; fix the blocker before running a human Safe Check\n' >&2; exit 78 ;;
 *) printf 'PR_CHECK=FAIL invalid parsed merge decision: %s\n' "$MERGE_DECISION" >&2; exit 70 ;;
esac
rm -rf "$LAUNCHER_TMP/world_data"; ln -s "$ROOT/world_data" "$LAUNCHER_TMP/world_data"
[[ -d "$ROOT/.venv" && ! -e "$LAUNCHER_TMP/.venv" ]] && ln -s "$ROOT/.venv" "$LAUNCHER_TMP/.venv" || true
if [[ -z "${BRUR_WORLD_PBF:-}" ]]; then data_dir="$(cd "$ROOT/.." && pwd)/data"; if [[ -d "$data_dir" ]]; then candidate="$(find "$data_dir" -maxdepth 1 -type f -name 'sweden-*.osm.pbf' -print 2>/dev/null | LC_ALL=C sort | tail -n 1)"; [[ -n "$candidate" ]] && export BRUR_WORLD_PBF="$candidate" || true; fi; fi
printf 'PR_CHECK=BOOTSTRAP main=%s mapped=%s working_branch=%s\n' "${MAIN_HEAD:0:12}" "$ROOT" "$WORKING_BRANCH"
cd "$LAUNCHER_TMP"
bash tools/pr_check.sh "$PR"
