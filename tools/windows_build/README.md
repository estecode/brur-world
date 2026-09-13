# Windows runtime build

This directory owns the reusable Windows build/package recipe. It is tooling only: authoritative world data remains owned by the offline/runtime-data pipeline.

## Normal invocation

From any mapped `brur-world` checkout:

```bash
bash tools/windows_build.sh 123
```

This means “build exact PR #123”. The launcher fetches the current `main` build tooling, resolves the exact PR head, creates an isolated temporary checkout for that revision, selects the production runtime-data subset from the mapped checkout's existing `world_data`, stages that subset as `res://world_data` for export, validates the exported PCK, and writes only the final ZIP to `~/Dropbox/BRUR/` by default.

Refs and full commits are also supported:

```bash
bash tools/windows_build.sh --ref issue/example
bash tools/windows_build.sh --ref <full-sha>
```

Overrides are environment variables, not alternate build implementations:

```bash
BRUR_WINDOWS_OUTPUT_DIR=/tmp/brur-out \
BRUR_WINDOWS_WORLD_DATA=/path/to/world_data \
GODOT_BIN=/path/to/godot \
bash tools/windows_build.sh --ref <ref>
```

## Safe Command trigger

The common project-leader action is the same repo-owned command through Safe Command Links. Approve it once on the local machine:

```bash
bash allow-project.sh /absolute/path/to/brur-world windows-build . /bin/bash tools/windows_build.sh --param pr:positive-int
```

A PR can then be built with:

```text
http://127.0.0.1:17384/safecommand/project?repo=estecode/brur-world&command=windows-build&pr=<PR number>
```

Safe Command owns only validation/launch. All revision resolution, isolated checkout, export, runtime-data preparation, manifests, packaging and delivery remain in this repository.

## Target contract

A revision that supports the build provides `tools/windows_build/target.sh`. The generic builder passes explicit environment paths for the isolated source checkout, authoritative local world data, temporary runtime-data output, binary output, build name and Godot binary.

The normal target exports the selected revision's existing production `run/main_scene` from `project.godot`. The Windows tooling must not rewrite the project entrypoint to a harness or POC scene.

`prepare_runtime_data.py` selects only generated production runtime representations and excludes rebuild-only inputs such as `buildings.jsonl`, `search_index.jsonl`, `pois.jsonl`, and `osm_source_cache/`. The selected files are copied into the isolated checkout as `world_data/`, and the temporary Windows export preset explicitly includes that directory so production's existing `res://world_data/...` paths resolve inside the PCK.

After export, the target opens the produced PCK with the local Godot runtime and executes `tests/godot/test_windows_packaged_world_data.gd`. Missing top-level datasets, empty runtime tile directories, or a leaked source cache fail the build before packaging.

## Package contract

A client-ready ZIP has this shape:

```text
BRUR/
  <build>.exe
  <build>.pck
  build_info.json
  client_bundle_info.json
  logs/
```

Production world data is embedded once in `<build>.pck` at `res://world_data`; it is not duplicated beside the executable. `build_info.json` records repository, selector/ref, PR/issue when available, exact SHA, build timestamp, Godot version/export target, source-manifest fingerprint, packaged runtime-file fingerprints, and `runtime_delivery=embedded_pck:res://world_data`. `client_bundle_info.json` repeats the code/world identity needed for copied client logs and package inspection.

`package.py` fails closed on missing EXE/PCK, missing/empty prepared runtime data, invalid build identity, missing source manifest, incomplete ZIP contents, or accidental duplicate `runtime_data/` payloads.

Intermediate worktrees, exports and runtime-data staging stay in temporary directories. Only the final ZIP is written to the configured delivery directory.
