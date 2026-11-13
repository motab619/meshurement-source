#!/usr/bin/env bash
# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

# Shared settings for the tile scripts. Sourced, not run.
# Everything big lives under $MESH_TILES_DIR (default ~/mesh-tiles), never in
# the repo.

set -euo pipefail

TILES_TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MESH_TILES_DIR="${MESH_TILES_DIR:-$HOME/mesh-tiles}"
# Big plain files (downloads, DEMs, outputs) can live on a network drive:
# MESH_TILES_BIG_DIR=/Volumes/MiniSlo/develop/mesh-tiles. SQLite files
# (.mbtiles) stay under MESH_TILES_DIR: SQLite over SMB is slow and unsafe.
MESH_TILES_BIG_DIR="${MESH_TILES_BIG_DIR:-$MESH_TILES_DIR}"
DL="$MESH_TILES_BIG_DIR/downloads"   # OSM extracts, planetiler + its sources
WORK="$MESH_TILES_DIR/work"          # SQLite intermediates (mbtiles)
BIGWORK="$MESH_TILES_BIG_DIR/work"   # GeoTIFF / FlatGeobuf intermediates
OUT="$MESH_TILES_BIG_DIR/out"        # the .pmtiles to upload
mkdir -p "$DL" "$WORK" "$BIGWORK" "$OUT"

# Region table: name -> bbox (W,S,E,N), Geofabrik extract, zooms, and the
# clip: STATES (USPS codes, union of the Census state outlines) and/or
# CIRCLES ("lat,lon,km;..." geodesic circles, intersected with the STATES
# outline when both are set). Tiles outside the clip are not built and the
# app falls back to OSM for them (a missing tile = OSM tile). One region per
# Geofabrik extract; the app tries regions in order, so boxes may overlap.
# State lists checked against the Geofabrik .poly files on 2026-11-05.
#   west      : Geofabrik "us-west" (11 states)
#   midwest   : Geofabrik "us-midwest" (12 states)
#   south     : Geofabrik "us-south" (16 states + DC)
#   northeast : Geofabrik "us-northeast" (9 states)
#   hawaii    : Geofabrik "us/hawaii", main islands
#   alaska    : Geofabrik "us/alaska", 161 km (100 mi) around Anchorage,
#               Fairbanks and Juneau, cut to the state outline
#   socal     : Geofabrik "socal" (Southern California), the first release
#   coachella : Coachella Valley (Palm Springs to Indio), for quick tests
# REGION_DEM_SRC overrides the elevation source for a region (empty = the
# USGS 1/3 arc-second seamless VRT, which covers CONUS, HI and AK).
GEOFABRIK="https://download.geofabrik.de/north-america"
DEM_13="/vsicurl/https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/13/TIFF/USGS_Seamless_DEM_13.vrt"
ALL_REGIONS="hawaii alaska west midwest south northeast"
set_region() {
  REGION="${1:-west}"
  STATES=""; CIRCLES=""; REGION_DEM_SRC=""
  STREETS_MINZOOM=8; STREETS_MAXZOOM=15
  TERRAIN_MINZOOM=8; TERRAIN_MAXZOOM=13
  CONTOURS_MINZOOM=13; CONTOURS_MAXZOOM=15
  case "$REGION" in
    west)
      BBOX="-124.90,31.20,-102.00,49.10"
      PBF_URL="$GEOFABRIK/us-west-latest.osm.pbf"
      STATES="AZ,CA,CO,ID,MT,NV,NM,OR,UT,WA,WY"
      ;;
    midwest)
      # N 49.45, not 49.40: Minnesota's Northwest Angle reaches 49.38 + buffer.
      BBOX="-104.10,35.90,-80.40,49.45"
      PBF_URL="$GEOFABRIK/us-midwest-latest.osm.pbf"
      STATES="IL,IN,IA,KS,MI,MN,MO,NE,ND,OH,SD,WI"
      ;;
    south)
      BBOX="-106.70,24.40,-75.00,40.70"
      PBF_URL="$GEOFABRIK/us-south-latest.osm.pbf"
      STATES="AL,AR,DE,DC,FL,GA,KY,LA,MD,MS,NC,OK,SC,TN,TX,VA,WV"
      ;;
    northeast)
      BBOX="-80.60,38.80,-66.90,47.50"
      PBF_URL="$GEOFABRIK/us-northeast-latest.osm.pbf"
      STATES="CT,ME,MA,NH,NJ,NY,PA,RI,VT"
      ;;
    hawaii)
      BBOX="-160.30,18.85,-154.75,22.30"
      PBF_URL="$GEOFABRIK/us/hawaii-latest.osm.pbf"
      STATES="HI"
      ;;
    alaska)
      BBOX="-153.00,56.80,-131.60,66.30"
      PBF_URL="$GEOFABRIK/us/alaska-latest.osm.pbf"
      STATES="AK"
      CIRCLES="61.2181,-149.9003,161;64.8378,-147.7164,161;58.3019,-134.4197,161"
      ;;
    socal)
      BBOX="-120.80,32.50,-114.10,35.80"
      PBF_URL="$GEOFABRIK/us/california/socal-latest.osm.pbf"
      ;;
    coachella)
      BBOX="-116.60,33.55,-116.05,33.95"
      PBF_URL="$GEOFABRIK/us/california/socal-latest.osm.pbf"
      STREETS_MAXZOOM=16; TERRAIN_MAXZOOM=14
      ;;
    *)
      echo "unknown region '$REGION' ($ALL_REGIONS socal coachella; add more in common.sh)" >&2
      exit 2
      ;;
  esac
  # Overrides: BBOX=..., STREETS_MAXZOOM=..., etc. from the environment.
  BBOX="${BBOX_OVERRIDE:-$BBOX}"
  STREETS_MAXZOOM="${STREETS_MAXZOOM_OVERRIDE:-$STREETS_MAXZOOM}"
  TERRAIN_MAXZOOM="${TERRAIN_MAXZOOM_OVERRIDE:-$TERRAIN_MAXZOOM}"
  IFS=, read -r W S E N <<<"$BBOX"
  PBF="$DL/$(basename "$PBF_URL")"
  # Clip outlines (make_poly.sh), empty when the region is just its bbox.
  POLY=""; CUTLINE=""
  if [ -n "$STATES$CIRCLES" ]; then
    POLY="$BIGWORK/$REGION.poly"; CUTLINE="$BIGWORK/$REGION-outline.geojson"
  fi
}

# What the clip outline was built from; a change rebuilds it.
clip_spec() { echo "states=$STATES circles=$CIRCLES buffer=${BUFFER_DEG:-0.03}"; }

# Build the clip outlines for a multi-state region if they are missing.
# (Rebuilt when the region's STATES/CIRCLES changed since: the spec is kept
# beside it in <region>.clipspec.)
ensure_poly() {
  [ -z "$POLY" ] && return 0
  if [ -s "$POLY" ] && [ -s "$CUTLINE" ] &&
     [ "$(cat "$BIGWORK/$REGION.clipspec" 2>/dev/null)" = "$(clip_spec)" ]; then
    return 0
  fi
  bash "$TILES_TOOL_DIR/make_poly.sh" "$REGION"
}

# Tile mask for the streets render (render.mjs --tile-mask): every zoom-14
# tile the clip outline touches, one "x y" per line after the zoom. Needed
# because Planetiler's --polygon keeps the ocean tiles (water polygons fill
# the whole bounds). Rebuilt when the outline is newer.
MASK_ZOOM=14
ensure_mask() {
  MASK=""
  [ -z "$CUTLINE" ] && return 0
  MASK="$WORK/$REGION-mask-z$MASK_ZOOM.txt"
  [ -s "$MASK" ] && [ "$MASK" -nt "$CUTLINE" ] && return 0
  local o=20037508.342789244 r te merc="$WORK/$REGION-outline-3857.geojson" tif="$WORK/$REGION-mask.tif"
  r=$(python3 -c "print(2*$o/2**$MASK_ZOOM)")
  te=$(python3 -c "
import math
w,s,e,n=$W,$S,$E,$N
X=lambda l: l*$o/180
Y=lambda a: math.log(math.tan(math.pi/4+math.radians(a)/2))*$o/math.pi
print(X(w),Y(s),X(e),Y(n))")
  rm -f "$merc" "$tif"
  ogr2ogr -f GeoJSON -t_srs EPSG:3857 "$merc" "$CUTLINE"
  # shellcheck disable=SC2086
  gdal_rasterize -q -burn 1 -at -ot Byte -a_nodata 0 -init 0 -tr "$r" "$r" -tap -te $te \
    -co COMPRESS=DEFLATE "$merc" "$tif"
  gdal_translate -q -of XYZ "$tif" /vsistdout/ |
    awk -v R="$r" -v O="$o" -v Z="$MASK_ZOOM" 'BEGIN { print Z }
      $3 > 0 { printf "%d %d\n", int(($1 + O) / R), int((O - $2) / R) }' >"$MASK.part"
  mv "$MASK.part" "$MASK"
  rm -f "$merc" "$tif"
  echo "tile mask: $(($(wc -l <"$MASK") - 1)) z$MASK_ZOOM tiles touch the $REGION outline"
}

# Tools. Homebrew's openjdk@21 is keg-only, so look there too.
find_java() {
  for j in "${JAVA:-}" /opt/homebrew/opt/openjdk@21/bin/java /opt/homebrew/opt/openjdk/bin/java java; do
    [ -n "$j" ] && "$j" -version >/dev/null 2>&1 && { echo "$j"; return; }
  done
  echo "Java 21+ not found: brew install openjdk@21" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing '$1': $2" >&2; exit 1; }
}

# Download once (resumable), skip if present.
fetch() {
  local url="$1" dest="$2"
  if [ -s "$dest" ]; then echo "have $(basename "$dest")"; return; fi
  echo "downloading $url"
  curl -fL --retry 3 -C - -o "$dest.part" "$url"
  mv "$dest.part" "$dest"
}

size_of() { du -h "$1" | cut -f1; }

# Local disk guard: the SQLite intermediates and Planetiler's temp files are
# on the local disk (MESH_TILES_DIR), so refuse to start a step with less
# than MIN_FREE_GB (default 15) free there. Exits 3.
check_space() { # step-name
  local min="${MIN_FREE_GB:-15}" avail
  avail=$(df -Pk "$MESH_TILES_DIR" | awk 'NR==2 {print int($4 / 1048576)}')
  if [ "$avail" -lt "$min" ]; then
    echo "only $avail GB free on the local disk ($MESH_TILES_DIR), need $min GB" \
         "before '$1'; free some space (or MIN_FREE_GB=...)" >&2
    exit 3
  fi
  echo "[$(date '+%F %T')] $1 ($avail GB free locally)"
}

# Big-file dir must be there (a dropped network share would otherwise fail
# halfway through a step).
check_big_dir() {
  [ -d "$DL" ] && [ -w "$OUT" ] || {
    echo "MESH_TILES_BIG_DIR=$MESH_TILES_BIG_DIR is not mounted/writable" >&2; exit 4; }
}

# Delete a local MBTiles with its SQLite side files.
clean_mbtiles() {
  rm -f "$1" "$1-wal" "$1-shm" "$1-journal"
  echo "CLEAN: removed $1"
}

# MBTiles -> PMTiles into $OUT, via a .part file so an interrupted convert
# never looks finished. pmtiles' temp file (about the size of the tiles) goes
# to $BIGWORK, not the local disk. CLEAN=1 then deletes the local MBTiles.
convert_pmtiles() { # in.mbtiles out.pmtiles
  local tmp="$BIGWORK/pmtiles-tmp"
  mkdir -p "$tmp"
  check_big_dir
  rm -f "$2.part"
  pmtiles convert --tmpdir="$tmp" "$1" "$2.part"
  mv "$2.part" "$2"
  if [ "${CLEAN:-0}" = 1 ]; then clean_mbtiles "$1"; fi
}

report() {
  echo
  echo "== outputs in $OUT =="
  ls -lh "$OUT"/*.pmtiles 2>/dev/null | awk '{print $5"\t"$9}'
}
