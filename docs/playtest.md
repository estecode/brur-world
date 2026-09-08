# One-click manual playtests

`brur-world` owns manual playtest preparation through `tools/playtest.sh`. Safe Command Links only validates the approved command and target before dispatching it.

Currently supported targets:

- `game` — full game scene
- `gps` — isolated GPS harness
- `driving` — isolated connected street/ring-road fixture using the production player vehicle, route follower and camera

Future targets should be added only when the corresponding production subsystem/harness actually exists.

## Local one-time setup

Map the repository and approve the target allowlist from the Safe Command Links checkout:

```bash
bash allow-repo.sh estecode/brur-world /absolute/path/to/brur-world
bash allow-project.sh /absolute/path/to/brur-world playtest . /bin/bash tools/playtest.sh --param target:enum=game,gps,driving
```

Safe Command Links must include enum project-parameter support. The signed local approval allows only `game`, `gps` or `driving`; arbitrary paths, scenes, shell arguments, and unknown target values are rejected before `tools/playtest.sh` runs.

If generated Sweden data already exists and is compatible, no source PBF setting is needed for `game`/`gps`. If a required world/routing artifact is missing or known stale, set the external source once in the environment used by Safe Command Links:

```bash
export BRUR_WORLD_PBF=/path/to/sweden.osm.pbf
```

The `driving` target deliberately needs neither Sweden data nor native GPS. Its small road network is a fixture at the world boundary while all vehicle/control/camera behavior under test uses production modules.

The PBF remains external and must not be committed. `tools/playtest.sh` reuses compatible `world_data` and native binaries, rebuilds only the prerequisites required by the selected target, and starts Godot only after preparation succeeds.

The default macOS Godot executable is:

```text
/Applications/Godot.app/Contents/MacOS/Godot
```

`BRUR_GODOT` may point to another executable when needed.

## One-click links

Game:

```text
http://127.0.0.1:17384/safecommand/project?repo=estecode/brur-world&command=playtest&target=game
```

GPS harness:

```text
http://127.0.0.1:17384/safecommand/project?repo=estecode/brur-world&command=playtest&target=gps
```

Driving harness:

```text
http://127.0.0.1:17384/safecommand/project?repo=estecode/brur-world&command=playtest&target=driving
```

The driving harness is a compact connected rectangular road grid: streets/avenues plus an outer ring road. W/S/A/D + Space control the production player car manually. `Follow route` hands control to the production route follower on a fixed ring-road route; any manual driving input disengages route follow without replacing/resetting the car. `Follow car` independently controls camera centering, and `Reset car` returns the same vehicle to the fixture start.

`playtest` always runs the current mapped checkout. It is intentionally separate from `pr-check`, which verifies an exact isolated pull-request revision.
