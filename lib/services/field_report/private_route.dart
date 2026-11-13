// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'field_report_data.dart';

/// The route as the card draws it, made safe to post: metres from the
/// origin (no coordinates), turned by a fixed angle per session so the
/// shape can't be laid over a street map, and nothing within the hidden
/// radius of the base. There are never street tiles under it.

/// Shared-preferences key for the sheet's Route choice ([showPathByDefault]
/// when unset): draw the path, or only the readings' points.
const reportShowPathPref = 'field_report_show_path';
const showPathByDefault = true;

/// Default "Hide base area" radius.
const defaultHideRadiusM = 120.0;

/// The fixed rotation (radians) for a session: the same every time it is
/// shared, so two shares can't be compared to undo it.
double reportRotation(int seed) => math.Random(seed).nextDouble() * 2 * math.pi;

class RoutePoint {
  final double x, y;
  const RoutePoint(this.x, this.y);
}

class RouteDot extends RoutePoint {
  final double marginDb;
  const RouteDot(super.x, super.y, this.marginDb);
}

class PrivateRoute {
  /// Track pieces; the line breaks where it entered the hidden area.
  final List<List<RoutePoint>> segments;
  final List<RouteDot> dots;
  final double hideRadiusM;

  /// What sits at (0, 0): the base, or where the session started.
  final ReportOrigin origin;

  const PrivateRoute({
    required this.segments,
    required this.dots,
    required this.hideRadiusM,
    required this.origin,
  });

  bool get isEmpty => dots.isEmpty && segments.every((s) => s.isEmpty);

  /// Every drawn point (and the hidden area, so it is in view).
  Iterable<RoutePoint> get extent sync* {
    for (final s in segments) {
      yield* s;
    }
    yield* dots;
    if (origin != ReportOrigin.none) {
      final r = hideRadiusM;
      yield RoutePoint(-r, -r);
      yield RoutePoint(r, r);
    }
  }

  /// [showPath] false leaves the track line out (no [segments]): only the
  /// readings' dots are drawn, so the line can't be matched to roads.
  factory PrivateRoute.of(FieldReportData d,
      {required double hideRadiusM,
      double? rotation,
      bool showPath = showPathByDefault}) {
    final a = rotation ?? reportRotation(d.rotationSeed);
    final c = math.cos(a), s = math.sin(a);
    final r = hideRadiusM;
    bool hidden(ReportFix f) => r > 0 && f.distanceM < r;
    RoutePoint turn(ReportFix f) =>
        RoutePoint(f.x * c - f.y * s, f.x * s + f.y * c);

    final segments = <List<RoutePoint>>[];
    var current = <RoutePoint>[];
    for (final f in showPath ? d.track : const <ReportFix>[]) {
      if (hidden(f)) {
        if (current.isNotEmpty) segments.add(current);
        current = [];
        continue;
      }
      current.add(turn(f));
    }
    if (current.isNotEmpty) segments.add(current);

    final dots = [
      for (final p in d.samples)
        if (!hidden(p))
          () {
            final t = turn(p);
            return RouteDot(t.x, t.y, p.marginDb);
          }(),
    ];
    return PrivateRoute(
      segments: segments,
      dots: dots,
      hideRadiusM: r,
      origin: d.origin,
    );
  }
}
