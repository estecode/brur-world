# brur-world

Minimal Godot 4 proof of concept for building a playable Sweden world from an external OSM PBF.

## Project rules

This is a standalone project. Do not reuse or depend on architecture or code from Syndicate. The current local PBF path happens to live under a Syndicate directory, but it is external source data only.

Keep every implementation as small as possible while preserving a clean architecture:

- Prefer small, well-defined objects/modules with one clear responsibility.
- Keep data, decisions, simulation and rendering separate where practical.
- Avoid large controllers, monster files and long chains of special-case `if` statements.
- Add interfaces/states/strategies only when they make an actual implemented feature simpler.
- Gameplay logic should not depend unnecessarily on Godot scene-tree state or rendering.
- Important source files should briefly explain in plain English what they do and their dependencies.
- Prefer real units for simulation data (metres, seconds, m/s, litres, kWh, etc.). Rendering coordinates are not automatically simulation truth.
- Use credible web sources, open-source projects, technical references or scientific papers when research materially improves realism. Keep the resulting implementation minimal.

## Development workflow

Develop the game as a sequence of small **vertical slices** rather than building large technical subsystems in isolation. Each slice should end in a working, demonstrable piece of gameplay.

Example progression:

`routing graph -> routing benchmark -> click-to-road GPS -> route following -> normal driving -> aggressive/maniac driving -> lightweight traffic -> police patrol -> offence detection -> pursuit`

Use GitHub issues as small work orders. An issue should have a clear goal, scope, dependencies where relevant, explicit out-of-scope boundaries and acceptance criteria. Keep the backlog prioritized by what is needed for the next playable step.

For each slice:

1. Define the smallest behavior that proves the feature.
2. Implement the minimum clean solution.
3. Add automatic tests while implementing the feature, not afterward.
4. Add benchmarks/performance counters early for systems where latency or scale matters, especially routing, streaming and traffic.
5. Verify functional correctness through tests before relying on visual inspection.
6. Use manual play-testing primarily for feel, presentation and visual quality.
7. Keep the project in a working state when the slice is complete.

Avoid speculative frameworks and premature generalization. Do not spend weeks building a complete subsystem before it produces gameplay. Extend or replace simple implementations only when a real requirement or measurement justifies it.

Prefer a lightweight project process: prioritized backlog, well-defined issues, short implementation cycles, automated tests and regular playable milestones. Heavy project-management ceremony is not a goal.

Use feature branches for substantial work and keep the stable branch usable. Preserve known-good snapshots/checkpoints before risky architectural changes when useful.

### Definition of done

A gameplay issue is complete when:

- its acceptance criteria pass;
- core functional behavior is covered by automatic reproducible tests;
- the implementation remains small, understandable and correctly separated by responsibility;
- relevant performance is measured and acceptable for the current gameplay scale;
- functional bugs discovered during development have regression tests where practical;
- the feature can be demonstrated in the game when it has a visible/gameplay component.

A feature is not considered complete merely because it appears to work during one manual play session.

## Automated testing rule

**A new gameplay feature is not complete until its core logic has automatic, reproducible tests.**

The target is that functional correctness can be verified without manual play-testing. Design gameplay systems so they can be exercised headlessly with explicit inputs and outputs instead of requiring a running rendered scene.

Examples:

- routing uses small synthetic road graphs to test one-way roads, speed limits, access, disconnected routes, bridges/tunnels/layers and path cost;
- route following can be tested with fixed routes, positions, speeds and look-ahead geometry;
- driving policies can be tested against known speed limits, curves and vehicle limits;
- acceleration, braking, fuel/energy use and tire wear use deterministic calculations with fixed test cases;
- lightweight traffic can be advanced through road edges without rendering;
- police observations use controlled timestamps and synthetic observations;
- pursuit/intercept logic uses deterministic road scenarios;
- police tactics are testable as state transitions/actions rather than requiring visual inspection;
- randomness that affects functional tests must be seedable/reproducible.

Godot nodes should generally act as thin adapters around testable gameplay logic rather than owning all logic directly in `_process()`/`_physics_process()`.

Manual testing is primarily for things that are inherently perceptual: visual quality, camera feel, animation, audio, final driving feel and similar presentation. State and decision logic behind those features should still be automatically tested where possible.

When fixing a functional bug, add or update a regression test that reproduces the bug whenever practical.

## Goal

Prove the world/gameplay stack incrementally with as little code as possible. The current world pipeline starts from OSM PBF, produces portable runtime data offline, and renders/streams it in Godot 4. Routing, vehicles, traffic and police systems are added as separate small systems as gameplay requires them.

Godot does not parse OSM PBF at runtime. Generated world data is intentionally ignored by Git.

## Build Sweden

The helper script already defaults to the local source used for this POC:

```bash
./build_sweden.sh
```

Equivalent explicit command:

```bash
./build_sweden.sh /Users/stefanlind/Dropbox/Code/syndicate/data/sweden-260824.osm.pbf
```

The PBF is external input and is not part of this repository.

## Run

Open this repository folder in **Godot 4**, then press **Run Project**.

Controls:

- Mouse wheel: zoom
- Middle or right mouse drag: pan
- WASD / arrow keys: pan

## POC road LODs

- LOD 0: motorway + trunk, thinned to roughly 400 m point spacing
- LOD 1: + primary + secondary, thinned to roughly 100 m spacing
- LOD 2: + tertiary/residential/unclassified/service, source geometry

Tiles are 32 km square. Runtime loads tiles around the current camera view and swaps LOD based on camera distance.
