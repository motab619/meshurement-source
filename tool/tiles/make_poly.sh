#!/usr/bin/env bash
# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

# Clip outlines for a region: the union of its STATES from the US Census
# cartographic boundaries (1:5M, public domain), buffered a little outward
# so border tiles are built rather than left to OSM; with CIRCLES
# ("lat,lon,km;...") the union of those geodesic circles, cut to the state
# outline (Alaska: 161 km around three cities, no ocean).
#
#   tool/tiles/make_poly.sh west
#
# Writes $BIGWORK/<region>.poly (osmosis format, for Planetiler --polygon),
# $BIGWORK/<region>-outline.geojson (for gdalwarp -cutline) and
# $BIGWORK/<region>.clipspec (what they were built from).

source "$(dirname "$0")/common.sh"
set_region "${1:-west}"
[ -n "$STATES$CIRCLES" ] || { echo "region '$REGION' has no STATES/CIRCLES; nothing to clip" >&2; exit 2; }
need ogr2ogr "brew install gdal"

CB_URL="https://www2.census.gov/geo/tiger/GENZ2023/shp/cb_2023_us_state_5m.zip"
CB="$DL/$(basename "$CB_URL")"
fetch "$CB_URL" "$CB"

BUFFER_DEG="${BUFFER_DEG:-0.03}"   # ~3 km
echo "== $REGION outline: states ${STATES:-none}, circles ${CIRCLES:-none}, buffer $BUFFER_DEG° =="
RAW="$WORK/$REGION-outline-raw.geojson"
rm -f "$RAW"
if [ -z "$CIRCLES" ]; then
  IN_LIST="'$(echo "$STATES" | sed "s/,/','/g")'"
  ogr2ogr -f GeoJSON "$RAW" "/vsizip/$CB" -dialect SQLite \
    -sql "SELECT ST_Buffer(ST_Union(geometry), $BUFFER_DEG) AS geometry
          FROM cb_2023_us_state_5m WHERE STUSPS IN ($IN_LIST)" \
    -lco COORDINATE_PRECISION=4
else
  # Circles (spherical, 128 points) as a layer next to the states in one
  # scratch GeoPackage (local: SQLite), so one SQL statement can intersect.
  CIRC="$WORK/$REGION-circles.geojson"
  GPKG="$WORK/$REGION-clip.gpkg"
  python3 - "$CIRCLES" "$CIRC" <<'PY2'
import json, math, sys
spec, out = sys.argv[1:]
R = 6371.0088
feats = []
for c in spec.split(";"):
    lat, lon, km = (float(v) for v in c.split(","))
    p1, l1, d = math.radians(lat), math.radians(lon), km / R
    ring = []
    for i in range(129):
        b = 2 * math.pi * (i % 128) / 128
        p2 = math.asin(math.sin(p1) * math.cos(d) + math.cos(p1) * math.sin(d) * math.cos(b))
        l2 = l1 + math.atan2(math.sin(b) * math.sin(d) * math.cos(p1),
                             math.cos(d) - math.sin(p1) * math.sin(p2))
        ring.append([round(math.degrees(l2), 5), round(math.degrees(p2), 5)])
    feats.append({"type": "Feature", "properties": {},
                  "geometry": {"type": "Polygon", "coordinates": [ring]}})
json.dump({"type": "FeatureCollection", "features": feats}, open(out, "w"))
PY2
  rm -f "$GPKG"
  # Census outlines are NAD83 (EPSG:4269); the circles are tagged the same
  # (metre-level difference from WGS84) so SpatiaLite will intersect them.
  ogr2ogr -f GPKG "$GPKG" "/vsizip/$CB" -nln states -nlt MULTIPOLYGON
  ogr2ogr -update -f GPKG "$GPKG" "$CIRC" -nln circles -a_srs EPSG:4269
  if [ -n "$STATES" ]; then
    IN_LIST="'$(echo "$STATES" | sed "s/,/','/g")'"
    SQL="SELECT ST_Intersection(
           (SELECT ST_Buffer(ST_Union(geom), $BUFFER_DEG) FROM states WHERE STUSPS IN ($IN_LIST)),
           (SELECT ST_Union(geom) FROM circles)) AS geometry"
  else
    SQL="SELECT ST_Union(geom) AS geometry FROM circles"
  fi
  ogr2ogr -f GeoJSON "$RAW" "$GPKG" -dialect SQLite -sql "$SQL" -lco COORDINATE_PRECISION=4
  rm -f "$GPKG" "$CIRC"
fi

# Normalise to one (Multi)Polygon (an intersection can come back as a
# GeometryCollection), write the cutline and the osmosis .poly.
python3 - "$RAW" "$CUTLINE" "$POLY" "$REGION" <<'PY'
import json, sys
raw, cutline, poly, name = sys.argv[1:]
g = json.load(open(raw))["features"][0]["geometry"]
def polys_of(g):
    if g["type"] == "Polygon": return [g["coordinates"]]
    if g["type"] == "MultiPolygon": return g["coordinates"]
    if g["type"] == "GeometryCollection":
        return [p for sub in g["geometries"] for p in polys_of(sub)]
    return []
polys = polys_of(g)
assert polys, "empty clip outline"
json.dump({"type": "FeatureCollection", "features": [{"type": "Feature", "properties": {},
           "geometry": {"type": "MultiPolygon", "coordinates": polys}}]}, open(cutline, "w"))
with open(poly, "w") as f:
    f.write(name + "\n")
    n = 0
    for p in polys:
        for i, ring in enumerate(p):
            n += 1
            f.write(("!" if i else "") + str(n) + "\n")
            for lon, lat in ring:
                f.write(f"   {lon:.4f}   {lat:.4f}\n")
            f.write("END\n")
    f.write("END\n")
print(f"{poly}: {n} rings")
PY
rm -f "$RAW"
clip_spec >"$BIGWORK/$REGION.clipspec"
