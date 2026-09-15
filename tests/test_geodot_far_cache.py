#!/usr/bin/env python3
from __future__ import annotations
import json
import sqlite3
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory() as td:
    td = Path(td)
    gpkg = td / "fixture.gpkg"
    con = sqlite3.connect(gpkg)
    con.executescript("""
    create table gpkg_contents(table_name text, data_type text);
    create table gpkg_geometry_columns(table_name text, column_name text, geometry_type_name text);
    create table buildings(id integer primary key, geom blob);
    create table rtree_buildings_geom(id integer, minx real, maxx real, miny real, maxy real);
    insert into gpkg_contents values('buildings','features');
    insert into gpkg_geometry_columns values('buildings','geom','MULTIPOLYGON');
    insert into rtree_buildings_geom values(1,0,10,0,20),(2,100,120,100,130),(3,5000,5400,5000,5100);
    """)
    con.commit(); con.close()
    a = td / "a.json"; b = td / "b.json"
    cmd = ["python3", str(ROOT / "tools/build_geodot_far_cache.py"), str(gpkg), "--output"]
    subprocess.run(cmd + [str(a)], check=True)
    subprocess.run(cmd + [str(b)], check=True)
    assert a.read_bytes() == b.read_bytes()
    payload = json.loads(a.read_text())
    assert payload["schema"] == 1
    assert payload["source"]["building_features"] == 3
    assert len(payload["levels"]) == 7
    assert sum(cell[2] for cell in payload["levels"][0]["cells"]) == 3
    assert max(cell[4] for cell in payload["levels"][0]["cells"]) == 400.0
print("GEODOT_FAR_CACHE_TEST=PASS")
