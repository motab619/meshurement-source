// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

import '../../data/radio/mesh_radio.dart';
import '../theme/app_theme.dart';

/// Oldest firmware that supports everything the app relies on (PKI direct
/// messages, key exchange for pings).
const List<int> minimumFirmware = [2, 5, 0];

/// Oldest MeshCore firmware that answers trace pings (the link check).
const List<int> minimumMeshCoreFirmware = [1, 11, 0];

/// True when [version] parses and is older than the minimum for
/// [protocol] ([minimumFirmware] for Meshtastic).
bool firmwareTooOld(String version,
    {RadioProtocol protocol = RadioProtocol.meshtastic}) {
  final v = parseFirmwareVersion(version);
  if (v == null) return false;
  final min = protocol == RadioProtocol.meshcore
      ? minimumMeshCoreFirmware
      : minimumFirmware;
  for (var i = 0; i < 3; i++) {
    if (v[i] != min[i]) return v[i] < min[i];
  }
  return false;
}

const String firmwareWarning =
    'Firmware older than 2.5: some features (ping key exchange) may not work';

const String meshCoreFirmwareWarning =
    'Firmware older than 1.11: link checks to the base may not work';

/// "Firmware x.y.z" plus an amber warning when it is too old. Shows nothing
/// while the version is unknown. Queries the radio once (not on every build).
class RadioFirmwareLine extends StatefulWidget {
  final MeshRadio radio;

  const RadioFirmwareLine({super.key, required this.radio});

  @override
  State<RadioFirmwareLine> createState() => _RadioFirmwareLineState();
}

class _RadioFirmwareLineState extends State<RadioFirmwareLine> {
  late Future<RadioInfo> _info;

  @override
  void initState() {
    super.initState();
    _info = widget.radio.queryDevice();
  }

  @override
  void didUpdateWidget(RadioFirmwareLine old) {
    super.didUpdateWidget(old);
    if (!identical(old.radio, widget.radio)) _info = widget.radio.queryDevice();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RadioInfo>(
      future: _info,
      builder: (context, snap) {
        final version = snap.data?.firmwareVersion ?? '';
        if (version.isEmpty) return const SizedBox.shrink();
        final protocol = snap.data?.protocol ?? RadioProtocol.meshtastic;
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Firmware $version'),
            if (firmwareTooOld(version, protocol: protocol))
              Text(
                  protocol == RadioProtocol.meshcore
                      ? meshCoreFirmwareWarning
                      : firmwareWarning,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.status.warning)),
          ],
        );
      },
    );
  }
}
