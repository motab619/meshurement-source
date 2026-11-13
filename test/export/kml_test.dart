// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/services/export/kml.dart';
import 'package:xml/xml.dart';

import 'fixture.dart';

void main() {
  late ExportFixture f;
  setUp(() async => f = await ExportFixture.create());
  tearDown(() => f.db.close());

  test('well-formed XML, one Folder per session, timestamps and styles',
      () async {
    final kml = buildKml(
        [await f.session(f.session1), await f.session(f.session2)]);
    final doc = XmlDocument.parse(kml);
    expect(doc.findAllElements('Folder'), hasLength(2));
    final marks = doc.findAllElements('Placemark').toList();
    // 3 + 1 positioned events, plus the track of session 1.
    expect(marks.where((m) => m.findElements('TimeStamp').isNotEmpty),
        hasLength(4));
    final styles = marks
        .map((m) => m.getElement('styleUrl')?.innerText)
        .whereType<String>()
        .toSet();
    // LONG_FAST: SNR 5.5 at -90 dBm is far above the -131.5 dBm
    // sensitivity (hybrid margin 41.5 dB); SNR -12 is 5.5 dB of margin.
    expect(styles, contains('#margin_strong'));
    expect(styles, contains('#margin_weak'));
    expect(styles, contains('#ping_failed'));
    expect(doc.findAllElements('Style').length, 6);
    expect(kml, contains('<when>2026-10-17T'));
    // The formula-like node name survives escaping as ExtendedData.
    expect(
        doc.findAllElements('Data').any((d) =>
            d.getAttribute('name') == 'source_node_id' &&
            d.innerText == '!0000a1b2'),
        isTrue);
  });

  test('special characters are escaped', () {
    expect(xmlEscape('a<b>&"c"'), 'a&lt;b&gt;&amp;&quot;c&quot;');
    expect(kmlStyleIdForMargin(5.5), 'margin_weak');
    expect(kmlStyleIdForMargin(-1), 'margin_below');
    expect(kmlStyleIdForMargin(null), 'no_signal');
  });
}
