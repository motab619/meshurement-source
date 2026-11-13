#!/usr/bin/env bash
# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

# Streets basemap: Geofabrik OSM extract -> Planetiler (OpenMapTiles vector
# MBTiles) -> MapLibre Native raster render -> raster PMTiles.
#
#   tool/tiles/build_streets.sh <region>   (see common.sh)
#
# Output: $OUT/<region>-streets.pmtiles. Re-runnable: finished steps are
# skipped (FORCE=1 redoes Planetiler; delete the raster mbtiles to
# re-render). CLEAN=1 deletes the local vector and raster MBTiles once the
# PMTiles is written. Each step refuses to start with < MIN_FREE_GB (15)
# free on the local disk.

source "$(dirname "$0")/common.sh"
set_region "${1:-west}"
need curl "install curl"
need pmtiles "brew install pmtiles"
JAVA_BIN="$(find_java)"

VECTOR="$WORK/$REGION-vector.mbtiles"
RASTER="$WORK/$REGION-streets-raster.mbtiles"
RESULT="$OUT/$REGION-streets.pmtiles"
PLANETILER="$DL/planetiler.jar"
PLANETILER_URL="${PLANETILER_URL:-https://github.com/onthegomap/planetiler/releases/latest/download/planetiler.jar}"

echo "== $REGION streets: bbox $BBOX, raster z$STREETS_MINZOOM-$STREETS_MAXZOOM =="
check_big_dir

# 1. Sources (and the state outlines for a clipped region).
fetch "$PBF_URL" "$PBF"
fetch "$PLANETILER_URL" "$PLANETILER"
ensure_poly
ensure_mask
echo "OSM extract: $(size_of "$PBF")"

# 2. Vector tiles (OpenMapTiles schema), clipped to the bbox, and to the
#    state outlines when the region has them (only tiles touching the
#    outline are written). --download fetches Natural Earth, OSM water
#    polygons and lake centerlines once (~1.3 GB) into $DL/planetiler.
#    --download only when one is missing: with it Planetiler asks the
#    upstream servers for sizes even when the files are there, and fails
#    when one of them doesn't answer.
#    Temp files go to the local disk ($WORK, never the network drive: they
#    are memory-mapped), compressed (PL_COMPRESS_TEMP=0 to turn off), and
#    are removed afterwards. Output goes to a .part file first so a killed
#    run is never mistaken for a finished one.
PL_DL="$DL/planetiler"
PL_TMP="$WORK/planetiler-tmp-$REGION"
PL_DOWNLOAD=""
for f in natural_earth_vector.sqlite.zip water-polygons-split-3857.zip lake_centerline.shp.zip; do
  [ -s "$PL_DL/$f" ] || PL_DOWNLOAD="--download"
done
if [ ! -s "$VECTOR" ] || [ "${FORCE:-0}" = 1 ]; then
  check_space planetiler
  VECTOR_PART="$WORK/$REGION-vector.part.mbtiles"
  rm -rf "$PL_TMP" "$VECTOR_PART"
  "$JAVA_BIN" -Xmx"${JAVA_HEAP:-4g}" -jar "$PLANETILER" \
    --osm-path="$PBF" \
    $PL_DOWNLOAD --download-dir="$PL_DL" \
    --tmpdir="$PL_TMP" --compress-temp="$([ "${PL_COMPRESS_TEMP:-1}" = 1 ] && echo true || echo false)" \
    --bounds="$BBOX" ${POLY:+--polygon="$POLY"} \
    --maxzoom=14 \
    --output="$VECTOR_PART" --force
  mv "$VECTOR_PART" "$VECTOR"
  rm -rf "$PL_TMP"
fi
echo "vector tiles: $(size_of "$VECTOR")"

# 3. Raster render (node + MapLibre Native + sharp, installed outside the
#    repo). MapLibre Native ships prebuilt binaries for LTS Node releases;
#    NODE=... picks one, default `npx node@22`.
RENDER_DIR="$MESH_TILES_DIR/tools/render"
mkdir -p "$RENDER_DIR"
cp "$TILES_TOOL_DIR/render/package.json" "$TILES_TOOL_DIR/render/render.mjs" \
   "$TILES_TOOL_DIR/render/style.json" "$RENDER_DIR/"
if [ -n "${NODE:-}" ]; then NODE_CMD=("$NODE"); else NODE_CMD=(npx -y node@22); fi
NPM_CMD=(npx -y -p node@22 npm)
[ -d "$RENDER_DIR/node_modules/@maplibre" ] || (cd "$RENDER_DIR" && "${NPM_CMD[@]}" install --no-audit --no-fund)
check_space render
"${NODE_CMD[@]}" "$RENDER_DIR/render.mjs" \
  --vector "$VECTOR" --out "$RASTER" --bbox "$BBOX" \
  --minzoom "$STREETS_MINZOOM" --maxzoom "$STREETS_MAXZOOM" \
  --scale "${SCALE:-2}" --format "${FORMAT:-webp}" --quality "${QUALITY:-80}" \
  --glyphs "$DL/glyphs" ${POLY:+--clip-to-source 1} ${MASK:+--tile-mask "$MASK"}
echo "raster mbtiles: $(size_of "$RASTER")"

# 4. PMTiles (CLEAN=1: the raster MBTiles goes after the convert, the
#    vector MBTiles with it).
check_space "pmtiles convert"
convert_pmtiles "$RASTER" "$RESULT"
if [ "${CLEAN:-0}" = 1 ]; then clean_mbtiles "$VECTOR"; fi
pmtiles show "$RESULT" | head -20
echo "streets: $RESULT ($(size_of "$RESULT"))"
report
