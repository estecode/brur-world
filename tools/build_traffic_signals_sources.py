#!/usr/bin/env python3
"""Build traffic-signal runtime data from independent source-cache blocks.

Signal-node facts come from the traffic_signals cache. Highway membership comes
from the shared highways cache so traffic does not need a combined source file.
The portable traffic-signals domain model remains the semantic owner.
"""

from __future__ import annotations

import json
import time
from datetime import datetime, timezone
from pathlib import Path

from build_traffic_signals import _pbf_memberships, _pbf_signals
from traffic_signals import SignalDraft, build_runtime_dataset, save_runtime_dataset
from world_common import ensure_pbf, project


def _now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def _log(message: str) -> None:
    print(f"[{_now()}] [traffic-signals] {message}", flush=True)


def build_traffic_signals_sources(signal_source: Path, highway_source: Path, output: Path) -> dict:
    ensure_pbf(signal_source)
    ensure_pbf(highway_source)
    output.mkdir(parents=True, exist_ok=True)
    destination = output / "traffic_signals.json"
    started = time.perf_counter()

    _log(f"START signals={signal_source.name} highways={highway_source.name}")
    signals, signal_node_count = _pbf_signals(signal_source)
    memberships, highway_way_count = _pbf_memberships(
        highway_source,
        {signal.osm_id for signal in signals},
    )

    drafts: list[SignalDraft] = []
    for signal in signals:
        x, y = project(signal.lon, signal.lat)
        drafts.append(
            SignalDraft(
                signal.osm_id,
                x,
                y,
                signal.tags,
                tuple(sorted(set(memberships.get(signal.osm_id, [])))),
            )
        )

    dataset = build_runtime_dataset(drafts)
    save_runtime_dataset(destination, dataset)
    stats = dict(dataset["stats"])
    stats.update({
        "output_bytes": destination.stat().st_size,
        "build_seconds": round(time.perf_counter() - started, 3),
        "source_node_count": signal_node_count,
        "source_way_count": highway_way_count,
        "source_cache_blocks": [signal_source.name, highway_source.name],
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
    }
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    _log(
        f"DONE source={stats['source_signal_count']:,} exported={stats['exported_signal_count']:,} "
        f"bytes={stats['output_bytes']:,} elapsed={stats['build_seconds']:.2f}s"
    )
    return stats
