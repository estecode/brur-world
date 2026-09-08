#!/usr/bin/env bash
set -euo pipefail

# Builds the dependency-free C++20 GPS runtime benchmark used by issue #4.
# Dependencies: Apple clang++ or another C++20 compiler available as CXX.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CXX_BIN="${CXX:-clang++}"
OUT="$ROOT/bin/brur-gps-native"
mkdir -p "$ROOT/bin"

"$CXX_BIN" \
  -std=c++20 \
  -O3 \
  -DNDEBUG \
  -Wall \
  -Wextra \
  -pedantic \
  "$ROOT/native/gps_runtime.cpp" \
  -o "$OUT"

echo "[native-gps] built: $OUT"
