#!/usr/bin/env bash
# Validates an exact PR revision against local production data before launching Godot for any remaining human check.
# Dependencies: git, GitHub CLI auth, Python 3, tools/pr_check_scope.py, tools/pr_check_status.py, tools/run_pr_owned_check.sh, a local Godot executable, a C++20 compiler, ignored world_data, and Sweden PBF for stale/invalid routing rebuilds.
set -euo pipefail

PR="${1:-}"
[[ "$PR" =~ ^[1-9][0-9]*$ ]] || { printf 'PR_CHECK=FAIL invalid PR number\n' >&2; exit 64; }

ROOT="$(git rev-parse --show-toplevel)"
WORLD_DATA="$ROOT/world_data"
[[ -f "$ROOT/tools/pr_check_scope.py" ]] || { printf 'PR_CHECK=FAIL missing tools/pr_check_scope.py\n' >&2; exit 66; }
[[ -f "$ROOT/tools/pr_check_status.py" ]] || { printf 'PR_CHECK=FAIL missing tools/pr_check_status.py\n' >&2; exit 66; }
[[ -f "$ROOT/tools/run_pr_owned_check.sh" ]] || { printf 'PR_CHECK=FAIL missing tools/run_pr_owned_check.sh\n' >&2; exit 66; }

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

if ! command -v gh >/dev/null 2>&1; then
  printf 'PR_CHECK=FAIL GitHub CLI (gh) is required so local check results cannot be lost\n' >&2
  exit 69
fi

CURRENT_STAGE="resolve-head"
if ! PR_HEAD="$("$PYTHON_BIN" "$ROOT/tools/pr_check_status.py" resolve-head --pr "$PR")"; then
  printf 'PR_CHECK=FAIL unable to resolve PR head through authenticated GitHub CLI\n' >&2
  exit 69
fi

CURRENT_STAGE="starting"
if ! "$PYTHON_BIN" "$ROOT/tools/pr_check_status.py" record \
  --pr "$PR" --sha "$PR_HEAD" --state pending --stage "$CURRENT_STAGE"; then
  printf 'PR_CHECK=FAIL unable to persist pending local-check status to GitHub\n' >&2
  exit 69
fi
printf 'PR_CHECK=STATUS pending pr=%s revision=%s\n' "$PR" "${PR_HEAD:0:12}"

TMP=""
ADDED=0
STATUS_ACTIVE=1
AUTOMATED_SUCCESS=0
cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [[ "$status" -ne 0 && "$STATUS_ACTIVE" -eq 1 && "$AUTOMATED_SUCCESS" -eq 0 ]]; then
    "$PYTHON_BIN" "$ROOT/tools/pr_check_status.py" record \
      --pr "$PR" --sha "$PR_HEAD" --state failure --stage "$CURRENT_STAGE" >/dev/null 2>&1 || \
      printf 'PR_CHECK=WARNING failed to persist failure status; pending status remains and still blocks merge\n' >&2
  fi
  if [[ "$ADDED" -eq 1 && -n "$TMP" ]]; then
    git -C "$ROOT" worktree remove --force "$TMP" >/dev/null 2>&1 || true
  fi
  if [[ -n "$TMP" ]]; then
    rm -rf "$TMP"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

CURRENT_STAGE="local-prerequisites"
[[ -d "$WORLD_DATA" ]] || { printf 'PR_CHECK=FAIL missing %s\n' "$WORLD_DATA" >&2; exit 66; }
[[ -f "$WORLD_DATA/manifest.json" ]] || { printf 'PR_CHECK=FAIL missing %s/manifest.json\n' "$WORLD_DATA" >&2; exit 66; }

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

CURRENT_STAGE="runtime-ports"
printf 'PR_CHECK=PREPARE pr=%s\n' "$PR"
ensure_runtime_ports_free

CURRENT_STAGE="fetch-pr"
git -C "$ROOT" fetch --quiet origin "pull/${PR}/head"
FETCHED_HEAD="$(git -C "$ROOT" rev-parse FETCH_HEAD)"
if [[ "$FETCHED_HEAD" != "$PR_HEAD" ]]; then
  printf 'PR_CHECK=FAIL PR head moved while preparing check; rerun the Safe Check\n' >&2
  exit 75
fi

CURRENT_STAGE="fetch-main"
git -C "$ROOT" fetch --quiet origin main:refs/remotes/origin/main
MAIN_HEAD="$(git -C "$ROOT" rev-parse refs/remotes/origin/main)"
PR_BASE="$(git -C "$ROOT" merge-base "$MAIN_HEAD" "$PR_HEAD")"
CHANGED_FILES="$(git -C "$ROOT" diff --name-only "$PR_BASE" "$PR_HEAD")"
ROUTE_GEOMETRY_SCOPE="$(printf '%s\n' "$CHANGED_FILES" | "$PYTHON_BIN" "$ROOT/tools/pr_check_scope.py" route-geometry)"
case "$ROUTE_GEOMETRY_SCOPE" in
  required|skip) ;;
  *)
    printf 'PR_CHECK=FAIL invalid route-geometry scope decision: %s\n' "$ROUTE_GEOMETRY_SCOPE" >&2
    exit 70
    ;;
esac

CURRENT_STAGE="prepare-worktree"
git -C "$ROOT" worktree add --quiet --detach "$TMP" "$PR_HEAD"
ADDED=1

CURRENT_STAGE="routing-data"
if [[ -f "$TMP/tools/build_routing_dataset.py" ]] && ! routing_dataset_ready; then
  rebuild_routing_dataset
fi

rm -rf "$TMP/world_data"
ln -s "$WORLD_DATA" "$TMP/world_data"

CURRENT_STAGE="native-gps"
if [[ -f "$TMP/tools/build_native_gps.sh" ]]; then
  printf 'PR_CHECK=BUILD_NATIVE_GPS pr=%s\n' "$PR"
  bash "$TMP/tools/build_native_gps.sh"
fi

CURRENT_STAGE="route-geometry"
if [[ -f "$TMP/tools/check_route_geometry_dataset.py" ]]; then
  if [[ "$ROUTE_GEOMETRY_SCOPE" == "required" ]]; then
    printf 'PR_CHECK=CHECK_ROUTE_GEOMETRY_DATASET pr=%s\n' "$PR"
    if ! "$PYTHON_BIN" "$TMP/tools/check_route_geometry_dataset.py" "$WORLD_DATA"; then
      printf 'PR_CHECK=ROUTE_GEOMETRY_INVALID pr=%s rebuilding source-aligned routing dataset\n' "$PR"
      rebuild_routing_dataset
      printf 'PR_CHECK=RECHECK_ROUTE_GEOMETRY_DATASET pr=%s\n' "$PR"
      "$PYTHON_BIN" "$TMP/tools/check_route_geometry_dataset.py" "$WORLD_DATA"
    fi
  else
    printf 'PR_CHECK=SKIP_ROUTE_GEOMETRY_DATASET pr=%s reason=unrelated-changes\n' "$PR"
  fi
fi

CURRENT_STAGE="pr-owned-objective-checks"
bash "$ROOT/tools/run_pr_owned_check.sh" "$TMP" "$PR" "$WORLD_DATA" "$PYTHON_BIN" "$GODOT"

CURRENT_STAGE="objective-checks-complete"
"$PYTHON_BIN" "$ROOT/tools/pr_check_status.py" record \
  --pr "$PR" --sha "$PR_HEAD" --state success --stage "$CURRENT_STAGE"
AUTOMATED_SUCCESS=1
printf 'PR_CHECK=STATUS success pr=%s revision=%s\n' "$PR" "${PR_HEAD:0:12}"

printf 'PR_CHECK=RUN pr=%s revision=%s\n' "$PR" "$(git -C "$TMP" rev-parse --short HEAD)"
printf 'Automated local checks are persisted on GitHub. Any remaining Godot judgment is a separate human result.\n'
printf 'Close Godot when the check is complete; the temporary checkout will then be removed automatically.\n'
CURRENT_STAGE="human-godot-session"
"$GODOT" --path "$TMP"
