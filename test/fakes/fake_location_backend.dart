// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:mesh_analyzer/services/gps_service.dart';

/// Scriptable location platform for [GpsService] tests (no plugin calls).
class FakeLocationBackend implements LocationBackend {
  FakeLocationBackend({
    this.permission = LocationPermission.whileInUse,
    this.afterRequest,
    this.serviceEnabled = true,
    this.accuracy = LocationAccuracyStatus.precise,
  });

  LocationPermission permission;

  /// What the permission becomes when requested (null: unchanged).
  LocationPermission? afterRequest;
  bool serviceEnabled;
  LocationAccuracyStatus accuracy;
  int requests = 0;
  int streamsOpened = 0;

  /// The settings of the newest stream.
  LocationSettings? lastSettings;
  final positions = StreamController<Position>.broadcast();

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    if (afterRequest != null) permission = afterRequest!;
    return permission;
  }

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async => accuracy;

  @override
  Stream<Position> getPositionStream(LocationSettings settings) {
    streamsOpened++;
    lastSettings = settings;
    return positions.stream;
  }

  @override
  Future<Position> getCurrentPosition(LocationSettings settings) =>
      positions.stream.first;

  static Position at(double lat, double lon, {double accuracy = 8}) => Position(
        latitude: lat,
        longitude: lon,
        timestamp: DateTime.now(),
        accuracy: accuracy,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
}
