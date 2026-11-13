// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';

/// Where the top of the phone points, in degrees clockwise from true north
/// (0 = north, 90 = east), or null while the compass has no reading.
///
/// The Live map's "heading up" mode turns the map by this so the way you
/// are facing is up. Only the map subscribes, and only while that mode is
/// on: the magnetometer costs battery.
abstract class HeadingSource {
  Stream<double?> get headings;
}

/// The phone's compass (CoreLocation `trueHeading` on iOS). Emits nothing
/// where there is no compass, such as the simulator.
///
/// Lazy: each [headings] stream opens the compass only when it is listened
/// to and closes it on cancel, so heading updates run only while heading up
/// is on. (flutter_compass 0.8.1 also starts CoreMotion device-motion
/// updates natively at launch; only replacing the plugin stops those.)
class CompassHeadingSource implements HeadingSource {
  /// [compass] opens the raw reading stream; tests pass a fake.
  const CompassHeadingSource({Stream<double?> Function() compass = _plugin})
      : _compass = compass;

  final Stream<double?> Function() _compass;

  /// Android's flutter_compass reports -180…180 (iOS 0…360): brought to
  /// 0…360 so both match [HeadingSource.headings]. A NaN (no sensor
  /// reading) counts as none. Android's is magnetic north (iOS gives true
  /// north when it has a location fix): off by the local declination.
  static Stream<double?> _plugin() =>
      FlutterCompass.events?.map((e) => normalize(e.heading)) ??
      const Stream.empty();

  /// [degrees] in 0…360, or null for none / NaN.
  @visibleForTesting
  static double? normalize(double? degrees) =>
      degrees == null || degrees.isNaN ? null : degrees % 360;

  @override
  Stream<double?> get headings {
    StreamSubscription<double?>? sub;
    late final StreamController<double?> out;
    out = StreamController<double?>(
      onListen: () {
        sub = _compass()
            .listen(out.add, onError: out.addError, onDone: () => out.close());
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: () {
        final s = sub;
        sub = null;
        return s?.cancel();
      },
    );
    return out.stream;
  }
}

/// No compass: demo mode and tests.
class NoHeadingSource implements HeadingSource {
  const NoHeadingSource();

  @override
  Stream<double?> get headings => const Stream.empty();
}
