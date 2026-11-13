// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../demo/demo_mode.dart';

/// Small on-device diagnostics log (Documents/diag.log, ~256 KB, oldest
/// half dropped when full) for things that are invisible in the field:
/// range alerts, notifications, GPS and Bluetooth state, app lifecycle.
/// Shared from About → "Share diagnostics log". Contains no positions or
/// keys; node numbers appear as `!abcd`.
class DiagLog {
  DiagLog._();
  static final DiagLog instance = DiagLog._();

  static const maxBytes = 256 * 1024;
  static const _keepRecent = 60;

  /// The newest lines, for an in-app view.
  final recent = ValueNotifier<List<String>>(const []);

  File? _file;
  Future<void> _pending = Future.value();

  Future<File?> _open() async {
    if (DemoMode.enabled) return null; // screenshots: never write
    if (_file != null) return _file;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/diag.log');
      return _file;
    } catch (e) {
      print('DiagLog: no documents dir: $e');
      return null;
    }
  }

  /// Append one line (also printed to the console).
  void log(String tag, String message) {
    final line = '${DateTime.now().toIso8601String()} [$tag] $message';
    print(line);
    final list = [...recent.value, line];
    recent.value = list.length > _keepRecent
        ? list.sublist(list.length - _keepRecent)
        : list;
    _pending = _pending.then((_) => _append(line)).catchError((Object e) {
      print('DiagLog: write failed: $e');
    });
  }

  Future<void> _append(String line) async {
    final f = await _open();
    if (f == null) return;
    await f.writeAsString('$line\n', mode: FileMode.append, flush: true);
    if (await f.length() > maxBytes) {
      final text = await f.readAsString();
      await f.writeAsString(text.substring(text.length ~/ 2), flush: true);
    }
  }

  /// Path of the log file (null when there is none yet).
  Future<String?> path() async {
    await _pending;
    final f = await _open();
    return f != null && await f.exists() ? f.path : null;
  }

  Future<void> clear() async {
    await _pending;
    final f = await _open();
    if (f != null && await f.exists()) await f.delete();
    recent.value = const [];
  }
}

/// `!abcd` form of a mesh node number for log lines.
String diagNode(int? num) => num == null
    ? '-'
    : '!${num.toRadixString(16).padLeft(8, '0').substring(4)}';
