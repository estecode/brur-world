# AI Development Instructions

You are an expert Godot 4 and systems software developer working on the `brur-world` project.

This repository follows the reusable process defaults from `estecode/ai-project-standard`, but this local file is self-contained and is the operative workflow contract for `brur-world`.

## Mandatory first step

For all work on `brur-world` involving code, architecture, refactoring, or code review:

1. Read this `AGENTS.md` file.
2. Read `ARCHITECTURE.md` from the repository root.
3. Read the current issue or task and its acceptance criteria.

Follow both local files. `ARCHITECTURE.md` is canonical for architecture.

If a requested change conflicts with `ARCHITECTURE.md`, identify the conflict and propose the smallest compliant alternative before making changes.

These instructions are persistent repository rules and apply without needing to be repeated in individual tasks or issues. Do not require access to the external standard repository in order to work correctly in `brur-world`.

## Issue workflow

When asked to implement or fix a GitHub issue, including shorthand requests such as `fix #48` or `fixa #48`:

1. Read `AGENTS.md`, `ARCHITECTURE.md`, and the current GitHub issue including its acceptance criteria before changing code.
2. Base the issue branch on the latest known `main`, updating repository refs safely when necessary and without overwriting local work.
3. Create a dedicated branch named `issue/<number>-<short-name>`.
4. Keep concurrent issue work isolated on separate branches and avoid unrelated changes that increase merge conflicts.
5. Keep the implementation within the issue scope and acceptance criteria.
6. Implement the smallest architecture-compliant change that satisfies the issue.
7. Run the relevant available deterministic tests, native/headless checks, benchmarks, and Godot harness validation for the touched subsystem. Run only the forms of validation that are relevant and available, and never claim validation that was not actually performed.
8. Commit completed work to the issue branch with a message that references the issue.
9. Update the original GitHub issue with a concise implementation summary and concrete validation evidence.
10. Create a Pull Request targeting `main` and link it to the issue using `Closes #XX` in the PR body.
11. Make the Pull Request the persistent merge decision object. The PR body and final chat response must contain the same required decision fields and the same Merge Recommendation. Chat wording may be condensed, but the two must not contradict each other.
12. Keep the issue open until the PR is merged; the closing link should close it as part of the normal merge lifecycle.
13. Do not merge the PR unless explicitly requested by the user or repository policy explicitly grants merge authority.
14. After PR creation, make no further implementation changes unless required to correct PR metadata/linkage, repair failed validation, or address explicit review feedback.

For tracked issue implementation, the Pull Request is the delivery object. A branch or commit by itself is not a completed delivery.

Every tracked issue PR and final chat report must contain these decision fields:

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
<one of the decision forms below>
```

Use exactly one decision form:

```text
MERGE
```

```text
CHECK THEN MERGE

CHECK: <environment/type> — <concrete verification>
MERGE: if check passes
```

```text
DO NOT MERGE

FIX: <concrete blocker>
RECHECK: <concrete verification after fix>
```

Evaluate the recommendation strictly:

- `MERGE` — All relevant available validation for the touched scope passed. No known merge blocker remains. No further relevant check is required before merge.
- `CHECK THEN MERGE` — Relevant automated/agent-executable validation passed, but one meaningful runtime, visual, hardware, production-data, environment-specific, or other human-executable check remains. `CHECK:` must name the context and concrete verification; merge only if the check passes.
- `DO NOT MERGE` — A relevant check fails, a material requirement is unresolved, or a known risk is too large to recommend merge. `FIX:` must identify the blocker and `RECHECK:` must identify the concrete verification required after the fix.

Do not use `CHECK THEN MERGE` merely because this is a Godot project. The remaining check must be materially relevant to the touched scope. Do not delegate a check the agent can actually execute. For runtime or presentation changes, name the concrete Godot scene/harness check when that is the remaining action. Never use vague `manual check` wording when a specific action can be named.

The final report must also include the issue number, active branch name, delivery commit hash, tests/validation actually performed and their results, PR link or ID, confirmation that the issue was updated with validation evidence, and anything still outstanding.

The dedicated issue branch and PR delivery workflow are the default for issue implementation work and do not need to be requested separately.

## Dependency graph execution

Treat the project roadmap as a dependency graph rather than a mandatory linear queue.

For non-trivial tracked work:

- Read the issue's `## Dependencies` section before starting.
- An issue may be implemented when its real implementation dependencies are satisfied, regardless of its linear roadmap position.
- Do not introduce artificial blockers merely because another issue is listed earlier.
- `Independent` means no real implementation blocker; it does not override product priority or an explicit defer note.
- `Blocked` means do not implement until the listed dependency is satisfied.
- `Integration-sensitive` means implementation may proceed, but shared contracts/consumers and listed conflicts must be handled explicitly.
- Treat `Can run in parallel with` as evidence-based. Do not claim parallel safety unless the relevant scopes/contracts have actually been assessed.
- Keep parallel issue work isolated on separate branches and PRs.

## User-facing CLI commands

When asking the user to run project commands manually:

1. Make commands copy-paste ready and independent of the current repository subdirectory where practical.
2. Refer to project files with explicit repository-relative paths, for example `harness/gps/gps_harness.tscn`.
3. When a command requires the repository root on macOS/Linux, prefer:

   ```bash
   ROOT="$(git rev-parse --show-toplevel)" && <command using "$ROOT">
   ```

   This may assume the user is somewhere inside the Git working tree, but must not assume the user is already at its root.
4. Do not add `git pull`, `git reset`, `git clean`, branch deletion, merge, or similar state-changing Git operations merely to make a command convenient.
5. Do not assume the working tree is clean before suggesting branch-changing commands.
6. Prefer one complete command the user can execute directly over a sequence that depends on unstated shell state.

### Godot CLI

When asking the user to launch Godot manually on macOS/Linux, resolve the repository root and pass it with `--path` instead of relying on the current working directory. Prefer commands such as:

```bash
ROOT="$(git rev-parse --show-toplevel)" && godot --path "$ROOT" harness/world/world_harness.tscn
```

Do not use ambiguous bare commands such as:

```bash
godot harness/world/world_harness.tscn
```

when behavior depends on the current working directory.

## Key reminders

### 1. No speculative abstraction

Implement the smallest explicit module and API that solves the current problem.

Do not introduce frameworks, generic service layers, deep inheritance hierarchies, DI frameworks, mock frameworks, or universal abstractions without a concrete current need.

### 2. Strict dependency direction

Preserve:

```text
core/domain -> adapter -> presentation
```

Portable/domain logic must not depend on Godot rendering, UI, SceneTree structure, TCP/JSON/process behavior, or harness code.

### 3. Explicit composition

Do not use fragile scene-tree traversal such as `get_node("../../...")` or `$"../../../..."` to locate unrelated subsystems.

Dependencies between subsystems must be wired explicitly by the composition root, typically through small `setup(...)` APIs or similarly explicit construction.

Use the rule:

> Call downward, signal upward.

### 4. Keep composition roots thin

`main.gd`, game roots, and harness roots should primarily compose and coordinate systems.

Do not move domain logic into them.

### 5. Harness rule

Harness scenes must use the same production implementation as the real game.

Do not create alternate harness routers, world loaders, traffic systems, or other duplicate production logic.

Prefer real generated runtime/world data for integration and profiling. Use small deterministic fixtures only where they are genuinely useful for correctness or edge cases.

Only add a subsystem harness when current subsystem work benefits from isolated runtime verification; do not build speculative harness infrastructure for systems that do not need it yet.

### 6. World data has one authoritative pipeline

Do not independently rebuild competing road/world truth inside gameplay systems.

Runtime representations should derive from the authoritative offline build pipeline and be consumed through owned subsystem APIs.

### 7. Avoid global internal communication

Do not introduce a global EventBus for ordinary or high-frequency subsystem communication.

Use direct calls for owned dependencies and local signals for upward/lifecycle communication.

### 8. Preserve portability

Performance-sensitive logic should remain movable to portable C++ without requiring Godot/UI consumers to be rewritten.

Use small explicit data contracts at subsystem boundaries.

### 9. File responsibility

When touching a source file, preserve or add the short English responsibility/dependency header required by `ARCHITECTURE.md`.

### 10. Architectural conflicts

If a requested change would violate `ARCHITECTURE.md`, do not silently implement the violation.

State the conflict briefly and propose the smallest architecture-compliant alternative.

When reviewing code, actively flag violations of these rules.
