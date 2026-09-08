# AI Development Instructions

You are an expert Godot 4 and systems software developer working on `brur-world`. This repository follows reusable process defaults from `estecode/ai-project-standard`, but this local file is self-contained and is the operative workflow contract. `ARCHITECTURE.md` is canonical for architecture.

## Mandatory first step

Before any code change, architecture work, refactor, or code review:

1. Read this `AGENTS.md`.
2. Read root `ARCHITECTURE.md`.
3. Read the current issue/task and acceptance criteria.

If a requested change conflicts with `ARCHITECTURE.md`, identify the conflict and use the smallest compliant alternative.

## Issue workflow

For tracked implementation such as `fixa #48`:

1. Read the required local files and issue before changing code.
2. Base work safely on the latest known `main` without overwriting local work.
3. Use `issue/<number>-<short-name>` and isolate concurrent issue work.
4. Implement the smallest architecture-compliant change inside issue scope.
5. Run all relevant available objective validation for the touched scope, including deterministic/core, native/headless Godot, and real-data integration checks where applicable. Do not delegate machine-verifiable checks to manual playtesting when they can reasonably be executed by the agent. Never claim validation not performed.
6. Commit the completed work, update the issue with implementation/validation evidence, and create a PR targeting `main` with `Closes #XX`.
7. Treat the PR as the persistent merge-decision object. PR body and final chat must agree.
8. Keep the issue open until merge. Do not merge unless explicitly requested or repository policy grants authority.
9. After PR creation, change implementation only for metadata/linkage repair, failed-validation repair, or explicit review feedback.

Required decision block:

```markdown
## Merge decision

**What changed**
<plain-language summary>

**Why this approach**
<why this was the smallest/correct solution>

**Behavioral impact**
<what can change or regress>

**Executed validation**
<exact checks actually run + results>

**Risk assessment**
<remaining risks, untested areas, known gaps>

**Merge recommendation**
<one decision form below>
```

Use exactly one:

```text
MERGE
```

```text
CHECK THEN MERGE

CHECK: <environment/type> — <concrete verification>
RUN: <portable Safe Command Link when the project PR-check launcher applies>
MERGE: if check passes
```

```text
DO NOT MERGE

FIX: <concrete blocker>
RECHECK: <concrete verification after fix>
```

`MERGE` means all relevant available objective validation passed and no meaningful manual check remains. `CHECK THEN MERGE` means objective validation passed but one meaningful perceptual, interactive, hardware-specific, production-data/environment-specific, or otherwise non-automatable human check remains. `DO NOT MERGE` means a blocker, failed relevant check, or material unresolved risk remains.

Do not use `CHECK THEN MERGE` merely because this is Godot. Do not delegate a check the agent can execute. Manual verification should primarily evaluate perception/feel or behavior that cannot reasonably be automated. Repeated objective manual checks are candidates for automation. Name the concrete scene/harness/runtime verification.

Final delivery reporting must include issue, branch, delivery commit, actual validation/results, PR, issue-update status, outstanding notes, and the same merge decision as the PR.

## Safe Command Links

This project supports `estecode/safe-command-links` for human-executable PR checks and current-checkout playtests.

```text
Safe Command Links: supported
Repository: estecode/brur-world
PR check command: pr-check
Parameters: pr:positive-int
Playtest command: playtest
Parameters: target:enum=game,gps
```

`playtest` targets are limited to real supported targets. Add new values only when the corresponding game/harness actually exists; do not create speculative harnesses to populate the allowlist.

When a PR is `CHECK THEN MERGE` and its remaining check can be launched by the project-owned PR-check command, the PR must include a normal clickable localhost HTTP link:

```text
RUN: [▶ Run safe check](http://127.0.0.1:17384/safecommand/project?repo=estecode/brur-world&command=pr-check&pr=<PR number>)
```

GitHub does not reliably make the custom `safecommand://` scheme clickable, so PRs must use the localhost HTTP form above. Safe Command Links listens only on loopback and forwards the request through the same local repository mapping, signed command approval and parameter validation.

Never put a developer's absolute checkout path in a PR. Safe Command Links maps `estecode/brur-world` to the local checkout on each Mac, then verifies the locally signed command approval and validated parameters.

`brur-world` owns what `pr-check` and `playtest` actually do. `pr-check` selects the exact PR revision, prepares isolated runtime state, launches the relevant Godot check, reuses required local runtime data safely, and cleans temporary state after Godot exits. `playtest` prepares the required dependencies for an allowlisted target and launches the current mapped checkout. Safe Command Links must remain generic and must not contain Godot/world-data/project-specific behavior.

If the local Safe Command installation/mapping/approval is missing, the link may fail locally; agents must not infer installation state from GitHub. Repository support is declared here, while local availability is machine state.

## Dependency graph execution

Treat the roadmap as a dependency graph, not a mandatory queue. Read issue dependencies for non-trivial tracked work. `Independent` means no implementation blocker, not priority. `Blocked` means do not complete until dependencies are satisfied. `Integration-sensitive` means work may proceed with explicit awareness of shared contracts/files. Claim parallel safety only after assessment.

## User-facing CLI commands

- Make commands copy-paste ready and independent of the current repository subdirectory where practical.
- Use explicit repository-relative paths.
- On macOS/POSIX prefer `ROOT="$(git rev-parse --show-toplevel)" && ...` when root is needed.
- Do not add `git pull`, `reset`, `clean`, branch deletion, merge, or similar state-changing operations merely for convenience.
- Do not assume a clean working tree.
- Prefer one complete command.
- For Godot, resolve the root and use `godot --path "$ROOT" <scene>` rather than relying on cwd.

## Architecture reminders

The full architecture contract is in `ARCHITECTURE.md`; it remains canonical. In particular:

- Preserve `core/domain -> adapter -> presentation`.
- Portable/domain logic must not depend on Godot rendering/UI, SceneTree, TCP/JSON/process behavior, mmap/POSIX, or harness code.
- Use explicit composition; avoid fragile cross-subsystem NodePath traversal. Call downward, signal upward.
- Keep game/harness composition roots thin and domain logic in owned modules.
- Harnesses use the same production implementation and real runtime data where practical; do not create duplicate harness implementations.
- World data has one authoritative offline pipeline; do not create competing road/routing truth.
- Coordinate conversion has one shared owner.
- Avoid a global EventBus for ordinary/high-frequency subsystem communication.
- Keep performance-sensitive logic portable to C++ behind small explicit contracts.
- Touched source files preserve/add the short English responsibility/dependency header required by `ARCHITECTURE.md`.
- Do not introduce speculative frameworks, universal service abstractions, giant bootstrap owners, or unrelated cleanup.

When reviewing code, actively flag violations of these rules.
