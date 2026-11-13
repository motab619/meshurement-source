// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers.dart';
import '../../services/csv_export_service.dart';
import '../../utils/user_errors.dart';
import '../../utils/app_info.dart';

enum ExportScope { session, map }

const exportPrivacyNote =
    'Exports include GPS positions; the base location is usually your home.';

Rect _originOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  return box == null
      ? const Rect.fromLTWH(0, 0, 1, 1)
      : box.localToGlobal(Offset.zero) & box.size;
}

/// iOS 26+ needs the share sheet's anchor, even on iPhone.
Future<void> _share(String path, String subject, Rect origin) =>
    Share.shareXFiles([XFile(path)],
        subject: subject, sharePositionOrigin: origin);

void _failed(BuildContext context, Object e) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text(userMessage(e, doing: 'exporting'))));

/// "Export…" dialog: pick a format and (when [sessionId] is given) the scope,
/// then share the file. On iOS the files are also kept in the Files app
/// (On My iPhone > Meshurement > Exports); on Android the app folder is
/// private, so the share sheet is the only way out.
Future<void> showExportDialog(
  BuildContext context,
  WidgetRef ref, {
  required int mapId,
  required String mapName,
  int? sessionId,
  String? sessionTitle,
}) async {
  final choice = await showDialog<(ExportFormat, ExportScope, Rect)>(
    context: context,
    builder: (_) => _ExportDialog(hasSession: sessionId != null),
  );
  if (choice == null || !context.mounted) return;
  final (format, scope, origin) = choice;
  try {
    final service = ref.read(csvExportServiceProvider);
    final session = scope == ExportScope.session && sessionId != null;
    final path = session
        ? await service.exportSession(sessionId, format: format)
        : await service.exportMap(mapId, format: format);
    await _share(path, session ? (sessionTitle ?? mapName) : mapName, origin);
  } catch (e) {
    if (context.mounted) _failed(context, e);
  }
}

/// Settings > Data > Export all data: one zip with everything.
Future<void> showExportAllDialog(BuildContext context, WidgetRef ref) async {
  final origin = await showDialog<Rect>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Export all data'),
      content: const Text(
          'A zip with every map and session: one CSV per session, one '
          'GeoJSON per map, and maps.json with the settings of each.\n\n'
          '$exportPrivacyNote'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        Builder(
          builder: (bctx) => FilledButton(
            onPressed: () => Navigator.pop(ctx, _originOf(bctx)),
            child: const Text('Export'),
          ),
        ),
      ],
    ),
  );
  if (origin == null || !context.mounted) return;
  try {
    final path = await ref.read(csvExportServiceProvider).exportAll();
    await _share(path, '${AppInfo.displayName} export', origin);
  } catch (e) {
    if (context.mounted) _failed(context, e);
  }
}

class _ExportDialog extends StatefulWidget {
  final bool hasSession;
  const _ExportDialog({required this.hasSession});

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  var _format = ExportFormat.csvV2;
  late var _scope = widget.hasSession ? ExportScope.session : ExportScope.map;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Export'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.hasSession) ...[
              SegmentedButton<ExportScope>(
                segments: const [
                  ButtonSegment(
                      value: ExportScope.session, label: Text('This session')),
                  ButtonSegment(
                      value: ExportScope.map, label: Text('Whole map')),
                ],
                selected: {_scope},
                onSelectionChanged: (s) => setState(() => _scope = s.first),
              ),
              const SizedBox(height: 8),
            ],
            for (final f in ExportFormat.values)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(f.label),
                trailing: f == _format ? const Icon(Icons.check) : null,
                onTap: () => setState(() => _format = f),
              ),
            const SizedBox(height: 8),
            Text(exportPrivacyNote,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        Builder(
          builder: (bctx) => FilledButton(
            onPressed: () =>
                Navigator.pop(context, (_format, _scope, _originOf(bctx))),
            child: const Text('Export'),
          ),
        ),
      ],
    );
  }
}
