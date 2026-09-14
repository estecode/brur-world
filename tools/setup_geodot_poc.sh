#!/usr/bin/env bash
# Installs the pinned GeoDot addon for the isolated POC without committing third-party binaries.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN="0301e42eecc45b36503da3c02a6296bcc5dc32a8"
GODOT_CPP_PIN="27d9dd23c83871e0619fca5dc2cddfbfd69e926a"
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

prepare_source() {
  command -v git >/dev/null 2>&1 || { printf 'GEODOT_SETUP=FAIL git missing\n' >&2; return 1; }
  if [[ ! -d "$SRC/.git" ]]; then
    rm -rf "$SRC"
    git clone --filter=blob:none --no-checkout https://github.com/$REPO.git "$SRC"
  fi
  git -C "$SRC" fetch --depth=1 origin "$PIN"
  git -C "$SRC" checkout --detach "$PIN"
  [[ "$(git -C "$SRC" rev-parse HEAD)" == "$PIN" ]] || {
    printf 'GEODOT_SETUP=FAIL pinned source revision mismatch\n' >&2
    return 1
  }
}

pin_godot_cpp() {
  # GeoDot master currently points at Godot 4.6 godot-cpp. BRUR is intentionally
  # still on Godot 4.5.x, and GDExtensions built for a newer engine are rejected
  # by 4.5 at load time. Keep the GeoDot source pin, but compile its binding layer
  # against a fixed 4.5-compatible godot-cpp revision instead of changing BRUR's
  # engine version just for the POC.
  git -C "$SRC/godot-cpp" fetch --depth=1 origin "$GODOT_CPP_PIN"
  git -C "$SRC/godot-cpp" checkout --detach "$GODOT_CPP_PIN"
  [[ "$(git -C "$SRC/godot-cpp" rev-parse HEAD)" == "$GODOT_CPP_PIN" ]] || {
    printf 'GEODOT_SETUP=FAIL pinned godot-cpp revision mismatch\n' >&2
    return 1
  }
  printf 'GEODOT_SETUP=GODOT_CPP sha=%s\n' "$GODOT_CPP_PIN"
}

patch_geopackage_crs() {
  # GeoDot's pinned NativeDataset::get_epsg_code() only calls GDALDataset::GetSpatialRef().
  # Vector-only GeoPackages commonly expose their SRS on each OGRLayer instead, so GeoDot
  # returns -1 even though gpkg_contents/gpkg_geometry_columns correctly declare the CRS.
  # Keep this POC patch narrow and deterministic: fall back to the first vector layer SRS.
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

try_artifact() {
  # Upstream artifacts follow GeoDot's own godot-cpp submodule and also lack the
  # vector-only GeoPackage CRS fallback required by this POC. Use a source build
  # until both compatibility fixes are available in an upstream artifact.
  return 1
}

build_from_source() {
  command -v scons >/dev/null 2>&1 || { printf 'GEODOT_SETUP=FAIL scons missing\n' >&2; return 1; }
  prepare_source
  git -C "$SRC" submodule update --init --recursive
  pin_godot_cpp
  patch_geopackage_crs

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
      # Match upstream packaging: keep runtime dependencies beside the extension so
      # the POC does not silently depend on the build machine's exact GDAL SONAME.
      (cd "$SRC/demo/addons/geodot/x11" && ldd libgeodot.so | awk '/=> \// {print $3}' | xargs -r -I '{}' cp -n '{}' ./)
      ;;
  esac
  mkdir -p "$ROOT/addons"
  rm -rf "$TARGET"
  cp -R "$SRC/demo/addons/geodot" "$TARGET"
  printf 'GEODOT_SETUP=SOURCE sha=%s godot_cpp=%s platform=%s\n' "$PIN" "$GODOT_CPP_PIN" "$platform"
}

if try_artifact; then
  :
else
  printf 'GEODOT_SETUP=ARTIFACT_UNAVAILABLE sha=%s; building patched source against BRUR-compatible host dependencies\n' "$PIN"
  build_from_source
fi

[[ -f "$TARGET/geodot.gdextension" ]] || { printf 'GEODOT_SETUP=FAIL addon missing after setup\n' >&2; exit 1; }
printf 'GEODOT_SETUP=OK sha=%s godot_cpp=%s target=%s\n' "$PIN" "$GODOT_CPP_PIN" "$TARGET"
