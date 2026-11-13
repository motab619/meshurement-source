#!/usr/bin/env bash
# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

# Build queue: for each region, build_streets.sh then CONTOURS=1
# build_terrain.sh, one after the other. A region whose outputs are already
# in $OUT is skipped; a failed step is logged and the queue moves on to the
# next region; a summary comes at the end. Meant to run for days:
#
#   nohup tool/tiles/build_all.sh >~/mesh-tiles/logs/queue.log 2>&1 &
#   tool/tiles/build_all.sh hawaii alaska      # just these
#   KINDS=terrain tool/tiles/build_all.sh south  # only hillshade + contours
#
# Defaults: MESH_TILES_BIG_DIR=/Volumes/MiniSlo/develop/mesh-tiles,
# JAVA_HEAP=12g, CLEAN=1 (local MBTiles deleted once each PMTiles is
# written). Logs: ~/mesh-tiles/logs/<region>-{streets,terrain}.log.
# Keeps the Mac awake while it runs (caffeinate).

set -uo pipefail
TOOL="$(cd "$(dirname "$0")" && pwd)"
export MESH_TILES_DIR="${MESH_TILES_DIR:-$HOME/mesh-tiles}"
export MESH_TILES_BIG_DIR="${MESH_TILES_BIG_DIR:-/Volumes/MiniSlo/develop/mesh-tiles}"
export JAVA_HEAP="${JAVA_HEAP:-12g}"
export CLEAN="${CLEAN:-1}"
KINDS="${KINDS:-streets terrain}"
OUT="$MESH_TILES_BIG_DIR/out"
LOGS="$MESH_TILES_DIR/logs"
mkdir -p "$LOGS"

if [ $# -gt 0 ]; then REGIONS=("$@"); else
  # shellcheck disable=SC2207
  REGIONS=($(bash -c "source '$TOOL/common.sh' >/dev/null && echo \$ALL_REGIONS")) || exit 1
fi

command -v caffeinate >/dev/null && { caffeinate -i -w $$ & }

stamp() { date '+%F %T'; }
RESULTS=()
run_step() { # region kind command...
  local region="$1" kind="$2" log="$LOGS/$1-$2.log" t0 rc
  shift 2
  t0=$(date +%s)
  echo "[$(stamp)] $region $kind: start (log $log)"
  { echo; echo "===== $(stamp) $region $kind: $*"; } >>"$log"
  "$@" >>"$log" 2>&1
  rc=$?
  local mins=$(( ($(date +%s) - t0) / 60 ))
  if [ $rc = 0 ]; then
    echo "[$(stamp)] $region $kind: done in ${mins} min"
    RESULTS+=("$region $kind: ok (${mins} min)")
  else
    echo "[$(stamp)] $region $kind: FAILED (exit $rc) after ${mins} min; tail of $log:"
    tail -5 "$log" | sed 's/^/    /'
    RESULTS+=("$region $kind: FAILED exit $rc (${mins} min), see $log")
  fi
  return $rc
}

echo "[$(stamp)] queue: ${REGIONS[*]} ($KINDS, big dir $MESH_TILES_BIG_DIR, heap $JAVA_HEAP, CLEAN=$CLEAN)"
for r in "${REGIONS[@]}"; do
  if [[ " $KINDS " != *" streets "* ]]; then
    :
  elif [ -s "$OUT/$r-streets.pmtiles" ]; then
    RESULTS+=("$r streets: skipped (exists)")
  else
    run_step "$r" streets bash "$TOOL/build_streets.sh" "$r"
  fi
  if [[ " $KINDS " != *" terrain "* ]]; then
    :
  elif [ -s "$OUT/$r-terrain.pmtiles" ] && [ -s "$OUT/$r-contours.pmtiles" ]; then
    RESULTS+=("$r terrain: skipped (exists)")
  else
    run_step "$r" terrain env CONTOURS=1 bash "$TOOL/build_terrain.sh" "$r"
  fi
done

echo
echo "[$(stamp)] queue finished:"
printf '  %s\n' "${RESULTS[@]}"
ls -lh "$OUT"/*.pmtiles 2>/dev/null | awk '{print "  " $5 "\t" $9}'
printf '%s\n' "${RESULTS[@]}" | grep -q FAILED && exit 1
exit 0
