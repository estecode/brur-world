#!/usr/bin/env bash
# Builds a complete #126 Windows client ZIP only when explicitly requested.
# Dependencies: Godot with Windows export templates, Python 3, and local existing world_data runtime exports.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-godot}"
PYTHON="${PYTHON_BIN:-python3}"
WORLD_DATA="${1:-$ROOT/world_data}"
OUTPUT_DIR="${2:-$ROOT/dist/windows-client}"

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
BINARY_DIR="$OUTPUT_DIR/$BUILD_NAME-binary"
ZIP_PATH="$OUTPUT_DIR/$BUILD_NAME-client.zip"
PROJECT_COPY="$OUTPUT_DIR/$BUILD_NAME-project.godot"

rm -rf "$BINARY_DIR"
mkdir -p "$BINARY_DIR" "$OUTPUT_DIR"
cp "$ROOT/project.godot" "$PROJECT_COPY"
restore_project() {
  cp "$PROJECT_COPY" "$ROOT/project.godot"
  rm -f "$PROJECT_COPY"
}
trap restore_project EXIT

"$PYTHON" - "$ROOT/project.godot" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace(
    'run/main_scene="res://harness/world_showcase/world_showcase.tscn"',
    'run/main_scene="res://harness/world_showcase/world_showcase_windows.tscn"',
)
path.write_text(text, encoding="utf-8")
PY

printf 'WINDOWS_CLIENT=EXPORT commit=%s\n' "$SHORT_SHA"
"$GODOT" --headless --path "$ROOT" --export-release "Windows Desktop" "$BINARY_DIR/$BUILD_NAME.exe"
test -s "$BINARY_DIR/$BUILD_NAME.exe"
test -s "$BINARY_DIR/$BUILD_NAME.pck"

printf '{\n  "pr": 128,\n  "commit": "%s",\n  "short_commit": "%s",\n  "godot": "local-export",\n  "platform": "windows-x86_64",\n  "client_ready": true\n}\n' \
  "$COMMIT" "$SHORT_SHA" > "$BINARY_DIR/build_info.json"

printf 'WINDOWS_CLIENT=PACKAGE runtime_source=%s\n' "$WORLD_DATA"
"$PYTHON" "$ROOT/tools/package_world_showcase_client.py" \
  "$BINARY_DIR" "$WORLD_DATA" --output "$ZIP_PATH"

test -s "$ZIP_PATH"
printf 'WINDOWS_CLIENT=READY %s\n' "$ZIP_PATH"
