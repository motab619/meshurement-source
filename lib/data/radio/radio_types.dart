// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:typed_data';

import 'radio_preset.dart';

/// Parse "2.5.11.abcdef" to [2, 5, 11]; null when it doesn't start with a
/// number.
List<int>? parseFirmwareVersion(String version) {
  final m = RegExp(r'^\s*v?(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(version);
  if (m == null) return null;
  return [
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3) ?? '0'),
  ];
}

/// Which mesh protocol a radio speaks. Stored on sessions by [name].
enum RadioProtocol { meshtastic, meshcore }

/// Phone ↔ radio link state.
enum RadioConnectionState {
  disconnected,
  connecting,

  /// Waiting for the user to enter the radio's Bluetooth PIN.
  pairing,

  /// Linked; downloading the radio's config and node list.
  configuring,
  ready,

  /// Link dropped unexpectedly; retrying with backoff.
  reconnecting,
}

/// What a connect (or reconnect) attempt is doing, for a progress display.
class ConnectProgress {
  final RadioConnectionState state;

  /// The current step in plain words, e.g. "Downloading node list".
  final String step;

  /// Counts so far, e.g. "87 of 142 nodes"; null when there's nothing to count.
  final String? detail;

  /// 0–1 when the radio said how much is coming, else null (indeterminate).
  final double? fraction;

  /// When this step began; the UI shows how long it has been going.
  final DateTime stepStartedAt;

  /// Reconnecting only: retry number (1 = first retry) and when it starts.
  final int attempt;
  final DateTime? retryAt;

  const ConnectProgress({
    required this.state,
    required this.step,
    required this.stepStartedAt,
    this.detail,
    this.fraction,
    this.attempt = 0,
    this.retryAt,
  });
}

/// A radio found by a scan (or remembered), enough to connect to it.
class RadioDescriptor {
  /// Platform Bluetooth identifier (a UUID on iOS, a MAC on Android).
  final String id;
  final String name;
  final RadioProtocol protocol;

  /// Signal strength at scan time, when known.
  final int? scanRssi;

  const RadioDescriptor({
    required this.id,
    required this.name,
    this.protocol = RadioProtocol.meshtastic,
    this.scanRssi,
  });

  @override
  bool operator ==(Object other) => other is RadioDescriptor && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// What the connected radio says about itself.
class RadioInfo {
  final RadioProtocol protocol;
  final String model;
  final String firmwareVersion;

  /// Protocol/API version negotiated with the radio, when it has one.
  final int? protocolVersion;

  const RadioInfo({
    required this.protocol,
    required this.model,
    required this.firmwareVersion,
    this.protocolVersion,
  });
}

/// A node the radio knows about (from its node DB or adverts).
class RadioNode {
  /// Mesh-wide node number (not the local DB id).
  final int num;
  final String longName;
  final String shortName;

  /// Hardware model name as the radio reports it, e.g. "TRACKER_T1000_E".
  final String hwModel;
  final double? latitude;
  final double? longitude;

  /// Hops away when last heard, if the radio knows.
  final int? hopsAway;
  final DateTime? lastHeard;

  /// The node's public key, on protocols where that is its identity
  /// (MeshCore: 32 bytes; [num] is then derived from it). Null otherwise.
  final Uint8List? publicKey;

  /// What the node is, when the protocol says: one of the [NodeKind]
  /// strings (MeshCore advert type). Null when unknown.
  final String? nodeKind;

  const RadioNode({
    required this.num,
    this.longName = '',
    this.shortName = '',
    this.hwModel = '',
    this.latitude,
    this.longitude,
    this.hopsAway,
    this.lastHeard,
    this.publicKey,
    this.nodeKind,
  });

  bool get hasUser => longName.isNotEmpty || shortName.isNotEmpty;
  bool get hasPosition =>
      latitude != null &&
      longitude != null &&
      (latitude != 0 || longitude != 0);
}

/// [RadioNode.nodeKind] values.
class NodeKind {
  NodeKind._();
  static const chat = 'chat';
  static const repeater = 'repeater';
  static const room = 'room';
  static const sensor = 'sensor';
}

/// One packet heard over the air, with its signal. Protocol-neutral.
class ReceivedPacket {
  /// Sending node number.
  final int from;

  /// Radio-assigned packet id (0 when the protocol has none).
  final int packetId;

  /// One of the `PacketType` strings in `utils/constants.dart`.
  final String type;

  /// Null when the radio didn't record it.
  final double? snr;
  final int? rssi;

  /// Hops travelled (0 = heard directly). SNR/RSSI describe the last hop.
  /// Meaningless when [hopsKnown] is false.
  final int hops;

  /// False when the protocol can't say how far the packet travelled
  /// (MeshCore direct packets, which carry only the hops still ahead).
  /// Such packets are kept in the log but not used for coverage.
  final bool hopsKnown;

  /// Protocol routing: true for a directed (source-routed) packet, false
  /// for a flood, null when the protocol doesn't distinguish.
  final bool? routeDirect;

  /// The node whose transmission we heard when [hops] > 0 (the last
  /// relay), when the protocol names it. Null when it is [from] or unknown.
  final int? lastHopId;
  final int channelIndex;
  final bool viaMqtt;

  /// Decrypted application payload; empty when we couldn't decode it.
  final Uint8List payload;

  /// When the radio received it over the air, if the radio knows the time
  /// (null otherwise). Radios buffer packets while the phone is away and
  /// replay them on connect; this tells the stale ones apart.
  final DateTime? rxTime;

  /// Delivered during the connect handshake (replayed from the radio's
  /// buffer), not heard just now.
  final bool queued;

  /// Beacon sequence number, when the sender's beacon carries one (Range
  /// Test `seq N`). Null for everything else.
  final int? beaconSeq;

  /// The sender's own channel utilisation (%) when the packet is a
  /// telemetry report that carries it. Null otherwise.
  final double? senderChannelUtil;

  ReceivedPacket({
    required this.from,
    required this.type,
    this.packetId = 0,
    this.snr,
    this.rssi,
    this.hops = 0,
    this.hopsKnown = true,
    this.routeDirect,
    this.lastHopId,
    this.channelIndex = 0,
    this.viaMqtt = false,
    Uint8List? payload,
    this.rxTime,
    this.queued = false,
    this.beaconSeq,
    this.senderChannelUtil,
  }) : payload = payload ?? Uint8List(0);

  /// Older than [maxAge] by the radio's clock, or replayed from its buffer:
  /// the phone was not necessarily here when this was heard.
  bool isStale(DateTime now, {Duration maxAge = const Duration(minutes: 2)}) {
    if (queued) return true;
    final t = rxTime;
    return t != null && now.difference(t) > maxAge;
  }
}

enum PingStatus {
  /// ACK from the target itself.
  received,

  /// ACK from another node (a relay was heard passing it on).
  implicit,

  /// The radio refused to send for airtime/duty-cycle reasons.
  throttled,

  /// NAK or send failure; see [PingOutcome.errorReason].
  error,

  /// No reply in time.
  timeout,
}

/// How one ping ended. Named to avoid the DB's `PingResult` row class.
class PingOutcome {
  /// The id passed to `beforeSend`.
  final int pingId;
  final PingStatus status;

  /// Protocol error name for [PingStatus.error]/[PingStatus.throttled].
  final String? errorReason;

  /// Node that answered (null on timeout/send failure).
  final int? responder;

  /// Id of the reply packet, when there was one.
  final int? replyPacketId;

  /// How well we heard the reply (downlink: target → us).
  final double? snr;
  final int? rssi;
  final int hops;
  final Duration roundTrip;

  /// How well the target heard our ping (uplink: us → target), when the
  /// protocol reports it (MeshCore trace hop SNR; Meshtastic traceroute).
  /// Null otherwise.
  final double? uplinkSnr;
  final int? uplinkRssi;

  const PingOutcome({
    required this.pingId,
    required this.status,
    required this.roundTrip,
    this.errorReason,
    this.responder,
    this.replyPacketId,
    this.snr,
    this.rssi,
    this.hops = 0,
    this.uplinkSnr,
    this.uplinkRssi,
  });
}

/// Everything needed to put a radio on our private test setup.
class TestProfile {
  /// Private channel name, e.g. "MeshTest".
  final String channelName;

  /// Channel key generated on the phone (32 bytes for AES-256).
  final Uint8List channelKey;
  final RadioPreset preset;

  /// Base = beacon sender; mobile = receiver.
  final bool isBase;

  /// Base beacon, applied in the same settings transaction (one reboot).
  final BeaconConfig? beacon;

  /// Region code name to apply (e.g. "EU_868"). Null/empty: keep the
  /// radio's own region (the protocol's default when it has none).
  final String? regionName;

  /// Rename the radio (long and short name) in the same transaction, so its
  /// role shows on its own screen. Null: keep its names.
  final String? radioLongName;
  final String? radioShortName;

  /// Exact centre frequency to apply, MHz, on protocols without a
  /// region → frequency table (MeshCore). Null: the protocol decides
  /// (Meshtastic: from the region and preset).
  final double? frequencyMHz;

  /// Transmit power to apply, dBm. Null: keep the radio's own.
  final int? txPowerDbm;

  /// A base must relay (MeshCore client repeat on), so it can answer trace
  /// pings. Ignored for a mobile and on protocols where a base needs no
  /// relaying.
  final bool baseRelays;

  /// [channelKey] as the protocol takes it: MeshCore channel secrets are 16
  /// bytes (the first 16 of our 32).
  Uint8List get channelKey16 => Uint8List.sublistView(
      channelKey, 0, channelKey.length < 16 ? channelKey.length : 16);

  const TestProfile({
    required this.channelName,
    required this.channelKey,
    required this.preset,
    required this.isBase,
    this.beacon,
    this.regionName,
    this.radioLongName,
    this.radioShortName,
    this.frequencyMHz,
    this.txPowerDbm,
    this.baseRelays = true,
  });
}

/// What the base radio sends so the mobile can measure the link without
/// pings. Position is deliberately not a kind: firmware 2.8 floors
/// stationary position broadcasts at 6 hours.
enum BeaconKind {
  none,

  /// Meshtastic Range Test sender: `seq N`, hop limit 0. Absent on firmware
  /// 2.8 and on classic ESP32 boards from 2.7.
  rangeTest,

  /// Periodic device telemetry broadcast (battery, channel use, uptime).
  telemetry,

  /// "Pulled" beacon: the mobile sends the base a trace ping on a timer and
  /// the reply is the beacon sample (MeshCore, whose radios send nothing
  /// periodic on their own). Nothing is written to the base; the app on
  /// the mobile runs the schedule and every miss is a known timeout.
  trace;

  /// Value stored in the sessions table (`beacon_kind`).
  String get dbValue => name;

  static BeaconKind fromDb(String? value) => BeaconKind.values
      .firstWhere((k) => k.name == value, orElse: () => BeaconKind.none);
}

/// What a connected radio's firmware can do, read at connect. Protocol
/// neutral: MeshCore fills in its own.
class RadioCapabilities {
  /// Firmware version string as the radio reports it; empty when unknown.
  final String firmwareVersion;

  /// The radio says its Range Test module is compiled out (firmware 2.8+
  /// sets this; 2.7 never does, even where the module is missing).
  final bool rangeTestExcluded;

  /// Can answer traceroute requests (Meshtastic 2.3+).
  final bool hasTraceroute;

  /// The radio relays other nodes' packets (MeshCore client repeat on, or
  /// repeater firmware). A MeshCore base must, to answer trace pings. Null
  /// when unknown or not applicable.
  final bool? canRelay;

  /// Width of the path hashes this radio puts in its own floods (MeshCore
  /// path hash mode, 1-3 bytes). Null when unknown or not applicable.
  final int? pathHashBytes;

  /// Companion/app protocol level the firmware speaks (MeshCore
  /// `FIRMWARE_VER_CODE`). Null when unknown or not applicable.
  final int? protocolLevel;

  const RadioCapabilities({
    this.firmwareVersion = '',
    this.rangeTestExcluded = false,
    this.hasTraceroute = false,
    this.canRelay,
    this.pathHashBytes,
    this.protocolLevel,
  });

  /// Nothing known (not connected, or a radio that doesn't say).
  static const unknown = RadioCapabilities();

  /// Firmware is [major].[minor] or newer. False when the version is
  /// unknown.
  bool firmwareAtLeast(int major, int minor) {
    final v = parseFirmwareVersion(firmwareVersion);
    if (v == null) return false;
    return v[0] != major ? v[0] > major : v[1] >= minor;
  }
}

/// The beacon a base with [caps] should run. MeshCore: always the pulled
/// trace beacon ([BeaconKind.trace]). Meshtastic: telemetry where Range
/// Test is gone (reported excluded, or firmware 2.8 and later); Range Test
/// on older firmware, where it is the densest beacon and carries a sequence
/// number.
BeaconKind selectBeaconKind(RadioCapabilities caps,
    {RadioProtocol protocol = RadioProtocol.meshtastic}) {
  if (protocol == RadioProtocol.meshcore) return BeaconKind.trace;
  if (caps.rangeTestExcluded) return BeaconKind.telemetry;
  if (caps.firmwareAtLeast(2, 8)) return BeaconKind.telemetry;
  // Unknown firmware: telemetry works everywhere, Range Test may be missing.
  if (caps.firmwareVersion.isEmpty) return BeaconKind.telemetry;
  return BeaconKind.rangeTest;
}

/// Periodic beacon from the base. Interval 0 or kind [BeaconKind.none]
/// turns it off. A null [kind] lets the radio choose from its
/// capabilities ([selectBeaconKind]).
class BeaconConfig {
  final int intervalSec;
  final BeaconKind? kind;
  const BeaconConfig({required this.intervalSec, this.kind});

  const BeaconConfig.off()
      : intervalSec = 0,
        kind = BeaconKind.none;

  bool get enabled => intervalSec > 0 && kind != BeaconKind.none;

  /// What is actually sent: [kind] when on, else none. An open (null) kind
  /// counts as none until [resolved].
  BeaconKind get activeKind =>
      enabled ? (kind ?? BeaconKind.none) : BeaconKind.none;

  /// The config with the kind filled in from [caps] when it was left open,
  /// and the interval the radio will really use ([normalized]).
  BeaconConfig resolved(RadioCapabilities caps,
          {RadioProtocol protocol = RadioProtocol.meshtastic}) =>
      BeaconConfig(
        intervalSec: intervalSec,
        kind: kind ?? selectBeaconKind(caps, protocol: protocol),
      ).normalized();

  /// The interval as the radio will keep it. Meshtastic's device telemetry
  /// module wakes once a minute (2.7.26 and 2.8.1, `DeviceTelemetry.h`
  /// `sendToPhoneIntervalMs`), so a telemetry beacon goes out at most every
  /// 60 s and otherwise on the next whole minute; seen on a Heltec V3 on
  /// 2.7.26 set to 20 s. Range Test keeps its own interval.
  BeaconConfig normalized() => kind == BeaconKind.telemetry && intervalSec > 0
      ? BeaconConfig(intervalSec: telemetryIntervalSec(intervalSec), kind: kind)
      : this;

  /// [requested] seconds rounded up to a whole minute, at least 60.
  static int telemetryIntervalSec(int requested) =>
      requested <= 60 ? 60 : (requested + 59) ~/ 60 * 60;
}

/// The radio's own measurement of how busy the air is. Optional: a
/// protocol/firmware that doesn't report it never emits one.
class RadioChannelStats {
  /// Percent (0..100) of the last hour our radio spent transmitting
  /// (Meshtastic `air_util_tx`). Includes everything it sends, not just
  /// the app's pings.
  final double airUtilTxPercent;

  /// Percent (0..100) of the channel busy with anyone's traffic, over a
  /// short recent window (Meshtastic: the last minute).
  final double channelUtilizationPercent;

  /// When the phone received the report.
  final DateTime measuredAt;

  const RadioChannelStats({
    required this.airUtilTxPercent,
    required this.channelUtilizationPercent,
    required this.measuredAt,
  });
}

/// The radio settings, beyond the modulation preset, that change what a
/// session measures: which frequency slot it sat on, how loud it
/// transmitted and how far packets may be relayed. Recorded on every
/// session so a preset or antenna comparison can't silently be a frequency
/// or power comparison. Protocol neutral; any field may be unknown.
class RadioSettings {
  /// Region code name, e.g. "US" (empty when unknown).
  final String region;

  /// Effective frequency slot, 1-based as Meshtastic numbers it
  /// (`channel_num`); null when a verbatim frequency overrides the slot or
  /// it can't be worked out.
  final int? frequencySlot;

  /// Transmit power the radio runs at, dBm.
  final int? txPowerDbm;

  /// How many times a packet may be relayed.
  final int? hopLimit;

  /// Centre frequency, MHz, when derivable.
  final double? frequencyMHz;

  const RadioSettings({
    this.region = '',
    this.frequencySlot,
    this.txPowerDbm,
    this.hopLimit,
    this.frequencyMHz,
  });

  @override
  bool operator ==(Object other) =>
      other is RadioSettings &&
      other.region == region &&
      other.frequencySlot == frequencySlot &&
      other.txPowerDbm == txPowerDbm &&
      other.hopLimit == hopLimit &&
      other.frequencyMHz == frequencyMHz;

  @override
  int get hashCode =>
      Object.hash(region, frequencySlot, txPowerDbm, hopLimit, frequencyMHz);

  @override
  String toString() => 'RadioSettings($region slot $frequencySlot, '
      '$frequencyMHz MHz, $txPowerDbm dBm, hops $hopLimit)';
}

/// "Slot 20 · 906.875 MHz · 27 dBm · hops 3", leaving out unknown parts;
/// empty when nothing is known. Takes the parts separately so stored
/// session columns can use it too.
String radioSettingsSummary({
  int? frequencySlot,
  double? frequencyMHz,
  int? txPowerDbm,
  int? hopLimit,
}) =>
    [
      if (frequencySlot != null) 'Slot $frequencySlot',
      if (frequencyMHz != null) '${formatFrequencyMHz(frequencyMHz)} MHz',
      if (txPowerDbm != null) '$txPowerDbm dBm',
      if (hopLimit != null) 'hops $hopLimit',
    ].join(' · ');

/// 906.875 → "906.875", 869.525 → "869.525", 915.0 → "915.000".
String formatFrequencyMHz(double mhz) => mhz.toStringAsFixed(3);

/// A position from our own node's GPS (the node the phone is connected
/// to, when it has a GPS chip: T1000-E and the like). It reaches the phone
/// over Bluetooth only: nothing extra goes on air. Used where the phone
/// has no good fix of its own (a Wi-Fi iPad has no GPS). Protocol neutral.
class NodeFix {
  final double latitude;
  final double longitude;
  final double? altitudeM;

  /// Rough horizontal accuracy in metres (the protocols report little:
  /// MeshCore rounds to 0.0001°, Meshtastic rarely sends DOP).
  final double accuracyM;

  /// When the node took the fix if it says, else when the phone got it.
  final DateTime time;

  const NodeFix({
    required this.latitude,
    required this.longitude,
    this.altitudeM,
    required this.accuracyM,
    required this.time,
  });

  /// A 0,0 position is "no fix", not a place.
  bool get isValid =>
      (latitude != 0 || longitude != 0) &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;

  @override
  String toString() => 'NodeFix(${latitude.toStringAsFixed(5)}, '
      '${longitude.toStringAsFixed(5)} ±${accuracyM.round()} m @ $time)';
}
