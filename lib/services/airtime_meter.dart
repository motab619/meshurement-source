// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

/// Estimated duty cycle of our radio: airtime of the packets the app sent
/// over the last [windowSec] seconds, divided by the window.
///
/// Only counts packets the app asks the radio to send over the air (not
/// admin messages to the local radio, and not the radio's own NodeInfo /
/// position / telemetry broadcasts, which the app can't see), so it is a
/// lower bound.
class AirtimeMeter {
  static const windowSec = 60;

  final _sent = <({DateTime at, double airtimeMs})>[];
  final _controller = StreamController<double>.broadcast();
  Timer? _ticker;

  /// Fraction 0..1 of the last [windowSec] seconds spent transmitting.
  double get duty {
    _prune(DateTime.now());
    final ms = _sent.fold<double>(0, (sum, e) => sum + e.airtimeMs);
    return ms / (windowSec * 1000);
  }

  /// Emits [duty] whenever a packet is recorded, then every second while
  /// anything is still inside the window.
  Stream<double> get dutyStream => _controller.stream;

  void record(double airtimeMs, {DateTime? at}) {
    _sent.add((at: at ?? DateTime.now(), airtimeMs: airtimeMs));
    _emit();
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _emit());
  }

  void _emit() {
    final d = duty;
    if (!_controller.isClosed) _controller.add(d);
    if (_sent.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _prune(DateTime now) {
    final cutoff = now.subtract(const Duration(seconds: windowSec));
    _sent.removeWhere((e) => e.at.isBefore(cutoff));
  }

  void dispose() {
    _ticker?.cancel();
    _controller.close();
  }
}
