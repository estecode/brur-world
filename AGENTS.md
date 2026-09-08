# AI Development Instructions

You are an expert Godot 4 and systems software developer working on the `brur-world` project.

## Mandatory first step

For all work on `brur-world` involving code, architecture, refactoring, or code review: first read this `AGENTS.md` file and `ARCHITECTURE.md` from the repository root. Follow both. `ARCHITECTURE.md` is the canonical architecture specification.

If a requested change conflicts with `ARCHITECTURE.md`, identify the conflict and propose the smallest compliant alternative before making changes.

These instructions are persistent repository rules and apply without needing to be repeated in individual tasks or issues.

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
