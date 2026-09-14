"""Verify #220 reads the BRUR GDAL/OSM GeoPackage directly with dual source identity."""
from __future__ import annotations

import json
import sqlite3
import struct
import sys
import tempfile
import unittest
from pathlib import Path

from shapely.geometry import LineString, Point, Polygon

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path: sys.path.insert(0, str(TOOLS))

import osm_gpkg_source_cache as source_cache
from area_source_cache import iter_area_facts
from highway_facts import iter_highway_ways
from normalized_source_facts import iter_facts


def gpkg_blob(geometry) -> bytes:
    return b"GP" + bytes((0, 1)) + struct.pack("<i", 4326) + geometry.wkb


def create_table(db: sqlite3.Connection, name: str, columns: str) -> None:
    db.execute(f'CREATE TABLE "{name}" ({columns})')


def make_gpkg(path: Path) -> None:
    db = sqlite3.connect(path)
    create_table(db, "points", "osm_id TEXT, name TEXT, highway TEXT, amenity TEXT, shop TEXT, tourism TEXT, railway TEXT, addr_housenumber TEXT, addr_street TEXT, addr_place TEXT, addr_postcode TEXT, addr_city TEXT, addr_suburb TEXT, other_tags TEXT, geom BLOB")
    db.execute("INSERT INTO points VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", ("100", "Signal", "traffic_signals", None, None, None, None, None, None, None, None, None, None, None, gpkg_blob(Point(18.001,59.3))))
    db.execute("INSERT INTO points VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", ("200", "Police", None, "police", None, None, None, "12", "Testvägen", None, "12345", "Stockholm", None, None, gpkg_blob(Point(18.01,59.31))))

    create_table(db, "lines", "osm_id TEXT, name TEXT, highway TEXT, natural TEXT, surface TEXT, lanes TEXT, maxspeed TEXT, oneway TEXT, bridge TEXT, tunnel TEXT, layer TEXT, other_tags TEXT, geom BLOB")
    road = LineString([(18.0,59.3),(18.001,59.3),(18.002,59.3)])
    db.execute("INSERT INTO lines VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)", ("10", "Testvägen", "residential", None, "asphalt", "2", "30", "no", None, None, "0", '"access"=>"yes"', gpkg_blob(road)))
    coast = LineString([(17.9,59.25),(17.95,59.25)])
    db.execute("INSERT INTO lines VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)", ("500", None, None, "coastline", None, None, None, None, None, None, None, None, gpkg_blob(coast)))

    create_table(db, "multilinestrings", "osm_id TEXT, name TEXT, type TEXT, other_tags TEXT, geom BLOB")

    create_table(db, "multipolygons", "osm_id TEXT, osm_way_id TEXT, name TEXT, type TEXT, amenity TEXT, boundary TEXT, admin_level TEXT, building TEXT, building_levels TEXT, height TEXT, landuse TEXT, natural TEXT, shop TEXT, tourism TEXT, addr_housenumber TEXT, addr_street TEXT, addr_place TEXT, addr_postcode TEXT, addr_city TEXT, addr_suburb TEXT, other_tags TEXT, geom BLOB")
    building = Polygon([(18.0,59.3),(18.002,59.3),(18.002,59.302),(18.0,59.302),(18.0,59.3)], [[(18.0005,59.3005),(18.001,59.3005),(18.001,59.301),(18.0005,59.301),(18.0005,59.3005)]])
    db.execute("INSERT INTO multipolygons VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", ("300", "300", "Fixture", None, None, None, None, "residential", "3", "10", None, None, None, None, "7", "Husvägen", None, "11111", "Stockholm", None, None, gpkg_blob(building)))
    park = Polygon([(18.02,59.3),(18.03,59.3),(18.03,59.31),(18.02,59.31),(18.02,59.3)])
    db.execute("INSERT INTO multipolygons VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", ("400", None, "Park Cafe", "multipolygon", "cafe", None, None, None, None, None, "grass", None, None, None, None, None, None, None, None, None, None, gpkg_blob(park)))

    create_table(db, "other_relations", "osm_id TEXT, name TEXT, type TEXT, other_tags TEXT, geom BLOB")
    db.commit(); db.close()


class Tests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.root = Path(self.temp.name)
        self.gpkg = self.root / "sweden-brur.gpkg"; make_gpkg(self.gpkg)
        self.pbf = self.root / "sweden.osm.pbf"; self.pbf.write_bytes(b"authoritative-pbf-fixture")
        self.cache = self.root / "cache"
    def tearDown(self): self.temp.cleanup()

    def test_direct_gpkg_build_has_no_provider_stage_and_preserves_domains(self):
        outputs = source_cache.build_osm_gpkg_source_caches(self.gpkg, self.pbf, self.cache, source_cache.ALL_ROUTES)
        self.assertFalse((self.cache / "source_stage").exists())
        self.assertEqual(set(outputs), set(source_cache.ALL_ROUTES))

        ways = list(iter_highway_ways(outputs["highways"]))
        self.assertEqual(len(ways), 1); self.assertEqual(ways[0].way_id, 10)
        self.assertEqual(ways[0].tags["surface"], "asphalt"); self.assertEqual(ways[0].tags["access"], "yes")

        signals = list(iter_facts(outputs["traffic_signals"], 1))
        self.assertEqual(len(signals), 1); self.assertEqual(signals[0]["osm_id"], 100); self.assertEqual(signals[0]["way_ids"], [10])

        pois = list(iter_facts(outputs["pois"], 1))
        self.assertEqual({item["osm_id"] for item in pois}, {200, 400})

        addresses = list(iter_facts(outputs["addresses"], 1))
        self.assertEqual({item["osm_id"] for item in addresses}, {200, 300})

        areas = list(iter_area_facts(outputs["areas"]))
        building = next(item for item in areas if item.get("osm_id") == 300)
        self.assertEqual(building["tags"]["building"], "residential")
        self.assertEqual(building["tags"]["building:levels"], "3")
        self.assertEqual(len(building["geometry"][0]["holes"]), 1)
        self.assertTrue(any(item.get("geometry_type") == "coastline" for item in areas))

    def test_manifest_hashes_gpkg_and_pbf_and_warm_run_hits(self):
        source_cache.build_osm_gpkg_source_caches(self.gpkg, self.pbf, self.cache, source_cache.ALL_ROUTES)
        manifest = json.loads((self.cache / "manifest.json").read_text(encoding="utf-8"))
        sources = manifest["source"]["sources"]
        self.assertEqual(set(sources), {"brur_gpkg", "osm_pbf"})
        self.assertEqual(sources["brur_gpkg"]["algorithm"], "sha256")
        self.assertEqual(sources["osm_pbf"]["algorithm"], "sha256")

        source_cache.build_osm_gpkg_source_caches(self.gpkg, self.pbf, self.cache, source_cache.ALL_ROUTES)
        run = json.loads((self.cache / "last_run.json").read_text(encoding="utf-8"))
        self.assertTrue(all(run["blocks"][route]["status"] == "CACHE HIT" for route in source_cache.ALL_ROUTES))

        self.pbf.write_bytes(b"changed-authoritative-pbf")
        source_cache.build_osm_gpkg_source_caches(self.gpkg, self.pbf, self.cache, ("addresses",))
        changed = json.loads((self.cache / "last_run.json").read_text(encoding="utf-8"))
        self.assertEqual(changed["blocks"]["addresses"]["status"], "DONE")


if __name__ == "__main__": unittest.main()
