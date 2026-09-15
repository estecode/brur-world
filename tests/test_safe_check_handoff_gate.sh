#!/usr/bin/env bash
# Regression for #343: a failed objective chain must never reach human handoff,
# while a fully green chain may emit HANDOFF_READY and launch the requested review.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
RUNNER="$ROOT/tools/run_pr_owned_check.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/brur-handoff-gate.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
WT="$TMP/worktree"
WORLD="$TMP/world_data"
mkdir -p "$WT/tools" "$WT/scenes" "$WORLD"
git -C "$WT" init -q
git -C "$WT" config user.email test@example.invalid
git -C "$WT" config user.name test
printf '[gd_scene]\n' > "$WT/scenes/main.tscn"
printf 'fixture\n' > "$WT/fixture.txt"
git -C "$WT" add .
git -C "$WT" commit -qm fixture

FAKE_PY="$TMP/python"
cat > "$FAKE_PY" <<'SH'
#!/usr/bin/env bash
# pr_check_status.py record is intentionally a no-op in this isolated gate test.
exit 0
SH
chmod +x "$FAKE_PY"
FAKE_GODOT="$TMP/godot"
GODOT_LOG="$TMP/godot.log"
export GODOT_LOG
cat > "$FAKE_GODOT" <<'SH'
#!/usr/bin/env bash
printf 'GODOT %s\n' "$*" >> "$GODOT_LOG"
exit 0
SH
chmod +x "$FAKE_GODOT"

write_hook() {
  local outcome="$1"
  cat > "$WT/tools/pr_check_local.sh" <<SH
#!/usr/bin/env bash
set -euo pipefail
printf 'OBJECTIVE_STAGE=before-visual\n'
"\$GODOT_BIN" --path "\$BRUR_PR_CHECK_WORKTREE" "\$BRUR_PR_CHECK_WORKTREE/scenes/main.tscn"
printf 'OBJECTIVE_STAGE=after-visual-request\n'
if [[ "$outcome" == fail ]]; then
  printf 'OBJECTIVE_STAGE=downstream-failure\n' >&2
  exit 23
fi
printf 'OBJECTIVE_STAGE=all-green\n'
SH
  chmod +x "$WT/tools/pr_check_local.sh"
}

write_hook fail
set +e
failed_output="$(BRUR_PR_CHECK_LOG_PATH="$TMP/fail.log" BRUR_PR_CHECK_MANUAL_REVIEW=required BRUR_PR_CHECK_MANUAL_CHECK='inspect Lund streaming' bash "$RUNNER" "$WT" 343 "$WORLD" "$FAKE_PY" "$FAKE_GODOT" 2>&1)"
failed_status=$?
set -e
[[ "$failed_status" -eq 23 ]]
printf '%s\n' "$failed_output" | grep -q 'PR_CHECK=VISUAL_REVIEW_DEFERRED'
printf '%s\n' "$failed_output" | grep -q 'PR_CHECK=HANDOFF_BLOCKED'
if printf '%s\n' "$failed_output" | grep -q 'PR_CHECK=HANDOFF_READY'; then
  printf 'failed objective chain incorrectly became handoff-ready\n' >&2; exit 1
fi
if [[ -s "$GODOT_LOG" ]]; then
  printf 'human Godot launch occurred before failed objective chain completed\n' >&2; exit 1
fi

write_hook pass
: > "$GODOT_LOG"
passed_output="$(BRUR_PR_CHECK_LOG_PATH="$TMP/pass.log" BRUR_PR_CHECK_MANUAL_REVIEW=required BRUR_PR_CHECK_MANUAL_CHECK='inspect Lund streaming' bash "$RUNNER" "$WT" 343 "$WORLD" "$FAKE_PY" "$FAKE_GODOT" 2>&1)"
printf '%s\n' "$passed_output" | grep -q 'OBJECTIVE_STAGE=all-green'
printf '%s\n' "$passed_output" | grep -q 'PR_CHECK=HANDOFF_READY pr=343'
printf '%s\n' "$passed_output" | grep -q 'SAFE CHECK — MANUAL CHECK REQUIRED'
grep -q 'GODOT .*scenes/main.tscn' "$GODOT_LOG"

# Ordering is part of the contract: the machine proof precedes the human prompt.
ready_line="$(printf '%s\n' "$passed_output" | grep -n 'PR_CHECK=HANDOFF_READY' | cut -d: -f1)"
prompt_line="$(printf '%s\n' "$passed_output" | grep -n 'SAFE CHECK — MANUAL CHECK REQUIRED' | cut -d: -f1)"
[[ "$ready_line" -lt "$prompt_line" ]]
printf 'SAFE_CHECK_HANDOFF_GATE_TEST=PASS\n'
