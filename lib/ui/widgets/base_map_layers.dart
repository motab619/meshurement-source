// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/tiles/pmtiles_tile_provider.dart';
import '../../providers.dart';
import '../../services/appearance.dart';
import '../../services/privacy_settings.dart';
import '../../utils/map_tiles.dart';
import '../theme/app_theme.dart';

/// The base map for the current [MapStyle], as the first child of a
/// [FlutterMap]: self-hosted PMTiles inside the covered region with OSM
/// tiles elsewhere, plus the hillshade (and contour) overlays for Terrain.
/// With nothing hosted it is exactly the OSM [TileLayer].
///
/// Show a [MapCreditChip] over the map (always visible, above any data
/// layers), or put [BaseMapAttribution] last in the children.
///
/// Dimming darkens and desaturates the tiles (only the tiles: data layers
/// drawn after this one stay at full strength), so a light basemap doesn't
/// outshine a dark UI and its yellow roads don't fight orange and red dots
/// (new-user walkthrough 2026-11-08). It follows [Appearance]: Night dims
/// every map, Bright never does (field test 2026-11-08: too dark in
/// sunlight), Automatic dims maps with [dim] set (Live) while the app is
/// dark.
class BaseMapLayers extends ConsumerStatefulWidget {
  const BaseMapLayers({super.key, this.dim = false});

  final bool dim;

  @override
  ConsumerState<BaseMapLayers> createState() => _BaseMapLayersState();
}

class _BaseMapLayersState extends ConsumerState<BaseMapLayers> {
  // Kept across rebuilds so tiles aren't reloaded; a TileLayer disposes its
  // provider when it leaves the tree, so a disposed one is replaced.
  final _providers = <String, _TrackedProvider>{};

  /// The provider for [kind]: every region's file, in lookup order, then
  /// OSM ([withFallback]) or transparent. Null when no region has [kind].
  TileProvider? _provider(HostedTileKind kind, MapTileConfig config,
      {required bool withFallback}) {
    final regions = config.regionsWith(kind);
    if (regions.isEmpty) return null;
    final key = '${kind.name}|${regions.map((r) => r.urlFor(kind)).join('|')}';
    final existing = _providers[key];
    if (existing != null && !existing.disposed) return existing;
    return _providers[key] = _TrackedProvider(
      files: [
        for (final r in regions)
          PmTilesRegionFile(url: r.urlFor(kind)!, covers: r.covers),
      ],
      fallback: withFallback
          ? NetworkTileProvider(headers: {
              'User-Agent':
                  'flutter_map (${MapTileConfig.userAgentPackageName})',
            })
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Settings → Privacy: no tile layer at all, so nothing is requested.
    if (!ref.watch(mapTilesEnabledProvider)) return const _TilesOffHint();
    final config = ref.watch(mapTileConfigProvider);
    final style = config.effectiveStyle(ref.watch(mapStyleProvider));
    final appearance = ref.watch(appearanceProvider);
    final dimmed = appearance.dimsMap(
        dimInDark: widget.dim,
        dark: Theme.of(context).brightness == Brightness.dark);
    // The hint is text, so it is never dimmed with the tiles.
    Widget tiles(Widget layer) =>
        dimmed ? ColorFiltered(colorFilter: mapDimFilter, child: layer) : layer;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        tiles(TileLayer(
          key: const ValueKey('base-streets'),
          urlTemplate: config.osmFallbackUrl,
          userAgentPackageName: MapTileConfig.userAgentPackageName,
          tileProvider:
              _provider(HostedTileKind.streets, config, withFallback: true),
        )),
        if (style == MapStyle.terrain) ...[
          _TerrainGapHint(config),
          Opacity(
            opacity: appearance.hillshadeOpacity,
            child: tiles(TileLayer(
              key: const ValueKey('base-hillshade'),
              userAgentPackageName: MapTileConfig.userAgentPackageName,
              tileProvider: _provider(HostedTileKind.terrain, config,
                  withFallback: false),
            )),
          ),
          if (config.regionsWith(HostedTileKind.contours).isNotEmpty)
            tiles(TileLayer(
              key: const ValueKey('base-contours'),
              userAgentPackageName: MapTileConfig.userAgentPackageName,
              tileProvider: _provider(HostedTileKind.contours, config,
                  withFallback: false),
            )),
        ],
      ],
    );
  }
}

/// The dimmed basemap: 45 % saturation toward grey, then 60 % brightness.
/// Roads and parks stay legible but sit back behind the signal dots.
const mapDimFilter = ColorFilter.matrix(<double>[
  0.3401, 0.2360, 0.0238, 0, 0, //
  0.0701, 0.5060, 0.0238, 0, 0, //
  0.0701, 0.2360, 0.2938, 0, 0, //
  0, 0, 0, 1, 0, //
]);

/// Terrain is selected but the map's centre is outside every hosted region, so
/// there is no hillshade to draw: say so instead of looking like Standard.
class _TerrainGapHint extends StatelessWidget {
  const _TerrainGapHint(this.config);
  final MapTileConfig config;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    if (config.terrainCovers(camera.center)) return const SizedBox.shrink();
    return const _MapHint(MapTileConfig.terrainGapHint);
  }
}

/// Shown on the map instead of a basemap while map tiles are off.
class _TilesOffHint extends StatelessWidget {
  const _TilesOffHint();

  @override
  Widget build(BuildContext context) =>
      const _MapHint('Map tiles are off — Settings → Privacy');
}

/// A one-line hint at the top of the map, on a dark veil.
class _MapHint extends StatelessWidget {
  const _MapHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.mapChrome.scrim,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                text,
                // A hint on a dark veil, so white in both themes.
                style:
                    theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackedProvider extends PmTilesTileProvider {
  _TrackedProvider({
    required super.files,
    super.fallback,
  });
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

Future<void> _openCredit(MapCredit c) async {
  final url = c.url;
  if (url == null) return;
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// flutter_map's attribution button with the credits for the current style.
/// Put it last in the [FlutterMap] children.
class BaseMapAttribution extends ConsumerWidget {
  const BaseMapAttribution({
    super.key,
    this.alignment = AttributionAlignment.bottomRight,
  });

  final AttributionAlignment alignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(mapTilesEnabledProvider)) return const SizedBox.shrink();
    final config = ref.watch(mapTileConfigProvider);
    final credits = config.creditsFor(ref.watch(mapStyleProvider));
    return RichAttributionWidget(
      alignment: alignment,
      popupInitialDisplayDuration: Duration.zero,
      attributions: [
        for (final c in credits)
          TextSourceAttribution(
            c.text.startsWith('© ') ? c.text.substring(2) : c.text,
            prependCopyright: c.text.startsWith('© '),
            textStyle:
                Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10),
            onTap: c.url == null ? null : () => _openCredit(c),
          ),
      ],
    );
  }
}

/// Always-visible credit text for screens where the attribution button would
/// sit under other controls (the Live map). Tap opens the sources.
class MapCreditChip extends ConsumerWidget {
  const MapCreditChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(mapTilesEnabledProvider)) return const SizedBox.shrink();
    final config = ref.watch(mapTileConfigProvider);
    final credits = config.creditsFor(ref.watch(mapStyleProvider));
    final text = credits.map((c) => c.text).join(' · ');
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Map credits: $text',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => credits.length == 1
            ? _openCredit(credits.single)
            : _showCredits(context, credits),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: theme.mapChrome.scrim,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // Drawn straight on the tiles under a dark veil, so white in
            // both themes.
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
        ),
      ),
    );
  }

  void _showCredits(BuildContext context, List<MapCredit> credits) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in credits)
              ListTile(
                title: Text(c.text),
                trailing: c.url == null
                    ? null
                    : const Icon(Icons.open_in_new, size: 18),
                onTap: c.url == null ? null : () => _openCredit(c),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small round layers button: Standard / Terrain (when terrain is hosted)
/// and the Automatic / Bright / Night [Appearance]. Hidden while map tiles
/// are off.
///
/// With [labelUntilOpened] (the Live map) it is a compact extended button
/// reading "Layers" until the user has opened the menu once
/// ([prefMapLayersOpened]), then the plain round icon: a bare glyph says
/// little on first use and iOS users never see the tooltip.
class MapStyleButton extends ConsumerStatefulWidget {
  const MapStyleButton({super.key, this.labelUntilOpened = false});

  final bool labelUntilOpened;

  @override
  ConsumerState<MapStyleButton> createState() => _MapStyleButtonState();
}

/// Set once the map style menu has been opened (see [MapStyleButton]).
const prefMapLayersOpened = 'map_layers_opened_v1';

class _MapStyleButtonState extends ConsumerState<MapStyleButton> {
  void _opened() {
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool(prefMapLayersOpened) == true) return;
    unawaited(prefs.setBool(prefMapLayersOpened, true));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(mapTileConfigProvider);
    if (!ref.watch(mapTilesEnabledProvider)) return const SizedBox.shrink();
    final style = config.effectiveStyle(ref.watch(mapStyleProvider));
    final appearance = ref.watch(appearanceProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labelled = widget.labelUntilOpened &&
        ref.read(sharedPreferencesProvider).getBool(prefMapLayersOpened) !=
            true;
    final icon = Icon(Icons.layers, color: scheme.onSurface);
    final side = BorderSide(color: theme.mapChrome.hairline);
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: labelled ? StadiumBorder(side: side) : CircleBorder(side: side),
      clipBehavior: Clip.antiAlias,
      child: PopupMenuButton<Object>(
        tooltip: 'Map style',
        icon: labelled ? null : icon,
        onOpened: _opened,
        onSelected: (v) {
          if (v is MapStyle) ref.read(mapStyleProvider.notifier).set(v);
          if (v is Appearance) ref.read(appearanceProvider.notifier).set(v);
        },
        itemBuilder: (_) => [
          if (config.terrainAvailable) ...[
            for (final s in MapStyle.values)
              CheckedPopupMenuItem<Object>(
                value: s,
                checked: s == style,
                child: Text(s.label),
              ),
            const PopupMenuDivider(),
          ],
          for (final a in Appearance.values)
            CheckedPopupMenuItem<Object>(
              key: ValueKey('appearance-${a.name}'),
              value: a,
              checked: a == appearance,
              child: Text(a.label),
            ),
        ],
        child: labelled
            ? SizedBox(
                height: 40,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      icon,
                      const SizedBox(width: 8),
                      Text('Layers',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(color: scheme.onSurface)),
                    ],
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
