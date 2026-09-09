"""Normalize and serialize static traffic-signal world facts.

Dependencies:
- Pure Python domain/data normalization for the offline pipeline.
- Does not depend on Godot, rendering, runtime traffic state, or PBF APIs.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Iterable

FORMAT = "BTS1"
SUPPORTED_DIRECTIONS = {"forward", "backward", "both"}


class DirectionSource(str, Enum):
    EXPLICIT = "explicit"
    LEGACY = "legacy"
    INFERRED = "inferred"
    UNKNOWN = "unknown"


@dataclass(frozen=True)
class SignalDraft:
    osm_id: int
    x: float
    y: float
    tags: dict[str, str]
    highway_way_ids: tuple[int, ...] = ()


def _normalize_direction(tags: dict[str, str]) -> tuple[str | None, DirectionSource]:
    explicit = tags.get("traffic_signals:direction", "").strip().lower()
    if explicit in SUPPORTED_DIRECTIONS:
        return explicit, DirectionSource.EXPLICIT

    legacy = tags.get("direction", "").strip().lower()
    if legacy in {"forward", "backward"}:
        return legacy, DirectionSource.LEGACY

    return None, DirectionSource.UNKNOWN


def _signal_type(tags: dict[str, str]) -> str | None:
    value = tags.get("traffic_signals", "").strip()
    return value or None


def _candidate_id(draft: SignalDraft) -> str | None:
    # A signal node that belongs to multiple highway ways is an explicit topology
    # junction candidate. Single-way approach signals remain ungrouped until #93,
    # which has the geometry needed to group nearby approaches safely.
    if len(draft.highway_way_ids) < 2:
        return None
    return f"junction-node:{draft.osm_id}"


def _record(draft: SignalDraft) -> dict:
    direction, direction_source = _normalize_direction(draft.tags)
    return {
        "id": f"n{draft.osm_id}",
        "osm_node_id": draft.osm_id,
        "x": draft.x,
        "y": draft.y,
        "highway_way_ids": list(draft.highway_way_ids),
        "direction": direction,
        "direction_source": direction_source.value,
        "explicit_stop_line": draft.tags.get("road_marking") == "stop_line",
        "signal_type": _signal_type(draft.tags),
        "crossing": draft.tags.get("crossing"),
        "bicycle": draft.tags.get("bicycle") or draft.tags.get("traffic_signals:bicycle"),
        "pedestrian": draft.tags.get("foot") or draft.tags.get("traffic_signals:foot"),
        "group_candidate_id": _candidate_id(draft),
    }


def build_runtime_dataset(drafts: Iterable[SignalDraft]) -> dict:
    ordered = sorted(drafts, key=lambda item: item.osm_id)
    records = [_record(draft) for draft in ordered]
    source_counts = {source.value: 0 for source in DirectionSource}
    for record in records:
        source_counts[record["direction_source"]] += 1

    return {
        "format": FORMAT,
        "signals": records,
        "stats": {
            "source_signal_count": len(ordered),
            "exported_signal_count": len(records),
            "explicit_direction_count": source_counts[DirectionSource.EXPLICIT.value],
            "legacy_direction_count": source_counts[DirectionSource.LEGACY.value],
            "inferred_direction_count": source_counts[DirectionSource.INFERRED.value],
            "unknown_direction_count": source_counts[DirectionSource.UNKNOWN.value],
            "explicit_stop_line_count": sum(1 for record in records if record["explicit_stop_line"]),
            "grouped_candidate_count": sum(1 for record in records if record["group_candidate_id"] is not None),
            "ungrouped_candidate_count": sum(1 for record in records if record["group_candidate_id"] is None),
        },
    }


def save_runtime_dataset(path: Path, dataset: dict) -> None:
    if dataset.get("format") != FORMAT:
        raise ValueError(f"unsupported traffic-signal format: {dataset.get('format')!r}")
    path.write_text(json.dumps(dataset, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


def load_runtime_dataset(path: Path) -> dict:
    dataset = json.loads(path.read_text(encoding="utf-8"))
    if dataset.get("format") != FORMAT:
        raise ValueError(f"unsupported traffic-signal format: {dataset.get('format')!r}")
    signals = dataset.get("signals")
    if not isinstance(signals, list):
        raise ValueError("traffic-signal dataset is missing signals")
    return dataset
