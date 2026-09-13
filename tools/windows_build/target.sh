#!/usr/bin/env bash
# Exports the selected revision while reusing a cached external production world-data resource pack.
# Dependencies: runtime_pack.py, project.godot production startup scene, Windows export preset, Godot, authoritative local world_data.
set -euo pipefail

: "${BRUR_WINDOWS_SOURCE_ROOT:?}"
: "${BRUR_WINDOWS_WORLD_DATA:?}"
: "${BRUR_WINDOWS_EXPORT_DIR:?}"
: "${BRUR_WINDOWS_BUILD_NAME:?}"
: "${GODOT_BIN:?}"
PYTHON="${PYTHON_BIN:-python3}"
CACHE_DIR="${BRUR_WINDOWS_CACHE_DIR:-$HOME/.cache/brur-world/windows-build}"

# The current main launcher still provides BRUR_WINDOWS_RUNTIME_DATA_OUT while
# this PR's build.sh provides BRUR_WINDOWS_RUNTIME_PACK_INFO. Support both so a
# PR can be tested safely through the stable main Safe Command bootstrap before merge.
RUNTIME_PACK_INFO="${BRUR_WINDOWS_RUNTIME_PACK_INFO:-}"
if [[ -z "$RUNTIME_PACK_INFO" ]]; then
  LEGACY_RUNTIME_OUT="${BRUR_WINDOWS_RUNTIME_DATA_OUT:-}"
  [[ -n "$LEGACY_RUNTIME_OUT" ]] || {
    printf 'WINDOWS_TARGET=FAIL missing runtime pack output contract\n' >&2
    exit 64
  }
  mkdir -p "$LEGACY_RUNTIME_OUT"
  RUNTIME_PACK_INFO="$LEGACY_RUNTIME_OUT/runtime_pack_info.json"
fi

printf 'WINDOWS_BUILD=RUNTIME_PACK checking reusable world-data pack\n'
TIMEFORMAT='WINDOWS_TIMING stage=runtime_pack seconds=%3R'
time "$PYTHON" "$BRUR_WINDOWS_SOURCE_ROOT/tools/windows_build/runtime_pack.py" \
  "$BRUR_WINDOWS_WORLD_DATA" \
  --cache-dir "$CACHE_DIR" \
  --output-info "$RUNTIME_PACK_INFO"

RUNTIME_PACK_PATH="$($PYTHON - "$RUNTIME_PACK_INFO" <<'PY'
import json, pathlib, sys
info = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
path = pathlib.Path(info["pack_path"])
if not path.is_file() or path.stat().st_size <= 0:
    raise SystemExit(f"WINDOWS_TARGET=FAIL missing runtime pack: {path}")
print(path)
PY
)"

printf 'WINDOWS_TARGET=EXPORT name=%s runtime_pack=%s\n' "$BRUR_WINDOWS_BUILD_NAME" "$RUNTIME_PACK_PATH"
EXPORT_LOG="$(mktemp "${TMPDIR:-/tmp}/brur-windows-export.XXXXXX.log")"
cleanup_export_log() {
  rm -f "$EXPORT_LOG"
}
trap cleanup_export_log EXIT INT TERM

set +e
TIMEFORMAT='WINDOWS_TIMING stage=godot_export seconds=%3R'
time "$GODOT_BIN" --headless --path "$BRUR_WINDOWS_SOURCE_ROOT" \
  --export-release "Windows Desktop" "$BRUR_WINDOWS_EXPORT_DIR/$BRUR_WINDOWS_BUILD_NAME.exe" \
  2>&1 | tee "$EXPORT_LOG"
GODOT_EXPORT_STATUS=${PIPESTATUS[0]}
set -e
if [[ "$GODOT_EXPORT_STATUS" -ne 0 ]]; then
  printf 'WINDOWS_TARGET=FAIL Godot export exited with status %s\n' "$GODOT_EXPORT_STATUS" >&2
  exit "$GODOT_EXPORT_STATUS"
fi
if grep -Eq 'SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script' "$EXPORT_LOG"; then
  printf 'WINDOWS_TARGET=FAIL Godot export reported script compile errors\n' >&2
  exit 1
fi

PCK_PATH="$BRUR_WINDOWS_EXPORT_DIR/$BRUR_WINDOWS_BUILD_NAME.pck"
[[ -s "$PCK_PATH" ]] || { printf 'WINDOWS_TARGET=FAIL missing exported PCK\n' >&2; exit 1; }
printf 'WINDOWS_TARGET=VERIFY_EXTERNAL_WORLD_DATA\n'
printf 'WINDOWS_TARGET=VERIFY isolated_from_source_world_data\n'
TIMEFORMAT='WINDOWS_TIMING stage=runtime_pack_verify seconds=%3R'
time (
  cd "$BRUR_WINDOWS_EXPORT_DIR"
  "$GODOT_BIN" --headless --main-pack "$PCK_PATH" \
    --script res://tests/godot/test_windows_packaged_world_data.gd -- "$RUNTIME_PACK_PATH"
)

trap - EXIT INT TERM
cleanup_export_log
