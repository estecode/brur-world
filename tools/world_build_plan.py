"""Small directed build planner for Sweden offline targets.

This module owns orchestration metadata only. Dataset semantics remain in their
existing builders and source-cache owners.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

PLAN_VERSION = 4
STATE_FILE = "build_state.json"
TARGET_SOURCES: dict[str, tuple[str, ...]] = {
    "roads": ("highways",),
    "routing": ("highways",),
    "traffic": ("traffic_signals", "highways"),
    "background": ("areas",),
    "pois": ("pois", "areas"),
    "buildings": ("areas",),
    "search": ("addresses",),
}
TARGET_ORDER = tuple(TARGET_SOURCES)
TARGET_OUTPUTS: dict[str, tuple[str, ...]] = {
    "roads": ("lod0", "lod1", "lod2", "road_surfaces"),
    "routing": ("routing.brg", "routing_geometry.brh", "routing_snap.brs", "routing_stats.json"),
    "traffic": ("traffic_signals.json",),
    "background": ("background.brmap",),
    "pois": ("pois.jsonl", "poi_tiles", "city_light_density.jsonl"),
    "buildings": ("buildings.jsonl", "building_mesh_lod"),
    "search": ("search_index.bsi",),
}
TARGET_BUILDERS: dict[str, tuple[str, ...]] = {
    "roads": ("build_roads.py", "road_surface_mesh.py", "normalized_source_facts.py"),
    "routing": ("build_routing_dataset.py", "build_routing.py", "routing_graph.py", "normalized_source_facts.py"),
    "traffic": ("build_traffic_signals.py", "build_traffic_signals_sources.py", "normalized_source_facts.py"),
    "background": ("build_background.py", "build_background_sources.py", "area_source_cache.py"),
    "pois": ("build_features.py", "poi_filter.py", "build_city_light_density.py", "area_source_cache.py", "normalized_source_facts.py"),
    "buildings": ("build_features.py", "build_building_mesh_pyramid.py", "area_source_cache.py"),
    "search": ("build_search_index.py", "build_search_binary.py", "normalized_source_facts.py"),
}


@dataclass(frozen=True)
class PlanItem:
    target: str
    status: str
    reason: str
    fingerprint: str | None


def parse_targets(value: str) -> tuple[str, ...]:
    requested = [part.strip() for part in value.split(",") if part.strip()]
    if not requested or requested == ["all"]:
        return TARGET_ORDER
    unknown = [name for name in requested if name not in TARGET_SOURCES]
    if unknown:
        raise ValueError(f"unknown build target(s): {', '.join(unknown)}")
    selected = set(requested)
    return tuple(name for name in TARGET_ORDER if name in selected)


def required_source_routes(targets: tuple[str, ...]) -> tuple[str, ...]:
    routes: list[str] = []
    for target in targets:
        for route in TARGET_SOURCES[target]:
            if route not in routes:
                routes.append(route)
    return tuple(routes)


def load_state(world_dir: Path) -> dict:
    path = world_dir / STATE_FILE
    if not path.is_file():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) and value.get("version") == PLAN_VERSION else {}


def save_state(world_dir: Path, state: dict) -> None:
    path = world_dir / STATE_FILE
    temp = path.with_suffix(".json.tmp")
    temp.write_text(json.dumps(state, indent=2, sort_keys=True), encoding="utf-8")
    temp.replace(path)


def _builder_digest(tools_dir: Path, target: str) -> str:
    digest = hashlib.sha256()
    for filename in TARGET_BUILDERS[target]:
        path = tools_dir / filename
        digest.update(filename.encode("utf-8"))
        digest.update(path.read_bytes())
    return digest.hexdigest()


def _source_artifact_valid(cache_dir: Path | None, route: str, entry: dict) -> bool:
    if cache_dir is None:
        return True
    filename = entry.get("file")
    checksum = entry.get("sha256")
    if not isinstance(filename, str) or not filename.endswith((".brfacts", ".baf")):
        return False
    if not isinstance(checksum, str) or len(checksum) != 64:
        return False
    path = cache_dir / filename
    if not path.is_file():
        return False
    expected_size = entry.get("size_bytes")
    if not isinstance(expected_size, int) or expected_size <= 0 or path.stat().st_size != expected_size:
        return False
    return True


def target_fingerprint(tools_dir: Path, source_manifest: dict, target: str, source_cache_dir: Path | None = None) -> str | None:
    routes = source_manifest.get("routes")
    source = source_manifest.get("source")
    if not isinstance(routes, dict) or not isinstance(source, dict):
        return None
    dependencies: dict[str, object] = {}
    for route in TARGET_SOURCES[target]:
        entry = routes.get(route)
        if not isinstance(entry, dict) or entry.get("complete") is not True:
            return None
        if not _source_artifact_valid(source_cache_dir, route, entry):
            return None
        route_source = entry.get("source_identity") if isinstance(entry.get("source_identity"), dict) else source
        dependencies[route] = {
            "version": entry.get("version"),
            "extractor_version": entry.get("extractor_version"),
            "file": entry.get("file"),
            "size_bytes": entry.get("size_bytes"),
            "sha256": entry.get("sha256"),
            "source_identity": route_source,
        }
    payload = {
        "plan_version": PLAN_VERSION,
        "target": target,
        "dependencies": dependencies,
        "builder_sha256": _builder_digest(tools_dir, target),
    }
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def outputs_exist(world_dir: Path, target: str) -> bool:
    for relative in TARGET_OUTPUTS[target]:
        path = world_dir / relative
        if not path.exists():
            return False
        if path.is_file() and path.stat().st_size == 0:
            return False
        if path.is_dir() and next(path.iterdir(), None) is None:
            return False
    return True


def target_output_bytes(world_dir: Path, target: str) -> int:
    total = 0
    for relative in TARGET_OUTPUTS[target]:
        path = world_dir / relative
        if path.is_file():
            total += path.stat().st_size
        elif path.is_dir():
            total += sum(child.stat().st_size for child in path.rglob("*") if child.is_file())
    return total


def make_plan(tools_dir: Path, world_dir: Path, source_manifest: dict, requested: tuple[str, ...], source_cache_dir: Path | None = None) -> tuple[PlanItem, ...]:
    state = load_state(world_dir)
    target_state = state.get("targets", {}) if isinstance(state.get("targets"), dict) else {}
    requested_set = set(requested)
    items: list[PlanItem] = []
    for target in TARGET_ORDER:
        if target not in requested_set:
            items.append(PlanItem(target, "SKIP", "not requested", None))
            continue
        fingerprint = target_fingerprint(tools_dir, source_manifest, target, source_cache_dir)
        if fingerprint is None:
            items.append(PlanItem(target, "BLOCKED", "source dependency missing/incomplete", None))
            continue
        old = target_state.get(target)
        if isinstance(old, dict) and old.get("fingerprint") == fingerprint and outputs_exist(world_dir, target):
            items.append(PlanItem(target, "CACHE HIT", "compatible fingerprint", fingerprint))
        elif not outputs_exist(world_dir, target):
            items.append(PlanItem(target, "REBUILD", "output missing/incomplete", fingerprint))
        else:
            items.append(PlanItem(target, "REBUILD", "dependency/builder fingerprint changed", fingerprint))
    return tuple(items)


def record_target(world_dir: Path, target: str, fingerprint: str, elapsed_s: float) -> None:
    state = load_state(world_dir)
    targets = dict(state.get("targets", {})) if isinstance(state.get("targets"), dict) else {}
    targets[target] = {"fingerprint": fingerprint, "complete": True, "elapsed_s": elapsed_s}
    save_state(world_dir, {"version": PLAN_VERSION, "targets": targets})
