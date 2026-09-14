"""Verify #220 stages GDAL OSM GeoPackage domains before BRUR normalization."""
from __future__ import annotations

import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import osm_gpkg_source_stage as stage


def make_gpkg(path: Path) -> None:
    db = sqlite3.connect(path)
    db.execute(
        "CREATE TABLE points (fid INTEGER, geom BLOB, osm_id TEXT, name TEXT, highway TEXT, amenity TEXT, shop TEXT, tourism TEXT, railway TEXT, addr_housenumber TEXT, addr_street TEXT, addr_postcode TEXT, addr_city TEXT, addr_suburb TEXT, other_tags TEXT)"
    )
    db.execute(
        "INSERT INTO points VALUES (1,X'01','10','Signal','traffic_signals',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'\"crossing\"=>\"traffic_signals\"')"
    )
    db.execute(
        "INSERT INTO points VALUES (2,X'02','11','Police',NULL,'police',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL)"
    )
    db.execute(
        "INSERT INTO points VALUES (3,X'03','12',NULL,NULL,NULL,NULL,NULL,NULL,'12','Testvägen','12345','Stockholm',NULL,NULL)"
    )

    db.execute(
        "CREATE TABLE lines (fid INTEGER, geom BLOB, osm_id TEXT, name TEXT, highway TEXT, natural TEXT, surface TEXT, lanes TEXT, maxspeed TEXT, oneway TEXT, bridge TEXT, tunnel TEXT, layer TEXT, other_tags TEXT)"
    )
    db.execute(
        "INSERT INTO lines VALUES (1,X'11','20','Testvägen','residential',NULL,'asphalt','2','30','yes',NULL,NULL,'0',NULL)"
    )
    db.execute(
        "INSERT INTO lines VALUES (2,X'12','21',NULL,NULL,'coastline',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL)"
    )
    db.execute(
        "INSERT INTO lines VALUES (3,X'13','22',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'\"addr:housenumber\"=>\"7\",\"addr:street\"=>\"Linjevägen\"')"
    )

    db.execute("CREATE TABLE multilinestrings (fid INTEGER, geom BLOB, osm_id TEXT, name TEXT, type TEXT, other_tags TEXT)")
    db.execute(
        "INSERT INTO multilinestrings VALUES (1,X'21','30','Route','route','\"highway\"=>\"service\"')"
    )

    db.execute(
        "CREATE TABLE multipolygons (fid INTEGER, geom BLOB, osm_id TEXT, osm_way_id TEXT, name TEXT, type TEXT, aeroway TEXT, amenity TEXT, barrier TEXT, boundary TEXT, building TEXT, building_levels TEXT, height TEXT, landuse TEXT, leisure TEXT, man_made TEXT, military TEXT, natural TEXT, office TEXT, place TEXT, shop TEXT, tourism TEXT, addr_housenumber TEXT, addr_street TEXT, addr_place TEXT, addr_postcode TEXT, addr_city TEXT, addr_suburb TEXT, other_tags TEXT)"
    )
    db.execute(
        "INSERT INTO multipolygons VALUES (1,X'31','40',NULL,'Building','multipolygon',NULL,NULL,NULL,NULL,'yes','3','10',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'8','Husvägen',NULL,'54321','Lund',NULL,NULL)"
    )
    db.execute(
        "INSERT INTO multipolygons VALUES (2,X'32','41',NULL,'School','multipolygon',NULL,'school',NULL,NULL,'school',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'\"addr:housenumber\"=>\"9\",\"addr:street\"=>\"Skolvägen\"')"
    )

    db.execute("CREATE TABLE other_relations (fid INTEGER, geom BLOB, osm_id TEXT, name TEXT, type TEXT, other_tags TEXT)")
    db.execute(
        "INSERT INTO other_relations VALUES (1,X'41','50','Relation POI','site','\"amenity\"=>\"hospital\",\"addr:housenumber\"=>\"1\"')"
    )
    db.commit()
    db.close()


def row_count(path: Path, table: str) -> int:
    db = sqlite3.connect(path)
    try:
        return int(db.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0])
    finally:
        db.close()


class Tests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.gpkg = self.root / "sweden-brur.gpkg"
        self.output = self.root / "source_stage"
        make_gpkg(self.gpkg)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_all_domains_are_written_without_normalized_outputs(self) -> None:
        outputs = stage.stage_osm_geopackage(self.gpkg, self.output)
        self.assertEqual(set(outputs), set(stage.ALL_DOMAINS))
        self.assertTrue(all(path.is_file() for path in outputs.values()))

        self.assertEqual(row_count(outputs["roads"], "source_lines"), 1)
        self.assertEqual(row_count(outputs["roads"], "source_multilinestrings"), 1)
        self.assertEqual(row_count(outputs["traffic"], "source_points"), 1)
        self.assertEqual(row_count(outputs["pois"], "source_points"), 1)
        self.assertEqual(row_count(outputs["pois"], "source_multipolygons"), 1)
        self.assertEqual(row_count(outputs["pois"], "source_other_relations"), 1)
        self.assertEqual(row_count(outputs["addresses"], "source_points"), 1)
        self.assertEqual(row_count(outputs["addresses"], "source_lines"), 1)
        self.assertEqual(row_count(outputs["addresses"], "source_multipolygons"), 2)
        self.assertEqual(row_count(outputs["addresses"], "source_other_relations"), 1)
        self.assertEqual(row_count(outputs["areas"], "source_multipolygons"), 2)
        self.assertEqual(row_count(outputs["coastline"], "source_lines"), 1)

        manifest = json.loads((self.output / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["format"], stage.STAGE_FORMAT)
        self.assertEqual(manifest["version"], stage.STAGE_VERSION)
        self.assertEqual(set(manifest["domains"]), set(stage.ALL_DOMAINS))
        self.assertFalse(list(self.root.rglob("*.brfacts")))
        self.assertFalse(list(self.root.rglob("*.baf")))

    def test_warm_stage_reuses_valid_domain_files(self) -> None:
        stage.stage_osm_geopackage(self.gpkg, self.output)
        with mock.patch.object(stage, "_stage_domain", side_effect=AssertionError("unexpected restage")):
            outputs = stage.stage_osm_geopackage(self.gpkg, self.output)
        self.assertTrue(all(path.is_file() for path in outputs.values()))


if __name__ == "__main__":
    unittest.main()
