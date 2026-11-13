// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/radio/radio_types.dart';
import 'radio_roles.dart';

/// The radio the phone was last connected to, so a session resumed after
/// the app was killed can reconnect to it on its own.
class LastRadio {
  /// SharedPreferences key: JSON `{id, name, protocol}`.
  static const prefKey = 'last_radio_id';

  final SharedPreferences _prefs;
  LastRadio(this._prefs);

  /// Remember [radio] (called on every successful connect).
  Future<void> save(RadioDescriptor radio) async {
    if (radio.id.isEmpty) return;
    await _prefs.setString(
      prefKey,
      jsonEncode({
        'id': radio.id,
        'name': radio.name,
        'protocol': radio.protocol.name,
      }),
    );
  }

  /// The last connected radio; falls back to the mobile radio's Bluetooth
  /// id from Radio Setup. Null if neither is known.
  /// The base is never chosen while the mobile is known (recording runs
  /// through the mobile).
  RadioDescriptor? load() {
    final roles = RadioRoles(_prefs);
    final mobile = roles.deviceOf(RadioRole.mobile);
    final raw = _prefs.getString(prefKey);
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        final id = m['id'] as String? ?? '';
        final isBase = id == roles.deviceOf(RadioRole.base);
        if (id.isNotEmpty && !(isBase && mobile != null && mobile.isNotEmpty)) {
          return RadioDescriptor(
            id: id,
            name: m['name'] as String? ?? '',
            protocol: RadioProtocol.values.firstWhere(
              (p) => p.name == m['protocol'],
              orElse: () => RadioProtocol.meshtastic,
            ),
          );
        }
      } catch (_) {
        // Corrupt value: fall through.
      }
    }
    if (mobile == null || mobile.isEmpty) return null;
    return RadioDescriptor(id: mobile, name: 'Mobile node');
  }

  /// Bluetooth ids of this app's own radios (the last connected one and
  /// the Radio Setup base and mobile), with the protocol when it is known
  /// (null: tell by the Bluetooth name). For the Android connect list,
  /// which can only show system-connected radios it already knows.
  Map<String, RadioProtocol?> knownRadios() {
    final roles = RadioRoles(_prefs);
    final known = <String, RadioProtocol?>{
      for (final r in RadioRole.values)
        if (roles.deviceOf(r) case final id? when id.isNotEmpty) id: null,
    };
    final raw = _prefs.getString(prefKey);
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        final id = m['id'] as String? ?? '';
        if (id.isNotEmpty) {
          known[id] = RadioProtocol.values
              .where((p) => p.name == m['protocol'])
              .firstOrNull;
        }
      } catch (_) {
        // Corrupt value: roles only.
      }
    }
    return known;
  }
}
