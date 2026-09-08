#!/usr/bin/env bash
# Launches an exact pull-request revision in an isolated temporary worktree for human Godot verification.
# Dependencies: git, a local Godot executable, a C++20 compiler, and this checkout's ignored world_data runtime dataset.
set -euo pipefail

PR="${1:-}"
[[ "$PR" =~ ^[1-9][0-9]*$ ]] || { printf 'PR_CHECK=FAIL invalid PR number\n' >&2; exit 64; }

ROOT="$(git rev-parse --show-toplevel)"
WORLD_DATA="$ROOT/world_data"
[[ -d "$WORLD_DATA" ]] || { printf 'PR_CHECK=FAIL missing %s\n' "$WORLD_DATA" >&2; exit 66; }
[[ -f "$WORLD_DATA/manifest.json" ]] || { printf 'PR_CHECK=FAIL missing %s/manifest.json\n' "$WORLD_DATA" >&2; exit 66; }

if command -v godot >/dev/null 2>&1; then
  GODOT="$(command -v godot)"
elif [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
  GODOT=/Applications/Godot.app/Contents/MacOS/Godot
else
  printf 'PR_CHECK=FAIL Godot executable not found\n' >&2
  exit 69
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/brur-world-pr${PR}.XXXXXX")"
ADDED=0
cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [[ "$ADDED" -eq 1 ]]; then
    git -C "$ROOT" worktree remove --force "$TMP" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP"
  exit "$status"
}
trap cleanup EXIT INT TERM

printf 'PR_CHECK=PREPARE pr=%s\n' "$PR"
git -C "$ROOT" fetch --quiet origin "pull/${PR}/head"
git -C "$ROOT" worktree add --quiet --detach "$TMP" FETCH_HEAD
ADDED=1

rm -rf "$TMP/world_data"
ln -s "$WORLD_DATA" "$TMP/world_data"

if [[ -f "$TMP/tools/build_native_gps.sh" ]]; then
  printf 'PR_CHECK=BUILD_NATIVE_GPS pr=%s\n' "$PR"
  bash "$TMP/tools/build_native_gps.sh"
fi

printf 'PR_CHECK=RUN pr=%s revision=%s\n' "$PR" "$(git -C "$TMP" rev-parse --short HEAD)"
printf 'Close Godot when the check is complete; the temporary checkout will then be removed automatically.\n'
"$GODOT" --path "$TMP"
