// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../services/coverage_interpolation.dart';
import 'signal_color_mapper.dart';

/// Turns an interpolated [CoverageGrid] into a PNG, one pixel per cell,
/// coloured with the same [SignalColorMapper] scale as the measured dots.
/// Non-RSSI grids hold link margins (`linkMarginDb`, interpolated per
/// sample so sessions on different presets blend on one scale) and are
/// coloured with [SignalColorMapper.fromMargin].
/// The map layer scales it up with bilinear filtering, so cells blend
/// smoothly. Transparent cells stay transparent (alpha fades the edges).
Future<ImageProvider> coverageGridImage(
  CoverageGrid grid, {
  required bool rssi,
}) async {
  final w = grid.cols, h = grid.rows;
  final pixels = Uint8List(w * h * 4);
  for (var row = 0; row < h; row++) {
    // Grid rows run south → north; images run top → bottom.
    final dstRow = h - 1 - row;
    for (var col = 0; col < w; col++) {
      final a = grid.alpha[row * w + col];
      if (a <= 0) continue;
      final v = grid.values[row * w + col];
      final color = rssi
          ? SignalColorMapper.fromRssi(v.round())
          : SignalColorMapper.fromMargin(v);
      final o = (dstRow * w + col) * 4;
      pixels[o] = (color.r * 255).round();
      pixels[o + 1] = (color.g * 255).round();
      pixels[o + 2] = (color.b * 255).round();
      pixels[o + 3] = (a * 255).round();
    }
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, w, h, ui.PixelFormat.rgba8888, done.complete);
  final image = await done.future;
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return MemoryImage(png!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

/// Diverging scale for rig comparison deltas (B minus A): blue where B is
/// better, orange where A is better, neutral grey at 0. Colour-blind safe
/// (no red/green). Symmetric, clamped at +-[clamp] dB.
const comparisonBetterBColor = ui.Color(0xFF1F6FEB);
const comparisonBetterAColor = ui.Color(0xFFE8710A);
const comparisonNeutralColor = ui.Color(0xFFBDBDBD);

ui.Color comparisonDeltaColor(double delta, double clamp) {
  final t = (delta / clamp).clamp(-1.0, 1.0);
  return ui.Color.lerp(
    comparisonNeutralColor,
    t >= 0 ? comparisonBetterBColor : comparisonBetterAColor,
    t.abs(),
  )!;
}

/// Three-way "who wins" colour for a delta (B minus A): blue when B is
/// better by at least [threshold] dB, orange when A is, grey otherwise.
ui.Color comparisonWinnerColor(double delta, double threshold) {
  if (delta >= threshold) return comparisonBetterBColor;
  if (delta <= -threshold) return comparisonBetterAColor;
  return comparisonNeutralColor;
}
