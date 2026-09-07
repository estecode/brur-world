#!/usr/bin/env bash
set -euo pipefail

PBF="${1:-/Users/stefanlind/Dropbox/Code/syndicate/data/sweden-260824.osm.pbf}"
PYTHON="${PYTHON:-python3}"

if [ ! -d .venv ]; then
  "$PYTHON" -m venv .venv
fi

source .venv/bin/activate
python -m pip install -q -r requirements.txt
python tools/build_sweden.py "$PBF" --output world_data

echo
echo "========================================"
echo "           BUILD COMPLETE"
echo "========================================"
echo "World built. Open this folder in Godot 4 and press Run."
