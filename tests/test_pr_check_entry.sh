#!/usr/bin/env bash
# Verifies that PR Safe Check bootstraps current origin/main instead of stale mapped-checkout tooling.
# Dependencies: bash, git, mktemp, and tools/pr_check_entry.sh.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
ENTRY="$ROOT/tools/pr_check_entry.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/brur-pr-check-entry-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

REMOTE="$TMP/remote.git"
SEED="$TMP/seed"
MAPPED="$TMP/mapped"

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
printf 'LAUNCHER=NEW pr=%s\n' "$1"
SH
git -C "$SEED" add tools/pr_check.sh
git -C "$SEED" commit -qm current-launcher
git -C "$SEED" push -q origin main

output="$(cd "$MAPPED" && bash "$ENTRY" 97)"
printf '%s\n' "$output" | grep -q 'LAUNCHER=NEW pr=97'
if printf '%s\n' "$output" | grep -q 'LAUNCHER=OLD'; then
  printf 'stale mapped launcher was executed\n' >&2
  exit 1
fi

rm "$SEED/tools/pr_check.sh"
git -C "$SEED" add -u
git -C "$SEED" commit -qm remove-launcher
git -C "$SEED" push -q origin main

set +e
failure_output="$(cd "$MAPPED" && bash "$ENTRY" 97 2>&1)"
status=$?
set -e
[[ "$status" -ne 0 ]]
printf '%s\n' "$failure_output" | grep -q 'current origin/main has no tools/pr_check.sh'

printf 'PR_CHECK_ENTRY_TEST=PASS\n'
