// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/radio/meshcore/meshcore_presets.dart';
import '../../data/radio/mesh_radio.dart';
import '../protocol_text.dart';
import '../../providers.dart';
import '../../services/radio_roles.dart';
import '../theme/app_theme.dart';

/// Why the base and mobile can't hear each other, or null when they match.
/// Compares what Radio Setup wrote to each role, and the connected radio's
/// live preset/region against what the other role was given (catches a
/// preset changed in another app).
String? setupMismatchMessage(RadioRoles roles, MeshRadio radio, bool ready) {
  String preset(String id) => anyPresetDisplayName(id);
  final stored = roles.setupMismatch();
  if (stored != null) {
    final bp = roles.presetOf(RadioRole.base);
    final mp = roles.presetOf(RadioRole.mobile);
    if (bp != null && mp != null && bp != mp) {
      return 'Base is on ${preset(bp)}, mobile on ${preset(mp)}';
    }
    return 'Base region ${roles.regionOf(RadioRole.base)}, mobile '
        '${roles.regionOf(RadioRole.mobile)}';
  }
  if (!ready) return null;
  final role = roles.roleOf(radio);
  if (role == null) return null;
  final other = role.other;
  final otherPreset = roles.presetOf(other);
  final mine = radio.currentPreset?.id;
  if (otherPreset != null &&
      mine != null &&
      MeshCoreModulations.ladderId(otherPreset) !=
          MeshCoreModulations.ladderId(mine)) {
    return '${other.label} is on ${preset(otherPreset)}, this node on '
        '${preset(mine)}';
  }
  final otherRegion = roles.regionOf(other);
  final myRegion = radio.regionName;
  if (radio.protocol != RadioProtocol.meshcore &&
      otherRegion != null &&
      myRegion.isNotEmpty &&
      myRegion != 'UNSET' &&
      otherRegion != myRegion) {
    return '${other.label} region $otherRegion, this node $myRegion';
  }
  return null;
}

/// Amber strip shown when the two radios were set up differently (preset
/// or region), which looks exactly like being out of range. Tapping opens
/// Node Setup when [onFix] is given.
class SetupMismatchBanner extends ConsumerWidget {
  final VoidCallback? onFix;

  const SetupMismatchBanner({super.key, this.onFix});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(radioRolesProvider);
    final radio = ref.watch(meshRadioProvider);
    final ready = ref.watch(meshLinkStateProvider).valueOrNull ==
        RadioConnectionState.ready;
    final message = setupMismatchMessage(roles, radio, ready);
    if (message == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final status = theme.status;
    return Semantics(
      button: onFix != null,
      child: InkWell(
        onTap: onFix,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: status.warningContainer.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: status.onWarningContainer),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Radio settings don\'t match — $message. They can\'t hear '
                  'each other.${onFix != null ? ' Tap to fix in Node Setup.' : ''}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: status.onWarningContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
