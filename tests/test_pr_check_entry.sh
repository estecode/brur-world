#!/usr/bin/env bash
# Verifies current-main Safe Check bootstrap plus persistent mapped-checkout logging on success and failure.
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
cat <<'BODY'
## Merge decision

**Merge recommendation**
MERGE
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
if "**Merge recommendation**\nMERGE" not in body:
    raise SystemExit(2)
print("merge")
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
SUCCESS_LOG="$MAPPED/.safecommand/logs/pr-check-97.log"
[[ -f "$SUCCESS_LOG" ]]
grep -q 'PR_CHECK=LOG_STARTED pr=97' "$SUCCESS_LOG"
grep -q 'PR_CHECK=MANUAL_REVIEW none pr=97 source=pr-merge-decision' "$SUCCESS_LOG"
grep -q 'LAUNCHER=NEW pr=97 manual=none' "$SUCCESS_LOG"
grep -q 'PR_CHECK=LOG_FINISHED pr=97 exit=0' "$SUCCESS_LOG"

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
# fetches current main and invokes this runner with a world_data symlink pointing
# back to the mapped checkout; the runner must recover that stable root itself.
FALLBACK_WORKTREE="$TMP/fallback-worktree"
FALLBACK_LAUNCHER="$TMP/fallback-launcher"
mkdir -p "$FALLBACK_WORKTREE/tools" "$FALLBACK_LAUNCHER"
git -C "$FALLBACK_WORKTREE" init -q
git -C "$FALLBACK_WORKTREE" config user.email test@example.invalid
git -C "$FALLBACK_WORKTREE" config user.name test
printf 'fixture\n' > "$FALLBACK_WORKTREE/fixture.txt"
cat > "$FALLBACK_WORKTREE/tools/pr_check_local.sh" <<'SH'
#!/usr/bin/env bash
printf 'FALLBACK_HOOK_FAILURE pr=%s\n' "$BRUR_PR_CHECK_PR"
exit 23
SH
git -C "$FALLBACK_WORKTREE" add .
git -C "$FALLBACK_WORKTREE" commit -qm fallback-fixture
ln -s "$MAPPED/world_data" "$FALLBACK_LAUNCHER/world_data"
set +e
env -u BRUR_PR_CHECK_LOG_PATH -u BRUR_PR_CHECK_MAPPED_ROOT \
  bash "$OWNED_RUNNER" "$FALLBACK_WORKTREE" 98 "$FALLBACK_LAUNCHER/world_data" /usr/bin/python3 /usr/bin/true >/dev/null 2>&1
fallback_status=$?
set -e
[[ "$fallback_status" -eq 23 ]] || { printf 'expected fallback hook exit 23, got %s\n' "$fallback_status" >&2; exit 1; }
FALLBACK_LOG="$MAPPED/.safecommand/logs/pr-check-98.log"
[[ -f "$FALLBACK_LOG" ]]
grep -q 'PR_CHECK=LOG_FALLBACK .*reason=stale-mapped-entrypoint' "$FALLBACK_LOG"
grep -q 'FALLBACK_HOOK_FAILURE pr=98' "$FALLBACK_LOG"
grep -q 'PR_CHECK=LOG_FALLBACK_FINISHED pr=98 exit=23' "$FALLBACK_LOG"

printf 'PR_CHECK_ENTRY_TEST=PASS\n'
