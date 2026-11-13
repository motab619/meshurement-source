// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../providers.dart';
import '../../services/base_location.dart';
import '../../services/base_node.dart';
import '../../services/gps_service.dart';
import '../../services/radio_roles.dart';
import '../../services/terrain/terrain_settings.dart';

/// Shows the "New coverage map" dialog. Returns the new map's id, or null
/// if cancelled.
Future<int?> showCreateMapDialog(BuildContext context, WidgetRef ref) {
  return showDialog<int>(
    context: context,
    builder: (context) => const _CreateMapDialog(),
  );
}

class _CreateMapDialog extends ConsumerStatefulWidget {
  const _CreateMapDialog();

  @override
  ConsumerState<_CreateMapDialog> createState() => _CreateMapDialogState();
}

class _CreateMapDialogState extends ConsumerState<_CreateMapDialog> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  bool _loaded = false;

  /// The Radio Setup base, whose remembered location the map may start
  /// with. A map is a place: it does not pick a base radio (each session
  /// records with the Radio Setup base of the day).
  int? _baseMeshNodeId;
  bool _saving = false;

  /// Where the base is for this map. Default: where it was set up, else
  /// the phone's position now, else set by hand later.
  _BaseWhere? _whereChoice;

  _BaseWhere get _where {
    final c = _whereChoice;
    if (c != null && _available(c)) return c;
    // A saved location far from where the phone is now is probably from
    // an earlier setup somewhere else (field, 2026-10-27: a map made at
    // home got the morning's work location, 50 km away).
    if (_savedBase != null && !_savedIsFar) return _BaseWhere.setup;
    if (_gpsFix != null) return _BaseWhere.here;
    if (_savedBase != null) return _BaseWhere.setup;
    return _BaseWhere.later;
  }

  /// Saved location further than this from the phone is suspect.
  static const _farM = 1000.0;

  /// Metres from the saved Radio Setup location to the phone now, when
  /// both are known.
  double? get _savedFarM {
    final saved = _savedBase;
    final fix = _gpsFix;
    if (saved == null || fix == null) return null;
    return const Distance().as(LengthUnit.Meter, saved.point, fix.$1);
  }

  bool get _savedIsFar => (_savedFarM ?? 0) > _farM;

  static String _km(double m) => m >= 10000
      ? '${(m / 1000).round()} km'
      : '${(m / 1000).toStringAsFixed(1)} km';

  bool _available(_BaseWhere w) => switch (w) {
        _BaseWhere.setup => _savedBase != null,
        _BaseWhere.here => _gpsFix != null,
        _BaseWhere.later => true,
      };

  BaseLocation? get _savedBase {
    final id = _baseMeshNodeId;
    if (id == null) return null;
    return BaseLocationStore(ref.read(sharedPreferencesProvider)).load(id);
  }

  /// The phone's fix, if good enough to stand in for the base.
  (LatLng, double)? get _gpsFix {
    final p = ref.read(gpsServiceProvider).lastPosition;
    if (p == null || p.accuracy > BaseLocationStore.maxAccuracyM) return null;
    return (LatLng(p.latitude, p.longitude), p.accuracy);
  }

  LatLng? _baseLocationChoice() => switch (_where) {
        _BaseWhere.setup => _savedBase?.point,
        _BaseWhere.here => _gpsFix?.$1,
        _BaseWhere.later => null,
      };

  static String _clock(DateTime t) {
    final l = t.toLocal();
    return '${l.month}/${l.day} ${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }

  /// What "My position now" says while there is no usable fix, by GPS
  /// state (first run 2026-11-06: a flat "No GPS fix good enough yet"
  /// when Location had never been asked for).
  String _noFixText(GpsState gps) => switch (gps.status) {
        GpsStatus.unknown || GpsStatus.notAsked => 'Location not allowed yet.',
        GpsStatus.denied => 'Location is off for this app (iOS Settings).',
        GpsStatus.off => 'Location Services are off (iOS Settings).',
        GpsStatus.searching => 'Getting a fix…',
        GpsStatus.fix => 'Fix is ±${(gps.accuracy ?? 0).round()} m; waiting '
            'for one within ${BaseLocationStore.maxAccuracyM.round()} m…',
      };

  List<Widget> _baseLocationRows() {
    final saved = _savedBase;
    final fix = _gpsFix;
    // Rebuild as fixes arrive: the option enables itself.
    final gps = ref.watch(gpsStatusProvider).valueOrNull ?? GpsState.unknown;
    final notAsked =
        gps.status == GpsStatus.unknown || gps.status == GpsStatus.notAsked;
    final theme = Theme.of(context);
    Widget option(_BaseWhere w, String title, String subtitle) =>
        RadioListTile<_BaseWhere>(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: w,
          enabled: _available(w),
          title: Text(title),
          subtitle: Text(subtitle),
        );
    return [
      Text('Base location', style: theme.textTheme.labelLarge),
      RadioGroup<_BaseWhere>(
        groupValue: _where,
        onChanged: (v) => setState(() => _whereChoice = v),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          option(
            _BaseWhere.setup,
            'Where it was set up',
            saved == null
                ? 'No location saved by Node Setup yet.'
                : 'The phone\'s position when Node Setup configured the base '
                    '(±${saved.accuracyM.round()} m, ${_clock(saved.at)}).'
                    '${_savedIsFar ? ' That is ${_km(_savedFarM!)} from where '
                        'you are now: pick it only if the base is still '
                        'there.' : ''}',
          ),
          option(
            _BaseWhere.here,
            'My position now',
            fix == null
                ? _noFixText(gps)
                : 'I\'m standing at the base (±${fix.$2.round()} m).',
          ),
          if (fix == null && notAsked)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 40),
                child: TextButton.icon(
                  key: const ValueKey('map-allow-location'),
                  onPressed: () =>
                      ref.read(gpsServiceProvider).ensureStarted(request: true),
                  icon: const Icon(Icons.my_location, size: 18),
                  label: const Text('Allow location'),
                ),
              ),
            ),
          option(
            _BaseWhere.later,
            'Set it by hand',
            'Long-press the map, or use the map menu: Set base location…',
          ),
        ]),
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _loadBase();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  /// The Radio Setup base (else the newest session's), for its location.
  Future<void> _loadBase() async {
    final roles = ref.read(radioRolesProvider);
    final baseNum = roles.nodeOf(RadioRole.base) ??
        await knownBaseNodeNum(
            ref.read(sharedPreferencesProvider), ref.read(databaseProvider));
    if (!mounted) return;
    setState(() {
      _baseMeshNodeId = baseNum;
      _loaded = true;
    });
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);

    final db = ref.read(databaseProvider);
    final baseLoc = _baseLocationChoice();
    final mapId = await db.createCoverageMap(
      name: name,
      baseLat: baseLoc?.latitude,
      baseLon: baseLoc?.longitude,
      description: _descController.text.trim(),
    );
    final prefs = ref.read(sharedPreferencesProvider);
    // Remember an explicit "no" so the map doesn't fall back to the Radio
    // Setup location later.
    if (_savedBase != null && _where != _BaseWhere.setup) {
      await TerrainSettings.saveBaseOptOut(prefs, mapId, true);
    }
    if (mounted) Navigator.pop(context, mapId);
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = !_saving && _nameController.text.trim().isNotEmpty;

    return AlertDialog(
      title: const Text('New coverage map'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Map name',
                hintText: 'e.g., Home Base - Stock Antenna',
              ),
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'A map is a place. Each session records with the base node '
              'from Node Setup, shown when you start it.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            if (!_loaded)
              const LinearProgressIndicator()
            else
              ..._baseLocationRows(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canCreate ? _create : null,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

enum _BaseWhere { setup, here, later }
