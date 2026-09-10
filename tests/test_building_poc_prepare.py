"""Tests that the #120 POC reuses existing building runtime data without rebuilding source datasets."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from prepare_building_poc import MALMO_X, MALMO_Y, prepare  # noqa: E402


def test_prepare_filters_existing_buildings_into_tiles(tmp_path: Path) -> None:
    source = tmp_path / "world_data"
    source.mkdir()
    (source / "manifest.json").write_text(json.dumps({"tile_size": 32000.0}), encoding="utf-8")
    inside = {
        "x": MALMO_X + 50.0,
        "y": MALMO_Y - 50.0,
        "geometry": [{"outer": [[MALMO_X, MALMO_Y], [MALMO_X + 10, MALMO_Y], [MALMO_X + 10, MALMO_Y + 10]], "holes": []}],
        "tags": {"building": "yes"},
    }
    outside = {"x": MALMO_X + 50000.0, "y": MALMO_Y, "geometry": [], "tags": {"building": "yes"}}
    (source / "buildings.jsonl").write_text(
        json.dumps(inside) + "\n" + json.dumps(outside) + "\n",
        encoding="utf-8",
    )

    output = tmp_path / "cache"
    result = prepare(source, output, radius_m=1000.0)

    assert result["source_rebuilt"] is False
    assert result["scanned_records"] == 2
    assert result["selected_records"] == 1
    assert result["tile_count"] == 1
    tile_files = [path for path in output.glob("*.jsonl")]
    assert len(tile_files) == 1
    cached = json.loads(tile_files[0].read_text(encoding="utf-8").strip())
    assert cached["x"] == inside["x"]
    assert cached["y"] == inside["y"]
