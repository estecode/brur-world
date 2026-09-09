#!/usr/bin/env bash
# Validates city-light production composition against the authoritative local Sweden runtime data.
# Dependencies: tools/build_city_light_density.py, tools/test_city_lights_real_data.sh, and BRUR PR-check environment paths.
set -euo pipefail

WORKTREE="${BRUR_PR_CHECK_WORKTREE:?}"
WORLD_DATA="${BRUR_PR_CHECK_WORLD_DATA:?}"
PYTHON="${PYTHON_BIN:?}"
GODOT="${GODOT_BIN:?}"

[[ -d "$WORLD_DATA/poi_tiles" ]] || { printf 'PR_CHECK=FAIL missing runtime POI tiles for city-light density\n' >&2; exit 66; }

printf 'PR_CHECK=BUILD_CITY_LIGHT_DENSITY pr=%s\n' "${BRUR_PR_CHECK_PR:?}"
"$PYTHON" "$WORKTREE/tools/build_city_light_density.py" "$WORLD_DATA"
printf 'PR_CHECK=CHECK_CITY_LIGHTS_REAL_DATA pr=%s\n' "$BRUR_PR_CHECK_PR"
GODOT_BIN="$GODOT" bash "$WORKTREE/tools/test_city_lights_real_data.sh"
