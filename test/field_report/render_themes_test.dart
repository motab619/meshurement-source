// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

// Writes every report theme and format as a PNG, for looking at:
//   REPORT_RENDER_DIR=/some/dir flutter test test/field_report/render_themes_test.dart
// Files: <theme>-<format>.png (single session) and
// <theme>-compare<2|4>-<format>.png (comparison).
// Optional REPORT_RENDER_THEME=pop renders one theme. Skipped otherwise.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/services/field_report/comparison_report_data.dart';
import 'package:mesh_analyzer/services/field_report/field_report_data.dart';
import 'package:mesh_analyzer/services/field_report/field_report_loader.dart';
import 'package:mesh_analyzer/ui/widgets/field_report/comparison_report_card.dart';
import 'package:mesh_analyzer/ui/widgets/field_report/field_report_card.dart';
import 'package:mesh_analyzer/ui/widgets/field_report/report_style.dart';
import 'package:mesh_analyzer/ui/widgets/field_report/report_theme.dart';

import 'fixtures.dart';

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    final bytes = File('assets/fonts/$f').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

/// A side that walks [far] m out from the base on a bent path, the signal
/// falling with distance from [snr0].
ComparisonSideInput _side(
    String name, int id, double far, double snr0, double bend) {
  const n = 40;
  return ComparisonSideInput(name, [
    SessionReportInput(session: testSession(id), events: [
      for (var i = 0; i < n; i++)
        testEvent(
          id,
          i,
          far * i / (n - 1) * (0.35 + bend * i / n),
          far * i / (n - 1),
          snr: snr0 - 24 * i / n + (i % 5) * 1.5,
        ),
    ]),
  ]);
}

ComparisonReportData _comparison(int sides) => ComparisonReportData.build(
    [
      _side('Stock stubby', 1, 900, 12, 0.3),
      _side('5.8 dBi whip', 2, 1900, 17, 0.5),
      _side('Yagi on the mast', 3, 1400, 15, -0.4),
      _side('Long Fast', 4, 1100, 13, 0.9),
    ].take(sides).toList(),
    base: (lat: baseLat, lon: baseLon));

void main() {
  final dir = Platform.environment['REPORT_RENDER_DIR'];
  final only = Platform.environment['REPORT_RENDER_THEME'];

  testWidgets('render report themes', (tester) async {
    await tester.runAsync(() async {
      await _font('B612', [
        'B612-Regular.ttf',
        'B612-Italic.ttf',
        'B612-Bold.ttf',
        'B612-BoldItalic.ttf',
      ]);
      await _font('B612Mono', ['B612Mono-Regular.ttf', 'B612Mono-Bold.ttf']);
      await _font('CourierPrime',
          ['CourierPrime-Regular.ttf', 'CourierPrime-Bold.ttf']);
      await _font('Fredoka', ['Fredoka-Variable.ttf']);
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final data = await tester.runAsync(() async {
      final s = await seedSession32(db);
      return FieldReportLoader(db).session(s.sessionId);
    });
    for (final theme in ReportTheme.values) {
      if (only != null && theme.name != only) continue;
      final cards = <String, Widget Function(ReportFormat)>{
        '': (format) => FieldReportCard(
              data: data!,
              title: defaultReportTitle(data.presetName, data.startedAt),
              format: format,
              miles: true,
              theme: theme,
            ),
        '-points': (format) => FieldReportCard(
              data: data!,
              title: defaultReportTitle(data.presetName, data.startedAt),
              format: format,
              miles: true,
              theme: theme,
              showPath: false,
            ),
        for (final n in [2, 4])
          '-compare$n': (format) {
            final c = _comparison(n);
            return ComparisonReportCard(
              data: c,
              title: defaultReportTitle(c.presetName, c.startedAt),
              format: format,
              miles: true,
              theme: theme,
            );
          },
      };
      for (final MapEntry(key: kind, value: build) in cards.entries) {
        for (final format in ReportFormat.values) {
          final key = GlobalKey();
          tester.view.physicalSize = format.size;
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox.fromSize(
                size: format.size,
                child: build(format),
              ),
            ),
          ));
          expect(tester.takeException(), isNull,
              reason: '${theme.name}$kind ${format.name} overflowed or threw');
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            File('$dir/${theme.name}$kind-${format.name}.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
          });
        }
      }
    }
    tester.view.reset();
  }, skip: dir == null);
}
