// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

/// `Config.SecurityConfig.admin_key` holds at most this many keys
/// (config.proto: `repeated bytes admin_key = 3 [max_count = 3]`).
const int maxAdminKeys = 3;

/// The base's admin-key list is full and the new key isn't in it. Nothing
/// was dropped: the caller asks the user whether to replace [oldest] (or
/// skips the grant, the default).
class AdminKeyListFull implements Exception {
  /// The entry that would be replaced (the oldest one that isn't the
  /// radio's own key).
  final List<int> oldest;
  const AdminKeyListFull(this.oldest);

  /// "1a2b3c4d…", the way the app names a key.
  String get oldestHex => keyPrefixHex(oldest);

  @override
  String toString() => 'The base node already has $maxAdminKeys admin keys '
      '(oldest $oldestHex); none was replaced';
}

/// Asked when the admin list is full: true replaces the oldest key
/// (shown as its 4-byte prefix [oldestKey]), false skips the grant.
typedef ReplaceAdminKeyPrompt = Future<bool> Function(String oldestKey);

/// The admin-key list [existing] with [key] in it, or null when it is
/// already there (nothing to write).
///
/// A full list throws [AdminKeyListFull] and loses nothing, unless
/// [replaceOldest] is set: then its oldest entry that isn't [ownKey] (the
/// radio's own public key, which some clients add; firmware appends new
/// keys, so index 0 is the oldest) makes room. [onReplace] gets that key,
/// so the caller can log it.
List<List<int>>? adminKeysWith(
  List<List<int>> existing,
  List<int> key, {
  List<int>? ownKey,
  bool replaceOldest = false,
  void Function(List<int> replaced)? onReplace,
}) {
  if (key.length != 32) {
    throw ArgumentError.value(key.length, 'key', 'A public key is 32 bytes');
  }
  if (existing.any((k) => sameKey(k, key))) return null;
  final keys = [for (final k in existing) List<int>.of(k)];
  if (keys.length >= maxAdminKeys) {
    var victim = keys.indexWhere(
        (k) => ownKey == null || ownKey.length != 32 || !sameKey(k, ownKey));
    if (victim < 0) victim = 0;
    if (!replaceOldest) throw AdminKeyListFull(keys[victim]);
    onReplace?.call(keys[victim]);
    keys.removeAt(victim);
  }
  keys.add(List<int>.of(key));
  return keys;
}

/// The admin-key list [existing] without [key], or null when it isn't in
/// it (nothing to write). Firmware clears a key when a security set that
/// keeps the private key carries the shorter list (AdminModule.cpp
/// handleSetConfig, security case).
List<List<int>>? adminKeysWithout(List<List<int>> existing, List<int> key) {
  if (!existing.any((k) => sameKey(k, key))) return null;
  return [
    for (final k in existing)
      if (!sameKey(k, key)) List<int>.of(k),
  ];
}

/// Two admin-key lists hold the same keys in the same order.
bool sameKeyList(List<List<int>> a, List<List<int>> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!sameKey(a[i], b[i])) return false;
  }
  return true;
}

/// "1a2b3c4d…": the first 4 bytes of a key, for logs and the UI.
String keyPrefixHex(List<int> key) =>
    '${key.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}…';

bool sameKey(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// `!1a2b3c4d`, the Meshtastic way of naming a node by number.
String nodeIdHex(int nodeNum) =>
    '!${nodeNum.toRadixString(16).padLeft(8, '0')}';
