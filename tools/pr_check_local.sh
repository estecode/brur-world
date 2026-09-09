#!/usr/bin/env bash
# Validates the traffic-signal compiler against the authoritative local Sweden PBF for this PR.
# Dependencies: tools/build_traffic_signals.py plus BRUR PR-check environment paths.
set -euo pipefail

WORKTREE="${BRUR_PR_CHECK_WORKTREE:?}"
WORLD_DATA="${BRUR_PR_CHECK_WORLD_DATA:?}"
PYTHON="${PYTHON_BIN:?}"

resolve_sweden_pbf() {
  if [[ -n "${BRUR_WORLD_PBF:-}" ]]; then
    [[ -f "$BRUR_WORLD_PBF" ]] || { printf 'PR_CHECK=FAIL BRUR_WORLD_PBF does not exist\n' >&2; return 1; }
    printf '%s\n' "$BRUR_WORLD_PBF"
    return 0
  fi

  local root data_dir candidate
  root="$(dirname "$WORLD_DATA")"
  data_dir="$(cd "$root/.." && pwd)/data"
  candidate="$(find "$data_dir" -maxdepth 1 -type f -name 'sweden-*.osm.pbf' -print 2>/dev/null | LC_ALL=C sort | tail -n 1)"
  [[ -n "$candidate" ]] || { printf 'PR_CHECK=FAIL no Sweden PBF was found; set BRUR_WORLD_PBF\n' >&2; return 1; }
  printf '%s\n' "$candidate"
}

pbf="$(resolve_sweden_pbf)"
output="$WORKTREE/.pr-check-traffic-signals"
mkdir -p "$output"

printf 'PR_CHECK=CHECK_TRAFFIC_SIGNALS_REAL_DATA pr=%s source=%s\n' "${BRUR_PR_CHECK_PR:?}" "$(basename "$pbf")"
"$PYTHON" "$WORKTREE/tools/build_traffic_signals.py" "$pbf" --output "$output"
"$PYTHON" - "$output/traffic_signals.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    payload = json.loads(path.read_text(encoding="utf-8"))
except (OSError, ValueError) as exc:
    print(f"PR_CHECK=FAIL invalid traffic-signal output: {exc}")
    raise SystemExit(1)

stats = payload.get("stats", {})
source = int(stats.get("source_signal_count", -1))
exported = int(stats.get("exported_signal_count", -1))
if source != 6974:
    print(f"PR_CHECK=FAIL expected 6974 source signals, got {source}")
    raise SystemExit(1)
if exported != source:
    print(f"PR_CHECK=FAIL exported {exported} of {source} source signals")
    raise SystemExit(1)

print(
    "PR_CHECK=TRAFFIC_SIGNALS_REAL_DATA_OK "
    f"source={source} exported={exported} "
    f"explicit={stats.get('explicit_direction_count')} "
    f"legacy={stats.get('legacy_direction_count')} "
    f"inferred={stats.get('inferred_direction_count')} "
    f"unknown={stats.get('unknown_direction_count')} "
    f"stop_lines={stats.get('explicit_stop_line_count')} "
    f"grouped={stats.get('grouped_candidate_count')} "
    f"ungrouped={stats.get('ungrouped_candidate_count')}"
)
PY
