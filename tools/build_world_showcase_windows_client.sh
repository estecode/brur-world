#!/usr/bin/env bash
# Builds a complete #126 Windows client ZIP only when explicitly requested.
# Dependencies: Godot with Windows export templates, Python 3, git, and local existing world_data runtime exports.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-godot}"
PYTHON="${PYTHON_BIN:-python3}"
WORLD_DATA="${1:-$ROOT/world_data}"
DROPBOX_OUTPUT="${BRUR_WINDOWS_DROPBOX_DIR:-$HOME/Dropbox/BRUR}"
OUTPUT_DIR="${2:-$DROPBOX_OUTPUT}"

if [[ ! -d "$WORLD_DATA" ]]; then
  printf 'WINDOWS_CLIENT=FAIL missing world_data: %s\n' "$WORLD_DATA" >&2
  exit 1
fi

for required in manifest.json buildings.jsonl background.brmap; do
  if [[ ! -s "$WORLD_DATA/$required" ]]; then
    printf 'WINDOWS_CLIENT=FAIL missing required runtime source: %s\n' "$WORLD_DATA/$required" >&2
    exit 1
  fi
done

COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
SHORT_SHA="${COMMIT:0:12}"
BUILD_NAME="brur-poc128-${SHORT_SHA}-win64"
ZIP_PATH="$OUTPUT_DIR/$BUILD_NAME-client.zip"
BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/brur-windows-client.XXXXXX")"
SOURCE_ROOT="$BUILD_ROOT/source"
BINARY_DIR="$BUILD_ROOT/binary"

cleanup() {
  rm -rf "$BUILD_ROOT"
}
trap cleanup EXIT

mkdir -p "$SOURCE_ROOT" "$BINARY_DIR" "$OUTPUT_DIR"

git -C "$ROOT" archive "$COMMIT" | tar -x -C "$SOURCE_ROOT"

"$PYTHON" - "$SOURCE_ROOT/project.godot" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = 'run/main_scene="res://harness/world_showcase/world_showcase.tscn"'
new = 'run/main_scene="res://harness/world_showcase/world_showcase_windows.tscn"'
if old not in text:
    raise SystemExit("WINDOWS_CLIENT=FAIL expected showcase main scene was not found")
path.write_text(text.replace(old, new), encoding="utf-8")
PY

printf 'WINDOWS_CLIENT=EXPORT commit=%s\n' "$SHORT_SHA"
"$GODOT" --headless --path "$SOURCE_ROOT" --export-release "Windows Desktop" "$BINARY_DIR/$BUILD_NAME.exe"
test -s "$BINARY_DIR/$BUILD_NAME.exe"
test -s "$BINARY_DIR/$BUILD_NAME.pck"

printf '{\n  "pr": 128,\n  "commit": "%s",\n  "short_commit": "%s",\n  "godot": "local-export",\n  "platform": "windows-x86_64",\n  "client_ready": true\n}\n' \
  "$COMMIT" "$SHORT_SHA" > "$BINARY_DIR/build_info.json"

printf 'WINDOWS_CLIENT=PACKAGE runtime_source=%s\n' "$WORLD_DATA"
"$PYTHON" "$SOURCE_ROOT/tools/package_world_showcase_client.py" \
  "$BINARY_DIR" "$WORLD_DATA" --output "$ZIP_PATH"

test -s "$ZIP_PATH"
printf 'WINDOWS_CLIENT=READY %s\n' "$ZIP_PATH"
