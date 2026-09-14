"""Verify #220 GeoPackage extraction is staged before BRUR normalization."""
from __future__ import annotations

import json
import shutil
import sqlite3
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import osmium
from shapely.geometry import LineString, Point, Polygon

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path: sys.path.insert(0, str(TOOLS))

import geofabrik_source_cache as source_cache
from area_source_cache import iter_area_facts
from highway_facts import iter_highway_ways
from normalized_source_facts import iter_facts
from source_identity import compute_source_identity


def gpkg_blob(geometry) -> bytes:
    # GeoPackageBinary: GP, version 0, little-endian/no envelope flags, srs_id.
    return b"GP" + bytes((0, 1)) + struct.pack("<i", 4326) + geometry.wkb


def create_table(db: sqlite3.Connection, name: str, columns: str) -> None:
    db.execute(f'CREATE TABLE "{name}" ({columns})')


def make_gpkg(path: Path) -> None:
    db = sqlite3.connect(path)
    create_table(db, "gis_osm_roads_free", "fid INTEGER, geom BLOB, osm_id TEXT, code INTEGER, fclass TEXT, name TEXT, ref TEXT, oneway TEXT, maxspeed INTEGER, layer INTEGER, bridge TEXT, tunnel TEXT")
    db.execute("INSERT INTO gis_osm_roads_free VALUES(?,?,?,?,?,?,?,?,?,?,?,?)", (1, gpkg_blob(LineString([(18.0,59.3),(18.001,59.3),(18.002,59.3)])), "10", 5122, "residential", "Testvägen", "", "B", 30, 0, "F", "F"))
    db.execute("INSERT INTO gis_osm_roads_free VALUES(?,?,?,?,?,?,?,?,?,?,?,?)", (2, gpkg_blob(LineString([(18.001,59.299),(18.001,59.3),(18.001,59.301)])), "11", 5113, "primary", "Bridge", "", "F", 70, 1, "T", "F"))

    create_table(db, "gis_osm_traffic_free", "fid INTEGER, geom BLOB, osm_id TEXT, code INTEGER, fclass TEXT, name TEXT, calming TEXT")
    db.execute("INSERT INTO gis_osm_traffic_free VALUES(?,?,?,?,?,?,?)", (1, gpkg_blob(Point(18.001,59.3)), "100", 5202, "traffic_signals", "", ""))

    create_table(db, "gis_osm_pois_free", "fid INTEGER, geom BLOB, osm_id TEXT, code INTEGER, fclass TEXT, name TEXT")
    db.execute("INSERT INTO gis_osm_pois_free VALUES(?,?,?,?,?,?)", (1, gpkg_blob(Point(18.01,59.31)), "200", 2082, "police", "Fixture Police"))

    create_table(db, "gis_osm_buildings_a_free", "fid INTEGER, geom BLOB, osm_id TEXT, code INTEGER, fclass TEXT, name TEXT, type TEXT")
    building = Polygon([(18.0,59.3),(18.002,59.3),(18.002,59.302),(18.0,59.302),(18.0,59.3)], [[(18.0005,59.3005),(18.001,59.3005),(18.001,59.301),(18.0005,59.301),(18.0005,59.3005)]])
    db.execute("INSERT INTO gis_osm_buildings_a_free VALUES(?,?,?,?,?,?,?)", (1, gpkg_blob(building), "300", 1500, "building", "Fixture", "residential"))
    create_table(db, "gis_osm_adminareas_a_free", "fid INTEGER, geom BLOB, osm_id TEXT, code INTEGER, fclass TEXT, name TEXT")
    admin = Polygon([(17.9,59.2),(18.2,59.2),(18.2,59.5),(17.9,59.5),(17.9,59.2)])
    db.execute("INSERT INTO gis_osm_adminareas_a_free VALUES(?,?,?,?,?,?)", (1, gpkg_blob(admin), "400", 1202, "national", "Sweden"))
    db.commit(); db.close()


FIXTURE = """<?xml version="1.0" encoding="UTF-8"?>
<osm version="0.6">
  <node id="1000" lon="18.0100" lat="59.3100"><tag k="addr:housenumber" v="12"/><tag k="addr:street" v="Testvägen"/><tag k="addr:postcode" v="12345"/></node>
  <node id="1001" lon="17.9000" lat="59.2500"/>
  <node id="1002" lon="17.9500" lat="59.2500"/>
  <way id="500"><nd ref="1001"/><nd ref="1002"/><tag k="natural" v="coastline"/></way>
</osm>
"""


class Copy(osmium.SimpleHandler):
    def __init__(self, writer): super().__init__(); self.writer = writer
    def node(self, value): self.writer.add_node(value)
    def way(self, value): self.writer.add_way(value)
    def relation(self, value): self.writer.add_relation(value)


def make_pbf(root: Path) -> Path:
    xml = root / "fixture.osm"; xml.write_text(FIXTURE, encoding="utf-8")
    pbf = root / "fixture.osm.pbf"
    with osmium.SimpleWriter(str(pbf), overwrite=True) as writer: Copy(writer).apply_file(str(xml))
    return pbf


def copy_supplement(source: Path, destination: Path, **kwargs) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(source, destination); return destination


class Tests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.root = Path(self.temp.name)
        self.gpkg = self.root / "sweden.gpkg"; make_gpkg(self.gpkg)
        self.pbf = make_pbf(self.root); self.cache = self.root / "cache"
    def tearDown(self): self.temp.cleanup()

    def test_geopackage_extraction_writes_separate_opaque_domain_files(self):
        identity = compute_source_identity(self.gpkg)
        staged = source_cache.stage_geopackage(self.gpkg, self.root / "stage", ("highways","traffic_signals","pois","areas"), identity)
        self.assertEqual(set(staged), {"roads","traffic","pois","areas"})
        for domain, path in staged.items():
            self.assertTrue(path.is_file(), domain)
            db = sqlite3.connect(path)
            marker = db.execute("SELECT format,version,domain FROM brur_source_stage").fetchone(); db.close()
            self.assertEqual(marker, (source_cache.STAGE_FORMAT, source_cache.STAGE_VERSION, domain))

    def test_all_routes_normalize_from_gpkg_and_single_staged_supplement(self):
        with mock.patch.object(source_cache, "stage_pyrosm_supplement", side_effect=copy_supplement) as stage:
            outputs = source_cache.build_geofabrik_source_caches(self.gpkg, self.pbf, self.cache, source_cache.ALL_ROUTES)
        self.assertEqual(stage.call_count, 1)
        self.assertEqual(set(outputs), set(source_cache.ALL_ROUTES))

        ways = list(iter_highway_ways(outputs["highways"]))
        self.assertEqual({way.way_id for way in ways}, {10,11})
        residential = next(way for way in ways if way.way_id == 10)
        bridge = next(way for way in ways if way.way_id == 11)
        self.assertEqual(residential.tags["maxspeed"], "30")
        self.assertEqual(bridge.tags["bridge"], "yes")
        # Same crossing coordinate but bridge interior stays grade-separated.
        self.assertNotEqual(residential.node_ids[1], bridge.node_ids[1])

        signals = list(iter_facts(outputs["traffic_signals"], 1))
        self.assertEqual(len(signals), 1)
        self.assertEqual(signals[0]["osm_id"], 100)
        self.assertEqual(signals[0]["way_ids"], [10,11])

        pois = list(iter_facts(outputs["pois"], 1))
        police = next(item for item in pois if item["osm_id"] == 200)
        self.assertEqual(police["tags"]["amenity"], "police")

        addresses = list(iter_facts(outputs["addresses"], 1))
        self.assertEqual(len(addresses), 1)
        self.assertEqual(addresses[0]["tags"]["addr:housenumber"], "12")

        areas = list(iter_area_facts(outputs["areas"]))
        building = next(item for item in areas if item.get("osm_id") == 300)
        self.assertEqual(building["tags"]["building"], "residential")
        self.assertEqual(len(building["geometry"][0]["holes"]), 1)
        self.assertTrue(any(item.get("geometry_type") == "coastline" for item in areas))

        manifest = json.loads((self.cache / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["format"], source_cache.CACHE_FORMAT)
        self.assertEqual(manifest["routes"]["addresses"]["source_identity"]["digest"], compute_source_identity(self.pbf)["digest"])
        self.assertNotEqual(manifest["routes"]["highways"]["source_identity"], manifest["routes"]["addresses"]["source_identity"])

    def test_warm_routes_do_not_repeat_provider_extraction_or_normalization(self):
        with mock.patch.object(source_cache, "stage_pyrosm_supplement", side_effect=copy_supplement):
            source_cache.build_geofabrik_source_caches(self.gpkg, self.pbf, self.cache, source_cache.ALL_ROUTES)
        with mock.patch.object(source_cache, "stage_geopackage", side_effect=AssertionError("unexpected GPKG extraction")), mock.patch.object(source_cache, "stage_pyrosm_supplement", side_effect=AssertionError("unexpected PBF extraction")):
            outputs = source_cache.build_geofabrik_source_caches(self.gpkg, self.pbf, self.cache, source_cache.ALL_ROUTES)
        self.assertTrue(all(path.is_file() for path in outputs.values()))
        run = json.loads((self.cache / "last_run.json").read_text(encoding="utf-8"))
        self.assertTrue(all(run["blocks"][route]["status"] == "CACHE HIT" for route in source_cache.ALL_ROUTES))


if __name__ == "__main__": unittest.main()
