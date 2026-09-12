# BRUR Gang-Violence Geospatial Research

Status: v0.1 — database-compatible geospatial companion
Coverage target: all incidents in the BRUR gang/network violence research corpus
Last research update: 2026-09-12

## Purpose

This file attaches geospatial information to incident IDs without duplicating person/event records. The target format is WGS84 decimal degrees (`latitude`, `longitude`) so the data can later move directly into a spatial database or GIS layer.

## Privacy precision rule

Use the most exact position supported by reliable public sources **except for private homes and family-linked residences**. For those, do not preserve a doorway, apartment, house number or exact parcel coordinate. Use a street, square, neighborhood or locality centroid instead.

This keeps the research spatially useful without creating a lookup table of real victims' or relatives' private homes.

## Precision classes

```text
EXACT_PUBLIC_SITE       = identifiable public square, station, venue, garage or other public-place feature
STREET_APPROX           = street known, exact point not independently verified
NEIGHBORHOOD_CENTROID   = only district/neighborhood is safely/usefully retained
LOCALITY_CENTROID       = only locality/municipality known
PRIVATE_SITE_WITHHELD   = source may identify a private address, but research stores only coarse position
UNKNOWN                 = not yet geocoded
```

## Coordinate record

```text
INCIDENT_ID:
LATITUDE:
LONGITUDE:
CRS: EPSG:4326
PRECISION_CLASS:
PRECISION_RADIUS_M:
LOCATION_LABEL:
SOURCE:
GEO_CONFIDENCE:
NOTES:
```

## Current geocoded incident layer

The coordinates below are research coordinates, not claims that every projectile/detonation occurred at the exact decimal point shown. `PRECISION_CLASS` must always be retained.

### Göteborg / Biskopsgården / Backa

```text
INCIDENT_ID: SE-2015-0001
LATITUDE: 57.71246
LONGITUDE: 11.89208
CRS: EPSG:4326
PRECISION_CLASS: EXACT_PUBLIC_SITE
PRECISION_RADIUS_M: 75
LOCATION_LABEL: Vårväderstorget, Biskopsgården, Göteborg
SOURCE: Mapcarta/OpenStreetMap Vårväderstorget feature; incident source SVT
GEO_CONFIDENCE: HIGH
```

```text
INCIDENT_ID: SE-2013-SUP-0003
LATITUDE: 57.72393
LONGITUDE: 11.89143
CRS: EPSG:4326
PRECISION_CLASS: EXACT_PUBLIC_SITE
PRECISION_RADIUS_M: 75
LOCATION_LABEL: Friskväderstorget, Biskopsgården, Göteborg
SOURCE: Wikidata Q10499229 / Göteborgs Stadsmuseum
GEO_CONFIDENCE: HIGH
```

```text
INCIDENT_ID: SE-2024-CGAMBINO
LATITUDE: 57.74950
LONGITUDE: 11.98239
CRS: EPSG:4326
PRECISION_CLASS: EXACT_PUBLIC_SITE
PRECISION_RADIUS_M: 120
LOCATION_LABEL: Selma Lagerlöfs torg / parking-garage area, Backa, Göteborg
SOURCE: Wikidata Q10665408; SVT murder reporting
GEO_CONFIDENCE: HIGH for square, MEDIUM for exact garage point
```

```text
INCIDENT_ID: SE-2012-0001 / SE-2012-SUP-0001
LATITUDE: 57.72
LONGITUDE: 11.89
CRS: EPSG:4326
PRECISION_CLASS: STREET_APPROX
PRECISION_RADIUS_M: 450
LOCATION_LABEL: Önskevädersgatan, Biskopsgården, Göteborg
GEO_CONFIDENCE: MEDIUM
```

```text
INCIDENT_ID: SE-2013-SUP-0001
LATITUDE: 57.72
LONGITUDE: 11.89
CRS: EPSG:4326
PRECISION_CLASS: STREET_APPROX
PRECISION_RADIUS_M: 500
LOCATION_LABEL: Köldgatan, Södra Biskopsgården, Göteborg
GEO_CONFIDENCE: MEDIUM
```

```text
INCIDENT_ID: SE-2013-0001 / SE-2013-SUP-0002
LATITUDE: 57.724
LONGITUDE: 11.892
CRS: EPSG:4326
PRECISION_CLASS: STREET_APPROX
PRECISION_RADIUS_M: 450
LOCATION_LABEL: Väderilsgatan, Biskopsgården, Göteborg
GEO_CONFIDENCE: MEDIUM
```

```text
INCIDENT_ID: SE-2016-0001
LATITUDE: 57.72
LONGITUDE: 11.89
CRS: EPSG:4326
PRECISION_CLASS: PRIVATE_SITE_WITHHELD
PRECISION_RADIUS_M: 700
LOCATION_LABEL: Dimvädersgatan/Biskopsgården area, Göteborg
GEO_CONFIDENCE: MEDIUM
NOTES: Apartment attack; exact residence deliberately not retained.
```

### Stockholm / Järva / south-west Stockholm

```text
INCIDENT_ID: SE-2017-0003
LATITUDE: 59.40139
LONGITUDE: 17.94444
CRS: EPSG:4326
PRECISION_CLASS: NEIGHBORHOOD_CENTROID
PRECISION_RADIUS_M: 900
LOCATION_LABEL: Kista, Stockholm
SOURCE: Wikidata Q1245744
GEO_CONFIDENCE: HIGH for neighborhood
```

```text
INCIDENT_ID: SE-2017-0002
LATITUDE: 59.27711
LONGITUDE: 17.90699
CRS: EPSG:4326
PRECISION_CLASS: NEIGHBORHOOD_CENTROID
PRECISION_RADIUS_M: 900
LOCATION_LABEL: Skärholmen, Stockholm
SOURCE: Wikidata Q500923
GEO_CONFIDENCE: HIGH for neighborhood
```

```text
INCIDENT_ID: SE-2017-0006
LATITUDE: 59.27547
LONGITUDE: 17.88658
CRS: EPSG:4326
PRECISION_CLASS: NEIGHBORHOOD_CENTROID
PRECISION_RADIUS_M: 900
LOCATION_LABEL: Vårberg, Stockholm
SOURCE: Apple Maps/Wikidata neighborhood coordinate
GEO_CONFIDENCE: HIGH for neighborhood
```

```text
INCIDENT_ID: SE-2017-0007
LATITUDE: 59.28333
LONGITUDE: 18.11667
CRS: EPSG:4326
PRECISION_CLASS: NEIGHBORHOOD_CENTROID
PRECISION_RADIUS_M: 900
LOCATION_LABEL: Östberga, Stockholm
SOURCE: Wikidata Q4357719
GEO_CONFIDENCE: HIGH for neighborhood
```

```text
INCIDENT_ID: SE-2017-0010
LATITUDE: 59.38806
LONGITUDE: 17.92861
CRS: EPSG:4326
PRECISION_CLASS: NEIGHBORHOOD_CENTROID
PRECISION_RADIUS_M: 800
LOCATION_LABEL: Rinkeby, Stockholm
SOURCE: Wikidata Q2575195
GEO_CONFIDENCE: HIGH for neighborhood
```

```text
INCIDENT_ID: SE-2023-0002
LATITUDE: 59.28333
LONGITUDE: 17.95000
CRS: EPSG:4326
PRECISION_CLASS: PRIVATE_SITE_WITHHELD
PRECISION_RADIUS_M: 1000
LOCATION_LABEL: Västberga, Stockholm
SOURCE: Wikidata Q4357634 + incident reporting
GEO_CONFIDENCE: HIGH for district
NOTES: Family residence attacked; exact home coordinate deliberately withheld.
```

```text
INCIDENT_ID: SE-2025-0001
LATITUDE: 59.28611
LONGITUDE: 17.96472
CRS: EPSG:4326
PRECISION_CLASS: NEIGHBORHOOD_CENTROID
PRECISION_RADIUS_M: 800
LOCATION_LABEL: Fruängen, Stockholm
SOURCE: Wikidata Q2552334
GEO_CONFIDENCE: HIGH for district
```

```text
INCIDENT_ID: ROZH-2019-BLACKEBERG
LATITUDE: 59.34806
LONGITUDE: 17.88194
CRS: EPSG:4326
PRECISION_CLASS: PRIVATE_SITE_WITHHELD
PRECISION_RADIUS_M: 900
LOCATION_LABEL: Blackeberg, Stockholm
SOURCE: Wikidata Q113546 + SVT/Aftonbladet murder reporting
GEO_CONFIDENCE: HIGH for district
NOTES: Artist was killed outside/near home; exact residence is not retained.
```

### Uppsala

```text
INCIDENT_ID: SE-2017-0008
LATITUDE: 59.85281
LONGITUDE: 17.56389
CRS: EPSG:4326
PRECISION_CLASS: NEIGHBORHOOD_CENTROID
PRECISION_RADIUS_M: 900
LOCATION_LABEL: Stenhagen, Uppsala
SOURCE: Wikidata Q10678495
GEO_CONFIDENCE: HIGH for district
```

```text
INCIDENT_ID: SE-2023-SUP-0001
LATITUDE: 59.88
LONGITUDE: 17.66
CRS: EPSG:4326
PRECISION_CLASS: PRIVATE_SITE_WITHHELD
PRECISION_RADIUS_M: 1400
LOCATION_LABEL: Gränby, Uppsala
GEO_CONFIDENCE: MEDIUM
NOTES: Relative-targeting murder; retain neighborhood only.
```

```text
INCIDENT_ID: SE-2023-SUP-0002
LATITUDE: 59.8528
LONGITUDE: 17.5639
CRS: EPSG:4326
PRECISION_CLASS: PRIVATE_SITE_WITHHELD
PRECISION_RADIUS_M: 1200
LOCATION_LABEL: Stenhagen, Uppsala
GEO_CONFIDENCE: HIGH for district
NOTES: Wrong-address/relative-targeting incident; exact residence withheld.
```

### Södertälje / Huddinge

```text
INCIDENT_ID: SE-2024-0002
LATITUDE: 59.17666
LONGITUDE: 17.60789
CRS: EPSG:4326
PRECISION_CLASS: EXACT_PUBLIC_SITE
PRECISION_RADIUS_M: 150
LOCATION_LABEL: Hovsjö centrum, Södertälje
SOURCE: Mapcarta/OpenStreetMap Hovsjö centrum position
GEO_CONFIDENCE: HIGH
```

```text
INCIDENT_ID: SE-2024-0001
LATITUDE: 59.22356
LONGITUDE: 17.93882
CRS: EPSG:4326
PRECISION_CLASS: NEIGHBORHOOD_CENTROID
PRECISION_RADIUS_M: 1000
LOCATION_LABEL: Flemingsberg, Huddinge
SOURCE: Wikidata Q21667208
GEO_CONFIDENCE: HIGH for district
```

### Malmö

The current corpus contains several incidents where reporting names a street but the exact event point has not yet been independently geocoded from a stable public map source. Do **not** invent decimal precision.

```text
INCIDENT_ID: SE-2012-SUP-0002
LOCATION_LABEL: Kantatgatan, Malmö
PRECISION_CLASS: STREET_APPROX
LATITUDE: pending_verified_geocode
LONGITUDE: pending_verified_geocode
```

```text
INCIDENT_ID: SE-2017-0011
LOCATION_LABEL: Docentgatan, Malmö
PRECISION_CLASS: STREET_APPROX
LATITUDE: pending_verified_geocode
LONGITUDE: pending_verified_geocode
```

```text
INCIDENT_ID: SE-2017-0012
LOCATION_LABEL: Kronetorpsgatan, Malmö
PRECISION_CLASS: STREET_APPROX
LATITUDE: pending_verified_geocode
LONGITUDE: pending_verified_geocode
```

```text
INCIDENT_ID: SE-2017-0013
LOCATION_LABEL: Ramels väg, Malmö
PRECISION_CLASS: STREET_APPROX
LATITUDE: pending_verified_geocode
LONGITUDE: pending_verified_geocode
```

```text
INCIDENT_ID: SE-2017-0014
LOCATION_LABEL: Eriksfältsgatan, Malmö
PRECISION_CLASS: STREET_APPROX
LATITUDE: pending_verified_geocode
LONGITUDE: pending_verified_geocode
```

## Database conversion note

Recommended later columns:

```text
incident_id TEXT PRIMARY KEY / FK
latitude REAL NULL
longitude REAL NULL
crs TEXT DEFAULT 'EPSG:4326'
precision_class TEXT
precision_radius_m INTEGER
location_label TEXT
geo_source TEXT
geo_confidence TEXT
private_location_withheld BOOLEAN
```

Never discard `precision_class` or `precision_radius_m`: a neighborhood centroid is analytically useful but must never be mistaken for the exact crime scene.

## Geocoding backlog

Priority order:

1. public squares/venues/stations/garages with reliable open-map coordinates;
2. street-level public incidents;
3. locality-only incidents;
4. private residences remain intentionally coarse even if exact addresses are published.

The geospatial layer should eventually contain one row for every stable incident ID in:

- `gang_violence_incident_research.md`
- `gang_violence_source_supplement.md`
- `gang_violence_third_party_research.md`

Unknown coordinates remain explicit `pending_verified_geocode`; they are never guessed.
