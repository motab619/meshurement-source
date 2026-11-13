// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/services/active_probe_service.dart';
import 'package:mesh_analyzer/services/out_of_range_monitor.dart';
import 'package:mesh_analyzer/services/session_manager.dart';
import 'package:mesh_analyzer/utils/constants.dart';

import 'fakes/fake_mesh_radio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const base = 7;

  group('out-of-range window', () {
    test('three missed probes, not two: 3 × interval + reply time', () {
      // MeshCore trace every 30 s, reply timeout 30 s.
      expect(
          SessionManager.outOfRangeTimeoutSecFor(
              prefSec: 30, intervalSec: 30, replySec: 30, beaconSec: 0),
          120);
      // Meshtastic ping every 60 s, DM ACK timeout 30 s.
      expect(
          SessionManager.outOfRangeTimeoutSecFor(
              prefSec: 90, intervalSec: 60, replySec: 30, beaconSec: 0),
          210);
      // The user's setting wins when it is longer.
      expect(
          SessionManager.outOfRangeTimeoutSecFor(
              prefSec: 600, intervalSec: 30, replySec: 30, beaconSec: 0),
          600);
      // Pings off: two beacon intervals plus jitter.
      expect(
          SessionManager.outOfRangeTimeoutSecFor(
              prefSec: 30, intervalSec: 0, replySec: 30, beaconSec: 60),
          150);
    });

    test('reply timeout per protocol', () {
      expect(ActiveProbeService.pingTimeoutSecFor(RadioProtocol.meshcore, 30),
          30);
      expect(
          ActiveProbeService.pingTimeoutSecFor(RadioProtocol.meshcore, 120),
          30);
      expect(ActiveProbeService.pingTimeoutSecFor(RadioProtocol.meshcore, 2),
          5);
      expect(
          ActiveProbeService.pingTimeoutSecFor(RadioProtocol.meshtastic, 5),
          30);
    });
  });

  group('OutOfRangeMonitor', () {
    late FakeMeshRadio radio;
    late OutOfRangeMonitor monitor;

    setUp(() {
      radio = FakeMeshRadio(protocol: RadioProtocol.meshcore);
      monitor = OutOfRangeMonitor(
          notifications: FlutterLocalNotificationsPlugin(), radio: radio);
    });

    tearDown(() async {
      monitor.dispose();
      await radio.dispose();
    });

    test('one answer while out of range is not back in range; two are', () {
      fakeAsync((async) {
        monitor.configure(baseNodeId: base, timeoutSec: 120);
        monitor.onPacketReceived(base);
        expect(monitor.state, RangeState.inRange);

        async.elapse(const Duration(seconds: 121));
        expect(monitor.state, RangeState.outOfRange);

        // A lucky trace at the edge of coverage.
        monitor.onPacketReceived(base);
        expect(monitor.state, RangeState.outOfRange);
        expect(monitor.lastHeardBase, isNotNull);

        monitor.onPacketReceived(base);
        expect(monitor.state, RangeState.inRange);
        expect(monitor.sentAlerts.map((a) => a.title),
            ['Out of range', 'Back in range']);
      });
    });

    test('a lone answer restarts the clock, then the count starts over',
        () {
      fakeAsync((async) {
        monitor.configure(baseNodeId: base, timeoutSec: 120);
        monitor.onPacketReceived(base);
        async.elapse(const Duration(seconds: 121));
        expect(monitor.state, RangeState.outOfRange);

        monitor.onPacketReceived(base);
        async.elapse(const Duration(seconds: 121));
        // Still out of range; the one answer no longer counts.
        monitor.onPacketReceived(base);
        expect(monitor.state, RangeState.outOfRange);
        monitor.onPacketReceived(base);
        expect(monitor.state, RangeState.inRange);
        // Only the first "Out of range" was posted: the state never left it.
        expect(monitor.sentAlerts.where((a) => a.title == 'Out of range'),
            hasLength(1));
      });
    });

    test('going out again within five minutes of coming back is quiet', () {
      fakeAsync((async) {
        monitor.configure(baseNodeId: base, timeoutSec: 120);
        monitor.onPacketReceived(base);
        async.elapse(const Duration(seconds: 121));
        expect(monitor.sentAlerts.single,
            (title: 'Out of range', quiet: false));

        // Back after 3 minutes: well past the 2-minute repeat window.
        async.elapse(const Duration(minutes: 3));
        monitor.onPacketReceived(base);
        monitor.onPacketReceived(base);
        expect(monitor.state, RangeState.inRange);
        expect(monitor.sentAlerts.last, (title: 'Back in range', quiet: false));

        // Out again 2 minutes later: a flap, silent.
        async.elapse(const Duration(seconds: 121));
        expect(monitor.state, RangeState.outOfRange);
        expect(monitor.sentAlerts.last, (title: 'Out of range', quiet: true));

        // Back 4 minutes after the last return: still the same flap.
        async.elapse(const Duration(minutes: 1));
        monitor.onPacketReceived(base);
        monitor.onPacketReceived(base);
        expect(monitor.sentAlerts.last, (title: 'Back in range', quiet: true));

        // Six quiet minutes in range, then a new outage: that one sounds.
        for (var i = 0; i < 6; i++) {
          async.elapse(const Duration(minutes: 1));
          monitor.onPacketReceived(base);
        }
        expect(monitor.state, RangeState.inRange);
        async.elapse(const Duration(seconds: 121));
        expect(monitor.state, RangeState.outOfRange);
        expect(monitor.sentAlerts.last, (title: 'Out of range', quiet: false));
      });
    });

    test('unknown to in range needs only one answer', () {
      fakeAsync((async) {
        monitor.configure(baseNodeId: base, timeoutSec: 120);
        expect(monitor.state, RangeState.unknown);
        monitor.onPacketReceived(base);
        expect(monitor.state, RangeState.inRange);
        expect(monitor.sentAlerts, isEmpty);
      });
    });
  });
}
