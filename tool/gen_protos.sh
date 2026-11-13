#!/usr/bin/env bash
# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
# Regenerate lib/proto from the upstream Meshtastic protobufs.
#
#   tool/gen_protos.sh <path-to-protoc-bin-dir> <path-to-meshtastic/protobufs-checkout>
#
# Needs protoc (https://github.com/protocolbuffers/protobuf/releases) and
# protoc_plugin 22.x (`dart pub global activate protoc_plugin 22.5.0`, matching
# the protobuf ^4 runtime in pubspec.yaml). Update lib/proto/UPSTREAM.md after.
set -euo pipefail
PROTOC_BIN="$1"
UPSTREAM="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/lib/proto"

rm -f "$OUT"/meshtastic/*.dart "$OUT"/meshtastic/*.proto "$OUT"/meshtastic/*.options
mkdir -p "$OUT/meshtastic"
cp "$UPSTREAM/LICENSE" "$OUT/LICENSE"
cp "$UPSTREAM/nanopb.proto" "$OUT/"
cp "$UPSTREAM"/meshtastic/*.proto "$UPSTREAM"/meshtastic/*.options "$OUT/meshtastic/"

TMP="$(mktemp -d)"
PATH="$HOME/.pub-cache/bin:$PATH" "$PROTOC_BIN/protoc" \
  -I"$UPSTREAM" -I"$PROTOC_BIN/../include" \
  --dart_out="$TMP" "$UPSTREAM"/meshtastic/*.proto
cp "$TMP"/meshtastic/*.dart "$OUT/meshtastic/"
rm -rf "$TMP"
echo "Regenerated $(ls "$OUT"/meshtastic/*.pb.dart | wc -l | tr -d ' ') protos into lib/proto/meshtastic"
