#!/usr/bin/env python3
"""Inspect the real GeoPackage contract used by the GeoDot POC without loading render code."""
from __future__ import annotations
import argparse, json, sqlite3, time
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("gpkg", type=Path)
    args = ap.parse_args()
    if not args.gpkg.is_file():
        raise SystemExit(f"missing GeoPackage: {args.gpkg}")
    t0 = time.perf_counter()
    con = sqlite3.connect(f"file:{args.gpkg}?mode=ro", uri=True)
    try:
        contents = con.execute("select table_name, data_type, srs_id from gpkg_contents order by table_name").fetchall()
        geometry = con.execute("select table_name, column_name, geometry_type_name, srs_id from gpkg_geometry_columns order by table_name").fetchall()
        rtrees = [r[0] for r in con.execute("select name from sqlite_master where type='table' and name like 'rtree_%' order by name")]
        indexes = [r[0] for r in con.execute("select name from sqlite_master where type='index' order by name")]
    finally:
        con.close()
    names = {r[0].lower() for r in contents}
    building_candidates = [n for n in names if "building" in n or n == "multipolygons"]
    road_candidates = [n for n in names if "road" in n or n == "lines"]
    if not building_candidates:
        raise SystemExit("GEODOT_GPKG=FAIL no building-like feature layer")
    if not road_candidates:
        raise SystemExit("GEODOT_GPKG=FAIL no road/line feature layer")
    report = {
        "path": str(args.gpkg),
        "size_bytes": args.gpkg.stat().st_size,
        "open_ms": round((time.perf_counter() - t0) * 1000, 2),
        "contents": contents,
        "geometry_columns": geometry,
        "rtree_count": len(rtrees),
        "rtree_tables": rtrees,
        "index_count": len(indexes),
        "building_candidates": building_candidates,
        "road_candidates": road_candidates,
    }
    print("GEODOT_GPKG=OK " + json.dumps(report, ensure_ascii=False))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
