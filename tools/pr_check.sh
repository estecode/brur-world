#!/usr/bin/env bash
# Validates an exact PR revision against local production data before launching Godot for any remaining human check.
# Dependencies: git, Python 3, a local Godot executable, a C++20 compiler, ignored world_data, and Sweden PBF for stale/invalid routing rebuilds.
set -euo pipefail

PR="${1:-}"
[[ "$PR" =~ ^[1-9][0-9]*$ ]] || { printf 'PR_CHECK=FAIL invalid PR number\n' >&2; exit 64; }

ROOT="$(git rev-parse --show-toplevel)"
WORLD_DATA="$ROOT/world_data"
[[ -d "$WORLD_DATA" ]] || { printf 'PR_CHECK=FAIL missing %s\n' "$WORLD_DATA" >&2; exit 66; }
[[ -f "$WORLD_DATA/manifest.json" ]] || { printf 'PR_CHECK=FAIL missing %s/manifest.json\n' "$WORLD_DATA" >&2; exit 66; }

if [[ -x "$ROOT/.venv/bin/python" ]]; then
  PYTHON_BIN="$ROOT/.venv/bin/python"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python)"
else
  printf 'PR_CHECK=FAIL Python 3 not found\n' >&2
  exit 69
fi

if command -v godot >/dev/null 2>&1; then
  GODOT="$(command -v godot)"
elif [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
  GODOT=/Applications/Godot.app/Contents/MacOS/Godot
else
  printf 'PR_CHECK=FAIL Godot executable not found\n' >&2
  exit 69
fi

ensure_runtime_ports_free() {
  "$PYTHON_BIN" - <<'PY'
import socket

ports = (47741, 47742)
occupied = []
for port in ports:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(0.2)
    try:
        if sock.connect_ex(("127.0.0.1", port)) == 0:
            occupied.append(port)
    finally:
        sock.close()

if occupied:
    joined = ", ".join(str(port) for port in occupied)
    print(
        f"PR_CHECK=FAIL GPS runtime port(s) already in use: {joined}. "
        "Close any existing Brur World/Godot instance or native GPS server, then run Safe Check again."
    )
    raise SystemExit(1)
PY
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/brur-world-pr${PR}.XXXXXX")"
ADDED=0
cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [[ "$ADDED" -eq 1 ]]; then
    git -C "$ROOT" worktree remove --force "$TMP" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP"
  exit "$status"
}
trap cleanup EXIT INT TERM

routing_dataset_ready() {
  [[ -f "$WORLD_DATA/routing.brg" ]] || return 1
  [[ -f "$WORLD_DATA/routing_snap.brs" ]] || return 1
  [[ -f "$WORLD_DATA/routing_geometry.brh" ]] || return 1
  [[ -f "$WORLD_DATA/routing_stats.json" ]] || return 1
  "$PYTHON_BIN" - "$WORLD_DATA/routing_stats.json" <<'PY'
import json
import sys

try:
    report = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError):
    raise SystemExit(1)
raise SystemExit(0 if report.get("routing_dataset_format") == "BRG1+BRS2+BRH1" else 1)
PY
}

resolve_sweden_pbf() {
  if [[ -n "${BRUR_WORLD_PBF:-}" ]]; then
    [[ -f "$BRUR_WORLD_PBF" ]] || {
      printf 'PR_CHECK=FAIL BRUR_WORLD_PBF does not exist\n' >&2
      return 1
    }
    printf '%s\n' "$BRUR_WORLD_PBF"
    return 0
  fi

  local data_dir candidate
  data_dir="$(cd "$ROOT/.." && pwd)/data"
  candidate="$(find "$data_dir" -maxdepth 1 -type f -name 'sweden-*.osm.pbf' -print 2>/dev/null | LC_ALL=C sort | tail -n 1)"
  if [[ -z "$candidate" ]]; then
    printf 'PR_CHECK=FAIL routing dataset is stale/invalid and no Sweden PBF was found; set BRUR_WORLD_PBF\n' >&2
    return 1
  fi
  printf '%s\n' "$candidate"
}

rebuild_routing_dataset() {
  [[ -f "$TMP/tools/build_routing_dataset.py" ]] || {
    printf 'PR_CHECK=FAIL PR has no routing dataset builder\n' >&2
    return 1
  }
  local pbf
  pbf="$(resolve_sweden_pbf)"
  printf 'PR_CHECK=BUILD_ROUTING_DATASET pr=%s source=%s\n' "$PR" "$(basename "$pbf")"
  "$PYTHON_BIN" "$TMP/tools/build_routing_dataset.py" "$pbf" --output "$WORLD_DATA"
}

route_geometry_check_needed() {
  git -C "$TMP" diff --name-only "$PR_BASE_SHA...HEAD" | grep -Eq '^((native/gps_route[^/]*\.(cpp|h))|(tools/(build_routing(_dataset)?|build_sweden|check_route_geometry_dataset|compressed_routing|route_geometry|routing_graph[^/]*|world_common)\.py))$'
}

printf 'PR_CHECK=PREPARE pr=%s\n' "$PR"
ensure_runtime_ports_free
# Fetch main separately so scope checks compare the exact PR head with the current remote base.
git -C "$ROOT" fetch --quiet origin main
PR_BASE_SHA="$(git -C "$ROOT" rev-parse FETCH_HEAD)"
git -C "$ROOT" fetch --quiet origin "pull/${PR}/head"
git -C "$ROOT" worktree add --quiet --detach "$TMP" FETCH_HEAD
ADDED=1

if [[ -f "$TMP/tools/build_routing_dataset.py" ]] && ! routing_dataset_ready; then
  rebuild_routing_dataset
fi

rm -rf "$TMP/world_data"
ln -s "$WORLD_DATA" "$TMP/world_data"

if [[ -f "$TMP/tools/build_city_light_density.py" && -f "$TMP/tools/test_city_lights_real_data.sh" ]]; then
  [[ -d "$WORLD_DATA/poi_tiles" ]] || { printf 'PR_CHECK=FAIL missing runtime POI tiles for city-light density\n' >&2; exit 66; }
  printf 'PR_CHECK=BUILD_CITY_LIGHT_DENSITY pr=%s\n' "$PR"
  "$PYTHON_BIN" "$TMP/tools/build_city_light_density.py" "$WORLD_DATA"
  printf 'PR_CHECK=CHECK_CITY_LIGHTS_REAL_DATA pr=%s\n' "$PR"
  GODOT_BIN="$GODOT" bash "$TMP/tools/test_city_lights_real_data.sh"
fi

if [[ -f "$TMP/tools/build_native_gps.sh" ]]; then
  printf 'PR_CHECK=BUILD_NATIVE_GPS pr=%s\n' "$PR"
  bash "$TMP/tools/build_native_gps.sh"
fi

if [[ -f "$TMP/tools/check_route_geometry_dataset.py" ]]; then
  if route_geometry_check_needed; then
    printf 'PR_CHECK=CHECK_ROUTE_GEOMETRY_DATASET pr=%s\n' "$PR"
    if ! "$PYTHON_BIN" "$TMP/tools/check_route_geometry_dataset.py" "$WORLD_DATA"; then
      printf 'PR_CHECK=ROUTE_GEOMETRY_INVALID pr=%s rebuilding source-aligned routing dataset\n' "$PR"
      rebuild_routing_dataset
      printf 'PR_CHECK=RECHECK_ROUTE_GEOMETRY_DATASET pr=%s\n' "$PR"
      "$PYTHON_BIN" "$TMP/tools/check_route_geometry_dataset.py" "$WORLD_DATA"
    fi
  else
    printf 'PR_CHECK=SKIP_ROUTE_GEOMETRY_DATASET pr=%s reason=unrelated_changes\n' "$PR"
  fi
fi

printf 'PR_CHECK=RUN pr=%s revision=%s\n' "$PR" "$(git -C "$TMP" rev-parse --short HEAD)"
printf 'Close Godot when the check is complete; the temporary checkout will then be removed automatically.\n'
"$GODOT" --path "$TMP"
