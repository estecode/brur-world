#!/usr/bin/env bash
# Runs one optional exact-PR local check while keeping machine status separate from human visual review.
# Dependencies: bash plus explicit worktree/runtime paths supplied by tools/pr_check.sh.
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

printf 'PR_CHECK=RUN_PR_OWNED_OBJECTIVE_CHECKS pr=%s hook=tools/pr_check_local.sh\n' "$PR"
(
  cd "$WORKTREE"
  BRUR_PR_CHECK_PR="$PR" \
  BRUR_PR_CHECK_WORKTREE="$WORKTREE" \
  BRUR_PR_CHECK_WORLD_DATA="$WORLD_DATA" \
  BRUR_PR_CHECK_HEAD="$WORKTREE_HEAD" \
  BRUR_PR_CHECK_REAL_GODOT="$GODOT_BIN" \
  BRUR_PR_CHECK_SUCCESS_MARKER="$SUCCESS_MARKER" \
  BRUR_PR_CHECK_STATUS_HELPER="$STATUS_HELPER" \
  BRUR_PR_CHECK_PYTHON="$PYTHON_BIN" \
  PYTHON_BIN="$PYTHON_BIN" \
  GODOT_BIN="$GODOT_WRAPPER" \
  bash "$HOOK"
)
