// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/bench/bench_mode.dart';

// The argument lists below are what AppDelegate hands over from
// `devicectl process launch` and what MainActivity.launchArgumentsOf builds
// from Intent extras (`--ez MeshBench true --ei benchPort 9000`).
void main() {
  group('BenchMode.parseArguments', () {
    test('off without -MeshBench, default port', () {
      final r = BenchMode.parseArguments(const ['-MeshDemo', '-demoScreen', 'map']);
      expect(r.enabled, isFalse);
      expect(r.port, BenchMode.defaultPort);
    });

    test('on with the bare flag (Android --ez MeshBench true)', () {
      final r = BenchMode.parseArguments(const ['-MeshBench']);
      expect(r.enabled, isTrue);
      expect(r.port, 8765);
    });

    test('port from -benchPort (Android --ei benchPort 9000)', () {
      final r = BenchMode.parseArguments(const ['-MeshBench', '-benchPort', '9000']);
      expect(r.port, 9000);
    });

    test('demo and bench flags can share one list', () {
      final r = BenchMode.parseArguments(
          const ['-MeshDemo', '-demoScreen', 'map', '-MeshBench', '-benchPort', '8766']);
      expect(r.enabled, isTrue);
      expect(r.port, 8766);
    });

    test('malformed or missing port keeps the default', () {
      expect(BenchMode.parseArguments(const ['-MeshBench', '-benchPort']).port, 8765);
      expect(BenchMode.parseArguments(const ['-MeshBench', '-benchPort', 'x']).port, 8765);
      expect(BenchMode.parseArguments(const ['-MeshBench', '-benchPort', '0']).port, 8765);
      expect(BenchMode.parseArguments(const ['-MeshBench', '-benchPort', '70000']).port, 8765);
    });
  });
}
