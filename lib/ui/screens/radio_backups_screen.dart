// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

import '../../services/radio_backup_service.dart';
import '../widgets/radio_backups_section.dart';
import '../layout/window_class.dart';

/// Settings → Radios → Radio backups: every saved radio setting, grouped
/// per radio (moved out of Radio Setup, new-user walkthrough 2026-11-08).
class RadioBackupsScreen extends StatelessWidget {
  /// Storage override for tests.
  final RadioBackupService? service;

  const RadioBackupsScreen({super.key, this.service});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Node backups')),
      body: WideColumn(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            RadioBackupsSection(service: service, showHeading: false),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
