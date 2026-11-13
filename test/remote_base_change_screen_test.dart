// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/guided/base_change_sequence.dart';
import 'package:mesh_analyzer/services/remote_base_change.dart';
import 'package:mesh_analyzer/ui/screens/remote_base_change_screen.dart';

import 'guided/fake_plan_environment.dart';
import 'guided_ui/fakes.dart';

void main() {
  late GuidedEnv g;
  late FakePlanEnvironment env;
  late RemoteBaseChange change;

  setUp(() async {
    // Risk sheet already read on this phone.
    g = await GuidedEnv.create(prefs: {guidedRiskSeenKey: true});
    env = FakePlanEnvironment(g.db)..remoteAdminMobileNode = 0x1001;
    change = RemoteBaseChange(env,
        sequence: BaseChangeSequence(
          env,
          settleDuration: const Duration(milliseconds: 10),
          listenDuration: const Duration(milliseconds: 60),
          rollbackListenDuration: const Duration(milliseconds: 40),
          pingEvery: const Duration(milliseconds: 5),
          tick: const Duration(milliseconds: 5),
        ));
  });

  tearDown(() async {
    await env.dispose();
    await g.close();
  });

  Widget app({bool pro = true}) =>
      g.app(const RemoteBaseChangeScreen(), pro: pro, overrides: [
        planEnvironmentProvider.overrideWithValue(env),
        remoteBaseChangeProvider.overrideWith((ref) => change),
        activePlanProvider.overrideWith((ref) => Stream.value(null)),
      ]);

  Future<void> pickLongFast(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('rbc-preset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Long Fast').last);
    await tester.pumpAndSettle();
  }

  testWidgets('blocked without the base\'s grant', (tester) async {
    env.remoteAdminMobileNode = null;
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.byKey(const ValueKey('rbc-blocker')), findsOneWidget);
    expect(find.byKey(const ValueKey('rbc-apply')), findsNothing);
    await unmount(tester);
  });

  testWidgets('changes the base and shows the result', (tester) async {
    env.pingScript.add(PingStatus.received);
    await tester.pumpWidget(app());
    await settle(tester);
    await pickLongFast(tester);
    await tester.tap(find.byKey(const ValueKey('rbc-apply')));
    await settle(tester, 12);
    expect(env.remoteChanges, [('LONG_FAST', null)]);
    expect(find.text('Both nodes are on Long Fast and the base answered.'),
        findsOneWidget);
    await unmount(tester);
  });

  testWidgets('mid-session: asks, ends the session, offers a new one',
      (tester) async {
    final mapId = (await g.db.getAllCoverageMaps()).first.id;
    await tester
        .runAsync(() => env.startSession(coverageMapId: mapId, name: 'Walk'));
    env.pingScript.add(PingStatus.received);
    await tester.pumpWidget(app());
    await settle(tester);
    await pickLongFast(tester);
    await tester.tap(find.byKey(const ValueKey('rbc-apply')));
    await tester.pumpAndSettle();
    expect(find.text('A session is recording'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rbc-end-and-change')));
    await settle(tester, 12);
    expect(env.activeSession, isNull);
    expect(env.remoteChanges, hasLength(1));
    await scrollTo(tester, find.byKey(const ValueKey('rbc-new-session')));
    await tester.tap(find.byKey(const ValueKey('rbc-new-session')));
    await settle(tester);
    expect(env.startedNames.last, 'Walk · Long Fast');
    await unmount(tester);
  });

  testWidgets('mid-session: Cancel changes nothing', (tester) async {
    final mapId = (await g.db.getAllCoverageMaps()).first.id;
    await tester
        .runAsync(() => env.startSession(coverageMapId: mapId, name: 'Walk'));
    await tester.pumpWidget(app());
    await settle(tester);
    await pickLongFast(tester);
    await tester.tap(find.byKey(const ValueKey('rbc-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(env.activeSession, isNotNull);
    expect(env.remoteChanges, isEmpty);
    await unmount(tester);
  });

  testWidgets('without Pro the paywall opens and nothing is sent',
      (tester) async {
    await tester.pumpWidget(app(pro: false));
    await settle(tester);
    await pickLongFast(tester);
    await tester.tap(find.byKey(const ValueKey('rbc-apply')));
    await settle(tester);
    expect(
        find.textContaining('Change the base from a distance'), findsWidgets);
    expect(env.remoteChanges, isEmpty);
    await unmount(tester);
  });
}
