#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
GODOT_BIN="${GODOT_BIN:-godot}"

"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/godot/test_cloud_field.gd
