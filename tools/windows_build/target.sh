#!/usr/bin/env bash
# Stages the selected revision's production runtime data into res://world_data and exports Windows.
# Dependencies: prepare_runtime_data.py, project.godot production startup scene, Windows export preset, Godot, authoritative local world_data.
set -euo pipefail

: "${BRUR_WINDOWS_SOURCE_ROOT:?}"
: "${BRUR_WINDOWS_WORLD_DATA:?}"
: "${BRUR_WINDOWS_RUNTIME_DATA_OUT:?}"
: "${BRUR_WINDOWS_EXPORT_DIR:?}"
: "${BRUR_WINDOWS_BUILD_NAME:?}"
: "${GODOT_BIN:?}"
PYTHON="${PYTHON_BIN:-python3}"

"$PYTHON" "$BRUR_WINDOWS_SOURCE_ROOT/tools/windows_build/prepare_runtime_data.py" \
  "$BRUR_WINDOWS_WORLD_DATA" --output "$BRUR_WINDOWS_RUNTIME_DATA_OUT"

STAGED_WORLD_DATA="$BRUR_WINDOWS_SOURCE_ROOT/world_data"
rm -rf "$STAGED_WORLD_DATA"
cp -R "$BRUR_WINDOWS_RUNTIME_DATA_OUT" "$STAGED_WORLD_DATA"

"$PYTHON" - "$BRUR_WINDOWS_SOURCE_ROOT/export_presets.cfg" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = 'include_filter=""'
new = 'include_filter="world_data/*,world_data/**/*"'
if old not in text:
    raise SystemExit("WINDOWS_TARGET=FAIL expected empty Windows export include_filter")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY

printf 'WINDOWS_TARGET=EXPORT name=%s\n' "$BRUR_WINDOWS_BUILD_NAME"
"$GODOT_BIN" --headless --path "$BRUR_WINDOWS_SOURCE_ROOT" \
  --export-release "Windows Desktop" "$BRUR_WINDOWS_EXPORT_DIR/$BRUR_WINDOWS_BUILD_NAME.exe"

PCK_PATH="$BRUR_WINDOWS_EXPORT_DIR/$BRUR_WINDOWS_BUILD_NAME.pck"
[[ -s "$PCK_PATH" ]] || { printf 'WINDOWS_TARGET=FAIL missing exported PCK\n' >&2; exit 1; }
printf 'WINDOWS_TARGET=VERIFY_PACKAGED_WORLD_DATA\n'
"$GODOT_BIN" --headless --main-pack "$PCK_PATH" \
  --script res://tests/godot/test_windows_packaged_world_data.gd
