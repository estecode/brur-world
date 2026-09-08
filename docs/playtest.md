# One-click manual playtests

`brur-world` owns manual playtest preparation through `tools/playtest.sh`. Safe Command Links only validates the approved command and target before dispatching it.

Currently supported targets:

- `game` — full game scene
- `gps` — isolated GPS harness
- `driving` — full production world through the driving harness, including the player vehicle and GPS follow toggle

Future targets should be added only when the corresponding production subsystem/harness actually exists.

## Local one-time setup

Map the repository and approve the target allowlist from the Safe Command Links checkout:

```bash
bash allow-repo.sh estecode/brur-world /absolute/path/to/brur-world
bash allow-project.sh /absolute/path/to/brur-world playtest . /bin/bash tools/playtest.sh --param target:enum=game,gps,driving
```

Safe Command Links must include enum project-parameter support. The signed local approval allows only `game`, `gps` or `driving`; arbitrary paths, scenes, shell arguments, and unknown target values are rejected before `tools/playtest.sh` runs.

If generated Sweden data already exists and is compatible, no source PBF setting is needed. If a required world/routing artifact is missing or known stale, set the external source once in the environment used by Safe Command Links:

```bash
export BRUR_WORLD_PBF=/path/to/sweden.osm.pbf
```

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

In the driving view, W/S/A/D + Space control the player car manually. After calculating a GPS route, `Follow route` hands control intent to the route follower for the same vehicle; any manual driving input disengages follow without replacing or resetting the car.

`playtest` always runs the current mapped checkout. It is intentionally separate from `pr-check`, which verifies an exact isolated pull-request revision.
