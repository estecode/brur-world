#!/usr/bin/env bash
# Verifies current-main Safe Check bootstrap plus connector-visible mapped-checkout logging on success and failure.
# Dependencies: bash, git, mktemp, tools/pr_check_entry.sh, tools/run_pr_owned_check.sh, and a fake gh PR metadata response.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
ENTRY="$ROOT/tools/pr_check_entry.sh"
OWNED_RUNNER="$ROOT/tools/run_pr_owned_check.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/brur-pr-check-entry-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

REMOTE="$TMP/remote.git"
SEED="$TMP/seed"
MAPPED="$TMP/mapped"
FAKE_BIN="$TMP/bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
case "${FAKE_PR_DECISION:-MERGE}" in
  MERGE)
    recommendation=MERGE
    ;;
  CHECK)
    recommendation='CHECK THEN MERGE'
    ;;
  BLOCK)
    recommendation='DO NOT MERGE'
    ;;
  *)
    printf 'unexpected FAKE_PR_DECISION=%s\n' "$FAKE_PR_DECISION" >&2
    exit 2
    ;;
esac
cat <<BODY
## Merge decision

**Merge recommendation**
$recommendation
BODY
GH
chmod +x "$FAKE_BIN/gh"

git init --bare -q "$REMOTE"
git init -q -b main "$SEED"
git -C "$SEED" config user.email test@example.invalid
git -C "$SEED" config user.name test
mkdir -p "$SEED/tools" "$SEED/world_data"
printf '{}\n' > "$SEED/world_data/manifest.json"
cat > "$SEED/tools/pr_check.sh" <<'SH'
#!/usr/bin/env bash
printf 'LAUNCHER=OLD pr=%s\n' "$1"
SH
cat > "$SEED/tools/pr_merge_decision.py" <<'PY'
#!/usr/bin/env python3
import sys
body = sys.stdin.read()
if "**Merge recommendation**\nMERGE" in body:
    print("merge")
elif "**Merge recommendation**\nCHECK THEN MERGE" in body:
    print("check")
elif "**Merge recommendation**\nDO NOT MERGE" in body:
    print("block")
else:
    raise SystemExit(2)
PY
git -C "$SEED" add .
git -C "$SEED" commit -qm initial
git -C "$SEED" remote add origin "$REMOTE"
git -C "$SEED" push -q -u origin main
git -C "$REMOTE" symbolic-ref HEAD refs/heads/main

git clone -q "$REMOTE" "$MAPPED"
mkdir -p "$MAPPED/world_data"
printf '{}\n' > "$MAPPED/world_data/manifest.json"

cat > "$SEED/tools/pr_check.sh" <<'SH'
#!/usr/bin/env bash
printf 'LAUNCHER=NEW pr=%s manual=%s\n' "$1" "${BRUR_PR_CHECK_MANUAL_REVIEW:-missing}"
SH
git -C "$SEED" add tools/pr_check.sh
git -C "$SEED" commit -qm current-launcher
git -C "$SEED" push -q origin main

output="$(cd "$MAPPED" && PATH="$FAKE_BIN:$PATH" bash "$ENTRY" 97)"
printf '%s\n' "$output" | grep -q 'LAUNCHER=NEW pr=97 manual=none'
if printf '%s\n' "$output" | grep -q 'LAUNCHER=OLD'; then
  printf 'stale mapped launcher was executed\n' >&2
  exit 1
fi
SUCCESS_LOG="$MAPPED/safecommand-logs/pr-check-97.log"
[[ -f "$SUCCESS_LOG" ]]
grep -q 'PR_CHECK=LOG_STARTED pr=97' "$SUCCESS_LOG"
grep -q 'PR_CHECK=MANUAL_REVIEW none pr=97 source=pr-merge-decision' "$SUCCESS_LOG"
grep -q 'LAUNCHER=NEW pr=97 manual=none' "$SUCCESS_LOG"
grep -q 'PR_CHECK=LOG_FINISHED pr=97 exit=0' "$SUCCESS_LOG"
[[ ! -e "$MAPPED/.safecommand/logs/pr-check-97.log" ]]

rm "$SEED/tools/pr_check.sh"
git -C "$SEED" add -u
git -C "$SEED" commit -qm remove-launcher
git -C "$SEED" push -q origin main

set +e
failure_output="$(cd "$MAPPED" && PATH="$FAKE_BIN:$PATH" bash "$ENTRY" 97 2>&1)"
status=$?
set -e
[[ "$status" -ne 0 ]]
printf '%s\n' "$failure_output" | grep -q 'current origin/main has no tools/pr_check.sh'
[[ -f "$SUCCESS_LOG" ]]
grep -q 'PR_CHECK=LOG_STARTED pr=97' "$SUCCESS_LOG"
grep -q 'current origin/main has no tools/pr_check.sh' "$SUCCESS_LOG"
grep -q 'PR_CHECK=LOG_FINISHED pr=97 exit=66' "$SUCCESS_LOG"
if grep -q 'LAUNCHER=NEW pr=97' "$SUCCESS_LOG"; then
  printf 'persistent PR log was not replaced for the latest run\n' >&2
  exit 1
fi

# Simulate a mapped checkout whose outer entrypoint is still old. The old entry
# fetches current main and invokes this runner without the new manual-review env;
# current-main runner must recover CHECK THEN MERGE itself and pass it to the hook.
FALLBACK_WORKTREE="$TMP/fallback-worktree"
FALLBACK_LAUNCHER="$TMP/fallback-launcher"
mkdir -p "$FALLBACK_WORKTREE/tools" "$FALLBACK_WORKTREE/scenes" "$FALLBACK_LAUNCHER"
git -C "$FALLBACK_WORKTREE" init -q
git -C "$FALLBACK_WORKTREE" config user.email test@example.invalid
git -C "$FALLBACK_WORKTREE" config user.name test
printf 'fixture\n' > "$FALLBACK_WORKTREE/fixture.txt"
touch "$FALLBACK_WORKTREE/scenes/main.tscn"
cat > "$FALLBACK_WORKTREE/tools/pr_check_local.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${BRUR_PR_CHECK_MANUAL_REVIEW:-}" == "required" ]] || {
  printf 'FALLBACK_MANUAL_REVIEW_MISSING value=%s\n' "${BRUR_PR_CHECK_MANUAL_REVIEW:-missing}" >&2
  exit 24
}
printf 'FALLBACK_MANUAL_REVIEW=%s\n' "$BRUR_PR_CHECK_MANUAL_REVIEW"
"$GODOT_BIN" --path "$BRUR_PR_CHECK_WORKTREE" "$BRUR_PR_CHECK_WORKTREE/scenes/main.tscn"
SH
git -C "$FALLBACK_WORKTREE" add .
git -C "$FALLBACK_WORKTREE" commit -qm fallback-fixture
ln -s "$MAPPED/world_data" "$FALLBACK_LAUNCHER/world_data"
FALLBACK_GODOT="$TMP/fallback-godot"
cat > "$FALLBACK_GODOT" <<'GODOT'
#!/usr/bin/env bash
set -euo pipefail
printf 'FALLBACK_GODOT %s\n' "$*" >> "$ORDER_LOG"
for arg in "$@"; do
  [[ "$arg" != "--editor" ]] || { printf 'editor must not be used\n' >&2; exit 41; }
done
exit 0
GODOT
chmod +x "$FALLBACK_GODOT"
ORDER_LOG="$TMP/fallback-order.log"
export ORDER_LOG
: > "$ORDER_LOG"
set +e
env -u BRUR_PR_CHECK_LOG_PATH -u BRUR_PR_CHECK_MAPPED_ROOT -u BRUR_PR_CHECK_MANUAL_REVIEW \
  FAKE_PR_DECISION=CHECK PATH="$FAKE_BIN:$PATH" \
  bash "$OWNED_RUNNER" "$FALLBACK_WORKTREE" 98 "$FALLBACK_LAUNCHER/world_data" /usr/bin/python3 "$FALLBACK_GODOT" >/dev/null 2>&1
fallback_status=$?
set -e
[[ "$fallback_status" -eq 0 ]] || { printf 'expected fallback review recovery success, got %s\n' "$fallback_status" >&2; exit 1; }
FALLBACK_LOG="$MAPPED/safecommand-logs/pr-check-98.log"
[[ -f "$FALLBACK_LOG" ]]
grep -q 'PR_CHECK=LOG_FALLBACK .*reason=stale-mapped-entrypoint' "$FALLBACK_LOG"
grep -q 'PR_CHECK=MANUAL_REVIEW required pr=98 source=pr-merge-decision-fallback' "$FALLBACK_LOG"
grep -q 'FALLBACK_MANUAL_REVIEW=required' "$FALLBACK_LOG"
grep -q 'PR_CHECK=LOG_FALLBACK_FINISHED pr=98 exit=0' "$FALLBACK_LOG"
grep -q 'FALLBACK_GODOT .*scenes/main.tscn' "$ORDER_LOG"
if grep -q -- '--editor' "$ORDER_LOG"; then
  printf 'stale bootstrap fallback attempted to open Godot editor\n' >&2
  exit 1
fi
[[ ! -e "$MAPPED/.safecommand/logs/pr-check-98.log" ]]

printf 'PR_CHECK_ENTRY_TEST=PASS\n'
