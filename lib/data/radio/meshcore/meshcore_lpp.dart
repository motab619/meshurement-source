// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:typed_data';

/// A GPS reading from a Cayenne LPP buffer.
typedef LppGps = ({double latitude, double longitude, double altitudeM});

/// Cayenne LPP as MeshCore writes it (fw:src/helpers/sensors/
/// LPPDataHelpers.h@81dbae5): `[channel][type][value…]`, big-endian.
/// Data sizes per type; a type not listed ends the walk (its size is
/// unknown, so nothing after it can be read).
const Map<int, int> _lppSizes = {
  0: 1, // digital input
  1: 1, // digital output
  2: 2, // analog input
  3: 2, // analog output
  100: 4, // generic sensor
  101: 2, // luminosity
  102: 1, // presence
  103: 2, // temperature
  104: 1, // humidity
  113: 6, // accelerometer
  115: 2, // barometric pressure
  116: 2, // voltage
  117: 2, // current
  118: 4, // frequency
  120: 1, // percentage
  121: 2, // altitude
  125: 2, // concentration
  128: 2, // power
  130: 4, // distance
  131: 4, // energy
  132: 2, // direction
  133: 4, // unix time
  134: 6, // gyrometer
  135: 3, // colour
  136: 9, // GPS: lat, lon (0.0001°), alt (0.01 m), 3 bytes signed each
  142: 1, // switch
};

const lppTypeGps = 136;

/// The first GPS entry on [channel] (1 = the node itself,
/// `TELEM_CHANNEL_SELF`) in [data], or null. A board without GPS sends
/// none; a T1000-E with its GPS switched off sends none either
/// (T1000SensorManager::querySensors only adds it while active).
LppGps? lppGps(Uint8List data, {int channel = 1}) {
  var i = 0;
  while (i + 2 <= data.length) {
    final ch = data[i], type = data[i + 1];
    final size = _lppSizes[type];
    if (size == null || i + 2 + size > data.length) return null;
    if (type == lppTypeGps && ch == channel) {
      final v = data.sublist(i + 2, i + 2 + size);
      return (
        latitude: _s24(v, 0) / 10000,
        longitude: _s24(v, 3) / 10000,
        altitudeM: _s24(v, 6) / 100,
      );
    }
    i += 2 + size;
  }
  return null;
}

int _s24(List<int> b, int o) {
  final v = (b[o] << 16) | (b[o + 1] << 8) | b[o + 2];
  return v & 0x800000 != 0 ? v - 0x1000000 : v;
}
