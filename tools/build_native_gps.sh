#!/usr/bin/env bash
set -euo pipefail

# Builds the portable C++20 GPS core adapters plus CH/snap acceleration adapters.
# Dependencies: Apple clang++ or another C++20 compiler available as CXX.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CXX_BIN="${CXX:-clang++}"
CORE_SOURCE="$ROOT/native/gps_core.cpp"
BENCH_OUT="$ROOT/bin/brur-gps-native"
ROUTE_OUT="$ROOT/bin/brur-gps-route"
SERVER_OUT="$ROOT/bin/brur-gps-server"
SEARCH_SERVER_OUT="$ROOT/bin/brur-gps-search-server"
CH_OUT="$ROOT/bin/brur-gps-ch"
SNAP_OUT="$ROOT/bin/brur-gps-snap"
mkdir -p "$ROOT/bin"

COMMON_FLAGS=(
  -std=c++20
  -O3
  -DNDEBUG
  -Wall
  -Wextra
  -pedantic
)

"$CXX_BIN" \
  "${COMMON_FLAGS[@]}" \
  "$CORE_SOURCE" \
  "$ROOT/native/gps_runtime.cpp" \
  -o "$BENCH_OUT"

"$CXX_BIN" \
  "${COMMON_FLAGS[@]}" \
  "$CORE_SOURCE" \
  "$ROOT/native/gps_route_cli.cpp" \
  -o "$ROUTE_OUT"

"$CXX_BIN" \
  "${COMMON_FLAGS[@]}" \
  "$CORE_SOURCE" \
  "$ROOT/native/gps_route_server.cpp" \
  -o "$SERVER_OUT"

"$CXX_BIN" \
  "${COMMON_FLAGS[@]}" \
  "$ROOT/native/gps_search_server.cpp" \
  -o "$SEARCH_SERVER_OUT"

"$CXX_BIN" \
  "${COMMON_FLAGS[@]}" \
  "$ROOT/native/gps_ch_runtime.cpp" \
  "$ROOT/native/gps_ch_cli.cpp" \
  -o "$CH_OUT"

"$CXX_BIN" \
  "${COMMON_FLAGS[@]}" \
  "$ROOT/native/gps_snap_runtime.cpp" \
  "$ROOT/native/gps_snap_cli.cpp" \
  -o "$SNAP_OUT"

echo "[native-gps] built: $BENCH_OUT"
echo "[native-gps] built: $ROUTE_OUT"
echo "[native-gps] built: $SERVER_OUT"
echo "[native-gps] built: $SEARCH_SERVER_OUT"
echo "[native-gps] built: $CH_OUT"
echo "[native-gps] built: $SNAP_OUT"
