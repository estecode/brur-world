"""Tests for the offline runtime POI allowlist.

Dependencies:
- Imports the pure Python POI filter from tools.
- Uses synthetic OSM tag dictionaries; no Godot or PBF data is required.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from poi_filter import excluded_poi_category, runtime_poi_category


def test_allowed_gameplay_pois_are_categorized() -> None:
    cases = {
        "police": {"amenity": "police", "name": "Polisen"},
        "fire_station": {"amenity": "fire_station"},
        "healthcare": {"amenity": "hospital"},
        "ambulance_station": {"emergency": "ambulance_station"},
        "fuel": {"amenity": "fuel"},
        "shopping": {"shop": "supermarket"},
        "vehicle_service": {"shop": "car_repair"},
        "lodging": {"tourism": "hotel"},
        "transit": {"railway": "station"},
        "road_service": {"highway": "rest_area"},
        "speed_camera": {"highway": "speed_camera"},
    }
    for expected, tags in cases.items():
        assert runtime_poi_category(tags) == expected


def test_irrelevant_pois_are_excluded() -> None:
    assert runtime_poi_category({"amenity": "bench"}) is None
    assert runtime_poi_category({"shop": "hairdresser"}) is None
    assert runtime_poi_category({"office": "company"}) is None
    assert runtime_poi_category({"advertising": "billboard"}) is None


def test_category_mapping_is_deterministic_for_borderline_tags() -> None:
    tags = {"amenity": "hospital", "tourism": "museum", "name": "Mixed use"}
    assert runtime_poi_category(tags) == "healthcare"
    assert runtime_poi_category(dict(reversed(list(tags.items())))) == "healthcare"


def test_special_cases_are_deliberate() -> None:
    assert runtime_poi_category({"amenity": "charging_station"}) == "fuel"
    assert runtime_poi_category({"public_transport": "platform"}) is None
    assert runtime_poi_category({"highway": "bus_stop"}) is None
    assert runtime_poi_category({"surveillance": "public"}) is None


def test_excluded_summary_bucket_is_stable() -> None:
    assert excluded_poi_category({"amenity": "bench", "name": "Bench"}) == "amenity:bench"
    assert excluded_poi_category({"camera:type": "fixed"}) == "camera:*"


def test_filter_does_not_mutate_raw_tags() -> None:
    tags = {"amenity": "hospital", "name": "Example", "addr:street": "Main"}
    before = dict(tags)
    assert runtime_poi_category(tags) == "healthcare"
    assert tags == before
