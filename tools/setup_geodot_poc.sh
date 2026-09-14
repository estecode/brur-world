#!/usr/bin/env bash
# Installs the pinned GeoDot addon for the isolated POC without committing third-party binaries.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN="0301e42eecc45b36503da3c02a6296bcc5dc32a8"
REPO="boku-ilen/geodot-plugin"
TARGET="$ROOT/addons/geodot"
CACHE_ROOT="$ROOT/.poc_runtime/geodot"
SRC="$CACHE_ROOT/src"
ARTIFACT="$CACHE_ROOT/artifact"

if [[ -f "$TARGET/geodot.gdextension" ]]; then
  printf 'GEODOT_SETUP=READY target=%s\n' "$TARGET"
  exit 0
fi

mkdir -p "$CACHE_ROOT"
rm -rf "$ARTIFACT"
mkdir -p "$ARTIFACT"

platform="$(uname -s)"
workflow=""
artifact=""
case "$platform" in
  Darwin)
    workflow="build-silicon.yml"
    artifact="macos-build"
    ;;
  Linux)
    workflow="build-linux.yml"
    artifact="linux-build"
    ;;
  *)
    printf 'GEODOT_SETUP=FAIL unsupported host platform=%s\n' "$platform" >&2
    exit 69
    ;;
esac

try_artifact() {
  command -v gh >/dev/null 2>&1 || return 1
  local row run_id head_sha
  row="$(gh run list -R "$REPO" --workflow "$workflow" --branch master --status success --limit 10 \
    --json databaseId,headSha --jq ".[] | select(.headSha == \"$PIN\") | [.databaseId,.headSha] | @tsv" | head -n1)"
  [[ -n "$row" ]] || return 1
  run_id="${row%%$'\t'*}"
  head_sha="${row#*$'\t'}"
  [[ "$head_sha" == "$PIN" ]] || return 1
  gh run download "$run_id" -R "$REPO" --name "$artifact" --dir "$ARTIFACT"
  [[ -d "$ARTIFACT/demo/addons/geodot" ]] || return 1
  mkdir -p "$ROOT/addons"
  rm -rf "$TARGET"
  cp -R "$ARTIFACT/demo/addons/geodot" "$TARGET"
  printf 'GEODOT_SETUP=ARTIFACT sha=%s run=%s platform=%s\n' "$PIN" "$run_id" "$platform"
}

build_from_source() {
  command -v git >/dev/null 2>&1 || { printf 'GEODOT_SETUP=FAIL git missing\n' >&2; return 1; }
  command -v scons >/dev/null 2>&1 || { printf 'GEODOT_SETUP=FAIL scons missing\n' >&2; return 1; }
  if [[ ! -d "$SRC/.git" ]]; then
    rm -rf "$SRC"
    git clone https://github.com/$REPO.git "$SRC"
  fi
  git -C "$SRC" fetch origin "$PIN"
  git -C "$SRC" checkout --detach "$PIN"
  git -C "$SRC" submodule update --init --recursive

  case "$platform" in
    Darwin)
      command -v brew >/dev/null 2>&1 || { printf 'GEODOT_SETUP=FAIL Homebrew required for source fallback\n' >&2; return 1; }
      local osgeo
      osgeo="$(brew --prefix gdal)"
      (cd "$SRC/godot-cpp" && scons platform=macos arch=arm64 generate_bindings=yes)
      (cd "$SRC" && scons platform=macos arch=arm64 osgeo_path="$osgeo")
      if command -v dylibbundler >/dev/null 2>&1; then
        (cd "$SRC" && dylibbundler -of -b -x ./demo/addons/geodot/macos/libgeodot.dylib -d ./demo/addons/geodot/macos/ -p @loader_path)
      fi
      ;;
    Linux)
      (cd "$SRC/godot-cpp" && scons platform=linux generate_bindings=yes)
      (cd "$SRC" && scons platform=linux)
      ;;
  esac
  mkdir -p "$ROOT/addons"
  rm -rf "$TARGET"
  cp -R "$SRC/demo/addons/geodot" "$TARGET"
  printf 'GEODOT_SETUP=SOURCE sha=%s platform=%s\n' "$PIN" "$platform"
}

if ! try_artifact; then
  printf 'GEODOT_SETUP=ARTIFACT_UNAVAILABLE sha=%s; falling back to source build\n' "$PIN"
  build_from_source
fi

[[ -f "$TARGET/geodot.gdextension" ]] || { printf 'GEODOT_SETUP=FAIL addon missing after setup\n' >&2; exit 1; }
printf 'GEODOT_SETUP=OK sha=%s target=%s\n' "$PIN" "$TARGET"
