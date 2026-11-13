// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';
import 'dart:typed_data';

import 'meshcore_frames.dart';
import 'meshcore_presets.dart';

/// Everything Radio Setup can change on a MeshCore companion, as the radio
/// reports it: the advert name, transmit power and radio parameters from
/// SELF_INFO, client repeat from DEVICE_INFO, and every channel slot from
/// GET_CHANNEL. A backup stores one of these; restoring writes it back.
class MeshCoreSettings {
  /// Advert (node) name; empty when unknown.
  final String name;
  final int txPowerDbm;
  final int frequencyKHz;
  final int bandwidthHz;
  final int spreadingFactor;
  final int codingRate;

  /// Client repeat (relaying); null on firmware that doesn't report it.
  final bool? clientRepeat;

  /// Every slot the radio has, by index (unused slots included, so a
  /// restore clears what Radio Setup added).
  final List<MeshCoreChannelInfo> channels;

  /// Board name from DEVICE_INFO ("Seeed Wio Tracker L1"), if known.
  final String? manufacturer;

  /// "v1.18.0", if known.
  final String? firmwareVersion;

  /// The board's GPS power (custom var `gps`, "0"/"1"); null when it has
  /// no such setting or it wasn't read. Node Setup turns a mobile's on
  /// (docs/design/ipad step 5), so a restore puts this back.
  final String? gps;

  MeshCoreSettings({
    required this.name,
    required this.txPowerDbm,
    required this.frequencyKHz,
    required this.bandwidthHz,
    required this.spreadingFactor,
    required this.codingRate,
    required this.clientRepeat,
    required List<MeshCoreChannelInfo> channels,
    this.manufacturer,
    this.firmwareVersion,
    this.gps,
  }) : channels = List.unmodifiable(
            channels.toList()..sort((a, b) => a.index.compareTo(b.index)));

  /// From what a connected radio holds; null until SELF_INFO carried the
  /// radio parameters.
  static MeshCoreSettings? of({
    required MeshCoreSelfInfo? self,
    required MeshCoreDeviceInfo? device,
    required Iterable<MeshCoreChannelInfo> channels,
    String? gps,
  }) {
    if (self == null || !self.hasRadioParams) return null;
    return MeshCoreSettings(
      name: self.name,
      txPowerDbm: self.txPowerDbm,
      frequencyKHz: self.frequencyKHz!,
      bandwidthHz: self.bandwidthHz!,
      spreadingFactor: self.spreadingFactor!,
      codingRate: self.codingRate!,
      clientRepeat: device?.clientRepeat,
      channels: channels.toList(),
      manufacturer: device?.manufacturer,
      firmwareVersion: device?.firmwareVersion,
      gps: gps,
    );
  }

  double get frequencyMHz => frequencyKHz / 1000.0;
  double get bandwidthKHz => bandwidthHz / 1000.0;

  /// "SF7 / 62.5 kHz / 4/5".
  String get paramsLabel {
    final bw = bandwidthKHz;
    final bwText =
        bw == bw.roundToDouble() ? bw.toInt().toString() : bw.toString();
    return 'SF$spreadingFactor / $bwText kHz / 4/$codingRate';
  }

  /// The ladder entry these parameters are ("Fast"), null for a custom
  /// modulation.
  MeshCoreModulation? get modulation => MeshCoreModulations.of(
      bandwidthHz: bandwidthHz,
      spreadingFactor: spreadingFactor,
      codingRate: codingRate);

  /// The community preset these parameters equal ("USA"), if any.
  MeshCorePreset? get community => MeshCorePresets.match(
      frequencyKHz: frequencyKHz,
      bandwidthHz: bandwidthHz,
      spreadingFactor: spreadingFactor,
      codingRate: codingRate);

  /// Slots in use, by index.
  List<MeshCoreChannelInfo> get usedChannels =>
      channels.where((c) => !c.isEmpty).toList();

  /// Same name, power, parameters, repeat flag and channel table.
  bool sameAs(MeshCoreSettings o) {
    if (name != o.name ||
        txPowerDbm != o.txPowerDbm ||
        frequencyKHz != o.frequencyKHz ||
        bandwidthHz != o.bandwidthHz ||
        spreadingFactor != o.spreadingFactor ||
        codingRate != o.codingRate ||
        clientRepeat != o.clientRepeat ||
        gps != o.gps ||
        channels.length != o.channels.length) {
      return false;
    }
    for (var i = 0; i < channels.length; i++) {
      final a = channels[i], b = o.channels[i];
      if (a.index != b.index || a.name != b.name || !_eq(a.secret, b.secret)) {
        return false;
      }
    }
    return true;
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'txPowerDbm': txPowerDbm,
        'frequencyKHz': frequencyKHz,
        'bandwidthHz': bandwidthHz,
        'spreadingFactor': spreadingFactor,
        'codingRate': codingRate,
        'clientRepeat': clientRepeat,
        if (manufacturer != null) 'manufacturer': manufacturer,
        if (firmwareVersion != null) 'firmwareVersion': firmwareVersion,
        if (gps != null) 'gps': gps,
        'channels': [
          for (final c in channels)
            {
              'index': c.index,
              'name': c.name,
              // 16-byte channel secret: a key, like a Meshtastic PSK.
              'secret': base64Encode(c.secret),
            }
        ],
      };

  /// Throws on anything malformed.
  static MeshCoreSettings fromJson(Map<String, dynamic> j) => MeshCoreSettings(
        name: j['name'] as String? ?? '',
        txPowerDbm: j['txPowerDbm'] as int,
        frequencyKHz: j['frequencyKHz'] as int,
        bandwidthHz: j['bandwidthHz'] as int,
        spreadingFactor: j['spreadingFactor'] as int,
        codingRate: j['codingRate'] as int,
        clientRepeat: j['clientRepeat'] as bool?,
        manufacturer: j['manufacturer'] as String?,
        firmwareVersion: j['firmwareVersion'] as String?,
        gps: j['gps'] as String?,
        channels: [
          for (final c in j['channels'] as List)
            MeshCoreChannelInfo(
              Uint8List(0),
              (c as Map<String, dynamic>)['index'] as int,
              c['name'] as String? ?? '',
              Uint8List.fromList(base64Decode(c['secret'] as String)),
            ),
        ],
      );

  static bool _eq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
