#!/usr/bin/env bash
# Verifies exact-PR hooks fail closed and machine success is persisted before optional human Godot review.
# Dependencies: bash, git, mktemp, grep, tools/run_pr_owned_check.sh, tools/pr_check.sh, and tests/test_pr_check_entry.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/brur-pr-owned-check-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

WORKTREE="$TMP/worktree"
WORLD_DATA="$TMP/world_data"
mkdir -p "$WORKTREE/tools" "$WORLD_DATA"
git -C "$WORKTREE" init -q
git -C "$WORKTREE" config user.name test
git -C "$WORKTREE" config user.email test@example.invalid
printf 'fixture\n' > "$WORKTREE/fixture.txt"
git -C "$WORKTREE" add fixture.txt
git -C "$WORKTREE" commit -qm fixture
WORKTREE_HEAD="$(git -C "$WORKTREE" rev-parse HEAD)"

output="$(bash "$ROOT/tools/run_pr_owned_check.sh" "$WORKTREE" 123 "$WORLD_DATA" /usr/bin/python3 /usr/bin/true)"
grep -q 'PR_CHECK=SKIP_PR_OWNED_OBJECTIVE_CHECKS pr=123 reason=no-hook' <<<"$output"

cat > "$WORKTREE/tools/pr_check_local.sh" <<'HOOK'
set -euo pipefail
printf 'HOOK_PR=%s\n' "$BRUR_PR_CHECK_PR"
printf 'HOOK_WORKTREE=%s\n' "$BRUR_PR_CHECK_WORKTREE"
printf 'HOOK_WORLD_DATA=%s\n' "$BRUR_PR_CHECK_WORLD_DATA"
printf 'HOOK_PYTHON=%s\n' "$PYTHON_BIN"
printf 'HOOK_GODOT=%s\n' "$GODOT_BIN"
HOOK

output="$(bash "$ROOT/tools/run_pr_owned_check.sh" "$WORKTREE" 123 "$WORLD_DATA" /usr/bin/python3 /usr/bin/true)"
grep -q 'PR_CHECK=RUN_PR_OWNED_OBJECTIVE_CHECKS pr=123 hook=tools/pr_check_local.sh' <<<"$output"
grep -q 'HOOK_PR=123' <<<"$output"
grep -Fq "HOOK_WORKTREE=$WORKTREE" <<<"$output"
grep -Fq "HOOK_WORLD_DATA=$WORLD_DATA" <<<"$output"
grep -q 'HOOK_PYTHON=/usr/bin/python3' <<<"$output"

cat > "$WORKTREE/tools/pr_check_local.sh" <<'HOOK'
exit 23
HOOK
set +e
bash "$ROOT/tools/run_pr_owned_check.sh" "$WORKTREE" 123 "$WORLD_DATA" /usr/bin/python3 /usr/bin/true >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 23 ]] || { printf 'expected objective hook failure 23, got %s\n' "$status" >&2; exit 1; }

ORDER_LOG="$TMP/order.log"
export ORDER_LOG
FAKE_PYTHON="$TMP/python"
cat > "$FAKE_PYTHON" <<'PY'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == */pr_check_status.py ]]; then
  shift
  printf 'STATUS %s\n' "$*" >> "$ORDER_LOG"
  exit 0
fi
exec /usr/bin/python3 "$@"
PY
chmod +x "$FAKE_PYTHON"

FAKE_GODOT="$TMP/godot"
cat > "$FAKE_GODOT" <<'GODOT'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  if [[ "$arg" == "--headless" ]]; then
    printf 'GODOT_HEADLESS %s\n' "$*" >> "$ORDER_LOG"
    exit 0
  fi
done
printf 'GODOT_VISUAL %s\n' "$*" >> "$ORDER_LOG"
exit 42
GODOT
chmod +x "$FAKE_GODOT"

cat > "$WORKTREE/tools/pr_check_local.sh" <<'HOOK'
set -euo pipefail
"$GODOT_BIN" --headless --path "$BRUR_PR_CHECK_WORKTREE" --script res://tests/fake.gd
printf 'HOOK_OBJECTIVE_DONE\n' >> "$ORDER_LOG"
"$GODOT_BIN" --path "$BRUR_PR_CHECK_WORKTREE" res://harness/fake.tscn
printf 'HOOK_VISUAL_RETURNED\n' >> "$ORDER_LOG"
HOOK

output="$(bash "$ROOT/tools/run_pr_owned_check.sh" "$WORKTREE" 123 "$WORLD_DATA" "$FAKE_PYTHON" "$FAKE_GODOT" 2>&1)"
grep -q 'PR_CHECK=STATUS success pr=123' <<<"$output"
grep -q 'PR_CHECK=VISUAL_REVIEW_WARNING Godot exited status=42 after objective success' <<<"$output"
status_count="$(grep -c '^STATUS .*--state success .*--stage objective-checks-complete' "$ORDER_LOG")"
[[ "$status_count" -eq 1 ]] || { printf 'expected exactly one pre-visual success status, got %s\n' "$status_count" >&2; cat "$ORDER_LOG" >&2; exit 1; }
status_line="$(grep -n '^STATUS ' "$ORDER_LOG" | cut -d: -f1)"
visual_line="$(grep -n '^GODOT_VISUAL ' "$ORDER_LOG" | cut -d: -f1)"
[[ "$status_line" -lt "$visual_line" ]] || { printf 'machine success must be persisted before visual Godot starts\n' >&2; cat "$ORDER_LOG" >&2; exit 1; }
grep -q '^GODOT_HEADLESS ' "$ORDER_LOG"
grep -q '^HOOK_VISUAL_RETURNED$' "$ORDER_LOG"
grep -q -- "--sha $WORKTREE_HEAD" "$ORDER_LOG"

hook_line="$(grep -n 'run_pr_owned_check.sh' "$ROOT/tools/pr_check.sh" | tail -n 1 | cut -d: -f1)"
success_line="$(grep -n -- '--state success' "$ROOT/tools/pr_check.sh" | head -n 1 | cut -d: -f1)"
[[ -n "$hook_line" && -n "$success_line" && "$hook_line" -lt "$success_line" ]] || {
  printf 'outer launcher must retain fail-closed hook-before-final-success ordering\n' >&2
  exit 1
}

grep -q 'DRIVING_VISUAL_SCOPE="required"' "$ROOT/tools/pr_check_local.sh" || {
  printf 'driving changes must still request exact-revision human review\n' >&2
  exit 1
}
grep -q 'harness/driving/driving_harness.tscn' "$ROOT/tools/pr_check_local.sh" || {
  printf 'driving human review must still launch the production-backed driving harness\n' >&2
  exit 1
}

bash -n "$ROOT/tools/run_pr_owned_check.sh"
bash -n "$ROOT/tools/pr_check_local.sh"
bash "$ROOT/tests/test_pr_check_entry.sh"
printf 'pr-owned check hook tests passed\n'
