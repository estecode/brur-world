#!/usr/bin/env bash
# Resolves an exact revision, builds its Windows target in isolation, and packages one client-ready ZIP.
# Dependencies: git, gh for PR selection, Python 3, Godot with Windows export templates, local authoritative world_data.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
PYTHON="${PYTHON_BIN:-python3}"
GODOT="${GODOT_BIN:-}"
WORLD_DATA="${BRUR_WINDOWS_WORLD_DATA:-$ROOT/world_data}"
OUTPUT_DIR="${BRUR_WINDOWS_OUTPUT_DIR:-${BRUR_WINDOWS_DROPBOX_DIR:-$HOME/Dropbox/BRUR}}"
REPOSITORY="estecode/brur-world"
SELECTOR_KIND=""
SELECTOR_VALUE=""
PR=""
REF_NAME=""
ISSUE=""

usage() {
  cat <<'EOF'
Usage:
  bash tools/windows_build.sh <PR number>
  bash tools/windows_build.sh --pr <PR number>
  bash tools/windows_build.sh --ref <branch|tag|commit>

Optional environment:
  BRUR_WINDOWS_WORLD_DATA=/path/to/world_data
  BRUR_WINDOWS_OUTPUT_DIR=/path/to/output
  GODOT_BIN=/path/to/godot
  PYTHON_BIN=python3
EOF
}

if [[ $# -eq 1 && "$1" =~ ^[1-9][0-9]*$ ]]; then
  SELECTOR_KIND="pr"
  SELECTOR_VALUE="$1"
elif [[ $# -eq 2 && "$1" == "--pr" && "$2" =~ ^[1-9][0-9]*$ ]]; then
  SELECTOR_KIND="pr"
  SELECTOR_VALUE="$2"
elif [[ $# -eq 2 && "$1" == "--ref" && -n "$2" ]]; then
  SELECTOR_KIND="ref"
  SELECTOR_VALUE="$2"
else
  usage >&2
  exit 64
fi

[[ -d "$WORLD_DATA" ]] || { printf 'WINDOWS_BUILD=FAIL missing world_data: %s\n' "$WORLD_DATA" >&2; exit 66; }
[[ -s "$WORLD_DATA/manifest.json" ]] || { printf 'WINDOWS_BUILD=FAIL missing authoritative manifest: %s/manifest.json\n' "$WORLD_DATA" >&2; exit 66; }

if [[ -z "$GODOT" ]]; then
  if command -v godot >/dev/null 2>&1; then
    GODOT="$(command -v godot)"
  elif [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
    GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
  else
    printf 'WINDOWS_BUILD=FAIL Godot not found; set GODOT_BIN\n' >&2
    exit 69
  fi
fi

if [[ "$SELECTOR_KIND" == "pr" ]]; then
  command -v gh >/dev/null 2>&1 || { printf 'WINDOWS_BUILD=FAIL gh is required for PR builds\n' >&2; exit 69; }
  PR="$SELECTOR_VALUE"
  PR_JSON="$(gh pr view "$PR" --repo "$REPOSITORY" --json headRefOid,headRefName,body)"
  EXPECTED_SHA="$($PYTHON -c 'import json,sys; print(json.load(sys.stdin)["headRefOid"])' <<<"$PR_JSON")"
  REF_NAME="$($PYTHON -c 'import json,sys; print(json.load(sys.stdin)["headRefName"])' <<<"$PR_JSON")"
  ISSUE="$($PYTHON -c 'import json,re,sys; b=json.load(sys.stdin).get("body") or ""; m=re.search(r"(?i)closes\s+#(\d+)", b); print(m.group(1) if m else "")' <<<"$PR_JSON")"
  git fetch --quiet origin "pull/$PR/head"
  COMMIT="$(git rev-parse FETCH_HEAD)"
  [[ "$COMMIT" == "$EXPECTED_SHA" ]] || { printf 'WINDOWS_BUILD=FAIL PR head moved while resolving (%s != %s)\n' "$COMMIT" "$EXPECTED_SHA" >&2; exit 75; }
else
  REF_NAME="$SELECTOR_VALUE"
  if git rev-parse --verify --quiet "${SELECTOR_VALUE}^{commit}" >/dev/null; then
    COMMIT="$(git rev-parse "${SELECTOR_VALUE}^{commit}")"
  else
    git fetch --quiet origin "$SELECTOR_VALUE" || { printf 'WINDOWS_BUILD=FAIL unable to fetch ref: %s\n' "$SELECTOR_VALUE" >&2; exit 69; }
    COMMIT="$(git rev-parse FETCH_HEAD)"
  fi
fi

SHORT_SHA="${COMMIT:0:12}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
BUILD_NAME="brur-${SHORT_SHA}-win64"
BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/brur-windows-build.XXXXXX")"
SOURCE_ROOT="$BUILD_ROOT/source"
BINARY_DIR="$BUILD_ROOT/binary"
RUNTIME_DATA="$BUILD_ROOT/runtime_data"
BUILD_INFO="$BUILD_ROOT/build_info.json"
ZIP_PATH="$OUTPUT_DIR/$BUILD_NAME-client.zip"
ADDED=0

cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [[ "$ADDED" -eq 1 ]]; then
    git -C "$ROOT" worktree remove --force "$SOURCE_ROOT" >/dev/null 2>&1 || true
  fi
  rm -rf "$BUILD_ROOT"
  exit "$status"
}
trap cleanup EXIT INT TERM

mkdir -p "$BINARY_DIR" "$RUNTIME_DATA"
git worktree add --quiet --detach "$SOURCE_ROOT" "$COMMIT"
ADDED=1
[[ "$(git -C "$SOURCE_ROOT" rev-parse HEAD)" == "$COMMIT" ]] || { printf 'WINDOWS_BUILD=FAIL isolated checkout mismatch\n' >&2; exit 70; }
[[ -f "$SOURCE_ROOT/tools/windows_build/target.sh" ]] || { printf 'WINDOWS_BUILD=FAIL selected revision has no Windows target contract\n' >&2; exit 66; }

GODOT_VERSION="$($GODOT --version | head -n 1 | tr -d '\r')"
export BRUR_WINDOWS_SOURCE_ROOT="$SOURCE_ROOT"
export BRUR_WINDOWS_WORLD_DATA="$WORLD_DATA"
export BRUR_WINDOWS_RUNTIME_DATA_OUT="$RUNTIME_DATA"
export BRUR_WINDOWS_EXPORT_DIR="$BINARY_DIR"
export BRUR_WINDOWS_BUILD_NAME="$BUILD_NAME"
export GODOT_BIN="$GODOT"

printf 'WINDOWS_BUILD=TARGET selector=%s:%s commit=%s\n' "$SELECTOR_KIND" "$SELECTOR_VALUE" "$SHORT_SHA"
bash "$SOURCE_ROOT/tools/windows_build/target.sh"
[[ -s "$BINARY_DIR/$BUILD_NAME.exe" ]] || { printf 'WINDOWS_BUILD=FAIL missing exported EXE\n' >&2; exit 1; }
[[ -s "$BINARY_DIR/$BUILD_NAME.pck" ]] || { printf 'WINDOWS_BUILD=FAIL missing exported PCK\n' >&2; exit 1; }
find "$RUNTIME_DATA" -type f -print -quit | grep -q . || { printf 'WINDOWS_BUILD=FAIL target produced no runtime data\n' >&2; exit 1; }

"$PYTHON" - "$BUILD_INFO" <<PY
import json, pathlib
payload = {
  "schema_version": 1,
  "repository": "$REPOSITORY",
  "selector": {"kind": "$SELECTOR_KIND", "value": "$SELECTOR_VALUE"},
  "pr": int("$PR") if "$PR" else None,
  "issue": int("$ISSUE") if "$ISSUE" else None,
  "ref": "$REF_NAME" or None,
  "commit": "$COMMIT",
  "short_commit": "$SHORT_SHA",
  "build_timestamp_utc": "$STAMP",
  "godot_version": "$GODOT_VERSION",
  "export_target": "Windows Desktop",
  "platform": "windows-x86_64",
  "packaging_format_version": 1,
  "client_ready": False,
}
pathlib.Path("$BUILD_INFO").write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
PY

mkdir -p "$OUTPUT_DIR"
printf 'WINDOWS_BUILD=PACKAGE runtime_source=%s\n' "$WORLD_DATA"
"$PYTHON" "$SOURCE_ROOT/tools/windows_build/package.py" \
  "$BINARY_DIR" "$RUNTIME_DATA" "$BUILD_INFO" "$WORLD_DATA/manifest.json" --output "$ZIP_PATH"
[[ -s "$ZIP_PATH" ]] || { printf 'WINDOWS_BUILD=FAIL package not created\n' >&2; exit 1; }
printf 'WINDOWS_BUILD=READY %s\n' "$ZIP_PATH"
