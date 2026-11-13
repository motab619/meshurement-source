// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/services/range_test_detector.dart';
import 'package:mesh_analyzer/ui/widgets/range_test_dialog.dart';

void main() {
  testWidgets('the dialog is not dismissed by tapping outside', (tester) async {
    bool? answer;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context, // default barrierDismissible: true
            builder: (_) => RangeTestDialog(
              prompt: RangeTestPrompt(meshNodeId: 9, nodeName: 'Hilltop'),
              onResult: (ok) => answer = ok,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(RangeTestDialog), findsOneWidget);

    await tester.tapAt(const Offset(5, 5)); // the barrier
    await tester.pumpAndSettle();
    expect(find.byType(RangeTestDialog), findsOneWidget);

    await tester.tap(find.text('Yes, record'));
    await tester.pumpAndSettle();
    expect(find.byType(RangeTestDialog), findsNothing);
    expect(answer, isTrue);
  });
}
