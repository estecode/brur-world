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

1. Read `AGENTS.md`, `ARCHITECTURE.md`, and the current issue before changing code.
2. Start from the latest `main` branch.
3. Create a dedicated branch named `issue/<number>-<short-name>`.
4. Keep concurrent issue work isolated on separate branches and avoid unrelated changes that increase merge conflicts.
5. Keep the implementation within the issue scope and acceptance criteria.
6. Implement the smallest architecture-compliant change that satisfies the issue.
7. Run the relevant tests and validation for the touched subsystem.
8. Commit completed work to the issue branch with a message that references the issue.
9. Do not merge the issue branch into `main` unless explicitly requested.
10. Report the branch name, commit, tests/validation performed, and anything still outstanding.

The dedicated issue branch is the default for issue implementation work and does not need to be requested separately.

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
