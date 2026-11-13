// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../services/gps_service.dart';

/// Location platform for bench mode: permission always granted, no prompt,
/// and a position stream that only carries what the bench sends
/// (`gps.set`, fed through [GpsService.useDemoPosition]). Real GPS never
/// runs, so the scripted position is the only one the app sees, while the
/// background-mode path (`setBackgroundMode`) still executes.
class BenchLocationBackend implements LocationBackend {
  const BenchLocationBackend();

  static final _never = StreamController<Position>.broadcast();

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.always;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async =>
      LocationAccuracyStatus.precise;

  @override
  Stream<Position> getPositionStream(LocationSettings settings) =>
      _never.stream;

  @override
  Future<Position> getCurrentPosition(LocationSettings settings) async =>
      // GpsService catches this and answers with the last injected position.
      throw StateError('bench: no live GPS');
}
