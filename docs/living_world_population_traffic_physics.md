# Living world: population, traffic, pedestrians and gameplay physics

Status: canonical systemspec under umbrella issue #286. Root `ARCHITECTURE.md` remains the canonical architecture contract.

## 1. Purpose

BRUR should feel like a continuous living world rather than a collection of camera-relative NPC spawners. Vehicles and people are world entities with one logical identity and state. Map, Drive, simulation LOD and presentation LOD are views/fidelity levels of that same truth.

The system must be realistic where the player can observe or affect it, aggressively bounded where exact simulation is unnecessary, deterministic enough to reproduce failures, and portable enough that performance-critical domain logic can move between GDScript and native C++ without rewriting consumers.

Project rule:

> **Correctness is automated. Feel is playtested.**

## 2. Ten non-negotiable requirements

1. **No observable pop-in/pop-out.** Visible or recently observed agents must not be casually created, removed, teleported or identity-swapped.
2. **No duplicated world truth between Map, Drive or LOD.** One logical identity/state exists per agent; views and fidelity levels adapt it.
3. **Population must never cause unbounded frametime, node-count, cache or memory growth.** Work and storage are explicitly bounded and degrade gracefully.
4. **No machine-verifiable invariant may depend on manual testing.** Anything objectively assertable must be covered by deterministic/core, headless Godot or real-data tests where reasonably possible.
5. **Gameplay consequences must never be erased by LOD/population.** Queues, collisions, blockages, interactions, chases and observed identities persist appropriately.
6. **NPC decisions must never contradict known world/routing truth.** One-way, lane endings, turn restrictions, access, pedestrian-only topology, boundaries and crossings are authoritative; uncertain data uses conservative deterministic fallback.
7. **Performance degradation may reduce fidelity, never world truth or gameplay outcomes.** Lower update rate, proxy density or render range is allowed; teleporting/removing meaningful state is not.
8. **Same input/state must produce reproducible results.** Seed + world state + agent state must be sufficient to reproduce critical scenarios.
9. **Gameplay-critical physical interactions use explicit physics/collision truth independent of presentation and LOD.** Render meshes are not authoritative collision truth.
10. **Physics simplification may reduce fidelity for performance but must not permit physically impossible gameplay outcomes inside the active gameplay region.**

These requirements are program-level invariants. Child issues own concrete implementation and regression coverage for the parts they touch.

## 3. Architecture and ownership

The dependency direction remains:

```text
core/domain -> adapter -> presentation
```

For the living world the intended flow is:

```text
authoritative world/routing facts
  -> portable population / behavior / physics-domain state
  -> simulation fidelity
       virtual flow
       lightweight individual
       detailed nearby actor
       gameplay-pinned actor
  -> runtime/Godot adapters
  -> Map presentation / Drive presentation
  -> replaceable art, animation, audio and effects
```

### Portability by default

Domain, simulation, policy and decision logic that does not intrinsically require Godot must remain portable and free of SceneTree, rendering and UI dependencies.

Ask for every new rule: **Could this logic run without Godot?** If yes, it normally belongs in portable core/domain state or policy.

Godot should primarily provide:

- composition and lifecycle adapters
- engine input
- runtime collision-world queries
- scene/node integration
- rendering and presentation
- interactive harness composition

Fast deterministic core tests should prove rules and state transitions before headless Godot tests prove adapter/runtime integration.

### World truth

World/routing owns road, lane, turn, access, crossing, pedestrian-infrastructure and boundary facts. Traffic and pedestrians must not build their own competing road graphs or coordinate formulas.

Presentation must never become the owner of gameplay truth. A rendered traffic light, sidewalk mesh, car mesh or building facade cannot be the authority for traffic permission, walkability or collision semantics.

## 4. Agent identity and simulation fidelity

Every individual agent that exists logically has a stable identity and enough state to preserve continuity. The exact state differs by vehicle/person but may include world position, directed edge/path, lane, progress, heading, speed, destination, current behavior, committed maneuver/crossing state, recently-seen state and gameplay relevance.

Simulation fidelity is separate from presentation fidelity:

### Virtual flow / demand

Aggregate population or flow where individual identity is unnecessary. This represents potentially very large populations cheaply.

### Lightweight individual

A stable individual identity with minimal graph/path state, position/progress, direction, speed, destination/intent and enough occupancy/commitment state to promote safely.

### Detailed nearby actor

Near-player or otherwise relevant local behavior: car-following, crossings, collision interaction, detailed vehicle/person adapters and richer perception.

### Gameplay-pinned actor

An actor involved in gameplay or a persistent observed consequence. Collisions, chases, interactions, blockages, injuries, arrests or other committed consequences can pin an actor so ambient lifecycle cannot casually erase it.

Promotion/demotion changes fidelity, not identity or world truth.

## 5. Interest regions and relevance

Population simulation is driven by world-space interest regions, not merely the current camera frustum.

The player is the primary interest source. Temporary gameplay events may create additional regions. Map browsing may create cheap visual-interest regions without moving the expensive full-simulation bubble.

Relevance combines factors such as:

- distance
- player velocity and travel direction
- predicted near-future interaction
- same-road / same-crossing / collision risk
- gameplay pinning
- recent observation
- visibility/occlusion where useful

The active logical bubble is larger than the visual range so a U-turn or fast camera rotation does not reveal population creation. At speed, activation should extend farther ahead while preserving enough rear continuity.

LOD thresholds must use hysteresis to prevent thrashing. Exact distances are configuration/profile data and should be tuned from profiling, not treated as architectural constants.

## 6. Natural population lifecycle

Existence, simulation fidelity and visibility are separate concepts.

Prefer natural sources/sinks:

- road/network ingress and egress
- building entrances
- parking facilities and driveways
- stations and bus stops
- side streets / connecting paths
- POIs and pedestrian areas

Off-screen or occluded materialization is a fallback when a natural source cannot be represented directly. It must still preserve plausible road/path position and occupancy.

Despawn/dematerialization should require sufficient distance, unseen time, relevance decay and grace. Recently observed agents are deliberately harder to forget.

Once an agent has been observed or becomes gameplay-relevant, identity/history cannot be casually rewritten merely to satisfy density.

Promotion to detailed representation reserves physical space first. Lightweight traffic must retain enough occupancy/gap state that multiple vehicles cannot promote into overlapping bodies.

## 7. Presentation LOD

Presentation consumes world/simulation state but does not own it.

### Drive

- near: full or highest available 3D representation in physical scale
- middle: cheap proxy / low-cost animation and collision representation where appropriate
- far: instanced proxy or no individual rendering

### Map

- close: shared/simplified 3D proxy or readable representation
- medium: cheap marker/instance
- far: density/flow aggregation or hidden individuals

Map readability may use presentation scale that differs from Drive physical scale, but identity/state is shared.

Presentation LOD should consider distance, projected size, relevance, frustum/occlusion and budget. Simulation LOD is a separate decision.

## 8. Performance and graceful degradation

The system is designed around bounded expensive work.

Use, where appropriate:

- pooling
- MultiMesh/instancing
- spatial buckets/indexes
- time slicing
- per-fidelity update rates
- hard caps on detailed actors
- bounded caches and memory budgets
- batch-friendly material variation
- frustum/occlusion culling
- per-frame work budgets
- cheap aggregate flow instead of full distant actors

Do not run full Godot nodes, full physics, skeleton animation or detailed AI for all Sweden-wide agents.

When budgets are exceeded, degrade in this order conceptually:

1. lower distant update frequency
2. reduce distant individual density
3. reduce proxy fidelity
4. reduce distant render range
5. protect observed/gameplay-relevant actors last

Degradation may change fidelity. It must not change known world truth or erase gameplay consequences.

Optimize stable frametime, including p95/p99 behavior, not only average FPS.

## 9. Telemetry

Expose explicit instrumentation through production APIs/adapters so profiling does not require scene-tree spelunking.

Useful counters include:

- virtual/lightweight/detailed/pinned vehicle counts
- virtual/lightweight/detailed/pinned pedestrian counts
- promotions/demotions
- materialization attempts/rejections
- source/sink admission/rejection
- cache/pool/node sizes
- work performed by fidelity level
- update-rate distribution
- queue/crowd abstraction counts
- collision resource counts

Headless stress/soak tests should guard architectural bounds. Real hardware/runtime profiling determines final frametime tuning.

## 10. Traffic world semantics

Sweden defaults to right-hand traffic, but traffic side is policy/data and should not be baked in as a visual offset.

Traffic consumes an explicit lane model where world/routing facts support it. Relevant facts may include lane count/direction, access, one-way, turn restrictions, merges/splits, lane continuation and road class.

Fallback from incomplete data must be deterministic and conservative.

### Lane behavior

A vehicle may track:

- current lane
- desired lane
- lane-change/maneuver reason
- route lookahead
- desired speed
- following gap
- braking/waiting state
- commitment/hysteresis

One-way roads with multiple lanes may use all valid lanes. Normal traffic tends to keep right when appropriate, while left lanes may be used for speed, overtaking, queue distribution, upcoming turns/exits or merge needs.

No spontaneous lane changes or U-turns.

If a vehicle cannot safely reach the correct lane for a turn, it should miss the turn and reroute rather than cut across traffic.

### Route planning, lane planning and local driving

Keep three responsibilities separate:

1. global route planning — where the vehicle should go
2. lane/maneuver planning — how to prepare for route topology
3. local driving — acceleration, braking, spacing and control intent

Traffic policy produces intent. Shared Vehicle/VehicleDynamics owns vehicle motion/dynamics.

### Local driving

First production realism should prioritize:

- lane keeping
- safe following distance
- natural acceleration/deceleration
- comfortable braking
- curve-aware safe speed
- stop/yield/signal compliance
- queue behavior
- merge behavior
- conservative collision avoidance/recovery

Seeded variation may later adjust desired speed, acceleration, following distance, caution and reaction delay while remaining reproducible.

### Occupancy and queues

Lightweight traffic must retain cheap lane/segment occupancy or capacity state sufficient to avoid overlap on promotion.

Queues should emerge from car-following, signals, downstream blockage and other real constraints. Far portions of long queues may be abstracted as queue length/flow state and materialized progressively near the player, but the queue consequence cannot disappear because fidelity changes.

Do not enter an intersection merely because the signal is green if usable downstream space is unavailable.

## 11. Traffic signals and intersections

Existing #91/#92/#93/#94 remain the traffic-signal/intersection foundation. #95 owns vehicle stop-line/signal compliance. #96 owns production signal presentation and the traffic harness.

The living-world program consumes those systems rather than replacing them.

Intersection conflict/occupancy facts should be shareable by vehicles, pedestrians and signal-aware policy through explicit APIs. Presentation never owns timing or permission state.

A vehicle legitimately committed to an intersection should clear it rather than freeze when a signal phase changes behind it.

## 12. World boundaries, road ends and special transitions

Traffic must distinguish technical data/streaming boundaries from real road topology.

Useful conceptual classes include:

- `VALID_CONTINUATION`
- `VALID_EXIT`
- `LEGAL_TURNAROUND`
- `RESTRICTED`
- `TEMP_BLOCKED`
- `DATA_BOUNDARY`
- `TRUE_DEAD_END`
- `SPECIAL_TRANSITION`

Names may evolve, but world/routing owns the distinction.

Examples:

- one-way motorway approaching a known data boundary: do not route ambient traffic beyond the last safe continuation/exit if no valid continuation exists
- Öresund-like cross-border continuation: technical data absence is not a physical dead end
- true two-way dead end: turn around only if legal and geometrically feasible for the vehicle profile
- missed motorway exit: continue/reroute; never brake, reverse or cross the gore illegally
- wrong-way player: player remains physically free to do it; NPC routing does not choose it and nearby traffic reacts conservatively
- roundabout: one-way loop semantics; missed exit can mean another lap
- ferry/special transition: explicit transition/queue behavior, not driving into water

Player control is never silently overridden to hide a world-data boundary.

## 13. POI, parking and stopping

A destination is not an exact coordinate at which a car must stop.

Vehicle destination resolution should seek plausible access such as:

- parking
- driveway
- legal curb/short-stop area
- side street
- service/rest area
- appropriate road exit or access point

If no valid stop exists, the vehicle passes or chooses a fallback. It must not stop irrationally in a motorway/through lane because a POI coordinate is nearby.

Distinguish states such as parked, short stop, queue, signal wait, bus/delivery stop and breakdown/blockage.

Parking has capacity/occupancy. Future chains may connect drive -> park -> Person exits -> walks to entrance without changing the underlying population architecture.

## 14. Pedestrians

Pedestrians strongly prefer:

```text
sidewalk -> footway -> pedestrian area -> crossing
```

Roadside fallback is allowed only where data is missing and the road context makes it plausible. Ordinary pedestrians must not use motorway carriageways as fallback.

Pedestrian state may include path progress, destination, group/cohort, idle/wait reason, crossing state and gameplay relevance.

Once a crossing begins, crossing state is sticky until it is safely completed or an explicit recovery rule applies. LOD transitions must preserve it.

Near traffic, pedestrians may use cheap safe-gap / signal / danger decisions. Expensive collision/visibility checks should only run for potentially interacting agents.

Groups/pairs may be aggregated far away and split into individuals near the player, while preserving cohort identity and protecting recently observed members from arbitrary rewrite.

Idle/waiting may occur at crossings, bus stops, entrances, parked cars and POIs.

## 15. Pedestrian infrastructure presentation

If pedestrian logic uses a sidewalk/crossing/path, Drive should be capable of showing the relevant infrastructure with at least simple production geometry/materials.

AI and rendering consume the same authoritative world facts. Rendering does not infer a separate walkability graph.

## 16. Gameplay relevance and persistent consequences

Ambient lifecycle and gameplay lifecycle are separate.

An actor may become pinned or otherwise high-relevance because of:

- collision
- chase
- stop/arrest/interaction
- injury/damage
- active observation/following
- blockage involvement
- other explicit gameplay event

A player blocking a road for ten minutes must create a real persistent consequence. Nearby vehicles can be detailed/lightweight; farther queue state may be abstracted, but the system cannot solve the blockage by deleting and respawning traffic beyond it.

Temporary road/lane state such as blocked, slow or restricted should be represented explicitly so traffic/routing policy can wait or reroute conservatively.

## 17. Gameplay physics and collision truth

Gameplay collision truth is independent of visual presentation.

A render mesh being hidden, culled, replaced, simplified or unloaded for presentation must not remove collision that is required by active gameplay.

Static world collision and dynamic actor collision need explicit ownership and bounded lifecycle. Large-world collision should be chunked/simplified where useful, but active gameplay-range simplification must remain conservative.

Physics queries must use the same shared coordinate/floating-origin conversion rules as the rest of the world. Large absolute coordinates must not create a situation where rendering is correct but collision/raycast results drift.

### Physical materials

Collision facts should be able to expose material metadata sufficient for later gameplay such as:

- concrete
- glass
- wood
- metal
- soil/terrain
- vehicle body/glass where useful

The initial foundation does not need firearm penetration, but it must avoid architecture that makes later penetration/ricochet depend on render meshes or scene internals.

## 18. Future ballistics

Weapons/ballistics are a later consumer of gameplay physics truth.

Ordinary firearm projectiles do not require thousands of full `RigidBody3D` bullets. A deterministic swept-segment/raycast ballistic model can support travel time, drop and material interaction when appropriate.

Conceptually:

```text
weapon state
  -> ballistic projectile/query model
  -> gameplay physics query
  -> material/thickness response
  -> hit/damage result
  -> presentation/effects
```

Solid objects block shots by default. Penetration, if supported, must be explicit material/geometry policy rather than accidental pass-through.

A person behind a solid gameplay obstacle must remain protected even if the obstacle's render mesh is culled or replaced.

## 19. Determinism and debugging

Critical population/traffic/pedestrian behavior should be reproducible from stable inputs.

Use deterministic seeds derived from explicit world/agent/scenario inputs. Record enough state/events that a failure such as "vehicle X made an illegal maneuver at position Y" can be recreated in a focused test.

Do not let random cosmetic presentation drive domain behavior.

## 20. Testing strategy

Tests are layered by responsibility and cost.

### Portable/core tests

Use for:

- identity/state transitions
- LOD/relevance decisions
- deterministic replay
- lifecycle/source/sink policy
- lane/path/turn/boundary semantics
- traffic behavior intent
- pedestrian decisions
- occupancy/capacity
- material/physics-domain policy

### Headless Godot integration

Use for:

- scene wiring/adapters
- Map/Drive representation exclusivity
- transform/floating-origin integration
- promotion/demotion to real production nodes
- collision-world queries
- visibility/state contracts
- production harness integration

### Real-data integration

Use representative Sweden runtime data where synthetic fixtures could hide integration failures:

- dense urban roads
- motorway / interchange
- multi-lane one-way
- signalized intersection
- pedestrian crossing/infrastructure
- dead end and data-boundary continuation
- POI/parking access

### Stress/soak

Guard:

- bounded cache/state/node counts
- bounded detailed actors
- no long-run retained-state leak
- bounded promotion rate during rapid camera/U-turn behavior
- distant agents do not accidentally run detailed/full-rate simulation

### Manual playtesting

Reserved for feel/perception: traffic naturalness, animation quality, visual pop perception, camera/gameplay feel and holistic runtime experience.

Objective correctness belongs in automation.

## 21. Shared deterministic scenarios

The living-world program should converge on reusable scenario fixtures rather than each subsystem inventing test-only worlds.

Required synthetic scenarios include:

- one-way motorway ending at a data boundary
- true two-way dead end with legal turnaround
- two-lane one-way traffic using valid lanes
- merge 2 -> 1
- missed exit
- blocked road and persistent queue
- pedestrian crossing
- teleport into dense traffic
- rapid 180-degree observation/camera turn
- Map -> Drive -> Map
- long traversal through many population cells

Production modules consume these fixtures. Harness code must not implement alternate traffic/pedestrian rules.

## 22. Implementation DAG

Umbrella: #286.

### Wave 0

- #287 — canonical systemspec, architecture rules and execution contract

### Wave 1: foundations that can proceed in parallel after #287

- #288 — portable population state, interest regions and simulation LOD
- #289 — authoritative lane/pedestrian/boundary semantics
- #290 — gameplay physics/collision truth
- #301 — deterministic CI scenario library

Supporting focused foundation slices can proceed when their dependencies are ready:

- #300 — performance telemetry/regression budgets
- #302 — observation retention and occupancy-safe materialization
- #303 — route/lane/local-driving state separation
- #304 — shared intersection conflict/occupancy contract
- #305 — player-safe teleport/extreme-speed activation
- #306 — lightweight traffic occupancy/gap continuity
- #308 — pedestrian cohort continuity
- #309 — traffic flow sources at streamed boundaries
- #310 — pedestrian natural sources/sinks

### Wave 2: production population

- #291 — ambient traffic + seamless Map/Drive presentation
- #292 — pedestrian population + seamless Map/Drive presentation
- #96 — production traffic-signal presentation/harness remains independently ready from its existing prerequisites

### Wave 3: correctness

- #293 — lane/flow/queue/world-boundary traffic correctness
- #294 — pedestrian walkable-infrastructure/crossing correctness
- #95 — traffic signal/stop-line compliance, consuming completed #91 foundations and production traffic state

### Wave 4: world/gameplay integration

- #295 — POI/parking/stopping and natural sources/sinks
- #296 — persistent gameplay consequences/blockages across LOD

### Wave 5: advanced realism

- #297 — advanced-realism tracker
- #298 — density, richer profiles and advanced behavior tracker
- #307 — sight/relevance policy tracker
- #299 — future ballistics/material-interaction tracker

Dependencies should flow through merged `main`. Avoid stacked feature-branch chains by default.

## 23. Continuous-agent execution

GitHub is the work queue and source of truth. No extra orchestration service is required.

For one agent working continuously:

1. read `AGENTS.md`, `ARCHITECTURE.md`, this systemspec and the selected issue
2. verify no active competing branch/PR owns the issue
3. select an unblocked child whose prerequisites are merged to `main`
4. implement the smallest compliant slice
5. run the issue's `MUST PASS` manifest plus relevant regression suites
6. repair failures until green or a genuine human-only blocker exists
7. create/update PR with exact validation evidence and merge decision
8. when repository policy permits and the PR remains `MERGE`, merge after fail-closed refresh
9. continue to the next unblocked, unoccupied child

For several agents in parallel, choose children from separate ownership areas in the DAG and keep each issue isolated. Shared dependencies merge to `main` before downstream work is refreshed.

Every child issue should specify:

```text
Scope
Ownership/API boundary
Dependencies
Acceptance invariants
MUST PASS test manifest
Real-data/stress requirements where relevant
Done condition
```

Do not treat implementation as complete because code exists. It is complete when the defined objective evidence is green and no unresolved architecture contract remains.

## 24. Relationship to existing systems

This program extends rather than replaces completed foundations:

- #8 lightweight NPC traffic/promotion
- #18 generic Person
- #19 pedestrian population/walking foundation
- shared Vehicle/VehicleDynamics
- #91/#92/#93/#94 traffic-signal/intersection foundation
- #95 signal compliance
- #96 traffic-signal presentation/harness
- shared world/routing and coordinate ownership

If a child discovers that an existing subsystem already owns the required fact or state, extend/use that API instead of creating another source of truth.

## 25. Completion standard

The living-world program is in good shape when:

- the ten non-negotiable requirements have concrete automated protection where objectively verifiable
- traffic and pedestrians maintain identity/state through LOD and Map/Drive transitions
- lifecycle is natural enough that camera movement does not reveal population creation/removal
- known world/routing truth always constrains NPC decisions
- gameplay consequences survive fidelity changes
- active gameplay collision is independent of render LOD
- all expensive work and retained state are bounded and observable
- domain rules remain portable by default
- real-data integration proves the architecture on representative Swedish world data
- richer art, animation, audio and future ballistics can be added without replacing the core world/simulation ownership model
