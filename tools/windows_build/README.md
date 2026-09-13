# Windows runtime build

This directory owns the reusable Windows build/package recipe. It is tooling only: authoritative world data remains owned by the offline/runtime-data pipeline.

## Normal invocation

From any mapped `brur-world` checkout:

```bash
bash tools/windows_build.sh 123
```

This means “build exact PR #123”. The launcher fetches the current `main` build tooling, resolves the exact PR head, creates an isolated temporary checkout for that revision, resolves the production runtime-data subset from the mapped checkout's existing `world_data`, reuses or builds a cached runtime resource pack, exports the revision-specific game EXE/PCK without embedding the large stable world dataset, verifies the combined game/runtime-pack contract, and writes only the final client ZIP to `~/Dropbox/BRUR/` by default.

Refs and full commits are also supported:

```bash
bash tools/windows_build.sh --ref issue/example
bash tools/windows_build.sh --ref <full-sha>
```

Overrides are environment variables, not alternate build implementations:

```bash
BRUR_WINDOWS_OUTPUT_DIR=/tmp/brur-out \
BRUR_WINDOWS_WORLD_DATA=/path/to/world_data \
BRUR_WINDOWS_CACHE_DIR=/path/to/persistent/windows-build-cache \
GODOT_BIN=/path/to/godot \
bash tools/windows_build.sh --ref <ref>
```

The default persistent cache is `~/.cache/brur-world/windows-build`.

## Safe Command trigger

The common project-leader action is the same repo-owned command through Safe Command Links. Approve it once on the local machine:

```bash
bash allow-project.sh /absolute/path/to/brur-world windows-build . /bin/bash tools/windows_build.sh --param pr:positive-int
```

A PR can then be built with:

```text
http://127.0.0.1:17384/safecommand/project?repo=estecode/brur-world&command=windows-build&pr=<PR number>
```

Safe Command owns only validation/launch. All revision resolution, isolated checkout, export, runtime-data identity/cache, manifests, packaging and delivery remain in this repository.

## Target contract

A revision that supports the build provides `tools/windows_build/target.sh`. The generic builder passes explicit environment paths for the isolated source checkout, authoritative local world data, runtime-pack info, binary output, build name and Godot binary.

The normal target exports the selected revision's existing production `run/main_scene` from `project.godot`. The Windows tooling must not rewrite the project entrypoint to a harness or POC scene.

`prepare_runtime_data.py` is the single selection contract for generated production runtime representations. It excludes rebuild-only inputs such as `buildings.jsonl`, `search_index.jsonl`, `pois.jsonl`, `building_tiles/`, and `osm_source_cache/`, and includes the current production `building_mesh_lod/` dataset.

`runtime_pack.py` fingerprints exactly that selection. On the first build it hashes the selected files and writes a compressed, mountable `brur-world-data.zip`. Verified per-file hashes are memoized against strong local file metadata (`dev`, `ino`, `size`, `mtime_ns`, `ctime_ns`). An unchanged warm build stats the files, reuses their verified hashes, and reuses the exact content-addressed runtime pack without rereading multi-GB payloads. Any metadata change rehashes the affected file. Invalid or modified cached packs are rebuilt.

The Godot export itself contains code/assets only. `scripts/windows_runtime_pack_loader.gd` is an autoload that, on Windows production startup, mounts `brur-world-data.zip` from beside the executable before the main scene starts. Existing gameplay paths remain `res://world_data/...`; local/editor runs that already have world data do not mount an external pack.

After export, the target opens the produced game PCK with local Godot, confirms that it does **not** contain `world_data`, mounts the external runtime pack, and executes `tests/godot/test_windows_packaged_world_data.gd`. Missing top-level datasets, empty runtime directories, obsolete `building_tiles`, or leaked source caches fail the build before packaging.

## Package contract

A client-ready ZIP has this shape:

```text
BRUR/
  <build>.exe
  <build>.pck
  brur-world-data.zip
  build_info.json
  client_bundle_info.json
  logs/
```

The external runtime resource pack is already compressed and content-addressed, so `package.py` stores it verbatim in the outer client ZIP instead of recompressing it on every code build. The delivered client remains completely self-contained.

`build_info.json` records repository, selector/ref, PR/issue when available, exact SHA, build timestamp, Godot version/export target, source-manifest fingerprint, runtime-file fingerprints, runtime-pack fingerprint/cache status, and `runtime_delivery=resource_pack:brur-world-data.zip=>res://world_data`. `client_bundle_info.json` repeats the code/world identity needed for copied client logs and package inspection.

`package.py` fails closed on missing EXE/PCK, missing or invalid runtime-pack info, missing/invalid runtime resource pack, invalid build identity, missing source manifest, incomplete ZIP contents, accidental duplicate `runtime_data/` payloads, or outer-ZIP recompression of the cached runtime pack.

## Timing

Windows builds print explicit timing records such as:

```text
WINDOWS_TIMING stage=runtime_pack seconds=...
WINDOWS_TIMING stage=godot_export seconds=...
WINDOWS_TIMING stage=runtime_pack_verify seconds=...
WINDOWS_TIMING stage=target_total seconds=...
WINDOWS_TIMING stage=client_package seconds=...
```

`runtime_pack.py` also reports whether the runtime pack was a cache `HIT` or `MISS`, how many file hashes were reused, how many files were rehashed, and the identity/pack time. This makes it clear whether a slow build is export, world-data identity, first-time compression, verification, or final client packaging.

Intermediate worktrees and exports stay in temporary directories. Only the final ZIP and the persistent content-addressed runtime-pack cache survive between builds.
