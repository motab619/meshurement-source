// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:mesh_analyzer/services/heading_service.dart';

/// Counts how often the compass is opened and whether it is still open.
class _FakeCompass {
  int opened = 0;
  StreamController<double?>? _c;

  bool get listening => _c?.hasListener ?? false;

  Stream<double?> open() {
    opened++;
    _c = StreamController<double?>();
    return _c!.stream;
  }

  void emit(double? h) => _c!.add(h);
}

void main() {
  test('the compass opens only while someone listens', () async {
    final fake = _FakeCompass();
    final source = CompassHeadingSource(compass: fake.open);

    final stream = source.headings;
    await Future<void>.delayed(Duration.zero);
    expect(fake.opened, 0, reason: 'getting the stream must not start it');

    final got = <double?>[];
    final sub = stream.listen(got.add);
    expect(fake.opened, 1);
    expect(fake.listening, isTrue);

    fake.emit(42);
    fake.emit(null);
    await Future<void>.delayed(Duration.zero);
    expect(got, [42, null]);

    await sub.cancel();
    expect(fake.listening, isFalse, reason: 'cancel stops the compass');

    // Heading up on again: a fresh subscription opens it again.
    final sub2 = source.headings.listen((_) {});
    expect(fake.opened, 2);
    expect(fake.listening, isTrue);
    await sub2.cancel();
    expect(fake.listening, isFalse);
  });

  test('normalize: Android -180…180 to 0…360, NaN = none', () {
    expect(CompassHeadingSource.normalize(-90), 270);
    expect(CompassHeadingSource.normalize(-180), 180);
    expect(CompassHeadingSource.normalize(90), 90);
    expect(CompassHeadingSource.normalize(360), 0);
    expect(CompassHeadingSource.normalize(double.nan), isNull);
    expect(CompassHeadingSource.normalize(null), isNull);
  });

  test('NoHeadingSource emits nothing', () async {
    expect(await const NoHeadingSource().headings.isEmpty, isTrue);
  });
}
