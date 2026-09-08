#!/usr/bin/env bash
set -euo pipefail

# Benchmarks the real offline Sweden GPS search index in headless Godot.
# Dependencies: Godot 4 and world_data/search_index.jsonl.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"

cd "$ROOT"

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "Godot not found at: $GODOT_BIN" >&2
  exit 2
fi

if [[ ! -f world_data/search_index.jsonl ]]; then
  echo "Missing world_data/search_index.jsonl" >&2
  echo "Build it first with:" >&2
  echo "  python tools/build_search_index.py /Users/stefanlind/Dropbox/Code/syndicate/data/sweden-260824.osm.pbf --output world_data" >&2
  exit 2
fi

"$GODOT_BIN" --headless --path "$ROOT" --script tests/godot/benchmark_gps_search.gd
