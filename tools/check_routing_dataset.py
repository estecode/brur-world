#!/usr/bin/env python3
"""Validate that BRG1/BRS2/BRH1 are one source-aligned routing dataset.

Dependencies:
- Reads routing_stats.json plus the three published routing payloads.
- Uses only the Python standard library.
- Does not inspect Godot/runtime state or rebuild data.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


DATASET_FORMAT = "BRG1+BRS2+BRH1"
PAYLOAD_FILES = (
    "routing.brg",
    "routing_snap.brs",
    "routing_geometry.brh",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_routing_dataset(world_data: Path) -> tuple[bool, str]:
    world_data = Path(world_data)
    stats_path = world_data / "routing_stats.json"
    if not stats_path.is_file():
        return False, f"missing {stats_path.name}"
    try:
        report = json.loads(stats_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        return False, f"invalid routing_stats.json: {error}"
    if report.get("routing_dataset_format") != DATASET_FORMAT:
        return False, "routing dataset format metadata missing or stale"
    expected = report.get("routing_dataset_sha256")
    if not isinstance(expected, dict):
        return False, "routing dataset SHA-256 metadata missing"
    for name in PAYLOAD_FILES:
        path = world_data / name
        if not path.is_file():
            return False, f"missing {name}"
        wanted = expected.get(name)
        if not isinstance(wanted, str) or len(wanted) != 64:
            return False, f"missing SHA-256 for {name}"
        actual = sha256(path)
        if actual != wanted:
            return False, f"SHA-256 mismatch for {name}"
    return True, "ok"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("world_data", type=Path)
    args = parser.parse_args()
    valid, reason = validate_routing_dataset(args.world_data)
    if not valid:
        print(f"ROUTING_DATASET=INVALID {reason}")
        raise SystemExit(1)
    print("ROUTING_DATASET=OK")


if __name__ == "__main__":
    main()
