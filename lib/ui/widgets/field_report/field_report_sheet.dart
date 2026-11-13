// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/database/app_database.dart';
import '../../../providers.dart';
import '../../../services/diag_log.dart';
import '../../../services/field_report/comparison_report_data.dart';
import '../../../services/field_report/field_report_data.dart';
import '../../../services/field_report/field_report_loader.dart';
import '../../../services/field_report/private_route.dart';
import '../../../services/guided/plan_models.dart';
import '../../../services/privacy_settings.dart';
import '../../../services/pro_entitlement.dart';
import '../../../services/units.dart';
import '../../../utils/app_info.dart';
import '../../../utils/user_errors.dart';
import '../../screens/pro_paywall_screen.dart';
import 'comparison_report_card.dart';
import 'field_report_card.dart';
import 'report_basemap.dart';
import 'report_style.dart';
import 'report_theme.dart';

/// What a report sheet shows: one session, or a comparison.
sealed class FieldReportContent {
  const FieldReportContent();

  /// The prefilled card title: range setting and date, never a session
  /// name (it may be a street or a person).
  String get defaultTitle;
}

class SingleReport extends FieldReportContent {
  final FieldReportData data;
  const SingleReport(this.data);

  @override
  String get defaultTitle =>
      defaultReportTitle(data.presetName, data.startedAt);
}

class ComparisonReport extends FieldReportContent {
  final ComparisonReportData data;
  const ComparisonReport(this.data);

  @override
  String get defaultTitle =>
      defaultReportTitle(data.presetName, data.startedAt);

  /// Comparison cards with three or four setups are Pro (two are free),
  /// the same line as guided tests.
  bool get needsPro => data.sides.length > 2;
}

typedef FieldReportLoad = Future<FieldReportContent?> Function(AppDatabase db);

/// Open the report sheet for one session.
Future<void> showSessionFieldReport(BuildContext context, int sessionId,
        {ReportFormat format = ReportFormat.feed}) =>
    showFieldReportSheet(context, format: format, load: (db) async {
      final d = await FieldReportLoader(db).session(sessionId);
      return d == null ? null : SingleReport(d);
    });

/// Open the report sheet for a comparison of named session groups.
Future<void> showComparisonFieldReport(
  BuildContext context, {
  required int coverageMapId,
  required List<(String, List<int>)> sides,
  PlanAnalysisResult? result,
  ReportFormat format = ReportFormat.feed,
}) =>
    showFieldReportSheet(context, format: format, load: (db) async {
      final d = await FieldReportLoader(db)
          .comparison(coverageMapId, sides, result: result);
      return d == null ? null : ComparisonReport(d);
    });

Future<void> showFieldReportSheet(BuildContext context,
    {required FieldReportLoad load, ReportFormat format = ReportFormat.feed}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.94,
      child: FieldReportSheet(load: load, initialFormat: format),
    ),
  );
}

/// The report generation sheet: live preview, title, format, Hide base
/// area, Share. Nothing is rendered to an image until Share.
class FieldReportSheet extends ConsumerStatefulWidget {
  const FieldReportSheet({
    super.key,
    required this.load,
    this.initialFormat = ReportFormat.feed,
  });

  final FieldReportLoad load;
  final ReportFormat initialFormat;

  @override
  ConsumerState<FieldReportSheet> createState() => _FieldReportSheetState();
}

class _FieldReportSheetState extends ConsumerState<FieldReportSheet> {
  final _title = TextEditingController();
  final _cardKey = GlobalKey();
  final _shareKey = GlobalKey();
  late ReportFormat _format = widget.initialFormat;

  /// Index into [hideRadiusChoicesM]: Off, 120 m (default), 300 m.
  int _hide = 1;

  /// Path and points, or points only (a line can be matched to roads);
  /// remembered ([reportShowPathPref]).
  bool _showPath = showPathByDefault;

  /// Plain grid or a map; the last choice is remembered
  /// ([reportBackgroundPref], Andy 2026-11-05).
  ReportBackground _background = ReportBackground.plain;
  ReportTileLoader? _tiles;

  /// The card's look, for single and comparison cards; remembered
  /// ([reportThemePref]). A Pro style is shown even without Pro: previewing
  /// is free, only Share is gated.
  ReportTheme _theme = ReportTheme.night;

  /// The title the style thumbnails show: follows the title field after a
  /// short pause, so typing doesn't redraw five cards per keystroke.
  String? _thumbTitle;
  Timer? _thumbDebounce;

  /// The thumbnail row, rebuilt only when what it shows changes.
  (String, int, bool, ReportTheme, bool)? _thumbsKey;
  Widget? _thumbs;
  FieldReportContent? _content;
  bool _loaded = false;
  bool _sharing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _background = ReportBackground.fromName(
        ref.read(sharedPreferencesProvider).getString(reportBackgroundPref));
    _theme = ReportTheme.fromName(
        ref.read(sharedPreferencesProvider).getString(reportThemePref));
    _showPath =
        ref.read(sharedPreferencesProvider).getBool(reportShowPathPref) ??
            showPathByDefault;
    _load();
  }

  @override
  void dispose() {
    _thumbDebounce?.cancel();
    _title.dispose();
    _tiles?.dispose();
    super.dispose();
  }

  /// The background the card actually gets: a map only while map tiles are
  /// allowed (Settings → Privacy).
  ReportBackground get _effectiveBackground => _background.isMap &&
          ref.read(mapTilesEnabledProvider) &&
          _theme == ReportTheme.night
      ? _background
      : ReportBackground.plain;

  ReportTileLoader? get _loader => _effectiveBackground.isMap
      ? (_tiles ??= ref.read(reportTileLoaderFactoryProvider)())
      : null;

  void _setTheme(ReportTheme t) {
    setState(() => _theme = t);
    ref.read(sharedPreferencesProvider).setString(reportThemePref, t.name);
  }

  void _setShowPath(bool v) {
    setState(() => _showPath = v);
    ref.read(sharedPreferencesProvider).setBool(reportShowPathPref, v);
  }

  void _setBackground(ReportBackground b) {
    setState(() => _background = b);
    ref.read(sharedPreferencesProvider).setString(reportBackgroundPref, b.name);
  }

  Future<void> _load() async {
    try {
      _content = await widget.load(ref.read(databaseProvider));
      _title.text = _content?.defaultTitle ?? '';
    } catch (e) {
      _error = userMessage(e, doing: 'building the report');
    }
    if (mounted) setState(() => _loaded = true);
  }

  void _titleChanged(String _) {
    setState(() {});
    _thumbDebounce?.cancel();
    _thumbDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _thumbTitle = _title.text);
    });
  }

  String _cardTitle(FieldReportContent c, String text) =>
      text.trim().isEmpty ? c.defaultTitle : text.trim();

  Widget _card(
    FieldReportContent c, {
    required bool miles,
    required String title,
    required ReportFormat format,
    required ReportTheme theme,
    required ReportBackground background,
    ReportTileLoader? tiles,
  }) {
    final hide = hideRadiusChoicesM(miles: miles)[_hide];
    return switch (c) {
      SingleReport(:final data) => FieldReportCard(
          data: data,
          title: title,
          format: format,
          miles: miles,
          hideRadiusM: hide,
          showPath: _showPath,
          background: background,
          tiles: tiles,
          theme: theme,
        ),
      ComparisonReport(:final data) => ComparisonReportCard(
          data: data,
          title: title,
          format: format,
          miles: miles,
          hideRadiusM: hide,
          showPath: _showPath,
          background: background,
          tiles: tiles,
          theme: theme,
        ),
    };
  }

  /// One tile per style: the real card for this content, drawn at its full
  /// feed size and scaled down (plain background, never map tiles). Cached
  /// until the title, Hide base area, units or the pick change, so the
  /// format, background and share button never redraw them.
  Widget _themeRow(FieldReportContent c, bool miles, bool isPro) {
    final title = _cardTitle(c, _thumbTitle ?? _title.text);
    final key = (title, _hide, miles, _theme, _showPath);
    if (_thumbs != null && _thumbsKey == key && _thumbsPro == isPro) {
      return _thumbs!;
    }
    _thumbsKey = key;
    _thumbsPro = isPro;
    const format = ReportFormat.feed;
    const w = 76.0;
    final h = w * format.size.height / format.size.width;
    return _thumbs = SizedBox(
      key: const ValueKey('field-report-theme'),
      height: h + 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: ReportTheme.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final t = ReportTheme.values[i];
          return _ThemeTile(
            key: ValueKey('field-report-theme-${t.name}'),
            theme: t,
            selected: t == _theme,
            showProTag: t.isPro && !isPro,
            width: w,
            height: h,
            onTap: () => _setTheme(t),
            card: _card(c,
                miles: miles,
                title: title,
                format: format,
                theme: t,
                background: ReportBackground.plain),
          );
        },
      ),
    );
  }

  bool? _thumbsPro;

  Rect _shareOrigin() {
    final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _share() async {
    final boundary =
        _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      // A map card waits for its tiles, then for them to be painted.
      final tiles = _tiles;
      if (_effectiveBackground.isMap && tiles != null) {
        await tiles.idle;
        await WidgetsBinding.instance.endOfFrame;
      }
      final path = await renderReportPng(boundary);
      await Share.shareXFiles([XFile(path, mimeType: 'image/png')],
          sharePositionOrigin: _shareOrigin());
    } catch (e) {
      DiagLog.instance.log('report', 'field report share failed: $e');
      messenger?.showSnackBar(
          SnackBar(content: Text(userMessage(e, doing: 'making the image'))));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final miles = ref.watch(useMilesProvider);
    final c = _content;
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (c == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error ?? 'Nothing recorded to make a report from.',
              textAlign: TextAlign.center),
        ),
      );
    }
    final size = _format.size;
    final hideChoices = hideRadiusChoicesM(miles: miles);
    final tilesOn = ref.watch(mapTilesEnabledProvider);
    final terrainOn = ref.watch(mapTileConfigProvider).terrainAvailable;
    final hasPlace = switch (c) {
      SingleReport(:final data) => data.geoOrigin != null,
      ComparisonReport(:final data) => data.sides.first.data.geoOrigin != null,
    };
    final mapShown = _effectiveBackground.isMap && hasPlace;
    final isPro = ref.watch(isProProvider).value ??
        ref.read(proEntitlementProvider).isPro;
    final proStyles = [
      for (final t in ReportTheme.values)
        if (t.isPro) t.label
    ];
    // One gate is enough: either feature leads to the same Pro.
    final gate = _theme.isPro
        ? ProFeature.reportStyles
        : c is ComparisonReport && c.needsPro
            ? ProFeature.guidedTests
            : null;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
          child: Row(children: [
            Expanded(
              child:
                  Text('Share field report', style: theme.textTheme.titleLarge),
            ),
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              LayoutBuilder(builder: (context, box) {
                const maxH = 400.0;
                final w =
                    math.min(box.maxWidth, maxH * size.width / size.height);
                return Center(
                  child: SizedBox(
                    key: const ValueKey('field-report-preview'),
                    width: w,
                    height: w * size.height / size.width,
                    child: FittedBox(
                      child: RepaintBoundary(
                        key: _cardKey,
                        child: SizedBox.fromSize(
                            size: size,
                            child: _card(c,
                                miles: miles,
                                title: _cardTitle(c, _title.text),
                                format: _format,
                                theme: _theme,
                                background: _effectiveBackground,
                                tiles: _loader)),
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('field-report-title'),
                controller: _title,
                maxLength: 60,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Card title',
                  helperText:
                      'Only on the card; the session keeps its own name.',
                ),
                onChanged: _titleChanged,
              ),
              const SizedBox(height: 12),
              Text('Style', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              _themeRow(c, miles, isPro),
              if (_theme.isPro && !isPro) ...[
                const SizedBox(height: 4),
                Text(
                  '${_joinNames(proStyles)} are part of ${AppInfo.proName}. '
                  'You can preview them here.',
                  key: const ValueKey('field-report-theme-pro-note'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              Text('Format', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              SegmentedButton<ReportFormat>(
                key: const ValueKey('field-report-format'),
                showSelectedIcon: false,
                segments: [
                  for (final f in ReportFormat.values)
                    ButtonSegment(value: f, label: Text(f.label)),
                ],
                selected: {_format},
                onSelectionChanged: (s) => setState(() => _format = s.first),
              ),
              const SizedBox(height: 4),
              Text(
                  switch (_format) {
                    ReportFormat.feed =>
                      'Instagram, Facebook, Mastodon, Discord',
                    ReportFormat.story => 'Instagram and Facebook stories',
                    ReportFormat.wide => 'X, Reddit and link previews',
                  },
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              Text('Background', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              SegmentedButton<ReportBackground>(
                key: const ValueKey('field-report-background'),
                showSelectedIcon: false,
                segments: [
                  for (final b in ReportBackground.values)
                    ButtonSegment(
                      value: b,
                      label: Text(b.label),
                      enabled: !b.isMap ||
                          (_theme == ReportTheme.night &&
                              tilesOn &&
                              hasPlace &&
                              (b != ReportBackground.terrain || terrainOn)),
                    ),
                ],
                selected: {_effectiveBackground},
                onSelectionChanged: (s) => _setBackground(s.first),
              ),
              const SizedBox(height: 4),
              Text(
                _theme != ReportTheme.night
                    ? 'Maps are only on the Night style for now.'
                    : !tilesOn
                        ? 'Map tiles are off in Settings → Privacy, so the card '
                            'uses the plain grid.'
                        : mapShown
                            ? 'The map shows where the route is: streets and '
                                'places can be read off it.'
                            : 'A plain grid with no streets.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Text('Route', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              SegmentedButton<bool>(
                key: const ValueKey('field-report-path'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, label: Text('Path and points')),
                  ButtonSegment(value: false, label: Text('Points only')),
                ],
                selected: {_showPath},
                onSelectionChanged: (s) => _setShowPath(s.first),
              ),
              const SizedBox(height: 4),
              Text(
                _showPath
                    ? 'The line shows the way you went. Its shape can be '
                        'matched to roads.'
                    : 'Only the readings are drawn, with no line between '
                        'them, so the route is harder to match to roads.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Text('Hide base area', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                key: const ValueKey('field-report-hide'),
                showSelectedIcon: false,
                segments: [
                  for (var i = 0; i < hideChoices.length; i++)
                    ButtonSegment(
                        value: i,
                        label: Text(
                            hideRadiusLabel(hideChoices[i], miles: miles))),
                ],
                selected: {_hide},
                onSelectionChanged: (s) => setState(() => _hide = s.first),
              ),
              const SizedBox(height: 4),
              Text(
                mapShown
                    ? 'Nothing is drawn this close to the base. The image '
                        'file itself carries no location data.'
                    : 'Nothing is drawn this close to the base. The route is '
                        'also turned and drawn without streets, so it can\'t '
                        'be laid over a map. The image carries no location.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: gate != null
                  ? ProGate(
                      feature: gate,
                      onUnlocked: _share,
                      builder: (context, unlocked, activate) => _shareButton(
                          unlocked ? null : 'Share (Pro)', activate),
                    )
                  : _shareButton(null, _share),
            ),
          ),
        ),
      ],
    );
  }

  Widget _shareButton(String? label, VoidCallback onPressed) =>
      FilledButton.icon(
        key: _shareKey,
        onPressed: _sharing ? null : onPressed,
        icon: Icon(label == null ? Icons.ios_share : Icons.lock_outline),
        label: Text(label ?? 'Share'),
      );
}

/// "Pop, Bridge and Mission".
String _joinNames(List<String> names) => names.length < 2
    ? names.join()
    : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';

/// A style thumbnail: the live card scaled down, its label under it, a
/// ring when picked and a PRO tag on Pro styles for users without Pro.
class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    super.key,
    required this.theme,
    required this.selected,
    required this.showProTag,
    required this.width,
    required this.height,
    required this.onTap,
    required this.card,
  });

  final ReportTheme theme;
  final bool selected;
  final bool showProTag;
  final double width;
  final double height;
  final VoidCallback onTap;
  final Widget card;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final size = ReportFormat.feed.size;
    return Semantics(
      button: true,
      selected: selected,
      label: '${theme.label} style${showProTag ? ', Pro' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: width,
          child: Column(children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                    width: selected ? 2.5 : 1,
                  ),
                ),
                padding: EdgeInsets.all(selected ? 2.5 : 1),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: ExcludeSemantics(
                    child: IgnorePointer(
                      child: FittedBox(
                        child: RepaintBoundary(
                          child: SizedBox.fromSize(size: size, child: card),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (showProTag)
                const Positioned(top: 4, right: 4, child: _ProTag()),
            ]),
            const SizedBox(height: 4),
            Text(
              theme.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.labelMedium?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? scheme.primary : null,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The small "PRO" tag, the same look as Settings' (settings_screen.dart).
class _ProTag extends StatelessWidget {
  const _ProTag();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.primary),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('PRO',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.primary, fontWeight: FontWeight.bold, fontSize: 9)),
    );
  }
}

/// Capture the card at its full pixel size as a PNG in the temporary
/// folder. dart:ui writes no metadata (no location, no date) into it.
Future<String> renderReportPng(RenderRepaintBoundary boundary) async {
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('The image could not be encoded.');
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '')
        .substring(0, 12);
    final file = File(p.join(dir.path, 'field-report-$stamp.png'));
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return file.path;
  } finally {
    image.dispose();
  }
}
