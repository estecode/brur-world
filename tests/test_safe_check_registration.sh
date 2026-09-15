#!/usr/bin/env bash
# Proves the registered bootstrap fetches/executes current origin/main even when the mapped checkout is stale.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
REGISTER="$ROOT/tools/register_safe_check.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/brur-safe-check-registration.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

bash -n "$REGISTER"
grep -Fq 'git fetch --quiet origin main:refs/remotes/origin/main' "$REGISTER"
grep -Fq 'git show refs/remotes/origin/main:tools/pr_check_entry.sh | /bin/bash -s -- "$1"' "$REGISTER"
if grep -Fq '/bin/bash tools/pr_check_entry.sh' "$REGISTER"; then
  printf 'registration still depends on mapped checkout entrypoint\n' >&2
  exit 1
fi

REMOTE="$TMP/remote.git"
SEED="$TMP/seed"
MAPPED="$TMP/mapped"
git init --bare -q "$REMOTE"
git init -q -b main "$SEED"
git -C "$SEED" config user.email test@example.invalid
git -C "$SEED" config user.name test
mkdir -p "$SEED/tools"
printf 'stale\n' > "$SEED/version.txt"
git -C "$SEED" add .
git -C "$SEED" commit -qm stale
git -C "$SEED" remote add origin "$REMOTE"
git -C "$SEED" push -q -u origin main
git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
git clone -q "$REMOTE" "$MAPPED"

cat > "$SEED/tools/pr_check_entry.sh" <<'SH'
#!/usr/bin/env bash
printf 'CURRENT_MAIN_ENTRY pr=%s\n' "$1"
SH
printf 'current\n' > "$SEED/version.txt"
git -C "$SEED" add .
git -C "$SEED" commit -qm current-main-entry
git -C "$SEED" push -q origin main

[[ ! -e "$MAPPED/tools/pr_check_entry.sh" ]]
output="$(cd "$MAPPED" && /bin/bash -c 'set -euo pipefail; git fetch --quiet origin main:refs/remotes/origin/main; git show refs/remotes/origin/main:tools/pr_check_entry.sh | /bin/bash -s -- "$1"' brur-world-main-pr-check 352)"
[[ "$output" == 'CURRENT_MAIN_ENTRY pr=352' ]]
[[ ! -e "$MAPPED/tools/pr_check_entry.sh" ]]
[[ "$(cat "$MAPPED/version.txt")" == 'stale' ]]
[[ "$(git -C "$MAPPED" status --porcelain)" == '' ]]

printf 'SAFE_CHECK_REGISTRATION_TEST=PASS\n'
