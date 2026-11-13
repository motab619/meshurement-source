// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

/// Shows the long explanation behind an ⓘ: a bottom sheet with a title and
/// a scrollable body. [body] is text, or any widget for richer content.
Future<void> showInfoSheet(BuildContext context,
    {required String title, String? body, Widget? child}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (body != null) Text(body, style: theme.textTheme.bodyMedium),
                if (child != null) child,
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// A small ⓘ that opens [showInfoSheet]. Keeps a control's own helper text
/// to one sentence; the rest lives behind it.
class InfoButton extends StatelessWidget {
  final String title;
  final String? body;

  /// Built when the sheet opens (for content that reads providers or the
  /// current choice).
  final WidgetBuilder? builder;

  const InfoButton({super.key, required this.title, this.body, this.builder});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'About $title',
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.info_outline, size: 20),
      onPressed: () => showInfoSheet(context,
          title: title,
          body: body,
          child: builder == null ? null : Builder(builder: builder!)),
    );
  }
}
