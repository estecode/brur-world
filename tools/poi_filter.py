"""Select gameplay-relevant POIs for runtime tiles.

Dependencies:
- Pure Python and OSM tag dictionaries only.
- Used by the offline world build; runtime code does not make relevance decisions.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class PoiRule:
    key: str
    values: frozenset[str]
    category: str


# Curated gameplay set, defined locally for brur-world. The old Syndicate POI
# selection was used only as a textual reference; no Syndicate code is shared.
RUNTIME_POI_RULES = (
    PoiRule("amenity", frozenset({"police"}), "police"),
    PoiRule("amenity", frozenset({"fire_station"}), "fire_station"),
    PoiRule("amenity", frozenset({"hospital", "clinic", "doctors", "pharmacy"}), "healthcare"),
    PoiRule("healthcare", frozenset({"hospital", "clinic", "doctor", "pharmacy"}), "healthcare"),
    PoiRule("emergency", frozenset({"ambulance_station"}), "ambulance_station"),
    PoiRule("amenity", frozenset({"fuel", "charging_station"}), "fuel"),
    PoiRule("amenity", frozenset({"parking", "parking_entrance"}), "parking"),
    PoiRule("amenity", frozenset({"bank", "atm"}), "money"),
    PoiRule("amenity", frozenset({"restaurant", "fast_food", "cafe", "bar", "pub"}), "food"),
    PoiRule("shop", frozenset({"supermarket", "convenience", "mall", "department_store"}), "shopping"),
    PoiRule("shop", frozenset({"car", "car_repair", "tyres", "bicycle"}), "vehicle_service"),
    PoiRule("tourism", frozenset({"hotel", "motel", "hostel"}), "lodging"),
    PoiRule("tourism", frozenset({"attraction", "museum", "viewpoint"}), "attraction"),
    PoiRule("amenity", frozenset({"school", "college", "university", "kindergarten"}), "education"),
    PoiRule("railway", frozenset({"station", "halt"}), "transit"),
    PoiRule("public_transport", frozenset({"station"}), "transit"),
    PoiRule("highway", frozenset({"services", "rest_area"}), "road_service"),
    PoiRule("highway", frozenset({"speed_camera"}), "speed_camera"),
)


def runtime_poi_category(tags: dict[str, str]) -> str | None:
    """Return the deterministic runtime category, or None when excluded."""
    for rule in RUNTIME_POI_RULES:
        if tags.get(rule.key) in rule.values:
            return rule.category
    return None


def excluded_poi_category(tags: dict[str, str]) -> str:
    """Return a stable summary bucket for a POI rejected from runtime tiles."""
    for key in (
        "amenity", "shop", "tourism", "leisure", "office", "healthcare", "emergency",
        "public_transport", "railway", "aeroway", "craft", "historic", "sport", "club",
        "man_made", "information", "advertising", "highway", "enforcement", "surveillance",
    ):
        value = tags.get(key)
        if value:
            return f"{key}:{value}"
    if any(key.startswith("camera:") for key in tags):
        return "camera:*"
    return "other"
