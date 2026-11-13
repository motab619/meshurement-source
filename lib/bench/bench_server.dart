// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/radio/ble/ble_transport.dart';
import '../data/radio/ble/radio_services.dart';
import '../data/radio/mesh_radio.dart';
import '../data/radio/meshcore/meshcore_presets.dart';
import '../data/radio/meshcore/meshcore_radio.dart';
import '../data/radio/meshcore/meshcore_settings.dart';
import '../data/radio/meshtastic/meshtastic_contacts.dart';
import '../data/radio/meshtastic/meshtastic_presets.dart';
import '../data/radio/switchable_radio.dart';
import '../demo/demo_mode.dart';
import '../providers.dart';
import '../services/csv_export_service.dart';
import '../services/diag_log.dart';
import '../services/radio_backup_service.dart';
import '../services/radio_roles.dart';
import '../ui/protocol_text.dart';
import '../utils/app_info.dart';
import 'bench_mode.dart';

/// Reads a provider; the server lives outside the widget tree.
typedef Reader = T Function<T>(ProviderListenable<T> provider);

/// The phone side of the bench (`tool/bench/bench/app.py` is the Mac side).
///
/// HTTP on 127.0.0.1:[BenchMode.port], JSON everywhere:
///
///   GET  /state                   app, radio, roles, session, range, beacon, gps
///   GET  /events?since=N[&wait=S] events after sequence N (long-poll ≤ S s, 20)
///   POST /cmd  {"cmd": "...", "args": {...}}  → {"ok": true, "value": ...}
///                                             or {"ok": false, "error": "..."}
///
/// Commands drive the same services the UI does ([RadioProfileService],
/// [SessionManager], [GpsService], [RadioBackupService],
/// [CsvExportService]...), so a bench run exercises the whole stack below
/// the widgets: BLE, protocol, firmware, database. Events carry link
/// state, range state, ping outcomes, beacon presence, Radio Setup and
/// restore steps and every [DiagLog] line. Only built with
/// `--dart-define=BENCH=true`.
///
/// Commands (args in braces; `[runCommand]` lists them all):
///
///   ping                              → "pong"
///   prefs.get {key} / prefs.set {key, value|null}
///   gps.set {lat, lon, alt?}          the bench's position (no real GPS)
///   radio.scan {seconds?}             BLE scan → [{id, name, protocol, rssi}]
///   radio.state                       same as /state.radio
///   radio.connect {id, name?, protocol?, timeoutSec?}
///   radio.reconnect {id?, name?, protocol?, timeoutSec?}
///                                     disconnect + connect (default: the
///                                     current radio, else the mobile role)
///   radio.disconnect / radio.queryDevice
///   radio.setupBase {id, name, protocol?, preset?, beaconSecs?, rename?,
///                    allowRemoteChanges?}             Radio Setup, base flow
///   radio.setupConnected {role?, preset?, beaconSecs?, rename?}
///   radio.switchToAndApplyMobile {id, name, protocol?, preset?, rename?}
///   map.create {name?, baseLat?, baseLon?, baseNodeId?} → map id
///   session.start {mapId, baseNodeId?, name?, pingIntervalSec?} → session id
///   session.end
///   beacon.state                      same as /state.beacon
///   backups.list                      every radio backup, newest first
///   backups.restoreOriginal {nodeNum?} "Put this radio back the way it
///                                     was" on the connected radio
///   export.session {sessionId, format?} → the export text
///                                     (csvV2 | meshtasticCsv | geoJson | kml)
///   export.mapsJson {mapId?}          → the maps.json text
///   export.all                        → path of the zip written on the phone
///   db.query {sql}                    read-only SELECT → rows
///   radio.settings                    the connected MeshCore radio's settings
///   radio.snapshot                    either protocol's settings (what a backup holds)
///   radio.setRemoteLora {nodeNum?, preset?, txPower?}
///                                     change the base over the mesh (session passkey)
///
/// MeshCore radios (a `companion_radio_ble` build is silent on USB) are
/// verified from this side: `radio.snapshot` / `radio.settings` return what
/// the radio reported over BLE after Radio Setup wrote it. The Radio Setup
/// commands take `preset` as a Meshtastic modem preset id (`MEDIUM_FAST`)
/// or a MeshCore ladder id (`MC_SF7_BW62.5_CR5`), plus `frequencyMHz` /
/// `txPowerDbm` (MeshCore; the frequency defaults like the Radio Setup
/// screen: the base's recorded test frequency, else the connected radio's
/// band's client-repeat frequency).
class BenchServer {
  BenchServer(this._read);

  /// The step `MeshtasticRadio.setRemoteLora` reports when the commit got
  /// no ACK (the node's reboot often eats it; the two writes before were
  /// acknowledged, so the change is in). Same text the guided runner keys on.
  static const unconfirmedSaveStep = 'did not confirm the save';

  final Reader _read;
  HttpServer? _server;
  final _events = <Map<String, Object?>>[];
  var _seq = 0;
  final _subs = <StreamSubscription<Object?>>[];
  Completer<void>? _wake;
  void Function()? _unlistenLog;
  bool _hooked = false;

  /// Events emitted so far (oldest first; the list is trimmed at 5000).
  List<Map<String, Object?>> get events => List.unmodifiable(_events);

  Future<void> start() async {
    if (!BenchMode.build || !BenchMode.enabled) return;
    hook();
    try {
      _server =
          await HttpServer.bind(InternetAddress.loopbackIPv4, BenchMode.port);
    } on SocketException catch (e) {
      // On the simulator the loopback is the Mac's: a stale iproxy / adb
      // forward on the same port takes it first. `-benchPort N` moves us.
      final msg = 'bench server could not bind 127.0.0.1:${BenchMode.port}: '
          '${e.osError?.message ?? e.message}';
      _log(msg);
      print(msg);
      return;
    }
    _server!.listen(_handle, onError: (Object e) => _log('http error $e'));
    _log('bench server on 127.0.0.1:${BenchMode.port}');
  }

  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _hooked = false;
    _unlistenLog?.call();
    _unlistenLog = null;
    await _server?.close(force: true);
  }

  // -- events --------------------------------------------------------------

  void emit(String type, [Map<String, Object?> data = const {}]) {
    _seq++;
    _events.add({
      'seq': _seq,
      't': DateTime.now().toIso8601String(),
      'type': type,
      ...data,
    });
    if (_events.length > 5000) _events.removeRange(0, 1000);
    _wake?.complete();
    _wake = null;
  }

  void _log(String msg) => DiagLog.instance.log('bench', msg);

  /// Subscribe to the app's streams ([start] does this; tests call it
  /// directly). Safe to call twice.
  @visibleForTesting
  void hook() {
    if (_hooked) return;
    _hooked = true;
    final radio = _read(meshRadioProvider);
    _subs.add(radio.connectionState.listen((s) => emit('link', {
          'state': s.name,
          'radio': radio.displayName,
          'nodeId': radio.myNodeId,
        })));
    _subs.add(radio.connectProgressStream.listen((p) {
      if (p != null) emit('connect', {'state': p.state.name, 'step': p.step});
    }));
    _subs.add(_read(sessionManagerProvider).sessionStream.listen((s) => emit(
        'session', {'id': s?.id, 'active': s != null && s.endedAt == null})));
    _subs.add(_read(outOfRangeMonitorProvider)
        .stateStream
        .listen((s) => emit('range', {'state': s.name})));
    _subs.add(_read(activeProbeServiceProvider).outcomes.listen((p) => emit(
        'ping', {
          'status': p.status,
          'snr': p.snr,
          'rssi': p.rssi,
          'uplinkSnr': p.uplinkSnr,
          'fromBase': p.fromBase,
          'hops': p.hops,
          'ms': p.answeredAt.difference(p.sentAt).inMilliseconds,
        })));
    // The base is heard but its beacon is not (BeaconTracker.absent).
    _subs.add(_read(packetProcessorProvider)
        .beacons
        .absentStream
        .listen((absent) => emit('beacon', {'absent': absent})));
    final log = DiagLog.instance.recent;
    var seen = log.value.length;
    void onLog() {
      final lines = log.value;
      // `recent` keeps the newest 60 lines; new ones are appended.
      final start = lines.length >= seen ? seen : 0;
      for (final l in lines.skip(start)) {
        emit('log', {'line': l});
      }
      seen = lines.length;
    }
    log.addListener(onLog);
    _unlistenLog = () => log.removeListener(onLog);
  }

  // -- http ----------------------------------------------------------------

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.contentType = ContentType.json;
    try {
      Object? body;
      switch ((req.method, req.uri.path)) {
        case ('GET', '/state'):
          body = state();
        case ('GET', '/events'):
          final since = int.tryParse(req.uri.queryParameters['since'] ?? '') ?? 0;
          final wait = int.tryParse(req.uri.queryParameters['wait'] ?? '') ?? 20;
          body = await _eventsSince(since, Duration(seconds: wait.clamp(0, 20)));
        case ('POST', '/cmd'):
          final text = await utf8.decoder.bind(req).join();
          final m = jsonDecode(text) as Map<String, dynamic>;
          final args = (m['args'] as Map<String, dynamic>?) ?? const {};
          try {
            final value = await runCommand(m['cmd'] as String, args);
            body = {'ok': true, 'value': value};
          } catch (e, st) {
            _log('cmd ${m['cmd']} failed: $e');
            body = {'ok': false, 'error': '$e', 'stack': '$st'};
          }
        default:
          res.statusCode = HttpStatus.notFound;
          body = {'error': 'no ${req.method} ${req.uri.path}'};
      }
      res.write(jsonEncode(body));
    } catch (e) {
      res.statusCode = HttpStatus.internalServerError;
      res.write(jsonEncode({'error': '$e'}));
    } finally {
      await res.close();
    }
  }

  Future<List<Map<String, Object?>>> _eventsSince(int since, Duration wait) async {
    var out = _events.where((e) => (e['seq'] as int) > since).toList();
    if (out.isEmpty && wait > Duration.zero) {
      final c = _wake ??= Completer<void>();
      await c.future.timeout(wait, onTimeout: () {});
      out = _events.where((e) => (e['seq'] as int) > since).toList();
    }
    return out;
  }

  /// What `GET /state` returns.
  Map<String, Object?> state() {
    final radio = _read(meshRadioProvider);
    final roles = _read(radioRolesProvider);
    final session = _read(sessionManagerProvider).activeSession;
    final gps = _read(gpsServiceProvider);
    final pos = gps.lastPosition;
    return {
      'app': {
        'name': AppInfo.displayName,
        'platform': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'bench': true,
        // T1 (simulator): the demo's pretend radio and database.
        'demo': DemoMode.enabled,
        'demoScreen': DemoMode.enabled ? DemoMode.screen : null,
      },
      'gps': {
        'status': gps.state.status.name,
        'lat': pos?.latitude,
        'lon': pos?.longitude,
        'alt': pos?.altitude,
      },
      'radio': _radioState(radio),
      'roles': {
        'base': roles.nodeOf(RadioRole.base),
        'mobile': roles.nodeOf(RadioRole.mobile),
        'basePreset': roles.presetOf(RadioRole.base),
        'mobilePreset': roles.presetOf(RadioRole.mobile),
        'baseDevice': roles.deviceOf(RadioRole.base),
        'mobileDevice': roles.deviceOf(RadioRole.mobile),
        'baseBeaconKind': roles.baseBeacon?.kind.name,
        'baseBeaconIntervalSec': roles.baseBeacon?.intervalSec,
      },
      'session': session == null
          ? null
          : {
              'id': session.id,
              'mapId': session.coverageMapId,
              'baseNodeId': session.baseNodeId,
              'startedAt': session.startedAt.toIso8601String(),
              'pingIntervalSec': session.pingIntervalSec,
              'beaconKind': session.beaconKind,
              'beaconIntervalSec': session.beaconIntervalSec,
              'loraPreset': session.loraPreset,
              'protocol': session.protocol,
            },
      'range': _read(outOfRangeMonitorProvider).state.name,
      'beacon': _beaconState(),
      'seq': _seq,
    };
  }

  Map<String, Object?> _beaconState() {
    final b = _read(packetProcessorProvider).beacons;
    return {
      'active': b.active,
      'kind': b.kind.name,
      'intervalSec': b.intervalSec,
      'heard': b.heard,
      'seqMissed': b.seqMissed,
      'traceMissed': b.traceMissed,
      'absent': b.absent,
    };
  }

  Map<String, Object?> _radioState(MeshRadio radio) => {
        'state': radio.state.name,
        'ready': radio.isReady,
        'protocol': radio.protocol.name,
        'name': radio.displayName,
        'descriptor': radio.descriptor == null
            ? null
            : {'id': radio.descriptor!.id, 'name': radio.descriptor!.name},
        'nodeId': radio.myNodeId,
        'preset': radio.currentPreset?.id,
        'region': radio.regionName,
        'frequencyMHz': radio.regionFrequencyMHz,
        'primaryChannel': radio.primaryChannelName,
        'onPublicChannel': radio.isReady ? radio.onPublicChannel : null,
        'settings': radio.radioSettings == null
            ? null
            : {
                'txPower': radio.radioSettings!.txPowerDbm,
                'hopLimit': radio.radioSettings!.hopLimit,
                'slot': radio.radioSettings!.frequencySlot,
                'frequencyMHz': radio.radioSettings!.frequencyMHz,
              },
      };

  // -- commands --------------------------------------------------------------

  /// Alias kept for the MeshCore / remote-admin tests.
  Future<Object?> run(String cmd, Map<String, dynamic> a) => runCommand(cmd, a);

  /// Run one `POST /cmd` command; throws on a bad command or a failure.
  Future<Object?> runCommand(String cmd, Map<String, dynamic> a) async {
    final radio = _read(meshRadioProvider);
    switch (cmd) {
      case 'ping':
        return 'pong';

      case 'prefs.get':
        return _read(sharedPreferencesProvider).get(a['key'] as String);
      case 'prefs.set':
        final prefs = _read(sharedPreferencesProvider);
        final key = a['key'] as String;
        final v = a['value'];
        switch (v) {
          case null:
            await prefs.remove(key);
          case bool b:
            await prefs.setBool(key, b);
          case int i:
            await prefs.setInt(key, i);
          case double d:
            await prefs.setDouble(key, d);
          case String s:
            await prefs.setString(key, s);
          default:
            throw ArgumentError('prefs.set: unsupported value $v');
        }
        return true;

      case 'gps.set':
        _read(gpsServiceProvider).useDemoPosition(
            (a['lat'] as num).toDouble(), (a['lon'] as num).toDouble(),
            altitude: (a['alt'] as num?)?.toDouble() ?? 0);
        return true;

      case 'radio.scan':
        final secs = (a['seconds'] as num?)?.toInt() ?? 10;
        final found = <String, RadioDescriptor>{};
        await for (final list in _read(radioScannerProvider)
            .scan(serviceUuids: RadioServices.all, timeout: Duration(seconds: secs))) {
          for (final d in list) {
            found[d.id] = d;
          }
        }
        return found.values
            .map((d) => {
                  'id': d.id,
                  'name': d.name,
                  'protocol': d.protocol.name,
                  'rssi': d.scanRssi
                })
            .toList();

      case 'radio.state':
        return _radioState(radio);

      case 'radio.connect':
        final d = _descriptor(a);
        final secs = (a['timeoutSec'] as num?)?.toInt() ?? 120;
        await radio.connect(d);
        await _waitReady(radio, Duration(seconds: secs));
        return _radioState(radio);

      // Drop the link and connect again, so the app re-reads the radio's
      // settings (a channel changed over USB while the nRF52 link stayed
      // up). Default target: the radio connected now, else the mobile role.
      case 'radio.reconnect':
        final RadioDescriptor d;
        if (a['id'] != null) {
          d = _descriptor(a);
        } else if (radio.descriptor != null) {
          d = radio.descriptor!;
        } else {
          final id = _read(radioRolesProvider).deviceOf(RadioRole.mobile);
          if (id == null) {
            throw StateError('radio.reconnect: no radio to reconnect to');
          }
          d = RadioDescriptor(id: id, name: '', protocol: radio.protocol);
        }
        final secs = (a['timeoutSec'] as num?)?.toInt() ?? 120;
        await radio.disconnect();
        await radio.connect(d);
        await _waitReady(radio, Duration(seconds: secs));
        return _radioState(radio);

      case 'radio.disconnect':
        await radio.disconnect();
        return true;

      // Android only: forget the phone's pairing with a radio whose keys
      // changed (reflashed), so the next connect pairs again. False on iOS.
      case 'ble.removeBond':
        return BleTransport.removeBond(a['id'] as String);

      case 'radio.queryDevice':
        final info = await radio.queryDevice();
        return {
          'protocol': info.protocol.name,
          'model': info.model,
          'firmware': info.firmwareVersion,
        };

      // The connected MeshCore radio's settings as it last reported them
      // (SELF_INFO / DEVICE_INFO / GET_CHANNEL): what a USB read-back would
      // give if the BLE companion build had one. Secrets as hex.
      case 'radio.settings':
        final mc = radioAs<MeshCoreRadio>(radio);
        if (mc == null) {
          throw StateError('radio.settings: the connected radio is not '
              'MeshCore (${radio.protocol.name}); use radio.snapshot');
        }
        final s = mc.settings;
        if (s == null) throw StateError("radio.settings: settings not read yet");
        return _meshCoreSettingsJson(s);

      // Either protocol's settings, read from the connected radio: the
      // same data a radio backup holds, as plain JSON.
      case 'radio.snapshot':
        return _snapshot(radio);

      // Radio Setup, the same calls the screen makes.
      case 'radio.setupBase':
        final d = _descriptor(a);
        await _read(radioProfileServiceProvider).applyToBase(
          d,
          preset: _preset(a),
          beaconSecs: (a['beaconSecs'] as num?)?.toInt() ?? 60,
          rename: a['rename'] as bool? ?? true,
          allowRemoteChanges: a['allowRemoteChanges'] as bool? ?? true,
          frequencyMHz: _frequency(a, d.protocol, radio, RadioRole.base),
          txPowerDbm: ((a['txPowerDbm'] ?? a['txPower']) as num?)?.toInt(),
          onStep: (s) => emit('setup', {'role': 'base', 'step': s}),
        );
        return true;
      case 'radio.setupConnected':
        final role = RadioRole.values.byName(a['role'] as String? ?? 'mobile');
        await _read(radioProfileServiceProvider).applyToConnected(
          role,
          preset: _preset(a),
          beaconSecs: (a['beaconSecs'] as num?)?.toInt() ?? 0,
          rename: a['rename'] as bool? ?? true,
          frequencyMHz: _frequency(a, radio.protocol, radio, role),
          txPowerDbm: ((a['txPowerDbm'] ?? a['txPower']) as num?)?.toInt(),
          onStep: (s) => emit('setup', {'role': role.name, 'step': s}),
        );
        return true;
      case 'radio.switchToAndApplyMobile':
        final d = _descriptor(a);
        await _read(radioProfileServiceProvider).switchToAndApplyMobile(
          d,
          preset: _preset(a),
          rename: a['rename'] as bool? ?? true,
          frequencyMHz: _frequency(a, d.protocol, radio, RadioRole.mobile),
          txPowerDbm: ((a['txPowerDbm'] ?? a['txPower']) as num?)?.toInt(),
          onStep: (s) => emit('setup', {'role': 'mobile', 'step': s}),
        );
        return true;

      // Change the BASE over the mesh from the connected mobile (the
      // guided plan's changeRadios step, `MeshRadio.setRemoteLora`: get the
      // LoRa config for the session passkey, begin/set/commit, PKI, waiting
      // for the base's own ACK; a lost ACK on the commit = sent, the node
      // reboots). `nodeNum` defaults to the Radio Setup base; `preset` is
      // a Meshtastic preset id, `txPower` dBm (0 = firmware maximum).
      // Returns the steps the radio reported and whether the commit was
      // acknowledged (`confirmed`), like `AppPlanEnvironment.changeBaseRemote`.
      case 'radio.setRemoteLora':
        if (!radio.supportsRemoteAdmin) {
          throw UnsupportedError(
              'radio.setRemoteLora: no remote administration on '
              '${radio.protocol.name}');
        }
        final roles = _read(radioRolesProvider);
        final nodeNum =
            (a['nodeNum'] as num?)?.toInt() ?? roles.nodeOf(RadioRole.base);
        if (nodeNum == null) {
          throw StateError(
              'radio.setRemoteLora: no base node (run Radio Setup first '
              'or pass nodeNum)');
        }
        final presetId = a['preset'] as String?;
        final preset = presetId == null
            ? null
            : (MeshtasticPresets.fromId(presetId) ??
                (throw ArgumentError('unknown preset $presetId')));
        final txPower = (a['txPower'] as num?)?.toInt();
        final steps = <String>[];
        var confirmed = true;
        await radio.setRemoteLora(
          nodeNum,
          preset: preset,
          txPowerDbm: txPower,
          onStep: (s) {
            steps.add(s);
            if (s.contains(unconfirmedSaveStep)) confirmed = false;
            emit('remote', {'nodeNum': nodeNum, 'step': s});
          },
        );
        // Like the guided runner after changeBaseRemote: the app's picture
        // of the base follows the change (the base can't be read back once
        // the phone is on the mobile).
        if (nodeNum == roles.nodeOf(RadioRole.base)) {
          await roles.recordSetup(
            RadioRole.base,
            presetId: preset?.id ?? roles.presetOf(RadioRole.base) ?? '',
            region: roles.regionOf(RadioRole.base) ?? '',
            frequencySlot: roles.slotOf(RadioRole.base),
            txPowerDbm: txPower ?? roles.txPowerOf(RadioRole.base),
            frequencyMHz: roles.frequencyOf(RadioRole.base),
          );
        }
        return {'nodeNum': nodeNum, 'confirmed': confirmed, 'steps': steps};

      case 'map.create':
        final id = await _read(databaseProvider).createCoverageMap(
          name: a['name'] as String? ?? 'Bench',
          baseLat: (a['baseLat'] as num?)?.toDouble(),
          baseLon: (a['baseLon'] as num?)?.toDouble(),
          baseNodeId: (a['baseNodeId'] as num?)?.toInt(),
        );
        return id;

      case 'session.start':
        final roles = _read(radioRolesProvider);
        final s = await _read(sessionManagerProvider).startSession(
          coverageMapId: (a['mapId'] as num).toInt(),
          baseMeshNodeId:
              (a['baseNodeId'] as num?)?.toInt() ?? roles.nodeOf(RadioRole.base),
          name: a['name'] as String? ?? 'bench',
          pingIntervalSec: (a['pingIntervalSec'] as num?)?.toInt() ?? 0,
        );
        return s.id;
      case 'session.end':
        await _read(sessionManagerProvider).endSession();
        return true;

      case 'beacon.state':
        return _beaconState();

      case 'backups.list':
        final node = (a['nodeNum'] as num?)?.toInt();
        final all = await _read(radioBackupServiceProvider).list();
        return [
          for (final b in all)
            if (node == null || b.nodeNum == node) _backupJson(b)
        ];

      case 'backups.restoreOriginal':
        return _restoreOriginal(
            radio, (a['nodeNum'] as num?)?.toInt() ?? radio.myNodeId);

      case 'export.session':
        final format = ExportFormat.values
            .byName(a['format'] as String? ?? ExportFormat.csvV2.name);
        return _read(csvExportServiceProvider)
            .renderSession((a['sessionId'] as num).toInt(), format: format);
      case 'export.mapsJson':
        return _read(csvExportServiceProvider)
            .mapsJson(mapId: (a['mapId'] as num?)?.toInt());
      case 'export.all':
        return _read(csvExportServiceProvider).exportAll();

      // Read-only SQL for assertions (bench builds only): one SELECT.
      case 'db.query':
        final sql = (a['sql'] as String).trim().replaceFirst(RegExp(r';\s*$'), '');
        if (!RegExp(r'^(select|with)\b', caseSensitive: false).hasMatch(sql) ||
            sql.contains(';')) {
          throw ArgumentError('db.query: a single SELECT only');
        }
        final rows = await _read(databaseProvider).customSelect(sql).get();
        return rows.map((r) => r.data).toList();

      default:
        throw ArgumentError('unknown command $cmd');
    }
  }

  Map<String, Object?> _backupJson(RadioBackup b) => {
        'path': b.path,
        'nodeNum': b.nodeNum,
        'nodeId': b.nodeId,
        'radioName': b.radioName,
        'ownerName': b.ownerName,
        'protocol': b.protocol.name,
        'reason': b.reason,
        'original': b.original,
        'savedAt': b.savedAt.toUtc().toIso8601String(),
        'lastConfirmedAt': b.lastConfirmedAt.toUtc().toIso8601String(),
        'firmwareVersion': b.firmwareVersion,
        'appVersion': b.appVersion,
        'summary': b.summary,
        'channels': b.channelSummary,
        'hardware': b.hardwareLabel,
        if (b is MeshtasticBackup) 'preset': b.presetName,
        if (b is MeshtasticBackup) 'region': b.lora.region.name,
        if (b is MeshtasticBackup) 'adminKeys': b.adminKeys?.length,
      };

  /// "Put this radio back the way it was" without the dialog: the
  /// connected radio's original backup, the same admin-key and roles
  /// bookkeeping as the Backups screen (`_restoreFlow(putBack: true)`).
  Future<Map<String, Object?>> _restoreOriginal(
      MeshRadio radio, int? nodeNum) async {
    if (_read(sessionManagerProvider).activeSession != null) {
      throw StateError('End the recording session before restoring a radio');
    }
    if (!RadioBackupService.supports(radio)) {
      throw StateError('Connect a Meshtastic or MeshCore radio first');
    }
    if (nodeNum == null) throw StateError('No connected radio and no nodeNum');
    final service = _read(radioBackupServiceProvider);
    final all = await service.list();
    final original =
        RadioBackup.originalOf(all.where((b) => b.nodeNum == nodeNum));
    if (original == null) {
      throw StateError('No original backup for ${nodeIdOf(nodeNum)}');
    }
    final roles = _read(radioRolesProvider);
    final grantedTo = roles.remoteAdminGrantedNode;
    final isBase = roles.nodeOf(RadioRole.base) == original.nodeNum;
    final reboots = original.protocol == RadioProtocol.meshtastic;
    final mobileKey = isBase && grantedTo != null && reboots
        ? MeshtasticContacts(_read(sharedPreferencesProvider))
            .get(grantedTo)
            ?.publicKey
        : null;
    final steps = <String>[];
    final outcome = await service.restore(
      radio,
      original,
      onStep: (s) {
        steps.add(s);
        emit('restore', {'nodeNum': nodeNum, 'step': s});
      },
      removeAdminKeys: [
        if (mobileKey != null && mobileKey.length == 32) mobileKey
      ],
    );
    final revoked = mobileKey != null && outcome.removed(mobileKey);
    if (revoked) await roles.clearRemoteAdmin();
    await roles.clearNode(original.nodeNum);
    return {
      'backup': _backupJson(original),
      'steps': steps,
      'reboots': reboots,
      'adminKeys': outcome.adminKeys?.length,
      'adminKeyProblem': outcome.adminKeyProblem,
      'revokedMobileKey': revoked,
      'rolesCleared': true,
    };
  }

  static String nodeIdOf(int n) =>
      '!${n.toRadixString(16).padLeft(8, '0')}';

  RadioDescriptor _descriptor(Map<String, dynamic> a) => RadioDescriptor(
        id: a['id'] as String,
        name: a['name'] as String? ?? '',
        protocol: RadioProtocol.values.byName(a['protocol'] as String? ?? 'meshtastic'),
      );

  /// A Meshtastic modem preset id, or a MeshCore ladder id (a community
  /// preset id is mapped onto the ladder like Radio Setup does).
  RadioPreset _preset(Map<String, dynamic> a) {
    final id = a['preset'] as String? ?? MeshtasticPresets.longFast.id;
    return MeshtasticPresets.fromId(id) ??
        MeshCoreModulations.byId(MeshCoreModulations.ladderId(id))
            ?.radioPreset ??
        (throw ArgumentError('unknown preset $id'));
  }

  /// The test frequency for a MeshCore write (null on Meshtastic, where
  /// region and preset decide): the `frequencyMHz` argument, else what
  /// Radio Setup recorded for the base (so the mobile follows it), else the
  /// client-repeat frequency of the connected radio's band, as the Radio
  /// Setup screen prefills it. Null when none is known: the radio then
  /// keeps its own frequency, and a base write fails unless that is one
  /// the firmware relays on.
  double? _frequency(Map<String, dynamic> a, RadioProtocol protocol,
      MeshRadio radio, RadioRole role) {
    final asked = (a['frequencyMHz'] as num?)?.toDouble();
    if (asked != null) return asked;
    if (protocol != RadioProtocol.meshcore) return null;
    if (role == RadioRole.mobile) {
      final base = _read(radioRolesProvider).frequencyOf(RadioRole.base);
      if (base != null && base > 0) return base;
    }
    if (radio.isReady && radio.protocol == RadioProtocol.meshcore) {
      final mhz = radio.radioSettings?.frequencyMHz ?? radio.regionFrequencyMHz;
      return MeshCoreBand.of(mhz > 0 ? mhz : 915).clientRepeatMHz;
    }
    return null;
  }

  // -- snapshots -------------------------------------------------------------

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Map<String, Object?> _meshCoreSettingsJson(MeshCoreSettings s) => {
        'name': s.name,
        'txPowerDbm': s.txPowerDbm,
        'frequencyKHz': s.frequencyKHz,
        'frequencyMHz': s.frequencyMHz,
        'bandwidthHz': s.bandwidthHz,
        'spreadingFactor': s.spreadingFactor,
        'codingRate': s.codingRate,
        'paramsLabel': s.paramsLabel,
        'modulation': s.modulation?.id,
        'community': s.community?.id,
        'clientRepeat': s.clientRepeat,
        'manufacturer': s.manufacturer,
        'firmwareVersion': s.firmwareVersion,
        'channels': [
          for (final c in s.channels)
            {
              'index': c.index,
              'name': c.name,
              'secret': _hex(c.secret),
              'empty': c.isEmpty,
            }
        ],
      };

  /// What the connected radio holds, by protocol. Built from the same
  /// read as a radio backup ([RadioBackupService.snapshot]), so a bench
  /// check sees exactly what Restore would write back.
  Future<Map<String, Object?>> _snapshot(MeshRadio radio) async {
    if (!radio.isReady) throw StateError('radio.snapshot: radio not ready');
    final backup = await _read(radioBackupServiceProvider).snapshot(radio);
    final out = <String, Object?>{
      'protocol': backup.protocol.name,
      'nodeId': backup.nodeNum,
      'nodeIdHex': backup.nodeId,
      'name': radio.displayName,
      'preset': radio.currentPreset?.id,
      'onPublicChannel': radio.onPublicChannel,
      'firmware': backup.firmwareVersion,
      'summary': backup.summary,
    };
    if (backup is MeshCoreBackup) {
      out['meshcore'] = _meshCoreSettingsJson(backup.settings);
    } else if (backup is MeshtasticBackup) {
      final lora = backup.lora;
      final owner = backup.owner;
      final device = backup.device;
      final telemetry = backup.telemetry;
      final rangeTest = backup.rangeTest;
      final settings = radio.radioSettings;
      out['meshtastic'] = {
        'channels': [
          for (final c in backup.channels)
            {
              'index': c.index,
              'role': c.role.name,
              'name': c.settings.name,
              'psk': _hex(c.settings.psk),
            }
        ],
        'lora': {
          'usePreset': lora.usePreset,
          'modemPreset': lora.modemPreset.name,
          'region': lora.region.name,
          'txPower': lora.txPower,
          'hopLimit': lora.hopLimit,
          'channelNum': lora.channelNum,
          'overrideFrequency': lora.overrideFrequency,
          'frequencySlot': settings?.frequencySlot,
          'frequencyMHz': settings?.frequencyMHz,
        },
        'owner': owner == null
            ? null
            : {
                'longName': owner.longName,
                'shortName': owner.shortName,
                'hwModel': owner.hwModel.name,
              },
        'device': device == null
            ? null
            : {
                'role': device.role.name,
                'rebroadcastMode': device.rebroadcastMode.name,
              },
        'telemetry': telemetry == null
            ? null
            : {
                'deviceUpdateInterval': telemetry.deviceUpdateInterval,
                'deviceTelemetryEnabled': telemetry.deviceTelemetryEnabled,
              },
        'rangeTest': rangeTest == null
            ? null
            : {'enabled': rangeTest.enabled, 'sender': rangeTest.sender},
        'adminKeys': backup.adminKeys?.map(_hex).toList(),
      };
    }
    return out;
  }

  Future<void> _waitReady(MeshRadio radio, Duration timeout) async {
    if (radio.isReady) return;
    await radio.connectionState
        .firstWhere((s) => s == RadioConnectionState.ready)
        .timeout(timeout, onTimeout: () =>
            throw TimeoutException('radio not ready after $timeout: ${radio.state.name}'));
  }
}
