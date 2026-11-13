// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/ui/widgets/connect_progress_view.dart';

void main() {
  final t0 = DateTime(2026, 10, 15, 12);

  ConnectProgress p(RadioConnectionState s, String step,
          {String? detail, double? fraction}) =>
      ConnectProgress(
          state: s,
          step: step,
          detail: detail,
          fraction: fraction,
          stepStartedAt: t0);

  test('pill shows node-list percentage when the total is known', () {
    expect(
        connectProgressLabel(
            p(RadioConnectionState.configuring, 'Downloading node list',
                detail: '87 of 142 nodes', fraction: 87 / 142),
            t0),
        'Nodes 61%');
  });

  test('pill shows a node count when the total is unknown', () {
    expect(
        connectProgressLabel(
            p(RadioConnectionState.configuring, 'Downloading node list',
                detail: '40 nodes'),
            t0),
        'Nodes 40');
  });

  test('pill adds elapsed seconds once a step is slow', () {
    final pairing = p(RadioConnectionState.pairing, 'Pairing');
    expect(connectProgressLabel(pairing, t0.add(const Duration(seconds: 2))),
        'Pairing…');
    expect(connectProgressLabel(pairing, t0.add(const Duration(seconds: 14))),
        'Pairing… 14s');
    expect(connectProgressLabel(null, t0), 'Connecting…');
  });
}
