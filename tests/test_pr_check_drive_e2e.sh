#!/usr/bin/env bash
# Exercises the real PR-owned Safe Check flow with fixture world data and a fake Godot runtime.
# Dependencies: tools/run_pr_owned_check.sh, tools/pr_check_local.sh, tools/pr_check_scope.py, bash, Python, git.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/brur-drive-pr-check-e2e.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

WORKTREE="$TMP/worktree"
WORLD_DATA="$TMP/world_data"
mkdir -p "$WORKTREE/tools" "$WORLD_DATA/building_mesh_lod"
cp "$ROOT/tools/pr_check_local.sh" "$WORKTREE/tools/pr_check_local.sh"
cp "$ROOT/tools/pr_check_scope.py" "$WORKTREE/tools/pr_check_scope.py"
chmod +x "$WORKTREE/tools/pr_check_local.sh" "$WORKTREE/tools/pr_check_scope.py"
printf '{}\n' > "$WORLD_DATA/manifest.json"
printf '{}\n' > "$WORLD_DATA/background.brmap"
printf '{"id":1}\n' > "$WORLD_DATA/buildings.jsonl"

git -C "$WORKTREE" init -q
git -C "$WORKTREE" config user.name test
git -C "$WORKTREE" config user.email test@example.invalid
printf 'fixture\n' > "$WORKTREE/fixture.txt"
git -C "$WORKTREE" add .
git -C "$WORKTREE" commit -qm fixture

cat > "$WORKTREE/tools/build_building_mesh_pyramid.py" <<'PY'
#!/usr/bin/env python3
import sys
# The e2e test exercises orchestration, not the building compiler. Existing fixture data is always current.
raise SystemExit(0)
PY
chmod +x "$WORKTREE/tools/build_building_mesh_pyramid.py"

git -C "$WORKTREE" add tools/build_building_mesh_pyramid.py
git -C "$WORKTREE" commit -qm fixture-builder

ORDER_LOG="$TMP/order.log"
export ORDER_LOG

FAKE_PYTHON="$TMP/python"
cat > "$FAKE_PYTHON" <<'PY'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == */pr_check_status.py ]]; then
  shift
  printf 'STATUS %s\n' "$*" >> "$ORDER_LOG"
  exit 0
fi
exec /usr/bin/python3 "$@"
PY
chmod +x "$FAKE_PYTHON"

FAKE_GODOT="$TMP/godot"
cat > "$FAKE_GODOT" <<'GODOT'
#!/usr/bin/env bash
set -euo pipefail
script=""
headless=0
for ((i=1; i<=$#; i++)); do
  arg="${!i}"
  [[ "$arg" == "--headless" ]] && headless=1
  if [[ "$arg" == "--script" ]]; then
    j=$((i + 1)); script="${!j}"
  fi
done
if [[ "$headless" -eq 1 ]]; then
  printf 'GODOT_HEADLESS %s\n' "$script" >> "$ORDER_LOG"
  if [[ "$script" == "res://tests/godot/test_production_fps_real_data.gd" ]]; then
    printf 'PRODUCTION_DRIVE_FPS_REAL_DATA Drive enabled player=(1, 2, 3)\n'
    if [[ "${FAKE_DRIVE_MARKER:-0}" == "1" ]]; then
      printf 'PRODUCTION_DRIVE_FPS_REAL_DATA fps=100.00 avg_ms=10.000 p95_ms=12.000 worst_ms=20.000 frames=360 cell_crossings=4 road_pending=0 buildings_ready=true active_chunks=16\n'
      printf 'production Drive FPS real-data test: OK\n'
    fi
  else
    printf 'fixture headless test: OK\n'
  fi
  exit 0
fi
printf 'GODOT_VISUAL %s\n' "$*" >> "$ORDER_LOG"
exit 0
GODOT
chmod +x "$FAKE_GODOT"

run_flow() {
  BRUR_PR_CHECK_CHANGED_FILES='scripts/camera_controller.gd' \
  FAKE_DRIVE_MARKER="${FAKE_DRIVE_MARKER:-0}" \
  bash "$ROOT/tools/run_pr_owned_check.sh" "$WORKTREE" 235 "$WORLD_DATA" "$FAKE_PYTHON" "$FAKE_GODOT"
}

# Regression case: a clean Godot exit without the final measurement marker must fail closed.
: > "$ORDER_LOG"
set +e
output="$(FAKE_DRIVE_MARKER=0 run_flow 2>&1)"
status=$?
set -e
[[ "$status" -ne 0 ]] || { printf 'expected missing Drive completion marker to fail the Safe Check\n' >&2; exit 1; }
grep -q 'PR_CHECK=FAIL Godot test exited without required completion marker' <<<"$output" || {
  printf 'missing-marker failure was not reported\n%s\n' "$output" >&2; exit 1;
}
if grep -q '^STATUS .*--state success' "$ORDER_LOG"; then
  printf 'Safe Check recorded success before the Drive measurement completed\n' >&2; cat "$ORDER_LOG" >&2; exit 1
fi
if grep -q '^GODOT_VISUAL ' "$ORDER_LOG"; then
  printf 'Safe Check launched visual Godot after an incomplete objective Drive test\n' >&2; cat "$ORDER_LOG" >&2; exit 1
fi

# Positive case: the exact same flow may record success only after the explicit 360-frame marker appears.
: > "$ORDER_LOG"
output="$(FAKE_DRIVE_MARKER=1 run_flow 2>&1)"
grep -q 'production Drive FPS real-data test: OK' <<<"$output"
grep -q 'PR_CHECK=STATUS success pr=235' <<<"$output"
status_count="$(grep -c '^STATUS .*--state success .*--stage objective-checks-complete' "$ORDER_LOG")"
[[ "$status_count" -eq 1 ]] || { printf 'expected exactly one objective success, got %s\n' "$status_count" >&2; cat "$ORDER_LOG" >&2; exit 1; }
headless_count="$(grep -c '^GODOT_HEADLESS ' "$ORDER_LOG")"
[[ "$headless_count" -eq 4 ]] || { printf 'expected four building/Drive headless steps, got %s\n' "$headless_count" >&2; cat "$ORDER_LOG" >&2; exit 1; }
grep -q '^GODOT_HEADLESS res://tests/godot/test_production_fps_real_data.gd$' "$ORDER_LOG"
grep -q '^GODOT_VISUAL ' "$ORDER_LOG"

bash -n "$ROOT/tools/pr_check_local.sh"
bash -n "$ROOT/tools/run_pr_owned_check.sh"
printf 'Drive PR Safe Check end-to-end regression: OK\n'
