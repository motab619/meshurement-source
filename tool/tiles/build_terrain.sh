#!/usr/bin/env bash
# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

# Terrain overlays: USGS 3DEP 1/3 arc-second DEM (public domain, read
# straight from the USGS cloud-optimized GeoTIFFs, only the bbox) ->
# gdaldem hillshade -> transparent shading -> raster PMTiles. With
# CONTOURS=1 also 100 ft contour lines as a second transparent PMTiles.
#
#   CONTOURS=1 tool/tiles/build_terrain.sh <region>   (see common.sh)
#
# Outputs: $OUT/<region>-terrain.pmtiles
#          $OUT/<region>-contours.pmtiles (CONTOURS=1)
# Re-runnable: existing intermediates and outputs are reused (FORCE=1
# rebuilds); every GDAL step writes a .part file first, so a killed run is
# never mistaken for a finished one. CLEAN=1 deletes the local MBTiles once
# the PMTiles is written. Each step refuses to start with < MIN_FREE_GB (15)
# free on the local disk.
#
# Elevation: the USGS 1/3 arc-second seamless VRT (CONUS, Hawaii and Alaska;
# checked 2026-11-05), or the region's REGION_DEM_SRC, or DEM_SRC=... from
# the environment. Outside the US use SRTM 1 arc-second instead:
# DEM_SRC=/path/to/srtm.vrt (tiles from https://earthexplorer.usgs.gov,
# NASA Earthdata login).

source "$(dirname "$0")/common.sh"
set_region "${1:-west}"
need gdalwarp "brew install gdal"
need gdaldem "brew install gdal"
need pmtiles "brew install pmtiles"

DEM_SRC="${DEM_SRC:-${REGION_DEM_SRC:-$DEM_13}}"
FORMAT="${FORMAT:-WEBP}"   # WEBP (smaller) or PNG
# Web Mercator metres per pixel at zoom z for 256 px tiles.
res_for_zoom() { python3 -c "print(2*20037508.342789244/256/2**$1)"; }
TR="$(res_for_zoom "$TERRAIN_MAXZOOM")"
export GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR GDAL_HTTP_MULTIPLEX=YES \
       GDAL_HTTP_VERSION=2 VSI_CACHE=TRUE GDAL_CACHEMAX=1024

DEM="$BIGWORK/$REGION-dem-3857-z$TERRAIN_MAXZOOM.tif"
SHADE="$BIGWORK/$REGION-hillshade.tif"
SHADE_RGBA="$BIGWORK/$REGION-hillshade-rgba.tif"
SHADE_MB="$WORK/$REGION-terrain.mbtiles"
RESULT="$OUT/$REGION-terrain.pmtiles"
CONT_RESULT="$OUT/$REGION-contours.pmtiles"
rebuild() { [ ! -s "$1" ] || [ "${FORCE:-0}" = 1 ]; }
part() { local f="$1"; echo "${f%.*}.part.${f##*.}"; }   # x.tif -> x.part.tif
GT_BIG=(-co COMPRESS=DEFLATE -co TILED=YES -co BIGTIFF=IF_SAFER)

echo "== $REGION terrain: bbox $BBOX, z$TERRAIN_MINZOOM-$TERRAIN_MAXZOOM ($TR m/px), DEM $DEM_SRC =="
check_big_dir
if ! rebuild "$RESULT" && { [ "${CONTOURS:-0}" != 1 ] || ! rebuild "$CONT_RESULT"; }; then
  echo "outputs exist (FORCE=1 rebuilds)"; report; exit 0
fi

# 1. DEM clipped to the bbox (and to the state outlines when the region has
#    them: outside is nodata, so those tiles come out transparent), in Web
#    Mercator on the tile grid (-tap).
ensure_poly
if rebuild "$DEM"; then
  check_space dem
  gdalwarp -overwrite -te "$W" "$S" "$E" "$N" -te_srs EPSG:4326 \
    ${CUTLINE:+-cutline "$CUTLINE"} \
    -t_srs EPSG:3857 -tr "$TR" "$TR" -tap -r bilinear -multi -wo NUM_THREADS=ALL_CPUS \
    -co COMPRESS=DEFLATE -co PREDICTOR=3 -co TILED=YES -co BIGTIFF=IF_SAFER \
    "$DEM_SRC" "$(part "$DEM")"
  mv "$(part "$DEM")" "$DEM"
fi
echo "DEM: $(size_of "$DEM")"

# 2. Hillshade. Mercator metres are stretched by 1/cos(lat) (~1.2 here), so
#    -z 1.5 gives a slightly exaggerated relief that reads well on a phone.
if rebuild "$SHADE"; then
  check_space hillshade
  gdaldem hillshade -multidirectional -compute_edges -z "${HILLSHADE_Z:-1.5}" \
    "${GT_BIG[@]}" "$DEM" "$(part "$SHADE")"
  mv "$(part "$SHADE")" "$SHADE"
fi

# 3. Grey shading -> dark, transparent overlay: flat ground (~180) almost
#    clear, shadows dark, sunlit slopes a faint highlight.
cat >"$WORK/hillshade-ramp.txt" <<'RAMP'
nv  0   0   0   0
1   25  30  45  190
120 25  30  45  110
170 25  30  45  25
185 0   0   0   0
215 255 255 240 0
255 255 255 240 70
RAMP
if rebuild "$SHADE_RGBA"; then
  check_space color-relief
  gdaldem color-relief -alpha "$SHADE" "$WORK/hillshade-ramp.txt" "$(part "$SHADE_RGBA")" \
    "${GT_BIG[@]}"
  mv "$(part "$SHADE_RGBA")" "$SHADE_RGBA"
fi

# 4. Tiles: base zoom from the raster, overviews down to the min zoom.
to_pmtiles() { # src.tif out.mbtiles out.pmtiles minzoom maxzoom
  local factors="" f=2 z
  if ! rebuild "$3"; then echo "have $(basename "$3")"; return; fi
  check_space "tiles $(basename "$3")"
  rm -f "$2" "$3"
  gdal_translate -of MBTILES -co TILE_FORMAT="$FORMAT" -co QUALITY=80 \
    -co ZOOM_LEVEL_STRATEGY=AUTO -co RESAMPLING=AVERAGE "$1" "$2"
  for ((z = $5 - 1; z >= $4; z--)); do factors="$factors $f"; f=$((f * 2)); done
  # shellcheck disable=SC2086
  [ -n "$factors" ] && gdaladdo -r average "$2" $factors
  check_space "pmtiles convert $(basename "$3")"
  convert_pmtiles "$2" "$3"
  echo "$(basename "$3"): $(size_of "$3")"
}
to_pmtiles "$SHADE_RGBA" "$SHADE_MB" "$RESULT" "$TERRAIN_MINZOOM" "$TERRAIN_MAXZOOM"

# 5. Optional contours: 100 ft lines, rasterized at the contour max zoom.
if [ "${CONTOURS:-0}" = 1 ]; then
  # FlatGeobuf, not GeoPackage: a plain streamable file, safe on a network
  # drive (GeoPackage is SQLite).
  CONT="$BIGWORK/$REGION-contours.fgb"
  CONT_TIF="$BIGWORK/$REGION-contours-rgba.tif"
  if rebuild "$CONT"; then
    check_space contours
    rm -f "$CONT" "$(part "$CONT")"
    gdal_contour -f FlatGeobuf -a elev_m -i "${CONTOUR_INTERVAL_M:-30.48}" "$DEM" "$(part "$CONT")"
    mv "$(part "$CONT")" "$CONT"
  fi
  CTR="$(res_for_zoom "$CONTOURS_MAXZOOM")"
  if rebuild "$CONT_TIF"; then
    check_space rasterize
    # Same extent as the DEM (Web Mercator metres: xmin ymin xmax ymax).
    read -r XMIN YMIN XMAX YMAX < <(gdalinfo -json "$DEM" | python3 -c '
import json, sys
c = json.load(sys.stdin)["cornerCoordinates"]
print(c["lowerLeft"][0], c["lowerLeft"][1], c["upperRight"][0], c["upperRight"][1])')
    gdal_rasterize -init 0 -burn 120 -burn 85 -burn 45 -burn 150 -ot Byte \
      -te "$XMIN" "$YMIN" "$XMAX" "$YMAX" \
      -tr "$CTR" "$CTR" -tap "${GT_BIG[@]}" \
      -co PHOTOMETRIC=RGB -co ALPHA=YES "$CONT" "$(part "$CONT_TIF")"
    mv "$(part "$CONT_TIF")" "$CONT_TIF"
  fi
  to_pmtiles "$CONT_TIF" "$WORK/$REGION-contours.mbtiles" \
    "$CONT_RESULT" "$CONTOURS_MINZOOM" "$CONTOURS_MAXZOOM"
fi

report
