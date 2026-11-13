// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/ui/widgets/export_dialog.dart';

void main() {
  Future<void> open(WidgetTester t, {int? sessionId}) async {
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => showExportDialog(context, ref,
                mapId: 1, mapName: 'Park', sessionId: sessionId),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
  }

  testWidgets('offers four formats, both scopes and the privacy note',
      (t) async {
    await open(t, sessionId: 5);
    expect(find.text('This session'), findsOneWidget);
    expect(find.text('Whole map'), findsOneWidget);
    expect(find.text('GeoJSON (QGIS, web maps)'), findsOneWidget);
    expect(find.text('KML (Google Earth)'), findsOneWidget);
    expect(find.text('CSV (Meshtastic range test layout)'), findsOneWidget);
    expect(find.text(exportPrivacyNote), findsOneWidget);
  });

  testWidgets('map-level dialog has no scope switch', (t) async {
    await open(t);
    expect(find.text('This session'), findsNothing);
    expect(find.text(exportPrivacyNote), findsOneWidget);
  });
}
