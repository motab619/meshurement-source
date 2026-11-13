// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/radio/mesh_radio.dart';
import '../../data/radio/meshtastic/meshtastic_contacts.dart';
import '../../providers.dart';
import '../../services/radio_backup_service.dart';
import '../protocol_text.dart' show protocolLabel;
import '../../services/radio_roles.dart';
import '../theme/app_theme.dart';
import 'connection_banner.dart' show showConnectDialog;

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Oct 12" in the phone's time zone.
String backupDay(DateTime d) {
  final t = d.toLocal();
  return '${_months[t.month - 1]} ${t.day}';
}

const _keyWarning = 'This includes the channel keys. Only share it with '
    'people who should be on those channels.';

class _RestoreResult {
  final bool cancelled;
  final String? error;
  const _RestoreResult({this.cancelled = false, this.error});
}

/// Confirm (with a current -> after diff) and run a restore of [backup] onto
/// the connected radio. For the original, also forget the radio's role.
Future<_RestoreResult> _restoreFlow({
  required BuildContext context,
  required WidgetRef ref,
  required RadioBackupService service,
  required RadioBackup backup,
  required void Function(String) onStep,
  required bool putBack,
}) async {
  if (ref.read(activeSessionProvider).valueOrNull != null) {
    return const _RestoreResult(
        error: 'End the recording session before restoring a node.');
  }
  final radio = ref.read(meshRadioProvider);
  if (!RadioBackupService.supports(radio)) {
    return const _RestoreResult(
        error: 'Connect a Meshtastic or MeshCore node first');
  }
  if (radio.protocol != backup.protocol) {
    return _RestoreResult(
        error: 'This backup is from a ${protocolLabel(backup.protocol)} '
            'node; connect one to restore it');
  }
  final reboots = backup.protocol == RadioProtocol.meshtastic;
  // A base that holds the mobile radio's key from Radio Setup: the
  // restore takes it out (a backup with admin keys puts its own list
  // back; an older one has the mobile's key removed from the current
  // list).
  final roles = ref.read(radioRolesProvider);
  final grantedTo = roles.remoteAdminGrantedNode;
  final isBase = roles.nodeOf(RadioRole.base) == backup.nodeNum;
  final mobileKey = isBase && grantedTo != null && reboots
      ? MeshtasticContacts(ref.read(sharedPreferencesProvider))
          .get(grantedTo)
          ?.publicKey
      : null;
  final grantHeld = isBase && grantedTo != null && reboots;
  List<BackupDiffLine> diff = const [];
  try {
    diff = restoreDiff(await service.snapshot(radio), backup);
  } catch (_) {
    // Settings not read yet: restore itself will say so.
  }
  if (!context.mounted) return const _RestoreResult(cancelled: true);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(putBack
          ? 'Put ${backup.ownerName} back the way it was?'
          : 'Restore ${backup.ownerName}?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings saved ${backupDay(backup.savedAt)}.'),
            const SizedBox(height: 8),
            for (final (i, l) in diff.indexed) ...[
              if (i > 0) const Divider(height: 1),
              _DiffRow(l),
            ],
            if (diff.isEmpty) Text(backup.summary),
            const SizedBox(height: 8),
            Text('${putBack ? 'Pings and sessions stop working on this node '
                    'until you run Node Setup on it again. ' : ''}'
                '${grantHeld ? 'It also removes the mobile node\'s admin '
                    'access to this base. ' : ''}'
                '${reboots ? 'The node reboots and the app reconnects.' : 'The node takes the settings without restarting.'}'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(putBack ? 'Put back' : 'Restore'),
        ),
      ],
    ),
  );
  if (ok != true) return const _RestoreResult(cancelled: true);
  try {
    final outcome = await service.restore(radio, backup,
        onStep: onStep,
        removeAdminKeys: [
          if (mobileKey != null && mobileKey.length == 32) mobileKey
        ]);
    final revoked = mobileKey != null && outcome.removed(mobileKey);
    if (revoked) await roles.clearRemoteAdmin();
    if (putBack) await roles.clearNode(backup.nodeNum);
    if (grantHeld && !revoked) {
      return const _RestoreResult(
          error: 'Restored, but the mobile node may still be able to change '
              'this node from a distance: its key is still in the admin '
              'list, or the list could not be read. Restore the original '
              'settings, or remove the key in the node\'s own app.');
    }
    return const _RestoreResult();
  } catch (e) {
    return _RestoreResult(error: 'Restore failed: $e');
  }
}

/// One setting in the restore preview: its name, then now → after. Rows
/// the restore won't change are dimmed.
class _DiffRow extends StatelessWidget {
  final BackupDiffLine line;
  const _DiffRow(this.line);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    return Opacity(
      opacity: line.changed ? 1 : 0.55,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(line.label,
                style: theme.textTheme.labelMedium?.copyWith(color: dim)),
            const SizedBox(height: 2),
            if (line.changed)
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                children: [
                  Text(line.from, style: TextStyle(color: dim)),
                  Icon(Icons.arrow_forward, size: 16, color: dim),
                  Text(line.to,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              )
            else
              Text('${line.to} · no change'),
          ],
        ),
      ),
    );
  }
}

/// The connected radio and its newest-first backups, for UI that offers
/// "put this radio back".
RadioBackup? _originalFor(List<RadioBackup> all, int? node) => node == null
    ? null
    : RadioBackup.originalOf(all.where((b) => b.nodeNum == node));

/// "Put this node back the way it was": restores the connected radio's
/// original backup. Hidden unless the connected radio has one (and, with
/// [onlyWhen], the predicate holds, e.g. "is on the MeshTest channel").
class RestoreOriginalButton extends ConsumerStatefulWidget {
  final RadioBackupService? service;
  final bool Function(MeshRadio radio)? onlyWhen;
  final VoidCallback? onRestored;

  /// A quiet text link instead of the filled button (Radio Setup, where
  /// applying is the main action).
  final bool asLink;
  const RestoreOriginalButton(
      {super.key,
      this.service,
      this.onlyWhen,
      this.onRestored,
      this.asLink = false});

  @override
  ConsumerState<RestoreOriginalButton> createState() =>
      RestoreOriginalButtonState();
}

class RestoreOriginalButtonState extends ConsumerState<RestoreOriginalButton> {
  late final RadioBackupService _service =
      widget.service ?? RadioBackupService();
  RadioBackup? _original;
  int? _loadedFor;
  bool _busy = false;
  final List<String> _log = [];
  String? _error;

  Future<void> reload() async {
    final radio = ref.read(meshRadioProvider);
    final node = radio.myNodeId;
    final all = await _service.list();
    if (mounted) {
      setState(() {
        _loadedFor = node;
        _original = _originalFor(all, node);
      });
    }
  }

  Future<void> _go() async {
    final b = _original!;
    setState(() {
      _busy = true;
      _error = null;
      _log.clear();
    });
    final r = await _restoreFlow(
      context: context,
      ref: ref,
      service: _service,
      backup: b,
      putBack: true,
      onStep: (s) {
        if (mounted) setState(() => _log.add(s));
      },
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = r.error;
    });
    if (!r.cancelled && r.error == null) widget.onRestored?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = ref.watch(meshLinkStateProvider).valueOrNull;
    final radio = ref.read(meshRadioProvider);
    final node = radio.myNodeId;
    if (_loadedFor != node) {
      _loadedFor = node;
      Future.microtask(reload);
    }
    final recording = ref.watch(activeSessionProvider).valueOrNull != null;
    final show = link == RadioConnectionState.ready &&
        !radio.isDemo &&
        _original != null &&
        (widget.onlyWhen?.call(radio) ?? true);
    if (!show && !_busy && _log.isEmpty && _error == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (show && widget.asLink)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('put-back-link'),
                onPressed: _busy || recording ? null : _go,
                icon: const Icon(Icons.history),
                label: const Text('Put this node back the way it was'),
              ),
            )
          else if (show)
            FilledButton.icon(
              onPressed: _busy || recording ? null : _go,
              icon: const Icon(Icons.history),
              label: const Text('Put this node back the way it was'),
            ),
          if (show && recording)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('End the recording session first',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.status.warning)),
            ),
          for (final line in _log) Text('• $line'),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
        ],
      ),
    );
  }
}

/// Saved radio settings, grouped per radio: made automatically before Radio
/// Setup changes a radio, or on demand. The first save for a radio is pinned
/// as its original settings.
class RadioBackupsSection extends ConsumerStatefulWidget {
  /// Storage override for tests.
  final RadioBackupService? service;

  /// The "Backups" heading (off on its own screen, whose app bar names it).
  final bool showHeading;
  const RadioBackupsSection({super.key, this.service, this.showHeading = true});

  @override
  ConsumerState<RadioBackupsSection> createState() =>
      RadioBackupsSectionState();
}

class RadioBackupsSectionState extends ConsumerState<RadioBackupsSection> {
  late final RadioBackupService _service =
      widget.service ?? RadioBackupService();
  final _putBackKey = GlobalKey<RestoreOriginalButtonState>();
  List<RadioBackup>? _backups;
  bool _busy = false;
  final List<String> _log = [];
  String? _error;
  final Set<int> _showAll = {};

  @override
  void initState() {
    super.initState();
    reload();
  }

  /// Re-read the backup files (call after Radio Setup made a new one).
  Future<void> reload() async {
    final list = await _service.list();
    if (mounted) setState(() => _backups = list);
    _putBackKey.currentState?.reload();
  }

  Future<void> _backUpNow() async {
    final radio = ref.read(meshRadioProvider);
    if (!RadioBackupService.supports(radio)) {
      _snack('Connect a Meshtastic or MeshCore node first');
      return;
    }
    try {
      final b = await _service.save(radio, reason: backupReasonByHand);
      _snack(b.unchanged
          ? 'Nothing changed since ${backupDay(b.savedAt)}; that backup '
              'still matches ${b.radioName}'
          : 'Saved ${b.radioName} (${b.summary})');
      await reload();
    } catch (e) {
      _snack('Could not back up: $e');
    }
  }

  Future<void> _import() async {
    try {
      final picked = await FilePicker.platform.pickFiles();
      final path = picked?.files.single.path;
      if (path == null) return;
      final b = await _service.import(File(path));
      _snack('Imported ${b.ownerName} ${b.nodeId} (${b.summary})');
      await reload();
    } on FormatException catch (e) {
      _snack('Could not import: ${e.message}');
    } catch (e) {
      _snack('Could not import: $e');
    }
  }

  Future<void> _restore(RadioBackup b) async {
    setState(() {
      _busy = true;
      _error = null;
      _log.clear();
    });
    final r = await _restoreFlow(
      context: context,
      ref: ref,
      service: _service,
      backup: b,
      putBack: false,
      onStep: (s) {
        if (mounted) setState(() => _log.add(s));
      },
    );
    if (mounted) {
      setState(() {
        _busy = false;
        _error = r.error;
      });
    }
  }

  Future<void> _share(RadioBackup b, BuildContext rowContext) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share backup file?'),
        content: const Text(_keyWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Share'),
          ),
        ],
      ),
    );
    if (ok != true || !rowContext.mounted) return;
    final box = rowContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      await Share.shareXFiles(
        [XFile(b.path)],
        subject: 'Node settings: ${b.radioName}',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      _snack('Share failed: $e');
    }
  }

  /// Warn first, like Share: the link carries the channel keys and the
  /// clipboard is readable by other apps.
  Future<void> _copyLink(RadioBackup b) async {
    final url = b.channelUrl;
    if (url == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Copy channel link?'),
        content: const Text(_keyWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Copy'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await Clipboard.setData(ClipboardData(text: url));
    _snack('Channel link copied');
  }

  Future<void> _delete(RadioBackup b) async {
    final isOriginal = b.original ||
        RadioBackup.originalOf(
                (_backups ?? []).where((x) => x.nodeNum == b.nodeNum))?.path ==
            b.path;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            isOriginal ? 'Delete the original settings?' : 'Delete backup?'),
        content: Text(isOriginal
            ? 'This is the only copy of how ${b.ownerName} was set up before '
                'Node Setup. It cannot be recovered.'
            : '${b.ownerName}, saved ${backupDay(b.savedAt)}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.delete(b);
    await reload();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkState = ref.watch(meshLinkStateProvider).valueOrNull;
    final radio = ref.read(meshRadioProvider);
    final roles = ref.watch(radioRolesProvider);
    final ready = linkState == RadioConnectionState.ready && !radio.isDemo;
    final connectedNode = ready ? radio.myNodeId : null;
    // Restore usually puts the radio back on its old (often public)
    // channels and reboots it: not while a session is recording.
    final recording = ref.watch(activeSessionProvider).valueOrNull != null;
    final backups = _backups;

    // Group by node; the connected radio's group first, then the rest by
    // newest backup.
    final byNode = <int, List<RadioBackup>>{};
    for (final b in backups ?? const <RadioBackup>[]) {
      byNode.putIfAbsent(b.nodeNum, () => []).add(b);
    }
    final nodes = byNode.keys.toList()
      ..sort((a, b) {
        if (a == connectedNode) return -1;
        if (b == connectedNode) return 1;
        return byNode[b]!.first.savedAt.compareTo(byNode[a]!.first.savedAt);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeading) ...[
          Text('Backups', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
        ],
        Text(
          "Node Setup saves each node's settings before changing them, so "
          'you can restore them here. Meshtastic: name, channels, LoRa and '
          'Range Test. MeshCore: name, frequency, range setting, power, '
          'relaying and channels.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        RestoreOriginalButton(
            key: _putBackKey, service: _service, onRestored: reload),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: ready && !_busy && RadioBackupService.supports(radio)
                    ? _backUpNow
                    : null,
                icon: const Icon(Icons.save_alt),
                label: Text(
                    'Back up ${ready ? radio.displayName : 'this node'} now'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Import backup…'),
            ),
          ],
        ),
        if (backups != null && backups.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('No backups yet.',
                style: TextStyle(color: theme.status.muted)),
          ),
        for (final node in nodes)
          _RadioGroup(
            key: ValueKey('group-$node'),
            backups: byNode[node]!,
            connected: node == connectedNode,
            role: roles.roleOfNode(node),
            recording: recording,
            busy: _busy,
            showAll: _showAll.contains(node),
            onToggleAll: () => setState(() {
              if (!_showAll.remove(node)) _showAll.add(node);
            }),
            onRestore: _restore,
            onShare: _share,
            onCopyLink: _copyLink,
            onDelete: _delete,
          ),
        if (_log.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final line in _log) Text('• $line'),
        ],
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child:
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
      ],
    );
  }
}

/// All backups of one radio. The connected radio's group is open; others
/// are one line ("MeshTest Base · original settings saved Oct 12 · Connect
/// to restore") that expands.
class _RadioGroup extends StatelessWidget {
  final List<RadioBackup> backups; // newest first
  final bool connected;
  final RadioRole? role;
  final bool recording;
  final bool busy;
  final bool showAll;
  final VoidCallback onToggleAll;
  final void Function(RadioBackup) onRestore;
  final void Function(RadioBackup, BuildContext) onShare;
  final void Function(RadioBackup) onCopyLink;
  final void Function(RadioBackup) onDelete;

  const _RadioGroup({
    super.key,
    required this.backups,
    required this.connected,
    required this.role,
    required this.recording,
    required this.busy,
    required this.showAll,
    required this.onToggleAll,
    required this.onRestore,
    required this.onShare,
    required this.onCopyLink,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final oldest = backups.last;
    final original = RadioBackup.originalOf(backups);
    final others = backups.where((b) => b.path != original?.path).toList();
    final shown = showAll ? others : others.take(3).toList();
    final name = oldest.ownerName;
    final model = oldest.hardwareLabel;
    final title = '$name  ${oldest.nodeId}${model == null ? '' : ' · $model'}';
    final roleLabel = role?.label;
    final String? disabledReason = connected
        ? (recording ? 'End the recording session first' : null)
        : 'Connect to $name to restore';

    Widget row(RadioBackup b, {required bool pinned}) => _BackupRow(
          backup: b,
          pinned: pinned,
          canRestore: disabledReason == null && !busy,
          disabledReason: disabledReason,
          onRestore: () => onRestore(b),
          onShare: (ctx) => onShare(b, ctx),
          onCopyLink: () => onCopyLink(b),
          onDelete: () => onDelete(b),
        );

    final header = Row(
      children: [
        Flexible(
          child:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        if (roleLabel != null) ...[
          const SizedBox(width: 6),
          Chip(
            label: Text(roleLabel),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
        ],
      ],
    );

    if (!connected) {
      final saved = original == null
          ? 'settings saved ${backupDay(oldest.savedAt)}'
          : 'original settings saved ${backupDay(original.savedAt)}';
      return ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          '$name${roleLabel == null ? '' : ' ($roleLabel)'} · $saved · '
          'Connect to restore',
          style: theme.textTheme.bodyMedium,
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    '${oldest.nodeId}${model == null ? '' : ' · $model'}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              // Restore needs this radio connected: offer the switch here
              // instead of sending people back up to "Change".
              TextButton.icon(
                key: ValueKey('connect-$name'),
                onPressed: () => showConnectDialog(context),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Connect…'),
              ),
            ],
          ),
          if (original != null) row(original, pinned: true),
          for (final b in shown) row(b, pinned: false),
          if (others.length > 3) _showAllButton(others.length),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (original != null) row(original, pinned: true),
          for (final b in shown) row(b, pinned: false),
          if (others.length > 3) _showAllButton(others.length),
        ],
      ),
    );
  }

  Widget _showAllButton(int n) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: onToggleAll,
          child: Text(showAll ? 'Show fewer' : 'Show all ($n)'),
        ),
      );
}

class _BackupRow extends StatelessWidget {
  final RadioBackup backup;
  final bool pinned;
  final bool canRestore;
  final String? disabledReason;
  final VoidCallback onRestore;
  final void Function(BuildContext) onShare;
  final VoidCallback onCopyLink;
  final VoidCallback onDelete;

  const _BackupRow({
    required this.backup,
    required this.pinned,
    required this.canRestore,
    required this.disabledReason,
    required this.onRestore,
    required this.onShare,
    required this.onCopyLink,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = backup;
    final confirmed = b.lastConfirmedAt.toLocal();
    final sameUntil = backupDay(confirmed) != backupDay(b.savedAt)
        ? ' · same until ${backupDay(confirmed)}'
        : '';
    return Builder(
      builder: (rowContext) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (pinned)
                  const Padding(
                    padding: EdgeInsets.only(right: 6, top: 2),
                    child: Icon(Icons.push_pin, size: 16),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (pinned)
                        const Text('Original settings',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      Text(b.summary,
                          style: pinned
                              ? theme.textTheme.bodyMedium
                              : const TextStyle(fontWeight: FontWeight.w500)),
                      Text(
                          '${pinned ? 'Saved ' : ''}${backupDay(b.savedAt)}'
                          '${b.savedName == null ? '' : ' · ${b.savedName}'}'
                          '$sameUntil',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                      if (disabledReason != null)
                        Text(disabledReason!,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.status.warning)),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: canRestore ? onRestore : null,
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('Restore'),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (v) {
                    switch (v) {
                      case 'share':
                        onShare(rowContext);
                      case 'link':
                        onCopyLink();
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'share', child: Text('Share file')),
                    if (b.channelUrl != null)
                      const PopupMenuItem(
                          value: 'link', child: Text('Copy channel link')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
