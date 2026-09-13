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
  local review_mode="${1:-required}"
  BRUR_PR_CHECK_CHANGED_FILES='scripts/camera_controller.gd' \
  BRUR_PR_CHECK_MANUAL_REVIEW="$review_mode" \
  FAKE_DRIVE_MARKER="${FAKE_DRIVE_MARKER:-0}" \
  bash "$ROOT/tools/run_pr_owned_check.sh" "$WORKTREE" 235 "$WORLD_DATA" "$FAKE_PYTHON" "$FAKE_GODOT"
}

fail_scenario() {
  local scenario="$1" message="$2"
  printf 'Drive Safe Check E2E failed scenario=%s: %s\n' "$scenario" "$message" >&2
  printf '%s\n' '--- flow output ---' >&2
  printf '%s\n' "${output:-<empty>}" >&2
  printf '%s\n' '--- order log ---' >&2
  cat "$ORDER_LOG" >&2 || true
  exit 1
}

# Regression case: a clean Godot exit without the final measurement marker must fail closed.
: > "$ORDER_LOG"
set +e
output="$(FAKE_DRIVE_MARKER=0 run_flow required 2>&1)"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail_scenario missing-marker "flow unexpectedly succeeded"
grep -q 'PR_CHECK=FAIL Godot test exited without required completion marker' <<<"$output" || fail_scenario missing-marker "required completion-marker failure was not reported"
if grep -q '^STATUS .*--state success' "$ORDER_LOG"; then fail_scenario missing-marker "success was recorded before measurement completed"; fi
if grep -q '^GODOT_VISUAL ' "$ORDER_LOG"; then fail_scenario missing-marker "visual Godot launched after incomplete objective test"; fi

# CHECK THEN MERGE may launch the explicit human review only after all objective gates pass.
# The runner must persist objective success before that blocking visual session starts.
: > "$ORDER_LOG"
set +e
output="$(FAKE_DRIVE_MARKER=1 run_flow required 2>&1)"
status=$?
set -e
[[ "$status" -eq 0 ]] || fail_scenario check-then-merge "flow exited $status"
grep -q 'production Drive FPS real-data test: OK' <<<"$output" || fail_scenario check-then-merge "Drive completion marker missing"
grep -q 'PR_CHECK=STATUS success pr=235' <<<"$output" || fail_scenario check-then-merge "objective success output missing"
status_count="$(grep -c '^STATUS .*--state success .*--stage objective-checks-complete' "$ORDER_LOG" || true)"
[[ "$status_count" -eq 1 ]] || fail_scenario check-then-merge "expected one objective success, got $status_count"
headless_count="$(grep -c '^GODOT_HEADLESS ' "$ORDER_LOG" || true)"
[[ "$headless_count" -eq 4 ]] || fail_scenario check-then-merge "expected four building/Drive headless steps, got $headless_count"
grep -q '^GODOT_HEADLESS res://tests/godot/test_production_fps_real_data.gd$' "$ORDER_LOG" || fail_scenario check-then-merge "production Drive headless step missing"
grep -q '^GODOT_VISUAL ' "$ORDER_LOG" || fail_scenario check-then-merge "required visual review did not launch"

# MERGE means no subjective review remains: the PR-owned hook runs all real-data gates
# headlessly and returns. Final success is owned by outer tools/pr_check.sh after this
# runner exits, so the inner runner must not write an early success status here.
: > "$ORDER_LOG"
set +e
output="$(FAKE_DRIVE_MARKER=1 run_flow none 2>&1)"
status=$?
set -e
[[ "$status" -eq 0 ]] || fail_scenario merge "flow exited $status"
grep -q 'production Drive FPS real-data test: OK' <<<"$output" || fail_scenario merge "Drive completion marker missing"
grep -q 'PR_CHECK=SKIP_VISUAL_REVIEW pr=235 reason=no-subjective-check-remains' <<<"$output" || fail_scenario merge "headless-only completion marker missing"
if grep -q 'PR_CHECK=STATUS success pr=235' <<<"$output"; then fail_scenario merge "inner runner wrote final success before outer Safe Check"; fi
status_count="$(grep -c '^STATUS .*--state success' "$ORDER_LOG" || true)"
[[ "$status_count" -eq 0 ]] || fail_scenario merge "inner runner unexpectedly persisted $status_count success status(es)"
headless_count="$(grep -c '^GODOT_HEADLESS ' "$ORDER_LOG" || true)"
[[ "$headless_count" -eq 4 ]] || fail_scenario merge "expected four automatic MERGE headless steps, got $headless_count"
if grep -q '^GODOT_VISUAL ' "$ORDER_LOG"; then fail_scenario merge "redundant visual Godot session opened"; fi

# Preserve the outer ownership contract: full Safe Check records success only after
# the PR-owned runner returns green.
hook_line="$(grep -n 'run_pr_owned_check.sh' "$ROOT/tools/pr_check.sh" | tail -n 1 | cut -d: -f1)"
success_line="$(grep -n -- '--state success' "$ROOT/tools/pr_check.sh" | head -n 1 | cut -d: -f1)"
[[ -n "$hook_line" && -n "$success_line" && "$hook_line" -lt "$success_line" ]] || fail_scenario merge "outer Safe Check no longer owns post-hook final success"

bash -n "$ROOT/tools/pr_check_local.sh"
bash -n "$ROOT/tools/run_pr_owned_check.sh"
printf 'Drive PR Safe Check end-to-end regression: OK\n'