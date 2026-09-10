#!/usr/bin/env bash
# Prepares and objectively validates the isolated #126 world showcase from existing runtime data only.
# Dependencies: tools/prepare_world_showcase.py, existing world_data/buildings.jsonl, and Godot supplied by PR check.
set -euo pipefail

WORKTREE="${BRUR_PR_CHECK_WORKTREE:?}"
WORLD_DATA="${BRUR_PR_CHECK_WORLD_DATA:?}"
PYTHON="${PYTHON_BIN:?}"
GODOT="${GODOT_BIN:?}"
CACHE="$WORKTREE/.poc_runtime/world_showcase"

printf 'PR_CHECK=PREPARE_WORLD_SHOWCASE pr=%s source=existing-buildings-jsonl\n' "${BRUR_PR_CHECK_PR:?}"
"$PYTHON" "$WORKTREE/tools/prepare_world_showcase.py" "$WORLD_DATA" --output "$CACHE"

"$PYTHON" - "$CACHE/showcase_manifest.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
report = json.loads(path.read_text(encoding="utf-8"))
if report.get("source_rebuilt") is not False:
    print("PR_CHECK=FAIL world showcase unexpectedly rebuilt source data")
    raise SystemExit(1)
if int(report.get("selected_records", 0)) <= 0 or int(report.get("tile_count", 0)) <= 0:
    print("PR_CHECK=FAIL world showcase cache is empty")
    raise SystemExit(1)
missing = [name for name, count in report.get("selected_by_city", {}).items() if int(count) <= 0]
if missing:
    print("PR_CHECK=FAIL missing showcase city building data: " + ", ".join(missing))
    raise SystemExit(1)
print(
    "PR_CHECK=WORLD_SHOWCASE_REAL_DATA_OK "
    f"selected={report['selected_records']} tiles={report['tile_count']} "
    f"cities={report['selected_by_city']} source_rebuilt={report['source_rebuilt']}"
)
PY

run_godot_test() {
  local script="$1"
  local log status
  log="$(mktemp "${TMPDIR:-/tmp}/brur-world-showcase-test.XXXXXX.log")"
  set +e
  "$GODOT" --headless --path "$WORKTREE" --script "$script" 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  set -e
  if [[ $status -ne 0 ]]; then
    printf 'PR_CHECK=FAIL Godot exited %d for %s\n' "$status" "$script" >&2
    rm -f "$log"
    return 1
  fi
  if grep -Eq 'SCRIPT ERROR:|Failed to load script|world (streaming foundation|showcase) test failed:' "$log"; then
    printf 'PR_CHECK=FAIL Godot reported script/test errors for %s\n' "$script" >&2
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
}

printf 'PR_CHECK=CHECK_WORLD_SHOWCASE_HEADLESS pr=%s\n' "${BRUR_PR_CHECK_PR:?}"
run_godot_test res://tests/godot/test_world_streaming_foundation.gd
run_godot_test res://tests/godot/test_world_showcase.gd
