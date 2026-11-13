// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../providers.dart';
import '../../services/terrain/elevation_source.dart';
import '../../services/terrain/geo.dart';
import '../../services/terrain/los_verdict.dart';
import '../../services/terrain/path_loss_model.dart';
import '../../services/terrain/terrain_profile.dart';
import '../../services/terrain/terrain_settings.dart';
import '../theme/app_theme.dart';
import 'terrain_profile_chart.dart';
import '../../utils/user_errors.dart';

/// A measured reading (for "measured -104 dBm here").
class ProfileReading {
  const ProfileReading(this.point, {this.rssi, this.snr});
  final LatLng point;
  final int? rssi;
  final double? snr;
}

/// Closest reading within [maxM] metres of [target] that has a value.
ProfileReading? nearestReading(
  LatLng target,
  Iterable<ProfileReading> readings, {
  double maxM = 50,
}) {
  ProfileReading? best;
  var bestD = maxM;
  for (final r in readings) {
    if (r.rssi == null && r.snr == null) continue;
    final d = greatCircleDistanceM(target, r.point);
    if (d <= bestD) {
      bestD = d;
      best = r;
    }
  }
  return best;
}

/// Opens the line-of-sight profile sheet from [base] to [target].
Future<void> showTerrainProfileSheet(
  BuildContext context, {
  required LatLng base,
  required LatLng target,
  List<ProfileReading> readings = const [],
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => TerrainProfileSheet(
      base: base,
      target: target,
      readings: readings,
    ),
  );
}

/// Bottom sheet: terrain cross-section, verdict, distance, predicted loss
/// and the nearest measurement.
class TerrainProfileSheet extends ConsumerStatefulWidget {
  const TerrainProfileSheet({
    super.key,
    required this.base,
    required this.target,
    this.readings = const [],
  });

  final LatLng base;
  final LatLng target;
  final List<ProfileReading> readings;

  @override
  ConsumerState<TerrainProfileSheet> createState() =>
      _TerrainProfileSheetState();
}

class _TerrainProfileSheetState extends ConsumerState<TerrainProfileSheet> {
  late final TerrainSettings _settings;
  late final double _freq;
  TerrainProfile? _profile;
  String? _error; // user-facing
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _settings = TerrainSettings.load(ref.read(sharedPreferencesProvider));
    _freq = ref.read(meshRadioProvider).regionFrequencyMHz;
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await TerrainProfile.build(
        ref.read(elevationSourceProvider),
        widget.base,
        widget.target,
        frequencyMHz: _freq,
        baseHeightM: _settings.baseHeightM,
        mobileHeightM: _settings.mobileHeightM,
      );
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
        if (profile == null) _error = 'No elevation data for this path';
      });
    } on ElevationQuotaExceeded {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Daily terrain data limit reached — try again tomorrow '
            '(areas you have already viewed still work)';
      });
    } on ElevationDisabled {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ElevationDisabled.userMessage;
      });
    } on ElevationUnavailable {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Terrain data unavailable offline';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userMessage(e, doing: 'loading the terrain profile');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = theme.status;
    final distance = greatCircleDistanceM(widget.base, widget.target);
    final profile = _profile;
    final verdict = profile == null ? null : LosVerdictRules.evaluate(profile);
    final prediction = PathLossModel(frequencyMHz: _freq)
        .predict(distanceM: distance, profile: profile);
    final measured = nearestReading(widget.target, widget.readings);

    final verdictColor = switch (verdict?.kind) {
      LosKind.clear => status.ok,
      LosKind.partial => status.warning,
      LosKind.blocked => status.danger,
      null => status.muted,
    };
    final verdictIcon = switch (verdict?.kind) {
      LosKind.clear => Icons.check_circle,
      LosKind.partial => Icons.warning_amber_rounded,
      LosKind.blocked => Icons.block,
      null => Icons.terrain,
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Line of sight to here', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_loading)
              const SizedBox(
                height: 190,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Fetching terrain…'),
                    ],
                  ),
                ),
              )
            else if (_error != null)
              SizedBox(
                height: 120,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off),
                      const SizedBox(width: 8),
                      Flexible(child: Text(_error!)),
                    ],
                  ),
                ),
              )
            else ...[
              TerrainProfileChart(
                profile: profile,
                baseHeightM: _settings.baseHeightM,
                mobileHeightM: _settings.mobileHeightM,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(verdictIcon, color: verdictColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      verdict!.text,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: verdictColor),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              [
                'Distance ${_dist(distance)}',
                if (!_loading && _error == null)
                  'predicted loss ≈ ${prediction.totalLossDb.round()} dB'
                      '${prediction.diffractionDb > 0.5 ? ' (incl. ${prediction.diffractionDb.round()} dB terrain)' : ''}'
                      ' → ${prediction.rssiDbm.round()} dBm (uncalibrated)',
              ].join(' · '),
              style: theme.textTheme.bodyMedium,
            ),
            if (measured != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  measured.rssi != null
                      ? 'measured ${measured.rssi} dBm here'
                      : 'measured SNR ${measured.snr!.toStringAsFixed(1)} dB here',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              'Antennas ${_settings.baseHeightM.toStringAsFixed(1)} m (base) '
              'and ${_settings.mobileHeightM.toStringAsFixed(1)} m (you) above '
              'ground · ${_freq.round()} MHz · modelled from public terrain '
              'data, not measured',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  static String _dist(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(2)} km' : '${m.round()} m';
}
