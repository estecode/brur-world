#!/usr/bin/env bash
# Prepares the runtime dependencies required by a supported manual playtest target and launches Godot.
# Dependencies: project-owned world/native builders, local generated world_data, and a local Godot executable.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-}"
WORLD_DATA="$ROOT/world_data"
PBF="${BRUR_WORLD_PBF:-}"

usage() {
  printf 'Usage: %s <game|gps>\n' "$0" >&2
}

fail() {
  printf 'PLAYTEST=FAIL %s\n' "$*" >&2
  exit 66
}

case "$TARGET" in
  game|gps) ;;
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

pbf_newer_than_any() {
  [[ -n "$PBF" ]] || return 1
  local output
  for output in "$@"; do
    [[ ! -f "$output" || "$PBF" -nt "$output" ]] && return 0
  done
  return 1
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

ensure_gps_data() {
  mkdir -p "$WORLD_DATA"
  local graph="$WORLD_DATA/routing.brg"
  local snap="$WORLD_DATA/routing_snap.brs"
  local build_inputs=("$ROOT/tools/build_routing.py" "$ROOT/tools/routing_graph.py" "$ROOT/tools/build_snap_index.py" "$ROOT/tools/world_common.py")
  local fingerprint
  fingerprint="$(fingerprint_files "${build_inputs[@]}")"
  local stamp="$WORLD_DATA/.playtest_gps_data_fingerprint"
  local rebuild_graph=0

  [[ -f "$graph" ]] || rebuild_graph=1
  pbf_newer_than_any "$graph" && rebuild_graph=1
  if [[ "$rebuild_graph" -eq 0 ]] && stamp_mismatch "$stamp" "$fingerprint"; then
    rebuild_graph=1
  fi

  if [[ "$rebuild_graph" -eq 1 ]]; then
    require_pbf
    local python
    python="$(ensure_python_dependencies)"
    printf 'PLAYTEST=PREPARE routing rebuild\n'
    "$python" "$ROOT/tools/build_routing.py" "$PBF" --output "$WORLD_DATA"
  else
    printf 'PLAYTEST=READY routing\n'
  fi

  if [[ ! -f "$snap" || "$graph" -nt "$snap" || "$rebuild_graph" -eq 1 ]]; then
    local python
    python="$(ensure_python_dependencies)"
    printf 'PLAYTEST=PREPARE routing-snap rebuild\n'
    "$python" "$ROOT/tools/build_snap_index.py" "$graph" --output "$snap"
  else
    printf 'PLAYTEST=READY routing-snap\n'
  fi

  [[ -f "$graph" ]] || fail "missing $graph after preparation"
  [[ -f "$snap" ]] || fail "missing $snap after preparation"
  printf '%s\n' "$fingerprint" > "$stamp"
}

ensure_game_data() {
  mkdir -p "$WORLD_DATA"
  local required=(
    "$WORLD_DATA/manifest.json"
    "$WORLD_DATA/routing.brg"
    "$WORLD_DATA/routing_snap.brs"
    "$WORLD_DATA/search_index.bsi"
  )
  local build_inputs=(
    "$ROOT/tools/build_sweden.py"
    "$ROOT/tools/build_roads.py"
    "$ROOT/tools/build_routing.py"
    "$ROOT/tools/build_background.py"
    "$ROOT/tools/build_features.py"
    "$ROOT/tools/build_search_index.py"
    "$ROOT/tools/build_search_binary.py"
    "$ROOT/tools/world_common.py"
  )
  local fingerprint
  fingerprint="$(fingerprint_files "${build_inputs[@]}")"
  local stamp="$WORLD_DATA/.playtest_world_fingerprint"
  local rebuild=0
  local artifact
  for artifact in "${required[@]}"; do
    [[ -f "$artifact" ]] || rebuild=1
  done
  pbf_newer_than_any "${required[@]}" && rebuild=1
  if [[ "$rebuild" -eq 0 ]] && stamp_mismatch "$stamp" "$fingerprint"; then
    rebuild=1
  fi

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
  printf '%s\n' "$fingerprint" > "$stamp"
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
esac

[[ -f "$SCENE" ]] || fail "playtest scene missing: $SCENE"
printf 'PLAYTEST=RUN target=%s scene=%s\n' "$TARGET" "${SCENE#$ROOT/}"
exec "$GODOT" --path "$ROOT" "$SCENE"
