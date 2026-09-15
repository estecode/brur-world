# Safe Check bootstrap

Safe Check must not depend on the branch currently checked out in the project leader's mapped `brur-world` checkout.

The registered `pr-check` command is therefore a minimal signed shell bootstrap, not a repository-relative `tools/pr_check_entry.sh` path. It performs only these steps in the mapped checkout:

```text
fetch current origin/main
-> stream origin/main:tools/pr_check_entry.sh to bash
-> current-main entrypoint creates its isolated main launcher worktree
-> current-main launcher resolves the exact requested PR head
-> PR-owned checks execute from that exact PR worktree
```

The mapped checkout supplies local machine state (`world_data`, `.venv`, repository credentials/remotes and sibling source data) but its checked-out branch does not supply Safe Check orchestration code.

## One-time registration

From the mapped `brur-world` checkout, run:

```bash
bash <(git show origin/main:tools/register_safe_check.sh)
```

If `safe-command-links` is not a sibling directory of `brur-world`, pass its absolute path:

```bash
bash <(git show origin/main:tools/register_safe_check.sh) /absolute/path/to/safe-command-links
```

The registration stored by Safe Command Links then remains valid while switching among `main`, old issue branches, current POC branches and future issue branches. Safe Check fetches current `origin/main` before executing project-owned Safe Check code, so those branches do not need to contain the latest launcher.

`tests/test_safe_check_registration.sh` deliberately uses a stale mapped checkout that does not contain `tools/pr_check_entry.sh`, advances remote `main`, and proves that the current-main entrypoint executes without modifying the stale checkout.
