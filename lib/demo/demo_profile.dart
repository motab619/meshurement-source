// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:latlong2/latlong.dart';

import '../services/terrain/elevation_source.dart';
import 'demo_site.dart';

/// Demo base position of the current demo site.
LatLng get demoBase => DemoSite.current.base;

/// Point used for the `-demoScreen profile` screenshot.
LatLng demoProfileTarget() => DemoSite.current.profileTarget();

/// Offline terrain for demo mode (real terrain for the Cove, a synthetic
/// hill for the polo grounds).
ElevationSource demoElevationSource() => DemoSite.current.elevation();
