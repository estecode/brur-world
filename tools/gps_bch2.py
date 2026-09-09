"""Serialize the production-oriented BCH2 contraction-hierarchy sidecar.

Dependencies:
- gps_ch.py owns fixture-scale exact CH construction and shortcut identities.
- gps_routing.py owns routing-preference semantics.
- This module owns only the pointer-free little-endian SoA binary encoding.
"""

from __future__ import annotations

import struct
from pathlib import Path

from gps_ch import CHIndex
from gps_routing import RoutingPreference

MAGIC = b"BCH2"
VERSION = 1
HEADER = struct.Struct("<4sIIIIIIIfIQQQQQQQQQQQ")
U32 = struct.Struct("<I")
I32 = struct.Struct("<i")
UINT32_MAX = (1 << 32) - 1

PREFERENCE_CODE = {
    RoutingPreference.FASTEST: 0,
    RoutingPreference.SHORTEST: 1,
    RoutingPreference.AVOID_SMALL_ROADS: 2,
    RoutingPreference.AVOID_MAJOR_ROADS: 3,
}


def weight_scale(preference: RoutingPreference) -> int:
    """Return deterministic fixed-point units per policy cost unit.

    Millimetres cover more than 4,000 km and milliseconds cover more than
    49 days in uint32, while keeping hot target+weight relaxation data at 8 bytes.
    """
    return 1_000


def quantize_cost(cost: float, scale: int) -> int:
    value = int(round(float(cost) * scale))
    if value < 0 or value > UINT32_MAX:
        raise OverflowError(f"BCH2 edge cost {cost!r} does not fit uint32 at scale {scale}")
    return value


def _flatten(rows: tuple[tuple[int, ...], ...]) -> tuple[list[int], list[int]]:
    offsets = [0]
    refs: list[int] = []
    for row in rows:
        refs.extend(row)
        offsets.append(len(refs))
    return offsets, refs


def write_bch2(index: CHIndex, path: Path) -> dict[str, int | float]:
    """Write one metric-specific CH as hot SoA arrays plus cold shortcut arrays."""
    node_count = len(index.rank)
    edge_count = len(index.edges)
    if len(index.upward_out) != node_count or len(index.downward_in) != node_count:
        raise ValueError("CH index CSR rows do not match node count")

    up_offsets, up_refs = _flatten(index.upward_out)
    down_offsets, down_refs = _flatten(index.downward_in)
    scale = weight_scale(index.preference)

    source_offset = HEADER.size
    target_offset = source_offset + edge_count * U32.size
    weight_offset = target_offset + edge_count * U32.size
    original_offset = weight_offset + edge_count * U32.size
    left_offset = original_offset + edge_count * I32.size
    right_offset = left_offset + edge_count * I32.size
    up_offsets_offset = right_offset + edge_count * I32.size
    up_refs_offset = up_offsets_offset + (node_count + 1) * U32.size
    down_offsets_offset = up_refs_offset + len(up_refs) * U32.size
    down_refs_offset = down_offsets_offset + (node_count + 1) * U32.size
    end_offset = down_refs_offset + len(down_refs) * U32.size

    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    try:
        with temp.open("wb") as handle:
            handle.write(
                HEADER.pack(
                    MAGIC,
                    VERSION,
                    node_count,
                    edge_count,
                    len(up_refs),
                    len(down_refs),
                    PREFERENCE_CODE[index.preference],
                    scale,
                    float(index.avoid_penalty),
                    0,
                    source_offset,
                    target_offset,
                    weight_offset,
                    original_offset,
                    left_offset,
                    right_offset,
                    up_offsets_offset,
                    up_refs_offset,
                    down_offsets_offset,
                    down_refs_offset,
                    end_offset,
                )
            )
            for edge in index.edges:
                handle.write(U32.pack(edge.source_index))
            for edge in index.edges:
                handle.write(U32.pack(edge.target_index))
            for edge in index.edges:
                handle.write(U32.pack(quantize_cost(edge.cost, scale)))
            for edge in index.edges:
                handle.write(I32.pack(edge.original_edge_index))
            for edge in index.edges:
                handle.write(I32.pack(edge.left_child))
            for edge in index.edges:
                handle.write(I32.pack(edge.right_child))
            for value in up_offsets:
                handle.write(U32.pack(value))
            for value in up_refs:
                handle.write(U32.pack(value))
            for value in down_offsets:
                handle.write(U32.pack(value))
            for value in down_refs:
                handle.write(U32.pack(value))
        temp.replace(path)
    except BaseException:
        if temp.exists():
            temp.unlink()
        raise

    if path.stat().st_size != end_offset:
        raise RuntimeError("BCH2 file size mismatch after write")
    return {
        "node_count": node_count,
        "edge_count": edge_count,
        "upward_reference_count": len(up_refs),
        "downward_reference_count": len(down_refs),
        "weight_scale": scale,
        "output_bytes": path.stat().st_size,
    }
