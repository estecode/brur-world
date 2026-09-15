#!/usr/bin/env bash
# Registers brur-world PR Safe Check so its first executed project code is always fetched from current origin/main.
# Run from the safe-command-links checkout; the mapped brur-world checkout may be on any branch/revision.
set -euo pipefail

SAFE_COMMAND_ROOT="$(git rev-parse --show-toplevel)"
BRUR_ROOT="${1:-}"
if [[ -z "$BRUR_ROOT" ]]; then
  printf 'Usage: %s /absolute/path/to/brur-world\n' "$0" >&2
  exit 64
fi
BRUR_ROOT="$(cd "$BRUR_ROOT" && pwd)"

bash "$SAFE_COMMAND_ROOT/allow-repo.sh" estecode/brur-world "$BRUR_ROOT"
bash "$SAFE_COMMAND_ROOT/allow-project.sh" "$BRUR_ROOT" pr-check . /bin/bash -c \
  'set -euo pipefail; git fetch --quiet origin main:refs/remotes/origin/main; git show refs/remotes/origin/main:tools/pr_check_entry.sh | /bin/bash -s -- "$1"' \
  brur-world-main-pr-check --param pr:positive-int

printf 'BRUR_SAFE_CHECK=REGISTERED source=current-origin-main mapped=%s\n' "$BRUR_ROOT"
