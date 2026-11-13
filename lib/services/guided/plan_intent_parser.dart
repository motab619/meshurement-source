// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

/// Guided test: turning what the person typed into a [PlanIntent]
/// (design: `docs/design/guided-test/README.md` §2 and §8).
///
/// Two parsers implement the contract's [PlanIntentParser]:
///
/// * [LocalPlanIntentParser]: keyword rules, no network. Always answers.
/// * [AiPlanIntentParser]: the AI backend (`tool/ai-analysis`, route
///   `kind: plan`) when it is configured and the person has consented to
///   AI analysis; on anything else (no consent, offline, a limit, a slow
///   or unreadable reply) it hands the text to the local parser.
///
/// The model only fills the intent. It never sees node ids, keys or
/// positions: the request carries the typed text, the template list, the
/// rig and preset names and the limits, nothing else, and a text that
/// looks like a coordinate is never sent.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/user_errors.dart';
import '../ai_analysis.dart'
    show
        AiAnalysisClient,
        AiAnalysisLimitException,
        AiUnavailableException,
        UnavailableAiAnalysisGateway,
        aiAppToken,
        aiRequestHeaders;
import 'plan_models.dart';

// ─── Local keyword parser ──────────────────────────────────────────────

/// Keyword rules; no network. Never throws and always returns an intent
/// that passes [PlanIntent.validate].
class LocalPlanIntentParser implements PlanIntentParser {
  const LocalPlanIntentParser();

  /// What the person typed is kept as the intent's question, cut here.
  static const maxQuestionChars = 300;

  @override
  Future<PlanIntentGuess> parse(String text, {required ParserContext ctx}) =>
      Future.value(parseSync(text, ctx: ctx));

  /// Same as [parse], synchronously (tests and the AI fallback).
  PlanIntentGuess parseSync(String text, {required ParserContext ctx}) {
    final raw = text.trim();
    final lower = raw.toLowerCase();

    final template = _template(lower, ctx);
    final side = _side(lower, template);
    final repeat = _repeat(lower);
    final minutes = _minutes(lower);
    final kind = _routeKind(lower);
    final route = PlanRoute(kind: kind, minutes: minutes ?? 12);
    final question = _question(raw);

    if (template == null) {
      return PlanIntentGuess(
        intent: PlanIntent(
          template: PlanTemplate.antennas,
          side: side,
          variants: _placeholders(PlanTemplate.antennas, ctx),
          repeat: repeat,
          route: route,
          question: question,
        ),
        confidence: 0.3,
        clarification: 'Pick one of the tests below.',
      );
    }

    if (template == PlanTemplate.reach) {
      return PlanIntentGuess(
        intent: PlanIntent(
          template: template,
          side: PlanSide.mobile,
          variants: const ['Current setup'],
          repeat: false,
          route: route,
          question: question,
        ),
        confidence: 0.9,
      );
    }

    var variants = _variants(raw, lower, template, ctx);
    var confidence = 0.9;
    String? clarification;
    if (variants.length < PlanLimits.minVariants) {
      confidence = 0.6;
      final defaults = _placeholders(template, ctx);
      if (variants.length == 1) {
        clarification = 'What is ${variants.first} compared with? '
            'Name it on the next screen.';
        variants = [
          variants.first,
          defaults.firstWhere(
              (d) => d.toLowerCase() != variants.first.toLowerCase(),
              orElse: () => defaults.last),
        ];
      } else {
        clarification = _askForVariants(template);
        variants = defaults;
      }
    }
    if (variants.length > PlanLimits.maxVariants) {
      variants = variants.sublist(0, PlanLimits.maxVariants);
    }

    final intent = PlanIntent(
      template: template,
      side: side,
      variants: variants,
      repeat: repeat,
      route: route,
      question: question,
    );
    // Belt and braces: a rule above may still have let something odd
    // through (two names that differ only in case, say). Then fall back to
    // the template's placeholders rather than hand out an invalid intent.
    if (intent.validate() != null) {
      return PlanIntentGuess(
        intent: intent.copyWith(variants: _placeholders(template, ctx)),
        confidence: 0.6,
        clarification: _askForVariants(template),
      );
    }
    return PlanIntentGuess(
        intent: intent, confidence: confidence, clarification: clarification);
  }

  // ─── Template ───

  static final _antennaWords = RegExp(
      r'\b(antennas?|whip|dipole|yagi|fibre?glass|fiberglass|rubber duck)\b');
  static final _rangeWords = RegExp(
      r'\b(presets?|range settings?|modulations?|spreading( factor)?|sf\s?\d+|'
      r'long[ _-]?fast|medium[ _-]?fast|short[ _-]?fast|long[ _-]?slow|'
      r'medium[ _-]?slow|short[ _-]?slow|short[ _-]?turbo|long[ _-]?turbo|'
      r'long[ _-]?moderate|link ?check|'
      '$_settingsPhrase)\\b');
  // "Radio settings" is the range setting, not a reason to compare nodes
  // (TestFlight 2026-11-10: "compare two separate radio settings" planned
  // a two-node test). Counted for range settings, removed before the
  // node words are counted.
  static const _settingsPhrase =
      r'(radio|lora|modem|rf|node|mesh) (settings?|configs?|configurations?)';
  static final _settingsPhraseRe = RegExp('\\b$_settingsPhrase\\b');
  static final _radioWords = RegExp(
      r'\b(radios?|nodes|devices?|t1000(-e)?|heltec|rak\w*|lilygo|t-?beam|t-?echo|'
      r'tracker|station|seeed|wio|xiao|nrf52\w*|esp32\w*)\b');
  static final _powerWords = RegExp(r'\b(power|dbm|watts?|tx|transmit)\b');
  static final _reachWords = RegExp(
      r'\b(how far|reach|range test|distance|how long|out of range|edge of)\b');

  PlanTemplate? _template(String lower, ParserContext ctx) {
    final scores = <PlanTemplate, int>{
      PlanTemplate.antennas: _antennaWords.allMatches(lower).length,
      PlanTemplate.rangeSettings:
          _rangeWords.allMatches(lower).length + _presets(lower, ctx).length,
      PlanTemplate.txPower: _powerWords.allMatches(lower).length,
      PlanTemplate.radios: _radioWords
          .allMatches(lower.replaceAll(_settingsPhraseRe, ' '))
          .length,
    };
    // Priority on ties: the specific words win over the generic "radio".
    const order = [
      PlanTemplate.antennas,
      PlanTemplate.txPower,
      PlanTemplate.rangeSettings,
      PlanTemplate.radios,
    ];
    PlanTemplate? best;
    var bestScore = 0;
    for (final t in order) {
      final s = scores[t]!;
      if (s > bestScore) {
        best = t;
        bestScore = s;
      }
    }
    if (best != null) return best;
    if (_reachWords.hasMatch(lower)) return PlanTemplate.reach;
    return null;
  }

  // ─── Side ───

  static final _baseWords = RegExp(
      r'\b(on|at|for|of)\s+(the\s+|my\s+)?base\b|\bbase (radio|node|side|antenna|station)\b');

  PlanSide _side(String lower, PlanTemplate? template) {
    if (template == PlanTemplate.radios) return PlanSide.mobile;
    if (_baseWords.hasMatch(lower)) return PlanSide.base;
    return PlanSide.mobile;
  }

  // ─── Repeat, route ───

  static final _repeatWords = RegExp(
      r'\b(twice|both orders|repeat(ed|s)?|two passes|a-?b-?b-?a|each way|'
      r'there and back|back to back|again in reverse)\b');

  bool _repeat(String lower) => _repeatWords.hasMatch(lower);

  static final _minutesNum =
      RegExp(r'\b(\d{1,3})\s*(-|to)?\s*(min|mins|minute|minutes)\b');
  static final _hoursNum =
      RegExp(r'\b(\d{1,2}|an?|one|two)\s*(hr|hrs|hour|hours)\b');
  static final _halfHour = RegExp(r'\bhalf\s+(an\s+)?hour\b|\b30\s*min');
  static final _quarterHour = RegExp(r'\bquarter\s+(of\s+)?(an\s+)?hour\b');

  int? _minutes(String lower) {
    int? m;
    if (_halfHour.hasMatch(lower)) {
      m = 30;
    } else if (_quarterHour.hasMatch(lower)) {
      m = 15;
    } else if (_minutesNum.firstMatch(lower) case final hit?) {
      m = int.tryParse(hit.group(1)!);
    } else if (_hoursNum.firstMatch(lower) case final hit?) {
      final n = hit.group(1)!;
      m = (n == 'a' || n == 'an' || n == 'one')
          ? 60
          : n == 'two'
              ? 120
              : (int.tryParse(n) ?? 1) * 60;
    }
    if (m == null) return null;
    return m.clamp(PlanLimits.minRouteMinutes, PlanLimits.maxRouteMinutes);
  }

  static final _driveWords =
      RegExp(r'\b(drive|drives|driving|drove|car|truck|van|road trip)\b');

  RouteKind _routeKind(String lower) =>
      _driveWords.hasMatch(lower) ? RouteKind.drive : RouteKind.walk;

  // ─── Variants ───

  static final _quoted = RegExp('["“”‘’\'](.{1,60}?)["“”‘’\']');

  List<String> _variants(
      String raw, String lower, PlanTemplate template, ParserContext ctx) {
    List<String> out;
    switch (template) {
      case PlanTemplate.txPower:
        out = _powerLevels(lower);
      case PlanTemplate.rangeSettings:
        out = _presets(lower, ctx);
      case PlanTemplate.antennas:
      case PlanTemplate.radios:
        out = _quotedNames(raw);
        if (out.length < PlanLimits.minVariants) {
          final rigs = _rigs(lower, ctx);
          if (rigs.length >= PlanLimits.minVariants) {
            out = rigs;
          } else if (out.isEmpty) {
            out = _split(raw, lower);
            if (out.length < PlanLimits.minVariants && rigs.isNotEmpty) {
              out = rigs;
            }
          }
        }
      case PlanTemplate.reach:
        out = const ['Current setup'];
    }
    return _dedupe(out);
  }

  List<String> _quotedNames(String raw) => [
        for (final m in _quoted.allMatches(raw)) m.group(1)!.trim()
      ].where((s) => s.isNotEmpty).toList();

  static final _dbm = RegExp(r'(?<![\d.])(\d{1,2})\s*(dbm|db|watts?|w)?\b');

  /// Numbers 0–30 as dBm, with time phrases taken out first so "20 minute
  /// walks" does not become 20 dBm.
  List<String> _powerLevels(String lower) {
    var s = lower
        .replaceAll(_minutesNum, ' ')
        .replaceAll(_hoursNum, ' ')
        .replaceAll(RegExp(r'\bsf\s?\d+\b'), ' ');
    s = s.replaceAll(RegExp(r'\d+(\.\d+)?\s*dbi\b'), ' ');
    return [
      for (final m in _dbm.allMatches(s))
        if (int.tryParse(m.group(1)!) case final n? when n >= 0 && n <= 30)
          '$n',
    ];
  }

  /// Meshtastic names the parser knows without a connected radio.
  static const _builtInPresets = <String, String>{
    'SHORT_TURBO': 'Short Turbo',
    'SHORT_FAST': 'Short Fast',
    'SHORT_SLOW': 'Short Slow',
    'MEDIUM_FAST': 'Medium Fast',
    'MEDIUM_SLOW': 'Medium Slow',
    'LONG_TURBO': 'Long Turbo',
    'LONG_FAST': 'Long Fast',
    'LONG_MODERATE': 'Long Moderate',
    'LONG_SLOW': 'Long Slow',
  };

  Map<String, String> _presetTable(ParserContext ctx) =>
      ctx.presetNames.isNotEmpty
          ? ctx.presetNames
          : ctx.protocol == 'meshcore'
              ? const {}
              : _builtInPresets;

  /// Presets named in the text, in text order, as ids. Matches the display
  /// name ("Long Fast", also "longfast"/"long-fast") or the id.
  List<String> _presets(String lower, ParserContext ctx) {
    final found = <(int, String)>[];
    final squashed = _squash(lower);
    for (final e in _presetTable(ctx).entries) {
      final names = {
        _squash(e.key),
        _squash(e.value.replaceAll(RegExp(r'\(.*?\)'), '')),
      }..removeWhere((n) => n.length < 3);
      int? at;
      for (final n in names) {
        final i = squashed.indexOf(n);
        if (i >= 0 && (at == null || i < at)) at = i;
      }
      if (at != null) found.add((at, e.key));
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final f in found) f.$2];
  }

  /// Rig names the text mentions, in text order. A rig matches when its
  /// squashed name is in the text, or when at least half of its tokens
  /// (3+ characters) appear as words.
  List<String> _rigs(String lower, ParserContext ctx) {
    final squashed = _squash(lower);
    final words = lower.split(RegExp(r'[^a-z0-9.]+')).toSet();
    final found = <(int, double, String)>[];
    for (final rig in ctx.rigNames) {
      final sq = _squash(rig);
      if (sq.length >= 3 && squashed.contains(sq)) {
        found.add((squashed.indexOf(sq), 1.0, rig));
        continue;
      }
      final tokens = rig
          .toLowerCase()
          .split(RegExp(r'[^a-z0-9.]+'))
          .where((t) => t.length >= 3)
          .toList();
      if (tokens.isEmpty) continue;
      var hits = 0;
      int? at;
      for (final t in tokens) {
        if (words.contains(t)) {
          hits++;
          final i = lower.indexOf(t);
          if (at == null || i < at) at = i;
        }
      }
      final score = hits / tokens.length;
      if (score >= 0.5) found.add((at ?? 0, score, rig));
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final f in found) f.$3];
  }

  static final _leadIn = RegExp(
      r"^(i('d| would)? (want|like|need) to |let'?s |can (we|i) |please |"
      r'help me |i want |)(test|compare|try|check|measure|see|run|do)?\s*'
      r'(out|whether|if|how|which|what|the difference between|between)?\s*',
      caseSensitive: false);
  static final _separators = RegExp(
      r'\s+(vs\.?|versus|v\.|against|and|or|with|beats?|compared (to|with))'
      r'\s+|\s*,\s*(and\s+|or\s+)?|\s*/\s*|\s+&\s+');
  static final _articles =
      RegExp(r'^(the|my|a|an|our|this|that|these|those)\s+');
  static final _trailingNoise = RegExp(
      r'\s*(twice|both orders|repeat(ed)?|again|here|today|tomorrow|please|'
      r'up the hill|on the (mobile|base)|at the base|for me|,.*)$');

  /// "test the stock whip vs the 5.8 dBi fiberglass twice, 20 minute walks"
  /// → ["stock whip", "5.8 dBi fiberglass"].
  List<String> _split(String raw, String lower) {
    var s = raw.trim();
    // Drop what the time, repeat and route phrases cover.
    for (final re in [_minutesNum, _hoursNum, _halfHour, _quarterHour]) {
      s = _eraseCaseInsensitive(s, re);
    }
    s = _eraseCaseInsensitive(s, _repeatWords);
    s = _eraseCaseInsensitive(s, _baseWords);
    s = _eraseCaseInsensitive(
        s, RegExp(r'\b(walks?|drives?|passes|rounds?|loops?|laps?)\b'));
    s = s.replaceAll(RegExp(r'[?!.]+$'), '').trim();
    s = s.replaceFirst(_leadIn, '').trim();
    // Cut at a question clause ("..., which is better").
    s = s
        .split(RegExp(r'\s*[,;:]\s*(which|what|how|is|does|do|so|and see)\b',
            caseSensitive: false))
        .first;
    final parts = s.split(_separators);
    final out = <String>[];
    for (var p in parts) {
      p = p
          .trim()
          .replaceFirst(_articles, '')
          .replaceAll(_trailingNoise, '')
          .trim();
      p = p.replaceAll(RegExp(r'\s+'), ' ');
      // Template words and fillers on their own are not names ("two
      // antennas", "a").
      if (p.isEmpty || p.length > 40) continue;
      final tokens = p.toLowerCase().split(' ');
      if (tokens.every(_fillers.contains)) continue;
      out.add(p);
    }
    return out;
  }

  static const _fillers = {
    'antenna',
    'antennas',
    'radio',
    'radios',
    'node',
    'nodes',
    'preset',
    'presets',
    'setting',
    'settings',
    'device',
    'devices',
    'range',
    'power',
    'level',
    'levels',
    'tx',
    'them',
    'it',
    'both',
    'two',
    'three',
    'four',
    'multiple',
    'several',
    'different',
    'some',
    'my',
    'the',
    'a',
    'an',
    'our',
    'this',
    'that',
    'these',
    'those',
    'of',
    'on',
    'in',
    'at',
    'for',
    'is',
    'are',
    'be',
    'best',
    'better',
    'here',
    'there',
    'which',
    'what',
    'one',
    'other',
    'mobile',
    'base',
    'i',
    'we',
    'me',
    'need',
    'do',
    'does',
    'much',
    'many',
    'how',
    'far',
    'test',
    'tests',
    'compare',
    'comparison',
    'walk',
    'walks',
    'drive',
    'drives',
    'to',
    'and',
    'or',
    'vs',
    'with',
  };

  String _eraseCaseInsensitive(String s, RegExp re) {
    final ci = RegExp(re.pattern, caseSensitive: false);
    return s.replaceAll(ci, ' ').replaceAll(RegExp(r'\s{2,}'), ' ');
  }

  // ─── Defaults ───

  List<String> _placeholders(PlanTemplate t, ParserContext ctx) {
    switch (t) {
      case PlanTemplate.antennas:
        return const ['Antenna A', 'Antenna B'];
      case PlanTemplate.radios:
        return const ['Node A', 'Node B'];
      case PlanTemplate.txPower:
        return const ['20', '10'];
      case PlanTemplate.rangeSettings:
        final table = _presetTable(ctx);
        if (table.length >= 2) return table.keys.take(2).toList();
        return const ['Setting A', 'Setting B'];
      case PlanTemplate.reach:
        return const ['Current setup'];
    }
  }

  String _askForVariants(PlanTemplate t) => switch (t) {
        PlanTemplate.antennas =>
          'Which two antennas? Name them on the next screen.',
        PlanTemplate.radios => 'Which two nodes? Name them on the next screen.',
        PlanTemplate.txPower =>
          'Which two power levels (dBm)? Set them on the next screen.',
        PlanTemplate.rangeSettings =>
          'Which two range settings? Pick them on the next screen.',
        PlanTemplate.reach => 'Pick one of the tests below.',
      };

  /// The typed text, kept as the intent's question; never a position.
  String? _question(String raw) {
    if (raw.isEmpty || coordinateText.hasMatch(raw)) return null;
    return raw.length > maxQuestionChars
        ? raw.substring(0, maxQuestionChars)
        : raw;
  }

  static String _squash(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static List<String> _dedupe(List<String> xs) {
    final seen = <String>{};
    return [
      for (final x in xs)
        if (x.trim().isNotEmpty && seen.add(x.trim().toLowerCase())) x.trim(),
    ];
  }
}

/// A pair of decimal numbers with three or more decimals: the same rule
/// `ai_analysis.dart` applies to every digest string. Text matching it is
/// never sent to the backend and never kept as the question.
final coordinateText =
    RegExp(r'-?\d{1,3}\.\d{3,}\s*[,;/ ]\s*-?\d{1,3}\.\d{3,}');

// ─── Gateway seam ──────────────────────────────────────────────────────

abstract class PlanIntentGateway {
  /// False when a request could not succeed (no app token compiled in):
  /// the parser then stays local and never offers the consent sheet.
  bool get canSend;

  /// Sends the plan request and returns the decoded JSON reply. Throws
  /// [AiAnalysisLimitException] for 429 and [HttpStatusException] for
  /// other non-200 answers.
  Future<Map<String, dynamic>> plan(
    Map<String, dynamic> body, {
    required String deviceId,
    required String appVersion,
  });
}

/// POSTs to the same Function URL as the analyses, with the same headers.
class HttpPlanIntentGateway implements PlanIntentGateway {
  final Uri url;
  final http.Client _client;

  /// [aiAppToken] unless a test passes its own. Empty: no request is made
  /// ([AiUnavailableException]) and the parser uses its keywords.
  final String appToken;

  HttpPlanIntentGateway(this.url, {http.Client? client, String? appToken})
      : _client = client ?? http.Client(),
        appToken = appToken ?? aiAppToken;

  @override
  bool get canSend => appToken.isNotEmpty;

  @override
  Future<Map<String, dynamic>> plan(
    Map<String, dynamic> body, {
    required String deviceId,
    required String appVersion,
  }) async {
    final headers = aiRequestHeaders(
        appToken: appToken, deviceId: deviceId, appVersion: appVersion);
    final res =
        await _client.post(url, headers: headers, body: jsonEncode(body));
    if (res.statusCode == 401 || res.statusCode == 403) {
      print('Plan parser: app token refused (HTTP ${res.statusCode})');
      throw const AiUnavailableException();
    }
    final decoded = _json(res);
    if (res.statusCode == 429) {
      print('Plan parser: limit reached (${decoded['reason'] ?? 'no reason'})');
      throw AiAnalysisLimitException.fromServer(
          reason: _str(decoded['reason']), message: _str(decoded['message']));
    }
    if (res.statusCode != 200) {
      final e = HttpStatusException(res.statusCode, _str(decoded['error']));
      print('Plan parser: $e');
      throw e;
    }
    return decoded;
  }

  static Map<String, dynamic> _json(http.Response res) {
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      return body is Map<String, dynamic> ? body : const {};
    } catch (_) {
      return const {};
    }
  }

  static String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;
}

/// Canned reply (or error) for tests. Records what it got.
class FakePlanIntentGateway implements PlanIntentGateway {
  FakePlanIntentGateway({this.reply, this.error, this.delay = Duration.zero});

  Map<String, dynamic>? reply;
  Object? error;
  Duration delay;
  final received = <Map<String, dynamic>>[];
  final deviceIds = <String>[];

  /// Tests set false to act like a build without the app token.
  @override
  bool canSend = true;

  @override
  Future<Map<String, dynamic>> plan(
    Map<String, dynamic> body, {
    required String deviceId,
    required String appVersion,
  }) async {
    received.add(body);
    deviceIds.add(deviceId);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (error != null) throw error!;
    return reply ?? const {};
  }
}

// ─── AI parser ─────────────────────────────────────────────────────────

/// The AI helper with the local parser behind it. Consent, install id and
/// quota are the ones AI analysis uses (one plan request counts as one
/// analysis on the backend). Replies are never cached: the text differs
/// every time.
class AiPlanIntentParser implements PlanIntentParser {
  /// A plan request is a few hundred tokens; longer than this and the
  /// chips are faster.
  static const defaultTimeout = Duration(seconds: 8);

  /// Longer texts are not sent (the backend refuses them too).
  static const maxTextChars = 500;

  final SharedPreferences prefs;
  final PlanIntentGateway gateway;
  final LocalPlanIntentParser local;
  final Duration timeout;
  final AiAnalysisClient _analysis;
  final Future<String> Function() _appVersion;

  AiPlanIntentParser({
    required this.prefs,
    required this.gateway,
    LocalPlanIntentParser? local,
    this.timeout = defaultTimeout,
    Future<String> Function()? appVersion,
  })  : local = local ?? const LocalPlanIntentParser(),
        _analysis = AiAnalysisClient(
            prefs: prefs, gateway: const UnavailableAiAnalysisGateway()),
        _appVersion = appVersion ?? _packageVersion;

  static Future<String> _packageVersion() async {
    try {
      final i = await PackageInfo.fromPlatform();
      return '${i.version}+${i.buildNumber}';
    } catch (_) {
      return 'unknown';
    }
  }

  /// Whether a request would go to the backend at all: the same AI
  /// switch (Settings → Privacy) as analysis. Off = keywords only, nothing
  /// leaves the phone.
  bool get hasConsent => _analysis.hasConsent;

  /// Set once the Ask screen has offered the consent sheet.
  static const prefConsentOffered = 'plan_ai_consent_offered_v1';

  /// True while the switch is off and the Ask screen has never offered the
  /// consent sheet: it offers it once, before the first typed request.
  bool get shouldOfferConsent =>
      gateway.canSend &&
      !hasConsent &&
      !(prefs.getBool(prefConsentOffered) ?? false);

  Future<void> markConsentOffered() => prefs.setBool(prefConsentOffered, true);

  @override
  Future<PlanIntentGuess> parse(String text,
      {required ParserContext ctx}) async {
    final trimmed = text.trim();
    PlanIntentGuess fallback() => local.parseSync(trimmed, ctx: ctx);

    if (!hasConsent || !gateway.canSend) return fallback();
    if (trimmed.isEmpty || trimmed.length > maxTextChars) return fallback();
    if (coordinateText.hasMatch(trimmed)) {
      print('Plan parser: text looks like a position; kept on the phone');
      return fallback();
    }

    final body = requestBody(trimmed, ctx);
    try {
      final reply = await gateway
          .plan(body,
              deviceId: _analysis.deviceId, appVersion: await _appVersion())
          .timeout(timeout);
      final guess = _guessFrom(reply, trimmed);
      if (guess == null) {
        print('Plan parser: reply did not fit; using the local guess');
        return fallback();
      }
      return guess;
    } on AiAnalysisLimitException catch (e) {
      print('Plan parser: ${e.reason ?? 'limit'}; using the local guess');
      return fallback();
    } on TimeoutException {
      print('Plan parser: timed out; using the local guess');
      return fallback();
    } catch (e) {
      print('Plan parser: ${e.runtimeType}; using the local guess');
      return fallback();
    }
  }

  /// The request as the backend expects it (README: `kind: plan`).
  static Map<String, dynamic> requestBody(String text, ParserContext ctx) => {
        'kind': 'plan',
        'text': text,
        'templates': [
          for (final t in PlanTemplate.values)
            {
              'id': t.name,
              'chip': t.chip,
              'variantsMean': variantsMean(t),
            },
        ],
        'protocol': ctx.protocol,
        'rigNames': ctx.rigNames,
        'presets': ctx.presetNames,
        'limits': {
          'minVariants': PlanLimits.minVariants,
          'maxVariants': PlanLimits.maxVariants,
          'minRouteMinutes': PlanLimits.minRouteMinutes,
          'maxRouteMinutes': PlanLimits.maxRouteMinutes,
        },
      };

  /// One line per template telling the model what its variants hold.
  static String variantsMean(PlanTemplate t) => switch (t) {
        PlanTemplate.antennas =>
          'antenna names, e.g. "Stock whip", "5.8 dBi fiberglass"',
        PlanTemplate.rangeSettings =>
          'preset ids from the presets list (e.g. "MEDIUM_FAST"), both nodes '
              'change; this is the template for "radio settings" or "LoRa '
              'settings"',
        PlanTemplate.radios =>
          'node hardware names (e.g. "T1000-E", "Heltec V3"); side is always '
              'mobile; only when the user compares devices, never settings',
        PlanTemplate.txPower => 'TX power in dBm as text, 0 to 30, e.g. "20"',
        PlanTemplate.reach => 'exactly one entry naming the current setup',
      };

  /// The reply as a guess, or null when it does not fit the contract.
  PlanIntentGuess? _guessFrom(Map<String, dynamic> reply, String text) {
    final raw = reply['intent'];
    if (raw is! Map) return null;
    final PlanIntent intent;
    try {
      intent = PlanIntent.fromJson(Map<String, dynamic>.from(raw))
          .copyWith(question: text);
    } catch (_) {
      return null;
    }
    if (intent.validate() != null) return null;
    final c = reply['confidence'];
    final confidence = c is num ? c.toDouble().clamp(0.0, 1.0) : 0.6;
    final cl = reply['clarification'];
    return PlanIntentGuess(
      intent: intent,
      confidence: confidence,
      clarification: cl is String && cl.trim().isNotEmpty ? cl.trim() : null,
      fromAi: true,
    );
  }
}
