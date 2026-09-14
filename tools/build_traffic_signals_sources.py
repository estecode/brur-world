#!/usr/bin/env python3
"""Build traffic-signal runtime data from normalized source-cache blocks."""
from __future__ import annotations

import json
import time
from datetime import datetime, timezone
from pathlib import Path

from highway_facts import iter_highway_ways, validate_highways
from normalized_source_facts import iter_facts, validate as validate_facts
from traffic_signals import SignalDraft, build_runtime_dataset, save_runtime_dataset
from world_common import project

SIGNAL_SCHEMA = 1


def _now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def _log(message: str) -> None:
    print(f"[{_now()}] [traffic-signals] {message}", flush=True)


def build_traffic_signals_sources(signal_source: Path, highway_source: Path, output: Path) -> dict:
    validate_facts(signal_source, SIGNAL_SCHEMA)
    validate_highways(highway_source)
    output.mkdir(parents=True, exist_ok=True)
    destination = output / "traffic_signals.json"
    started = time.perf_counter()
    _log(f"START signals={signal_source.name} highways={highway_source.name}")

    signals: list[dict] = []
    signal_ids: set[int] = set()
    explicit_memberships = True
    for fact in iter_facts(signal_source, SIGNAL_SCHEMA):
        signal_id = int(fact["osm_id"])
        signal_ids.add(signal_id)
        signals.append(fact)
        if "way_ids" not in fact:
            explicit_memberships = False

    memberships: dict[int, list[int]] = {signal_id: [] for signal_id in signal_ids}
    highway_way_count = 0
    if explicit_memberships:
        for signal in signals:
            signal_id = int(signal["osm_id"])
            memberships[signal_id] = sorted({int(value) for value in signal.get("way_ids", [])})
        _log(f"MEMBERSHIP source=explicit signals={len(signals):,}")
    else:
        # Legacy normalized PBF facts retain OSM node ids in the highway cache,
        # so memberships can be joined by node id exactly as before.
        for index, way in enumerate(iter_highway_ways(highway_source), 1):
            highway_way_count += 1
            way_id = int(way.way_id)
            for node_id in way.node_ids:
                value = int(node_id)
                if value in memberships:
                    memberships[value].append(way_id)
            if index % 250_000 == 0:
                linked = sum(1 for values in memberships.values() if values)
                _log(f"PROGRESS highway-facts={index:,} linked-signals={linked:,}")

    drafts: list[SignalDraft] = []
    for signal in signals:
        x, y = project(float(signal["lon"]), float(signal["lat"]))
        signal_id = int(signal["osm_id"])
        drafts.append(
            SignalDraft(
                signal_id,
                x,
                y,
                {str(k): str(v) for k, v in signal.get("tags", {}).items()},
                tuple(sorted(set(memberships.get(signal_id, [])))),
            )
        )

    dataset = build_runtime_dataset(drafts)
    save_runtime_dataset(destination, dataset)
    stats = dict(dataset["stats"])
    stats.update({
        "output_bytes": destination.stat().st_size,
        "build_seconds": round(time.perf_counter() - started, 3),
        "source_node_count": len(signals),
        "source_way_count": highway_way_count,
        "source_cache_blocks": [signal_source.name, highway_source.name],
        "membership_source": "explicit" if explicit_memberships else "highway_node_join",
    })
    manifest_path = output / "manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.is_file() else {}
    except (OSError, json.JSONDecodeError):
        manifest = {}
    manifest["traffic_signals"] = {
        "format": dataset["format"],
        "file": destination.name,
        "source_cache_blocks": [signal_source.name, highway_source.name],
        "source_signal_count": stats["source_signal_count"],
        "exported_signal_count": stats["exported_signal_count"],
        "membership_source": stats["membership_source"],
    }
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    _log(
        f"DONE source={stats['source_signal_count']:,} exported={stats['exported_signal_count']:,} "
        f"bytes={stats['output_bytes']:,} elapsed={stats['build_seconds']:.2f}s"
    )
    return stats
