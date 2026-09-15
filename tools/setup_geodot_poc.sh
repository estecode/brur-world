#!/usr/bin/env bash
# Installs the pinned GeoDot addon for the isolated POC without committing third-party binaries.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN="0301e42eecc45b36503da3c02a6296bcc5dc32a8"
GODOT_CPP_PIN="27d9dd23c83871e0619fca5dc2cddfbfd69e926a"
REPO="boku-ilen/geodot-plugin"
TARGET="$ROOT/addons/geodot"
PLATFORM="$(uname -s)"
ARCH="$(uname -m)"
CACHE_BASE="${BRUR_GEODOT_CACHE_ROOT:-${XDG_CACHE_HOME:-$HOME/.cache}/brur-world/geodot}"
BUILD_ID="${PIN}-${GODOT_CPP_PIN}-crs-v1-${PLATFORM}-${ARCH}"
CACHE_ROOT="$CACHE_BASE/$BUILD_ID"
SRC="$CACHE_ROOT/src"
INSTALLED="$CACHE_ROOT/addon"

install_cached_addon() {
  [[ -f "$INSTALLED/geodot.gdextension" ]] || return 1
  mkdir -p "$ROOT/addons"
  rm -rf "$TARGET"
  cp -R "$INSTALLED" "$TARGET"
  printf 'GEODOT_SETUP=CACHED build_id=%s cache=%s target=%s\n' "$BUILD_ID" "$INSTALLED" "$TARGET"
}

if [[ -f "$TARGET/geodot.gdextension" ]]; then
  printf 'GEODOT_SETUP=READY target=%s\n' "$TARGET"
  exit 0
fi

if install_cached_addon; then
  exit 0
fi

mkdir -p "$CACHE_ROOT"
platform="$PLATFORM"
case "$platform" in
  Darwin|Linux) ;;
  *) printf 'GEODOT_SETUP=FAIL unsupported host platform=%s\n' "$platform" >&2; exit 69 ;;
esac

prepare_source() {
  command -v git >/dev/null 2>&1 || { printf 'GEODOT_SETUP=FAIL git missing\n' >&2; return 1; }
  if [[ ! -d "$SRC/.git" ]]; then
    rm -rf "$SRC"
    git clone --filter=blob:none --no-checkout https://github.com/$REPO.git "$SRC"
  fi
  git -C "$SRC" fetch --depth=1 origin "$PIN"
  git -C "$SRC" checkout --detach "$PIN"
  [[ "$(git -C "$SRC" rev-parse HEAD)" == "$PIN" ]] || { printf 'GEODOT_SETUP=FAIL pinned source revision mismatch\n' >&2; return 1; }
}

pin_godot_cpp() {
  git -C "$SRC/godot-cpp" fetch --depth=1 origin "$GODOT_CPP_PIN"
  git -C "$SRC/godot-cpp" checkout --detach "$GODOT_CPP_PIN"
  [[ "$(git -C "$SRC/godot-cpp" rev-parse HEAD)" == "$GODOT_CPP_PIN" ]] || { printf 'GEODOT_SETUP=FAIL pinned godot-cpp revision mismatch\n' >&2; return 1; }
  printf 'GEODOT_SETUP=GODOT_CPP sha=%s\n' "$GODOT_CPP_PIN"
}

patch_geopackage_crs() {
  python3 - "$SRC/src/vector-extractor/NativeDataset.cpp" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = '''int NativeDataset::get_epsg_code() const {
    if (!dataset) return -1;
    const OGRSpatialReference* sr = dataset->GetSpatialRef();
    if (!sr) return -1;

    // Attempt to compute EPSG codes
    
    OGRSpatialReference srCopy(*sr);
    srCopy.AutoIdentifyEPSG();
    const char* authName = srCopy.GetAuthorityName(nullptr);
    const char* authCode = srCopy.GetAuthorityCode(nullptr);

    if (authName && authCode && std::string(authName) == "EPSG")
        return std::stoi(authCode);
    return -1;
}
'''
new = '''int NativeDataset::get_epsg_code() const {
    if (!dataset) return -1;
    const OGRSpatialReference* sr = dataset->GetSpatialRef();
    if (!sr) {
        const int layer_count = dataset->GetLayerCount();
        for (int i = 0; i < layer_count && !sr; ++i) {
            OGRLayer* vector_layer = dataset->GetLayer(i);
            if (vector_layer) sr = vector_layer->GetSpatialRef();
        }
    }
    if (!sr) return -1;

    // Attempt to compute EPSG codes
    OGRSpatialReference srCopy(*sr);
    srCopy.AutoIdentifyEPSG();
    const char* authName = srCopy.GetAuthorityName(nullptr);
    const char* authCode = srCopy.GetAuthorityCode(nullptr);

    if (authName && authCode && std::string(authName) == "EPSG")
        return std::stoi(authCode);
    return -1;
}
'''
if old not in text:
    if new in text:
        raise SystemExit(0)
    raise SystemExit("GEODOT_SETUP=FAIL pinned GeoDot CRS patch context changed")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY
  printf 'GEODOT_SETUP=CRS_PATCH vector-layer-fallback\n'
}

ensure_macos_build_dependencies() {
  command -v brew >/dev/null 2>&1 || { printf 'GEODOT_SETUP=FAIL Homebrew required for macOS source build\n' >&2; return 1; }
  command -v scons >/dev/null 2>&1 || { printf 'GEODOT_SETUP=FAIL scons missing; install development dependencies first\n' >&2; return 1; }
  brew --prefix gdal >/dev/null 2>&1 || { printf 'GEODOT_SETUP=FAIL gdal missing; install development dependencies first\n' >&2; return 1; }
  command -v dylibbundler >/dev/null 2>&1 || { printf 'GEODOT_SETUP=FAIL dylibbundler missing; install development dependencies first\n' >&2; return 1; }
}

build_from_source() {
  if [[ "$platform" == "Darwin" ]]; then
    ensure_macos_build_dependencies
  else
    command -v scons >/dev/null 2>&1 || { printf 'GEODOT_SETUP=FAIL scons missing\n' >&2; return 1; }
  fi
  prepare_source
  git -C "$SRC" submodule update --init --recursive
  pin_godot_cpp
  patch_geopackage_crs

  case "$platform" in
    Darwin)
      local osgeo
      osgeo="$(brew --prefix gdal)"
      (cd "$SRC/godot-cpp" && scons platform=macos arch=arm64 generate_bindings=yes)
      (cd "$SRC" && scons platform=macos arch=arm64 osgeo_path="$osgeo")
      (cd "$SRC" && dylibbundler -of -b -x ./demo/addons/geodot/macos/libgeodot.dylib -d ./demo/addons/geodot/macos/ -p @loader_path)
      ;;
    Linux)
      (cd "$SRC/godot-cpp" && scons platform=linux generate_bindings=yes)
      (cd "$SRC" && scons platform=linux)
      (cd "$SRC/demo/addons/geodot/x11" && ldd libgeodot.so | awk '/=> \/\// {print $3}' | xargs -r -I '{}' cp -n '{}' ./)
      ;;
  esac

  rm -rf "$INSTALLED"
  mkdir -p "$CACHE_ROOT"
  cp -R "$SRC/demo/addons/geodot" "$INSTALLED"
  install_cached_addon
  printf 'GEODOT_SETUP=SOURCE sha=%s godot_cpp=%s platform=%s cache=%s\n' "$PIN" "$GODOT_CPP_PIN" "$platform" "$INSTALLED"
}

printf 'GEODOT_SETUP=ARTIFACT_UNAVAILABLE sha=%s; building once into persistent cache=%s\n' "$PIN" "$CACHE_ROOT"
build_from_source

[[ -f "$TARGET/geodot.gdextension" ]] || { printf 'GEODOT_SETUP=FAIL addon missing after setup\n' >&2; exit 1; }
printf 'GEODOT_SETUP=OK sha=%s godot_cpp=%s target=%s cache=%s\n' "$PIN" "$GODOT_CPP_PIN" "$TARGET" "$INSTALLED"
