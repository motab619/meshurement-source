// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

/// MeshCore companion-protocol frame codec: [MeshCoreCommands] builds the
/// frames the app writes, [MeshCoreFrame.parse] decodes the frames the
/// radio sends.
///
/// Every layout cites `examples/companion_radio/MyMesh.cpp:<line>@sha`
/// (or another firmware file) at [meshCoreFirmwareSha]. Conventions on
/// the wire: little-endian integers; SNR is int8 in quarter-dB (value / 4);
/// RSSI is int8 dBm; latitude/longitude are int32 degrees * 1e6; strings
/// are UTF-8, either NUL-terminated in a fixed-width field or running to
/// the end of the frame.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'meshcore_protocol.dart';
import '../../../utils/app_info.dart';

// ---------------------------------------------------------------------------
// Shared value types
// ---------------------------------------------------------------------------

/// The encoded path-length byte used in contacts, messages, raw packets and
/// CMD_SEND_RAW_DATA (src/Packet.h:79-87, src/Packet.cpp:13-18@sha):
/// bits 0-5 = hop count, bits 6-7 = hash size - 1 (1..3 bytes per hop;
/// size 4 is reserved). 0xFF ([MeshCoreLimits.pathUnknown]) means no
/// known path (flood) in a contact, or "arrived direct" in a message.
class MeshCorePathLen {
  MeshCorePathLen._();

  /// Bytes per hop hash.
  static int hashSize(int encoded) => ((encoded & 0xFF) >> 6) + 1;

  /// Number of hops.
  static int hashCount(int encoded) => encoded & 63;

  /// Path bytes that follow on the wire.
  static int byteLength(int encoded) => hashCount(encoded) * hashSize(encoded);

  /// Mirrors `Packet::isValidPathLen`.
  static bool isValid(int encoded) =>
      hashSize(encoded) != 4 &&
      byteLength(encoded) <= MeshCoreLimits.maxPathSize;

  /// Encodes [hops] hashes of [hashSize] bytes each.
  static int encode({required int hops, int hashSize = 1}) {
    if (hashSize < 1 || hashSize > 3) {
      throw ArgumentError.value(hashSize, 'hashSize', 'must be 1..3');
    }
    if (hops < 0 || hops > 63 || hops * hashSize > MeshCoreLimits.maxPathSize) {
      throw ArgumentError.value(hops, 'hops', 'path too long');
    }
    return ((hashSize - 1) << 6) | hops;
  }
}

/// A contact record as the radio stores it: RESP_CODE_CONTACT,
/// PUSH_CODE_NEW_ADVERT and CMD_ADD_UPDATE_CONTACT share this layout
/// (MyMesh.cpp:171-192 writes it, 194-218 reads it @sha).
class MeshCoreContact {
  /// Full 32-byte public key.
  final Uint8List publicKey;

  /// One of [MeshCoreAdvType].
  final int type;

  /// [MeshCoreContactFlags] bits.
  final int flags;

  /// Encoded out-path length (see [MeshCorePathLen]); 0xFF = flood.
  final int outPathLen;

  /// The out-path hop hashes ([MeshCorePathLen.byteLength] bytes; empty
  /// when [outPathLen] is 0xFF).
  final Uint8List outPath;

  /// Advertised name (at most 31 UTF-8 bytes on the wire).
  final String name;

  /// Their last advert time, by THEIR clock (Unix seconds). The firmware
  /// uses it as the replay guard, so send back what the radio gave you.
  final int lastAdvertTimestamp;

  /// Advertised position, degrees * 1e6 (0/0 = none).
  final int latE6;
  final int lonE6;

  /// Last modified, by the radio's clock (Unix seconds).
  final int lastModified;

  MeshCoreContact({
    required this.publicKey,
    required this.type,
    this.flags = 0,
    this.outPathLen = MeshCoreLimits.pathUnknown,
    Uint8List? outPath,
    required this.name,
    this.lastAdvertTimestamp = 0,
    this.latE6 = 0,
    this.lonE6 = 0,
    this.lastModified = 0,
  }) : outPath = outPath ?? Uint8List(0);

  double get latitude => latE6 / 1e6;
  double get longitude => lonE6 / 1e6;

  /// Whether the advert carried a position (the firmware sends 0/0 when
  /// not).
  bool get hasPosition => latE6 != 0 || lonE6 != 0;

  /// Whether the radio knows a direct route.
  bool get hasPath => outPathLen != MeshCoreLimits.pathUnknown;

  /// Hop count of the out-path, or null for flood.
  int? get hops => hasPath ? MeshCorePathLen.hashCount(outPathLen) : null;

  @override
  bool operator ==(Object other) =>
      other is MeshCoreContact &&
      _bytesEqual(other.publicKey, publicKey) &&
      other.type == type &&
      other.flags == flags &&
      other.outPathLen == outPathLen &&
      _bytesEqual(other.outPath, outPath) &&
      other.name == name &&
      other.lastAdvertTimestamp == lastAdvertTimestamp &&
      other.latE6 == latE6 &&
      other.lonE6 == lonE6 &&
      other.lastModified == lastModified;

  @override
  int get hashCode => Object.hash(Object.hashAll(publicKey), type, flags,
      outPathLen, name, lastAdvertTimestamp, latE6, lonE6, lastModified);

  @override
  String toString() =>
      'MeshCoreContact($name ${hexOf(publicKey, 6)} type=$type '
      'hops=${hops ?? "flood"})';
}

/// SELF_INFO, the reply to CMD_APP_START (MyMesh.cpp:1076-1117@sha).
class MeshCoreSelfInfo {
  /// Advert type of this node (always [MeshCoreAdvType.chat] for a
  /// companion).
  final int advType;
  final int txPowerDbm;
  final int maxTxPowerDbm;
  final Uint8List publicKey;

  /// Configured advert position, degrees * 1e6 (null on very old
  /// firmware whose frame stops after the key).
  final int? latE6;
  final int? lonE6;
  final int? multiAcks;
  final int? advertLocationPolicy;

  /// Packed telemetry modes: bits 0-1 base, 2-3 location, 4-5 environment.
  final int? telemetryModes;
  final int? manualAddContacts;

  /// Radio parameters; null when the frame predates them.
  final int? frequencyKHz;
  final int? bandwidthHz;
  final int? spreadingFactor;
  final int? codingRate;
  final String name;

  const MeshCoreSelfInfo({
    required this.advType,
    required this.txPowerDbm,
    required this.maxTxPowerDbm,
    required this.publicKey,
    this.latE6,
    this.lonE6,
    this.multiAcks,
    this.advertLocationPolicy,
    this.telemetryModes,
    this.manualAddContacts,
    this.frequencyKHz,
    this.bandwidthHz,
    this.spreadingFactor,
    this.codingRate,
    required this.name,
  });

  double? get frequencyMHz =>
      frequencyKHz == null ? null : frequencyKHz! / 1000.0;
  double? get bandwidthKHz =>
      bandwidthHz == null ? null : bandwidthHz! / 1000.0;
  double? get latitude => latE6 == null ? null : latE6! / 1e6;
  double? get longitude => lonE6 == null ? null : lonE6! / 1e6;
  bool get hasRadioParams => frequencyKHz != null;
}

/// DEVICE_INFO, the reply to CMD_DEVICE_QUERY (MyMesh.cpp:1056-1075@sha).
/// Fields after [firmwareVerCode] appeared over time and are null when the
/// frame is too short to hold them.
class MeshCoreDeviceInfo {
  /// Companion protocol level of the firmware (FIRMWARE_VER_CODE, 14 at
  /// v1.18.0).
  final int firmwareVerCode;

  /// MAX_CONTACTS (the wire carries half of it; v3+).
  final int? maxContacts;

  /// MAX_GROUP_CHANNELS (v3+).
  final int? maxChannels;

  /// BLE pairing PIN (0 = none/random).
  final int? blePin;

  /// FIRMWARE_BUILD_DATE, e.g. "15 Oct 2026".
  final String? buildDate;

  /// Board manufacturer/model name.
  final String? manufacturer;

  /// FIRMWARE_VERSION, e.g. "v1.18.0".
  final String? firmwareVersion;

  /// Client repeat (off-grid) mode enabled (v9+).
  final bool? clientRepeat;

  /// Path hash mode: on-air path hashes are mode + 1 bytes (v10+).
  final int? pathHashMode;

  const MeshCoreDeviceInfo({
    required this.firmwareVerCode,
    this.maxContacts,
    this.maxChannels,
    this.blePin,
    this.buildDate,
    this.manufacturer,
    this.firmwareVersion,
    this.clientRepeat,
    this.pathHashMode,
  });
}

/// The repeater/room-server stats blob in a status response
/// (`RepeaterStats`, examples/simple_repeater/MyMesh.h:44-60@sha; filled in
/// examples/simple_repeater/MyMesh.cpp:216-236). 56 bytes, packed by
/// natural alignment (no padding).
class MeshCoreRepeaterStats {
  static const size = 56;

  final int battMilliVolts;
  final int txQueueLen;
  final int noiseFloor;
  final int lastRssi;
  final int packetsRecv;
  final int packetsSent;
  final int airTimeSecs;
  final int upTimeSecs;
  final int sentFlood;
  final int sentDirect;
  final int recvFlood;
  final int recvDirect;
  final int errEvents;

  /// SNR of the last packet the repeater heard, dB (wire: int16 * 4).
  final double lastSnr;
  final int directDups;
  final int floodDups;
  final int rxAirTimeSecs;
  final int recvErrors;

  const MeshCoreRepeaterStats({
    required this.battMilliVolts,
    required this.txQueueLen,
    required this.noiseFloor,
    required this.lastRssi,
    required this.packetsRecv,
    required this.packetsSent,
    required this.airTimeSecs,
    required this.upTimeSecs,
    required this.sentFlood,
    required this.sentDirect,
    required this.recvFlood,
    required this.recvDirect,
    required this.errEvents,
    required this.lastSnr,
    required this.directDups,
    required this.floodDups,
    required this.rxAirTimeSecs,
    required this.recvErrors,
  });

  /// Decodes [data] (the bytes after the 4-byte tag), or null if too short.
  static MeshCoreRepeaterStats? tryParse(Uint8List data) {
    if (data.length < size) return null;
    final b = ByteData.sublistView(data);
    int u16(int o) => b.getUint16(o, Endian.little);
    int i16(int o) => b.getInt16(o, Endian.little);
    int u32(int o) => b.getUint32(o, Endian.little);
    return MeshCoreRepeaterStats(
      battMilliVolts: u16(0),
      txQueueLen: u16(2),
      noiseFloor: i16(4),
      lastRssi: i16(6),
      packetsRecv: u32(8),
      packetsSent: u32(12),
      airTimeSecs: u32(16),
      upTimeSecs: u32(20),
      sentFlood: u32(24),
      sentDirect: u32(28),
      recvFlood: u32(32),
      recvDirect: u32(36),
      errEvents: u16(40),
      lastSnr: i16(42) / 4.0,
      directDups: u16(44),
      floodDups: u16(46),
      rxAirTimeSecs: u32(48),
      recvErrors: u32(52),
    );
  }
}

/// An over-the-air MeshCore packet as carried raw in PUSH_CODE_LOG_RX_DATA
/// (wire format `Packet::writeTo`/`readFrom`, src/Packet.cpp:52-85@sha):
/// header, [transport codes u16 x2 for transport routes], path_len, path,
/// payload. The payload is still encrypted for most types.
class MeshCoreRawPacket {
  final int header;
  final List<int>? transportCodes;
  final int pathLen;
  final Uint8List path;
  final Uint8List payload;

  const MeshCoreRawPacket({
    required this.header,
    this.transportCodes,
    required this.pathLen,
    required this.path,
    required this.payload,
  });

  /// One of [MeshCoreRouteType].
  int get routeType => header & 0x03;

  /// One of [MeshCorePayloadType].
  int get payloadType => (header >> 2) & 0x0F;
  int get payloadVersion => (header >> 6) & 0x03;
  bool get isFlood =>
      routeType == MeshCoreRouteType.flood ||
      routeType == MeshCoreRouteType.transportFlood;

  /// Hops travelled so far (flood) or remaining (direct). For TRACE
  /// packets the path holds one int8 SNR*4 per hop instead of hashes.
  int get hops => MeshCorePathLen.hashCount(pathLen);

  /// Mirrors `Packet::readFrom`; null where it would return false.
  static MeshCoreRawPacket? tryParse(Uint8List raw) {
    var i = 0;
    if (raw.isEmpty) return null;
    final header = raw[i++];
    final route = header & 0x03;
    List<int>? codes;
    if (route == MeshCoreRouteType.transportFlood ||
        route == MeshCoreRouteType.transportDirect) {
      if (raw.length < i + 4) return null;
      final b = ByteData.sublistView(raw);
      codes = [
        b.getUint16(i, Endian.little),
        b.getUint16(i + 2, Endian.little)
      ];
      i += 4;
    }
    if (raw.length <= i) return null;
    final pathLen = raw[i++];
    if (!MeshCorePathLen.isValid(pathLen)) return null;
    final bl = MeshCorePathLen.byteLength(pathLen);
    if (raw.length < i + bl) return null;
    final path = Uint8List.fromList(raw.sublist(i, i + bl));
    i += bl;
    if (i >= raw.length) return null; // firmware: empty payload is bad
    return MeshCoreRawPacket(
      header: header,
      transportCodes: codes,
      pathLen: pathLen,
      path: path,
      payload: Uint8List.fromList(raw.sublist(i)),
    );
  }
}

// ---------------------------------------------------------------------------
// Command builders
// ---------------------------------------------------------------------------

/// Builders for the frames the app writes to [MeshCoreBle.rxCharacteristicUuid].
///
/// Connect sequence: [deviceQuery] first (it sets the protocol level the
/// radio uses for message frames), then [appStart] for SELF_INFO.
class MeshCoreCommands {
  MeshCoreCommands._();

  /// CMD_APP_START: `[1][reserved x7][app name...]`; the firmware needs at
  /// least 8 bytes and NUL-terminates the name itself
  /// (MyMesh.cpp:1076-1081@sha). Byte 1 is treated as an app version by
  /// the official clients; the firmware ignores bytes 1-7.
  static Uint8List appStart(
      {String appName = AppInfo.displayName, int appVersion = 1}) {
    final w = _Writer()
      ..u8(MeshCoreCmd.appStart)
      ..u8(appVersion)
      ..zeros(6)
      ..bytes(utf8.encode(appName));
    return w.take();
  }

  /// CMD_DEVICE_QUERY: `[22][app protocol version]` (MyMesh.cpp:1056-1057).
  static Uint8List deviceQuery(
          {int protocolVersion = MeshCoreLimits.appProtocolVersion}) =>
      Uint8List.fromList([MeshCoreCmd.deviceQuery, protocolVersion & 0xFF]);

  /// CMD_GET_CONTACTS: `[4][since u32?]` (MyMesh.cpp:1238-1258). Replies
  /// CONTACTS_START, CONTACT x n (lastmod > since), END_OF_CONTACTS.
  static Uint8List getContacts({int? since}) {
    final w = _Writer()..u8(MeshCoreCmd.getContacts);
    if (since != null) w.u32(since);
    return w.take();
  }

  /// CMD_GET_CONTACT_BY_KEY: `[30][pub_key x32]` (MyMesh.cpp:1371-1378).
  static Uint8List getContactByKey(Uint8List publicKey) =>
      _cmdWithKey(MeshCoreCmd.getContactByKey, publicKey);

  /// CMD_ADD_UPDATE_CONTACT: same layout as a contact record, with the
  /// optional lat/lon/lastmod tail always written (MyMesh.cpp:194-218,
  /// 1328-1348@sha).
  static Uint8List addUpdateContact(MeshCoreContact c) =>
      _contactRecord(MeshCoreCmd.addUpdateContact, c);

  /// CMD_REMOVE_CONTACT: `[15][pub_key x32]` (MyMesh.cpp:1349-1358).
  static Uint8List removeContact(Uint8List publicKey) =>
      _cmdWithKey(MeshCoreCmd.removeContact, publicKey);

  /// CMD_RESET_PATH: `[13][pub_key x32]`, forget the direct route so the
  /// next send floods (MyMesh.cpp:1317-1327).
  static Uint8List resetPath(Uint8List publicKey) =>
      _cmdWithKey(MeshCoreCmd.resetPath, publicKey);

  /// CMD_SEND_TXT_MSG: `[2][txt_type][attempt][timestamp u32][key prefix
  /// x6][text...]`, no terminator (MyMesh.cpp:1132-1177@sha). Replies SENT
  /// (with the expected ACK code) or ERR. Only plain, CLI data and CLI
  /// command types are accepted; text must fit
  /// [MeshCoreLimits.maxTextLen] (2 bytes less from attempt 4).
  static Uint8List sendTextMessage({
    required Uint8List publicKeyPrefix,
    required String text,
    required int timestamp,
    int attempt = 0,
    int txtType = MeshCoreTxtType.plain,
  }) {
    _checkLen(
        publicKeyPrefix, MeshCoreLimits.pubKeyPrefixSize, 'publicKeyPrefix',
        orLonger: true);
    final w = _Writer()
      ..u8(MeshCoreCmd.sendTxtMsg)
      ..u8(txtType)
      ..u8(attempt)
      ..u32(timestamp)
      ..bytes(publicKeyPrefix.sublist(0, MeshCoreLimits.pubKeyPrefixSize))
      ..bytes(utf8.encode(text));
    return w.take();
  }

  /// CMD_SEND_CHANNEL_TXT_MSG: `[3][txt_type=0][channel_idx][timestamp
  /// u32][text...]` (MyMesh.cpp:1178-1197). The radio prefixes
  /// "node name: " on air. Replies OK or ERR(NOT_FOUND).
  static Uint8List sendChannelTextMessage({
    required int channelIndex,
    required String text,
    required int timestamp,
  }) {
    final w = _Writer()
      ..u8(MeshCoreCmd.sendChannelTxtMsg)
      ..u8(MeshCoreTxtType.plain)
      ..u8(channelIndex)
      ..u32(timestamp)
      ..bytes(utf8.encode(text));
    return w.take();
  }

  /// CMD_SEND_CHANNEL_DATA: `[62][channel_idx][path_len][path?][data_type
  /// u16][payload...]` (MyMesh.cpp:1198-1237@sha). [pathLen] 0xFF floods
  /// (then no path bytes); [dataType] 0 is rejected. Payload at most
  /// MAX_GROUP_DATA_LENGTH (165) bytes.
  static Uint8List sendChannelData({
    required int channelIndex,
    required int dataType,
    required Uint8List payload,
    int pathLen = MeshCoreLimits.pathUnknown,
    Uint8List? path,
  }) {
    final w = _Writer()
      ..u8(MeshCoreCmd.sendChannelData)
      ..u8(channelIndex)
      ..u8(pathLen);
    if (pathLen != MeshCoreLimits.pathUnknown) {
      w.bytes(_pathBytes(pathLen, path));
    }
    w
      ..u16(dataType)
      ..bytes(payload);
    return w.take();
  }

  /// CMD_SEND_RAW_DATA: `[25][path_len][path][payload >= 4 bytes]`, sent
  /// direct along [path] as a RAW_CUSTOM packet; flood is not supported by
  /// the firmware (MyMesh.cpp:1557-1576@sha). The receiver gets
  /// PUSH_CODE_RAW_DATA.
  static Uint8List sendRawData({
    required int pathLen,
    required Uint8List path,
    required Uint8List payload,
  }) {
    if (!MeshCorePathLen.isValid(pathLen)) {
      throw ArgumentError.value(
          pathLen, 'pathLen', 'invalid (flood unsupported)');
    }
    if (payload.length < 4) {
      throw ArgumentError.value(payload.length, 'payload', 'needs >= 4 bytes');
    }
    final w = _Writer()
      ..u8(MeshCoreCmd.sendRawData)
      ..u8(pathLen)
      ..bytes(_pathBytes(pathLen, path))
      ..bytes(payload);
    return w.take();
  }

  /// CMD_SEND_TRACE_PATH: `[36][tag u32][auth u32][flags][path hashes...]`
  /// (MyMesh.cpp:1813-1838@sha). `flags & 3` = log2 of the hash size, so
  /// [path] must be a multiple of `1 << (flags & 3)` bytes. The path lists
  /// every hop to visit, out and back (e.g. [a, b, a] to trace a->b and
  /// return). Replies SENT (tag echoed); the result arrives as
  /// PUSH_CODE_TRACE_DATA with the same tag.
  static Uint8List sendTracePath({
    required int tag,
    required Uint8List path,
    int authCode = 0,
    int flags = 0,
  }) {
    final hashBytes = 1 << (flags & 0x03);
    if (path.isEmpty || path.length % hashBytes != 0) {
      throw ArgumentError.value(path.length, 'path',
          'must be a non-empty multiple of $hashBytes bytes');
    }
    final w = _Writer()
      ..u8(MeshCoreCmd.sendTracePath)
      ..u32(tag)
      ..u32(authCode)
      ..u8(flags)
      ..bytes(path);
    return w.take();
  }

  /// CMD_SEND_STATUS_REQ: `[27][pub_key x32]` (MyMesh.cpp:1630-1650).
  /// Replies SENT; the answer arrives as PUSH_CODE_STATUS_RESPONSE.
  static Uint8List sendStatusRequest(Uint8List publicKey) =>
      _cmdWithKey(MeshCoreCmd.sendStatusReq, publicKey);

  /// CMD_SEND_SELF_ADVERT: `[7][1 = flood | 0 = zero hop]`
  /// (MyMesh.cpp:1297-1316).
  static Uint8List sendSelfAdvert({bool flood = false}) =>
      Uint8List.fromList([MeshCoreCmd.sendSelfAdvert, flood ? 1 : 0]);

  /// CMD_SYNC_NEXT_MESSAGE: `[10]` (MyMesh.cpp:1415-1423). Replies with the
  /// next queued message frame or NO_MORE_MESSAGES.
  static Uint8List syncNextMessage() =>
      Uint8List.fromList([MeshCoreCmd.syncNextMessage]);

  /// CMD_SET_RADIO_PARAMS: `[11][freq kHz u32][bw Hz u32][sf][cr][repeat?]`
  /// (MyMesh.cpp:1424-1459@sha). The firmware divides both by 1000, so
  /// frequency goes in kHz and bandwidth in Hz. It accepts 150-2500 MHz,
  /// 7-500 kHz, SF5-12, CR5-8. [clientRepeat] is v9+; omit for older
  /// firmware.
  static Uint8List setRadioParams({
    required double frequencyMHz,
    required double bandwidthKHz,
    required int spreadingFactor,
    required int codingRate,
    bool? clientRepeat,
  }) {
    final w = _Writer()
      ..u8(MeshCoreCmd.setRadioParams)
      ..u32((frequencyMHz * 1000).round())
      ..u32((bandwidthKHz * 1000).round())
      ..u8(spreadingFactor)
      ..u8(codingRate);
    if (clientRepeat != null) w.u8(clientRepeat ? 1 : 0);
    return w.take();
  }

  /// CMD_SET_RADIO_TX_POWER: `[12][dBm int8]`, -9..max
  /// (MyMesh.cpp:1460-1469).
  /// CMD_GET_CUSTOM_VARS: `[40]`; answered with RESP_CODE_CUSTOM_VARS
  /// "name:value,…" from the board's sensor manager (MyMesh.cpp:1853-1866
  /// @sha). A T1000-E has one: `gps` (its GPS power, "0"/"1").
  static Uint8List getCustomVars() =>
      Uint8List.fromList([MeshCoreCmd.getCustomVars]);

  /// CMD_SET_CUSTOM_VAR: `[41]["name:value"]` → OK, or ERR when the board
  /// doesn't know the name (MyMesh.cpp:1867-1892@sha). Setting `gps` also
  /// saves it in the node's prefs.
  static Uint8List setCustomVar(String name, String value) =>
      Uint8List.fromList(
          [MeshCoreCmd.setCustomVar, ...utf8.encode('$name:$value')]);

  static Uint8List setTxPower(int dbm) =>
      Uint8List.fromList([MeshCoreCmd.setRadioTxPower, dbm & 0xFF]);

  /// CMD_GET_CHANNEL: `[31][idx]` (MyMesh.cpp:1752-1766).
  static Uint8List getChannel(int index) =>
      Uint8List.fromList([MeshCoreCmd.getChannel, index & 0xFF]);

  /// CMD_SET_CHANNEL: `[32][idx][name x32][secret x16]`
  /// (MyMesh.cpp:1767-1780@sha). Only 128-bit secrets; a 32-byte one is
  /// refused.
  static Uint8List setChannel(int index, String name, Uint8List secret) {
    _checkLen(secret, MeshCoreLimits.channelSecretSize, 'secret');
    final w = _Writer()
      ..u8(MeshCoreCmd.setChannel)
      ..u8(index)
      ..fixedString(name, MeshCoreLimits.nameSize)
      ..bytes(secret);
    return w.take();
  }

  /// CMD_GET_DEVICE_TIME: `[5]` (MyMesh.cpp:1281-1286).
  static Uint8List getDeviceTime() =>
      Uint8List.fromList([MeshCoreCmd.getDeviceTime]);

  /// CMD_SET_DEVICE_TIME: `[6][unix secs u32]`; the radio refuses to go
  /// backwards (MyMesh.cpp:1287-1296).
  static Uint8List setDeviceTime(int unixSeconds) => (_Writer()
        ..u8(MeshCoreCmd.setDeviceTime)
        ..u32(unixSeconds))
      .take();

  /// CMD_SET_ADVERT_NAME: `[8][name...]`, truncated by the radio to 31
  /// bytes (MyMesh.cpp:1259-1265).
  static Uint8List setAdvertName(String name) => (_Writer()
        ..u8(MeshCoreCmd.setAdvertName)
        ..bytes(_utf8Truncate(name, MeshCoreLimits.nameSize - 1)))
      .take();

  /// CMD_SET_ADVERT_LATLON: `[14][lat e6 i32][lon e6 i32]`
  /// (MyMesh.cpp:1266-1280).
  static Uint8List setAdvertLatLon(double latitude, double longitude) =>
      (_Writer()
            ..u8(MeshCoreCmd.setAdvertLatLon)
            ..i32((latitude * 1e6).round())
            ..i32((longitude * 1e6).round()))
          .take();

  /// CMD_GET_BATT_AND_STORAGE: `[20]` (MyMesh.cpp:1517-1527).
  static Uint8List getBattAndStorage() =>
      Uint8List.fromList([MeshCoreCmd.getBattAndStorage]);

  /// CMD_GET_STATS: `[56][MeshCoreStatsType]` (MyMesh.cpp:1914-1964).
  static Uint8List getStats(int statsType) =>
      Uint8List.fromList([MeshCoreCmd.getStats, statsType & 0xFF]);

  /// CMD_SEND_TELEMETRY_REQ for our own node: exactly `[39][0][0][0]`
  /// (MyMesh.cpp:1700-1719@sha, `len == 4`). Answered only by a
  /// PUSH_CODE_TELEMETRY_RESPONSE carrying our key prefix and Cayenne LPP
  /// (all permissions, so the GPS when the board has one); nothing is
  /// sent on air.
  static Uint8List selfTelemetry() =>
      Uint8List.fromList([MeshCoreCmd.sendTelemetryReq, 0, 0, 0]);

  /// CMD_GET_ALLOWED_REPEAT_FREQ: `[60]` (MyMesh.cpp:2036-2044@sha).
  static Uint8List getAllowedRepeatFreq() =>
      Uint8List.fromList([MeshCoreCmd.getAllowedRepeatFreq]);

  static Uint8List _cmdWithKey(int cmd, Uint8List publicKey) {
    _checkLen(publicKey, MeshCoreLimits.pubKeySize, 'publicKey');
    return (_Writer()
          ..u8(cmd)
          ..bytes(publicKey))
        .take();
  }

  static Uint8List _contactRecord(int code, MeshCoreContact c) {
    _checkLen(c.publicKey, MeshCoreLimits.pubKeySize, 'publicKey');
    final path = Uint8List(MeshCoreLimits.maxPathSize);
    path.setRange(
        0, c.outPath.length.clamp(0, MeshCoreLimits.maxPathSize), c.outPath);
    return (_Writer()
          ..u8(code)
          ..bytes(c.publicKey)
          ..u8(c.type)
          ..u8(c.flags)
          ..u8(c.outPathLen)
          ..bytes(path)
          ..fixedString(c.name, MeshCoreLimits.nameSize)
          ..u32(c.lastAdvertTimestamp)
          ..i32(c.latE6)
          ..i32(c.lonE6)
          ..u32(c.lastModified))
        .take();
  }

  /// Exactly the path bytes [pathLen] says follow.
  static Uint8List _pathBytes(int pathLen, Uint8List? path) {
    if (!MeshCorePathLen.isValid(pathLen)) {
      throw ArgumentError.value(pathLen, 'pathLen', 'invalid path length');
    }
    final n = MeshCorePathLen.byteLength(pathLen);
    final p = path ?? Uint8List(0);
    if (p.length != n) {
      throw ArgumentError.value(p.length, 'path',
          'pathLen 0x${pathLen.toRadixString(16)} needs $n bytes');
    }
    return p;
  }

  static void _checkLen(Uint8List b, int n, String name,
      {bool orLonger = false}) {
    if (orLonger ? b.length < n : b.length != n) {
      throw ArgumentError.value(b.length, name, 'needs $n bytes');
    }
  }
}

// ---------------------------------------------------------------------------
// Parsed frames
// ---------------------------------------------------------------------------

/// A frame received from the radio. [MeshCoreFrame.parse] never throws:
/// unknown codes become [MeshCoreUnknownFrame], short or inconsistent
/// frames become [MeshCoreMalformedFrame].
sealed class MeshCoreFrame {
  /// The whole frame as received.
  final Uint8List bytes;

  const MeshCoreFrame(this.bytes);

  /// Byte 0, or -1 for an empty frame.
  int get code => bytes.isEmpty ? -1 : bytes[0];

  /// Whether this is an unsolicited push (code >= 0x80).
  bool get isPush => code >= 0x80;

  /// Decodes one frame.
  static MeshCoreFrame parse(Uint8List frame) {
    if (frame.isEmpty) {
      return MeshCoreMalformedFrame(frame, 'empty frame');
    }
    try {
      return _parse(frame, _Reader(frame));
    } on _Short catch (e) {
      return MeshCoreMalformedFrame(frame, e.message);
    }
  }
}

/// A frame whose code is not decoded here (or is new).
final class MeshCoreUnknownFrame extends MeshCoreFrame {
  const MeshCoreUnknownFrame(super.bytes);

  @override
  String toString() => 'MeshCoreUnknownFrame(code=0x${code.toRadixString(16)}, '
      '${bytes.length} bytes)';
}

/// A known code whose frame is truncated or inconsistent.
final class MeshCoreMalformedFrame extends MeshCoreFrame {
  final String reason;

  const MeshCoreMalformedFrame(super.bytes, this.reason);

  @override
  String toString() => 'MeshCoreMalformedFrame(code=$code: $reason)';
}

/// RESP_CODE_OK `[0]` (MyMesh.cpp:153-157).
final class MeshCoreOk extends MeshCoreFrame {
  const MeshCoreOk(super.bytes);
}

/// RESP_CODE_ERR `[1][err code]` (MyMesh.cpp:158-163).
final class MeshCoreError extends MeshCoreFrame {
  /// One of [MeshCoreErr]; null if the byte is absent.
  final int? errorCode;

  const MeshCoreError(super.bytes, this.errorCode);

  @override
  String toString() => 'MeshCoreError(${MeshCoreErr.name(errorCode)})';
}

/// RESP_CODE_DISABLED `[15]` (MyMesh.cpp:165-169).
final class MeshCoreDisabled extends MeshCoreFrame {
  const MeshCoreDisabled(super.bytes);
}

/// RESP_CODE_CONTACTS_START `[2][total count u32]` (MyMesh.cpp:1248-1251).
final class MeshCoreContactsStart extends MeshCoreFrame {
  final int count;

  const MeshCoreContactsStart(super.bytes, this.count);
}

/// RESP_CODE_CONTACT, PUSH_CODE_NEW_ADVERT: a full contact record
/// (MyMesh.cpp:171-192@sha).
final class MeshCoreContactFrame extends MeshCoreFrame {
  final MeshCoreContact contact;

  const MeshCoreContactFrame(super.bytes, this.contact);

  /// True for PUSH_CODE_NEW_ADVERT (a node not yet in the contact table).
  bool get isNewAdvert => code == MeshCorePush.newAdvert;
}

/// RESP_CODE_END_OF_CONTACTS `[4][most recent lastmod u32]`
/// (MyMesh.cpp:2403-2406@sha); use it as the next `since`.
final class MeshCoreEndOfContacts extends MeshCoreFrame {
  final int mostRecentLastModified;

  const MeshCoreEndOfContacts(super.bytes, this.mostRecentLastModified);
}

/// RESP_CODE_SELF_INFO.
final class MeshCoreSelfInfoFrame extends MeshCoreFrame {
  final MeshCoreSelfInfo info;

  const MeshCoreSelfInfoFrame(super.bytes, this.info);
}

/// RESP_CODE_DEVICE_INFO.
final class MeshCoreDeviceInfoFrame extends MeshCoreFrame {
  final MeshCoreDeviceInfo info;

  const MeshCoreDeviceInfoFrame(super.bytes, this.info);
}

/// RESP_CODE_SENT `[6][flood][ack or tag u32][est timeout ms u32]`
/// (MyMesh.cpp:1167-1171@sha). For a DM, [expectedAck] is the code a later
/// PUSH_CODE_SEND_CONFIRMED carries (0 = no ACK expected); for requests
/// and traces it is the tag the response will carry.
final class MeshCoreSent extends MeshCoreFrame {
  final bool isFlood;
  final int expectedAck;
  final int estimatedTimeoutMs;

  const MeshCoreSent(
      super.bytes, this.isFlood, this.expectedAck, this.estimatedTimeoutMs);
}

/// RESP_CODE_CONTACT_MSG_RECV(_V3), a DM from the offline queue
/// (`queueMessage`, MyMesh.cpp:440-480@sha):
/// v3: `[16][snr*4 i8][0][0][key prefix x6][path_len][txt_type][ts u32]
/// [sig prefix x4 if signed][text...]`; legacy (7) has no SNR/reserved.
final class MeshCoreContactMessage extends MeshCoreFrame {
  /// SNR of the last hop, dB; null in the legacy frame.
  final double? snr;
  final Uint8List senderKeyPrefix;

  /// Hops it flooded over, or 0xFF if it arrived by a direct route.
  final int pathLen;
  final int txtType;

  /// Sender's clock, Unix seconds.
  final int senderTimestamp;

  /// 4-byte prefix of the signer's key for [MeshCoreTxtType.signedPlain].
  final Uint8List? signerKeyPrefix;
  final String text;

  const MeshCoreContactMessage(
    super.bytes, {
    this.snr,
    required this.senderKeyPrefix,
    required this.pathLen,
    required this.txtType,
    required this.senderTimestamp,
    this.signerKeyPrefix,
    required this.text,
  });

  bool get isDirect => pathLen == MeshCoreLimits.pathUnknown;

  /// Flood hop count, or null when direct.
  int? get hops => isDirect ? null : MeshCorePathLen.hashCount(pathLen);
}

/// RESP_CODE_CHANNEL_MSG_RECV(_V3) (`onChannelMessageRecv`,
/// MyMesh.cpp:558-599@sha): v3 `[17][snr*4 i8][0][0][channel_idx]
/// [path_len][txt_type][ts u32][text...]`; legacy (8) has no SNR/reserved.
/// [text] is "sender name: message" as sent on air.
final class MeshCoreChannelMessage extends MeshCoreFrame {
  final double? snr;
  final int channelIndex;
  final int pathLen;
  final int txtType;
  final int senderTimestamp;
  final String text;

  const MeshCoreChannelMessage(
    super.bytes, {
    this.snr,
    required this.channelIndex,
    required this.pathLen,
    required this.txtType,
    required this.senderTimestamp,
    required this.text,
  });

  bool get isDirect => pathLen == MeshCoreLimits.pathUnknown;
  int? get hops => isDirect ? null : MeshCorePathLen.hashCount(pathLen);
}

/// RESP_CODE_CHANNEL_DATA_RECV (`onChannelDataRecv`,
/// MyMesh.cpp:601-638@sha): `[27][snr*4 i8][0][0][channel_idx][path_len]
/// [data_type u16][data_len][data...]`.
final class MeshCoreChannelData extends MeshCoreFrame {
  final double snr;
  final int channelIndex;
  final int pathLen;
  final int dataType;
  final Uint8List data;

  const MeshCoreChannelData(super.bytes,
      {required this.snr,
      required this.channelIndex,
      required this.pathLen,
      required this.dataType,
      required this.data});
}

/// RESP_CODE_NO_MORE_MESSAGES `[10]`.
final class MeshCoreNoMoreMessages extends MeshCoreFrame {
  const MeshCoreNoMoreMessages(super.bytes);
}

/// RESP_CODE_CURR_TIME `[9][unix secs u32]` (MyMesh.cpp:1281-1286).
final class MeshCoreCurrentTime extends MeshCoreFrame {
  final int unixSeconds;

  const MeshCoreCurrentTime(super.bytes, this.unixSeconds);
}

/// RESP_CODE_BATT_AND_STORAGE `[12][mV u16][used KB u32][total KB u32]`
/// (MyMesh.cpp:1517-1527); storage is absent on old firmware.
final class MeshCoreBattAndStorage extends MeshCoreFrame {
  final int battMilliVolts;
  final int? storageUsedKb;
  final int? storageTotalKb;

  const MeshCoreBattAndStorage(super.bytes, this.battMilliVolts,
      this.storageUsedKb, this.storageTotalKb);
}

/// RESP_CODE_CHANNEL_INFO `[18][idx][name x32][secret x16]`
/// (MyMesh.cpp:1752-1766@sha). The name is `strcpy`'d, so bytes after its
/// NUL are leftovers and ignored.
final class MeshCoreChannelInfo extends MeshCoreFrame {
  final int index;
  final String name;
  final Uint8List secret;

  const MeshCoreChannelInfo(super.bytes, this.index, this.name, this.secret);

  /// An unused slot reads back with an empty name and an all-zero secret.
  bool get isEmpty => name.isEmpty && secret.every((b) => b == 0);
}

/// RESP_CODE_CUSTOM_VARS `[21]["name:value,name:value"]`.
final class MeshCoreCustomVars extends MeshCoreFrame {
  final Map<String, String> vars;

  const MeshCoreCustomVars(super.bytes, this.vars);
}

/// "gps:1,gps_interval:0" → {gps: 1, gps_interval: 0}.
Map<String, String> parseCustomVars(String text) => {
      for (final item in text.split(','))
        if (item.contains(':'))
          item.substring(0, item.indexOf(':')).trim():
              item.substring(item.indexOf(':') + 1).trim(),
    };

/// RESP_CODE_STATS, type RADIO: `[24][1][noise floor i16][last rssi i8]
/// [last snr*4 i8][tx air secs u32][rx air secs u32]`
/// (MyMesh.cpp:1928-1942@sha).
final class MeshCoreRadioStats extends MeshCoreFrame {
  final int noiseFloor;
  final int lastRssi;
  final double lastSnr;
  final int txAirSecs;
  final int rxAirSecs;

  const MeshCoreRadioStats(super.bytes,
      {required this.noiseFloor,
      required this.lastRssi,
      required this.lastSnr,
      required this.txAirSecs,
      required this.rxAirSecs});
}

/// RESP_CODE_STATS, type CORE: `[24][0][batt mV u16][uptime secs u32]
/// [err flags u16][tx queue len]` (MyMesh.cpp:1916-1927@sha).
final class MeshCoreCoreStats extends MeshCoreFrame {
  final int battMilliVolts;
  final int uptimeSecs;
  final int errFlags;
  final int txQueueLen;

  const MeshCoreCoreStats(super.bytes,
      {required this.battMilliVolts,
      required this.uptimeSecs,
      required this.errFlags,
      required this.txQueueLen});
}

/// RESP_CODE_STATS, type PACKETS: `[24][2]` then seven u32 counters
/// (MyMesh.cpp:1943-1961@sha).
final class MeshCorePacketStats extends MeshCoreFrame {
  final int recv;
  final int sent;
  final int sentFlood;
  final int sentDirect;
  final int recvFlood;
  final int recvDirect;
  final int recvErrors;

  const MeshCorePacketStats(super.bytes,
      {required this.recv,
      required this.sent,
      required this.sentFlood,
      required this.sentDirect,
      required this.recvFlood,
      required this.recvDirect,
      required this.recvErrors});
}

/// PUSH_CODE_ADVERT, PUSH_CODE_PATH_UPDATED, PUSH_CODE_CONTACT_DELETED:
/// `[code][pub_key x32]` (MyMesh.cpp:345-347, 358-369, 409-415@sha).
/// ADVERT = an advert from a known contact was heard.
final class MeshCoreKeyPush extends MeshCoreFrame {
  final Uint8List publicKey;

  const MeshCoreKeyPush(super.bytes, this.publicKey);

  bool get isAdvert => code == MeshCorePush.advert;
  bool get isPathUpdated => code == MeshCorePush.pathUpdated;
  bool get isContactDeleted => code == MeshCorePush.contactDeleted;
}

/// PUSH_CODE_SEND_CONFIRMED `[0x82][ack code u32][round trip ms u32]`
/// (MyMesh.cpp:424-432@sha); match [ackCode] to [MeshCoreSent.expectedAck].
final class MeshCoreSendConfirmed extends MeshCoreFrame {
  final int ackCode;
  final int roundTripMs;

  const MeshCoreSendConfirmed(super.bytes, this.ackCode, this.roundTripMs);
}

/// PUSH_CODE_MSG_WAITING `[0x83]`: call CMD_SYNC_NEXT_MESSAGE.
final class MeshCoreMsgWaiting extends MeshCoreFrame {
  const MeshCoreMsgWaiting(super.bytes);
}

/// PUSH_CODE_CONTACTS_FULL `[0x90]`.
final class MeshCoreContactsFull extends MeshCoreFrame {
  const MeshCoreContactsFull(super.bytes);
}

/// PUSH_CODE_LOG_RX_DATA `[0x88][snr*4 i8][rssi i8][raw packet...]`
/// (`logRxRaw`, MyMesh.cpp:291-302@sha): every packet the radio decodes,
/// before any filtering, with its own SNR/RSSI. Packets longer than 173
/// bytes are not reported (frame limit).
final class MeshCoreRxLog extends MeshCoreFrame {
  final double snr;
  final int rssi;
  final Uint8List raw;

  const MeshCoreRxLog(super.bytes, this.snr, this.rssi, this.raw);

  /// The decoded packet header, or null if [raw] is malformed.
  MeshCoreRawPacket? get packet => MeshCoreRawPacket.tryParse(raw);
}

/// PUSH_CODE_RAW_DATA / PUSH_CODE_CONTROL_DATA `[code][snr*4 i8][rssi i8]
/// [path_len][payload...]` (MyMesh.cpp:810-853@sha). For RAW_DATA the path
/// byte is reserved (0xFF).
final class MeshCoreDataPush extends MeshCoreFrame {
  final double snr;
  final int rssi;
  final int pathLen;
  final Uint8List payload;

  const MeshCoreDataPush(
      super.bytes, this.snr, this.rssi, this.pathLen, this.payload);

  bool get isControl => code == MeshCorePush.controlData;
}

/// PUSH_CODE_TRACE_DATA (`onTraceRecv`, MyMesh.cpp:855-884@sha):
/// `[0x89][0][path_len][flags][tag u32][auth u32][hashes x path_len]
/// [snr*4 i8 x (path_len >> (flags & 3))][final snr*4 i8]`.
/// [hopSnrs][i] is how well hop i heard the packet; [finalSnr] is how well
/// our radio heard the last hop.
final class MeshCoreTraceData extends MeshCoreFrame {
  final int flags;
  final int tag;
  final int authCode;

  /// The traced path's hop hashes, [hashSize] bytes each.
  final Uint8List pathHashes;
  final List<double> hopSnrs;
  final double finalSnr;

  const MeshCoreTraceData(
    super.bytes, {
    required this.flags,
    required this.tag,
    required this.authCode,
    required this.pathHashes,
    required this.hopSnrs,
    required this.finalSnr,
  });

  int get hashSize => 1 << (flags & 0x03);
  int get hopCount => hopSnrs.length;
}

/// PUSH_CODE_STATUS_RESPONSE / PUSH_CODE_TELEMETRY_RESPONSE `[code][0][key
/// prefix x6][data...]` (MyMesh.cpp:724-748@sha). For a status response
/// [data] is a `RepeaterStats` blob ([repeaterStats]); for telemetry it is
/// Cayenne LPP (big-endian).
final class MeshCoreNodeResponse extends MeshCoreFrame {
  final Uint8List keyPrefix;
  final Uint8List data;

  const MeshCoreNodeResponse(super.bytes, this.keyPrefix, this.data);

  bool get isStatus => code == MeshCorePush.statusResponse;
  bool get isTelemetry => code == MeshCorePush.telemetryResponse;

  /// Decoded stats for a status response from a repeater/room server.
  MeshCoreRepeaterStats? get repeaterStats =>
      isStatus ? MeshCoreRepeaterStats.tryParse(data) : null;
}

/// PUSH_CODE_BINARY_RESPONSE `[0x8C][0][tag u32][data...]`
/// (MyMesh.cpp:750-775@sha); the tag matches [MeshCoreSent.expectedAck].
final class MeshCoreBinaryResponse extends MeshCoreFrame {
  final int tag;
  final Uint8List data;

  const MeshCoreBinaryResponse(super.bytes, this.tag, this.data);
}

/// RESP_ALLOWED_REPEAT_FREQ `[26]` then `[lower kHz u32][upper kHz u32]`
/// per range (MyMesh.cpp:2036-2044@sha): the frequencies at which the radio
/// accepts client repeat (default 433000, 869495, 918000 kHz exactly,
/// MyMesh.cpp:1032-1040).
final class MeshCoreAllowedRepeatFreq extends MeshCoreFrame {
  /// Inclusive (lower, upper) ranges in kHz.
  final List<(int, int)> rangesKHz;

  const MeshCoreAllowedRepeatFreq(super.bytes, this.rangesKHz);
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

MeshCoreFrame _parse(Uint8List f, _Reader r) {
  final code = r.u8();
  switch (code) {
    case MeshCoreResp.ok:
      return MeshCoreOk(f);
    case MeshCoreResp.err:
      return MeshCoreError(f, r.remaining > 0 ? r.u8() : null);
    case MeshCoreResp.disabled:
      return MeshCoreDisabled(f);
    case MeshCoreResp.contactsStart:
      return MeshCoreContactsStart(f, r.u32());
    case MeshCoreResp.contact:
    case MeshCorePush.newAdvert:
      return MeshCoreContactFrame(f, _contact(r));
    case MeshCoreResp.endOfContacts:
      return MeshCoreEndOfContacts(f, r.u32());
    case MeshCoreResp.selfInfo:
      return MeshCoreSelfInfoFrame(f, _selfInfo(r));
    case MeshCoreResp.deviceInfo:
      return MeshCoreDeviceInfoFrame(f, _deviceInfo(r));
    case MeshCoreResp.sent:
      return MeshCoreSent(f, r.u8() == 1, r.u32(), r.u32());
    case MeshCoreResp.contactMsgRecv:
    case MeshCoreResp.contactMsgRecvV3:
      return _contactMessage(f, r, v3: code == MeshCoreResp.contactMsgRecvV3);
    case MeshCoreResp.channelMsgRecv:
    case MeshCoreResp.channelMsgRecvV3:
      final v3 = code == MeshCoreResp.channelMsgRecvV3;
      final snr = v3 ? _snr(r) : null;
      if (v3) r.skip(2);
      return MeshCoreChannelMessage(f,
          snr: snr,
          channelIndex: r.u8(),
          pathLen: r.u8(),
          txtType: r.u8(),
          senderTimestamp: r.u32(),
          text: _utf8(r.rest()));
    case MeshCoreResp.channelDataRecv:
      final snr = _snr(r);
      r.skip(2);
      final idx = r.u8();
      final pathLen = r.u8();
      final dataType = r.u16();
      final len = r.u8();
      return MeshCoreChannelData(f,
          snr: snr,
          channelIndex: idx,
          pathLen: pathLen,
          dataType: dataType,
          data: r.take(len));
    case MeshCoreResp.noMoreMessages:
      return MeshCoreNoMoreMessages(f);
    case MeshCoreResp.currTime:
      return MeshCoreCurrentTime(f, r.u32());
    case MeshCoreResp.battAndStorage:
      final mv = r.u16();
      final hasStorage = r.remaining >= 8;
      return MeshCoreBattAndStorage(
          f, mv, hasStorage ? r.u32() : null, hasStorage ? r.u32() : null);
    case MeshCoreResp.channelInfo:
      return MeshCoreChannelInfo(
          f,
          r.u8(),
          r.fixedString(MeshCoreLimits.nameSize),
          r.take(MeshCoreLimits.channelSecretSize));
    case MeshCoreResp.stats:
      return _stats(f, r);
    case MeshCoreResp.customVars:
      return MeshCoreCustomVars(f, parseCustomVars(_utf8(r.rest())));
    case MeshCoreResp.allowedRepeatFreq:
      final ranges = <(int, int)>[];
      while (r.remaining >= 8) {
        ranges.add((r.u32(), r.u32()));
      }
      return MeshCoreAllowedRepeatFreq(f, ranges);
    case MeshCorePush.advert:
    case MeshCorePush.pathUpdated:
    case MeshCorePush.contactDeleted:
      return MeshCoreKeyPush(f, r.take(MeshCoreLimits.pubKeySize));
    case MeshCorePush.sendConfirmed:
      return MeshCoreSendConfirmed(f, r.u32(), r.u32());
    case MeshCorePush.msgWaiting:
      return MeshCoreMsgWaiting(f);
    case MeshCorePush.contactsFull:
      return MeshCoreContactsFull(f);
    case MeshCorePush.logRxData:
      return MeshCoreRxLog(f, _snr(r), r.i8(), r.rest());
    case MeshCorePush.rawData:
    case MeshCorePush.controlData:
      return MeshCoreDataPush(f, _snr(r), r.i8(), r.u8(), r.rest());
    case MeshCorePush.traceData:
      return _trace(f, r);
    case MeshCorePush.statusResponse:
    case MeshCorePush.telemetryResponse:
      r.skip(1);
      return MeshCoreNodeResponse(
          f, r.take(MeshCoreLimits.pubKeyPrefixSize), r.rest());
    case MeshCorePush.binaryResponse:
      r.skip(1);
      return MeshCoreBinaryResponse(f, r.u32(), r.rest());
    default:
      return MeshCoreUnknownFrame(f);
  }
}

double _snr(_Reader r) => r.i8() / 4.0;

// MyMesh.cpp:171-192 (writeContactRespFrame) @sha. 148 bytes with the code.
MeshCoreContact _contact(_Reader r) {
  final key = r.take(MeshCoreLimits.pubKeySize);
  final type = r.u8();
  final flags = r.u8();
  final outPathLen = r.u8();
  final pathBuf = r.take(MeshCoreLimits.maxPathSize);
  final name = r.fixedString(MeshCoreLimits.nameSize);
  final lastAdvert = r.u32();
  final lat = r.i32();
  final lon = r.i32();
  final lastMod = r.u32();
  final pathBytes = outPathLen == MeshCoreLimits.pathUnknown ||
          !MeshCorePathLen.isValid(outPathLen)
      ? 0
      : MeshCorePathLen.byteLength(outPathLen);
  return MeshCoreContact(
    publicKey: key,
    type: type,
    flags: flags,
    outPathLen: outPathLen,
    outPath: Uint8List.fromList(pathBuf.sublist(0, pathBytes)),
    name: name,
    lastAdvertTimestamp: lastAdvert,
    latE6: lat,
    lonE6: lon,
    lastModified: lastMod,
  );
}

// MyMesh.cpp:1084-1116 @sha. Offsets: 1 adv_type, 2 tx_power, 3 max_tx,
// 4-35 key, 36 lat, 40 lon, 44 multi_acks, 45 loc policy, 46 telemetry
// modes, 47 manual add, 48 freq kHz, 52 bw Hz, 56 sf, 57 cr, 58+ name.
MeshCoreSelfInfo _selfInfo(_Reader r) {
  final advType = r.u8();
  final tx = r.i8();
  final maxTx = r.i8();
  final key = r.take(MeshCoreLimits.pubKeySize);
  int? lat, lon, multiAcks, locPolicy, telem, manual, freq, bw, sf, cr;
  if (r.remaining >= 8) {
    lat = r.i32();
    lon = r.i32();
  }
  if (r.remaining >= 4) {
    multiAcks = r.u8();
    locPolicy = r.u8();
    telem = r.u8();
    manual = r.u8();
  }
  if (r.remaining >= 10) {
    freq = r.u32();
    bw = r.u32();
    sf = r.u8();
    cr = r.u8();
  }
  return MeshCoreSelfInfo(
    advType: advType,
    txPowerDbm: tx,
    maxTxPowerDbm: maxTx,
    publicKey: key,
    latE6: lat,
    lonE6: lon,
    multiAcks: multiAcks,
    advertLocationPolicy: locPolicy,
    telemetryModes: telem,
    manualAddContacts: manual,
    frequencyKHz: freq,
    bandwidthHz: bw,
    spreadingFactor: sf,
    codingRate: cr,
    name: _utf8(r.rest()),
  );
}

// MyMesh.cpp:1059-1074 @sha. Offsets: 1 ver code, 2 max contacts / 2,
// 3 max channels, 4 BLE pin u32, 8 build date x12, 20 manufacturer x40,
// 60 version x20, 80 client repeat, 81 path hash mode.
MeshCoreDeviceInfo _deviceInfo(_Reader r) {
  final ver = r.u8();
  int? maxContacts, maxChannels, pin, pathHashMode;
  String? date, manufacturer, version;
  bool? repeat;
  if (r.remaining >= 2) {
    maxContacts = r.u8() * 2;
    maxChannels = r.u8();
  }
  if (r.remaining >= 4) pin = r.u32();
  if (r.remaining >= 12) date = r.fixedString(12);
  if (r.remaining >= 40) manufacturer = r.fixedString(40);
  if (r.remaining >= 20) version = r.fixedString(20);
  if (r.remaining >= 1) repeat = r.u8() != 0;
  if (r.remaining >= 1) pathHashMode = r.u8();
  return MeshCoreDeviceInfo(
    firmwareVerCode: ver,
    maxContacts: maxContacts,
    maxChannels: maxChannels,
    blePin: pin,
    buildDate: date,
    manufacturer: manufacturer,
    firmwareVersion: version,
    clientRepeat: repeat,
    pathHashMode: pathHashMode,
  );
}

// MyMesh.cpp:440-466 (queueMessage) @sha.
MeshCoreFrame _contactMessage(Uint8List f, _Reader r, {required bool v3}) {
  final snr = v3 ? _snr(r) : null;
  if (v3) r.skip(2);
  final prefix = r.take(MeshCoreLimits.pubKeyPrefixSize);
  final pathLen = r.u8();
  final txtType = r.u8();
  final ts = r.u32();
  final signer = txtType == MeshCoreTxtType.signedPlain ? r.take(4) : null;
  return MeshCoreContactMessage(f,
      snr: snr,
      senderKeyPrefix: prefix,
      pathLen: pathLen,
      txtType: txtType,
      senderTimestamp: ts,
      signerKeyPrefix: signer,
      text: _utf8(r.rest()));
}

// MyMesh.cpp:1914-1964 @sha.
MeshCoreFrame _stats(Uint8List f, _Reader r) {
  switch (r.u8()) {
    case MeshCoreStatsType.core:
      return MeshCoreCoreStats(f,
          battMilliVolts: r.u16(),
          uptimeSecs: r.u32(),
          errFlags: r.u16(),
          txQueueLen: r.u8());
    case MeshCoreStatsType.radio:
      return MeshCoreRadioStats(f,
          noiseFloor: r.i16(),
          lastRssi: r.i8(),
          lastSnr: _snr(r),
          txAirSecs: r.u32(),
          rxAirSecs: r.u32());
    case MeshCoreStatsType.packets:
      return MeshCorePacketStats(f,
          recv: r.u32(),
          sent: r.u32(),
          sentFlood: r.u32(),
          sentDirect: r.u32(),
          recvFlood: r.u32(),
          recvDirect: r.u32(),
          recvErrors: r.u32());
    default:
      return MeshCoreUnknownFrame(f);
  }
}

// MyMesh.cpp:855-884 (onTraceRecv) @sha.
MeshCoreFrame _trace(Uint8List f, _Reader r) {
  r.skip(1);
  final pathLen = r.u8();
  final flags = r.u8();
  final tag = r.u32();
  final auth = r.u32();
  final hashes = r.take(pathLen);
  final hops = pathLen >> (flags & 0x03);
  final snrs = [for (var i = 0; i < hops; i++) _snr(r)];
  final finalSnr = _snr(r);
  return MeshCoreTraceData(f,
      flags: flags,
      tag: tag,
      authCode: auth,
      pathHashes: hashes,
      hopSnrs: snrs,
      finalSnr: finalSnr);
}

// ---------------------------------------------------------------------------
// Byte helpers
// ---------------------------------------------------------------------------

/// Lower-case hex of the first [maxBytes] bytes (all when null).
String hexOf(List<int> bytes, [int? maxBytes]) {
  final n =
      maxBytes == null || maxBytes > bytes.length ? bytes.length : maxBytes;
  final sb = StringBuffer();
  for (var i = 0; i < n; i++) {
    sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Decodes UTF-8, stopping at the first NUL; malformed sequences (the
/// firmware truncates by bytes) become U+FFFD instead of throwing.
String _utf8(Uint8List b) {
  final nul = b.indexOf(0);
  return utf8.decode(nul < 0 ? b : b.sublist(0, nul), allowMalformed: true);
}

/// [s] as UTF-8, cut to at most [maxBytes] without splitting a character.
Uint8List _utf8Truncate(String s, int maxBytes) {
  final b = utf8.encode(s);
  if (b.length <= maxBytes) return b;
  var n = maxBytes;
  while (n > 0 && (b[n] & 0xC0) == 0x80) {
    n--;
  }
  return Uint8List.fromList(b.sublist(0, n));
}

class _Short implements Exception {
  final String message;
  _Short(this.message);
}

class _Reader {
  final Uint8List _b;
  final ByteData _d;
  int _i = 0;

  _Reader(this._b) : _d = ByteData.sublistView(_b);

  int get remaining => _b.length - _i;

  void _need(int n) {
    if (remaining < n) {
      throw _Short('truncated: needs $n more bytes at offset $_i, '
          'frame is ${_b.length}');
    }
  }

  int u8() {
    _need(1);
    return _b[_i++];
  }

  int i8() {
    _need(1);
    return _d.getInt8(_i++);
  }

  int u16() {
    _need(2);
    final v = _d.getUint16(_i, Endian.little);
    _i += 2;
    return v;
  }

  int i16() {
    _need(2);
    final v = _d.getInt16(_i, Endian.little);
    _i += 2;
    return v;
  }

  int u32() {
    _need(4);
    final v = _d.getUint32(_i, Endian.little);
    _i += 4;
    return v;
  }

  int i32() {
    _need(4);
    final v = _d.getInt32(_i, Endian.little);
    _i += 4;
    return v;
  }

  void skip(int n) {
    _need(n);
    _i += n;
  }

  Uint8List take(int n) {
    _need(n);
    final v = Uint8List.fromList(_b.sublist(_i, _i + n));
    _i += n;
    return v;
  }

  String fixedString(int width) => _utf8(take(width));

  Uint8List rest() => take(remaining);
}

class _Writer {
  final _b = BytesBuilder(copy: false);
  final _tmp = ByteData(4);

  void u8(int v) => _b.addByte(v & 0xFF);

  void u16(int v) {
    _tmp.setUint16(0, v & 0xFFFF, Endian.little);
    _b.add(_tmp.buffer.asUint8List(0, 2).toList());
  }

  void u32(int v) {
    _tmp.setUint32(0, v & 0xFFFFFFFF, Endian.little);
    _b.add(_tmp.buffer.asUint8List(0, 4).toList());
  }

  void i32(int v) {
    _tmp.setInt32(0, v, Endian.little);
    _b.add(_tmp.buffer.asUint8List(0, 4).toList());
  }

  void bytes(List<int> v) => _b.add(v);

  void zeros(int n) => _b.add(Uint8List(n));

  /// NUL-padded fixed-width string with at least one NUL (firmware
  /// `strzcpy`/`strncpy` semantics).
  void fixedString(String s, int width) {
    final out = Uint8List(width);
    final enc = _utf8Truncate(s, width - 1);
    out.setRange(0, enc.length, enc);
    _b.add(out);
  }

  Uint8List take() => _b.takeBytes();
}
