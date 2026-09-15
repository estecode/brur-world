#!/usr/bin/env python3
"""Build a disposable multi-resolution far-view cache from a GeoPackage spatial index.

The GeoPackage remains authoritative. This artifact stores only presentation aggregates
(count, bbox coverage proxy, and largest source bbox span) so high-altitude rendering
never has to materialize every building feature.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
from collections import defaultdict
from pathlib import Path

SCHEMA = 1
LEVEL_MULTIPLIERS = (1, 2, 4, 8, 16, 32, 64)


def q(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def source_identity(path: Path, con: sqlite3.Connection, rtree: str) -> dict[str, object]:
    stat = path.stat()
    count, min_x, min_y, max_x, max_y = con.execute(
        f"select count(*), min(minx), min(miny), max(maxx), max(maxy) from {q(rtree)}"
    ).fetchone()
    stable = json.dumps([stat.st_size, count, min_x, min_y, max_x, max_y], separators=(",", ":"))
    return {
        "size_bytes": stat.st_size,
        "building_features": int(count),
        "bounds": [min_x, min_y, max_x, max_y],
        "fingerprint": hashlib.sha256(stable.encode()).hexdigest()[:24],
    }


def find_building_rtree(con: sqlite3.Connection) -> str:
    rows = con.execute(
        "select g.table_name, g.column_name from gpkg_geometry_columns g "
        "join gpkg_contents c on c.table_name=g.table_name "
        "where c.data_type='features' and upper(g.geometry_type_name) like '%POLYGON%' "
        "order by case when lower(g.table_name) in ('buildings','building','multipolygons') then 0 else 1 end, g.table_name"
    ).fetchall()
    tables = {str(row[0]).lower(): str(row[0]) for row in con.execute("select name from sqlite_master where type='table'")}
    for table, geom in rows:
        expected = f"rtree_{table}_{geom}"
        if expected.lower() in tables:
            return tables[expected.lower()]
    raise SystemExit("GEODOT_FAR_CACHE=FAIL no polygon feature RTree")


def aggregate(rows, cell_m: float) -> dict[tuple[int, int], list[float]]:
    cells: dict[tuple[int, int], list[float]] = defaultdict(lambda: [0.0, 0.0, 0.0])
    for min_x, max_x, min_y, max_y in rows:
        width = max(0.0, float(max_x) - float(min_x))
        depth = max(0.0, float(max_y) - float(min_y))
        cx = (float(min_x) + float(max_x)) * 0.5
        cy = (float(min_y) + float(max_y)) * 0.5
        key = (int(cx // cell_m), int(cy // cell_m))
        value = cells[key]
        value[0] += 1.0
        value[1] += min(width * depth, cell_m * cell_m)
        value[2] = max(value[2], width, depth)
    return cells


def collapse(base: dict[tuple[int, int], list[float]], multiplier: int) -> dict[tuple[int, int], list[float]]:
    if multiplier == 1:
        return base
    result: dict[tuple[int, int], list[float]] = defaultdict(lambda: [0.0, 0.0, 0.0])
    for (x, y), value in base.items():
        key = (x // multiplier, y // multiplier)
        target = result[key]
        target[0] += value[0]
        target[1] += value[1]
        target[2] = max(target[2], value[2])
    return result


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("gpkg", type=Path)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--base-cell-m", type=float, default=2000.0)
    args = ap.parse_args()
    if not args.gpkg.is_file():
        raise SystemExit(f"GEODOT_FAR_CACHE=FAIL missing {args.gpkg}")
    con = sqlite3.connect(f"file:{args.gpkg}?mode=ro", uri=True)
    try:
        rtree = find_building_rtree(con)
        identity = source_identity(args.gpkg, con, rtree)
        rows = con.execute(f"select minx,maxx,miny,maxy from {q(rtree)}")
        base = aggregate(rows, args.base_cell_m)
    finally:
        con.close()
    levels = []
    for multiplier in LEVEL_MULTIPLIERS:
        cell_m = args.base_cell_m * multiplier
        cells = collapse(base, multiplier)
        packed = [[x, y, int(v[0]), round(v[1], 2), round(v[2], 2)] for (x, y), v in sorted(cells.items())]
        levels.append({"cell_m": cell_m, "cells": packed})
    payload = {"schema": SCHEMA, "source": identity, "base_cell_m": args.base_cell_m, "levels": levels}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temp = args.output.with_suffix(args.output.suffix + ".tmp")
    temp.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
    temp.replace(args.output)
    print(f"GEODOT_FAR_CACHE=OK output={args.output} levels={len(levels)} base_cells={len(base)} fingerprint={identity['fingerprint']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
