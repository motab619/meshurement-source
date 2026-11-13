// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/services/gps_service.dart';

import 'fakes/fake_location_backend.dart';

/// The node's GPS standing in for the phone's (docs/design/ipad step 5):
/// a Wi-Fi iPad has no GPS, so the connected node's fixes are used while
/// the phone has no fix within 30 m, and only while they are fresh.
void main() {
  NodeFix fixAt(DateTime t, {double lat = 33.68, double lon = -116.24}) =>
      NodeFix(latitude: lat, longitude: lon, accuracyM: 10, time: t);

  test('no phone permission at all: the node fix is the position', () {
    fakeAsync((async) {
      final gps = GpsService(
          backend:
              FakeLocationBackend(permission: LocationPermission.deniedForever),
          clock: () => DateTime(2026, 11, 10).add(async.elapsed));
      final seen = <Position>[];
      gps.positionStream.listen(seen.add);
      gps.ensureStarted(request: false);
      async.flushMicrotasks();
      expect(gps.state.status, GpsStatus.denied);

      gps.addNodeFix(fixAt(DateTime(2026, 11, 10)));
      async.flushMicrotasks();
      expect(gps.state.status, GpsStatus.fix);
      expect(gps.state.source, GpsSource.node);
      expect(gps.lastPosition!.latitude, 33.68);
      expect(seen, hasLength(1));
      expect(gpsStatusLine(gps.state).text, 'GPS: from your node ±10 m');
      expect(gpsStatusLine(gps.state).problem, isFalse);

      // Two minutes without another: back to the phone's own state.
      async.elapse(const Duration(minutes: 2, seconds: 2));
      expect(gps.state.status, GpsStatus.denied);
      expect(gps.lastPosition, isNull);
      gps.dispose();
    });
  });

  test('a good phone fix wins; a poor one gives way to the node', () {
    fakeAsync((async) {
      final backend = FakeLocationBackend();
      final gps = GpsService(
          backend: backend,
          clock: () => DateTime(2026, 11, 10).add(async.elapsed));
      final seen = <Position>[];
      gps.positionStream.listen(seen.add);
      gps.ensureStarted(request: false);
      async.flushMicrotasks();

      backend.positions.add(FakeLocationBackend.at(33.70, -116.20));
      async.flushMicrotasks();
      gps.addNodeFix(fixAt(DateTime(2026, 11, 10)));
      async.flushMicrotasks();
      expect(gps.state.source, GpsSource.phone, reason: '±8 m phone fix');
      expect(gps.lastPosition!.latitude, 33.70);
      expect(seen.map((p) => p.latitude), [33.70]);

      // A Wi-Fi iPad's fix: ±65 m. The node's takes over, and the poor
      // phone fix is not passed on.
      backend.positions
          .add(FakeLocationBackend.at(33.71, -116.21, accuracy: 65));
      async.flushMicrotasks();
      expect(gps.state.source, GpsSource.node);
      expect(gps.lastPosition!.latitude, 33.68);
      expect(seen.map((p) => p.latitude), [33.70]);

      gps.addNodeFix(fixAt(DateTime(2026, 11, 10), lat: 33.69));
      async.flushMicrotasks();
      expect(seen.map((p) => p.latitude), [33.70, 33.69]);
      gps.dispose();
    });
  });

  test('node fixes are wanted only while the phone has no good fix', () {
    fakeAsync((async) {
      final backend = FakeLocationBackend();
      final gps = GpsService(backend: backend);
      final wanted = <bool>[];
      gps.nodeFixWantedChanges.listen(wanted.add);
      expect(gps.nodeFixWanted, isTrue, reason: 'no fix yet');
      gps.ensureStarted(request: false);
      async.flushMicrotasks();
      backend.positions.add(FakeLocationBackend.at(33.70, -116.20));
      async.flushMicrotasks();
      expect(gps.nodeFixWanted, isFalse);
      backend.positions
          .add(FakeLocationBackend.at(33.70, -116.20, accuracy: 65));
      async.flushMicrotasks();
      expect(gps.nodeFixWanted, isTrue);
      expect(wanted.last, isTrue);
      expect(wanted, contains(false));
      gps.dispose();
    });
  });

  test('an old or 0,0 node fix is ignored', () {
    fakeAsync((async) {
      final gps = GpsService(
          backend:
              FakeLocationBackend(permission: LocationPermission.deniedForever),
          clock: () => DateTime(2026, 11, 10, 12));
      gps.ensureStarted(request: false);
      async.flushMicrotasks();
      gps.addNodeFix(fixAt(DateTime(2026, 11, 10, 11, 50)));
      gps.addNodeFix(fixAt(DateTime(2026, 11, 10, 12), lat: 0, lon: 0));
      async.flushMicrotasks();
      expect(gps.state.status, GpsStatus.denied);
      expect(gps.lastPosition, isNull);
      gps.dispose();
    });
  });
}
