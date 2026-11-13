// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

import '../../data/radio/radio_types.dart';
import '../protocol_text.dart';

/// Small outlined label naming a radio's protocol in a radio list.
class ProtocolTag extends StatelessWidget {
  final RadioProtocol protocol;
  const ProtocolTag(this.protocol, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(protocolLabel(protocol),
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
    );
  }
}
