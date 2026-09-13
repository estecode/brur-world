#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
GODOT="${GODOT_BIN:-godot}"

"$GODOT" --headless --path "$ROOT" --script res://tests/godot/test_police_dispatch.gd
