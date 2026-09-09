#!/usr/bin/env bash
# Runs deterministic/headless city-light model, POI-density builder, and renderer validation.
# Dependencies: Python 3, Godot 4, build_city_light_density.py, and tests/godot/test_city_lights.gd.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/brur-city-light-test.XXXXXX")"
cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/poi_tiles"
printf '%s\n' \
  '{"x":100.0,"y":100.0,"category":"shop"}' \
  '{"x":200.0,"y":200.0,"category":"hospital"}' \
  '{"x":4100.0,"y":100.0,"category":"fuel"}' \
  > "$TMP/poi_tiles/0_0.jsonl"
printf '{}\n' > "$TMP/manifest.json"
"$PYTHON_BIN" "$ROOT/tools/build_city_light_density.py" "$TMP"
"$PYTHON_BIN" - "$TMP" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
records = [json.loads(line) for line in (root / "city_light_density.jsonl").read_text().splitlines() if line]
assert len(records) == 2, records
assert sorted(record["count"] for record in records) == [1, 2], records
manifest = json.loads((root / "manifest.json").read_text())
meta = manifest["city_light_density"]
assert meta["format"] == "CLD1", meta
assert meta["runtime_pois"] == 3, meta
assert meta["cells"] == 2, meta
print("city light density builder tests: OK")
PY

if [[ -n "${GODOT_BIN:-}" ]]; then
  GODOT="$GODOT_BIN"
elif command -v godot >/dev/null 2>&1; then
  GODOT="$(command -v godot)"
elif [[ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]]; then
  GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
else
  echo "city light tests: Godot executable not found" >&2
  exit 1
fi

set +e
output="$($GODOT --headless --path "$ROOT" --script tests/godot/test_city_lights.gd 2>&1)"
status=$?
set -e
printf '%s\n' "$output"

if [[ $status -ne 0 ]]; then
  echo "city light tests: Godot exited with status $status" >&2
  exit $status
fi
error_output="$(grep -E 'SCRIPT ERROR:|Parse Error:|Failed to load script|^ERROR:' <<<"$output" | grep -Ev '^ERROR: [0-9]+ resources still in use at exit' || true)"
if [[ -n "$error_output" ]]; then
  echo "city light tests: Godot reported an error" >&2
  exit 1
fi
if ! grep -Fq 'godot city light tests: OK' <<<"$output"; then
  echo "city light tests: success marker missing" >&2
  exit 1
fi

echo "city light automated tests: OK"
