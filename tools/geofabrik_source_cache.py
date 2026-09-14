#!/usr/bin/env python3
"""Build normalized BRUR source caches from Geofabrik GeoPackage + OSM supplement.

Phase 1 is provider extraction only: SQLite copies requested GeoPackage layers
into per-domain files without decoding rows and pyrosm performs one Sweden query
for the OSM-only supplement (addresses and/or coastline) and writes that result
to disk. Phase 2 starts only after every requested source file exists and turns
those files into BRUR's existing portable highway/area/fact cache contracts.
"""
from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Iterator

import osmium
from shapely import from_wkb

from area_source_cache import (
    FOOTER as BAF_FOOTER,
    FOOTER_MAGIC as BAF_FOOTER_MAGIC,
    FRAME as BAF_FRAME,
    HEADER as BAF_HEADER,
    MAGIC as BAF_MAGIC,
    RECORD_AREA_WAY,
    VERSION as BAF_VERSION,
    _encode_area,
    _encode_coastline,
    area_source_cache_metadata,
)
from highway_facts import FOOTER as HIGHWAY_FOOTER, HighwayFactWriter, validate_highways
from normalized_source_facts import FOOTER as FACT_FOOTER, FactWriter, validate as validate_facts
from source_identity import compute_source_identity
from world_common import project

CACHE_FORMAT = "BOSC5-GEOFABRIK"
EXTRACTOR_VERSION = 1
ROUTE_VERSIONS = {"highways": 6, "pois": 5, "addresses": 5, "traffic_signals": 5, "areas": 3}
ALL_ROUTES = tuple(ROUTE_VERSIONS)
SCHEMAS = {"pois": 1, "addresses": 1, "traffic_signals": 1}
STAGE_FORMAT = "BGS1"
STAGE_VERSION = 1
STAGE_DIR_NAME = "source_stage"
PROGRESS_INTERVAL = 250_000

DOMAIN_TABLES: dict[str, tuple[str, ...]] = {
    "roads": ("gis_osm_roads_free",),
    "traffic": ("gis_osm_traffic_free", "gis_osm_traffic_a_free"),
    "pois": (
        "gis_osm_pois_free", "gis_osm_pois_a_free", "gis_osm_places_free", "gis_osm_places_a_free",
        "gis_osm_pofw_free", "gis_osm_pofw_a_free", "gis_osm_transport_free", "gis_osm_transport_a_free",
        "gis_osm_traffic_free", "gis_osm_traffic_a_free",
    ),
    "areas": (
        "gis_osm_buildings_a_free", "gis_osm_landuse_a_free", "gis_osm_natural_a_free",
        "gis_osm_water_a_free", "gis_osm_adminareas_a_free",
    ),
}

POI_RULES: dict[str, tuple[str, str]] = {
    "police": ("amenity", "police"), "fire_station": ("amenity", "fire_station"),
    "hospital": ("amenity", "hospital"), "clinic": ("amenity", "clinic"), "doctors": ("amenity", "doctors"),
    "pharmacy": ("amenity", "pharmacy"), "fuel": ("amenity", "fuel"),
    "charging_station": ("amenity", "charging_station"), "parking": ("amenity", "parking"),
    "bank": ("amenity", "bank"), "atm": ("amenity", "atm"), "restaurant": ("amenity", "restaurant"),
    "fast_food": ("amenity", "fast_food"), "cafe": ("amenity", "cafe"), "bar": ("amenity", "bar"),
    "pub": ("amenity", "pub"), "school": ("amenity", "school"), "college": ("amenity", "college"),
    "university": ("amenity", "university"), "kindergarten": ("amenity", "kindergarten"),
    "supermarket": ("shop", "supermarket"), "convenience": ("shop", "convenience"), "mall": ("shop", "mall"),
    "department_store": ("shop", "department_store"), "car_repair": ("shop", "car_repair"),
    "bicycle_shop": ("shop", "bicycle"), "hotel": ("tourism", "hotel"), "motel": ("tourism", "motel"),
    "hostel": ("tourism", "hostel"), "attraction": ("tourism", "attraction"), "museum": ("tourism", "museum"),
    "viewpoint": ("tourism", "viewpoint"), "railway_station": ("railway", "station"),
    "railway_halt": ("railway", "halt"), "speed_camera": ("highway", "speed_camera"),
}
ADDRESS_TAGS = ("addr:housenumber", "addr:street", "addr:place", "addr:postcode", "addr:city", "addr:suburb")


def _now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def _log(message: str) -> None:
    print(f"[{_now()}] [geofabrik-source] {message}", flush=True)


def _atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + f".tmp-{os.getpid()}")
    temp.write_text(json.dumps(value, indent=2, sort_keys=True), encoding="utf-8")
    temp.replace(path)


def _load_json(path: Path) -> dict:
    if not path.is_file(): return {}
    try: value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError): return {}
    return value if isinstance(value, dict) else {}


def _route_filename(route: str) -> str:
    return "areas.baf" if route == "areas" else f"{route}.brfacts"


def _route_metadata(path: Path, route: str) -> dict:
    if route == "areas": return area_source_cache_metadata(path)
    if route == "highways": return validate_highways(path)
    return validate_facts(path, SCHEMAS[route])


def _route_valid(cache_dir: Path, route: str, entry: object, source_identity: dict) -> bool:
    if not isinstance(entry, dict): return False
    if entry.get("version") != ROUTE_VERSIONS[route] or entry.get("extractor_version") != EXTRACTOR_VERSION: return False
    if entry.get("complete") is not True or entry.get("file") != _route_filename(route): return False
    if entry.get("source_identity") != source_identity: return False
    path = cache_dir / _route_filename(route)
    if not path.is_file() or entry.get("size_bytes") != path.stat().st_size: return False
    try: metadata = _route_metadata(path, route)
    except (OSError, ValueError, TypeError, KeyError): return False
    return str(metadata.get("sha256", "")) == entry.get("sha256")


def _table_exists(connection: sqlite3.Connection, table: str) -> bool:
    return connection.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)).fetchone() is not None


def _quote(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


def _stage_domain(gpkg: Path, destination: Path, domain: str, tables: tuple[str, ...]) -> dict:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temp = destination.with_suffix(destination.suffix + f".tmp-{os.getpid()}-{time.time_ns()}")
    try: temp.unlink()
    except OSError: pass
    source = sqlite3.connect(f"file:{gpkg}?mode=ro", uri=True)
    try: available = [table for table in tables if _table_exists(source, table)]
    finally: source.close()
    if not available: raise ValueError(f"GeoPackage has no required {domain} layers: {', '.join(tables)}")
    started = time.monotonic(); target = sqlite3.connect(temp)
    try:
        target.execute("PRAGMA journal_mode=OFF"); target.execute("PRAGMA synchronous=OFF")
        target.execute("ATTACH DATABASE ? AS src", (str(gpkg),))
        target.execute("CREATE TABLE brur_source_stage(format TEXT NOT NULL, version INTEGER NOT NULL, domain TEXT NOT NULL)")
        target.execute("INSERT INTO brur_source_stage VALUES(?,?,?)", (STAGE_FORMAT, STAGE_VERSION, domain))
        for table in available:
            _log(f"STAGE domain={domain} layer={table}")
            target.execute(f"CREATE TABLE {_quote(table)} AS SELECT * FROM src.{_quote(table)}")
        target.commit(); target.execute("DETACH DATABASE src")
    except BaseException:
        target.close()
        try: temp.unlink()
        except OSError: pass
        raise
    target.close(); temp.replace(destination)
    return {"tables": available, "size_bytes": destination.stat().st_size, "elapsed_seconds": round(time.monotonic()-started, 3)}


def _stage_required_domains(routes: Iterable[str]) -> tuple[str, ...]:
    route_set = set(routes); domains: list[str] = []
    if route_set & {"highways", "traffic_signals"}: domains.append("roads")
    if "traffic_signals" in route_set: domains.append("traffic")
    if "pois" in route_set: domains.append("pois")
    if "areas" in route_set: domains.append("areas")
    return tuple(domains)


def stage_geopackage(gpkg: Path, stage_dir: Path, routes: Iterable[str], source_identity: dict) -> dict[str, Path]:
    stage_dir.mkdir(parents=True, exist_ok=True); manifest_path = stage_dir / "geofabrik_manifest.json"; old = _load_json(manifest_path)
    compatible = old.get("format") == STAGE_FORMAT and old.get("version") == STAGE_VERSION and old.get("source") == source_identity
    old_domains = old.get("domains", {}) if compatible and isinstance(old.get("domains"), dict) else {}
    domains: dict[str, dict] = dict(old_domains); outputs: dict[str, Path] = {}
    for domain in _stage_required_domains(routes):
        path = stage_dir / f"{domain}.sqlite"; entry = old_domains.get(domain)
        valid = isinstance(entry, dict) and entry.get("complete") is True and path.is_file() and entry.get("size_bytes") == path.stat().st_size
        if valid: _log(f"STAGE HIT domain={domain} bytes={path.stat().st_size:,}")
        else:
            report = _stage_domain(gpkg, path, domain, DOMAIN_TABLES[domain]); domains[domain] = {"complete": True, **report}
            _atomic_json(manifest_path, {"format":STAGE_FORMAT, "version":STAGE_VERSION, "source":source_identity, "domains":domains})
            _log(f"STAGE DONE domain={domain} bytes={path.stat().st_size:,} elapsed={report['elapsed_seconds']:.3f}s")
        outputs[domain] = path
    _atomic_json(manifest_path, {"format":STAGE_FORMAT, "version":STAGE_VERSION, "source":source_identity, "domains":domains})
    return outputs


def stage_pyrosm_supplement(pbf: Path, destination: Path, *, addresses: bool, coastline: bool, source_identity: dict) -> Path:
    if not addresses and not coastline: raise ValueError("supplement requested without predicates")
    manifest_path = destination.with_suffix(destination.suffix + ".json"); old = _load_json(manifest_path)
    predicates = {"addresses":bool(addresses), "coastline":bool(coastline)}
    if destination.is_file() and old.get("complete") is True and old.get("source") == source_identity and old.get("predicates") == predicates and old.get("size_bytes") == destination.stat().st_size:
        _log(f"SUPPLEMENT HIT bytes={destination.stat().st_size:,}"); return destination
    try: from pyrosm import OSM
    except ImportError as exc: raise RuntimeError("pyrosm >= 0.13.1 is required for the OSM address/coastline supplement") from exc
    filters: dict[str, object] = {}
    if addresses: filters["addr:housenumber"] = True
    if coastline: filters["natural"] = ["coastline"]
    destination.parent.mkdir(parents=True, exist_ok=True)
    temp = destination.parent / f".{destination.stem}.tmp-{os.getpid()}-{time.time_ns()}.osm.pbf"
    _log(f"SUPPLEMENT START addresses={addresses} coastline={coastline}"); started = time.monotonic()
    osm = OSM(str(pbf)); frame = osm.get_data_by_custom_criteria(custom_filter=filters, filter_type="keep")
    osm.write_pbf(frame, str(temp), subset_only=True); temp.replace(destination)
    _atomic_json(manifest_path, {"format":STAGE_FORMAT, "version":STAGE_VERSION, "complete":True, "source":source_identity, "predicates":predicates, "size_bytes":destination.stat().st_size, "elapsed_seconds":round(time.monotonic()-started,3)})
    _log(f"SUPPLEMENT DONE bytes={destination.stat().st_size:,} elapsed={time.monotonic()-started:.3f}s")
    return destination


def _gpkg_wkb(blob) -> bytes:
    raw = bytes(blob)
    if len(raw) < 8 or raw[:2] != b"GP": raise ValueError("invalid GeoPackage geometry header")
    envelope = (raw[3] >> 1) & 0x07; envelope_bytes = {0:0, 1:32, 2:48, 3:48, 4:64}.get(envelope)
    if envelope_bytes is None: raise ValueError(f"unsupported GeoPackage envelope code: {envelope}")
    offset = 8 + envelope_bytes
    if offset >= len(raw): raise ValueError("truncated GeoPackage geometry")
    return raw[offset:]


def _geometry(blob): return from_wkb(_gpkg_wkb(blob))


def _iter_lines(geometry) -> Iterator:
    if geometry is None or geometry.is_empty: return
    if geometry.geom_type == "LineString": yield geometry
    elif geometry.geom_type == "MultiLineString": yield from geometry.geoms


def _iter_polygons(geometry) -> Iterator:
    if geometry is None or geometry.is_empty: return
    if geometry.geom_type == "Polygon": yield geometry
    elif geometry.geom_type == "MultiPolygon": yield from geometry.geoms
    elif geometry.geom_type == "GeometryCollection":
        for child in geometry.geoms: yield from _iter_polygons(child)


def _osm_id(value) -> int: return int(str(value).strip())
def _qcoord(lon: float, lat: float) -> tuple[int,int]: return int(round(lon*10_000_000.0)), int(round(lat*10_000_000.0))


def _synthetic_node_id(lon: float, lat: float, separation: str = "") -> int:
    qlon, qlat = _qcoord(lon,lat); digest = hashlib.blake2b(f"{qlon}:{qlat}:{separation}".encode("ascii"),digest_size=8,person=b"brurroad").digest()
    return int.from_bytes(digest,"little",signed=False) & 0x7FFF_FFFF_FFFF_FFFF


def _truth(value) -> bool: return str(value or "").strip().upper() in {"T","TRUE","YES","1"}


def _road_tags(row: sqlite3.Row) -> dict[str,str]:
    keys=set(row.keys()); fclass=str(row["fclass"] or "").strip(); tags:dict[str,str]={}
    if fclass.startswith("track_grade"): tags.update({"highway":"track", "tracktype":fclass.removeprefix("track_")})
    elif fclass: tags["highway"]=fclass
    if "name" in keys and row["name"]: tags["name"]=str(row["name"])
    if "ref" in keys and row["ref"]: tags["ref"]=str(row["ref"])
    if "maxspeed" in keys and row["maxspeed"] not in (None,"",0,"0"): tags["maxspeed"]=str(row["maxspeed"])
    if "oneway" in keys:
        value=str(row["oneway"] or "").strip().upper()
        if value=="F": tags["oneway"]="yes"
        elif value=="T": tags["oneway"]="-1"
        elif value=="B": tags["oneway"]="no"
    if "layer" in keys and row["layer"] not in (None,"",0,"0"): tags["layer"]=str(row["layer"])
    if "bridge" in keys and _truth(row["bridge"]): tags["bridge"]="yes"
    if "tunnel" in keys and _truth(row["tunnel"]): tags["tunnel"]="yes"
    for key in ("surface","lanes","access","vehicle","motor_vehicle","motorcar","service","width","lit","junction"):
        if key in keys and row[key] not in (None,""): tags[key]=str(row[key])
    return tags


def _separation(tags:dict[str,str])->str:
    return f"l={tags.get('layer','0')};b={tags.get('bridge','')};t={tags.get('tunnel','')}" if tags.get("bridge")=="yes" or tags.get("tunnel")=="yes" or tags.get("layer") else ""


def _traffic_signal_points(path:Path)->tuple[list[dict],dict[tuple[int,int],list[int]]]:
    connection=sqlite3.connect(path); connection.row_factory=sqlite3.Row; signals:list[dict]=[]; by_coord:dict[tuple[int,int],list[int]]={}
    try:
        if not _table_exists(connection,"gis_osm_traffic_free"): return signals,by_coord
        for row in connection.execute("SELECT * FROM gis_osm_traffic_free WHERE fclass='traffic_signals'"):
            geometry=_geometry(row["geom"])
            if geometry.geom_type!="Point": continue
            signal_id=_osm_id(row["osm_id"]); lon=float(geometry.x); lat=float(geometry.y); index=len(signals)
            signals.append({"osm_id":signal_id,"lon":lon,"lat":lat,"name":str(row["name"] or ""),"way_ids":set()}); by_coord.setdefault(_qcoord(lon,lat),[]).append(index)
    finally: connection.close()
    return signals,by_coord


def _scan_roads(roads_stage:Path, destination:Path|None, signal_stage:Path|None)->tuple[dict|None,list[dict]]:
    signals:list[dict]=[]; signal_by_coord:dict[tuple[int,int],list[int]]={}
    if signal_stage is not None: signals,signal_by_coord=_traffic_signal_points(signal_stage)
    writer=HighwayFactWriter(destination) if destination is not None else None
    connection=sqlite3.connect(roads_stage); connection.row_factory=sqlite3.Row; ways=0
    try:
        for row in connection.execute("SELECT * FROM gis_osm_roads_free"):
            way_id=_osm_id(row["osm_id"]); tags=_road_tags(row); geometry=_geometry(row["geom"])
            for line in _iter_lines(geometry):
                coordinates=[(float(point[0]),float(point[1])) for point in line.coords]
                if len(coordinates)<2: continue
                sep=_separation(tags); last=len(coordinates)-1; node_ids=[]
                for index,(lon,lat) in enumerate(coordinates):
                    node_ids.append(_synthetic_node_id(lon,lat,sep if sep and index not in {0,last} else ""))
                    for signal_index in signal_by_coord.get(_qcoord(lon,lat),()): signals[signal_index]["way_ids"].add(way_id)
                if writer is not None: writer.write_way(way_id,node_ids,coordinates,tags)
                ways+=1
            if ways and ways%PROGRESS_INTERVAL==0: _log(f"NORMALIZE highways={ways:,}")
        report=writer.publish() if writer is not None else None
    except BaseException:
        if writer is not None: writer.abort()
        raise
    finally: connection.close()
    return report,signals


def _normalize_signals(signals:list[dict],destination:Path)->dict:
    writer=FactWriter(destination,SCHEMAS["traffic_signals"])
    try:
        for signal in signals:
            tags={"highway":"traffic_signals"}
            if signal.get("name"): tags["name"]=str(signal["name"])
            writer.write({"osm_id":int(signal["osm_id"]),"lon":float(signal["lon"]),"lat":float(signal["lat"]),"tags":tags,"way_ids":sorted(int(value) for value in signal.get("way_ids",()))})
        return writer.publish()
    except BaseException: writer.abort(); raise


def _poi_tags(fclass:str,name:str)->dict[str,str]:
    tags={"geofabrik:fclass":fclass}; rule=POI_RULES.get(fclass)
    if rule is not None: tags[rule[0]]=rule[1]
    elif fclass: tags["amenity"]=fclass
    if name: tags["name"]=name
    return tags


def _normalize_pois(stage:Path,destination:Path)->dict:
    writer=FactWriter(destination,SCHEMAS["pois"]); connection=sqlite3.connect(stage); connection.row_factory=sqlite3.Row; records=0
    try:
        for table in DOMAIN_TABLES["pois"]:
            if not _table_exists(connection,table): continue
            for row in connection.execute(f"SELECT * FROM {_quote(table)}"):
                keys=set(row.keys()); fclass=str(row["fclass"] or "") if "fclass" in keys else ""; name=str(row["name"] or "") if "name" in keys else ""
                geometry=_geometry(row["geom"]); osm_id=_osm_id(row["osm_id"]); tags=_poi_tags(fclass,name)
                if "places" in table: tags.pop("amenity",None); tags["place"]=fclass
                if geometry.geom_type=="Point":
                    x,y=project(float(geometry.x),float(geometry.y)); writer.write({"osm_type":"node","osm_id":osm_id,"x":x,"y":y,"tags":tags}); records+=1
                else:
                    polygons=list(_iter_polygons(geometry))
                    if not polygons: continue
                    centroid=geometry.centroid; x,y=project(float(centroid.x),float(centroid.y)); projected=[]
                    for polygon in polygons: projected.append([[*project(float(p[0]),float(p[1]))] for p in polygon.exterior.coords])
                    writer.write({"osm_type":"way","osm_id":osm_id,"x":x,"y":y,"geometry":projected,"tags":tags}); records+=1
            _log(f"NORMALIZE pois layer={table} records={records:,}")
        return writer.publish()
    except BaseException: writer.abort(); raise
    finally: connection.close()


def _polygon_fact_geometry(geometry)->list[dict]:
    result=[]
    for polygon in _iter_polygons(geometry):
        outer=[[*project(float(p[0]),float(p[1]))] for p in list(polygon.exterior.coords)[:-1]]
        holes=[[ [*project(float(p[0]),float(p[1]))] for p in list(ring.coords)[:-1] ] for ring in polygon.interiors]
        if len(outer)>=3: result.append({"outer":outer,"holes":[hole for hole in holes if len(hole)>=3]})
    return result


def _area_tags(table:str,row:sqlite3.Row)->dict[str,str]|None:
    keys=set(row.keys()); fclass=str(row["fclass"] or "") if "fclass" in keys else ""; name=str(row["name"] or "") if "name" in keys else ""; tags:dict[str,str]={}
    if table=="gis_osm_buildings_a_free":
        building_type=str(row["type"] or "") if "type" in keys else ""; tags["building"]=building_type or "yes"
        for column,key in (("height","height"),("levels","building:levels"),("building_levels","building:levels")):
            if column in keys and row[column] not in (None,""): tags[key]=str(row[column])
    elif table=="gis_osm_landuse_a_free":
        if not fclass:return None
        tags["landuse"]=fclass
    elif table=="gis_osm_natural_a_free":
        if not fclass:return None
        tags["natural"]=fclass
    elif table=="gis_osm_water_a_free":
        if fclass=="reservoir": tags.update({"natural":"water","water":"reservoir","landuse":"reservoir"})
        elif fclass=="river": tags.update({"natural":"water","water":"river","waterway":"riverbank"})
        elif fclass=="dock": tags["waterway"]="dock"
        elif fclass: tags.update({"natural":"water","water":fclass})
        else: tags["natural"]="water"
    elif table=="gis_osm_adminareas_a_free":
        code=int(row["code"] or 0) if "code" in keys else 0
        if code!=1202 and fclass not in {"national","country"}: return None
        tags.update({"boundary":"administrative","admin_level":"2"})
    else:return None
    if name: tags["name"]=name
    return tags


class _AreaWriter:
    def __init__(self,destination:Path)->None:
        self.destination=destination; destination.parent.mkdir(parents=True,exist_ok=True); self.temp=destination.with_suffix(destination.suffix+f".tmp-{os.getpid()}-{time.time_ns()}")
        self.handle=self.temp.open("wb"); self.digest=hashlib.sha256(); self.records=0; self.payload_bytes=0; header=BAF_HEADER.pack(BAF_MAGIC,BAF_VERSION); self.handle.write(header); self.digest.update(header)
    def write_payload(self,payload:bytes)->None:
        framed=BAF_FRAME.pack(len(payload))+payload; self.handle.write(framed); self.digest.update(framed); self.payload_bytes+=len(framed); self.records+=1
    def publish(self)->dict:
        digest=self.digest.digest(); self.handle.write(BAF_FOOTER.pack(BAF_FOOTER_MAGIC,self.records,self.payload_bytes,digest)); self.handle.flush(); os.fsync(self.handle.fileno()); self.handle.close(); self.temp.replace(self.destination)
        return {"records":self.records,"size_bytes":self.destination.stat().st_size,"sha256":digest.hex()}
    def abort(self)->None:
        try:self.handle.close()
        except Exception:pass
        try:self.temp.unlink()
        except OSError:pass


class _SupplementHandler(osmium.SimpleHandler):
    def __init__(self,address_writer:FactWriter|None,area_writer:_AreaWriter|None)->None:
        super().__init__(); self.address_writer=address_writer; self.area_writer=area_writer
    def _address(self,osm_type:str,osm_id:int,tags,x:float,y:float)->None:
        if self.address_writer is None:return
        number=str(tags.get("addr:housenumber") or "").strip(); street=str(tags.get("addr:street") or tags.get("addr:place") or "").strip()
        if not number or not street:return
        values={key:str(tags.get(key)) for key in ADDRESS_TAGS if tags.get(key) is not None}; self.address_writer.write({"osm_type":osm_type,"osm_id":osm_id,"x":x,"y":y,"tags":values})
    def node(self,node)->None:
        if self.address_writer is not None and node.location.valid():
            x,y=project(float(node.lon),float(node.lat)); self._address("node",int(node.id),node.tags,x,y)
    def way(self,way)->None:
        points=[]
        try:
            for node in way.nodes:
                if node.location.valid():points.append((float(node.lon),float(node.lat)))
        except osmium.InvalidLocationError:return
        if self.area_writer is not None and way.tags.get("natural")=="coastline" and len(points)>=2:self.area_writer.write_payload(_encode_coastline(int(way.id),[project(lon,lat) for lon,lat in points]))
        if self.address_writer is not None and points:
            projected=[project(lon,lat) for lon,lat in points]; x=sum(p[0] for p in projected)/len(projected); y=sum(p[1] for p in projected)/len(projected); self._address("way",int(way.id),way.tags,x,y)


def _normalize_areas(stage:Path,supplement:Path,destination:Path)->dict:
    writer=_AreaWriter(destination); connection=sqlite3.connect(stage); connection.row_factory=sqlite3.Row; count=0
    try:
        for table in DOMAIN_TABLES["areas"]:
            if not _table_exists(connection,table):continue
            for row in connection.execute(f"SELECT * FROM {_quote(table)}"):
                tags=_area_tags(table,row)
                if tags is None:continue
                polygons=_polygon_fact_geometry(_geometry(row["geom"]))
                if not polygons:continue
                osm_id=_osm_id(row["osm_id"]); writer.write_payload(_encode_area(RECORD_AREA_WAY,osm_id,osm_id,tags,polygons)); count+=1
                if count%PROGRESS_INTERVAL==0:_log(f"NORMALIZE areas={count:,}")
            _log(f"NORMALIZE areas layer={table} records={count:,}")
        _SupplementHandler(None,writer).apply_file(str(supplement),locations=True); return writer.publish()
    except BaseException:writer.abort();raise
    finally:connection.close()


def _normalize_addresses(supplement:Path,destination:Path)->dict:
    writer=FactWriter(destination,SCHEMAS["addresses"])
    try:_SupplementHandler(writer,None).apply_file(str(supplement),locations=True);return writer.publish()
    except BaseException:writer.abort();raise


def _entry(route:str,report:dict,path:Path,source_identity:dict,elapsed:float)->dict:
    return {"version":ROUTE_VERSIONS[route],"extractor_version":EXTRACTOR_VERSION,"extractor":"geofabrik-gpkg+pyrosm-supplement","complete":True,"file":_route_filename(route),"records":int(report.get("records",0)),"size_bytes":int(path.stat().st_size),"sha256":str(report["sha256"]),"source_identity":source_identity,"elapsed_seconds":round(elapsed,3)}


def _composite_identity(gpkg_identity:dict,pbf_identity:dict|None)->dict:
    payload={"geofabrik":gpkg_identity,"osm_supplement":pbf_identity}; digest=hashlib.sha256(json.dumps(payload,sort_keys=True,separators=(",",":")).encode("utf-8")).hexdigest(); return {"algorithm":"sha256-composite","digest":digest,"sources":payload}


def build_geofabrik_source_caches(gpkg:Path,address_pbf:Path|None,cache_dir:Path,routes:Iterable[str]=ALL_ROUTES)->dict[str,Path]:
    requested=tuple(dict.fromkeys(routes)); unknown=sorted(set(requested)-set(ALL_ROUTES))
    if unknown:raise ValueError(f"unknown GeoPackage source route(s): {', '.join(unknown)}")
    if not gpkg.is_file():raise FileNotFoundError(gpkg)
    need_supplement=bool(set(requested)&{"addresses","areas"})
    if need_supplement and (address_pbf is None or not address_pbf.is_file()):raise ValueError("--address-pbf is required for addresses/coastline when building from GeoPackage")
    cache_dir.mkdir(parents=True,exist_ok=True); stage_dir=cache_dir/STAGE_DIR_NAME
    gpkg_identity=compute_source_identity(gpkg,cache_dir/"geofabrik_identity.json"); pbf_identity=compute_source_identity(address_pbf,cache_dir/"supplement_identity.json") if need_supplement and address_pbf is not None else None
    route_sources={route:(_composite_identity(gpkg_identity,pbf_identity) if route=="areas" else pbf_identity if route=="addresses" else gpkg_identity) for route in requested}
    manifest_path=cache_dir/"manifest.json"; old=_load_json(manifest_path); old_routes=old.get("routes",{}) if isinstance(old.get("routes"),dict) else {}; entries={route:dict(entry) for route,entry in old_routes.items() if route in ROUTE_VERSIONS and isinstance(entry,dict)}
    stale={route for route in requested if not _route_valid(cache_dir,route,entries.get(route),route_sources[route])}; run={"format":CACHE_FORMAT,"status":"RUNNING","started_at":_now(),"requested":list(requested),"blocks":{}}
    for route in requested:run["blocks"][route]={"status":"REBUILD" if route in stale else "CACHE HIT"};_log(f"PLAN route={route} status={run['blocks'][route]['status']}")
    _atomic_json(cache_dir/"last_run.json",run)
    composite=_composite_identity(gpkg_identity,pbf_identity)
    if not stale:
        run.update({"status":"DONE","completed_at":_now(),"source":composite});_atomic_json(cache_dir/"last_run.json",run);return {route:cache_dir/_route_filename(route) for route in requested}

    # Phase 1: finish and publish every required provider extraction first.
    staged=stage_geopackage(gpkg,stage_dir,stale,gpkg_identity); supplement=None
    if stale&{"addresses","areas"}:
        assert address_pbf is not None and pbf_identity is not None
        supplement=stage_pyrosm_supplement(address_pbf,stage_dir/"osm_supplement.osm.pbf",addresses="addresses" in stale,coastline="areas" in stale,source_identity=pbf_identity)

    # Phase 2: normalize only after all phase-1 source files exist.
    signal_records=None
    if "highways" in stale:
        started=time.monotonic(); report,signal_records=_scan_roads(staged["roads"],cache_dir/"highways.brfacts",staged.get("traffic") if "traffic_signals" in stale else None); elapsed=time.monotonic()-started; assert report is not None
        entries["highways"]=_entry("highways",report,cache_dir/"highways.brfacts",route_sources["highways"],elapsed);run["blocks"]["highways"]={"status":"DONE",**entries["highways"]}
    elif "traffic_signals" in stale:
        _,signal_records=_scan_roads(staged["roads"],None,staged["traffic"])
    if "traffic_signals" in stale:
        assert signal_records is not None; started=time.monotonic();report=_normalize_signals(signal_records,cache_dir/"traffic_signals.brfacts");elapsed=time.monotonic()-started;entries["traffic_signals"]=_entry("traffic_signals",report,cache_dir/"traffic_signals.brfacts",route_sources["traffic_signals"],elapsed);run["blocks"]["traffic_signals"]={"status":"DONE",**entries["traffic_signals"]}
    if "pois" in stale:
        started=time.monotonic();report=_normalize_pois(staged["pois"],cache_dir/"pois.brfacts");elapsed=time.monotonic()-started;entries["pois"]=_entry("pois",report,cache_dir/"pois.brfacts",route_sources["pois"],elapsed);run["blocks"]["pois"]={"status":"DONE",**entries["pois"]}
    if "addresses" in stale:
        assert supplement is not None;started=time.monotonic();report=_normalize_addresses(supplement,cache_dir/"addresses.brfacts");elapsed=time.monotonic()-started;entries["addresses"]=_entry("addresses",report,cache_dir/"addresses.brfacts",route_sources["addresses"],elapsed);run["blocks"]["addresses"]={"status":"DONE",**entries["addresses"]}
    if "areas" in stale:
        assert supplement is not None;started=time.monotonic();report=_normalize_areas(staged["areas"],supplement,cache_dir/"areas.baf");elapsed=time.monotonic()-started;entries["areas"]=_entry("areas",report,cache_dir/"areas.baf",route_sources["areas"],elapsed);run["blocks"]["areas"]={"status":"DONE",**entries["areas"]}
    _atomic_json(manifest_path,{"format":CACHE_FORMAT,"source":composite,"routes":entries});run.update({"status":"DONE","completed_at":_now(),"source":composite});_atomic_json(cache_dir/"last_run.json",run)
    return {route:cache_dir/_route_filename(route) for route in requested}
