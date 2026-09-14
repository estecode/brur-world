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

## 7. Testing strategy

> **Correctness is automated. Feel is playtested.**
>
> **Anything objectively machine-verifiable should be caught automatically, not discovered during playtesting.**

Validation is divided by responsibility and cost.

### Automated correctness vs. manual playtesting

The testing boundary is **objectively verifiable vs. subjective perception**, not "visual vs. code". **You should never be a human assert-runner.**

Any objectively observable runtime state or presentation invariant must be automated where reasonably possible. This includes spatial, structural, rendering-state and interaction-state invariants that can be asserted programmatically in headless Godot. The fact that a property exists in a rendered scene does not make it a manual test.

Examples of objective invariants include:

- a vehicle spawn is on or above its expected drivable surface within tolerance, including terrain, bridges and tunnels
- world chunks and route meshes exist and have sane bounds for the expected coordinates
- a camera does not penetrate terrain or other surfaces according to its defined collision/clearance contract
- follow-camera behavior keeps its target within a defined position or screen-space tolerance
- UI rectangles remain inside the active viewport and do not overlap explicitly forbidden zones
- state transitions such as manual driving takeover, GPS control release/reacquisition and reroute requests follow their defined contracts

Manual playtesting should be reserved primarily for perception, feel, aesthetics, hardware-specific behavior, holistic UX, or other behavior that cannot reasonably be reduced to deterministic assertions. Examples include whether camera smoothing feels cinematic, vehicle handling feels rewarding, clouds look natural, or a layout feels intuitive.

Do not create brittle or disproportionately expensive automation merely because a property is theoretically measurable. Prefer the smallest stable invariant that proves the behavior users depend on.

### 1. Core tests

Fast, deterministic tests for portable/domain behavior without SceneTree or presentation dependencies.

Typical examples:

- rules and algorithms
- state transitions
- coordinate conversion
- routing semantics
- protocol/data contracts
- native/reference parity

### 2. Godot integration and harness tests

Headless Godot tests verify integration that requires the runtime while using the real production modules.

Typical examples:

- scene wiring
- signals and adapters
- input -> production API
- lifecycle
- generated meshes
- visibility/state
- runtime contracts

Tests and harness controls should use existing public subsystem APIs, or a small harness-specific adapter/controller when that boundary is useful. Do not add test-specific APIs to production/domain code, and do not require a harness controller when the existing production API is sufficient.

### 3. Real-data integration tests

Use real production datasets and native processes where synthetic fixtures could hide integration failures.

Typical examples:

- real Sweden routing/world data
- native process startup/shutdown
- cross-boundary coordinate correctness
- streaming/data-format compatibility
- realistic data edge cases

These tests may be slower and should run when relevant to the touched integration boundary rather than for every small change.

### 4. Manual harness and playtesting

Manual verification is primarily for human perception, interaction, hardware-specific behavior, or behavior that cannot reasonably be automated.

Typical examples:

- visual readability
- camera feel
- driving feel
- animation
- UX
- gameplay/police feel
- difficulty and presentation

Repeated objective manual checks should be treated as candidates for automation.

### Render validation

Prefer deterministic state and geometric assertions for correctness, such as:

- node/mesh existence
- visibility/state
- vertex and surface counts
- sane bounding boxes
- coordinate alignment
- route length/endpoints
- streamed tile counts
- POI counts

Avoid pixel-perfect screenshot comparison when structural assertions verify the same behavior more reliably. Screenshot regression tests may be used when rendered pixels themselves are the behavior under test.

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

---

## 16. Portable simulation by default

For population, traffic, pedestrians, gameplay physics policy and similar runtime systems, keep domain state, rules and decision logic portable whenever they do not intrinsically require Godot.

Use this question at subsystem boundaries:

> **Could this logic run without Godot?**

If yes, it should normally live in core/domain state or policy and receive explicit data through a small API. Godot should primarily provide composition, engine adapters, collision-world integration and presentation.

This rule does not require speculative abstraction. Use the smallest explicit portable boundary that solves the current issue.

---

## 17. Simulation truth vs. presentation fidelity

World entities have one logical identity/state. Map, Drive, simulation LOD and presentation LOD must not create competing copies of world truth.

Simulation fidelity may range from aggregate/virtual state to lightweight individual state to detailed nearby actors and gameplay-pinned actors. Presentation fidelity may independently range from full 3D to proxy/marker/aggregation.

Changing either fidelity level must preserve the facts that matter to continuity and gameplay. Performance degradation may reduce update rate, visual detail or distant density, but it must not erase gameplay consequences, rewrite observed identity, violate known world/routing truth or introduce unbounded work/state growth.

Population/LOD systems must use bounded work and storage. Gameplay relevance can override pure distance when deciding fidelity.

---

## 18. Gameplay physics and collision truth

Gameplay-critical collision truth is separate from render geometry and visibility.

A mesh being hidden, culled, replaced or simplified for presentation must not remove collision that active gameplay depends on. Physics simplification is allowed for performance, but inside the active gameplay region it must remain conservative enough that it cannot permit physically impossible pass-through or equivalent gameplay outcomes.

Static world collision and dynamic actor collision should have explicit ownership and bounded lifecycle. Physics queries must use shared coordinate/floating-origin conversion rules rather than inventing another coordinate path.

Physical material facts needed by future systems such as ballistics belong to gameplay/world collision contracts or portable policy, not to weapon-specific render code.

---

## 19. Deterministic living-world regression contracts

Population, traffic and pedestrian systems should preserve stable identity/state across fidelity transitions and expose deterministic inputs sufficient to reproduce critical scenarios.

Where applicable, automated coverage should include long-running bounded-state checks, promotion/demotion continuity, Map/Drive continuity, rapid observation-direction changes, world-boundary/dead-end distinctions, occupancy/queue persistence and gameplay collision behavior.

Synthetic fixtures prove precise invariants; real-data fixtures prove integration with production world/routing data. Harnesses and presentation must consume the same production implementation rather than reproducing the rules under test.

Detailed living-world design and delivery dependencies are tracked by umbrella issue #286 and `docs/living_world_population_traffic_physics.md`.