#!/usr/bin/env python3
"""Prebuild deterministic binary building render chunks for fast viewport staging.

Dependencies:
- Reads authoritative world_data/buildings.jsonl from the existing offline world pipeline.
- Mirrors the explicit production building LOD thresholds/chunk sizes.
- Preserves authoritative building footprint silhouettes at every LOD; LOD changes selection only.
- Writes only derived building_mesh_lod binary render chunks and manifest metadata.
- Uses no Sweden PBF access and introduces no alternate building truth.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import shutil
import struct
import time
from collections import OrderedDict
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO, Iterable

FORMAT_VERSION = 1
MAGIC = b"BMC1"
HEADER_STRUCT = struct.Struct("<4sII")
VERTEX_STRUCT = struct.Struct("<ffffffBBBB")
DEFAULT_MAX_OPEN = 48
DEFAULT_HEIGHT_M = 9.0
LEVEL_HEIGHT_M = 3.0
MIN_HEIGHT_M = 2.5
MAX_HEIGHT_M = 120.0
PROGRESS_EVERY_RECORDS = 25_000


@dataclass(frozen=True)
class LodLevel:
    lod: int
    chunk_size_m: float
    min_area_m2: float
    simplified: bool


LOD_LEVELS = (
    LodLevel(0, 16_000.0, 3_500.0, False),
    LodLevel(1, 8_000.0, 1_200.0, False),
    LodLevel(2, 4_000.0, 300.0, False),
    LodLevel(3, 2_000.0, 0.0, False),
)


def _builder_sha256() -> str:
    return hashlib.sha256(Path(__file__).read_bytes()).hexdigest()


def _policy_fingerprint() -> str:
    payload = [
        {
            "lod": level.lod,
            "chunk_size_m": level.chunk_size_m,
            "min_area_m2": level.min_area_m2,
            "simplified": level.simplified,
        }
        for level in LOD_LEVELS
    ]
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode("utf-8")).hexdigest()


def _numeric_tag(value: object) -> float:
    text = str(value or "").strip().replace(",", ".")
    if not text:
        return 0.0
    number = ""
    for character in text:
        if character in "0123456789.+-":
            number += character
        elif number:
            break
    try:
        return float(number) if number else 0.0
    except ValueError:
        return 0.0


def height_from_tags(tags: dict) -> float:
    explicit = _numeric_tag(tags.get("height", ""))
    if explicit > 0.0:
        return min(MAX_HEIGHT_M, max(MIN_HEIGHT_M, explicit))
    levels = _numeric_tag(tags.get("building:levels", ""))
    if levels > 0.0:
        return min(MAX_HEIGHT_M, max(MIN_HEIGHT_M, levels * LEVEL_HEIGHT_M))
    return DEFAULT_HEIGHT_M


def stable_source_id(record: dict) -> str:
    for key in ("id", "osm_id", "source_id"):
        value = str(record.get(key, ""))
        if value:
            return value
    return f"xy:{float(record.get('x', 0.0)):.3f}:{float(record.get('y', 0.0)):.3f}"


def appearance_rgba(record: dict) -> tuple[tuple[int, int, int, int], ...]:
    digest = hashlib.blake2b(stable_source_id(record).encode("utf-8"), digest_size=8).digest()
    variation = int.from_bytes(digest[:2], "little") / 65535.0
    wall_value = 0.43 + variation * 0.12
    roof_value = min(0.67, max(0.48, wall_value + 0.055 + (digest[2] % 5) * 0.008))
    wall = _gray_rgba(wall_value, wall_value + 0.008, wall_value + 0.018)
    roof = _gray_rgba(roof_value, roof_value + 0.006, roof_value + 0.012)
    base = _gray_rgba(wall_value * 0.8, (wall_value + 0.008) * 0.8, (wall_value + 0.018) * 0.8)
    return wall, roof, base


def _gray_rgba(r: float, g: float, b: float) -> tuple[int, int, int, int]:
    def channel(value: float) -> int:
        return max(0, min(255, round(value * 255.0)))

    return channel(r), channel(g), channel(b), 255


def _clean_ring(raw: object) -> list[tuple[float, float]]:
    if not isinstance(raw, list):
        return []
    result: list[tuple[float, float]] = []
    for value in raw:
        if not isinstance(value, list) or len(value) < 2:
            continue
        point = (float(value[0]), float(value[1]))
        if not result or point != result[-1]:
            result.append(point)
    if len(result) > 1 and result[0] == result[-1]:
        result.pop()
    return result


def _signed_area(points: list[tuple[float, float]]) -> float:
    if len(points) < 3:
        return 0.0
    return 0.5 * sum(
        points[index][0] * points[(index + 1) % len(points)][1]
        - points[(index + 1) % len(points)][0] * points[index][1]
        for index in range(len(points))
    )


def footprint_area_m2(record: dict) -> float:
    total = 0.0
    for polygon in record.get("geometry", []):
        if not isinstance(polygon, dict):
            continue
        outer = _clean_ring(polygon.get("outer", []))
        total += abs(_signed_area(outer))
        for hole in polygon.get("holes", []):
            total -= abs(_signed_area(_clean_ring(hole)))
    return max(0.0, total)


def _cross(a: tuple[float, float], b: tuple[float, float], c: tuple[float, float]) -> float:
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def _point_in_triangle(
    point: tuple[float, float],
    a: tuple[float, float],
    b: tuple[float, float],
    c: tuple[float, float],
) -> bool:
    epsilon = 1e-9
    ab = _cross(a, b, point)
    bc = _cross(b, c, point)
    ca = _cross(c, a, point)
    return ab >= -epsilon and bc >= -epsilon and ca >= -epsilon


def triangulate_ring(points: list[tuple[float, float]]) -> list[tuple[int, int, int]]:
    """Deterministic ear clipping for ordinary OSM building outer rings."""
    if len(points) < 3:
        return []
    if _signed_area(points) < 0.0:
        points.reverse()
    indices = list(range(len(points)))
    triangles: list[tuple[int, int, int]] = []
    guard = len(indices) * len(indices)
    while len(indices) > 3 and guard > 0:
        guard -= 1
        ear_found = False
        for pos in range(len(indices)):
            prev_index = indices[(pos - 1) % len(indices)]
            index = indices[pos]
            next_index = indices[(pos + 1) % len(indices)]
            a, b, c = points[prev_index], points[index], points[next_index]
            if _cross(a, b, c) <= 1e-9:
                continue
            if any(
                _point_in_triangle(points[other], a, b, c)
                for other in indices
                if other not in (prev_index, index, next_index)
            ):
                continue
            triangles.append((prev_index, index, next_index))
            del indices[pos]
            ear_found = True
            break
        if not ear_found:
            break
    if len(indices) == 3:
        triangles.append((indices[0], indices[1], indices[2]))
    if not triangles and len(points) >= 3:
        triangles.extend((0, index, index + 1) for index in range(1, len(points) - 1))
    return triangles


def _simplified_ring(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    if len(points) < 3:
        return []
    min_x = min(point[0] for point in points)
    max_x = max(point[0] for point in points)
    min_y = min(point[1] for point in points)
    max_y = max(point[1] for point in points)
    if max_x - min_x <= 0.01 or max_y - min_y <= 0.01:
        return []
    return [(min_x, min_y), (max_x, min_y), (max_x, max_y), (min_x, max_y)]


def _normalize_horizontal(x: float, z: float) -> tuple[float, float]:
    length = math.hypot(x, z)
    if length <= 1e-9:
        return 0.0, 1.0
    return x / length, z / length


def _vertex_bytes(
    x: float,
    y: float,
    z: float,
    nx: float,
    ny: float,
    nz: float,
    color: tuple[int, int, int, int],
) -> bytes:
    return VERTEX_STRUCT.pack(x, y, z, nx, ny, nz, *color)


def polygon_vertex_blob(
    points_absolute: list[tuple[float, float]],
    height_m: float,
    chunk_origin: tuple[float, float],
    colors: tuple[tuple[int, int, int, int], ...],
) -> tuple[bytes, int]:
    if len(points_absolute) < 3:
        return b"", 0
    points = list(points_absolute)
    triangles = triangulate_ring(points)
    if not triangles:
        return b"", 0
    wall, roof, base = colors
    origin_x, origin_y = chunk_origin
    blob = bytearray()

    def local(point: tuple[float, float], y: float) -> tuple[float, float, float]:
        return point[0] - origin_x, y, -(point[1] - origin_y)

    for ia, ib, ic in triangles:
        for index in (ia, ib, ic):
            x, y, z = local(points[index], height_m)
            blob += _vertex_bytes(x, y, z, 0.0, 1.0, 0.0, roof)

    for index in range(len(points)):
        a = points[index]
        b = points[(index + 1) % len(points)]
        if a == b:
            continue
        ax, _, az = local(a, 0.0)
        bx, _, bz = local(b, 0.0)
        dx, dz = bx - ax, bz - az
        nx, nz = _normalize_horizontal(-dz, dx)
        a0 = (ax, 0.0, az)
        b0 = (bx, 0.0, bz)
        a1 = (ax, height_m, az)
        b1 = (bx, height_m, bz)
        for vertex, color in ((a0, base), (b0, base), (b1, wall), (a0, base), (b1, wall), (a1, wall)):
            blob += _vertex_bytes(vertex[0], vertex[1], vertex[2], nx, 0.0, nz, color)

    return bytes(blob), len(blob) // VERTEX_STRUCT.size


class ChunkWriter:
    def __init__(self, directory: Path, max_open: int = DEFAULT_MAX_OPEN) -> None:
        self.directory = directory
        stamp = f"{os.getpid()}-{time.time_ns()}"
        self.write_directory = directory.parent / f".{directory.name}.build-{stamp}"
        self.write_directory.mkdir(parents=True, exist_ok=False)
        self.max_open = max_open
        self.files: OrderedDict[tuple[int, int, int], BinaryIO] = OrderedDict()
        self.vertex_counts: dict[tuple[int, int, int], int] = {}
        self.building_counts = {level.lod: 0 for level in LOD_LEVELS}
        self.bytes_written = {level.lod: 0 for level in LOD_LEVELS}

    def _path(self, key: tuple[int, int, int]) -> Path:
        lod, x, y = key
        directory = self.write_directory / f"lod{lod}"
        directory.mkdir(parents=True, exist_ok=True)
        return directory / f"{x}_{y}.bmc"

    def write(self, level: LodLevel, chunk: tuple[int, int], blob: bytes, vertex_count: int) -> None:
        if vertex_count <= 0 or not blob:
            return
        key = (level.lod, chunk[0], chunk[1])
        handle = self.files.pop(key, None)
        if handle is None:
            path = self._path(key)
            new_file = not path.exists()
            handle = path.open("ab")
            if new_file:
                handle.write(HEADER_STRUCT.pack(MAGIC, FORMAT_VERSION, 0))
        self.files[key] = handle
        handle.write(blob)
        self.vertex_counts[key] = self.vertex_counts.get(key, 0) + vertex_count
        self.building_counts[level.lod] += 1
        self.bytes_written[level.lod] += len(blob)
        if len(self.files) > self.max_open:
            _, oldest = self.files.popitem(last=False)
            oldest.close()

    def close(self) -> None:
        for handle in self.files.values():
            handle.close()
        self.files.clear()

    def finalize_headers(self) -> None:
        self.close()
        for key, count in self.vertex_counts.items():
            path = self._path(key)
            with path.open("r+b") as handle:
                handle.seek(8)
                handle.write(struct.pack("<I", count))

    def publish(self) -> None:
        self.finalize_headers()
        stale: Path | None = None
        if self.directory.exists():
            stale = self.directory.parent / f".{self.directory.name}.old-{os.getpid()}-{time.time_ns()}"
            self.directory.rename(stale)
        try:
            self.write_directory.rename(self.directory)
        except Exception:
            if stale is not None and stale.exists() and not self.directory.exists():
                stale.rename(self.directory)
            raise
        if stale is not None and stale.exists():
            shutil.rmtree(stale)

    def cleanup(self, remove_files: bool = True) -> None:
        self.close()
        if remove_files and self.write_directory.exists():
            shutil.rmtree(self.write_directory)


def _chunk_key(record: dict, level: LodLevel) -> tuple[int, int]:
    return math.floor(float(record["x"]) / level.chunk_size_m), math.floor(float(record["y"]) / level.chunk_size_m)


def _chunk_origin(chunk: tuple[int, int], level: LodLevel) -> tuple[float, float]:
    return chunk[0] * level.chunk_size_m, chunk[1] * level.chunk_size_m


def building_mesh_pyramid_cache_valid(world_dir: Path) -> bool:
    manifest_path = world_dir / "manifest.json"
    source_path = world_dir / "buildings.jsonl"
    output_dir = world_dir / "building_mesh_lod"
    if not manifest_path.is_file() or not source_path.is_file() or not output_dir.is_dir():
        return False
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        source_stat = source_path.stat()
        features = manifest.get("features", {})
        if features.get("building_mesh_lod_dir") != "building_mesh_lod":
            return False
        if int(features.get("building_mesh_lod_format_version", 0)) != FORMAT_VERSION:
            return False
        if features.get("building_mesh_lod_builder_sha256") != _builder_sha256():
            return False
        if features.get("building_mesh_lod_policy_sha256") != _policy_fingerprint():
            return False
        if int(features.get("building_mesh_lod_source_size", -1)) != source_stat.st_size:
            return False
        if int(features.get("building_mesh_lod_source_mtime_ns", -1)) != source_stat.st_mtime_ns:
            return False
        levels = features.get("building_mesh_lod_levels", [])
        if len(levels) != len(LOD_LEVELS):
            return False
        for expected, actual in zip(LOD_LEVELS, levels, strict=True):
            if int(actual.get("lod", -1)) != expected.lod:
                return False
            if float(actual.get("chunk_size_m", 0.0)) != expected.chunk_size_m:
                return False
            if float(actual.get("min_area_m2", -1.0)) != expected.min_area_m2:
                return False
            if bool(actual.get("simplified", False)) != expected.simplified:
                return False
            if int(actual.get("chunks", 0)) <= 0:
                return False
            level_dir = output_dir / f"lod{expected.lod}"
            if not level_dir.is_dir() or next(level_dir.glob("*.bmc"), None) is None:
                return False
        return True
    except (OSError, TypeError, ValueError, KeyError):
        return False


def _clean_outer_rings(record: dict) -> list[list[tuple[float, float]]]:
    result: list[list[tuple[float, float]]] = []
    for polygon in record.get("geometry", []):
        if not isinstance(polygon, dict):
            continue
        outer = _clean_ring(polygon.get("outer", []))
        if len(outer) >= 3:
            result.append(outer)
    return result


def _outer_area_m2(rings: Iterable[list[tuple[float, float]]]) -> float:
    return sum(abs(_signed_area(ring)) for ring in rings)


def _simplify_rings(rings: Iterable[list[tuple[float, float]]]) -> list[list[tuple[float, float]]]:
    result: list[list[tuple[float, float]]] = []
    for ring in rings:
        simplified = _simplified_ring(ring)
        if len(simplified) >= 3:
            result.append(simplified)
    return result


def _payload_bytes_written(writer: ChunkWriter) -> int:
    return sum(writer.bytes_written.values())


def _print_progress(source_records: int, started: float, writer: ChunkWriter) -> None:
    elapsed = max(0.001, time.monotonic() - started)
    rate = source_records / elapsed
    payload_mib = _payload_bytes_written(writer) / (1024.0 * 1024.0)
    print(
        f"[building-mesh-lod] {source_records:,} buildings | {rate:,.0f}/s | "
        f"{elapsed:.1f}s | {payload_mib:,.1f} MiB",
        flush=True,
    )


def build_building_mesh_pyramid(world_dir: Path) -> dict:
    manifest_path = world_dir / "manifest.json"
    source_path = world_dir / "buildings.jsonl"
    if not manifest_path.is_file():
        raise SystemExit(f"missing manifest: {manifest_path}")
    if not source_path.is_file():
        raise SystemExit(f"missing authoritative building export: {source_path}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    source_stat = source_path.stat()
    output_dir = world_dir / "building_mesh_lod"
    writer = ChunkWriter(output_dir)
    started = time.monotonic()
    source_records = 0
    success = False
    interrupted = False
    try:
        with source_path.open("r", encoding="utf-8") as source:
            for line_number, line in enumerate(source, 1):
                if not line.strip():
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError as exc:
                    raise SystemExit(f"invalid buildings.jsonl at line {line_number}: {exc}") from exc
                if "x" not in record or "y" not in record:
                    raise SystemExit(f"building record {line_number} is missing x/y")
                source_records += 1
                full_rings = _clean_outer_rings(record)
                area = _outer_area_m2(full_rings)
                simplified_rings: list[list[tuple[float, float]]] | None = None
                height = height_from_tags(record.get("tags", {}))
                colors = appearance_rgba(record)
                for level in LOD_LEVELS:
                    if area < level.min_area_m2:
                        continue
                    rings = full_rings
                    if level.simplified:
                        if simplified_rings is None:
                            simplified_rings = _simplify_rings(full_rings)
                        rings = simplified_rings
                    chunk = _chunk_key(record, level)
                    origin = _chunk_origin(chunk, level)
                    record_blob = bytearray()
                    vertex_count = 0
                    for ring in rings:
                        blob, count = polygon_vertex_blob(ring, height, origin, colors)
                        record_blob += blob
                        vertex_count += count
                    writer.write(level, chunk, bytes(record_blob), vertex_count)
                if source_records % PROGRESS_EVERY_RECORDS == 0:
                    _print_progress(source_records, started, writer)
        _print_progress(source_records, started, writer)
        writer.publish()
        success = True
    except KeyboardInterrupt:
        interrupted = True
        writer.cleanup(remove_files=False)
        print(
            f"[building-mesh-lod] interrupted after {source_records:,} buildings; "
            f"partial scratch retained at {writer.write_directory}",
            flush=True,
        )
        raise
    finally:
        if not success and not interrupted:
            writer.cleanup()

    level_reports = []
    for level in LOD_LEVELS:
        level_dir = output_dir / f"lod{level.lod}"
        chunks = len(list(level_dir.glob("*.bmc"))) if level_dir.is_dir() else 0
        vertices = sum(count for (lod, _, _), count in writer.vertex_counts.items() if lod == level.lod)
        level_reports.append(
            {
                "lod": level.lod,
                "chunk_size_m": level.chunk_size_m,
                "min_area_m2": level.min_area_m2,
                "simplified": level.simplified,
                "chunks": chunks,
                "buildings": writer.building_counts[level.lod],
                "vertices": vertices,
                "payload_bytes": writer.bytes_written[level.lod],
            }
        )

    features = dict(manifest.get("features", {}))
    features["building_mesh_lod_dir"] = "building_mesh_lod"
    features["building_mesh_lod_format_version"] = FORMAT_VERSION
    features["building_mesh_lod_builder_sha256"] = _builder_sha256()
    features["building_mesh_lod_policy_sha256"] = _policy_fingerprint()
    features["building_mesh_lod_source_size"] = source_stat.st_size
    features["building_mesh_lod_source_mtime_ns"] = source_stat.st_mtime_ns
    features["building_mesh_lod_levels"] = level_reports
    manifest["features"] = features
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    report = {
        "source": "buildings.jsonl",
        "source_records": source_records,
        "format_version": FORMAT_VERSION,
        "levels": level_reports,
        "elapsed_s": time.monotonic() - started,
    }
    print(
        "[building-mesh-lod] "
        + " ".join(
            f"lod{item['lod']}={item['chunks']:,}chunks/{item['vertices']:,}v"
            for item in level_reports
        )
        + f" elapsed={report['elapsed_s']:.1f}s",
        flush=True,
    )
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("world_dir", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        raise SystemExit(0 if building_mesh_pyramid_cache_valid(args.world_dir) else 1)
    build_building_mesh_pyramid(args.world_dir)


if __name__ == "__main__":
    main()