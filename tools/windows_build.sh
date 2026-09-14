#!/usr/bin/env bash
# Boots the repository-owned Windows builder from current origin/main without mutating the mapped checkout.
# Dependencies: git, a mapped brur-world checkout with local world_data, and tools/windows_build/build.sh on origin/main.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
[[ -d "$ROOT/world_data" ]] || { printf 'WINDOWS_BUILD=FAIL missing %s/world_data\n' "$ROOT" >&2; exit 66; }

LAUNCHER_TMP="$(mktemp -d "${TMPDIR:-/tmp}/brur-world-windows-build-main.XXXXXX")"
ADDED=0
cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [[ "$ADDED" -eq 1 ]]; then
    git -C "$ROOT" worktree remove --force "$LAUNCHER_TMP" >/dev/null 2>&1 || true
  fi
  rm -rf "$LAUNCHER_TMP"
  exit "$status"
}
trap cleanup EXIT INT TERM

printf 'WINDOWS_BUILD=BOOTSTRAP fetch-current-main\n'
git -C "$ROOT" fetch --quiet origin main:refs/remotes/origin/main || {
  printf 'WINDOWS_BUILD=FAIL unable to fetch current origin/main launcher\n' >&2
  exit 69
}
MAIN_HEAD="$(git -C "$ROOT" rev-parse refs/remotes/origin/main)"
rm -rf "$LAUNCHER_TMP"
git -C "$ROOT" worktree add --quiet --detach "$LAUNCHER_TMP" "$MAIN_HEAD" || {
  printf 'WINDOWS_BUILD=FAIL unable to prepare current main launcher worktree\n' >&2
  exit 70
}
ADDED=1

[[ -f "$LAUNCHER_TMP/tools/windows_build/build.sh" ]] || {
  printf 'WINDOWS_BUILD=FAIL current origin/main has no Windows builder\n' >&2
  exit 66
}

rm -rf "$LAUNCHER_TMP/world_data"
ln -s "$ROOT/world_data" "$LAUNCHER_TMP/world_data"
export BRUR_WINDOWS_MAPPED_ROOT="$ROOT"
# The normal bootstrap/Safe Command contract is the mapped checkout's world_data.
# Pin it explicitly so ambient process environment cannot silently redirect the build.
export BRUR_WINDOWS_WORLD_DATA="$ROOT/world_data"
printf 'WINDOWS_BUILD=BOOTSTRAP main=%s mapped=%s world_data=%s\n' "${MAIN_HEAD:0:12}" "$ROOT" "$BRUR_WINDOWS_WORLD_DATA"
cd "$LAUNCHER_TMP"
bash tools/windows_build/build.sh "$@"
