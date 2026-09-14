# Living world: population, traffic, pedestrians and gameplay physics

Status: canonical systemspec under umbrella issue #286. Root `ARCHITECTURE.md` remains the canonical architecture contract.

## 1. Purpose

BRUR should feel like a continuous real 3D world rather than a collection of camera-relative NPC spawners or view-specific simulations.

Vehicles and people are world entities with one logical identity/state. Terrain, roads, lanes, bridges, tunnels, buildings, collision and gameplay share one coherent vertical world truth. Map, top-down driving, future Chase/Driver cameras, simulation LOD and presentation LOD are views/fidelity levels of that same world.

The first prioritized playable presentation is a tilted perspective top-down driving view over the real 3D world. This is not a 2D simulation and must not create throwaway 2D logic.

The system must be realistic where the player can observe or affect it, aggressively bounded where exact simulation is unnecessary, deterministic/reproducible enough to debug and test, and portable enough that performance-critical domain logic can move between GDScript and native C++ without rewriting consumers.

Project rule:

> **Correctness is automated. Feel is playtested.**

## 2. Non-negotiable program requirements

1. **No observable pop-in/pop-out.** Visible or recently observed agents must not be casually created, removed, teleported or identity-swapped.
2. **No duplicated world truth between views, LOD or subsystems.** One logical identity/state exists per entity; views/fidelity adapt it.
3. **Population and world streaming must remain bounded.** Frametime, node-count, collision resources, caches, state, build buffers and memory require explicit lifecycle/budgets.
4. **No machine-verifiable invariant may depend on manual testing.** Objective behavior belongs in deterministic/core, headless Godot, real-data, stress or soak tests where reasonably possible.
5. **Gameplay consequences survive LOD/population changes.** Queues, collisions, blockages, interactions, chases and observed identities cannot be erased to save work.
6. **NPC/Auto Drive decisions must not contradict known world/routing truth.** One-way, lane topology, turns, access, boundaries, crossings and physical layers are authoritative; uncertainty fails conservatively.
7. **Performance degradation changes fidelity, never truth.** Lower update rate, visual detail or distant density is allowed; changed topology, elevation, collision outcome or meaningful state is not.
8. **Critical behavior is reproducible.** Explicit source/build versions and simulation seed/state must be enough to reproduce failures.
9. **Gameplay physics/collision truth is independent of presentation.** Render meshes are not authoritative collision truth.
10. **Physics simplification may reduce fidelity but must not permit physically impossible active-gameplay outcomes.**
11. **Vertical world truth is authoritative.** Terrain, roads, lanes, bridges, tunnels, buildings, rail/pedestrian structures, collision and gameplay share one 3D elevation model.
12. **Source schema is not runtime schema.** Runtime gameplay must consume provider-independent world semantics, not raw OSM/DEM/provider tags.
13. **World build is deterministic and provenance-traceable.** Same versioned inputs/config produce the same semantic artifacts and derived facts can be traced to source/inference.
14. **Camera and control are independent.** Manual/GPS control must survive camera changes without recreating player/world state.
15. **GPS Auto Drive may never cheat world, traffic, occupancy or physics truth.**

## 3. Canonical dependency flow

```text
raw authoritative sources
  -> source adapters
  -> normalized source model
  -> deterministic world semantics / solvers
  -> versioned portable runtime artifacts
  -> runtime adapters
  -> portable simulation / policy / player-control state
  -> engine physics/collision integration
  -> presentation (Map / top-down / future cameras / UI)
```

Godot primarily owns composition, input adapters, collision-world integration, scene/node lifecycle and presentation.

Domain/simulation/policy logic that can run without Godot should normally do so.

## 4. World-data and build boundaries

### Source facts

OSM, elevation data and future approved datasets are raw/normalized source facts. They are not runtime APIs.

Provider-specific details belong in adapters. The normalized source model preserves the semantic facts required by world building while avoiding provider lock-in.

### Derived world semantics

Build-time semantics/solvers own normalized facts such as:

- road/lane direction and access
- bridge/tunnel/grade-separation relationships
- pedestrian/cycle/rail relationships
- terrain/elevation samples
- road engineered elevation profiles
- structure clearances
- normalized physical/world surface classifications
- inference provenance

### Portable artifacts

Runtime artifacts may be optimized differently for rendering, routing, search, collision or simulation if those needs genuinely differ. They still derive from one authoritative pipeline and may not become independent truths.

Artifacts are versioned, deterministic, fail-closed on incompatibility/corruption and reproducible from source identity + builder/schema version + build policy.

### Inference

Use explicit source facts where available, then deterministic conservative inference, then conservative fallback.

Defaults such as lane width, bridge clearance, road-profile constraints or missing structure facts are centralized/versioned. They must not be reinvented by traffic, GPS, rendering or physics.

Derived facts should expose provenance sufficient to answer whether they came from explicit source data, inference or fallback and which build rule/version produced them.

### Spatial partitioning

Tiles/chunks/cells exist for storage, streaming and LOD. They are not domain owners.

Changing tile size or cache strategy must not change entity identity, topology, elevation, collision or gameplay meaning.

Adjacent tiles and LOD levels must meet deterministically without seams, duplicate physical surfaces or changed authoritative height.

## 5. Authoritative 3D surface truth

The first top-down milestone uses real terrain elevation and true 3D world relationships.

Conceptually:

```text
DEM/elevation + normalized topology/structures
        -> authoritative terrain/world surface
        -> engineered road/structure profiles
        -> 3D lanes / walk / rail poses
        -> collision + simulation + presentation
```

A surface query should be able to answer world-surface facts without depending on a render mesh. A road/lane surface query should be able to provide equivalent facts to 3D position, heading, slope/surface normal and layer/structure relation.

Same XY may contain multiple valid Z surfaces. Bridge traffic and traffic below must not collide merely because projected XY overlaps.

## 6. Terrain and elevation

Terrain uses real elevation input and must be tile/LOD/streaming friendly with bounded work and memory.

LOD can simplify geometry but may not move authoritative active-gameplay surfaces or change relationships to roads/structures.

Terrain tile borders and LOD transitions require deterministic shared edge facts so no cracks or physical jumps appear during streaming.

Water bodies need coherent surface elevation sufficient for bridges, shores and presentation/collision alignment, even before advanced water physics.

## 7. Roads as engineered 3D surfaces

Regular roads are not blindly draped over raw DEM noise.

Build-time road profiles combine terrain + topology/structure semantics + deterministic engineering constraints, including where appropriate:

- bounded grade
- smooth vertical curvature
- local cut/fill/embankment behavior
- connection continuity
- correct layer/structure relations

Road modification has bounded local influence. It may shape its immediate corridor but not deform unrelated terrain.

Lane geometry derives from the authoritative road surface. Lane poses are true 3D and are used by traffic, GPS, teleports, collision/presentation alignment and validation.

## 8. Bridges, tunnels and grade separation

`bridge`, `tunnel`, `layer` and equivalent source facts provide topology/ordering, not exact meters by themselves.

The world build derives coherent physical profiles:

```text
road -> approach -> bridge deck -> approach -> road
road -> descent -> tunnel -> ascent -> road
```

Explicit height/clearance metadata wins when present. Otherwise inference is deterministic and conservative.

Bridge/tunnel profiles must preserve bounded grade/curvature and required clearance over/under other relevant surfaces.

Basic procedural presentation can derive deck thickness, portals, barriers/rails/supports from the same structure truth. Presentation detail may improve later without changing physical/world semantics.

Railways and pedestrian/cycle bridges/tunnels participate in the same vertical world truth even before their full simulation exists.

Vertical clearance becomes a world semantic so future vehicle dimensions can decide feasibility.

## 9. Buildings and terrain adaptation

Buildings consume the same world surface.

A footprint may sample terrain and derive a stable foundation/base plus bounded skirt/foundation geometry. Buildings must not visibly float at one corner or sink arbitrarily at another because a center-point Y was used.

Detailed foundations/interiors may come later. Their later addition must not require a new height/collision truth.

## 10. Agent identity and simulation fidelity

Every logical individual has stable identity and enough state to preserve continuity. State may include world position, path/edge/lane, progress, heading, speed, destination, behavior, committed maneuver/crossing state, recent observation and gameplay relevance.

Simulation fidelity is independent of presentation fidelity:

### Virtual flow/demand

Aggregate population where identity is unnecessary.

### Lightweight individual

Stable identity with cheap graph/path/position/speed/intent and enough occupancy/commitment state to materialize safely.

### Detailed nearby actor

Near-player/relevant local behavior: car-following, crossings, collision interaction, richer perception and detailed adapters.

### Gameplay-pinned actor

Actor/consequence involved in gameplay or strongly observed state. Ambient lifecycle cannot casually erase it.

Promotion/demotion changes fidelity, not identity/world truth.

## 11. Interest regions and natural lifecycle

Population is driven by world-space interest, not camera frustum.

Player is primary interest source. Gameplay events may add temporary regions. Map browsing may request cheap visual-interest data without moving the expensive simulation bubble.

Relevance may combine distance, velocity/prediction, same-road/crossing collision risk, gameplay pinning, recent observation and visibility/occlusion.

Logical activation extends beyond visible range so a U-turn/camera rotation cannot reveal population creation. At speed, predictive activation extends forward while retaining sufficient rear continuity.

Use natural sources/sinks where possible: network boundaries, buildings/entrances, parking, stations, stops, side streets, connecting paths and POIs.

Existence, simulation fidelity and visibility are separate.

Recently observed agents require retention/grace. Promotion reserves occupancy before a detailed body is created.

## 12. Presentation LOD and top-down first

Presentation consumes simulation/world state; it does not own it.

The prioritized driving presentation is a real perspective/tilted top-down camera over the true 3D world.

Initial camera tuning target is roughly 60-100 m above the player vehicle, around 75 m baseline, showing roughly one to two city blocks. Height, tilt, FOV, look-ahead, smoothing and offset are configurable/tunable rather than architectural constants.

The vehicle may sit below image center so more route/road is visible ahead. Camera follow can rotate smoothly with vehicle heading and use bounded speed look-ahead/zoom without pumping.

Camera height follows local player/surface elevation rather than absolute world Y and smooths terrain noise.

Future Chase/Driver/hood cameras are presentation adapters over the same running state and must not require resetting route, traffic, player or population.

## 13. Camera/view vs. player control

Keep separate:

```text
world/gameplay state
player control state
camera/view state
```

Manual Drive is a control mode. GPS Auto Drive is a control mode. Neither is a camera mode.

The player vehicle is one persistent gameplay-pinned identity across Map/top-down/future cameras, Manual/GPS, teleport and floating origin.

Input contexts have one owner at a time so map movement and vehicle steering cannot both consume the same action accidentally.

## 14. Named teleport anchors

Provide named development/gameplay anchors such as Lund, Malmö and Stockholm as data-driven world anchors rather than fixed raw XYZ.

Resolution flow:

```text
named anchor
 -> valid authoritative road
 -> valid lane
 -> legal direction
 -> correct 3D layer/elevation
 -> safe unoccupied pose
 -> atomic player/world relocation
 -> surrounding world activation
 -> camera focus/reacquire
```

If the preferred pose is blocked, choose a deterministic nearby safe placement.

Teleport must never create an intermediate frame where camera, physics and population disagree on old/new position.

Teleport is not GPS recovery and Auto Drive must never invoke debug vehicle recovery.

Lund/Malmö/Stockholm are permanent real-data smoke/regression fixtures.

## 15. Traffic world semantics

Sweden defaults to right-hand traffic through data/policy, not a hardcoded visual offset.

Traffic consumes authoritative lane semantics: lane count/direction/access, one-way, turn restrictions, lane continuation, merges/splits, road class and boundary facts.

Known world truth wins over heuristic behavior. Missing/ambiguous data uses deterministic conservative fallback.

Keep global route planning, lane/maneuver planning and local driving separate.

No spontaneous lane changes/U-turns. If the correct turn lane cannot be reached safely, miss the turn and reroute.

Queues emerge from following, signals and blockage. Green does not imply entry when downstream space is unavailable.

## 16. GPS Auto Drive

GPS Auto Drive operates the player's actual physical vehicle through the same world and VehicleDynamics/physics as Manual Drive.

```text
GPS destination/route
 -> route intent/version
 -> lane/maneuver planner
 -> driver profile/policy
 -> throttle/brake/steer/gear requests
 -> VehicleDynamics/physics
 -> actual vehicle motion
```

Core invariants:

> **GPS Auto Drive may plan better, but it may never cheat world, routing, traffic, occupancy or physics truth.**

> **Auto Drive may never do anything that a physical driver of the same car could not do with throttle, brake, steering and gear.**

No direct transform motion, teleport, collision ghosting, impossible lane change, instant U-turn or stale impossible shortcut.

Physical feasibility outranks route obedience. Missed turns/exits are valid; continue safely and reroute.

New destination while driving updates route intent atomically without reset. Route versions prevent stale async reroutes from overwriting newer user intent.

Destination and current active route are separate state. Temporary route invalidity does not erase destination.

## 17. Driver profiles

GPS Auto Drive exposes data-driven profiles over one implementation:

- Normal
- Aggressive
- Maniac

Profiles may vary desired speed, acceleration/braking intent, following gap, reaction latency, gap acceptance, lane-change willingness and overtaking willingness.

They do not alter grip, brake capability, engine power, vehicle dimensions or other physical truth.

Profile changes during driving affect future decisions continuously without resetting the vehicle. Safety-critical committed maneuvers complete according to state before profile preference can reverse them.

Future explicit illegal/forced driving is a separate policy/intent layer and must not be implemented by redefining Maniac as physically/rules-ignorant.

## 18. Manual/GPS handover

Control transfer is explicit state, not a camera side effect.

Conceptually:

```text
GPS -> MANUAL_REQUESTED -> MANUAL
MANUAL -> GPS_ACQUIRING -> GPS
```

A Manual request transfers immediately when stable enough. If the car is in a critical turn, lane change, roundabout, intersection or evasive maneuver, AI may complete the critical safe portion or brake to a safe stop first.

No arbitrary fixed delay.

Emergency manual takeover must remain available so the player cannot become trapped in automation; the player then accepts the physical consequence of immediate transfer.

GPS acquisition starts from the vehicle's actual speed/steering/pose and stabilizes naturally rather than snapping.

## 19. Driver state, failure and no-progress watchdog

Explicit states may include:

- NO_ROUTE
- REROUTING
- WORLD_DATA_WAIT
- BLOCKED
- SAFE_STOP
- COMPLETE
- COLLISION / ASSESSING
- MANUAL_REQUESTED / GPS_ACQUIRING

Unknown or contradictory world/lane truth may result in a controlled safe stop; it must not produce undefined driving.

A no-progress watchdog distinguishes legitimate queue/red light/blockage/deadlock from routing/AI failure and may request legitimate reroute/recovery policy. It may never teleport or ghost the vehicle.

Backwards driving is an explicit low-speed maneuver/recovery state, not a generic routing shortcut.

After collision, AI assesses whether continuation is physically/safely valid before resuming route.

## 20. Driver Activity / Intent Feed

Autonomous behavior exposes structured production events/state for intent, reason, action and result.

Examples of rendered text may include:

- Following route toward Malmö
- Preparing for upcoming right turn
- Waiting for safe gap
- Changing lane
- Lane change aborted - gap closed
- Waiting at red light
- Route changed - evaluating new route
- Continuing ahead - safe U-turn unavailable
- Unable to proceed safely - waiting

Core/domain emits structured reason/action data; presentation translates it to text.

The same source feeds gameplay UI, detailed debug/history, deterministic replay and tests.

Every autonomous action that physically affects the player car should be traceable:

```text
route/version -> decision/reason -> requested driver input -> actual vehicle response
```

AI knowledge, plan, attempted action and actual result must remain distinguishable.

## 21. Vehicle telemetry

Debug telemetry comes from real VehicleState/VehicleDynamics/physics, not presentation approximation.

At minimum expose as applicable:

- speed
- actual acceleration/deceleration
- requested brake/throttle
- requested steering
- actual steering
- longitudinal G
- lateral G
- total G

Requested driver command and actual vehicle response remain separate. This allows weather, grip, damage and surface conditions later without changing AI ownership.

## 22. UI/debug rules

Gameplay controls/status have priority. Debug adapts around them.

Hard rules:

- no overlay may obscure another interactive overlay;
- new debug information is consolidated before allocating new screen area;
- debug panels are collapsible/hideable, preferably with compact +/-/chevron controls;
- gameplay UI and debug are separate responsibilities;
- layout ownership reserves safe regions rather than each panel positioning itself freely;
- representative viewport/UI-scale no-overlap constraints are automated where practical.

Gameplay UI should always be able to communicate controller (MANUAL/GPS), selected profile, route state and handover state without requiring debug.

## 23. Pedestrians

Pedestrians prefer sidewalk -> footway -> pedestrian area -> crossing. Roadside fallback is conservative and motorways are excluded for ordinary walking.

Pedestrian state may include path progress, destination, group/cohort, idle/wait reason, crossing state and gameplay relevance.

Crossing commitment is sticky through LOD until safely complete or explicit recovery applies.

Pedestrian infrastructure presentation derives from the same authoritative world facts used by AI.

Pedestrian bridges/tunnels/crossings use the same 3D layer/surface truth as vehicles and terrain.

## 24. Gameplay consequences and physics

Ambient lifecycle and gameplay lifecycle are separate.

Collisions, chases, interactions, injuries, blockages and recently observed actors can pin state so ambient LOD cannot erase it.

A player road blockage may be abstracted at distance but cannot disappear because traffic was dematerialized.

Collision truth is separate from render geometry/visibility. Active-gameplay collision must remain physically conservative enough to prevent impossible pass-through.

Physics uses the same floating-origin and 3D surface/layer facts as the rest of the world.

Physical materials belong to world/gameplay collision contracts and remain ready for future ballistics/material response without weapon-specific render hacks.

## 25. Performance, memory and graceful degradation

The system is designed around bounded expensive work.

Use where appropriate:

- pooling/instancing
- spatial indexes/buckets
- time slicing
- per-fidelity update rates
- hard caps on detailed actors
- bounded caches/pools/memory
- chunked collision lifecycle
- frustum/occlusion for presentation only
- cheap aggregate flow for distant population
- build/runtime streaming

Do not run full SceneTree nodes, full physics, skeleton animation or detailed AI for Sweden-wide population.

When budgets are exceeded, degrade distant update frequency/density/proxy fidelity/render range first and protect observed/gameplay-relevant state.

Measure p95/p99 frametime, not only average FPS.

Offline world build additionally measures build wall-clock, stage timings, memory/temporary disk where practical, artifact size and warm-cache behavior.

Stress/soak tests protect bounded node/cache/state/collision growth and promotion storms.

## 26. Determinism and time

Critical simulation behavior is derived from explicit world/agent/scenario state and deterministic seed/version inputs.

Equivalent state should not change semantic decisions merely because rendering ran at 30, 60 or 120 FPS.

WorldClock/simulation time is separate from wall-clock time. Pause/resume does not secretly advance driver/simulation decisions unless explicitly owned by the simulation contract.

Stability/hysteresis prevents frame-to-frame lane, reroute, throttle/brake, steering or camera oscillation.

## 27. Testing strategy

### Portable/core

Prove world semantics, build inference, identity/LOD state, route/lane/driver policy, handover state, deterministic replay and budget accounting without Godot where possible.

### Headless Godot

Prove adapters/geometry/collision/lifecycle/input/UI-layout state that actually requires engine integration.

### Real-data

Use production Sweden data for integration risks that synthetic fixtures hide.

Permanent real-data corpus should include Lund, Malmö, Stockholm plus representative:

- multi-level interchange
- bridge over road/water
- tunnel
- steep road
- railway grade separation
- dense urban intersection

### Stress/soak/performance

Protect bounded memory/cache/node/collision/state growth, promotion rate, streaming churn and stable frame/work budgets.

### Manual

Reserve for camera feel, vehicle feel, visual realism/readability, animation/audio/aesthetics and holistic UX after objective checks are green.

## 28. Program-level regression scenarios

At minimum the completed program should automatically protect:

- identity continuity through virtual/lightweight/detailed/pinned transitions
- camera/view changes without world/player reset
- top-down -> future camera transition contract without control-state reset
- rapid 180-degree camera turn/U-turn without population popping
- player teleport into dense traffic without overlap/materialization collision
- Lund/Malmö/Stockholm teleport to correct road/lane/direction/layer/elevation
- long traversal with bounded node/cache/state/collision growth
- terrain tile/LOD seam continuity and stable authoritative height
- road mesh/collision/lane pose agreement within tolerance
- bridge vehicle above road below with no false occupancy/collision
- tunnel vehicle below surface/other road with no false connection
- bridge/tunnel approach continuity and bounded grade
- floating-origin equivalence for world surface/collision/vehicle pose
- building foundation adaptation without unacceptable float/sink
- one-way motorway data boundary vs. true dead end
- multilane/merge/missed-exit correctness
- blocked road persistent queue
- signal/stop-line compliance
- pedestrian crossing continuity
- deterministic replay across representative frame rates
- render culling/LOD not changing gameplay collision
- GPS Auto Drive never invoking teleport/debug recovery
- contradictory world state causing safe stop rather than undefined driving
- autonomous action trace from route -> reason -> requested input -> actual response
- gameplay/debug overlay no-overlap at representative viewport/UI scales

## 29. Revised delivery DAG

This DAG updates the original #286 plan. Existing issues remain owners where their scope still fits; new issues only fill missing boundaries.

### Wave A - architecture freeze

- #312 top-down-first 3D/world-build/control architecture formalization

### Wave B - independent foundations after #312

- #313 normalized source/build contract, provenance/versioning and deterministic world artifacts
- #288 portable population state, interest regions and bounded simulation LOD
- #289 authoritative mobility semantics for lanes/pedestrians/boundaries
- #290 gameplay physics/collision truth
- #301 deterministic shared CI scenario library

Existing #220 remains the source-cache/runtime-footprint performance owner and must compose with #313 rather than be replaced.

### Wave C - authoritative vertical world

- #314 real elevation/terrain world-surface pipeline
- #315 engineered 3D road/structure/lane surface solver for roads/bridges/tunnels/rail/ped grade separation
- #320 terrain-adapted structures/collision integration

Existing #249 connected road surfaces must consume #315 vertical/structure truth rather than become a second height owner. Existing #243 land-cover remains a source/build input for later terrain/vegetation presentation, not elevation truth.

### Wave D - top-down playable control foundation

- #316 camera-independent player control state + production top-down driving camera
- #319 named Lund/Malmö/Stockholm safe 3D teleport anchors/regressions
- #291 production ambient traffic with top-down-first presentation
- #292 production pedestrians with top-down-first presentation
- #96 traffic-signal production presentation/harness

Map remains supported as a presentation/view, but ground-level Drive presentation is not a prerequisite for living-world correctness.

### Wave E - traffic/player autonomous driving correctness

- #303 route/lane/local-driving state separation
- #293 lane/flow/queue/boundary correctness
- #95 signal/stop-line compliance
- #304 shared intersection conflict/occupancy
- #306 lightweight occupancy/gap continuity
- #317 GPS Auto Drive, driver profiles, route versioning, safe handover and no-cheat vehicle control
- #318 Driver Activity Feed + control/route UI + consolidated vehicle telemetry/debug layout

### Wave F - pedestrian/world integration

- #294 walkable infrastructure/crossings
- #295 POI/parking/stopping and natural sources/sinks
- #296 persistent gameplay consequences/blockages
- #302 observation retention/materialization
- #305 teleport/extreme-speed population activation
- #308 pedestrian cohort continuity
- #309 traffic sources/sinks
- #310 pedestrian sources/sinks

### Wave G - performance/realism extension

- #300 living-world performance telemetry/regression budgets
- #297 advanced realism tracker
- #298 density/profiles/advanced ambient behavior
- #307 sight/relevance
- #299 future ballistics/material interaction

Dependencies are refined in individual issues. Agents must use merged `main` dependencies by default rather than stacked branch chains.

## 30. Rules for every implementation child

Each child must:

- use isolated `issue/<number>-<short-name>` work;
- define one clear owner and smallest explicit API;
- ask `Could this run without Godot?` and keep it portable when yes;
- consume authoritative world/routing/elevation data rather than inventing a local truth;
- define an objective `MUST PASS` manifest before implementation;
- include deterministic/core tests first where applicable;
- add headless Godot only for real engine integration;
- add real-data fixtures where synthetic data could hide integration problems;
- define performance/memory/cache/node/collision/build-work bounds where scale is involved;
- add stress/soak coverage for unbounded-growth risks;
- expose enough telemetry/provenance to diagnose failures without private-state reach-through;
- never use manual playtesting to replace objective assertions;
- reserve manual checks for feel/aesthetics/holistic UX;
- merge only after required objective validation is green and current-main integration relevance is rechecked.

## 31. Completion

The umbrella is complete when the required DAG deliveries are merged or explicitly satisfied without duplicate implementation; all non-negotiable requirements have automated protection where objectively verifiable; real-Sweden vertical/world/traffic regressions are stable; runtime/build memory and work are bounded/profiled; and richer art, cameras, animation, audio, police, weather and future ballistics can be added without replacing world truth, control, simulation or data-build architecture.
