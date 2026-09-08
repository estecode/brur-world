# brur-world Architecture

This file defines the architectural rules for `brur-world`.

The goal is to keep gameplay/runtime systems small, isolated, testable, profileable and portable between Godot and native C++ where useful.

Do not introduce frameworks or abstractions only to satisfy this document. Prefer the smallest explicit boundary that solves the current problem.

---

## 1. Dependency direction

The fundamental dependency direction is:

```text
core/domain -> adapter -> presentation
```

Core/domain logic must not depend on:

- Godot rendering or UI
- SceneTree structure
- TCP/sockets
- JSON transport
- mmap/POSIX APIs
- command-line/process entrypoints
- harness code

Adapters may depend on core. Presentation may depend on adapters/core-facing APIs.

Never reverse this dependency direction.

---

## 2. Project composition

Production systems and harnesses consume the same implementation.

```text
production modules <- game composition
production modules <- harness composition
```

Rules:

```text
src/*     must never depend on harness/*
harness/* may depend on src/*
game/*    may depend on src/*
```

Harness code must never become a production dependency.

---

## 3. Subsystem ownership

Major systems own their own behavior and expose small explicit APIs.

Examples:

```text
world
routing
search
player
vehicle
traffic
police
ui
```

Do not reach into another subsystem's internal dictionaries, nodes or private state.

Prefer:

```gdscript
routing.find_route(...)
```

over:

```gdscript
routing._graph._nodes[...]
```

Public APIs should remain small enough that implementations can later be replaced or moved to C++ without rewriting consumers.

---

## 4. Composition instead of scene-tree coupling

Do not use scene-tree traversal to locate unrelated systems.

Avoid:

```gdscript
get_node("../../RoutingSystem")
```

or:

```gdscript
$"../../../TrafficManager"
```

Dependencies between systems are provided explicitly by the composition root.

Example:

```gdscript
func setup(routing_system: RoutingSystem) -> void:
    routing = routing_system
```

`game/*` and harness scenes are allowed to wire systems together.

`main.gd` / game root should primarily compose systems, not implement them.

---

## 5. Calls and signals

Use the simplest communication mechanism appropriate to ownership.

```text
Direct call
    ↓
owned dependency / explicit API

Local signal
    ↓
child -> owner / nearby lifecycle notification

Global gameplay event
    ↓
only genuinely cross-cutting gameplay events
```

Prefer the rule:

> Call downward, signal upward.

Do not create a global EventBus for high-frequency internal communication.

Examples of bad global events:

```text
vehicle_position_changed
route_node_changed
chunk_loaded
vehicle_speed_changed
```

A global event mechanism, if used, is reserved for genuinely broad gameplay events where direct ownership would be artificial.

---

## 6. Runtime harnesses

Major runtime subsystems that benefit from interactive verification should be runnable in isolation under:

```text
harness/<subsystem>/
```

Examples as they become necessary:

```text
harness/gps/
harness/world/
harness/driving/
harness/traffic/
harness/police/
```

Do not create future harnesses before their subsystem exists.

A harness:

- uses the same production implementation as the game
- may provide fixture inputs and debug controls
- should use real runtime data where practical
- may expose profiling/debug information
- must not contain an alternate implementation of the subsystem

Example:

```text
GPS problem     -> gps harness
World problem   -> world harness
Traffic problem -> traffic harness
Police problem  -> police harness
```

---

## 7. Tests vs harnesses

These solve different problems.

### Headless / contract tests

Answer:

> Is the logic/data contract correct?

Use deterministic input -> expected-output tests for portable logic.

Examples:

- route request -> route result
- bytes -> decoded values
- coordinates -> converted coordinates
- policy/state transition -> expected state
- Python reference -> native C++ semantic parity

### Harness scenes

Answer:

> Does the production subsystem work correctly inside Godot/runtime?

Use harnesses for:

- interaction
- streaming
- visualization
- performance
- integration boundaries
- real-data edge cases

Do not replace deterministic tests with manual harness testing.

---

## 8. World-data ownership

Gameplay systems must not independently recreate world truth.

The source pipeline is:

```text
Sweden OSM PBF
      ↓
offline build pipeline
      ↓
runtime datasets
```

The offline pipeline owns generation of runtime representations such as:

```text
render data
routing graph
search index
POI data
metadata
```

Runtime systems consume the appropriate optimized representation.

For example:

```text
WorldRenderer -> render data
RoutingCore   -> routing graph
SearchCore    -> search index
Traffic       -> road/routing data through owned APIs
Police        -> routing/observation APIs
```

Do not build another road graph inside Traffic or Police if Routing/World already owns the required representation.

Different optimized representations are allowed when they serve genuinely different runtime needs, but they must derive from the same authoritative offline source/build pipeline.

---

## 9. Coordinate ownership

Projected absolute coordinates, Godot world coordinates and tile coordinates must have one shared conversion owner.

Do not duplicate origin/sign/tile formulas across:

- world
- GPS
- POIs
- search
- traffic
- police

Coordinate math must remain deterministic and independent of rendering, camera state and routing policy.

See issue #48.

---

## 10. Native code boundaries

Performance-critical systems may move to portable C++.

Native core code should consume explicit data structures / immutable byte views and produce structured results.

Example direction:

```text
portable C++ core
      ↓
TCP / CLI / mmap adapter
      ↓
Godot adapter
      ↓
presentation
```

The portable core must not know that Godot, TCP or mmap exists.

Do not optimize by pushing presentation/transport concerns back into the core.

---

## 11. Real data first

For world, routing, traffic and police integration, prefer real production runtime data.

Useful repeatable scenarios may include:

```text
Stockholm centre
dense urban roads
E4 / motorway
rural road
large intersection
motorway interchange
```

Synthetic fixtures remain appropriate for deterministic correctness tests and hard-to-reproduce edge cases.

Do not build a separate fake world implementation for harness use.

---

## 12. File responsibility

Touched source files should begin with a short English comment describing:

- what the file does in plain language
- its important dependencies

Example:

```gdscript
##
## Routes vehicles over the loaded road graph.
##
## Dependencies:
## - Reads immutable routing graph data.
## - Does not depend on UI, rendering or player state.
##
```

Keep descriptions short.

---

## 13. Definition of done for a subsystem boundary

When applicable, a subsystem is in good architectural shape when:

- its core responsibility has one clear owner
- consumers use a small explicit API
- unrelated systems do not reach into its internals
- portable logic has deterministic tests
- Godot/rendering/UI are adapters rather than owners of domain rules
- it can be run in isolation through a harness when runtime inspection is useful
- the harness uses production code
- performance-sensitive work can be measured independently
- no duplicate world/routing truth has been introduced

---

## 14. Anti-patterns

Do not introduce:

- giant `main.gd` / bootstrap-style implementation owners
- sibling systems located through fragile NodePaths
- global EventBus for ordinary component communication
- one Resource type used as a universal service/interface abstraction
- duplicate routing/world representations without a measured reason
- mocks replacing real runtime world data in integration harnesses
- Godot UI/rendering inside portable simulation logic
- socket/JSON/process code inside routing/search cores
- speculative abstraction for systems that do not exist yet
- large inheritance hierarchies merely to share behavior

When in doubt:

> Prefer a small explicit module and a small explicit API.

---

## 15. AI guidance

Before architectural or cross-module changes, read this file.

New code must preserve these dependency rules. If an issue appears to conflict with this document, prefer the smallest change that satisfies the issue while preserving the architecture, and make the conflict explicit rather than silently introducing a new dependency direction.

`ARCHITECTURE.md` is the canonical architecture contract. GitHub issue #45 tracks the incremental work needed to reach and preserve it, while issue #50 tracks the harness convention and first subsystem harnesses.
