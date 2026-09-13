#!/usr/bin/env bash
# Prepares the runtime dependencies required by a supported manual playtest target and launches Godot.
# Dependencies: project-owned world/native builders, local generated world_data where required, and a local Godot executable.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-}"
WORLD_DATA="$ROOT/world_data"
PBF="${BRUR_WORLD_PBF:-}"

usage() {
  printf 'Usage: %s <game|gps|driving>\n' "$0" >&2
}

fail() {
  printf 'PLAYTEST=FAIL %s\n' "$*" >&2
  exit 66
}

case "$TARGET" in
  game|gps|driving) ;;
  "") usage; exit 64 ;;
  *) printf 'PLAYTEST=FAIL unsupported target: %s\n' "$TARGET" >&2; usage; exit 64 ;;
esac

if [[ -n "$PBF" && ! -f "$PBF" ]]; then
  fail "BRUR_WORLD_PBF does not exist: $PBF"
fi

resolve_godot() {
  if [[ -n "${BRUR_GODOT:-}" ]]; then
    [[ -x "$BRUR_GODOT" ]] || fail "BRUR_GODOT is not executable: $BRUR_GODOT"
    printf '%s\n' "$BRUR_GODOT"
    return
  fi
  if [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
    printf '%s\n' /Applications/Godot.app/Contents/MacOS/Godot
    return
  fi
  if command -v godot >/dev/null 2>&1; then
    command -v godot
    return
  fi
  fail "Godot not found; install it at /Applications/Godot.app or set BRUR_GODOT"
}

resolve_python() {
  if [[ -x "$ROOT/.venv/bin/python" ]]; then
    printf '%s\n' "$ROOT/.venv/bin/python"
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    command -v python3
    return
  fi
  fail "Python 3 not found"
}

ensure_python_dependencies() {
  if [[ ! -x "$ROOT/.venv/bin/python" ]]; then
    local system_python
    system_python="$(resolve_python)"
    printf 'PLAYTEST=PREPARE python-venv\n' >&2
    "$system_python" -m venv "$ROOT/.venv"
  fi
  local python="$ROOT/.venv/bin/python"
  if ! "$python" -c 'import osmium, shapely' >/dev/null 2>&1; then
    printf 'PLAYTEST=PREPARE python-dependencies\n' >&2
    "$python" -m pip install -q -r "$ROOT/requirements.txt"
  fi
  printf '%s\n' "$python"
}

require_pbf() {
  if [[ -z "$PBF" ]]; then
    fail "runtime data needs rebuilding; set BRUR_WORLD_PBF to the Sweden .osm.pbf file"
  fi
}

fingerprint_files() {
  local file
  for file in "$@"; do
    if [[ -f "$file" ]]; then
      cksum "$file"
    fi
  done | cksum | awk '{print $1 ":" $2}'
}

stamp_mismatch() {
  local stamp="$1"
  local expected="$2"
  [[ -f "$stamp" ]] || return 1
  [[ "$(cat "$stamp")" != "$expected" ]]
}

ensure_native() {
  local sources=()
  while IFS= read -r source; do
    sources+=("$source")
  done < <(find "$ROOT/native" -type f \( -name '*.cpp' -o -name '*.h' \) | sort)
  local fingerprint
  fingerprint="$(fingerprint_files "${sources[@]}")"
  local stamp="$ROOT/bin/.playtest_native_fingerprint"
  local rebuild=0
  local binary
  for binary in "$@"; do
    if [[ ! -x "$ROOT/bin/$binary" ]]; then
      rebuild=1
      break
    fi
  done
  if [[ "$rebuild" -eq 0 ]] && stamp_mismatch "$stamp" "$fingerprint"; then
    rebuild=1
  fi
  if [[ "$rebuild" -eq 1 ]]; then
    printf 'PLAYTEST=PREPARE native-gps rebuild\n'
    bash "$ROOT/tools/build_native_gps.sh"
    mkdir -p "$ROOT/bin"
    printf '%s\n' "$fingerprint" > "$stamp"
  else
    printf 'PLAYTEST=READY native-gps\n'
  fi
  for binary in "$@"; do
    [[ -x "$ROOT/bin/$binary" ]] || fail "native build did not produce bin/$binary"
  done
}

routing_dataset_valid() {
  [[ -f "$ROOT/tools/check_routing_dataset.py" ]] || return 1
  local python
  python="$(resolve_python)"
  "$python" "$ROOT/tools/check_routing_dataset.py" "$WORLD_DATA" >/dev/null
}

ensure_gps_data() {
  mkdir -p "$WORLD_DATA"
  local required=(
    "$WORLD_DATA/routing.brg"
    "$WORLD_DATA/routing_snap.brs"
    "$WORLD_DATA/routing_geometry.brh"
    "$WORLD_DATA/routing_stats.json"
  )
  local rebuild=0
  local artifact
  for artifact in "${required[@]}"; do
    [[ -f "$artifact" ]] || rebuild=1
  done
  if [[ "$rebuild" -eq 0 ]] && ! routing_dataset_valid; then
    rebuild=1
  fi

  # The offline build pipeline owns runtime-data freshness. A successful manual
  # build is already authoritative; playtest only checks that its required
  # artifacts exist and that the routing generation is internally consistent.
  if [[ "$rebuild" -eq 1 ]]; then
    require_pbf
    local python
    python="$(ensure_python_dependencies)"
    printf 'PLAYTEST=PREPARE routing-dataset rebuild\n'
    "$python" "$ROOT/tools/build_routing_dataset.py" "$PBF" --output "$WORLD_DATA"
  else
    printf 'PLAYTEST=READY routing-dataset\n'
  fi

  for artifact in "${required[@]}"; do
    [[ -f "$artifact" ]] || fail "missing $artifact after preparation"
  done
  routing_dataset_valid || fail "routing dataset failed identity validation after preparation"
}

ensure_game_data() {
  mkdir -p "$WORLD_DATA"
  local required=(
    "$WORLD_DATA/manifest.json"
    "$WORLD_DATA/routing.brg"
    "$WORLD_DATA/routing_snap.brs"
    "$WORLD_DATA/routing_geometry.brh"
    "$WORLD_DATA/routing_stats.json"
    "$WORLD_DATA/search_index.bsi"
  )
  local rebuild=0
  local artifact
  for artifact in "${required[@]}"; do
    [[ -f "$artifact" ]] || rebuild=1
  done
  if [[ "$rebuild" -eq 0 ]] && ! routing_dataset_valid; then
    rebuild=1
  fi

  # World data is owned by build_sweden and its dataset validators. Do not
  # second-guess an already-valid build using playtest-private fingerprints or
  # source-file mtimes; those can drift independently and cause full duplicate
  # Sweden builds immediately after a successful offline build.
  if [[ "$rebuild" -eq 1 ]]; then
    require_pbf
    local python
    python="$(ensure_python_dependencies)"
    printf 'PLAYTEST=PREPARE world rebuild\n'
    "$python" "$ROOT/tools/build_sweden.py" "$PBF" --output "$WORLD_DATA"
  else
    printf 'PLAYTEST=READY world-data\n'
  fi

  for artifact in "${required[@]}"; do
    [[ -f "$artifact" ]] || fail "world build did not produce $artifact"
  done
  routing_dataset_valid || fail "routing dataset failed identity validation after world preparation"
}

GODOT="$(resolve_godot)"
SCENE=""
case "$TARGET" in
  game)
    ensure_game_data
    ensure_native brur-gps-server brur-gps-search-server
    SCENE="$ROOT/scenes/main.tscn"
    ;;
  gps)
    ensure_gps_data
    ensure_native brur-gps-server
    SCENE="$ROOT/harness/gps/gps_harness.tscn"
    ;;
  driving)
    # The driving harness is intentionally synthetic at the world boundary and
    # uses production vehicle/camera code, so it needs no Sweden data or native GPS process.
    SCENE="$ROOT/harness/driving/driving_harness.tscn"
    ;;
esac

[[ -f "$SCENE" ]] || fail "playtest scene missing: $SCENE"
printf 'PLAYTEST=RUN target=%s scene=%s\n' "$TARGET" "${SCENE#$ROOT/}"
exec "$GODOT" --path "$ROOT" "$SCENE"
