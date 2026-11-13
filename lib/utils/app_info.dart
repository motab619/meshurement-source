// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

/// The app's name and website: the one place to change them.
///
/// Every user-facing mention of the app (About, paywall, onboarding, share
/// subjects, exports, the Field Report card, the name sent to MeshCore
/// radios) reads it from here. The home-screen name is `CFBundleDisplayName`
/// in ios/Runner/Info.plist and ios/MeshActivity/Info.plist, which must match.
/// Renamed from Mesh Analyzer on 2026-11-05; the bundle ID, StoreKit product
/// IDs, database file names and the `.mabackup` format keep the old slug.
class AppInfo {
  AppInfo._();

  static const displayName = 'Meshurement';
  static const website = 'meshurement.com';

  /// The subscription's name in the app (matches the App Store product).
  static const proName = '$displayName Pro';
}
