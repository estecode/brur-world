#!/usr/bin/env bash
# Verifies exact-PR hooks fail closed and machine success is persisted before optional human Godot review.
# Dependencies: bash, git, mktemp, grep, tools/run_pr_owned_check.sh, tools/pr_check.sh, and tests/test_pr_check_entry.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/brur-pr-owned-check-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

WORKTREE="$TMP/worktree"
WORLD_DATA="$TMP/world_data"
mkdir -p "$WORKTREE/tools" "$WORLD_DATA"
git -C "$WORKTREE" init -q
git -C "$WORKTREE" config user.name test
git -C "$WORKTREE" config user.email test@example.invalid
printf 'fixture\n' > "$WORKTREE/fixture.txt"
git -C "$WORKTREE" add fixture.txt
git -C "$WORKTREE" commit -qm fixture
WORKTREE_HEAD="$(git -C "$WORKTREE" rev-parse HEAD)"

output="$(BRUR_PR_CHECK_MANUAL_REVIEW=none bash "$ROOT/tools/run_pr_owned_check.sh" "$WORKTREE" 123 "$WORLD_DATA" /usr/bin/python3 /usr/bin/true)"
grep -q 'PR_CHECK=SKIP_PR_OWNED_OBJECTIVE_CHECKS pr=123 reason=no-hook' <<<"$output"

cat > "$WORKTREE/tools/pr_check_local.sh" <<'HOOK'
set -euo pipefail
printf 'HOOK_PR=%s\n' "$BRUR_PR_CHECK_PR"
printf 'HOOK_WORKTREE=%s\n' "$BRUR_PR_CHECK_WORKTREE"
printf 'HOOK_WORLD_DATA=%s\n' "$BRUR_PR_CHECK_WORLD_DATA"
printf 'HOOK_PYTHON=%s\n' "$PYTHON_BIN"
printf 'HOOK_GODOT=%s\n' "$GODOT_BIN"
HOOK

output="$(BRUR_PR_CHECK_MANUAL_REVIEW=none bash "$ROOT/tools/run_pr_owned_check.sh" "$WORKTREE" 123 "$WORLD_DATA" /usr/bin/python3 /usr/bin/true)"
grep -q 'PR_CHECK=RUN_PR_OWNED_OBJECTIVE_CHECKS pr=123 hook=tools/pr_check_local.sh' <<<"$output"
grep -q 'HOOK_PR=123' <<<"$output"
grep -Fq "HOOK_WORKTREE=$WORKTREE" <<<"$output"
grep -Fq "HOOK_WORLD_DATA=$WORLD_DATA" <<<"$output"
grep -q 'HOOK_PYTHON=/usr/bin/python3' <<<"$output"

cat > "$WORKTREE/tools/pr_check_local.sh" <<'HOOK'
exit 23
HOOK
set +e
BRUR_PR_CHECK_MANUAL_REVIEW=none bash "$ROOT/tools/run_pr_owned_check.sh" "$WORKTREE" 123 "$WORLD_DATA" /usr/bin/python3 /usr/bin/true >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 23 ]] || { printf 'expected objective hook failure 23, got %s\n' "$status" >&2; exit 1; }

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
for arg in "$@"; do
  if [[ "$arg" == "--headless" ]]; then
    printf 'GODOT_HEADLESS %s\n' "$*" >> "$ORDER_LOG"
    exit 0
  fi
done
printf 'GODOT_VISUAL %s\n' "$*" >> "$ORDER_LOG"
exit 42
GODOT
chmod +x "$FAKE_GODOT"

# Reproduce an old PR hook that ignores the authoritative manual-review contract
# and claims no subjective review remains. The current-main runner must override
# that stale decision and launch production Main itself, never the editor.
mkdir -p "$WORKTREE/scenes"
touch "$WORKTREE/scenes/main.tscn"
cat > "$WORKTREE/tools/pr_check_local.sh" <<'HOOK'
set -euo pipefail
printf 'PR_CHECK=SKIP_VISUAL_REVIEW pr=%s reason=no-subjective-check-remains\n' "$BRUR_PR_CHECK_PR"
HOOK
: > "$ORDER_LOG"
output="$(BRUR_PR_CHECK_MANUAL_REVIEW=required bash "$ROOT/tools/run_pr_owned_check.sh" "$WORKTREE" 123 "$WORLD_DATA" "$FAKE_PYTHON" "$FAKE_GODOT" 2>&1)"
grep -q 'PR_CHECK=SKIP_VISUAL_REVIEW pr=123 reason=no-subjective-check-remains' <<<"$output"
grep -q 'PR_CHECK=FORCE_VISUAL_REVIEW pr=123 reason=authoritative-manual-review-not-launched-by-pr-hook' <<<"$output"
grep -q 'PR_CHECK=VISUAL_REVIEW_TARGET scene=scenes/main.tscn reason=manual-review-contract-fallback' <<<"$output"
grep -q 'PR_CHECK=VISUAL_REVIEW_EXPECT window=production-main not=editor' <<<"$output"
visual_count="$(grep -c '^GODOT_VISUAL ' "$ORDER_LOG")"
[[ "$visual_count" -eq 1 ]] || { printf 'expected exactly one forced production visual launch, got %s\n' "$visual_count" >&2; cat "$ORDER_LOG" >&2; exit 1; }
grep -Fq "$WORKTREE/scenes/main.tscn" "$ORDER_LOG"
if grep -q -- '--editor' "$ORDER_LOG"; then
  printf 'forced review must never open the Godot editor\n' >&2
  cat "$ORDER_LOG" >&2
  exit 1
fi
status_line="$(grep -n '^STATUS ' "$ORDER_LOG" | head -n 1 | cut -d: -f1)"
visual_line="$(grep -n '^GODOT_VISUAL ' "$ORDER_LOG" | head -n 1 | cut -d: -f1)"
[[ "$status_line" -lt "$visual_line" ]] || { printf 'forced review must persist machine success before visual Godot starts\n' >&2; cat "$ORDER_LOG" >&2; exit 1; }

# A required review must also survive an exact PR revision with no PR-owned hook.
rm "$WORKTREE/tools/pr_check_local.sh"
: > "$ORDER_LOG"
output="$(BRUR_PR_CHECK_MANUAL_REVIEW=required bash "$ROOT/tools/run_pr_owned_check.sh" "$WORKTREE" 123 "$WORLD_DATA" "$FAKE_PYTHON" "$FAKE_GODOT" 2>&1)"
grep -q 'PR_CHECK=SKIP_PR_OWNED_OBJECTIVE_CHECKS pr=123 reason=no-hook' <<<"$output"
grep -q 'PR_CHECK=FORCE_VISUAL_REVIEW pr=123 reason=authoritative-manual-review-not-launched-by-pr-hook' <<<"$output"
[[ "$(grep -c '^GODOT_VISUAL ' "$ORDER_LOG")" -eq 1 ]]

cat > "$WORKTREE/tools/pr_check_local.sh" <<'HOOK'
set -euo pipefail
"$GODOT_BIN" --headless --path "$BRUR_PR_CHECK_WORKTREE" --script res://tests/fake.gd
printf 'HOOK_OBJECTIVE_DONE\n' >> "$ORDER_LOG"
"$GODOT_BIN" --path "$BRUR_PR_CHECK_WORKTREE" res://harness/fake.tscn
printf 'HOOK_VISUAL_RETURNED\n' >> "$ORDER_LOG"
HOOK

: > "$ORDER_LOG"
output="$(BRUR_PR_CHECK_MANUAL_REVIEW=none bash "$ROOT/tools/run_pr_owned_check.sh" "$WORKTREE" 123 "$WORLD_DATA" "$FAKE_PYTHON" "$FAKE_GODOT" 2>&1)"
grep -q 'PR_CHECK=STATUS success pr=123' <<<"$output"
grep -q 'PR_CHECK=VISUAL_REVIEW_WARNING Godot exited status=42 after objective success' <<<"$output"
status_count="$(grep -c '^STATUS .*--state success .*--stage objective-checks-complete' "$ORDER_LOG")"
[[ "$status_count" -eq 1 ]] || { printf 'expected exactly one pre-visual success status, got %s\n' "$status_count" >&2; cat "$ORDER_LOG" >&2; exit 1; }
status_line="$(grep -n '^STATUS ' "$ORDER_LOG" | cut -d: -f1)"
visual_line="$(grep -n '^GODOT_VISUAL ' "$ORDER_LOG" | cut -d: -f1)"
[[ "$status_line" -lt "$visual_line" ]] || { printf 'machine success must be persisted before visual Godot starts\n' >&2; cat "$ORDER_LOG" >&2; exit 1; }
grep -q '^GODOT_HEADLESS ' "$ORDER_LOG"
grep -q '^HOOK_VISUAL_RETURNED$' "$ORDER_LOG"
grep -q -- "--sha $WORKTREE_HEAD" "$ORDER_LOG"

hook_line="$(grep -n 'run_pr_owned_check.sh' "$ROOT/tools/pr_check.sh" | tail -n 1 | cut -d: -f1)"
success_line="$(grep -n -- '--state success' "$ROOT/tools/pr_check.sh" | head -n 1 | cut -d: -f1)"
[[ -n "$hook_line" && -n "$success_line" && "$hook_line" -lt "$success_line" ]] || {
  printf 'outer launcher must retain fail-closed hook-before-final-success ordering\n' >&2
  exit 1
}

grep -q 'DRIVE_HUD_VISUAL_SCOPE="required"' "$ROOT/tools/pr_check_local.sh" || {
  printf 'Drive HUD presentation changes must request exact-revision production-scene review\n' >&2
  exit 1
}
grep -q 'VISUAL_REVIEW_TARGET scene=scenes/main.tscn reason=drive-hud' "$ROOT/tools/pr_check_local.sh" || {
  printf 'Drive HUD human review must identify the production Main scene explicitly\n' >&2
  exit 1
}
grep -q 'VISUAL_REVIEW_EXPECT window=production-main not=driving-harness' "$ROOT/tools/pr_check_local.sh" || {
  printf 'Drive HUD handoff must state the expected production review surface\n' >&2
  exit 1
}
hud_line="$(grep -n 'if \[\[ "$DRIVE_HUD_VISUAL_SCOPE" == "required" \]\]' "$ROOT/tools/pr_check_local.sh" | head -n 1 | cut -d: -f1)"
driving_line="$(grep -n 'if \[\[ "$DRIVING_VISUAL_SCOPE" == "required" \]\]' "$ROOT/tools/pr_check_local.sh" | head -n 1 | cut -d: -f1)"
[[ -n "$hud_line" && -n "$driving_line" && "$hud_line" -lt "$driving_line" ]] || {
  printf 'Drive HUD review must take priority over generic driving review when both scopes match\n' >&2
  exit 1
}

SELECTOR="$TMP/selector"
mkdir -p "$SELECTOR/tools" "$SELECTOR/scenes" "$SELECTOR/harness/driving"
cp "$ROOT/tools/pr_check_local.sh" "$SELECTOR/tools/pr_check_local.sh"
cat > "$SELECTOR/tools/pr_check_scope.py" <<'PY'
#!/usr/bin/env python3
print("skip")
PY
chmod +x "$SELECTOR/tools/pr_check_scope.py"
touch "$SELECTOR/scenes/main.tscn" "$SELECTOR/harness/driving/driving_harness.tscn"
git -C "$SELECTOR" init -q
git -C "$SELECTOR" config user.name test
git -C "$SELECTOR" config user.email test@example.invalid
git -C "$SELECTOR" add .
git -C "$SELECTOR" commit -qm selector
SELECTOR_GODOT="$TMP/selector-godot"
cat > "$SELECTOR_GODOT" <<'GODOT'
#!/usr/bin/env bash
set -euo pipefail
printf 'SELECTOR_GODOT %s\n' "$*" >> "$ORDER_LOG"
exit 0
GODOT
chmod +x "$SELECTOR_GODOT"
: > "$ORDER_LOG"
BRUR_PR_CHECK_WORKTREE="$SELECTOR" BRUR_PR_CHECK_WORLD_DATA="$WORLD_DATA" BRUR_PR_CHECK_PR=248 \
BRUR_PR_CHECK_CHANGED_FILES=$'scripts/drive_hud.gd\nscripts/vehicle_route_follower.gd' \
PYTHON_BIN=/usr/bin/python3 GODOT_BIN="$SELECTOR_GODOT" bash "$SELECTOR/tools/pr_check_local.sh" >/dev/null
selector_visual="$(grep '^SELECTOR_GODOT ' "$ORDER_LOG" | tail -n 1)"
grep -Fq "$SELECTOR/scenes/main.tscn" <<<"$selector_visual" || {
  printf 'HUD + route-follower PR must launch production Main for visual review\n' >&2
  cat "$ORDER_LOG" >&2
  exit 1
}
if grep -Fq "$SELECTOR/harness/driving/driving_harness.tscn" <<<"$selector_visual"; then
  printf 'HUD + route-follower PR incorrectly launched driving harness\n' >&2
  cat "$ORDER_LOG" >&2
  exit 1
fi

bash -n "$ROOT/tools/run_pr_owned_check.sh"
bash -n "$ROOT/tools/pr_check_local.sh"
bash "$ROOT/tests/test_pr_check_entry.sh"
printf 'pr-owned check hook tests passed\n'
