#!/usr/bin/env bash
# Prepares and validates the isolated #122 world-streaming POC from existing runtime building data only.
# Dependencies: tools/prepare_building_poc.py, existing world_data/buildings.jsonl, and Godot supplied by PR check.
set -euo pipefail

WORKTREE="${BRUR_PR_CHECK_WORKTREE:?}"
WORLD_DATA="${BRUR_PR_CHECK_WORLD_DATA:?}"
PYTHON="${PYTHON_BIN:?}"
GODOT="${GODOT_BIN:?}"
CACHE="$WORKTREE/.poc_runtime/buildings"

printf 'PR_CHECK=PREPARE_WORLD_STREAMING_POC pr=%s source=existing-buildings-jsonl\n' "${BRUR_PR_CHECK_PR:?}"
"$PYTHON" "$WORKTREE/tools/prepare_building_poc.py" "$WORLD_DATA" --output "$CACHE"

"$PYTHON" - "$CACHE/poc_manifest.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
report = json.loads(path.read_text(encoding="utf-8"))
if report.get("source_rebuilt") is not False:
    print("PR_CHECK=FAIL world-streaming POC unexpectedly rebuilt source data")
    raise SystemExit(1)
selected_by_city = report.get("selected_by_city", {})
missing = [city for city in ("malmo", "goteborg", "stockholm") if int(selected_by_city.get(city, 0)) <= 0]
if missing:
    print("PR_CHECK=FAIL missing real building data for " + ",".join(missing))
    raise SystemExit(1)
if int(report.get("tile_count", 0)) <= 0:
    print("PR_CHECK=FAIL no building POC tiles prepared")
    raise SystemExit(1)
print(
    "PR_CHECK=WORLD_STREAMING_REAL_DATA_OK "
    f"selected={report['selected_records']} tiles={report['tile_count']} "
    f"cities={selected_by_city} scanned={report['scanned_records']} "
    f"source_rebuilt={report['source_rebuilt']}"
)
PY

printf 'PR_CHECK=CHECK_WORLD_STREAMING_POC_HEADLESS pr=%s\n' "${BRUR_PR_CHECK_PR:?}"
"$GODOT" --headless --path "$WORKTREE" --script res://tests/godot/test_building_poc.gd
