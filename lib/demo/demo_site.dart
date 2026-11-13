// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:latlong2/latlong.dart';

import '../services/terrain/elevation_source.dart';
import '../services/terrain/geo.dart';
import 'cove_data.dart';
import 'cove_terrain.dart';
import 'demo_mode.dart';
import 'demo_walk.dart';
import 'grid_elevation.dart';
import 'synthetic_elevation.dart';

/// One more finished session on a demo site's map.
class DemoExtraSession {
  const DemoExtraSession({
    required this.name,
    required this.rows,
    required this.daysAgo,
  });

  final String name;
  final List<DemoRow> rows;
  final int daysAgo;
}

/// Where demo mode's pretend test took place and what it recorded.
///
/// Picked with `-demoSite cove|polo` (or MESH_DEMO_SITE); [cove] is the
/// default. The first session ([live]) is the one recording; the second
/// ([secondLapName], with [secondLap] rows or, when null, made from [live]
/// with a few dB more) is side B of Compare.
class DemoSite {
  const DemoSite({
    required this.id,
    required this.base,
    required this.baseName,
    required this.mobileName,
    required this.mobileShort,
    required this.mapName,
    required this.mapDescription,
    required this.liveName,
    required this.live,
    required this.secondLapName,
    this.secondLap,
    this.extra = const [],
    required this.elevation,
    required this.profileTarget,
  });

  final String id;
  final LatLng base;
  final String baseName;
  final String mobileName;
  final String mobileShort;
  final String mapName;
  final String mapDescription;
  final String liveName;
  final List<DemoRow> live;
  final String secondLapName;
  final List<DemoRow>? secondLap;
  final List<DemoExtraSession> extra;
  final ElevationSource Function() elevation;

  /// Point for the `-demoScreen profile` screenshot.
  final LatLng Function() profileTarget;

  static DemoSite get current => DemoMode.site == polo.id ? polo : cove;

  /// The original demo: a real 19-minute walk (two T1000-Es, Medium Fast)
  /// moved to the Empire Polo Club, Indio.
  static const polo = DemoSite(
    id: 'polo',
    base: LatLng(demoBaseLat, demoBaseLon),
    baseName: 'Polo Field Base',
    mobileName: 'Walker',
    mobileShort: 'WLKR',
    mapName: 'Empire Polo – Medium Fast',
    mapDescription: 'Base on the polo grounds, walking the perimeter',
    liveName: 'Around the polo fields',
    live: demoWalk,
    secondLapName: 'Second lap, 5.8 dBi whip',
    elevation: _poloElevation,
    profileTarget: _poloProfileTarget,
  );

  /// La Quinta Cove (2026-11-06): readings computed from real terrain by
  /// tool/demo_site/gen_cove.py. Base at the Cove Oasis trailhead; a drive
  /// through the Cove and behind the east ridge (stubby, then whip) and a
  /// walk into the canyon.
  static const cove = DemoSite(
    id: 'cove',
    base: LatLng(coveBaseLat, coveBaseLon),
    baseName: 'Cove Trailhead Base',
    mobileName: 'Rover',
    mobileShort: 'ROVR',
    mapName: 'La Quinta Cove – Medium Fast',
    mapDescription: 'Base on a tripod at the Cove Oasis trailhead',
    liveName: 'Cove drive, stock stubby',
    live: coveDriveStubby,
    secondLapName: 'Cove drive, 5.8 dBi whip',
    secondLap: coveDriveWhip,
    extra: [
      DemoExtraSession(
          name: 'Canyon walk', rows: coveCanyonWalk, daysAgo: 1),
    ],
    elevation: _coveElevation,
    profileTarget: _coveProfileTarget,
  );
}

/// Received reading of the polo walk closest to 1 km from the base.
LatLng _poloProfileTarget() {
  const base = LatLng(demoBaseLat, demoBaseLon);
  DemoRow? best;
  var bestErr = double.infinity;
  for (final r in demoWalk) {
    if (r.rssi == null || r.direction == 'tx') continue;
    final d = greatCircleDistanceM(base, LatLng(r.lat, r.lon));
    final err = (d - 1000).abs();
    if (err < bestErr) {
      bestErr = err;
      best = r;
    }
  }
  return LatLng(best!.lat, best.lon);
}

/// Rolling ground with one hill about 40 % of the way to the profile target.
ElevationSource _poloElevation() {
  const base = LatLng(demoBaseLat, demoBaseLon);
  return SyntheticElevationSource(
    hillCenter: greatCircleInterpolate(base, _poloProfileTarget(), 0.4),
    hillHeightM: 11,
  );
}

GridElevationSource? _coveGrid;

ElevationSource _coveElevation() => _coveGrid ??= GridElevationSource(
      north: coveTerrainNorth,
      west: coveTerrainWest,
      stepDeg: coveTerrainStepDeg,
      rows: coveTerrainRows,
      cols: coveTerrainCols,
      base64Data: coveTerrainB64,
      label: 'USGS 3DEP (bundled, demo)',
    );

LatLng _coveProfileTarget() => const LatLng(coveProfileLat, coveProfileLon);
