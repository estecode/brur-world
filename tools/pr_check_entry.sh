#!/usr/bin/env bash
# Boots the PR-check launcher from current origin/main without mutating the mapped checkout.
# Dependencies: git, a mapped brur-world checkout, ignored local world_data/.venv, and tools/pr_check.sh on origin/main.
set -euo pipefail

PR="${1:-}"
[[ "$PR" =~ ^[1-9][0-9]*$ ]] || { printf 'PR_CHECK=FAIL invalid PR number\n' >&2; exit 64; }

ROOT="$(git rev-parse --show-toplevel)"
[[ -d "$ROOT/world_data" ]] || { printf 'PR_CHECK=FAIL missing %s/world_data\n' "$ROOT" >&2; exit 66; }

LAUNCHER_TMP="$(mktemp -d "${TMPDIR:-/tmp}/brur-world-pr-check-main.XXXXXX")"
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

printf 'PR_CHECK=BOOTSTRAP fetch-current-main\n'
if ! git -C "$ROOT" fetch --quiet origin main:refs/remotes/origin/main; then
  printf 'PR_CHECK=FAIL unable to fetch current origin/main launcher\n' >&2
  exit 69
fi
MAIN_HEAD="$(git -C "$ROOT" rev-parse refs/remotes/origin/main)"

rm -rf "$LAUNCHER_TMP"
if ! git -C "$ROOT" worktree add --quiet --detach "$LAUNCHER_TMP" "$MAIN_HEAD"; then
  printf 'PR_CHECK=FAIL unable to prepare current main launcher worktree\n' >&2
  exit 70
fi
ADDED=1

[[ -f "$LAUNCHER_TMP/tools/pr_check.sh" ]] || {
  printf 'PR_CHECK=FAIL current origin/main has no tools/pr_check.sh\n' >&2
  exit 66
}

rm -rf "$LAUNCHER_TMP/world_data"
ln -s "$ROOT/world_data" "$LAUNCHER_TMP/world_data"
if [[ -d "$ROOT/.venv" && ! -e "$LAUNCHER_TMP/.venv" ]]; then
  ln -s "$ROOT/.venv" "$LAUNCHER_TMP/.venv"
fi

if [[ -z "${BRUR_WORLD_PBF:-}" ]]; then
  data_dir="$(cd "$ROOT/.." && pwd)/data"
  if [[ -d "$data_dir" ]]; then
    candidate="$(find "$data_dir" -maxdepth 1 -type f -name 'sweden-*.osm.pbf' -print 2>/dev/null | LC_ALL=C sort | tail -n 1)"
    if [[ -n "$candidate" ]]; then
      export BRUR_WORLD_PBF="$candidate"
    fi
  fi
fi

printf 'PR_CHECK=BOOTSTRAP main=%s mapped=%s\n' "${MAIN_HEAD:0:12}" "$ROOT"
cd "$LAUNCHER_TMP"
bash tools/pr_check.sh "$PR"
