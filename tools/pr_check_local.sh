#!/usr/bin/env bash
# Prepares real-data checks and runs the issue #136 renderer benchmark without manual FPS judgment.
# Dependencies: existing local world_data, GitHub CLI auth, city-light/world-showcase tooling, and Godot supplied by PR check.
set -euo pipefail

WORKTREE="${BRUR_PR_CHECK_WORKTREE:?}"
WORLD_DATA="${BRUR_PR_CHECK_WORLD_DATA:?}"
PYTHON="${PYTHON_BIN:?}"
GODOT="${GODOT_BIN:?}"
PR="${BRUR_PR_CHECK_PR:?}"
CACHE="$WORKTREE/.poc_runtime/world_showcase"

[[ -d "$WORLD_DATA/poi_tiles" ]] || { printf 'PR_CHECK=FAIL missing runtime POI tiles for city-light density\n' >&2; exit 66; }

printf 'PR_CHECK=BUILD_CITY_LIGHT_DENSITY pr=%s\n' "$PR"
"$PYTHON" "$WORKTREE/tools/build_city_light_density.py" "$WORLD_DATA"
printf 'PR_CHECK=CHECK_CITY_LIGHTS_REAL_DATA pr=%s\n' "$PR"
GODOT_BIN="$GODOT" bash "$WORKTREE/tools/test_city_lights_real_data.sh"

printf 'PR_CHECK=PREPARE_WORLD_SHOWCASE pr=%s source=existing-runtime-data\n' "$PR"
"$PYTHON" "$WORKTREE/tools/prepare_world_showcase.py" "$WORLD_DATA" --output "$CACHE"

"$PYTHON" - "$CACHE/showcase_manifest.json" "$CACHE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
cache = Path(sys.argv[2])
report = json.loads(path.read_text(encoding="utf-8"))
if report.get("source_rebuilt") is not False:
    print("PR_CHECK=FAIL world showcase unexpectedly rebuilt source data")
    raise SystemExit(1)
if int(report.get("selected_records", 0)) <= 0 or int(report.get("tile_count", 0)) <= 0:
    print("PR_CHECK=FAIL world showcase building cache is empty")
    raise SystemExit(1)
missing = [name for name, count in report.get("selected_by_city", {}).items() if int(count) <= 0]
if missing:
    print("PR_CHECK=FAIL missing showcase city building data: " + ", ".join(missing))
    raise SystemExit(1)
background = report.get("background_triangles_by_city", {})
missing_background = [name for name in ("malmo", "goteborg", "stockholm") if int(background.get(name, 0)) <= 0]
if missing_background:
    print("PR_CHECK=FAIL missing showcase city background data: " + ", ".join(missing_background))
    raise SystemExit(1)
missing_files = [name for name in background if not (cache / f"background_{name}.brmap").is_file()]
if missing_files:
    print("PR_CHECK=FAIL missing local BRM2 files: " + ", ".join(missing_files))
print(
    "PR_CHECK=WORLD_SHOWCASE_REAL_DATA_OK "
    f"selected={report['selected_records']} tiles={report['tile_count']} "
    f"cities={report['selected_by_city']} background={background} "
    f"source_rebuilt={report['source_rebuilt']}"
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

printf 'PR_CHECK=CHECK_WORLD_SHOWCASE_HEADLESS pr=%s\n' "$PR"
run_godot_test res://tests/godot/test_world_streaming_foundation.gd
run_godot_test res://tests/godot/test_world_showcase.gd

wait_runtime_ports_free() {
  "$PYTHON" - <<'PY'
import socket
import time

ports = (47741, 47742)
for _ in range(120):
    occupied = []
    for port in ports:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(0.1)
        try:
            if sock.connect_ex(("127.0.0.1", port)) == 0:
                occupied.append(port)
        finally:
            sock.close()
    if not occupied:
        raise SystemExit(0)
    time.sleep(0.1)
print("PR_CHECK=FAIL renderer benchmark left GPS runtime ports occupied")
raise SystemExit(1)
PY
}

run_renderer_benchmark() {
  local label="$1"
  shift
  local log="$CACHE/renderer-${label}.log"
  printf 'PR_CHECK=RENDER_BENCHMARK pr=%s variant=%s\n' "$PR" "$label"
  set +e
  "$GODOT" --path "$WORKTREE" "$@" res://harness/perf_diagnostic/renderer_benchmark.tscn 2>&1 | tee "$log"
  local status=${PIPESTATUS[0]}
  set -e
  if [[ $status -ne 0 ]]; then
    printf 'PR_CHECK=FAIL renderer benchmark %s exited %d\n' "$label" "$status" >&2
    return 1
  fi
  if ! grep -q '^PERF_RENDER_DIAG complete ' "$log"; then
    printf 'PR_CHECK=FAIL renderer benchmark %s produced no completion marker\n' "$label" >&2
    return 1
  fi
  wait_runtime_ports_free
}

# These are real-window runs on the project leader machine. They measure the
# actual renderer while the harness changes variants and exits automatically.
run_renderer_benchmark project-default

MOBILE_STATUS=0
set +e
run_renderer_benchmark mobile --rendering-method mobile
MOBILE_STATUS=$?
set -e
if [[ $MOBILE_STATUS -ne 0 ]]; then
  printf 'PR_CHECK=RENDER_BENCHMARK mobile-unavailable status=%d\n' "$MOBILE_STATUS"
fi

REPORT="$CACHE/renderer-report.md"
{
  printf '### Automated renderer benchmark for PR #%s\n\n' "$PR"
  printf 'No manual FPS judgment was used. These lines were produced by timed real-window Godot runs on the local machine.\n\n'
  printf '```text\n'
  grep '^PERF_RENDER_DIAG' "$CACHE/renderer-project-default.log" || true
  if [[ -f "$CACHE/renderer-mobile.log" ]]; then
    grep '^PERF_RENDER_DIAG' "$CACHE/renderer-mobile.log" || true
  fi
  printf '```\n'
} > "$REPORT"

gh pr comment "$PR" --body-file "$REPORT" >/dev/null
printf 'PR_CHECK=RENDER_REPORT posted-to-pr=%s\n' "$PR"

# The outer PR-check launcher always opens Godot after objective checks. This
# diagnostic has no remaining visual judgment, so make that final temporary
# launch exit immediately instead of asking the project leader to test again.
"$PYTHON" - "$WORKTREE/project.godot" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text, count = re.subn(
    r'run/main_scene="[^"]+"',
    'run/main_scene="res://harness/perf_diagnostic/auto_quit.tscn"',
    text,
    count=1,
)
if count != 1:
    print("PR_CHECK=FAIL unable to install temporary auto-quit scene")
    raise SystemExit(1)
path.write_text(text, encoding="utf-8")
PY
