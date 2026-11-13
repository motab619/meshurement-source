// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'path_loss_model.dart';
import 'terrain_profile.dart';

/// How a profile reads to a person.
enum LosKind { clear, partial, blocked }

/// Plain-language result for a [TerrainProfile].
class LosVerdict {
  const LosVerdict(this.kind, this.text, {this.obstructionIndex});

  final LosKind kind;
  final String text;

  /// Index of the profile sample that limits the path (null if none).
  final int? obstructionIndex;
}

/// Verdict rules.
///
/// The engine's raw classification ([PathClass]) is deliberately strict: at
/// low antenna heights a path longer than a few hundred metres has a first
/// Fresnel radius of several metres, so even flat ground "intrudes" into the
/// zone. Telling users every flat path is "partly blocked" would be noise,
/// so the app words it by cause:
///
/// 1. **Blocked**: the line of sight itself is below the (earth-bulged)
///    ground at some interior sample (clearance < 0). The text names the
///    lowest-clearance sample. If that sample's ground is not
///    [terrainRiseMinM] above the straight ground line between the two end
///    points, the cause is the earth's curvature, not terrain, and the text
///    says so.
/// 2. **Partly blocked**: no blockage, but clearance is under 60 % of the
///    first Fresnel radius (the usual design target) at a sample where the
///    terrain rises at least [terrainRiseMinM] above that straight ground
///    line. Terrain really is intruding on the zone.
/// 3. **Clear**: everything else, including flat or gently rolling ground
///    where only the Fresnel zone grazes the surface.
///
/// [terrainRiseMinM] (3 m) is about the vertical noise of the 30 m SRTM data.
class LosVerdictRules {
  LosVerdictRules._();

  static const double terrainRiseMinM = 3.0;

  /// Height of sample [i]'s ground above the straight line between the
  /// ground under the base and under the target.
  static double terrainRiseM(TerrainProfile p, int i) {
    final s = p.samples;
    final total = p.distanceM;
    final t = total > 0 ? s[i].distanceM / total : 0.0;
    final line = s.first.groundM + (s.last.groundM - s.first.groundM) * t;
    return s[i].groundM - line;
  }

  static String _dist(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(2)} km' : '${m.round()} m';

  static LosVerdict evaluate(TerrainProfile p) {
    final s = p.samples;
    if (s.length < 3 || p.worstIndex < 0) {
      return const LosVerdict(LosKind.clear, 'Clear line of sight');
    }
    var minClr = double.infinity, minI = -1;
    for (var i = 1; i < s.length - 1; i++) {
      if (s[i].clearanceM < minClr) {
        minClr = s[i].clearanceM;
        minI = i;
      }
    }
    if (minClr < 0) {
      final at = _dist(s[minI].distanceM);
      if (terrainRiseM(p, minI) >= terrainRiseMinM) {
        return LosVerdict(
          LosKind.blocked,
          'Blocked by terrain at $at (ridge ${s[minI].groundM.round()} m)',
          obstructionIndex: minI,
        );
      }
      return LosVerdict(
        LosKind.blocked,
        "Blocked by the earth's curvature around $at "
        '(raise an antenna or shorten the path)',
        obstructionIndex: minI,
      );
    }
    var worstRatio = double.infinity, worstI = -1;
    for (var i = 1; i < s.length - 1; i++) {
      if (isObstruction(p, i) && s[i].clearanceRatio < worstRatio) {
        worstRatio = s[i].clearanceRatio;
        worstI = i;
      }
    }
    if (worstI >= 0) {
      return LosVerdict(
        LosKind.partial,
        'Partly blocked (Fresnel zone) — expect weaker signal',
        obstructionIndex: worstI,
      );
    }
    return const LosVerdict(LosKind.clear, 'Clear line of sight');
  }

  /// True for samples the chart marks as obstructions: clearance below zero,
  /// or terrain-caused clearance under 60 % of F1.
  static bool isObstruction(TerrainProfile p, int i) {
    if (i <= 0 || i >= p.samples.length - 1) return false;
    final s = p.samples[i];
    return s.clearanceM < 0 ||
        (s.clearanceRatio < PathLossModel.clearThreshold &&
            terrainRiseM(p, i) >= terrainRiseMinM);
  }
}
