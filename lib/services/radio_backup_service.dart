// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';
import 'dart:io';

import 'package:mesh_analyzer/proto/meshtastic/admin.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/apponly.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/channel.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/module_config.pb.dart' as pb;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/radio/mesh_radio.dart';
import '../data/radio/meshcore/meshcore_radio.dart';
import '../data/radio/meshcore/meshcore_settings.dart';
import '../data/radio/meshtastic/meshtastic_admin_keys.dart';
import '../data/radio/meshtastic/meshtastic_radio.dart';
import '../data/radio/switchable_radio.dart';
import 'diag_log.dart';
import '../utils/app_info.dart';

/// Reason strings written by the app.
const backupReasonBeforeSetup = 'Before Radio Setup';
const backupReasonByHand = 'Saved by hand';

/// File extension of new backups (the document type registered in
/// Info.plist). Older `.json` files are still read.
const backupExtension = '.mabackup';

/// "LONG_FAST" to "LongFast".
String prettyEnumName(String name) => name
    .split('_')
    .map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase())
    .join();

/// One row of the "current -> after restore" comparison.
class BackupDiffLine {
  final String label;
  final String from;
  final String to;
  const BackupDiffLine(this.label, this.from, this.to);
  bool get changed => from != to;
}

/// What restoring [target] would change on a radio that currently holds
/// [current]. Both must be of the same protocol.
List<BackupDiffLine> restoreDiff(RadioBackup current, RadioBackup target) {
  if (current is MeshtasticBackup && target is MeshtasticBackup) {
    return _meshtasticDiff(current, target);
  }
  if (current is MeshCoreBackup && target is MeshCoreBackup) {
    return _meshCoreDiff(current, target);
  }
  throw ArgumentError('Backups of different protocols');
}

List<BackupDiffLine> _meshtasticDiff(
    MeshtasticBackup current, MeshtasticBackup target) {
  String rt(MeshtasticBackup b) =>
      b.rangeTest == null ? 'not saved' : (b.rangeTest!.enabled ? 'on' : 'off');
  String tel(MeshtasticBackup b) {
    final t = b.telemetry;
    if (t == null) return 'not saved';
    return t.deviceTelemetryEnabled
        ? 'every ${t.deviceUpdateInterval == 0 ? 'default' : '${t.deviceUpdateInterval}s'}'
        : 'off';
  }

  String relay(MeshtasticBackup b) => b.device == null
      ? 'not saved'
      : prettyEnumName(b.device!.rebroadcastMode.name);
  String role(MeshtasticBackup b) =>
      b.device == null ? 'not saved' : prettyEnumName(b.device!.role.name);
  String lora(MeshtasticBackup b) => '${b.presetLabel} / ${b.lora.region.name}';
  String gps(MeshtasticBackup b) =>
      b.position == null ? 'not saved' : meshtasticGpsLabel(b.position!);
  return [
    if (target.owner != null)
      BackupDiffLine('Name', current.ownerName, target.ownerName),
    BackupDiffLine(
        'Channels', current.channelsDescription, target.channelsDescription),
    BackupDiffLine('Preset / region', lora(current), lora(target)),
    if (target.rangeTest != null)
      BackupDiffLine('Test signal beacon', rt(current), rt(target)),
    if (target.telemetry != null)
      BackupDiffLine('Telemetry beacon', tel(current), tel(target)),
    if (target.device != null)
      BackupDiffLine('Relaying', relay(current), relay(target)),
    if (target.device != null)
      BackupDiffLine('Role', role(current), role(target)),
    if (target.position != null)
      BackupDiffLine('GPS', gps(current), gps(target)),
    if (target.adminKeys != null)
      BackupDiffLine('Admin keys (remote changes)', adminKeyList(current),
          adminKeyList(target)),
  ];
}

/// "none", or the keys' 4-byte prefixes ("1a2b3c4d…, 99aa00bb…").
String adminKeyList(MeshtasticBackup b) {
  final keys = b.adminKeys;
  if (keys == null) return 'not saved';
  if (keys.isEmpty) return 'none';
  return keys.map(keyPrefixHex).join(', ');
}

List<BackupDiffLine> _meshCoreDiff(
    MeshCoreBackup current, MeshCoreBackup target) {
  String relay(MeshCoreBackup b) => switch (b.settings.clientRepeat) {
        null => 'not saved',
        true => 'on',
        false => 'off',
      };
  return [
    if (target.settings.name.isNotEmpty)
      BackupDiffLine('Name', current.ownerName, target.ownerName),
    BackupDiffLine('Frequency', current.frequencyLabel, target.frequencyLabel),
    BackupDiffLine(
        'Range setting', current.modulationLabel, target.modulationLabel),
    BackupDiffLine('Transmit power', '${current.settings.txPowerDbm} dBm',
        '${target.settings.txPowerDbm} dBm'),
    if (target.settings.clientRepeat != null)
      BackupDiffLine('Relaying', relay(current), relay(target)),
    if (target.settings.gps != null)
      BackupDiffLine('GPS', current.settings.gps == '1' ? 'on' : 'off',
          target.settings.gps == '1' ? 'on' : 'off'),
    BackupDiffLine('Channels', current.channelSummary, target.channelSummary),
  ];
}

/// A saved copy of the settings Radio Setup changes on a radio. Restoring
/// writes exactly these back. One subclass per protocol: the saved
/// settings have nothing in common across protocols, only the bookkeeping
/// (which radio, when, why).
abstract class RadioBackup {
  final String path;

  /// Node number: Meshtastic's, or the first 4 bytes of a MeshCore public
  /// key.
  final int nodeNum;
  final String radioName;
  final DateTime savedAt;

  /// Last time the radio was seen with exactly these settings (a save that
  /// finds nothing changed updates this instead of writing a new file).
  final DateTime lastConfirmedAt;
  final String reason;

  /// The first backup for this node: the settings from before the app
  /// touched the radio. Never auto-pruned.
  final bool original;
  final String firmwareVersion;
  final String appVersion;

  /// Set on the result of a save that found nothing changed (not stored).
  final bool unchanged;

  RadioBackup({
    required this.path,
    required this.nodeNum,
    required this.radioName,
    required this.savedAt,
    DateTime? lastConfirmedAt,
    required this.reason,
    this.original = false,
    this.firmwareVersion = '',
    this.appVersion = '',
    this.unchanged = false,
  }) : lastConfirmedAt = lastConfirmedAt ?? savedAt;

  RadioProtocol get protocol;

  RadioBackup copyWith({
    String? path,
    DateTime? lastConfirmedAt,
    bool? original,
    bool? unchanged,
  });

  String get nodeId => '!${nodeNum.toRadixString(16).padLeft(8, '0')}';

  bool get isManual => reason == backupReasonByHand;

  /// One line for a list row: the settings that matter.
  String get summary;

  /// Enabled channel names, comma separated.
  String get channelSummary;

  /// The radio's name as saved, else [radioName].
  String get ownerName;

  /// The name saved on the radio, if the backup has one.
  String? get savedName;

  /// Hardware, already readable ("Tracker T1000 E", "Seeed Wio Tracker L1").
  String? get hardwareLabel;

  /// A link other apps can import (Meshtastic channel URL); null when the
  /// protocol has none.
  String? get channelUrl => null;

  /// True when [other] holds the same settings (bookkeeping aside).
  bool sameSettingsAs(RadioBackup other);

  Map<String, Object?> toJson();

  Map<String, Object?> _commonJson() => {
        'format': 'mesh-analyzer-radio-backup',
        'radio': {'name': radioName, 'nodeNum': nodeNum, 'nodeId': nodeId},
        'savedAt': savedAt.toUtc().toIso8601String(),
        'lastConfirmedAt': lastConfirmedAt.toUtc().toIso8601String(),
        'reason': reason,
        'original': original,
        if (firmwareVersion.isNotEmpty) 'firmwareVersion': firmwareVersion,
        if (appVersion.isNotEmpty) 'appVersion': appVersion,
      };

  /// Reads version 1 to 4 files (1 and 2 are Meshtastic; 3 names its
  /// `protocol`; 4 is Meshtastic with the admin keys). Throws on anything
  /// malformed.
  static RadioBackup fromJson(String path, Map<String, dynamic> j) {
    if (j['format'] != 'mesh-analyzer-radio-backup') {
      throw const FormatException('Not a ${AppInfo.displayName} node backup');
    }
    final version = j['version'];
    if (version is! int || version < 1 || version > 4) {
      throw FormatException('Unsupported backup version: $version');
    }
    final protocol = j['protocol'] as String? ?? 'meshtastic';
    return switch (protocol) {
      'meshtastic' => MeshtasticBackup._fromJson(path, j),
      'meshcore' => MeshCoreBackup._fromJson(path, j),
      _ => throw FormatException('Unknown radio protocol: $protocol'),
    };
  }

  /// The original backup among one node's [backups]: the one flagged
  /// `original`, else (backups from before v2) the oldest "Before Radio
  /// Setup" one.
  static RadioBackup? originalOf(Iterable<RadioBackup> backups) {
    RadioBackup? flagged, legacy;
    for (final b in backups) {
      if (b.original) {
        if (flagged == null || b.savedAt.isBefore(flagged.savedAt)) flagged = b;
      } else if (b.reason == backupReasonBeforeSetup) {
        if (legacy == null || b.savedAt.isBefore(legacy.savedAt)) legacy = b;
      }
    }
    return flagged ?? legacy;
  }

  static bool _eq(List<int>? a, List<int>? b) {
    if (a == null || b == null) return a == null && b == null;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A Meshtastic radio's channel table, LoRa settings, Range Test and
/// telemetry modules, device config and owner, as protobuf bytes.
class MeshtasticBackup extends RadioBackup {
  final List<pb.Channel> channels;
  final pb.Config_LoRaConfig lora;
  final pb.ModuleConfig_RangeTestConfig? rangeTest;

  /// The radio's names (absent in backups made before renaming existed).
  final pb.User? owner;

  /// Telemetry module and device config (rebroadcast mode): Radio Setup
  /// changes both for the beacon, so Restore writes them back.
  final pb.ModuleConfig_TelemetryConfig? telemetry;
  final pb.Config_DeviceConfig? device;

  /// Position config: Node Setup switches a mobile node's GPS on and makes
  /// it update every 30 s (docs/design/ipad step 5), so Restore writes
  /// it back. Null in older files.
  final pb.Config_PositionConfig? position;

  /// `security.admin_key`: the public keys allowed to change this radio
  /// from a distance (file version 4; null in older files, or when the
  /// radio didn't report its security settings). Radio Setup can add the
  /// mobile radio's key to a base, so Restore writes this list back. Only
  /// the admin list is kept: never the radio's private key.
  final List<List<int>>? adminKeys;

  MeshtasticBackup({
    required super.path,
    required super.nodeNum,
    required super.radioName,
    required super.savedAt,
    super.lastConfirmedAt,
    required super.reason,
    required this.channels,
    required this.lora,
    required this.rangeTest,
    this.owner,
    super.original,
    super.firmwareVersion,
    super.appVersion,
    this.telemetry,
    this.device,
    this.position,
    this.adminKeys,
    super.unchanged,
  });

  @override
  RadioProtocol get protocol => RadioProtocol.meshtastic;

  @override
  MeshtasticBackup copyWith({
    String? path,
    DateTime? lastConfirmedAt,
    bool? original,
    bool? unchanged,
  }) =>
      MeshtasticBackup(
        path: path ?? this.path,
        nodeNum: nodeNum,
        radioName: radioName,
        savedAt: savedAt,
        lastConfirmedAt: lastConfirmedAt ?? this.lastConfirmedAt,
        reason: reason,
        channels: channels,
        lora: lora,
        rangeTest: rangeTest,
        owner: owner,
        original: original ?? this.original,
        firmwareVersion: firmwareVersion,
        appVersion: appVersion,
        telemetry: telemetry,
        device: device,
        position: position,
        adminKeys: adminKeys,
        unchanged: unchanged ?? this.unchanged,
      );

  /// Enabled channels, primary first.
  List<pb.Channel> get activeChannels =>
      channels.where((c) => c.role != pb.Channel_Role.DISABLED).toList()
        ..sort((a, b) => a.index.compareTo(b.index));

  @override
  String get channelSummary => activeChannels
      .map((c) => c.settings.name.isEmpty ? '(default)' : c.settings.name)
      .join(', ');

  String get presetName => lora.usePreset ? lora.modemPreset.name : 'CUSTOM';

  /// "LongFast", "MediumFast", "Custom".
  String get presetLabel =>
      lora.usePreset ? prettyEnumName(lora.modemPreset.name) : 'Custom';

  /// Enabled channel names; an unnamed channel is shown under the name the
  /// firmware gives it (the preset's).
  List<String> get channelNames => [
        for (final c in activeChannels)
          c.settings.name.isEmpty ? presetLabel : c.settings.name,
      ];

  /// "LongFast · 2 channels (LongFast, Friends)".
  @override
  String get summary {
    final n = activeChannels.length;
    return '$presetLabel · $n ${n == 1 ? 'channel' : 'channels'} '
        '(${channelNames.join(', ')})';
  }

  /// Like [channelNames] joined, with a public primary called out.
  String get channelsDescription {
    final names = channelNames;
    if (names.isEmpty) return 'none';
    if (primaryIsPublic) names[0] = 'public ${names[0]}';
    return names.join(', ');
  }

  @override
  String get ownerName =>
      owner?.longName.isNotEmpty == true ? owner!.longName : radioName;

  @override
  String? get savedName =>
      owner?.longName.isNotEmpty == true ? owner!.longName : null;

  /// Hardware model if the backup knows it ("TRACKER_T1000_E").
  String? get hardwareModel {
    final m = owner?.hwModel;
    if (m == null || m == pb.HardwareModel.UNSET) return null;
    return m.name;
  }

  @override
  String? get hardwareLabel {
    final m = hardwareModel;
    return m == null ? null : prettyEnumName(m);
  }

  /// Whether the primary channel uses a well-known (public) key.
  bool get primaryIsPublic {
    final a = activeChannels;
    return a.isNotEmpty && MeshtasticRadio.isPublicPsk(a.first.settings.psk);
  }

  /// True when [other] holds the same channels, LoRa, Range Test, telemetry,
  /// device config and owner (compared as protobuf bytes).
  @override
  bool sameSettingsAs(RadioBackup other) {
    if (other is! MeshtasticBackup) return false;
    if (channels.length != other.channels.length) return false;
    for (var i = 0; i < channels.length; i++) {
      if (!RadioBackup._eq(
          channels[i].writeToBuffer(), other.channels[i].writeToBuffer())) {
        return false;
      }
    }
    return RadioBackup._eq(lora.writeToBuffer(), other.lora.writeToBuffer()) &&
        RadioBackup._eq(
            rangeTest?.writeToBuffer(), other.rangeTest?.writeToBuffer()) &&
        RadioBackup._eq(
            telemetry?.writeToBuffer(), other.telemetry?.writeToBuffer()) &&
        RadioBackup._eq(
            device?.writeToBuffer(), other.device?.writeToBuffer()) &&
        RadioBackup._eq(
            position?.writeToBuffer(), other.position?.writeToBuffer()) &&
        RadioBackup._eq(owner?.writeToBuffer(), other.owner?.writeToBuffer()) &&
        _sameAdminKeys(adminKeys, other.adminKeys);
  }

  static bool _sameAdminKeys(List<List<int>>? a, List<List<int>>? b) {
    if (a == null || b == null) return a == null && b == null;
    return sameKeyList(a, b);
  }

  /// Standard Meshtastic channel link (channels + LoRa settings). The
  /// official app and coachella-mesh can import it. Contains the channel
  /// keys — share it only with people who should be on those channels.
  @override
  String get channelUrl {
    final set = pb.ChannelSet(
      settings: activeChannels.map((c) => c.settings),
      loraConfig: lora,
    );
    final b64 = base64Url.encode(set.writeToBuffer()).replaceAll('=', '');
    return 'https://meshtastic.org/e/#$b64';
  }

  @override
  Map<String, Object?> toJson() => {
        ..._commonJson(),
        // 4 once the admin keys are saved (older app versions refuse the
        // file rather than restore it without them); else 2, so versions
        // from before MeshCore still read it.
        'version': adminKeys != null ? 4 : 2,
        'protocol': 'meshtastic',
        // Human-readable summary (not used for restore).
        'summary': {
          'region': lora.region.name,
          'preset': presetName,
          'channels': channelSummary,
          'rangeTest': rangeTest == null
              ? null
              : {
                  'enabled': rangeTest!.enabled,
                  'senderSecs': rangeTest!.sender
                },
          if (owner != null)
            'name': {'long': owner!.longName, 'short': owner!.shortName},
        },
        'channelUrl': channelUrl,
        // Exact protobuf bytes, base64 — these are what restore writes back.
        'protobuf': {
          'channels': [
            for (final c in channels) base64Encode(c.writeToBuffer())
          ],
          'lora': base64Encode(lora.writeToBuffer()),
          if (rangeTest != null)
            'rangeTest': base64Encode(rangeTest!.writeToBuffer()),
          if (owner != null) 'owner': base64Encode(owner!.writeToBuffer()),
          if (telemetry != null)
            'telemetry': base64Encode(telemetry!.writeToBuffer()),
          if (device != null) 'device': base64Encode(device!.writeToBuffer()),
          if (position != null)
            'position': base64Encode(position!.writeToBuffer()),
          if (adminKeys != null)
            'adminKeys': [for (final k in adminKeys!) base64Encode(k)],
        },
      };

  static MeshtasticBackup _fromJson(String path, Map<String, dynamic> j) {
    final radio = j['radio'] as Map<String, dynamic>;
    final proto = j['protobuf'] as Map<String, dynamic>;
    final rt = proto['rangeTest'] as String?;
    final owner = proto['owner'] as String?;
    final tel = proto['telemetry'] as String?;
    final dev = proto['device'] as String?;
    final pos = proto['position'] as String?;
    final admin = proto['adminKeys'] as List?;
    final channels = [
      for (final c in proto['channels'] as List)
        pb.Channel.fromBuffer(base64Decode(c as String)),
    ];
    if (channels.isEmpty) throw const FormatException('Backup has no channels');
    final savedAt = DateTime.parse(j['savedAt'] as String);
    final confirmed = j['lastConfirmedAt'] as String?;
    return MeshtasticBackup(
      path: path,
      nodeNum: radio['nodeNum'] as int,
      radioName: radio['name'] as String? ?? '',
      savedAt: savedAt,
      lastConfirmedAt: confirmed == null ? null : DateTime.parse(confirmed),
      reason: j['reason'] as String? ?? '',
      original: j['original'] as bool? ?? false,
      firmwareVersion: j['firmwareVersion'] as String? ?? '',
      appVersion: j['appVersion'] as String? ?? '',
      channels: channels,
      lora: pb.Config_LoRaConfig.fromBuffer(
          base64Decode(proto['lora'] as String)),
      rangeTest: rt == null
          ? null
          : pb.ModuleConfig_RangeTestConfig.fromBuffer(base64Decode(rt)),
      owner: owner == null ? null : pb.User.fromBuffer(base64Decode(owner)),
      telemetry: tel == null
          ? null
          : pb.ModuleConfig_TelemetryConfig.fromBuffer(base64Decode(tel)),
      device: dev == null
          ? null
          : pb.Config_DeviceConfig.fromBuffer(base64Decode(dev)),
      position: pos == null
          ? null
          : pb.Config_PositionConfig.fromBuffer(base64Decode(pos)),
      adminKeys: admin == null
          ? null
          : [
              for (final k in admin) _adminKey(base64Decode(k as String)),
            ],
    );
  }

  static List<int> _adminKey(List<int> k) {
    if (k.length != 32) {
      throw FormatException('Admin key of ${k.length} bytes, not 32');
    }
    return k;
  }
}

/// A MeshCore companion's name, transmit power, radio parameters, client
/// repeat flag and channel table ([MeshCoreSettings]). Version 3 file.
class MeshCoreBackup extends RadioBackup {
  final MeshCoreSettings settings;

  MeshCoreBackup({
    required super.path,
    required super.nodeNum,
    required super.radioName,
    required super.savedAt,
    super.lastConfirmedAt,
    required super.reason,
    required this.settings,
    super.original,
    super.firmwareVersion,
    super.appVersion,
    super.unchanged,
  });

  @override
  RadioProtocol get protocol => RadioProtocol.meshcore;

  @override
  MeshCoreBackup copyWith({
    String? path,
    DateTime? lastConfirmedAt,
    bool? original,
    bool? unchanged,
  }) =>
      MeshCoreBackup(
        path: path ?? this.path,
        nodeNum: nodeNum,
        radioName: radioName,
        savedAt: savedAt,
        lastConfirmedAt: lastConfirmedAt ?? this.lastConfirmedAt,
        reason: reason,
        settings: settings,
        original: original ?? this.original,
        firmwareVersion: firmwareVersion,
        appVersion: appVersion,
        unchanged: unchanged ?? this.unchanged,
      );

  /// "918.000 MHz", with the community preset it equals ("910.525 MHz,
  /// USA").
  String get frequencyLabel {
    final c = settings.community;
    return '${formatFrequencyMHz(settings.frequencyMHz)} MHz'
        '${c == null ? '' : ', ${c.title}'}';
  }

  /// "Fast (SF7 / 62.5 kHz / 4/5)", or the bare parameters when custom.
  String get modulationLabel {
    final params = settings.paramsLabel;
    final m = settings.modulation;
    return m == null ? 'Custom ($params)' : '${m.name} ($params)';
  }

  @override
  String get channelSummary {
    final names = settings.usedChannels.map((c) => c.name).toList();
    return names.isEmpty ? 'none' : names.join(', ');
  }

  /// "Fast · 910.525 MHz, USA · 22 dBm · 2 channels (Public, Friends)".
  @override
  String get summary {
    final used = settings.usedChannels;
    final n = used.length;
    return '${settings.modulation?.name ?? 'Custom'} · $frequencyLabel · '
        '${settings.txPowerDbm} dBm · $n ${n == 1 ? 'channel' : 'channels'}'
        '${n == 0 ? '' : ' ($channelSummary)'}';
  }

  @override
  String get ownerName => settings.name.isNotEmpty ? settings.name : radioName;

  @override
  String? get savedName => settings.name.isNotEmpty ? settings.name : null;

  @override
  String? get hardwareLabel => settings.manufacturer;

  @override
  bool sameSettingsAs(RadioBackup other) =>
      other is MeshCoreBackup && settings.sameAs(other.settings);

  @override
  Map<String, Object?> toJson() => {
        ..._commonJson(),
        'version': 3,
        'protocol': 'meshcore',
        // Human-readable summary (not used for restore).
        'summary': {
          'frequencyMHz': settings.frequencyMHz,
          'modulation': settings.modulation?.name ?? 'CUSTOM',
          'community': settings.community?.title,
          'txPowerDbm': settings.txPowerDbm,
          'clientRepeat': settings.clientRepeat,
          'channels': channelSummary,
          'name': settings.name,
        },
        // What restore writes back (includes the channel secrets).
        'meshcore': settings.toJson(),
      };

  static MeshCoreBackup _fromJson(String path, Map<String, dynamic> j) {
    final radio = j['radio'] as Map<String, dynamic>;
    final savedAt = DateTime.parse(j['savedAt'] as String);
    final confirmed = j['lastConfirmedAt'] as String?;
    return MeshCoreBackup(
      path: path,
      nodeNum: radio['nodeNum'] as int,
      radioName: radio['name'] as String? ?? '',
      savedAt: savedAt,
      lastConfirmedAt: confirmed == null ? null : DateTime.parse(confirmed),
      reason: j['reason'] as String? ?? '',
      original: j['original'] as bool? ?? false,
      firmwareVersion: j['firmwareVersion'] as String? ?? '',
      appVersion: j['appVersion'] as String? ?? '',
      settings:
          MeshCoreSettings.fromJson(j['meshcore'] as Map<String, dynamic>),
    );
  }
}

/// Saves radio settings to files in the app's Documents folder
/// (`radio_backups/`), lists them, and restores them over Bluetooth.
///
/// Each save is compared with the newest backup of the same node: if
/// nothing changed, that file's `lastConfirmedAt` is updated instead of
/// writing a copy. After a save, old files are pruned per node (see
/// [prune]).
class RadioBackupService {
  /// [directory] overrides the storage folder (tests).
  RadioBackupService({Directory? directory}) : _override = directory;

  final Directory? _override;

  /// Manual saves kept per node, besides the original.
  static const keepManual = 5;

  /// Whether [radio] is one the service can back up and restore (a
  /// Meshtastic or MeshCore radio, possibly inside a switchable one).
  static bool supports(MeshRadio? radio) =>
      radioAs<MeshtasticRadio>(radio) != null ||
      radioAs<MeshCoreRadio>(radio) != null;

  Future<Directory> _dir() async {
    if (_override != null) {
      if (!await _override.exists()) await _override.create(recursive: true);
      return _override;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'radio_backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Save [radio]'s current settings.
  Future<RadioBackup> save(MeshRadio radio, {required String reason}) async =>
      store(await snapshot(radio, reason: reason));

  /// [radio]'s current settings as an unsaved backup (also the "current"
  /// side of a restore diff). Throws when the radio is of a protocol
  /// without backups or its settings haven't been read yet.
  Future<RadioBackup> snapshot(MeshRadio radio, {String reason = ''}) async {
    final meshtastic = radioAs<MeshtasticRadio>(radio);
    if (meshtastic != null) return _snapshotMeshtastic(meshtastic, reason);
    final meshcore = radioAs<MeshCoreRadio>(radio);
    if (meshcore != null) return _snapshotMeshCore(meshcore, reason);
    throw StateError('Backups need a Meshtastic or MeshCore node');
  }

  Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return '';
    }
  }

  Future<MeshtasticBackup> _snapshotMeshtastic(
      MeshtasticRadio radio, String reason) async {
    final lora = radio.loraConfig;
    final node = radio.myNodeNum;
    if (lora == null || node == null || radio.channels.isEmpty) {
      throw StateError("The node's settings haven't been read yet");
    }
    final rangeTest =
        radio.moduleConfigs[pb.ModuleConfig_PayloadVariant.rangeTest];
    final telemetry =
        radio.moduleConfigs[pb.ModuleConfig_PayloadVariant.telemetry];
    final device = radio.configs[pb.Config_PayloadVariant.device];
    final position = radio.configs[pb.Config_PayloadVariant.position];
    return MeshtasticBackup(
      path: '',
      nodeNum: node,
      radioName: radio.displayName,
      savedAt: DateTime.now().toUtc(),
      reason: reason,
      firmwareVersion: radio.metadata?.firmwareVersion ?? '',
      appVersion: await _appVersion(),
      channels: [
        for (var i = 0; i < 8; i++)
          radio.channels[i]?.deepCopy() ??
              pb.Channel(index: i, role: pb.Channel_Role.DISABLED),
      ],
      lora: lora.deepCopy(),
      rangeTest: rangeTest?.hasRangeTest() == true
          ? rangeTest!.rangeTest.deepCopy()
          : null,
      owner: radio.nodeInfos[node]?.hasUser() == true
          ? radio.nodeInfos[node]!.user.deepCopy()
          : null,
      telemetry: telemetry?.hasTelemetry() == true
          ? telemetry!.telemetry.deepCopy()
          : null,
      device: device?.hasDevice() == true ? device!.device.deepCopy() : null,
      position: position?.hasPosition() == true
          ? position!.position.deepCopy()
          : null,
      adminKeys: radio.downloadedAdminKeys,
    );
  }

  Future<MeshCoreBackup> _snapshotMeshCore(
      MeshCoreRadio radio, String reason) async {
    try {
      await radio.readCustomVars(); // the GPS switch, where there is one
    } catch (e) {
      DiagLog.instance.log('backup', 'custom vars not read: $e');
    }
    final settings = radio.settings;
    final node = radio.myNodeId;
    if (settings == null || node == null) {
      throw StateError("The node's settings haven't been read yet");
    }
    return MeshCoreBackup(
      path: '',
      nodeNum: node,
      radioName: radio.displayName,
      savedAt: DateTime.now().toUtc(),
      reason: reason,
      firmwareVersion: settings.firmwareVersion ?? '',
      appVersion: await _appVersion(),
      settings: settings,
    );
  }

  /// Write [candidate] (path ignored) as a new file, unless the newest
  /// backup of the same node holds identical settings, in which case that
  /// file's `lastConfirmedAt` is updated and it is returned with
  /// `unchanged` set. Marks `original` when the node has no earlier backup.
  /// Prunes afterwards.
  Future<RadioBackup> store(RadioBackup candidate) async {
    final dir = await _dir();
    final existing =
        (await list()).where((b) => b.nodeNum == candidate.nodeNum).toList();
    if (existing.isNotEmpty && existing.first.sameSettingsAs(candidate)) {
      final newest = existing.first;
      final updated = newest.copyWith(
        lastConfirmedAt: candidate.savedAt.isAfter(newest.lastConfirmedAt)
            ? candidate.savedAt
            : newest.lastConfirmedAt,
        unchanged: true,
      );
      await _write(updated);
      return updated;
    }
    final stamp =
        '${candidate.savedAt.toUtc().toIso8601String().replaceAll(':', '-').split('.').first}Z';
    var file = File(p.join(dir.path,
        '${candidate.nodeNum.toRadixString(16).padLeft(8, '0')}_$stamp$backupExtension'));
    for (var n = 2; await file.exists(); n++) {
      file = File(p.join(dir.path,
          '${candidate.nodeNum.toRadixString(16).padLeft(8, '0')}_${stamp}_$n$backupExtension'));
    }
    final backup = candidate.copyWith(
      path: file.path,
      original: existing.isEmpty,
    );
    await _write(backup);
    await prune(candidate.nodeNum);
    return backup;
  }

  Future<void> _write(RadioBackup b) => File(b.path)
      .writeAsString(const JsonEncoder.withIndent('  ').convert(b.toJson()));

  /// Add a backup file from outside (AirDrop, Files). Throws a
  /// [FormatException] unless it is a valid radio backup.
  Future<RadioBackup> import(File file) async {
    final Object? j;
    try {
      j = jsonDecode(await file.readAsString());
    } catch (_) {
      throw const FormatException('Not a ${AppInfo.displayName} node backup');
    }
    if (j is! Map<String, dynamic>) {
      throw const FormatException('Not a ${AppInfo.displayName} node backup');
    }
    final RadioBackup parsed;
    try {
      parsed = RadioBackup.fromJson(file.path, j);
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Damaged backup file ($e)');
    }
    // Only the first backup of a node may claim to be the original.
    return store(parsed);
  }

  /// Delete old backups of [nodeNum]: keeps the original, the
  /// [keepManual] newest "Saved by hand" and the newest automatic one.
  Future<void> prune(int nodeNum) async {
    final mine = (await list()).where((b) => b.nodeNum == nodeNum).toList();
    final original = RadioBackup.originalOf(mine);
    final keep = <String>{if (original != null) original.path};
    final rest = mine.where((b) => b.path != original?.path).toList();
    keep.addAll(
        rest.where((b) => b.isManual).take(keepManual).map((b) => b.path));
    final auto = rest.where((b) => !b.isManual).toList();
    if (auto.isNotEmpty) keep.add(auto.first.path);
    for (final b in mine) {
      if (!keep.contains(b.path)) {
        try {
          await File(b.path).delete();
        } catch (e) {
          print('RadioBackupService: could not prune ${b.path}: $e');
        }
      }
    }
  }

  /// All backups, newest first.
  Future<List<RadioBackup>> list() async {
    final dir = await _dir();
    final backups = <RadioBackup>[];
    await for (final f in dir.list()) {
      if (f is! File ||
          !(f.path.endsWith(backupExtension) || f.path.endsWith('.json'))) {
        continue;
      }
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        backups.add(RadioBackup.fromJson(f.path, j));
      } catch (e) {
        print('RadioBackupService: skipping ${f.path}: $e');
      }
    }
    backups.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return backups;
  }

  Future<void> delete(RadioBackup backup) => File(backup.path).delete();

  /// Write [backup] back to [radio] (must be the same radio). A Meshtastic
  /// radio reboots; a MeshCore radio takes the settings at once.
  ///
  /// Meshtastic admin keys: a backup with them puts that exact list back.
  /// One from before they were saved leaves the list as it is, minus
  /// [removeAdminKeys] (the mobile radio's key, when Radio Setup gave it to
  /// this base). The result says what the list is afterwards.
  Future<RestoreOutcome> restore(
    MeshRadio radio,
    RadioBackup backup, {
    required void Function(String step) onStep,
    List<List<int>> removeAdminKeys = const [],
  }) async {
    if (!radio.isReady) throw StateError('Connect to the node first');
    if (radio.myNodeId != backup.nodeNum) {
      throw StateError(
          'This backup is from ${backup.radioName} (${backup.nodeId})');
    }
    final meshtastic = radioAs<MeshtasticRadio>(radio);
    final meshcore = radioAs<MeshCoreRadio>(radio);
    if (backup is MeshtasticBackup && meshtastic != null) {
      return _restoreMeshtastic(meshtastic, backup, onStep, removeAdminKeys);
    } else if (backup is MeshCoreBackup && meshcore != null) {
      await meshcore.applySettings(backup.settings, onStep: onStep);
      onStep('Done');
      return const RestoreOutcome();
    } else {
      throw StateError('This backup is for a '
          '${backup.protocol == RadioProtocol.meshcore ? 'MeshCore' : 'Meshtastic'}'
          ' node');
    }
  }

  Future<RestoreOutcome> _restoreMeshtastic(
    MeshtasticRadio radio,
    MeshtasticBackup backup,
    void Function(String step) onStep,
    List<List<int>> removeAdminKeys,
  ) async {
    // Read before the edit begins (the transaction holds only writes).
    pb.Config? security;
    List<List<int>>? keysAfter;
    String? adminKeyProblem;
    final wanted = backup.adminKeys;
    if (wanted != null || removeAdminKeys.isNotEmpty) {
      try {
        (security, keysAfter) = await radio.securityWithAdminKeys((current) => [
              for (final k in wanted ?? current)
                if (wanted != null ||
                    !removeAdminKeys.any((r) => sameKey(r, k)))
                  List<int>.of(k),
            ]);
      } catch (e) {
        keysAfter = null;
        adminKeyProblem = 'The admin keys could not be restored: '
            '${e is StateError ? e.message : e}';
        onStep(adminKeyProblem);
        DiagLog.instance.log('admin', 'restore: admin keys skipped: $e');
      }
    }
    onStep('Restoring channels (${backup.channelSummary})…');
    await radio.sendAdmin(pb.AdminMessage(beginEditSettings: true));
    for (final c in backup.channels) {
      await radio.sendAdmin(pb.AdminMessage(setChannel: c));
    }
    onStep('Restoring ${backup.presetName} / ${backup.lora.region.name}…');
    await radio
        .sendAdmin(pb.AdminMessage(setConfig: pb.Config(lora: backup.lora)));
    if (backup.rangeTest != null) {
      onStep('Restoring the test signal beacon…');
      await radio.sendAdmin(pb.AdminMessage(
        setModuleConfig: pb.ModuleConfig(rangeTest: backup.rangeTest),
      ));
    }
    if (backup.telemetry != null) {
      onStep('Restoring the telemetry settings…');
      await radio.sendAdmin(pb.AdminMessage(
        setModuleConfig: pb.ModuleConfig(telemetry: backup.telemetry),
      ));
    }
    if (backup.device != null) {
      onStep('Restoring the relay mode…');
      await radio.sendAdmin(
          pb.AdminMessage(setConfig: pb.Config(device: backup.device)));
    }
    if (backup.position != null) {
      onStep('Restoring the GPS settings…');
      await radio.sendAdmin(
          pb.AdminMessage(setConfig: pb.Config(position: backup.position)));
    }
    if (backup.owner != null) {
      onStep('Restoring name "${backup.owner!.longName}"…');
      await radio.sendAdmin(pb.AdminMessage(setOwner: backup.owner));
    }
    if (security != null) {
      onStep(keysAfter!.isEmpty
          ? 'Removing every admin key: no other node can change this one '
              'from a distance…'
          : 'Restoring the admin keys (${keysAfter.length})…');
      await radio.sendAdmin(pb.AdminMessage(setConfig: security));
    }
    onStep('Saving — the node restarts…');
    await radio.commitSettings();
    if (security != null) {
      radio.configs[pb.Config_PayloadVariant.security] = security;
    }
    onStep('Done');
    return RestoreOutcome(
        adminKeys: keysAfter, adminKeyProblem: adminKeyProblem);
  }
}

/// What a restore did beyond the settings it wrote.
class RestoreOutcome {
  /// The radio's admin-key list after the restore, or null when it was
  /// not touched (MeshCore, a backup without the list and nothing to
  /// remove, or a problem: see [adminKeyProblem]).
  final List<List<int>>? adminKeys;

  /// Why the admin keys were left as they were, for the step list.
  final String? adminKeyProblem;

  const RestoreOutcome({this.adminKeys, this.adminKeyProblem});

  /// The restore left [key] out of the admin list.
  bool removed(List<int> key) =>
      adminKeys != null && !adminKeys!.any((k) => sameKey(k, key));
}
