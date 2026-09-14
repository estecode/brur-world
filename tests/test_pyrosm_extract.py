"""Exercise the real pyrosm adapter on a deterministic multi-domain PBF fixture."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import osmium

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"

FIXTURE = '''<?xml version="1.0" encoding="UTF-8"?>
<osm version="0.6">
 <node id="1" lon="18.000" lat="59.300"><tag k="highway" v="traffic_signals"/></node>
 <node id="2" lon="18.001" lat="59.300"/>
 <node id="3" lon="18.002" lat="59.300"><tag k="amenity" v="school"/><tag k="name" v="Fixture School"/></node>
 <node id="4" lon="18.003" lat="59.300"><tag k="addr:housenumber" v="12"/><tag k="addr:street" v="Testvägen"/></node>
 <node id="10" lon="18.010" lat="59.310"/><node id="11" lon="18.012" lat="59.310"/>
 <node id="12" lon="18.012" lat="59.312"/><node id="13" lon="18.010" lat="59.312"/>
 <node id="14" lon="18.0105" lat="59.3105"/><node id="15" lon="18.0115" lat="59.3105"/>
 <node id="16" lon="18.0115" lat="59.3115"/><node id="17" lon="18.0105" lat="59.3115"/>
 <node id="20" lon="17.990" lat="59.290"/><node id="21" lon="17.990" lat="59.330"/>
 <node id="30" lon="17.980" lat="59.280"/><node id="31" lon="18.030" lat="59.280"/>
 <node id="32" lon="18.030" lat="59.340"/><node id="33" lon="17.980" lat="59.340"/>
 <way id="100"><nd ref="1"/><nd ref="2"/><tag k="highway" v="residential"/><tag k="name" v="Signal Street"/></way>
 <way id="110"><nd ref="2"/><nd ref="3"/><tag k="amenity" v="parking"/></way>
 <way id="120"><nd ref="2"/><nd ref="4"/><tag k="addr:housenumber" v="14"/><tag k="addr:street" v="Testvägen"/></way>
 <way id="200"><nd ref="10"/><nd ref="11"/><nd ref="12"/><nd ref="13"/><nd ref="10"/><tag k="building" v="yes"/></way>
 <way id="210"><nd ref="10"/><nd ref="11"/><nd ref="12"/><nd ref="13"/><nd ref="10"/></way>
 <way id="211"><nd ref="14"/><nd ref="15"/><nd ref="16"/><nd ref="17"/><nd ref="14"/></way>
 <way id="300"><nd ref="20"/><nd ref="21"/><tag k="natural" v="coastline"/></way>
 <way id="310"><nd ref="30"/><nd ref="31"/><nd ref="32"/><nd ref="33"/><nd ref="30"/></way>
 <way id="320"><nd ref="10"/><nd ref="11"/><nd ref="12"/><nd ref="13"/><nd ref="10"/><tag k="natural" v="water"/></way>
 <relation id="400"><member type="way" ref="210" role="outer"/><member type="way" ref="211" role="inner"/><tag k="type" v="multipolygon"/><tag k="building" v="school"/><tag k="building:levels" v="3"/></relation>
 <relation id="410"><member type="way" ref="310" role="outer"/><tag k="type" v="multipolygon"/><tag k="boundary" v="administrative"/><tag k="admin_level" v="2"/></relation>
</osm>'''


class Copy(osmium.SimpleHandler):
    def __init__(self, writer): super().__init__(); self.writer = writer
    def node(self, value): self.writer.add_node(value)
    def way(self, value): self.writer.add_way(value)
    def relation(self, value): self.writer.add_relation(value)


class Inspect(osmium.SimpleHandler):
    def __init__(self):
        super().__init__(); self.tags: list[dict[str, str]] = []; self.ids: set[int] = set()
    def node(self, value): self._add(value)
    def way(self, value): self._add(value)
    def relation(self, value): self._add(value)
    def _add(self, value):
        tags = {str(tag.k): str(tag.v) for tag in value.tags}
        if tags:
            self.tags.append(tags); self.ids.add(int(value.id))


def write_pbf(xml: Path, pbf: Path) -> None:
    with osmium.SimpleWriter(str(pbf), overwrite=True) as writer:
        Copy(writer).apply_file(str(xml))


def extract(source: Path, root: Path, domain: str) -> tuple[Path, dict]:
    output = root / f"{domain}.osm.pbf"; report = root / f"{domain}.json"
    subprocess.run([
        sys.executable, str(TOOLS / "pyrosm_extract.py"), str(source),
        "--domain", domain, "--output", str(output), "--report", str(report),
        "--workers", "1",
    ], check=True)
    return output, json.loads(report.read_text(encoding="utf-8"))


class Tests(unittest.TestCase):
    def test_real_adapter_preserves_semantic_blocks_and_source_topology(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); xml = root / "fixture.osm"; xml.write_text(FIXTURE, encoding="utf-8")
            source = root / "fixture.osm.pbf"; write_pbf(xml, source)
            expected = {
                "highways": lambda tags: tags.get("highway") == "residential",
                "buildings": lambda tags: "building" in tags,
                "pois": lambda tags: tags.get("amenity") in {"school", "parking"},
                "addresses": lambda tags: tags.get("addr:housenumber") in {"12", "14"},
                "traffic_signals": lambda tags: tags.get("highway") == "traffic_signals",
                "background_areas": lambda tags: tags.get("natural") == "water",
                "coastlines": lambda tags: tags.get("natural") == "coastline",
                "admin_boundaries": lambda tags: tags.get("admin_level") == "2",
            }
            for domain, predicate in expected.items():
                with self.subTest(domain=domain):
                    output, report = extract(source, root, domain)
                    self.assertGreater(output.stat().st_size, 0)
                    self.assertEqual(report["domain"], domain)
                    self.assertEqual(len(report["sha256"]), 64)
                    inspect = Inspect(); inspect.apply_file(str(output))
                    self.assertTrue(any(predicate(tags) for tags in inspect.tags), inspect.tags)

    def test_building_relation_with_inner_ring_survives_adapter_and_brur_builder(self):
        from build_features import build_buildings
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); xml = root / "fixture.osm"; xml.write_text(FIXTURE, encoding="utf-8")
            source = root / "fixture.osm.pbf"; write_pbf(xml, source)
            buildings, _ = extract(source, root, "buildings")
            world = root / "world"; build_buildings(buildings, world)
            records = [json.loads(line) for line in (world / "buildings.jsonl").read_text(encoding="utf-8").splitlines()]
            relation = next(record for record in records if record["tags"].get("building") == "school")
            self.assertEqual(relation["tags"]["building:levels"], "3")
            self.assertTrue(any(polygon["holes"] for polygon in relation["geometry"]))


if __name__ == "__main__": unittest.main()
