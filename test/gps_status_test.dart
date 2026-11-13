// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/gps_service.dart';

import 'fakes/fake_location_backend.dart';

void main() {
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('gpsStatusLine', () {
    test('maps each status to one line', () {
      expect(gpsStatusLine(const GpsState(GpsStatus.fix, accuracy: 7.6)),
          (text: 'GPS: fix ±8 m', problem: false));
      expect(gpsStatusLine(const GpsState(GpsStatus.searching)),
          (text: 'GPS: waiting for fix…', problem: true));
      expect(gpsStatusLine(const GpsState(GpsStatus.denied)),
          (text: 'GPS: permission denied — enable in Settings', problem: true));
      expect(gpsStatusLine(const GpsState(GpsStatus.off)).problem, isTrue);
      expect(gpsStatusLine(GpsState.unknown).problem, isFalse);
    });

    test('approximate location is flagged', () {
      final line = gpsStatusLine(
          const GpsState(GpsStatus.fix, accuracy: 900, approximate: true));
      expect(line.problem, isTrue);
      // "Precise Location" (iOS) / "Use precise location" (Android, what
      // flutter test reports as the platform).
      expect(line.text.toLowerCase(), contains('precise location'));
    });
  });

  group('GpsService.ensureStarted', () {
    test('denied: no stream, status denied; allowed later: starts', () async {
      final backend =
          FakeLocationBackend(permission: LocationPermission.deniedForever);
      final gps = GpsService(backend: backend);
      addTearDown(gps.dispose);

      expect((await gps.ensureStarted()).status, GpsStatus.denied);
      expect(backend.streamsOpened, 0);

      // The user allows location in Settings, then the app resumes.
      backend.permission = LocationPermission.whileInUse;
      expect((await gps.ensureStarted(request: false)).status,
          GpsStatus.searching);
      expect(backend.streamsOpened, 1);

      // Calling again doesn't open a second stream.
      await gps.ensureStarted();
      expect(backend.streamsOpened, 1);
    });

    test('asks only when requested', () async {
      final backend = FakeLocationBackend(
        permission: LocationPermission.denied,
        afterRequest: LocationPermission.whileInUse,
      );
      final gps = GpsService(backend: backend);
      addTearDown(gps.dispose);

      expect(
          (await gps.ensureStarted(request: false)).status, GpsStatus.notAsked);
      expect(backend.requests, 0);
      expect((await gps.ensureStarted()).status, GpsStatus.searching);
      expect(backend.requests, 1);
    });

    test('Location Services off', () async {
      final gps =
          GpsService(backend: FakeLocationBackend(serviceEnabled: false));
      addTearDown(gps.dispose);
      expect((await gps.ensureStarted()).status, GpsStatus.off);
    });

    test('a position turns searching into a fix with accuracy', () async {
      final backend = FakeLocationBackend();
      final gps = GpsService(backend: backend);
      addTearDown(gps.dispose);
      await gps.ensureStarted();

      backend.positions.add(FakeLocationBackend.at(33.7, -116.2, accuracy: 8));
      await settle();
      expect(gps.state, const GpsState(GpsStatus.fix, accuracy: 8));
      expect(gps.lastPosition!.latitude, 33.7);
    });

    test('gpsStatusProvider follows the service', () async {
      final backend = FakeLocationBackend();
      final gps = GpsService(backend: backend);
      final container = ProviderContainer(
          overrides: [gpsServiceProvider.overrideWithValue(gps)]);
      addTearDown(container.dispose);
      final seen = <GpsStatus>[];
      container.listen(gpsStatusProvider, (_, next) {
        if (next.valueOrNull case final s?) seen.add(s.status);
      }, fireImmediately: true);

      await gps.ensureStarted();
      backend.positions.add(FakeLocationBackend.at(1, 2));
      await settle();
      expect(seen, [GpsStatus.unknown, GpsStatus.searching, GpsStatus.fix]);
    });
  });

  group('stream settings', () {
    test('iOS: background location only while recording', () {
      final idle =
          GpsService.streamSettingsFor(TargetPlatform.iOS, background: false)
              as AppleSettings;
      final rec =
          GpsService.streamSettingsFor(TargetPlatform.iOS, background: true)
              as AppleSettings;
      expect(idle.allowBackgroundLocationUpdates, isFalse);
      expect(rec.allowBackgroundLocationUpdates, isTrue);
      expect(rec.showBackgroundLocationIndicator, isTrue);
    });

    test('Android: foreground service notice only while recording', () {
      final idle = GpsService.streamSettingsFor(TargetPlatform.android,
          background: false) as AndroidSettings;
      final rec =
          GpsService.streamSettingsFor(TargetPlatform.android, background: true)
              as AndroidSettings;
      expect(idle.foregroundNotificationConfig, isNull);
      expect(rec.foregroundNotificationConfig?.notificationTitle,
          'Meshurement is recording');
      expect(rec.foregroundNotificationConfig?.setOngoing, isTrue);
      expect(rec.distanceFilter, 5);
    });

    test('Android: the foreground service waits for the app to be resumed',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final backend = FakeLocationBackend();
      final gps = GpsService(backend: backend);
      addTearDown(gps.dispose);
      await gps.ensureStarted();
      expect(backend.streamsOpened, 1);
      AndroidSettings last() => backend.lastSettings as AndroidSettings;

      // A session picked up again at a launch into the background: Android
      // would refuse the foreground service, so a plain stream for now.
      gps.appInForeground = false;
      gps.setBackgroundMode(true);
      expect(backend.streamsOpened, 2);
      expect(last().foregroundNotificationConfig, isNull);

      // Resumed: the recording settings apply.
      gps.appInForeground = true;
      expect(backend.streamsOpened, 3);
      expect(last().foregroundNotificationConfig, isNotNull);

      // Going to the background again changes nothing; ending the session
      // drops the service.
      gps.appInForeground = false;
      expect(backend.streamsOpened, 3);
      gps.setBackgroundMode(false);
      expect(backend.streamsOpened, 4);
      expect(last().foregroundNotificationConfig, isNull);

      // A session started while resumed gets the service at once.
      gps.appInForeground = true;
      gps.setBackgroundMode(true);
      expect(backend.streamsOpened, 5);
      expect(last().foregroundNotificationConfig, isNotNull);
    });
  });
}
