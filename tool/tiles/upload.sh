#!/usr/bin/env bash
# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
#
# Upload a region's PMTiles to the hosting bucket under a version prefix,
# then verify range requests through CloudFront. A rebuilt region goes to a
# NEW version (v2, v3...) and the app constants change with it: a PMTiles
# file must never change under a running app.
#
#   bash tool/tiles/upload.sh west v2
source "$(dirname "$0")/common.sh"
REGION="${1:-west}"
VERSION="${2:-v2}"
# shellcheck source=/dev/null
. "$MESH_TILES_DIR/host.env"   # BUCKET, DIST_ID, DOMAIN from host_setup.sh
export AWS_REGION=us-west-2

for kind in streets terrain contours; do
  f="$OUT/$REGION-$kind.pmtiles"
  [ -f "$f" ] || { echo "skip $kind (no $f)"; continue; }
  key="$VERSION/$REGION-$kind.pmtiles"
  if aws s3api head-object --bucket "$BUCKET" --key "$key" >/dev/null 2>&1; then
    echo "exists s3://$BUCKET/$key — not overwriting (use a new version)"
    continue
  fi
  echo "upload $(du -h "$f" | cut -f1) -> s3://$BUCKET/$key"
  aws s3 cp "$f" "s3://$BUCKET/$key" \
    --content-type application/octet-stream \
    --cache-control "public, max-age=31536000, immutable" --only-show-errors
done

echo
echo "verify (expect HTTP 206 and Accept-Ranges: bytes):"
curl -s -D - -o /dev/null -r 0-126 "https://$DOMAIN/$VERSION/$REGION-streets.pmtiles" | head -12
echo
echo "constants for lib/utils/map_tiles.dart:"
for kind in streets terrain contours; do
  echo "  https://$DOMAIN/$VERSION/$REGION-$kind.pmtiles"
done
