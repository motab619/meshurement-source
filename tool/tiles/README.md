<!--
Meshurement - maps LoRa mesh radio coverage.
Copyright (C) 2026 Andy Brunker (Plateau Nerd)
SPDX-License-Identifier: GPL-3.0-or-later
Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
-->

# Self-hosted map tiles

These scripts build the map tiles the app loads from our own server (S3 +
CloudFront) instead of `tile.openstreetmap.org`, whose
[tile policy](https://operations.osmfoundation.org/policies/tiles/) rules out
heavy use by a distributed app. Outside the region we host, the app still
falls back to OSM tiles. This is also the groundwork for Phase 6 (offline map
packs, `docs/roadmap.md`): a pack is the same PMTiles file stored on the
phone.

Two map styles, picked with the layers button on the maps:

| Style | Layers | Files |
|---|---|---|
| Standard | streets | `<region>-streets.pmtiles` |
| Terrain | streets + hillshade (+ contours) | `+ <region>-terrain.pmtiles`, `<region>-contours.pmtiles` |

Satellite is out of scope.

Nothing here touches the repo's contents: downloads, intermediates and
outputs all live under `$MESH_TILES_DIR` (default `~/mesh-tiles/`). The big
plain files (downloads, DEMs, contour lines, finished `.pmtiles`) can go on
a network drive with `MESH_TILES_BIG_DIR` (Andy's:
`/Volumes/MiniSlo/develop/mesh-tiles`); the SQLite intermediates
(`.mbtiles`) always stay local, because SQLite over SMB is slow and unsafe.
Never commit tile data.

## Route: raster PMTiles, our own reader

What flutter_map 8 can consume (checked on pub.dev, October 2026):

- **Vector**: `vector_map_tiles` 8.0.0 needs flutter_map ^7 (only a
  10.0.0 beta moves on), and `vector_map_tiles_pmtiles` 1.5.0 is pinned to
  `vector_map_tiles` ^8. Neither works with flutter_map 8 today.
- **Raster**: `flutter_map_pmtiles` 1.0.5 accepts flutter_map <9, but it
  depends on `pmtiles` ^1.2, which needs `protobuf` ^3. The app needs
  `protobuf` ^4 for the vendored Meshtastic protos, so it doesn't resolve
  (`pmtiles` 2.x moved to `protobuf` ^6 and `latlong2` ^0.10, also
  incompatible).

So the app reads **raster PMTiles** with a small PMTiles v3 reader of its own
(`lib/data/tiles/`, ~300 lines, no new packages): header, gzip directories,
leaf directories, Hilbert tile ids, from a local file or over HTTP range
requests. Raster keeps the phone side trivial (just images, same as OSM
tiles), renders identically on every phone, and works offline the moment the
file is on disk. The cost is file size (each zoom is stored as images rather
than geometry) and labels baked in at one size. Vector would be ~5-10x
smaller and restylable, and can come later if `vector_map_tiles` gets a
flutter_map 8 release; the streets pipeline already produces OpenMapTiles
vector tiles as its middle step, so switching would only drop the render
step.

How the app picks tiles (`lib/utils/map_tiles.dart`,
`lib/ui/widgets/base_map_layers.dart`): per tile, if the tile lies entirely
inside `coveredBounds` it is read from the PMTiles file; otherwise (or if the
file can't be reached, **or the file has no such tile**) the OSM tile is used
for streets, and overlays are left blank. That last rule is what lets a
multi-state region be one file clipped to the state outlines: tiles over
Mexico, Canada or a neighbouring state are simply not built, so the app
shows OSM there instead of an empty tile of ours. Zooming past the file's
max zoom upscales the deepest tile. A Terrain map centred outside the
region shows a one-line hint ("No hillshade here"). With every URL `null`
the map is exactly the old OSM `TileLayer`.

## Prerequisites (macOS, Homebrew)

```bash
brew install gdal pmtiles openjdk@21   # GDAL 3.x, go-pmtiles, Java for Planetiler
# node is only needed for the streets render; the script uses `npx node@22`
# because MapLibre Native ships prebuilt binaries for LTS Node versions.
```

## Regions

Defined in `common.sh` (`set_region`); add more there. The hosted set
(decided 2026-11-05) is the lower 48, Hawaii and 100 miles around Alaska's
three biggest cities, as **separate region files, one per Geofabrik
extract**: the app routes each tile to the first region whose bounds hold
it and falls back to OSM for a tile the file doesn't have, so the boxes may
overlap and be generous.

| Region | Geofabrik extract | Clip | bbox (W,S,E,N) |
|---|---|---|---|
| `west` | `us-west` (3.3 GB) | AZ CA CO ID MT NV NM OR UT WA WY | -124.90,31.20,-102.00,49.10 |
| `midwest` | `us-midwest` (2.4 GB) | IL IN IA KS MI MN MO NE ND OH SD WI | -104.10,35.90,-80.40,49.45 |
| `south` | `us-south` (3.9 GB) | AL AR DE DC FL GA KY LA MD MS NC OK SC TN TX VA WV | -106.70,24.40,-75.00,40.70 |
| `northeast` | `us-northeast` (1.7 GB) | CT ME MA NH NJ NY PA RI VT | -80.60,38.80,-66.90,47.50 |
| `hawaii` | `us/hawaii` (26 MB) | HI (main islands) | -160.30,18.85,-154.75,22.30 |
| `alaska` | `us/alaska` (137 MB) | AK ∩ 161 km circles around Anchorage, Fairbanks, Juneau | -153.00,56.80,-131.60,66.30 |
| `socal` (v1, 2026-10) | `us/california/socal` | bbox only | -120.80,32.50,-114.10,35.80 |
| `coachella` (quick test) | `us/california/socal` | bbox only | -116.60,33.55,-116.05,33.95 |

Zooms everywhere: streets z8-15, hillshade z8-13, contours z13-15
(coachella: streets to z16, hillshade to z14).

The state lists were checked on 2026-11-05 against Geofabrik's own region
outlines (`https://download.geofabrik.de/north-america/us-<region>.poly`,
each state counted when more than half of it lies inside): they match the
table. (`us-pacific` is just HI + AK; we use the two state extracts
instead.) The bboxes were checked against the Census state outlines plus
the 0.03° buffer: the midwest's north edge went from 49.40 to 49.45 for
Minnesota's Northwest Angle (49.38 + buffer); the others fit as given.

**Clip.** For a region with `STATES` the clip is the union of those states
from the US Census 1:5M cartographic boundaries, buffered 0.03° (~3 km)
outward so border tiles are built rather than left to OSM. For `CIRCLES`
(`"lat,lon,km;..."`, so far only Alaska) `make_poly.sh` draws 128-point
spherical circles (Python, stdlib) and intersects their union with the
buffered state outline, so open ocean and Canada are not built (the Alaska
clip is 36 rings: the circles' coastline and islands). `make_poly.sh` runs
automatically and rebuilds when the region's `STATES`/`CIRCLES` change
(`<region>.clipspec` beside the outline). The clip is applied three ways:
Planetiler `--polygon`, the renderer, and gdalwarp `-cutline`.
Planetiler's `--polygon` drops land tiles outside the outline but **not
ocean tiles** (the water polygons fill the whole bbox: Hawaii's vector file
had 42,907 of the bbox's 42,926 z14 tiles), so the streets build also
writes a **tile mask** (`ensure_mask` in `common.sh`: the outline
rasterized with `gdal_rasterize -at` on the z14 tile grid, one `x y` line
per touched tile) and `render.mjs --tile-mask` renders only tiles inside
it (Hawaii: 24k of the bbox's 228k tiles). The terrain DEM is cut to the
outline, and GDAL's MBTiles writer skips fully transparent tiles, so the
overlays stop at the outline too.

The `socal` bbox was *not* clipped, which is why its tiles showed empty
land over Yuma, Mexicali and Lake Havasu (the extract stops at the state
line). Overrides: `BBOX_OVERRIDE=W,S,E,N`, `STREETS_MAXZOOM_OVERRIDE=…`,
`TERRAIN_MAXZOOM_OVERRIDE=…`, `MESH_TILES_DIR=…`, `MESH_TILES_BIG_DIR=…`,
`DEM_SRC=…`.

### Elevation sources (checked 2026-11-05)

All regions use the USGS 3DEP seamless 1/3 arc-second VRT
(`prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/13/TIFF/USGS_Seamless_DEM_13.vrt`,
1,420 one-degree tiles). Despite the name it is not CONUS-only:

- **Hawaii**: every 1° tile over the main islands is in it
  (n19w156 … n23w161); Mauna Kea reads 4,207 m.
- **Alaska**: every 1° tile touching the Anchorage and Fairbanks circles is
  in it; around Juneau 7 tiles are missing (n58w132, n58w138, n59w132/133,
  n60w132/133/134), and none of them holds any Alaska land (Census
  outline): they are Canada and open sea, which the clip drops anyway.
  36 random points inside the circles: real elevations on land, 0 on sea,
  nodata only in Canada/sea.
- The 1 arc-second VRT (`…/1/TIFF/USGS_Seamless_DEM_1.vrt`, 3,782 tiles)
  also covers HI and AK (and the Canadian side near Juneau); the 2
  arc-second VRT is Alaska-only (504 tiles, no HI). Neither is needed now.

A region can still override the source in the table (`REGION_DEM_SRC`,
e.g. the 1 arc-second VRT), and `DEM_SRC=…` in the environment overrides
both.

## Build

One region by hand:

```bash
tool/tiles/build_streets.sh coachella            # -> $OUT/coachella-streets.pmtiles
CONTOURS=1 tool/tiles/build_terrain.sh coachella  # -> coachella-terrain.pmtiles, coachella-contours.pmtiles
```

All of them, one after the other (the queue):

```bash
nohup tool/tiles/build_all.sh >~/mesh-tiles/logs/queue.log 2>&1 &
tool/tiles/build_all.sh hawaii alaska     # just these, in this order
```

`build_all.sh` runs `build_streets.sh` then `CONTOURS=1 build_terrain.sh`
per region (default order: hawaii alaska west midwest south northeast),
skips a step whose outputs are already in `$OUT`, logs each step to
`~/mesh-tiles/logs/<region>-{streets,terrain}.log`, carries on with the
next step/region when one fails and prints a summary (exit 1 if anything
failed). Defaults: `MESH_TILES_BIG_DIR=/Volumes/MiniSlo/develop/mesh-tiles`,
`JAVA_HEAP=12g`, `CLEAN=1`. It holds a `caffeinate -i` while it runs.
Re-running it after a failure picks up where it stopped.

Every step is re-runnable: Planetiler and the GDAL steps write to a
`.part` file and rename it when done, and `pmtiles convert` writes
`<file>.pmtiles.part`, so a killed run is never mistaken for a finished
one; `FORCE=1` redoes Planetiler and the GDAL steps; the renderer skips
tiles already rendered.

**Streets** (`build_streets.sh`):

1. Download the Geofabrik extract and the latest `planetiler.jar`; build the
   clip outline and the tile mask.
2. Planetiler (`--bounds` = region bbox, `--polygon` = outline,
   `--maxzoom 14`) writes OpenMapTiles vector MBTiles. First run also
   downloads Natural Earth, OSM water polygons and lake centerlines
   (~1.3 GB, once; `--download` is passed only when one of them is
   missing). Temp files go to `~/mesh-tiles/work/planetiler-tmp-<region>`
   (local: they are memory-mapped; compressed with `--compress-temp`, turn
   off with `PL_COMPRESS_TEMP=0`) and are deleted afterwards.
3. `render/render.mjs` (MapLibre Native in tile mode + sharp, run in
   parallel workers) renders each tile with `render/style.json`, a muted
   light style written for coverage maps so the coloured signal dots stand
   out (peaks with elevations in feet, minor roads from z12, buildings from
   z14). Tiles are 512 px for 256-pt slots (crisp on Retina), WebP q80.
   Glyphs (Noto Sans) come from `protomaps/basemaps-assets` and are cached
   in `downloads/glyphs`. Tiles outside the mask or without vector data are
   skipped.
4. `pmtiles convert` to PMTiles (its temp file in `$BIGWORK/pmtiles-tmp`).

**Terrain** (`build_terrain.sh`):

1. `gdalwarp` reads only the bbox of the USGS 3DEP seamless 1/3 arc-second
   (~10 m) DEM straight from the USGS cloud-optimized GeoTIFFs and
   resamples it to Web Mercator on the tile grid at the terrain max zoom,
   cut to the clip outline. Outside the US, point `DEM_SRC` at an SRTM
   1 arc-second mosaic.
2. `gdaldem hillshade -multidirectional -z 1.5`.
3. `gdaldem color-relief -alpha` turns the grey hillshade into a transparent
   overlay: flat ground nearly clear, shadows dark blue-grey, sunlit slopes a
   faint highlight (ramp in the script; tweak and `FORCE=1` to restyle).
4. `gdal_translate -of MBTILES` (WebP with alpha) + `gdaladdo` overviews down
   to the min zoom, then `pmtiles convert`.
5. `CONTOURS=1`: `gdal_contour` every 100 ft (`CONTOUR_INTERVAL_M=30.48`)
   into a FlatGeobuf (a plain file, fine on a network drive), rasterized as
   thin brown lines at the contour max zoom, tiled the same way.

GeoTIFFs are written with `BIGTIFF=IF_SAFER` (the west contour raster is
hundreds of gigapixels). Each script prints the size of every intermediate
and the final `.pmtiles`.

### Disk

The Mac has ~35 GB free locally; the network drive has ~2 TB.

- **On the network drive** (`MESH_TILES_BIG_DIR`): downloads, DEMs,
  hillshade/contour GeoTIFFs, contour FlatGeobufs, pmtiles' temp file, the
  outputs. These are kept (the DEM is the slow part to redo); delete
  `$BIGWORK/<region>-*` by hand once a region is uploaded.
- **Local** (`~/mesh-tiles/work`): Planetiler's temp files, the vector
  MBTiles, the raster/terrain/contour MBTiles (SQLite must not live on SMB).
- Every step refuses to start with less than `MIN_FREE_GB` (15) free
  locally (`check_space`, exit 3), and the network drive must be mounted
  (`check_big_dir`, exit 4).
- `CLEAN=1` (on in the queue) deletes each local MBTiles as soon as its
  PMTiles is written (streets: the raster and the vector MBTiles; terrain:
  the hillshade MBTiles before the contours start).

Local peak per region (estimates from the measured Hawaii and SoCal
figures and the us-west Planetiler run of 2026-11-05, which had a 5.8 GB
node map and 7.8 GB of features three quarters of the way through):

| Region | Planetiler temp + vector | Streets render (vector + raster MBTiles) | Terrain (largest MBTiles) |
|---|---|---|---|
| west | ~15-20 GB | ~18 GB | ~12 GB |
| south (biggest extract) | ~18-25 GB | ~13 GB | ~6 GB |
| midwest | ~12-18 GB | ~13 GB | ~6 GB |
| northeast | ~8-12 GB | ~4 GB | ~2 GB |
| alaska | ~1 GB | ~3 GB | ~2 GB |
| hawaii (measured) | 0.12 GB | 0.12 GB | 0.95 GB |

So the queue fits in ~35 GB free, but only one region at a time: never run
two builds at once.

## Sizes and times

Measured, Hawaii (2026-11-05, M-series Mac, 10 cores, network drive for the
big files):

| Step | Tiles | Output | Time |
|---|---|---|---|
| Streets: Planetiler (26 MB extract → 26 MB vector) | 42.9k z14 vector tiles (the ocean too) | | 25 s |
| Streets: render z8-15 (tile mask: 4,535 z14 tiles) | 24,363 of the bbox's 227,955 | `hawaii-streets.pmtiles` 66 MB | 42 s |
| Hillshade: DEM over /vsicurl (141 MB GeoTIFF) | | | 3 min 45 s |
| Hillshade: shade, colour, tiles z8-13 | 1,740 | `hawaii-terrain.pmtiles` 49 MB | 1 min 20 s |
| Contours: lines (131 MB FlatGeobuf), rasterize, tiles z13-15 | 17,926 | `hawaii-contours.pmtiles` 64 MB | 23 min (rasterize 11, MBTiles 8, overviews 4) |

Whole region ~30 min (terrain 28.6 min of it; `gdal_translate` to MBTiles
is single-threaded). Local disk peak: 0.12 GB (streets), 0.95 GB
(contours MBTiles). The network drive kept ~530 MB of Hawaii
intermediates. Checked with `pmtiles tile`: a Honolulu z14 tile has the
streets (23 KB), an open-ocean tile off the islands is absent in all three
files, the z12 hillshade tile over Mauna Kea shows the cinder cones
(59 KB), a z14 contour tile on its flank has the 100 ft lines.

Estimates for the rest, scaled from Hawaii and SoCal (socal: 298k street
tiles 782 MB in an 11 min render; hillshade 563 MB; contours 669 MB in
2.7 h). Streets and file sizes scale with the clipped area (z14 tiles in
the tile mask: socal's whole bbox 56k, hawaii 4.5k, alaska 161k, northeast
143k, south 577k, midwest 632k, west 919k); the GDAL steps run over the
whole bbox, but nodata (outside the clip) costs little (see Hawaii), so
times scale mostly with the clipped area too. Flat country makes smaller
hillshade tiles and far fewer contours than SoCal's mountains.

| Region | Clip (z14 tiles) | Streets | Hillshade | Contours | Time (streets + terrain) |
|---|---|---|---|---|---|
| hawaii (measured) | 4.5k | 66 MB | 49 MB | 64 MB | 1 min + 29 min |
| alaska | 161k | ~1.5-2.3 GB | ~1.7 GB | ~2 GB | ~0.5 h + ~10-12 h |
| northeast | 143k | ~2-3 GB | ~1.5 GB | ~1.5 GB | ~0.5 h + ~6-8 h |
| south | 577k | ~8 GB | ~4-6 GB | ~3-5 GB | ~2.5 h + ~20-30 h |
| midwest | 632k | ~9 GB | ~4-6 GB | ~2-4 GB | ~2.5 h + ~20-30 h |
| west | 919k | ~13 GB | ~10 GB | ~11 GB | ~3.5 h + ~45-50 h |

Per z14 clip tile, both SoCal and Hawaii came out at ~14 KB of streets,
~10.5 KB of hillshade and 12.5-14 KB of contours, which is what the
mountainous west will look like; the flat midwest and south should be well
under that for hillshade and contours. Streets render at ~450-570
tiles/s. Contours cost ~2.7 h per SoCal-sized area (56k z14 tiles) of
real relief and ~0.25 h per SoCal-sized area of nodata. Total: roughly
35 GB of streets and 45 GB of terrain (~80 GB in S3, ≈ $1.85/month), and
4-5 days for the whole queue, nearly all of it contours.

## Testing locally

Without real data, `make_sample.py` writes small synthetic PMTiles (stdlib
Python only):

```bash
python3 tool/tiles/make_sample.py ~/mesh-tiles/out/sample-terrain.pmtiles --kind terrain
python3 tool/tiles/make_sample.py ~/mesh-tiles/out/sample-streets.pmtiles --kind streets --minzoom 10 --maxzoom 12
```

Point the app at a file (the iOS simulator can read the Mac's disk):

```bash
flutter run -d <sim> \
  --dart-define=TILES_TERRAIN_URL=file://$HOME/mesh-tiles/out/coachella-terrain.pmtiles \
  --dart-define=TILES_STREETS_URL=file://$HOME/mesh-tiles/out/coachella-streets.pmtiles \
  --dart-define=TILES_BOUNDS=33.55,-116.60,33.95,-116.05 \
  --dart-define=TILES_REGION="the Coachella Valley"
```

or over HTTP with range requests, like CloudFront (`python3 -m http.server`
ignores `Range`, so use this one):

```bash
python3 tool/tiles/serve_range.py ~/mesh-tiles/out --port 8765
flutter run … --dart-define=TILES_TERRAIN_URL=http://localhost:8765/coachella-terrain.pmtiles
```

`pmtiles serve` / `pmtiles show <file>` / `pmtiles tile <file> z x y` help
inspect a file.

## What the first real build produced (2026-10-16, socal)
- streets: 297,917 tiles z8–15, 782 MB, 11 min render on an M-series Mac
- terrain (hillshade): 16,875 tiles z8–13, 590 MB
- contours (100 ft): 188,998 tiles z13–15, 702 MB
- hosted at https://d13u6w4g5rrbl6.cloudfront.net/v1/ (bucket
  `plateaunerd-mesh-tiles`, us-west-2, no logging); ~2 GB in S3 ≈ $0.05/month.

## Hosting on S3 + CloudFront (Andy runs these)
Shortcut: `bash tool/tiles/host_setup.sh` does steps 1–4 below in one go
(re-runnable; writes `~/mesh-tiles/host.env`), then
`bash tool/tiles/upload.sh socal v1` does step 5 and the verification.
Neither enables any logging, so the tile host keeps no record of who viewed
what.


Region us-west-2. The bucket stays private; CloudFront reads it through
Origin Access Control (OAC). CloudFront serves byte ranges from S3 origins
natively (206 + `Content-Range` + `Accept-Ranges: bytes`), which is all
PMTiles needs; no Lambda, no tile server. Replace `ACCOUNT_ID` and pick a
bucket name.

```bash
export AWS_REGION=us-west-2
BUCKET=plateaunerd-mesh-tiles
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 1. Private bucket.
aws s3api create-bucket --bucket "$BUCKET" --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# 2. Origin Access Control.
OAC_ID=$(aws cloudfront create-origin-access-control \
  --origin-access-control-config \
  Name=mesh-tiles-oac,SigningProtocol=sigv4,SigningBehavior=always,OriginAccessControlOriginType=s3 \
  --query OriginAccessControl.Id --output text)

# 3. Distribution. Managed policies (check the ids with
#    `aws cloudfront list-cache-policies --type managed` and
#    `aws cloudfront list-response-headers-policies --type managed`):
#    CachingOptimized 658327ea-f89d-4fab-a63d-7e88639e58f6,
#    SimpleCORS       60669652-455b-4ae9-85a4-c4c02393f86c (only matters for a
#    future web viewer; the iOS app doesn't need CORS).
cat > /tmp/mesh-tiles-dist.json <<JSON
{
  "CallerReference": "mesh-tiles-$(date +%s)",
  "Comment": "Meshurement map tiles (PMTiles)",
  "Enabled": true,
  "HttpVersion": "http2and3",
  "PriceClass": "PriceClass_100",
  "Origins": { "Quantity": 1, "Items": [{
    "Id": "s3-mesh-tiles",
    "DomainName": "$BUCKET.s3.us-west-2.amazonaws.com",
    "OriginAccessControlId": "$OAC_ID",
    "S3OriginConfig": { "OriginAccessIdentity": "" }
  }]},
  "DefaultCacheBehavior": {
    "TargetOriginId": "s3-mesh-tiles",
    "ViewerProtocolPolicy": "https-only",
    "AllowedMethods": { "Quantity": 2, "Items": ["GET", "HEAD"],
      "CachedMethods": { "Quantity": 2, "Items": ["GET", "HEAD"] } },
    "Compress": false,
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
    "ResponseHeadersPolicyId": "60669652-455b-4ae9-85a4-c4c02393f86c"
  }
}
JSON
DIST_ID=$(aws cloudfront create-distribution \
  --distribution-config file:///tmp/mesh-tiles-dist.json \
  --query Distribution.Id --output text)
aws cloudfront get-distribution --id "$DIST_ID" --query Distribution.DomainName --output text
# -> dxxxxxxxxxxxx.cloudfront.net

# 4. Let only this distribution read the bucket.
cat > /tmp/mesh-tiles-policy.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "CloudFrontOAC",
    "Effect": "Allow",
    "Principal": { "Service": "cloudfront.amazonaws.com" },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::$BUCKET/*",
    "Condition": { "StringEquals": {
      "AWS:SourceArn": "arn:aws:cloudfront::$ACCOUNT_ID:distribution/$DIST_ID" } }
  }]
}
JSON
aws s3api put-bucket-policy --bucket "$BUCKET" --policy file:///tmp/mesh-tiles-policy.json

# 5. Upload. Versioned prefix + immutable caching: a rebuild goes to v2/
#    and the app constants change, so no invalidations and no mixed old/new
#    byte ranges (a PMTiles file must not change under a running app).
for f in socal-streets socal-terrain socal-contours; do
  aws s3 cp ~/mesh-tiles/out/$f.pmtiles s3://$BUCKET/v1/$f.pmtiles \
    --content-type application/octet-stream \
    --cache-control "public, max-age=31536000, immutable"
done

# 6. Check range requests through CloudFront (expect 206 and Accept-Ranges).
curl -s -D - -o /dev/null -r 0-126 https://dxxxxxxxxxxxx.cloudfront.net/v1/socal-streets.pmtiles
pmtiles show https://dxxxxxxxxxxxx.cloudfront.net/v1/socal-streets.pmtiles
```

Large files: `aws s3 cp` uses multipart automatically; files over 5 GB are
fine.

### Then fill in the app constants

`lib/utils/map_tiles.dart`, class `MapTileConfig`:

```dart
static const String? hostedStreetsUrl  = 'https://dxxxxxxxxxxxx.cloudfront.net/v1/socal-streets.pmtiles';
static const String? hostedTerrainUrl  = 'https://dxxxxxxxxxxxx.cloudfront.net/v1/socal-terrain.pmtiles';
static const String? hostedContoursUrl = 'https://dxxxxxxxxxxxx.cloudfront.net/v1/socal-contours.pmtiles'; // or null
static const List<double> hostedBoundsSWNE = [32.5, -120.8, 35.8, -114.1]; // S, W, N, E of the built bbox
static const String hostedRegionName = 'Southern California';
```

Setting `hostedTerrainUrl` makes the layers button appear; the About
screen's privacy line switches to "our map tile server (CloudFront) inside
Southern California and tile.openstreetmap.org elsewhere" automatically.
Update the privacy policy page to match.

### Monthly cost estimate

- S3 storage (Standard, us-west-2, $0.023/GB-month): socal ~2 GB → ~$0.05; the full US set (estimated ~80 GB, see "Sizes and times") → **~$1.85**.
- S3 requests: only CloudFront cache misses; cents.
- CloudFront: each tile is one range request (~10-30 KB); a session of
  panning is a few hundred tiles. The always-free tier covers 1 TB out and
  10 M requests per month (or CloudFront's $0 flat-rate Free plan:
  1 M requests, 100 GB). 1,000 active users × ~2,000 tiles/month ≈ 2 M
  requests and ~40 GB: **$0** on the always-free tier. 10,000 users ≈ 20 M
  requests, ~400 GB: ≈ 10 M billable HTTPS requests × $0.01/10k ≈ **~$10**,
  data still within the free 1 TB.
- So: under $1/month until the app has thousands of active users. Set an
  AWS Budget alert (e.g. $10) on the account anyway.

## Data licences and attribution

- **OpenStreetMap** data: ODbL 1.0, "© OpenStreetMap contributors"
  (https://www.openstreetmap.org/copyright). Required on the map: the app
  always shows it.
- **OpenMapTiles** schema (Planetiler's output): CC-BY 4.0, "© OpenMapTiles"
  shown when the hosted streets are configured.
- **USGS 3DEP** elevation: public domain (US Government work). Credit as
  courtesy: "Hillshade: USGS 3DEP / NASA SRTM" in the Terrain style.
- **NASA SRTM** (if used outside the US): public domain.
- **Noto Sans** glyphs used while rendering: SIL OFL 1.1 (baked into the
  images; no font ships in the app).
- Tools (not distributed): Planetiler (Apache-2.0), MapLibre Native
  (BSD-2-Clause), sharp (Apache-2.0), GDAL (MIT), go-pmtiles (BSD-3-Clause).

The app-side credits live in `MapTileConfig.creditsFor` and `NOTICE`.

## What ran on the dev machine (October 2026)

- Downloaded the Geofabrik `socal` extract (671.6 MB) and `planetiler.jar`
  (93 MB) into `~/mesh-tiles/downloads/`.
- `brew install gdal pmtiles openjdk@21` did not complete on this machine:
  Homebrew hung (0% CPU) inside its own `sandbox_operation.rb`
  (relocate / extract steps) on three attempts and was stopped, so there was
  no Java (Planetiler), no GDAL and no `pmtiles` CLI. Nothing past the
  downloads ran. Side effect: before hanging, Homebrew had already upgraded
  some shared dependencies (simdjson 4.6.1 → 5.0.4, sqlite, nss), which
  breaks Homebrew's `node` 25.9 (`libsimdjson.33.dylib` not found); fix with
  `brew upgrade node` (or `brew reinstall node`). Run the install in a normal Terminal, then the two build
  commands above for `coachella`.
- Generated `sample-terrain.pmtiles` (237 tiles z10-13, 6.6 MB) and
  `sample-streets.pmtiles` (69 tiles z10-12, 0.1 MB) with `make_sample.py`;
  the app's reader opens them (gzip root directory, PNG tiles).
