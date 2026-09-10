#!/usr/bin/env bash
# Prepares the current repository Windows showcase target using existing runtime data and production scenes.
# Dependencies: prepare_world_showcase.py, project.godot, Windows export preset, Godot, authoritative local world_data.
set -euo pipefail

: "${BRUR_WINDOWS_SOURCE_ROOT:?}"
: "${BRUR_WINDOWS_WORLD_DATA:?}"
: "${BRUR_WINDOWS_RUNTIME_DATA_OUT:?}"
: "${BRUR_WINDOWS_EXPORT_DIR:?}"
: "${BRUR_WINDOWS_BUILD_NAME:?}"
: "${GODOT_BIN:?}"
PYTHON="${PYTHON_BIN:-python3}"

for required in manifest.json buildings.jsonl background.brmap; do
  [[ -s "$BRUR_WINDOWS_WORLD_DATA/$required" ]] || {
    printf 'WINDOWS_TARGET=FAIL missing runtime source: %s\n' "$BRUR_WINDOWS_WORLD_DATA/$required" >&2
    exit 66
  }
done

"$PYTHON" "$BRUR_WINDOWS_SOURCE_ROOT/tools/prepare_world_showcase.py" \
  "$BRUR_WINDOWS_WORLD_DATA" --output "$BRUR_WINDOWS_RUNTIME_DATA_OUT"

"$PYTHON" - "$BRUR_WINDOWS_SOURCE_ROOT/project.godot" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = 'run/main_scene="res://harness/world_showcase/world_showcase.tscn"'
new = 'run/main_scene="res://harness/world_showcase/world_showcase_windows.tscn"'
if new not in text:
    if old not in text:
        raise SystemExit("WINDOWS_TARGET=FAIL expected showcase main scene was not found")
    path.write_text(text.replace(old, new), encoding="utf-8")
PY

printf 'WINDOWS_TARGET=EXPORT name=%s\n' "$BRUR_WINDOWS_BUILD_NAME"
"$GODOT_BIN" --headless --path "$BRUR_WINDOWS_SOURCE_ROOT" \
  --export-release "Windows Desktop" "$BRUR_WINDOWS_EXPORT_DIR/$BRUR_WINDOWS_BUILD_NAME.exe"
