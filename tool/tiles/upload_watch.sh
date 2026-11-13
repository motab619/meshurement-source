#!/usr/bin/env bash
# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
#
# Upload each region's PMTiles as the build queue finishes them. Polls $OUT
# every few minutes; a file that exists and has no marker in $LOGS is handed
# to upload.sh (which never overwrites an existing S3 key). Costs money
# (S3 storage): run only with the owner's go-ahead for the version.
#
#   nohup bash tool/tiles/upload_watch.sh v2 [queue-pid] > ~/mesh-tiles/logs/upload-watch.log 2>&1 &
#
# With a queue pid it exits once that process is gone and nothing is left to
# upload; without one it runs until killed. A network drive that is
# unmounted is waited for, not treated as "no files".
source "$(dirname "$0")/common.sh"
VERSION="${1:-v2}"
QUEUE_PID="${2:-}"
LOGS="$MESH_TILES_DIR/logs"
POLL="${POLL:-300}"
mkdir -p "$LOGS"

say() { echo "[$(date '+%F %T')] $*"; }
say "watching $OUT for $VERSION uploads (poll ${POLL}s, queue pid ${QUEUE_PID:-none})"

while :; do
  if [ -d "$OUT" ]; then
    for region in $ALL_REGIONS; do
      pending=
      for kind in streets terrain contours; do
        f="$OUT/$region-$kind.pmtiles"
        [ -f "$f" ] && [ ! -f "$LOGS/uploaded-$VERSION-$region-$kind" ] && pending="$pending $kind"
      done
      [ -n "$pending" ] || continue
      say "$region: new$pending -> upload"
      if bash "$(dirname "$0")/upload.sh" "$region" "$VERSION"; then
        for kind in $pending; do
          touch "$LOGS/uploaded-$VERSION-$region-$kind"
          say "$region-$kind: uploaded ($(du -h "$OUT/$region-$kind.pmtiles" | cut -f1))"
        done
      else
        say "$region: upload FAILED (exit $?), will retry"
      fi
    done
  else
    say "$OUT not reachable (drive unmounted?), waiting"
  fi
  # Only decide "nothing left" from a reachable folder: an unmounted drive
  # looks empty (2026-11-06: the Mac slept a minute after Alaska contours
  # finished and the watcher quit without uploading it).
  if [ -n "$QUEUE_PID" ] && [ -d "$OUT" ] && ! kill -0 "$QUEUE_PID" 2>/dev/null; then
    left=0
    for region in $ALL_REGIONS; do for kind in streets terrain contours; do
      [ -f "$OUT/$region-$kind.pmtiles" ] && [ ! -f "$LOGS/uploaded-$VERSION-$region-$kind" ] && left=1
    done; done
    [ "$left" = 0 ] && { say "queue gone, nothing left to upload; done"; exit 0; }
  fi
  sleep "$POLL"
done
