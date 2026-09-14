# brur-world Architecture

This file defines the architectural rules for `brur-world`.

The goal is to keep gameplay/runtime systems small, isolated, testable, profileable and portable between Godot and native C++ where useful, while keeping one coherent world truth from offline data build through simulation, physics and presentation.

Do not introduce frameworks or abstractions only to satisfy this document. Prefer the smallest explicit boundary that solves the current problem.

---

## 1. Dependency direction

The fundamental dependency direction is:

```text
core/domain -> adapter -> presentation
```

Core/domain logic must not depend on Godot rendering/UI, SceneTree structure, TCP/sockets, JSON transport, mmap/POSIX APIs, command-line/process entrypoints or harness code.

Adapters may depend on core. Presentation may depend on adapters/core-facing APIs. Never reverse this dependency direction.

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

Major systems own their own behavior and expose small explicit APIs. Typical owners include world, routing, search, player, vehicle, traffic, police and UI.

Do not reach into another subsystem's internal dictionaries, nodes or private state. Public APIs should remain small enough that implementations can later be replaced or moved to C++ without rewriting consumers.

---

## 4. Composition instead of scene-tree coupling

Do not use scene-tree traversal to locate unrelated systems. Dependencies between systems are provided explicitly by the composition root.

`game/*` and harness scenes may wire systems together. `main.gd` / game root should primarily compose systems, not implement them.

---

## 5. Calls and signals

Use the simplest communication mechanism appropriate to ownership:

```text
Direct call -> owned dependency / explicit API
Local signal -> child -> owner / nearby lifecycle notification
Global gameplay event -> only genuinely cross-cutting gameplay events
```

Prefer:

> Call downward, signal upward.

Do not create a global EventBus for high-frequency internal state such as vehicle position, route-node changes, chunk loading or vehicle speed.

---

## 6. Runtime harnesses

Major runtime subsystems that benefit from interactive verification should be runnable in isolation under `harness/<subsystem>/` when the subsystem exists.

A harness uses the same production implementation as the game, may provide fixture inputs/debug controls, should use real runtime data where practical, may expose profiling/debug information, and must never contain an alternate implementation of the subsystem.

---

## 7. Testing strategy

> **Correctness is automated. Feel is playtested.**
>
> **Anything objectively machine-verifiable should be caught automatically, not discovered during playtesting.**

The testing boundary is objectively verifiable vs. subjective perception, not visual vs. code.

Use, in increasing integration cost:

1. fast deterministic core tests for portable rules/state/algorithms/data contracts;
2. headless Godot integration tests for real engine adapters, geometry, lifecycle and interaction-state contracts;
3. real-data integration tests against production Sweden data where synthetic fixtures can hide failures;
4. manual harness/playtesting only for feel, aesthetics, holistic UX, hardware-specific behavior or behavior that cannot reasonably be reduced to deterministic assertions.

Objective runtime invariants such as vehicle placement on the expected 3D drivable surface, camera/surface clearance, mesh bounds, UI overlap, route/control state transitions and LOD continuity must be automated where reasonably possible.

Prefer stable structural/geometric assertions over pixel-perfect screenshots unless pixels themselves are the behavior under test.

Do not create brittle or disproportionately expensive automation merely because something is theoretically measurable.

---

## 8. World-data ownership

Gameplay systems must not independently recreate world truth.

The source pipeline is conceptually:

```text
raw authoritative sources
      -> source adapters
      -> normalized source model
      -> deterministic world semantics / solvers
      -> versioned portable runtime artifacts
      -> runtime adapters
      -> simulation / physics / presentation
```

OSM, elevation data and future approved source datasets are source facts. Runtime code must not parse provider/source schemas as its domain model.

Different optimized runtime representations are allowed when they serve genuinely different needs, but they must derive reproducibly from the same authoritative build pipeline and may not become competing world truths.

Traffic, police, pedestrians, GPS and presentation must not build private road, lane, surface or coordinate truths when World/Routing already owns them.

---

## 9. Source schema is not runtime schema

Provider-specific schemas are confined to source adapters and normalized build inputs.

Runtime systems should never need to ask questions such as whether a source OSM object carried a particular raw tag in order to decide gameplay behavior. The build pipeline translates source facts into provider-independent world semantics with explicit provenance.

Changing or adding a source provider must not require rewriting traffic, GPS, physics or rendering rules when the normalized semantics remain equivalent.

---

## 10. Deterministic world build and portable artifacts

The offline build is part of the product architecture, not disposable glue.

For the same versioned source inputs and build configuration it must produce the same semantic world artifacts.

Derived artifacts must be:

- versioned and self-describing enough to fail closed on incompatible/corrupt input;
- deterministic in semantic content and stable ordering where applicable;
- portable/semantic rather than having a Godot scene or render mesh as the only truth;
- streamable/chunkable where scale requires it;
- reproducible/disposable from source data plus versioned build policy;
- attributable to source identity, builder/schema version and inference policy.

Runtime packaging consumes production artifacts. It must not become the owner of world semantics or compression policy.

---

## 11. Inference and provenance

Missing/ambiguous source data is resolved through a centralized, deterministic and versioned inference/fallback policy.

Do not scatter defaults such as lane width, bridge clearance, road class fallback or structure height across runtime consumers.

When practical, derived facts retain provenance equivalent to:

```text
explicit source fact
inferred from source context
conservative fallback
```

Debug/validation must be able to trace a problematic derived fact back to its source object(s), build rule/version and inference decision without scene-tree spelunking.

Known source truth always wins over heuristics. Contradictory/unknown source state fails conservatively rather than inventing a gameplay shortcut.

---

## 12. Spatial partitioning is implementation, not truth

Tiles, chunks, cells, cache blocks and LOD partitions exist for build/runtime performance only.

They do not own roads, structures, agents or world identity. Changing tile size or streaming strategy must not change domain identity, topology, elevation, collision outcome or simulation meaning.

Adjacent partitions that share a physical boundary must derive matching boundary facts deterministically. Streaming/LOD transitions must not introduce cracks, duplicate surfaces, changed authoritative heights or changed gameplay relationships.

---

## 13. Coordinate ownership and floating origin

Projected absolute coordinates, geodetic/source coordinates, Godot render-local coordinates and tile coordinates have one shared conversion owner.

Do not duplicate origin/sign/tile/floating-origin formulas across world, GPS, POIs, traffic, pedestrians, police or physics.

Coordinate math must remain deterministic and independent of rendering, camera state and routing policy.

Floating origin is presentation/runtime positioning infrastructure; it must not create a second logical world coordinate truth.

---

## 14. Authoritative vertical world truth

BRUR is a real 3D world from the first top-down playable milestone. Top-down is a camera/presentation choice, not a 2D simulation.

> **Vertical world truth is authoritative. Terrain, roads, lanes, bridges, tunnels, buildings, railways, pedestrian infrastructure, collision and gameplay must share one coherent 3D elevation model. No presentation subsystem may invent its own height.**

Conceptually:

```text
normalized elevation + topology/structure semantics
        -> authoritative terrain/world surface
        -> engineered road/structure surface profiles
        -> 3D lane/walk/rail poses
        -> collision + simulation + presentation adapters
```

A world-surface API may expose facts equivalent to terrain height at a world position. A drivable-surface API may expose position, heading, slope/surface normal and layer/structure relation along a road/lane. Exact type names are implementation details.

The same XY coordinate may validly contain multiple gameplay surfaces at different Z. 2D overlap must never imply connectivity, occupancy conflict or collision when layers are physically separated.

---

## 15. Terrain, roads and engineered elevation

Elevation/terrain data is an authoritative build input, not a cosmetic shader.

Terrain must be tile/LOD/streaming friendly with bounded memory and work. LOD may reduce geometric fidelity but must not change authoritative surface relationships or gameplay outcomes in the active gameplay region.

Roads must not blindly drape over every raw elevation sample. Roads are engineered surfaces. Build-time road profiles should use terrain plus road/structure semantics and deterministic constraints such as bounded grade, smooth vertical curvature and local cut/fill/embankment behavior.

Road/terrain adjustment must have bounded spatial influence. A road corridor may alter its immediate engineered surface without deforming an entire landform. Bridge decks do not pull terrain up to deck height; tunnels do not push surface terrain down to tunnel elevation.

Water bodies need a coherent surface-elevation contract sufficient for shorelines, bridges and collision/presentation alignment even before advanced water physics exists.

---

## 16. Bridges, tunnels, railways and grade separation

Source `bridge`, `tunnel`, `layer` or equivalent facts express semantics/topology, not meters of elevation by themselves.

Build-time structure solving must produce physically coherent 3D profiles and relationships. Use explicit source height/clearance facts when available; otherwise use deterministic conservative inference.

Bridge profiles include approach continuity, deck elevation and required clearance. Tunnel profiles include approach/descent, underground section and exit/ascent. Rail and pedestrian/cycle grade separation participate in the same vertical truth even when their simulation is not yet implemented.

Vertical clearance is a world semantic so future vehicle dimensions can determine whether a path is physically feasible.

---

## 17. Buildings and surface adaptation

Buildings and other grounded structures consume authoritative world surface information rather than selecting their own Y values.

A building footprint may sample the local surface and derive a stable foundation/base plus bounded foundation/skirt geometry so terrain slope does not leave obvious floating/sinking corners.

More detailed foundations/interiors are future presentation work; the foundational relation to terrain and gameplay collision must not require an architectural rewrite.

---

## 18. Portable simulation by default

For population, traffic, pedestrians, player-control policy, autonomous driving, gameplay physics policy and similar runtime systems, keep domain state, rules and decision logic portable whenever they do not intrinsically require Godot.

Ask:

> **Could this logic run without Godot?**

If yes, it should normally live in core/domain state or policy and receive explicit data through a small API.

Godot primarily provides composition, input adapters, engine collision-world integration, scene/node lifecycle and presentation.

---

## 19. Simulation truth vs. presentation fidelity

World entities have one logical identity/state. Map, top-down driving, future Chase/Driver cameras, simulation LOD and presentation LOD must not create competing copies of world truth.

Simulation fidelity may independently range from aggregate/virtual state to lightweight individual state to detailed nearby actors and gameplay-pinned actors. Presentation fidelity may range from full 3D to proxy/marker/aggregation.

Changing either fidelity level must preserve continuity and gameplay-relevant facts. Performance degradation may reduce update rate, visual detail or distant density, but may not erase consequences, rewrite observed identity, violate known world/routing truth or introduce unbounded work/state growth.

Population/LOD systems must use bounded work/storage. Gameplay relevance can override pure distance.

---

## 20. Player control is independent from camera/view

World/gameplay state, player-control state and camera/view state are separate responsibilities.

Manual Drive is a control mode, not a camera mode. GPS Auto Drive is a control mode, not a camera mode. Top-down, Map, future Chase and Driver cameras are presentation choices over the same running player vehicle/world state.

The player vehicle has one persistent identity across camera changes, Manual/GPS control, named teleports and floating-origin shifts and is always gameplay-pinned while active.

Input ownership is explicit. The same physical input must not simultaneously control a map camera and a vehicle because two modes happened to be active.

---

## 21. Top-down-first 3D presentation

The first prioritized driving presentation is a configurable tilted perspective top-down camera over the real 3D world.

Initial tuning may target roughly 60-100 m above the vehicle with a baseline near 75 m, but height, tilt, FOV, follow offset, look-ahead and smoothing are profile/configuration data and are finalized by playtesting rather than architecture.

Camera height follows the player/local authoritative surface rather than absolute world Y and smooths elevation changes to avoid terrain-noise jitter. Camera motion never owns simulation/population existence.

Future Chase/Driver/hood cameras must be addable without changing vehicle, routing, traffic, physics or control-domain state.

---

## 22. Autonomous player driving contract

GPS Auto Drive must use the same world, lane, traffic, occupancy and vehicle-physics truth as ordinary gameplay.

Conceptually:

```text
GPS destination/route
    -> route intent
    -> lane/maneuver planner
    -> driver policy/profile
    -> throttle / brake / steering / gear requests
    -> shared VehicleDynamics / physics
    -> actual vehicle motion
```

> **GPS Auto Drive may plan better, but it may never cheat world, routing, traffic, occupancy or physics truth.**

> **Auto Drive may never do anything that a physical driver of the same car could not do with throttle, brake, steering and gear.**

GPS decides where to go; lane/local-driving policy decides how to attempt it; physics decides what actually happens.

No direct transform driving, teleport recovery, ghosting through traffic, impossible lane changes, instant U-turns or stale-route shortcuts.

Physical feasibility outranks route obedience. A missed turn/exit and reroute is valid when the desired maneuver is no longer safely/physically available.

---

## 23. Driver state, handover and observability

Autonomous driving has explicit state for route/version, committed maneuvers, rerouting, blockage/world-data wait, safe stop, completion and no-progress diagnosis.

Manual/GPS handover is stateful and physically continuous. A Manual request may wait only long enough to complete the critical safe portion of a maneuver or reach a safe stop, while an explicit emergency manual takeover remains possible so automation cannot trap the player.

Normal/Aggressive/Maniac are data-driven driver profiles over one implementation. They may affect speed preference, following distance, reaction latency, gap acceptance and maneuver willingness, but never vehicle grip, braking capability, power or physical geometry.

Autonomous actions that physically affect the player vehicle must be traceable through:

```text
route/version -> decision/reason -> requested driver input -> actual vehicle response
```

Driver intent/reason/action/result is emitted as structured production state/events. Gameplay feed, debug UI, replay and tests consume that one source rather than inventing separate explanations.

Requested control and actual vehicle response remain separately observable.

---

## 24. Gameplay physics and collision truth

Gameplay-critical collision truth is separate from render geometry and visibility.

A mesh being hidden, culled, replaced or simplified for presentation must not remove collision that active gameplay depends on. Physics simplification is allowed for performance, but inside the active gameplay region it must remain conservative enough that it cannot permit physically impossible pass-through or equivalent outcomes.

Static world collision and dynamic actor collision have explicit ownership and bounded lifecycle. Physics queries use shared coordinate/floating-origin rules and authoritative 3D surface/layer relationships.

Physical material facts needed by future systems such as ballistics belong to gameplay/world collision contracts or portable policy, not weapon-specific render code.

---

## 25. Performance, memory and graceful degradation

Performance and memory are architecture constraints, not late polish.

Every scalable subsystem must define bounded work/storage behavior appropriate to its scope: caches, nodes, actors, collision shapes, streamed tiles, build buffers, queues and per-frame updates may not grow without an explicit bound/lifecycle.

Use hard caps, pooling/instancing, time slicing, spatial indexes, multi-rate simulation, streaming and bounded caches where they materially help.

Measure stable behavior including p95/p99 frametime, not only average FPS. Build pipelines additionally measure wall-clock, peak/working memory, temporary disk and artifact size where relevant.

Graceful degradation reduces distant fidelity/update frequency/density first and protects observed/gameplay-relevant state. It may never change authoritative world truth, erase gameplay consequences or allow impossible physical outcomes.

Stress/soak tests must protect architectural bounds where objective automation is practical.

---

## 26. Determinism and time ownership

Critical simulation and world-build behavior must be reproducible from explicit state/input/version/seed.

Render frame rate must not become semantic decision input. Equivalent simulation state should not make different lane/route/driver decisions merely because rendering ran at 30 vs. 60 vs. 120 FPS.

WorldClock/simulation time and wall-clock/system time are distinct. Pause/resume must not secretly advance portable driver/simulation decisions unless the owning simulation contract explicitly says so.

---

## 27. Real data and regression fixtures

For world, routing, traffic, terrain/elevation and physics integration, prefer production data where synthetic fixtures could hide boundary errors.

Maintain a small fixed real-Sweden regression corpus, including Lund, Malmö and Stockholm plus representative difficult geometry such as a multi-level interchange, bridge over road/water, tunnel, steep road, railway grade separation and dense urban intersection.

Named player teleport anchors are resolved through authoritative road/lane/layer/elevation/occupancy truth and are also regression fixtures; they are not raw XYZ constants or an Auto Drive recovery mechanism.

Synthetic fixtures remain appropriate for precise edge cases. There is no privileged alternate test world implementation.

---

## 28. UI/debug ownership

Gameplay controls/status and debug tooling are separate presentation responsibilities.

Gameplay UI has priority. No overlay may obscure another interactive overlay. Layout ownership is centralized enough to reserve regions/safe areas rather than letting every feature freely place floating controls.

Debug information is consolidated before allocating new screen area, is collapsible/hideable and should group related telemetry (for example Vehicle, Routing, Population, Physics) rather than create one panel per metric.

Objective no-overlap/viewport constraints are automated across representative viewport sizes/UI scales where reasonably possible. Manual review judges readability/feel.

---

## 29. Native code boundaries

Performance-critical systems may move to portable C++.

Native core code consumes explicit data structures / immutable byte views and produces structured results. Transport/process/mmap/Godot concerns remain adapters.

Do not optimize by pushing presentation, source-provider or transport concerns back into portable core.

---

## 30. File responsibility

Touched source files should begin with a short English comment describing what the file does in plain language and its important dependencies.

Keep descriptions short.

---

## 31. Definition of done for a subsystem boundary

When applicable, a subsystem is in good architectural shape when:

- its core responsibility has one clear owner;
- consumers use a small explicit API;
- unrelated systems do not reach into internals;
- portable logic has deterministic tests;
- Godot/rendering/UI are adapters rather than owners of domain rules;
- production/harnesses use the same implementation;
- real-data integration is exercised where synthetic tests can hide failures;
- performance-sensitive work is independently measurable and bounded;
- no duplicate world/routing/coordinate/elevation truth has been introduced;
- derived data is versioned/reproducible/provenance-traceable where applicable;
- objective correctness is automated before manual feel testing.

---

## 32. Anti-patterns

Do not introduce:

- giant `main.gd` / bootstrap implementation owners;
- sibling systems located through fragile NodePaths;
- global EventBus for ordinary component communication;
- one Resource type as a universal service/interface framework;
- duplicate routing/world/elevation representations without measured reason and explicit derivation;
- mocks replacing production world data in integration harnesses;
- Godot UI/rendering inside portable simulation logic;
- source-provider tags/types leaking directly into runtime gameplay policy;
- Godot mesh/scene data as the only authoritative world artifact;
- tile/chunk ownership becoming domain identity;
- per-subsystem inference/defaults for shared world facts;
- socket/JSON/process code inside portable domain cores;
- camera/frustum-driven population existence;
- autonomous vehicle motion by direct transform/teleport shortcuts;
- unbounded caches/nodes/actors/build buffers justified as temporary;
- speculative frameworks for systems that do not exist yet;
- large inheritance hierarchies merely to share behavior.

When in doubt:

> Prefer a small explicit module and a small explicit API.

---

## 33. Living-world program

Detailed living-world design and delivery dependencies are tracked by umbrella issue #286 and `docs/living_world_population_traffic_physics.md`.

The living-world program must preserve all rules above, especially portability by default, one world truth across fidelity/view changes, authoritative vertical world truth, deterministic/reproducible build/simulation behavior, explicit physics truth, bounded performance/memory and automated objective correctness.

---

## 34. Future gameplay extensibility contract

Current living-world work must leave room for richer gameplay without making those future systems dependencies of Waves B-G.

The architectural boundary is:

```text
world entities + persistent gameplay state
        -> owned subsystem APIs / structured gameplay events
        -> scenario/mission orchestration
        -> cinematic/dialogue/UI/audio presentation
```

Rules:

- People, Vehicles, Places and future Items use stable logical identities. Gameplay-relevant state that may outlive a scene/view/session must be designed so it can become versioned persistent state rather than being owned only by transient Godot nodes.
- Future inventory/equipment/ownership/containment must be representable as gameplay/domain state. Items may later be carried by People, stored in Vehicles/Places/containers or exist in the world without requiring separate incompatible item models.
- A Person or Vehicle is not a special "mission actor" type. Scenario participation, player control, AI control, cinematic focus, passenger/driver role, witness role or similar responsibilities are roles/state over the same logical entity.
- Generic gameplay actions/interactions and their results should cross subsystem boundaries through small owned APIs and structured events. Scenario code must not directly mutate private traffic, physics, inventory, police, communication or world internals.
- Scenario/mission systems orchestrate intentions, conditions, timers, branches and consequences; they do not become owners of world truth. A future visual editor must author the same runtime scenario data/contracts rather than define a second runtime model.
- Hand-authored scenarios and template-driven scenarios may resolve actors, routes and locations through authoritative People/Vehicle/POI/world semantics. Template variation must not invent raw coordinates or bypass world constraints merely to satisfy a mission beat.
- Cinematics/cutscenes are presentation/control orchestration over the same live world entities where practical. Camera changes or cinematic control handover must not require duplicate actors, a duplicate world, or state reset.
- Timed decisions use explicit simulation/gameplay-time deadlines, choices and defined timeout outcomes. UI presentation of a decision is not the decision's source of truth, and consequences may be immediate or delayed.
- Future communications such as SMS, calls, contacts, multiple phones or burner phones remain an owned gameplay subsystem. Exact phone UX/schema is intentionally not fixed by this contract.
- Dialogue content is referenced through stable dialogue/event identity rather than hardcoded presentation strings in gameplay logic. Spoken audio, subtitles and closed captions are separate presentation assets. Spoken dialogue may initially be Swedish-only without preventing later text/caption localization. Closed captions may include speaker and meaningful non-speech audio cues.
- Knowledge, relationships/factions/reputation, crime/police response, health/damage, economy, interiors, schedules, weather and audio-awareness may be added later through owned subsystem contracts. Current waves must not create hard dependencies on speculative implementations of them.
- Gameplay code must not assume a scripted happy path. Future scenarios must be able to observe timeout, failure, death/incapacitation, arrest, missing actor/item, route failure or other alternate results without forcing world state back to the script.
- Persistence/save format, scenario file format, mission editor, phone behavior, inventory UX and exact future gameplay mechanics are intentionally deferred until their own scoped work exists.

When extending gameplay, preserve the same principle used elsewhere in this architecture:

> **Orchestration may request and observe gameplay; it may not replace the subsystem that owns the truth.**

---

## 35. Replaceable presentation and production-asset contract

BRUR must be able to evolve from simple placeholder visuals to production-quality art without rewriting world truth, simulation, gameplay, physics, persistence or entity identity.

The boundary is:

```text
authoritative entity/world state
        -> presentation-facing semantic state
        -> replaceable presentation recipe / asset selection
        -> mesh / rig / animation / materials / audio / lights / VFX
```

Rules:

- A Building, Vehicle, Person or other presentable world entity keeps the same logical identity and gameplay-relevant state regardless of which visual representation is currently active. This does not require one universal entity class; each domain owner keeps its own model and API.
- Meshes, scenes, textures, PBR materials, rigs/skeletons, animation graphs/clips, audio, lights, shadows, decals, particles and other VFX are presentation assets. They must not become the owner of entity identity, world truth, gameplay state, route/lane state, persistence or authoritative physics state.
- Placeholder/simple geometry is a valid temporary or low-fidelity presentation, not an architectural truth. The same entity may progress from placeholder to procedural/generated representation to production asset to entity-specific or handcrafted override without identity reset or gameplay-state migration.
- Presentation LOD, instancing, culling and asset replacement may change visual fidelity but must not change gameplay/collision truth. Gameplay-critical collision follows section 24 even when visual meshes are hidden, simplified or replaced.
- Animation presents authoritative simulation/physics state. Character locomotion, vehicle movement, wheel steering/rotation, suspension, doors or similar motion may be animated from owned gameplay/physics state, but presentation animation must not silently become the source of authoritative world movement unless an explicitly scoped system owns that gameplay action.
- World/build pipelines should preserve useful provider-independent semantics and provenance that future presentation can consume, such as building dimensions/type, vehicle class/dimensions or person presentation attributes when such facts exist. They must not bake today's renderer, mesh topology, material library or current placeholder choices into world truth.
- Presentation artifacts should be independently regenerable/cacheable where practical. A new building generator, vehicle asset pack, character rig or material/shader version should not force unrelated routing, traffic, terrain or search artifacts to rebuild when their authoritative inputs and contracts are unchanged.
- Asset/archetype selection may be data-driven and may support specific entity/landmark overrides, but selection is presentation policy over stable identity. Handcrafted overrides must not require creating a competing Building/Vehicle/Person truth.
- Future art systems may add detailed facades, windows, interiors, clothing, faces, damage visuals, vehicle parts, vegetation, weather response, lighting or other production presentation without requiring current gameplay/domain systems to know those asset schemas.
- Exact production asset formats, art tools, procedural-building generator, character rig, animation state machine, material library and authoring workflow are intentionally deferred until scoped implementation exists. Do not create speculative frameworks merely to anticipate them.

The governing rule is:

> **Presentation may become richer or be replaced entirely; authoritative identity, world truth and gameplay state must survive unchanged.**
