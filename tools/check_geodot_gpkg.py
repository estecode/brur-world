#!/usr/bin/env python3
"""Inspect the GeoPackage contract used by the GeoDot POC without loading render code."""
from __future__ import annotations

import argparse
import json
import sqlite3
import time
from pathlib import Path


def quote_identifier(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def choose_layer(names: list[str], exact: tuple[str, ...], fallback: str) -> str:
    by_lower = {name.lower(): name for name in names}
    for candidate in exact:
        if candidate in by_lower:
            return by_lower[candidate]
    for name in names:
        if fallback in name.lower():
            return name
    return ""


def table_columns(con: sqlite3.Connection, table: str) -> list[str]:
    return [str(row[1]) for row in con.execute(f"pragma table_info({quote_identifier(table)})")]


def timed_scalar(con: sqlite3.Connection, sql: str) -> tuple[int, float]:
    started = time.perf_counter()
    value = int(con.execute(sql).fetchone()[0])
    return value, round((time.perf_counter() - started) * 1000.0, 3)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("gpkg", type=Path)
    args = ap.parse_args()
    if not args.gpkg.is_file():
        raise SystemExit(f"missing GeoPackage: {args.gpkg}")

    opened = time.perf_counter()
    con = sqlite3.connect(f"file:{args.gpkg}?mode=ro", uri=True)
    try:
        contents = con.execute(
            "select table_name, data_type, srs_id, min_x, min_y, max_x, max_y "
            "from gpkg_contents order by table_name"
        ).fetchall()
        geometry = con.execute(
            "select table_name, column_name, geometry_type_name, srs_id "
            "from gpkg_geometry_columns order by table_name"
        ).fetchall()
        feature_names = [str(row[0]) for row in contents if str(row[1]).lower() == "features"]
        building_layer = choose_layer(feature_names, ("buildings", "building", "multipolygons"), "building")
        road_layer = choose_layer(feature_names, ("roads", "road", "lines"), "road")
        if not building_layer and "multipolygons" in {name.lower() for name in feature_names}:
            building_layer = next(name for name in feature_names if name.lower() == "multipolygons")
        if not road_layer and "lines" in {name.lower() for name in feature_names}:
            road_layer = next(name for name in feature_names if name.lower() == "lines")
        if not building_layer:
            raise SystemExit("GEODOT_GPKG=FAIL no building-like feature layer")
        if not road_layer:
            raise SystemExit("GEODOT_GPKG=FAIL no road/line feature layer")

        geometry_by_table = {str(row[0]): row for row in geometry}
        if building_layer not in geometry_by_table or road_layer not in geometry_by_table:
            raise SystemExit("GEODOT_GPKG=FAIL selected feature layer lacks gpkg_geometry_columns metadata")
        building_geom = geometry_by_table[building_layer]
        road_geom = geometry_by_table[road_layer]
        if "POLYGON" not in str(building_geom[2]).upper():
            raise SystemExit(f"GEODOT_GPKG=FAIL building layer geometry is {building_geom[2]!r}, expected polygon")
        if "LINE" not in str(road_geom[2]).upper():
            raise SystemExit(f"GEODOT_GPKG=FAIL road layer geometry is {road_geom[2]!r}, expected line")
        if int(building_geom[3]) <= 0 or int(road_geom[3]) <= 0:
            raise SystemExit("GEODOT_GPKG=FAIL selected feature CRS is missing/invalid")
        if int(building_geom[3]) != int(road_geom[3]):
            raise SystemExit("GEODOT_GPKG=FAIL building and road feature layers use different CRS")

        building_columns = table_columns(con, building_layer)
        road_columns = table_columns(con, road_layer)
        building_lower = {value.lower() for value in building_columns}
        road_lower = {value.lower() for value in road_columns}
        if "building" not in building_lower and not ({"tags", "other_tags"} & building_lower):
            raise SystemExit("GEODOT_GPKG=FAIL building layer exposes neither building nor tags/other_tags")
        if "highway" not in road_lower and not ({"tags", "other_tags"} & road_lower):
            raise SystemExit("GEODOT_GPKG=FAIL road layer exposes neither highway nor tags/other_tags")

        rtrees = [
            str(row[0])
            for row in con.execute(
                "select name from sqlite_master where type='table' and name like 'rtree_%' order by name"
            )
        ]
        rtree_lower = {name.lower(): name for name in rtrees}
        building_rtree_expected = f"rtree_{building_layer}_{building_geom[1]}"
        road_rtree_expected = f"rtree_{road_layer}_{road_geom[1]}"
        building_rtree = rtree_lower.get(building_rtree_expected.lower(), "")
        road_rtree = rtree_lower.get(road_rtree_expected.lower(), "")
        if not building_rtree:
            raise SystemExit(f"GEODOT_GPKG=FAIL missing spatial index {building_rtree_expected}")
        if not road_rtree:
            raise SystemExit(f"GEODOT_GPKG=FAIL missing spatial index {road_rtree_expected}")

        building_count, building_count_ms = timed_scalar(
            con, f"select count(*) from {quote_identifier(building_rtree)}"
        )
        road_count, road_count_ms = timed_scalar(
            con, f"select count(*) from {quote_identifier(road_rtree)}"
        )
        if building_count <= 0 or road_count <= 0:
            raise SystemExit("GEODOT_GPKG=FAIL selected spatial index is empty")

        indexes = [
            str(row[0])
            for row in con.execute("select name from sqlite_master where type='index' order by name")
        ]
        report = {
            "path": str(args.gpkg),
            "size_bytes": args.gpkg.stat().st_size,
            "open_ms": round((time.perf_counter() - opened) * 1000.0, 2),
            "contents": contents,
            "geometry_columns": geometry,
            "selected": {
                "building_layer": building_layer,
                "building_geometry": str(building_geom[2]),
                "building_columns": building_columns,
                "building_rtree": building_rtree,
                "building_rtree_features": building_count,
                "building_rtree_count_ms": building_count_ms,
                "road_layer": road_layer,
                "road_geometry": str(road_geom[2]),
                "road_columns": road_columns,
                "road_rtree": road_rtree,
                "road_rtree_features": road_count,
                "road_rtree_count_ms": road_count_ms,
                "epsg": int(building_geom[3]),
            },
            "rtree_count": len(rtrees),
            "rtree_tables": rtrees,
            "index_count": len(indexes),
        }
    finally:
        con.close()

    print("GEODOT_GPKG=OK " + json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
