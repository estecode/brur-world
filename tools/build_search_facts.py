"""Build search JSONL directly from normalized address source facts."""
from __future__ import annotations

import time
from pathlib import Path

from build_search_index import (
    AddressFact,
    PostcodeSample,
    _grid_cell,
    _join_unique,
    _locality_key,
    _postcode_key,
    _record,
    infer_nearby_postcode,
    infer_postcode,
    load_named_pois,
)
from gps_search import write_search_index
from normalized_source_facts import iter_facts, validate as validate_facts

ADDRESS_SCHEMA = 1


def _clean(value) -> str:
    return str(value or "").strip()


def build_search_index_facts(source: Path, output: Path) -> Path:
    validate_facts(source, ADDRESS_SCHEMA)
    output.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    poi_records = load_named_pois(output / "pois.jsonl")
    facts: list[AddressFact] = []
    known_postcodes: dict[tuple[str,str], set[str]] = {}
    postcode_samples: dict[tuple[int,int], list[PostcodeSample]] = {}

    for index, item in enumerate(iter_facts(source, ADDRESS_SCHEMA), 1):
        tags = {str(k):str(v) for k,v in item.get("tags",{}).items()}
        number = _clean(tags.get("addr:housenumber"))
        street = _clean(tags.get("addr:street") or tags.get("addr:place"))
        if not number or not street:
            continue
        postcode = _clean(tags.get("addr:postcode"))
        locality = _clean(tags.get("addr:city") or tags.get("addr:suburb") or tags.get("addr:place"))
        x = float(item["x"]); y = float(item["y"])
        fact = AddressFact(str(item.get("osm_type","unknown")), int(item["osm_id"]), f"{street} {number}".strip(), street, postcode, locality, x, y)
        facts.append(fact)
        if postcode:
            key = _postcode_key(street, locality)
            if key is not None: known_postcodes.setdefault(key,set()).add(postcode)
            locality_normalized = _locality_key(locality)
            if locality_normalized:
                postcode_samples.setdefault(_grid_cell(x,y),[]).append(PostcodeSample(postcode, locality_normalized, x, y))
        if index % 250_000 == 0:
            print(f"[search] source-facts={index:,} addresses={len(facts):,}", flush=True)

    address_records = []
    inferred = nearby_inferred = 0
    for fact in facts:
        postcode = fact.postcode
        if not postcode:
            postcode = infer_postcode(fact.street, fact.locality, known_postcodes)
            if postcode:
                inferred += 1
            else:
                postcode = infer_nearby_postcode(fact.x, fact.y, fact.locality, postcode_samples)
                if postcode: nearby_inferred += 1
        subtitle = _join_unique(postcode, fact.locality)
        address_records.append(_record("address", fact.osm_type, fact.osm_id, fact.display, subtitle, fact.x, fact.y))

    records = poi_records + address_records
    path = output / "search_index.jsonl"
    write_search_index(records, path)
    print(f"[search] normalized addresses: {len(address_records):,}", flush=True)
    print(f"[search] inferred missing postcodes: {inferred + nearby_inferred:,}", flush=True)
    print(f"[search] output: {path} ({path.stat().st_size:,} bytes) elapsed={time.monotonic()-started:.1f}s", flush=True)
    return path
