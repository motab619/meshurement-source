// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

import '../../data/radio/meshtastic/meshtastic_radio.dart';
import '../../data/radio/meshtastic/meshtastic_regions.dart';
import '../theme/app_theme.dart';
import '../../utils/user_errors.dart';

/// Ask for the radio's LoRa region and write it. A new radio has none and
/// won't transmit until it's set (the official app asks first thing too).
/// Returns true once the region is written; the radio then reboots and
/// the app reconnects on its own.
Future<bool> showRegionDialog(
  BuildContext context,
  MeshtasticRadio radio, {
  bool newRadio = false,
}) async {
  final written = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RegionDialog(radio: radio, newRadio: newRadio),
  );
  return written == true;
}

class _RegionDialog extends StatefulWidget {
  final MeshtasticRadio radio;
  final bool newRadio;

  const _RegionDialog({required this.radio, required this.newRadio});

  @override
  State<_RegionDialog> createState() => _RegionDialogState();
}

class _RegionDialogState extends State<_RegionDialog> {
  late MeshtasticRegion _region;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _region = MeshtasticRegions.byCode(widget.radio.regionName) ??
        MeshtasticRegions.guessFor(
            WidgetsBinding.instance.platformDispatcher.locale.countryCode);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.radio.setRegion(_region.code);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = userMessage(e, doing: 'setting the region');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.radio.displayName;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.newRadio ? 'Set up $name' : 'LoRa region'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.newRadio
              ? 'This node has no LoRa region yet, so it can\'t transmit. '
                  'Pick the region for the country you\'re in.'
              : 'Pick the region for the country you\'re in.'),
          const SizedBox(height: 12),
          DropdownButtonFormField<MeshtasticRegion>(
            initialValue: _region,
            isExpanded: true,
            // Rows size to their label, so long names wrap instead of
            // cutting off the band (e.g. "... Mexico (915 MHz)").
            itemHeight: null,
            decoration: const InputDecoration(
              labelText: 'Region',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final r in MeshtasticRegions.all)
                DropdownMenuItem(
                  value: r,
                  child: Text(r.label),
                ),
            ],
            onChanged:
                _saving ? null : (r) => setState(() => _region = r ?? _region),
          ),
          const SizedBox(height: 8),
          Text(
            'Using the wrong region can be illegal where you are. '
            'The node restarts after saving.',
            style:
                theme.textTheme.bodySmall?.copyWith(color: theme.status.muted),
          ),
          if (_saving) ...[
            const SizedBox(height: 12),
            const Row(children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text('Saving — node will restart…'),
            ]),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(widget.newRadio ? 'Later' : 'Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Set region'),
        ),
      ],
    );
  }
}
