// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';

import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/diag_log.dart';

/// The user records (names and public keys) of our own radios, kept on the
/// phone so a radio that has lost one (node list cleared or reset) can be
/// given it back with AdminMessage.add_contact instead of waiting to hear
/// it over the air. Without the base's key, Meshtastic 2.7.19+ refuses to
/// send it a direct message (a local PKI_SEND_FAIL_PUBLIC_KEY NAK, nothing
/// transmitted), so pings fail.
class MeshtasticContacts {
  static const prefKey = 'radio_contacts_v1';

  final SharedPreferences _prefs;

  MeshtasticContacts(this._prefs);

  Map<String, dynamic> _all() {
    final raw = _prefs.getString(prefKey);
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// The saved user for [nodeNum], if any.
  pb.User? get(int nodeNum) {
    final b64 = _all()['$nodeNum'] as String?;
    if (b64 == null) return null;
    try {
      return pb.User.fromBuffer(base64Decode(b64));
    } catch (_) {
      return null;
    }
  }

  /// Remember [user] for [nodeNum]; only users with a public key are worth
  /// keeping. A key that differs from the saved one is only taken with
  /// [replaceKey]: the record came straight from that radio over the
  /// phone's own Bluetooth link (a reset radio has a new key). A different
  /// key heard over the air is logged and dropped (returns false), so a
  /// NodeInfo claiming our base's node number can't become the key we
  /// encrypt pings and remote admin to.
  Future<bool> save(int nodeNum, pb.User user,
      {bool replaceKey = false}) async {
    if (user.publicKey.length != 32) return false;
    final all = _all();
    final saved = get(nodeNum)?.publicKey;
    if (!replaceKey &&
        saved != null &&
        saved.length == 32 &&
        !_same(saved, user.publicKey)) {
      final msg = 'kept the saved key for node $nodeNum; ignored a '
          'different one (${_prefix(user.publicKey)} instead of '
          '${_prefix(saved)})';
      print('MeshtasticContacts: $msg');
      DiagLog.instance.log('contacts', msg);
      return false;
    }
    final b64 = base64Encode(user.writeToBuffer());
    if (all['$nodeNum'] == b64) return true;
    all['$nodeNum'] = b64;
    await _prefs.setString(prefKey, jsonEncode(all));
    return true;
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _prefix(List<int> key) =>
      '${key.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}…';
}
