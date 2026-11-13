// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'platform_text.dart';

/// A non-2xx answer from a server we called (the AI analysis backend).
class HttpStatusException implements Exception {
  final int statusCode;

  /// The server's own explanation (its JSON `error` field), when it gave
  /// one; for logs and problem reports, not for the user-facing text.
  final String? reason;
  const HttpStatusException(this.statusCode, [this.reason]);

  @override
  String toString() => 'HttpStatusException($statusCode'
      '${reason == null ? '' : ': $reason'})';
}

/// Plain-English text for an error caught in the UI, so testers never see
/// "Bad state: ..." or a stack of Dart type names. [doing] is a short
/// phrase for the default message ("setting up the node").
String userMessage(Object error, {String? doing}) {
  if (error is TimeoutException) {
    return 'The node didn\'t answer in time. Make sure it\'s on and nearby, '
        'then try again.';
  }
  if (error is HttpStatusException) {
    final c = error.statusCode;
    if (c == 429) return 'Daily limit reached. Try again tomorrow.';
    if (c >= 500) {
      return 'The analysis service is having trouble. Try again in a few '
          'minutes.';
    }
    if (c == 413 || c == 400) {
      return 'The service could not use this comparison. Try another one.';
    }
    return 'The analysis service refused the request (HTTP $c).';
  }
  if (error is SocketException) return 'No internet connection.';
  if (error is PlatformException) {
    final text = '${error.code} ${error.message ?? ''}'.toLowerCase();
    // Android 11 and older: a Bluetooth scan needs Location on and the
    // location permission (flutter_blue_plus startScan asks for it and
    // fails with these texts).
    if (text.contains('location services')) {
      return 'Location is off. Android needs it on to find Bluetooth '
          'radios: turn it on in the quick settings, then try again.';
    }
    if (text.contains('location')) {
      return 'Location permission is off. Android needs it to find '
          'Bluetooth radios: allow it in '
          '${PlatformText.appPermission('Location')}.';
    }
    if (text.contains('permission') || text.contains('unauthorized')) {
      return 'Bluetooth permission is off. Turn it on in '
          '${PlatformText.appPermission('Bluetooth', androidLeaf: 'Nearby devices')}.';
    }
    if (text.contains('powered') ||
        text.contains('bluetooth is off') ||
        text.contains('must be turned on') ||
        text.contains('adapter')) {
      return 'Bluetooth is off. Turn it on and try again.';
    }
    if (text.contains('disconnect') || text.contains('connection')) {
      return 'The Bluetooth link to your node dropped. Try again.';
    }
    return 'Bluetooth problem. Make sure the node is on and nearby, then '
        'try again.';
  }
  final raw = _stripPrefix(error.toString());
  final lower = raw.toLowerCase();
  if (isLostBondError(raw)) {
    if (PlatformText.isAndroid) {
      return 'The phone still has an old pairing for this node (it was '
          'reset, re-flashed or updated, and forgot the phone), or the PIN '
          'was wrong. Open ${PlatformText.bluetoothDevices}, tap the gear '
          'next to the node, Unpair (Forget), then connect again.';
    }
    return 'iOS still has an old pairing for this node (it was reset, '
        're-flashed or updated, and forgot the phone). Open iOS Settings → '
        'Bluetooth, tap ⓘ next to the node, Forget This Device, then '
        'connect again.';
  }
  if (error is StateError && lower.contains('rejected')) {
    // "Radio rejected setting: NOT_AUTHORIZED" -> keep the short reason;
    // a worded reason ("relaying is not allowed on ...") is kept as written.
    final colon = raw.indexOf(': ');
    final reason = colon < 0 ? '' : raw.substring(colon + 2).trim();
    if (reason.isEmpty) return 'The node refused that setting.';
    if (RegExp(r'^[A-Z0-9_]+$').hasMatch(reason)) {
      return 'The node refused that setting '
          '(${reason.toLowerCase().replaceAll('_', ' ')}).';
    }
    if (reason.contains(' ')) {
      return 'The node refused that setting. '
          '${_sentence(reason[0].toUpperCase() + reason.substring(1))}';
    }
    return 'The node refused that setting ($reason).';
  }
  if (lower.contains('not ready') ||
      lower.contains('not connected') ||
      lower.contains('connect to your radio first') ||
      lower.contains('connect to your node first')) {
    return 'Connect to your node first.';
  }
  if (lower.contains('socket') ||
      lower.contains('network') ||
      lower.contains('failed host lookup')) {
    return 'No internet connection.';
  }
  // A message written for people (the services throw StateErrors and
  // exceptions like PlanError with a full sentence): show it as written.
  // Programmer errors (ArgumentError, RangeError...) and exceptions whose
  // text starts with their type name ("FormatException: ...") never pass.
  if (error is StateError || (error is Exception && error is! Error)) {
    if (isUserSentence(raw)) return _sentence(raw);
  }
  final what = doing == null ? '' : ' while $doing';
  return 'Something went wrong$what. Try again; if it keeps happening, '
      'send us the details from Settings → About.';
}

/// A Bluetooth connect refused because the phone's pairing record no
/// longer matches the radio's: CoreBluetooth code 14 "Peer removed pairing
/// information", or an encryption/authentication failure. Retrying never
/// helps; only "Forget This Device" does. Seen after flashing a Heltec V3
/// to firmware 2.8 (it purges old-format bonds on first boot).
bool isLostBondError(Object error) {
  // Android (flutter_blue_plus) names the same failures in upper snake
  // case: GATT_INSUFFICIENT_AUTHENTICATION / _ENCRYPTION, GATT_AUTH_FAIL,
  // and the HCI disconnect reasons PIN_OR_KEY_MISSING / AUTHENTICATION_FAILURE.
  final t = error.toString().toLowerCase().replaceAll('_', ' ');
  return t.contains('peer removed pairing') ||
      // CoreBluetooth 14 = peer removed pairing; Android's 14 is unrelated.
      (t.contains('code: 14') && !t.contains('android-code')) ||
      t.contains('insufficient authentication') ||
      t.contains('insufficient encryption') ||
      t.contains('authentication failed') ||
      t.contains('authentication failure') ||
      t.contains('gatt auth fail') ||
      t.contains('pin or key missing');
}

/// Dart's own [StateError] texts: sentences, but not for people.
const _internalStateErrors = [
  'No element',
  'Too many elements',
  'Too few elements',
  'Cannot add',
  'Cannot close',
  'Stream has already',
  'Future already completed',
  'Cannot fire',
  'Cannot listen',
];

/// True when [text] reads as a sentence written for the user: it starts
/// with a capital letter, has a space, and is not a "TypeName: ..." dump
/// or one of Dart's own state errors.
bool isUserSentence(String text) {
  final t = text.trim();
  if (t.length < 4 || !t.contains(' ')) return false;
  if (!RegExp(r'^[A-Z]').hasMatch(t)) return false;
  if (RegExp(r'^[A-Za-z_]\w*(Exception|Error)\b').hasMatch(t)) return false;
  if (t.startsWith('Instance of')) return false;
  for (final p in _internalStateErrors) {
    if (t.startsWith(p)) return false;
  }
  return true;
}

/// [s] with a closing full stop when it has none.
String _sentence(String s) {
  final t = s.trim();
  return RegExp(r'[.!?]$').hasMatch(t) ? t : '$t.';
}

String _stripPrefix(String s) =>
    s.replaceFirst(RegExp(r'^(Bad state|Exception|Error): '), '');

/// "!abcd": the short form of a radio's id, for radios with no name.
String shortNodeId(int nodeNum) =>
    '!${nodeNum.toRadixString(16).padLeft(8, '0').substring(4)}';
