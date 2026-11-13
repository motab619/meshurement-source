// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

/// Turning MeshCore frames into the neutral radio types: node numbers from
/// keys, contacts and adverts into [RadioNode]s, logged LoRa frames
/// (PUSH_CODE_LOG_RX_DATA) into [ReceivedPacket]s. Pure functions, so they
/// are tested on their own. Firmware references are to
/// meshcore-dev/MeshCore at [meshCoreFirmwareSha].
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../../utils/constants.dart';
import '../radio_types.dart';
import 'meshcore_frames.dart';
import 'meshcore_protocol.dart';
import 'meshcore_sha256.dart';

/// Node number of a MeshCore identity: the first 4 bytes of its public
/// key, big-endian, so it reads like the hex prefix the official apps show
/// (`a1b2c3d4…` → 0xa1b2c3d4).
int meshCoreNodeNum(List<int> publicKey) => prefixNum(publicKey);

/// [bytes] (1-4 of them) left-aligned in a u32, big-endian: a 1-byte path
/// hash 0xa1 → 0xa1000000. For 4 bytes this is [meshCoreNodeNum], so a
/// path hash and the node number of the node it names share their top
/// bytes.
int prefixNum(List<int> bytes) {
  var v = 0;
  for (var i = 0; i < 4; i++) {
    v = (v << 8) | (i < bytes.length ? bytes[i] & 0xFF : 0);
  }
  return v;
}

/// First 4 hex digits of the key: the short name of a MeshCore node.
String meshCoreShortName(List<int> publicKey) => hexOf(publicKey, 2);

/// [NodeKind] of a MeshCore advert/contact type (AdvertDataHelpers.h:7-11),
/// null for none/unknown.
String? nodeKindFor(int advType) => switch (advType) {
      MeshCoreAdvType.chat => NodeKind.chat,
      MeshCoreAdvType.repeater => NodeKind.repeater,
      MeshCoreAdvType.room => NodeKind.room,
      MeshCoreAdvType.sensor => NodeKind.sensor,
      _ => null,
    };

/// A contact record as a [RadioNode]. `lastmod` is by the radio's clock,
/// which the app sets on connect.
RadioNode nodeFromContact(MeshCoreContact c) => RadioNode(
      num: meshCoreNodeNum(c.publicKey),
      longName: c.name,
      shortName: meshCoreShortName(c.publicKey),
      latitude: c.hasPosition ? c.latitude : null,
      longitude: c.hasPosition ? c.longitude : null,
      hopsAway: c.hops,
      lastHeard: c.lastModified > 0
          ? DateTime.fromMillisecondsSinceEpoch(c.lastModified * 1000)
          : null,
      publicKey: c.publicKey,
      nodeKind: nodeKindFor(c.type),
    );

/// RSSI as the firmware sends it is an int8 (`(int8_t)rssi`,
/// MyMesh.cpp:296), so anything below -128 dBm wraps to a positive value.
/// A positive RSSI is impossible on air: v → v - 256.
int unwrapRssi(int v) => v > 0 ? v - 256 : v;

/// The packet id: the first 4 bytes (big-endian) of the hash the firmware
/// uses for duplicate detection, SHA-256 over the payload type, then the
/// path length byte for TRACE packets only, then the payload
/// (`Packet::calculatePacketHash`, src/Packet.cpp:41-50).
int meshCorePacketId(MeshCoreRawPacket p) {
  final t = p.payloadType;
  final digest = sha256([
    t,
    if (t == MeshCorePayloadType.trace) p.pathLen,
    ...p.payload,
  ]);
  return prefixNum(digest);
}

/// A signed advert payload: `pub_key[32] ts u32 sig[64] app_data`, app
/// data `flags [lat lon i32 ×1e6] [feat1 u16] [feat2 u16] [name…]`
/// (src/Mesh.cpp:252-289, src/helpers/AdvertDataHelpers.cpp:39-69). The
/// signature is not checked here: the radio drops forged adverts before
/// they reach a contact, but the raw log shows them all.
class MeshCoreAdvert {
  final Uint8List publicKey;
  final int timestamp;

  /// [MeshCoreAdvType] (low 4 bits of the flags byte).
  final int type;
  final String name;
  final int? latE6;
  final int? lonE6;

  const MeshCoreAdvert({
    required this.publicKey,
    required this.timestamp,
    required this.type,
    required this.name,
    this.latE6,
    this.lonE6,
  });

  static const _latLon = 0x10, _feat1 = 0x20, _feat2 = 0x40, _name = 0x80;

  /// Null when [payload] is too short to hold the fixed part.
  static MeshCoreAdvert? tryParse(Uint8List payload) {
    const fixed = MeshCoreLimits.pubKeySize + 4 + 64;
    if (payload.length < fixed + 1) return null;
    final bd = ByteData.sublistView(payload);
    final key = Uint8List.fromList(payload.sublist(0, 32));
    final ts = bd.getUint32(32, Endian.little);
    var i = fixed;
    final flags = payload[i++];
    int? lat, lon;
    if (flags & _latLon != 0) {
      if (payload.length < i + 8) return null;
      lat = bd.getInt32(i, Endian.little);
      lon = bd.getInt32(i + 4, Endian.little);
      i += 8;
    }
    if (flags & _feat1 != 0) i += 2;
    if (flags & _feat2 != 0) i += 2;
    if (i > payload.length) return null;
    var name = '';
    if (flags & _name != 0 && i < payload.length) {
      final raw = payload.sublist(i);
      final nul = raw.indexOf(0);
      name = _utf8(nul < 0 ? raw : raw.sublist(0, nul));
    }
    return MeshCoreAdvert(
        publicKey: key,
        timestamp: ts,
        type: flags & 0x0F,
        name: name,
        latE6: lat,
        lonE6: lon);
  }

  bool get hasPosition =>
      latE6 != null && lonE6 != null && (latE6 != 0 || lonE6 != 0);

  /// As a node heard just now, [hops] away.
  RadioNode toNode({int? hops, required DateTime heard}) => RadioNode(
        num: meshCoreNodeNum(publicKey),
        longName: name,
        shortName: meshCoreShortName(publicKey),
        latitude: hasPosition ? latE6! / 1e6 : null,
        longitude: hasPosition ? lonE6! / 1e6 : null,
        hopsAway: hops,
        lastHeard: heard,
        publicKey: publicKey,
        nodeKind: nodeKindFor(type),
      );
}

String _utf8(List<int> b) => const Utf8Decoder(allowMalformed: true).convert(b);

/// A TRACE payload: `tag u32, auth u32, flags, hashes…`; the path field of
/// the packet holds one SNR×4 byte per hop done (src/Mesh.cpp:42-61).
class MeshCoreTracePayload {
  final int tag;
  final int authCode;
  final int flags;
  final Uint8List hashes;

  const MeshCoreTracePayload(this.tag, this.authCode, this.flags, this.hashes);

  /// Bytes per hash: `1 << (flags & 3)` (v1.11+).
  int get hashSize => 1 << (flags & 0x03);

  /// Whether a trace that has done [snrCount] hops has reached the end of
  /// its path (Mesh.cpp:55-57): the receiver then reports it to its app.
  bool isComplete(int snrCount) => snrCount * hashSize >= hashes.length;

  static MeshCoreTracePayload? tryParse(Uint8List payload) {
    if (payload.length < 9) return null;
    final bd = ByteData.sublistView(payload);
    return MeshCoreTracePayload(
      bd.getUint32(0, Endian.little),
      bd.getUint32(4, Endian.little),
      payload[8],
      Uint8List.fromList(payload.sublist(9)),
    );
  }
}

/// Resolves a key prefix (a 1-3 byte path hash, a 1-byte source hash or a
/// 4-byte trace hash) to the node number of the one known node whose key
/// starts with it; null when none or several match.
typedef NodeByPrefix = int? Function(List<int> prefix);

/// One logged LoRa frame (`0x88`) as a [ReceivedPacket], or null when the
/// raw packet doesn't parse (the firmware would drop it too).
///
/// Hops and attribution follow docs/design/meshcore.md §8: a flood with n
/// path hashes travelled n hops and was last sent by the node of the last
/// hash ([ReceivedPacket.lastHopId]: resolved node number, else the hash
/// left-aligned as by [prefixNum]); a direct packet with an empty path is
/// zero-hop; a direct packet with hashes left on its path is on its way
/// elsewhere and its distance travelled is unknown. A TRACE carries SNRs
/// in its path, not hashes: it was last sent by the hop of the last SNR.
ReceivedPacket? packetFromRxLog(
  MeshCoreRxLog log, {
  required NodeByPrefix nodeByPrefix,
  required DateTime now,
}) {
  final p = log.packet;
  if (p == null) return null;
  final type = p.payloadType;
  final direct = !p.isFlood;
  var from = 0;
  var hops = 0;
  var hopsKnown = true;
  int? lastHop;

  int senderFromHashes() {
    switch (type) {
      case MeshCorePayloadType.req:
      case MeshCorePayloadType.response:
      case MeshCorePayloadType.txtMsg:
      case MeshCorePayloadType.path:
        // dest_hash(1), src_hash(1), MAC + ciphertext (Mesh.cpp:130-136).
        if (p.payload.length >= 2) {
          return nodeByPrefix([p.payload[1]]) ?? 0;
        }
        return 0;
      case MeshCorePayloadType.advert:
        if (p.payload.length >= MeshCoreLimits.pubKeySize) {
          return meshCoreNodeNum(p.payload);
        }
        return 0;
      default:
        return 0;
    }
  }

  if (type == MeshCorePayloadType.trace) {
    // Direct only (sendFlood refuses traces, Mesh.cpp:665-667).
    final t = MeshCoreTracePayload.tryParse(p.payload);
    final done = p.hops; // SNR bytes appended so far
    if (t != null && done > 0) {
      final at = (done - 1) * t.hashSize;
      if (at + t.hashSize <= t.hashes.length) {
        final h = t.hashes.sublist(at, at + t.hashSize);
        from = nodeByPrefix(h) ?? 0;
      }
    }
  } else if (p.isFlood) {
    from = senderFromHashes();
    hops = p.hops;
    if (hops > 0) {
      final size = MeshCorePathLen.hashSize(p.pathLen);
      final last = p.path.sublist(p.path.length - size);
      lastHop = nodeByPrefix(last) ?? prefixNum(last);
      if (lastHop == from) lastHop = null;
    }
  } else {
    from = senderFromHashes();
    if (p.hops > 0) hopsKnown = false;
  }

  return ReceivedPacket(
    from: from,
    packetId: meshCorePacketId(p),
    type: packetTypeFor(type),
    snr: log.snr,
    rssi: unwrapRssi(log.rssi),
    hops: hops,
    hopsKnown: hopsKnown,
    routeDirect: direct,
    lastHopId: lastHop,
    rxTime: now,
  );
}

/// `PacketType` string of a MeshCore payload type.
String packetTypeFor(int payloadType) => switch (payloadType) {
      MeshCorePayloadType.advert => PacketType.advert,
      MeshCorePayloadType.trace => PacketType.trace,
      MeshCorePayloadType.grpTxt ||
      MeshCorePayloadType.grpData =>
        PacketType.group,
      MeshCorePayloadType.req ||
      MeshCorePayloadType.response ||
      MeshCorePayloadType.txtMsg ||
      MeshCorePayloadType.path ||
      MeshCorePayloadType.anonReq =>
        PacketType.direct,
      MeshCorePayloadType.ack => PacketType.ack,
      _ => PacketType.raw,
    };
