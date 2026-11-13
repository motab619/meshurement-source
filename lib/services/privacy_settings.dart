// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../demo/demo_mode.dart';
import '../providers.dart';
import '../utils/constants.dart';

/// The three things that can leave the phone, each behind one switch
/// (Settings → Privacy). The map, terrain and AI code all read these.
///
/// Each value is the same pref the feature already used, so there is one
/// source of truth: map tiles `privacy_map_tiles_enabled` (default on),
/// terrain elevation `terrain_online_enabled` (default off), AI analysis
/// `ai_analysis_consent` (default off).
class PrivacyState {
  const PrivacyState({
    required this.mapTiles,
    required this.terrain,
    required this.aiConsent,
  });

  final bool mapTiles;
  final bool terrain;
  final bool aiConsent;

  factory PrivacyState.load(SharedPreferences prefs) => PrivacyState(
        mapTiles: AppConstants.mapTilesEnabled(prefs),
        terrain: AppConstants.terrainOnlineEnabled(prefs),
        aiConsent: prefs.getBool(AppConstants.prefAiConsent) ?? false,
      );

  PrivacyState copyWith({bool? mapTiles, bool? terrain, bool? aiConsent}) =>
      PrivacyState(
        mapTiles: mapTiles ?? this.mapTiles,
        terrain: terrain ?? this.terrain,
        aiConsent: aiConsent ?? this.aiConsent,
      );
}

class PrivacyNotifier extends Notifier<PrivacyState> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  PrivacyState build() =>
      PrivacyState.load(ref.watch(sharedPreferencesProvider));

  Future<void> setMapTiles(bool on) async {
    state = state.copyWith(mapTiles: on);
    await _prefs.setBool(AppConstants.prefMapTilesEnabled, on);
  }

  Future<void> setTerrain(bool on) async {
    state = state.copyWith(terrain: on);
    await _prefs.setBool(AppConstants.prefTerrainOnlineEnabled, on);
  }

  /// On = the user agreed to send session summaries; off revokes it, so the
  /// next analysis asks again.
  Future<void> setAiConsent(bool on) async {
    state = state.copyWith(aiConsent: on);
    await _prefs.setBool(AppConstants.prefAiConsent, on);
  }

  /// Deletes every saved AI answer (not the consent or the install id).
  Future<void> clearAiResults() async {
    for (final k in _prefs.getKeys().toList()) {
      if (k.startsWith(AppConstants.prefAiAnalysisPrefix) &&
          k != AppConstants.prefAiConsent) {
        await _prefs.remove(k);
      }
    }
  }
}

final privacyProvider =
    NotifierProvider<PrivacyNotifier, PrivacyState>(PrivacyNotifier.new);

/// Whether the maps may request tiles. Demo mode always does (screenshots).
final mapTilesEnabledProvider = Provider<bool>((ref) =>
    DemoMode.enabled || ref.watch(privacyProvider.select((s) => s.mapTiles)));
