// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:io';

import 'package:flutter/services.dart';

/// Bench mode: the hardware-in-the-loop rig (`tool/bench`,
/// `docs/design/bench-rig/README.md`).
///
/// Real radios over BLE and a real database, but GPS comes from the bench
/// and a small HTTP server on the phone's loopback ([BenchServer]) lets the
/// Mac drive services and read state. The Mac reaches it over USB
/// (`iproxy` on iOS, `adb forward` on Android), so nothing touches Wi-Fi
/// and iOS asks no local-network permission.
///
/// Compiled in only with `--dart-define=BENCH=true`; store builds never
/// honour the arguments. On with `-MeshBench` in the launch arguments
/// (`-benchPort N` picks the port, default 8765), or `MESH_BENCH=1` in the
/// environment. The arguments come over the `mesh_analyzer/app` channel:
/// on iOS `devicectl … process launch <bundle> -MeshBench -benchPort 8765`
/// hands them to AppDelegate as is; on Android MainActivity builds the same
/// list from Intent extras (`am start … --ez MeshBench true --ei benchPort
/// 8765`, each extra named like the flag without its dash).
class BenchMode {
  BenchMode._();

  /// Compile-time switch; everything else is dead code without it.
  static const bool build = bool.fromEnvironment('BENCH');

  static const defaultPort = 8765;

  static bool enabled = false;
  static int port = defaultPort;

  static Future<void> detect() async {
    if (!build) return;
    final env = Platform.environment['MESH_BENCH'];
    if (env != null && env.isNotEmpty && env != '0') {
      enabled = true;
      port = int.tryParse(Platform.environment['MESH_BENCH_PORT'] ?? '') ??
          defaultPort;
      return;
    }
    // Same channel and retry as DemoMode: on iOS the native side can lag
    // main(); Android's MainActivity registers the handler before main()
    // runs, so one try is enough there.
    final attempts = Platform.isIOS ? 30 : 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final args = await const MethodChannel('mesh_analyzer/app')
                .invokeListMethod<String>('launchArguments') ??
            const [];
        final parsed = parseArguments(args);
        enabled = parsed.enabled;
        port = parsed.port;
        break;
      } on MissingPluginException {
        if (attempt + 1 < attempts) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      } catch (_) {
        enabled = false;
        break;
      }
    }
  }

  /// What a launch argument list asks for: `-MeshBench` turns bench mode
  /// on, `-benchPort N` picks the port (a missing or malformed number keeps
  /// [defaultPort]). Pure, so the Android/iOS argument plumbing can be
  /// tested without a device.
  static ({bool enabled, int port}) parseArguments(List<String> args) {
    final enabled = args.contains('-MeshBench');
    var port = defaultPort;
    final i = args.indexOf('-benchPort');
    if (i >= 0 && i + 1 < args.length) {
      final n = int.tryParse(args[i + 1]);
      if (n != null && n > 0 && n <= 65535) port = n;
    }
    return (enabled: enabled, port: port);
  }
}
