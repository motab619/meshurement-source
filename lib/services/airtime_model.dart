// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math';

import '../data/radio/radio_preset.dart';
import '../data/radio/radio_types.dart' show RadioProtocol;

/// LoRa modulation for a modem preset.
class LoraParams {
  final int sf;
  final double bwKHz;

  /// Coding-rate denominator: 5 means 4/5, 8 means 4/8.
  final int cr;

  const LoraParams(this.sf, this.bwKHz, this.cr);

  /// One symbol, in milliseconds.
  double get symbolMs => pow(2, sf) / bwKHz;
}

/// How long packets take on air for each modem preset, and the shortest
/// ping interval that keeps our radio under a target duty cycle.
///
/// Preset parameters live with each protocol (see `MeshtasticPresets`).
/// Airtime is the Semtech SX126x formula with Meshtastic's 16-symbol
/// preamble, explicit header and CRC on.
class AirtimeModel {
  AirtimeModel._();

  static const preambleSymbols = 16;

  /// Bytes on air for one of our pings: 16-byte Meshtastic header +
  /// encoded Data (portnum, 'ping', want_response…) + 12 bytes of PKI
  /// overhead (auth tag + extra nonce) for a direct message.
  static const pingPacketBytes = 40;

  /// Bytes on air for a MeshCore trace ping and its return
  /// (`docs/design/meshcore.md` §7c: header, tag, auth, flags and a 4-byte
  /// base key prefix out; the same plus the base's SNR byte back).
  static const traceOutBytes = 15;
  static const traceBackBytes = 16;

  /// Bytes on air for one Meshtastic base beacon: 16-byte header + Data
  /// carrying a DeviceMetrics telemetry (time, battery, voltage, channel
  /// use, airtime, uptime; about 32 bytes). A Range Test `seq N` is
  /// smaller, so this is the upper of the two. Channel-encrypted
  /// broadcast: no PKI overhead.
  static const beaconPacketBytes = 48;

  /// Duty cycle we keep pings under.
  static const targetDuty = 0.05;

  /// Never ping more often than this, even on the fastest presets.
  static const minIntervalFloorSec = 5;

  /// With "Faster than recommended" on: never below this.
  static const overrideFloorSec = 2;

  /// Amber warning in the session HUD above this duty (last 60 s).
  static const warnDuty = 0.04;

  /// Meshtastic firmware's "polite" channel-utilization gate (percent):
  /// above this, optional traffic (telemetry, NodeInfo...) is skipped
  /// (airtime.h `polite_channel_util_percent`). Amber in the UI.
  static const channelPoliteLimitPercent = 25.0;

  /// The numbers used when the radio's modulation isn't known yet
  /// (Meshtastic's LONG_FAST: SF11 / 250 kHz / 4/5).
  static const defaultPreset = RadioPreset(
      id: 'LONG_FAST', displayName: 'Long Fast', sf: 11, bwKHz: 250, cr: 5);

  /// Modulation of [preset].
  static LoraParams paramsFor(RadioPreset preset) =>
      LoraParams(preset.sf, preset.bwKHz, preset.cr);

  /// Time on air for one packet of [payloadBytes], in milliseconds.
  static double airtimeMs(LoraParams p, {int payloadBytes = pingPacketBytes}) {
    final tSym = p.symbolMs;
    final preambleMs = (preambleSymbols + 4.25) * tSym;
    final lowDataRateOptimize = tSym > 16 ? 1 : 0;
    const crcOn = 1, implicitHeader = 0;
    final numerator =
        8 * payloadBytes - 4 * p.sf + 28 + 16 * crcOn - 20 * implicitHeader;
    final denominator = 4 * (p.sf - 2 * lowDataRateOptimize);
    final payloadSymbols = 8 + max((numerator / denominator).ceil() * p.cr, 0);
    return preambleMs + payloadSymbols * tSym;
  }

  /// Airtime of one base beacon: a Meshtastic beacon packet
  /// ([beaconPacketBytes]), or on MeshCore the trace exchange the mobile
  /// pulls ([traceAirtimeMs]). [defaultPreset] when the modulation isn't
  /// known yet.
  static double beaconAirtimeMsFor(RadioPreset? preset,
          {RadioProtocol protocol = RadioProtocol.meshtastic}) =>
      protocol == RadioProtocol.meshcore
          ? traceAirtimeMs(preset ?? defaultPreset)
          : airtimeMs(paramsFor(preset ?? defaultPreset),
              payloadBytes: beaconPacketBytes);

  /// Airtime of one ping on [preset], in milliseconds.
  static double pingAirtimeMs(RadioPreset preset) =>
      airtimeMs(paramsFor(preset));

  /// Airtime of one whole trace exchange on [preset] (our 15-byte trace
  /// out plus the base's 16-byte return), in milliseconds. Both legs
  /// count: the base's reply takes the same channel.
  static double traceAirtimeMs(RadioPreset preset) =>
      airtimeMs(paramsFor(preset), payloadBytes: traceOutBytes) +
      airtimeMs(paramsFor(preset), payloadBytes: traceBackBytes);

  /// Airtime the duty budget charges per ping on [protocol]: a Meshtastic
  /// DM ping (our transmission only) or a MeshCore trace exchange (both
  /// legs). [defaultPreset] when the modulation isn't known yet.
  static double probeAirtimeMsFor(RadioPreset? preset,
          {RadioProtocol protocol = RadioProtocol.meshtastic}) =>
      protocol == RadioProtocol.meshcore
          ? traceAirtimeMs(preset ?? defaultPreset)
          : pingAirtimeMsFor(preset);

  /// Shortest ping interval (whole seconds) that keeps one ping per
  /// interval under [duty]; never below [minIntervalFloorSec].
  static int minIntervalSec(
    RadioPreset preset, {
    double duty = targetDuty,
  }) =>
      minIntervalForAirtime(pingAirtimeMs(preset), duty: duty);

  static int minIntervalForAirtime(double airtimeMs,
          {double duty = targetDuty}) =>
      max(minIntervalFloorSec, (airtimeMs / 1000 / duty).ceil());

  /// The interval to use: [requested] if the preset allows it, otherwise
  /// the preset's minimum.
  static int clampInterval(int requested, RadioPreset preset) =>
      max(requested, minIntervalSec(preset));

  /// Airtime of one ping with a radio's actual modulation; [defaultPreset]
  /// when it isn't known yet.
  static double pingAirtimeMsFor(RadioPreset? preset) =>
      pingAirtimeMs(preset ?? defaultPreset);

  /// Shortest allowed ping interval for a radio's modulation. With
  /// [override] ("Faster than recommended") the airtime budget is ignored
  /// and only [fastestIntervalSecFor] applies.
  ///
  /// [protocol] picks what one ping costs ([probeAirtimeMsFor]).
  static int minIntervalSecFor(RadioPreset? preset,
          {bool override = false,
          RadioProtocol protocol = RadioProtocol.meshtastic}) =>
      override
          ? fastestIntervalSecFor(preset, protocol: protocol)
          : minIntervalForAirtime(
              probeAirtimeMsFor(preset, protocol: protocol));

  /// Physical limit: time for the ping and the base's reply to go out (two
  /// ping airtimes; a MeshCore trace exchange already counts both legs)
  /// plus a second's margin, never under [overrideFloorSec].
  static int fastestIntervalSecFor(RadioPreset? preset,
      {RadioProtocol protocol = RadioProtocol.meshtastic}) {
    final exchangeMs = protocol == RadioProtocol.meshcore
        ? probeAirtimeMsFor(preset, protocol: protocol)
        : 2 * pingAirtimeMsFor(preset);
    return max(overrideFloorSec, (exchangeMs / 1000).ceil() + 1);
  }

  /// Share of airtime one ping every [intervalSec] uses (0..1).
  static double dutyFor(RadioPreset? preset, int intervalSec,
          {RadioProtocol protocol = RadioProtocol.meshtastic}) =>
      intervalSec <= 0
          ? 0
          : probeAirtimeMsFor(preset, protocol: protocol) / 1000 / intervalSec;
}
