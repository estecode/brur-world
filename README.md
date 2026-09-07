# brur-world

Minimal Godot 4 proof of concept for streaming Sweden road data from an external OSM PBF.

## Goal

Prove this flow with as little code as possible:

`OSM PBF -> portable road tiles -> Godot 4 -> perspective pan/zoom + streamed LOD`

Godot does not parse OSM. `tools/build_sweden.py` converts the PBF offline to the tiny `BRT1` tile format. Generated world data is intentionally ignored by Git.

## Build Sweden

The helper script already defaults to the local source used for this POC:

```bash
./build_sweden.sh
```

Equivalent explicit command:

```bash
./build_sweden.sh /Users/stefanlind/Dropbox/Code/syndicate/data/sweden-260824.osm.pbf
```

The first run creates `.venv`, installs `osmium`, reads the PBF and writes `world_data/`.

## Run

Open this repository folder in **Godot 4**, then press **Run Project**.

Controls:

- Mouse wheel: zoom
- Middle or right mouse drag: pan
- WASD / arrow keys: pan

## POC LODs

- LOD 0: motorway + trunk, thinned to roughly 400 m point spacing
- LOD 1: + primary + secondary, thinned to roughly 100 m spacing
- LOD 2: + tertiary/residential/unclassified/service, source geometry

Tiles are 32 km square. Runtime loads only tiles around the current camera focus and swaps LOD based on camera distance.

## Deliberately not included yet

No routing, traffic, buildings, terrain elevation, HTTP streaming, advanced caching, crossfade, shaders, or game logic. This branch only proves portable world data and perspective streaming in Godot.
