// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/database/app_database.dart';
import 'data/radio/ble/radio_scanner.dart';
import 'data/radio/mesh_radio.dart';
import 'data/radio/meshcore/meshcore_radio.dart';
import 'data/radio/meshtastic/meshtastic_radio.dart';
import 'data/radio/switchable_radio.dart';
import 'demo/demo_mode.dart';
import 'demo/demo_plan_runner.dart';
import 'demo/demo_profile.dart';
import 'models/processed_signal_event.dart';
import 'services/active_probe_service.dart';
import 'services/ai_analysis.dart';
import 'services/airtime_meter.dart';
import 'services/base_ride_along_detector.dart';
import 'services/csv_export_service.dart';
import 'services/radio_roles.dart';
import 'services/test_build.dart';
import 'services/data_erase_service.dart';
import 'services/gps_service.dart';
import 'services/heading_service.dart';
import 'services/guided/app_plan_environment.dart';
import 'services/guided/plan_environment.dart';
import 'services/guided/plan_intent_parser.dart';
import 'services/guided/plan_models.dart';
import 'services/guided/plan_runner.dart';
import 'services/live_activity_service.dart';
import 'services/other_radio_monitor.dart';
import 'services/out_of_range_monitor.dart';
import 'services/packet_processor.dart';
import 'services/pro_entitlement.dart';
import 'services/radio_backup_service.dart';
import 'services/radio_profile_service.dart';
import 'services/range_test_detector.dart';
import 'services/remote_base_change.dart';
import 'utils/map_tiles.dart';
import 'services/session_manager.dart';
import 'services/signal_history.dart';
import 'services/terrain/default_elevation_source.dart';
import 'services/terrain/elevation_source.dart';
import 'services/terrain/terrain_service.dart';
import 'services/units.dart';
import 'services/appearance.dart';
import 'utils/constants.dart';

// ─── Data Layer Providers ──────────────────────────────

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// Builds a new, unconnected radio for [protocol] (e.g. Radio Setup's
/// temporary connection to the base).
final radioFactoryProvider = Provider<MeshRadio Function(RadioProtocol)>((ref) {
  return (protocol) => switch (protocol) {
        RadioProtocol.meshtastic => MeshtasticRadio(),
        RadioProtocol.meshcore => MeshCoreRadio(),
      };
});

/// The phone's own radio (the one the app records with): a
/// [SwitchableRadio] that starts as Meshtastic and changes protocol when
/// the user connects to a radio speaking another one. Its streams survive
/// the switch, so everything below subscribes once. Use
/// `radioAs<MeshtasticRadio>(radio)` for protocol extras.
final Provider<MeshRadio> meshRadioProvider = Provider<MeshRadio>((ref) {
  final radio = SwitchableRadio(
    factory: ref.watch(radioFactoryProvider),
    // Read when a switch is attempted, not now (the session manager is
    // built on top of this radio).
    switchBlockedReason: (to) {
      final session = ref.read(sessionManagerProvider).activeSession;
      if (session == null || session.protocol == to.name) return null;
      return 'End the recording session before connecting to a '
          '${to == RadioProtocol.meshcore ? 'MeshCore' : 'Meshtastic'} '
          'node';
    },
  );
  ref.onDispose(() => radio.dispose());
  return radio;
});

/// Bluetooth scanning for radios (the UI never touches the plugin).
final radioScannerProvider = Provider<RadioScanner>((ref) {
  return RadioScanner(demo: DemoMode.enabled);
});

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Must be overridden in main.dart');
});

final notificationsProvider = Provider<FlutterLocalNotificationsPlugin>((ref) {
  return FlutterLocalNotificationsPlugin();
});

// ─── Service Layer Providers ───────────────────────────

final gpsServiceProvider = Provider<GpsService>((ref) {
  final gps = GpsService();
  ref.onDispose(() => gps.dispose());
  return gps;
});

/// The phone's compass for the Live map's heading-up mode. Nothing in demo
/// mode (the simulator has no compass and screenshots must be still).
final headingSourceProvider = Provider<HeadingSource>((ref) =>
    DemoMode.enabled ? const NoHeadingSource() : const CompassHeadingSource());

final rangeTestDetectorProvider = Provider<RangeTestDetector>((ref) {
  final detector = RangeTestDetector();
  ref.onDispose(() => detector.dispose());
  return detector;
});

final packetProcessorProvider = Provider<PacketProcessor>((ref) {
  final processor = PacketProcessor(
    db: ref.watch(databaseProvider),
    radio: ref.watch(meshRadioProvider),
    gps: ref.watch(gpsServiceProvider),
    rangeTestDetector: ref.watch(rangeTestDetectorProvider),
    outOfRangeMonitor: ref.watch(outOfRangeMonitorProvider),
    countRelayed: () =>
        AppConstants.countRelayedPackets(ref.read(sharedPreferencesProvider)),
  );
  ref.onDispose(() => processor.dispose());
  return processor;
});

final sessionManagerProvider = Provider<SessionManager>((ref) {
  final manager = SessionManager(
    db: ref.watch(databaseProvider),
    radio: ref.watch(meshRadioProvider),
    gps: ref.watch(gpsServiceProvider),
    packetProcessor: ref.watch(packetProcessorProvider),
    rangeTestDetector: ref.watch(rangeTestDetectorProvider),
    activeProbeService: ref.watch(activeProbeServiceProvider),
    outOfRangeMonitor: ref.watch(outOfRangeMonitorProvider),
    prefs: ref.watch(sharedPreferencesProvider),
    rideAlong: ref.watch(baseRideAlongDetectorProvider),
    fasterAllowed: () =>
        ref.read(proEntitlementProvider).canCreate(ProFeature.fasterIntervals),
  );
  ref.onDispose(() => manager.dispose());
  return manager;
});

final airtimeMeterProvider = Provider<AirtimeMeter>((ref) {
  final meter = AirtimeMeter();
  final sub = ref.watch(meshRadioProvider).txAirtimeStream.listen(meter.record);
  ref.onDispose(() {
    sub.cancel();
    meter.dispose();
  });
  return meter;
});

/// Estimated duty cycle (0..1, last 60 s) of our radio's own sends.
final airtimeDutyProvider = StreamProvider<double>((ref) async* {
  final meter = ref.watch(airtimeMeterProvider);
  yield meter.duty;
  yield* meter.dutyStream;
});

/// The radio's own measured airtime / channel utilization (null until it
/// reports; never for radios that don't). Re-emits the last value first.
final radioChannelStatsProvider = StreamProvider<RadioChannelStats?>((ref) {
  final radio = ref.watch(meshRadioProvider);
  // Subscribe before emitting the last value so no report is missed.
  final out = StreamController<RadioChannelStats?>();
  final sub = radio.channelStats.listen(out.add);
  out.add(radio.lastChannelStats);
  ref.onDispose(() {
    sub.cancel();
    out.close();
  });
  return out.stream;
});

final activeProbeServiceProvider = Provider<ActiveProbeService>((ref) {
  // Keep the airtime meter alive (and subscribed to the radio) whenever
  // pinging is possible; the probe service is created at app start.
  ref.watch(airtimeMeterProvider);
  final service = ActiveProbeService(
    db: ref.watch(databaseProvider),
    radio: ref.watch(meshRadioProvider),
    gps: ref.watch(gpsServiceProvider),
    countRelayed: () =>
        AppConstants.countRelayedPackets(ref.read(sharedPreferencesProvider)),
  );
  ref.onDispose(() => service.dispose());
  return service;
});

final outOfRangeMonitorProvider = Provider<OutOfRangeMonitor>((ref) {
  final monitor = OutOfRangeMonitor(
    notifications: ref.watch(notificationsProvider),
    radio: ref.watch(meshRadioProvider),
  );
  ref.onDispose(() => monitor.dispose());
  return monitor;
});

final proEntitlementProvider = Provider<ProEntitlement>((ref) {
  // Demo mode (screenshots) behaves as Pro, like PRO_OVERRIDE, so demo flows
  // never hit the paywall; so do builds from the fastlane beta lane
  // (TESTFLIGHT_PRO define), for testers. Null keeps the default
  // (debug-only define). Android is free for now (TestBuild.androidProFree):
  // Pro unlocked and no store at all, so Play Billing is never opened.
  final proFree = TestBuild.proFreeOn(defaultTargetPlatform);
  final service = ProEntitlement(
    prefs: ref.watch(sharedPreferencesProvider),
    store: proFree ? NoStoreGateway() : null,
    proOverride:
        DemoMode.enabled || TestBuild.unlockPro || proFree ? true : null,
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Current Pro status (entitlement, products, purchase state).
final proStatusProvider = StreamProvider<ProStatus>((ref) {
  return ref.watch(proEntitlementProvider).statusStream;
});

/// Whether Pro is active. Use `ProEntitlement.canCreate` / `ProGate` to gate.
final isProProvider = StreamProvider<bool>((ref) {
  return ref.watch(proEntitlementProvider).statusStream.map((s) => s.isPro);
});

final liveActivityServiceProvider = Provider<LiveActivityService>((ref) {
  final service = LiveActivityService(
    db: ref.watch(databaseProvider),
    radio: ref.watch(meshRadioProvider),
    sessions: ref.watch(sessionManagerProvider),
    packets: ref.watch(packetProcessorProvider),
    probe: ref.watch(activeProbeServiceProvider),
    monitor: ref.watch(outOfRangeMonitorProvider),
    allowed: () =>
        ref.read(proEntitlementProvider).canCreate(ProFeature.liveActivity),
    proChanges:
        ref.watch(proEntitlementProvider).statusStream.map((s) => s.isPro),
  );
  ref.onDispose(() => service.dispose());
  return service;
});

/// Which radio is the base and which the mobile (set by Radio Setup).
final radioRolesProvider = ChangeNotifierProvider<RadioRoles>((ref) {
  return RadioRoles(ref.watch(sharedPreferencesProvider));
});

/// Radio Setup's logic: the connected radio is the mobile; the base is
/// reached over a second connection.
final radioProfileServiceProvider = Provider<RadioProfileService>((ref) {
  return RadioProfileService(
    ref.watch(meshRadioProvider),
    ref.watch(sharedPreferencesProvider),
    null,
    ref.watch(radioFactoryProvider),
    // The notifier, not its notifications: roles change mid-apply (a
    // learned Bluetooth id, a recorded setup) and must not rebuild the
    // service or what is built on it (the guided engine).
    ref.watch(radioRolesProvider.notifier),
    () {
      // The phone is beside the base while setting it up.
      final p = ref.read(gpsServiceProvider).lastPosition;
      return p == null ? null : (LatLng(p.latitude, p.longitude), p.accuracy);
    },
  );
});

/// Beacons heard and missed in a session. Not autoDispose: with it the
/// drift watch is cancelled from the widget-test zone and `db.close()` in
/// `runAsync` waits forever (recording_ui_test); these only follow
/// sessions shown in the session panel, so few stay alive.
final beaconStatsProvider =
    StreamProvider.family<BeaconStats, int>((ref, sessionId) {
  return ref.watch(databaseProvider).watchBeaconStats(sessionId);
});

/// The base answers but its beacon is not arriving (see [BeaconTracker]).
final beaconAbsentProvider = StreamProvider<bool>((ref) async* {
  final tracker = ref.watch(packetProcessorProvider).beacons;
  yield tracker.absent;
  yield* tracker.absentStream;
});

final signalHistoryProvider = ChangeNotifierProvider<SignalHistory>((ref) {
  return SignalHistory(
    packets: ref.watch(packetProcessorProvider),
    probe: ref.watch(activeProbeServiceProvider),
    db: ref.watch(databaseProvider),
    sessions: ref.watch(sessionManagerProvider),
  )..start();
});

final dataEraseServiceProvider = Provider<DataEraseService>((ref) {
  return DataEraseService(
    db: ref.watch(databaseProvider),
    prefs: ref.watch(sharedPreferencesProvider),
    packets: ref.watch(packetProcessorProvider),
    history: ref.watch(signalHistoryProvider),
    sessions: ref.watch(sessionManagerProvider),
    radio: ref.watch(meshRadioProvider),
  );
});

final csvExportServiceProvider = Provider<CsvExportService>((ref) {
  return CsvExportService(db: ref.watch(databaseProvider));
});

/// Ground elevation: Open Topo Data behind a disk cache. Demo mode uses
/// synthetic terrain and never touches the network.
final elevationSourceProvider = Provider<ElevationSource>((ref) {
  if (DemoMode.enabled) return demoElevationSource();
  final prefs = ref.watch(sharedPreferencesProvider);
  return DefaultElevationSource(
      enabled: () => AppConstants.terrainOnlineEnabled(prefs));
});

/// Where map tiles come from (self-hosted PMTiles vs OSM). Overridden in
/// tests.
final mapTileConfigProvider = Provider<MapTileConfig>((ref) {
  return MapTileConfig.current;
});

/// The chosen base map style, persisted in `map_style`.
final mapStyleProvider =
    NotifierProvider<MapStyleNotifier, MapStyle>(MapStyleNotifier.new);

class MapStyleNotifier extends Notifier<MapStyle> {
  @override
  MapStyle build() => MapStyle.fromName(ref
      .watch(sharedPreferencesProvider)
      .getString(AppConstants.prefMapStyle));

  void set(MapStyle style) {
    state = style;
    unawaited(ref
        .read(sharedPreferencesProvider)
        .setString(AppConstants.prefMapStyle, style.name));
  }
}

/// Distance units (Settings → Display → Units), persisted in
/// `distance_units`. Automatic follows the phone's region; resolve with
/// `DistanceUnits.useMiles` or [useMilesProvider].
final distanceUnitsProvider =
    NotifierProvider<DistanceUnitsNotifier, DistanceUnits>(
        DistanceUnitsNotifier.new);

class DistanceUnitsNotifier extends Notifier<DistanceUnits> {
  @override
  DistanceUnits build() => DistanceUnits.fromName(ref
      .watch(sharedPreferencesProvider)
      .getString(AppConstants.prefDistanceUnits));

  void set(DistanceUnits units) {
    state = units;
    unawaited(ref
        .read(sharedPreferencesProvider)
        .setString(AppConstants.prefDistanceUnits, units.name));
  }
}

/// App and map look (Settings → Display → Appearance), persisted in
/// `app_appearance`.
final appearanceProvider =
    NotifierProvider<AppearanceNotifier, Appearance>(AppearanceNotifier.new);

class AppearanceNotifier extends Notifier<Appearance> {
  @override
  Appearance build() => Appearance.fromName(ref
      .watch(sharedPreferencesProvider)
      .getString(AppConstants.prefAppearance));

  void set(Appearance appearance) {
    state = appearance;
    unawaited(ref
        .read(sharedPreferencesProvider)
        .setString(AppConstants.prefAppearance, appearance.name));
  }
}

/// Whether distances show in miles: the Units setting, with Automatic
/// following the phone's region (`PlatformDispatcher.locale`).
final useMilesProvider = Provider<bool>((ref) => ref
    .watch(distanceUnitsProvider)
    .useMiles(PlatformDispatcher.instance.locale.countryCode));

final terrainServiceProvider = Provider<TerrainService>((ref) {
  // Chunks of 200 points (2 requests) keep progress and cancel responsive.
  return TerrainService(ref.watch(elevationSourceProvider), chunkSize: 200);
});

// ─── Stream Providers (for UI consumption) ─────────────

final bleAdapterStateProvider = StreamProvider<RadioAdapterState>((ref) {
  // Demo mode never touches Bluetooth (no permission prompt): the scanner
  // reports the adapter as on.
  return ref.watch(radioScannerProvider).adapterState;
});

/// Radio link state (connecting → configuring → ready, reconnects).
final meshLinkStateProvider = StreamProvider<RadioConnectionState>((ref) {
  return ref.watch(meshRadioProvider).connectionState;
});

/// Step-by-step connect progress (null once ready or disconnected).
final connectProgressProvider = StreamProvider<ConnectProgress?>((ref) async* {
  final radio = ref.watch(meshRadioProvider);
  yield radio.connectProgress;
  yield* radio.connectProgressStream;
});

final liveSignalProvider = StreamProvider<ProcessedSignalEvent>((ref) {
  return ref.watch(packetProcessorProvider).signalStream;
});

/// Ping replies as they come in (with the phone's position), for the Live
/// map: PacketProcessor drops ACKs, so they never reach [liveSignalProvider].
final pingSampleProvider = StreamProvider<PingSample>((ref) {
  return ref.watch(activeProbeServiceProvider).outcomes;
});

final activeSessionProvider = StreamProvider<Session?>((ref) async* {
  final manager = ref.watch(sessionManagerProvider);
  yield manager.activeSession;
  yield* manager.sessionStream;
});

final sessionPacketCountProvider =
    StreamProvider.family<int, int>((ref, sessionId) {
  return ref.watch(databaseProvider).watchPacketCount(sessionId);
});

final rangeStateProvider = StreamProvider<RangeState>((ref) async* {
  final monitor = ref.watch(outOfRangeMonitorProvider);
  yield monitor.state;
  yield* monitor.stateStream;
});

final rangeTestPromptProvider = StreamProvider<RangeTestPrompt>((ref) {
  return ref.watch(rangeTestDetectorProvider).promptStream;
});

final nodesProvider = StreamProvider<List<Node>>((ref) {
  return ref.watch(databaseProvider).watchAllNodes();
});

final coverageMapsProvider = StreamProvider<List<CoverageMap>>((ref) {
  return ref.watch(databaseProvider).watchAllCoverageMaps();
});

/// How many sessions this install has recorded (the Get started card's
/// last step).
final sessionCountProvider = StreamProvider<int>((ref) {
  return ref.watch(databaseProvider).watchSessionCount();
});

/// The selected bottom tab (0 Live, 1 Coverage, 2 Settings). Owned by
/// `MainScaffold`; anything may set it to send the user to a tab.
final mainTabProvider = StateProvider<int>((ref) => 0);

/// Set to ask the Live tab to open the start-session form on its next
/// build; the Live map resets it once the form is up. The Get started
/// card's last step sets it with the tab (first run 2026-11-07: "Go to
/// Live" left the user on the map, hunting for the Session button).
final openStartFormProvider = StateProvider<bool>((ref) => false);

/// Set once the Get started checklist on the Coverage tab has been
/// dismissed, or when an existing install is recognised at first launch.
const onboardingChecklistHiddenKey = 'onboarding_checklist_hidden_v1';

/// Whether the Get started checklist is hidden; writes go to prefs too.
final checklistHiddenProvider = StateProvider<bool>((ref) {
  return ref
          .watch(sharedPreferencesProvider)
          .getBool(onboardingChecklistHiddenKey) ??
      false;
});

final rigProfilesProvider = StreamProvider<List<RigProfile>>((ref) {
  return ref.watch(databaseProvider).watchRigProfiles();
});

// ─── Recording health (session panel) ──────────────────

/// GPS status: off / denied / searching / fix (with accuracy).
final gpsStatusProvider = StreamProvider<GpsState>((ref) async* {
  final gps = ref.watch(gpsServiceProvider);
  yield gps.state;
  yield* gps.stateStream;
});

/// A [ValueListenable] as a stream that starts with its current value.
Stream<T> _listenableStream<T>(Ref ref, ValueListenable<T> v) {
  final out = StreamController<T>();
  void emit() => out.add(v.value);
  v.addListener(emit);
  emit();
  ref.onDispose(() {
    v.removeListener(emit);
    out.close();
  });
  return out.stream;
}

/// Why the Live Activity isn't showing ("disabled", "unsupported",
/// "error: …"), null when it is (or no session).
final liveActivityProblemProvider = StreamProvider<String?>((ref) =>
    _listenableStream(ref, ref.watch(liveActivityServiceProvider).problem));

/// Why pings are paused (radio on the public channel), or null.
final pingBlockedReasonProvider = StreamProvider<String?>((ref) =>
    _listenableStream(
        ref, ref.watch(activeProbeServiceProvider).blockedReason));

/// A radio other than the base (and ours) heard on the test channel, or
/// answering our pings, this session; null when none or dismissed. Shown
/// as a banner on the live map (see [OtherRadioMonitor]).
final otherRadioAlertProvider = StreamProvider<OtherRadioAlert?>((ref) =>
    _listenableStream(
        ref, ref.watch(packetProcessorProvider).otherRadios.current));

/// Notices the base travelling with the phone mid-session (see
/// [BaseRideAlongDetector]); started and stopped by [SessionManager].
final baseRideAlongDetectorProvider = Provider<BaseRideAlongDetector>((ref) {
  final detector = BaseRideAlongDetector(
    db: ref.watch(databaseProvider),
    positions: ref.watch(gpsServiceProvider).positionStream,
    signals: ref.watch(packetProcessorProvider).signalStream,
    pings: ref.watch(activeProbeServiceProvider).outcomes,
    monitor: ref.watch(outOfRangeMonitorProvider),
    prefs: ref.watch(sharedPreferencesProvider),
  );
  ref.onDispose(detector.dispose);
  return detector;
});

/// The unanswered "base riding with you" event (Live map banner), or null.
final rideAlongPendingProvider = StreamProvider<RideAlongEvent?>((ref) =>
    _listenableStream(ref, ref.watch(baseRideAlongDetectorProvider).pending));

/// Range state changes this session (session panel), oldest first.
final rangeEventsProvider = StreamProvider<List<RangeEvent>>((ref) =>
    _listenableStream(ref, ref.watch(outOfRangeMonitorProvider).events));

/// Live tab colour key (Settings → Display). Off by default: the colours
/// read on their own; the key is there for whoever wants it.
final showSignalLegendProvider = StateProvider<bool>((ref) =>
    ref
        .watch(sharedPreferencesProvider)
        .getBool(AppConstants.prefShowSignalLegend) ??
    true);

/// Whether out-of-range alerts can reach the locked phone (null: unknown).
final notificationsAllowedProvider = StreamProvider<bool?>((ref) =>
    _listenableStream(
        ref, ref.watch(outOfRangeMonitorProvider).notificationsAllowed));

/// Set when the automatic reconnect after a relaunch failed (shown in the
/// session panel); cleared once the radio connects.
final autoReconnectNoticeProvider = StateProvider<String?>((ref) => null);

// ─── AI session analysis (Pro, opt-in; see services/ai_analysis.dart) ───

/// Whether the AI analysis backend is configured. Overridden in tests.
final aiAnalysisAvailableProvider =
    Provider<bool>((ref) => AppConstants.aiAnalysisUrl != null);

final aiAnalysisGatewayProvider = Provider<AiAnalysisGateway>((ref) {
  const url = AppConstants.aiAnalysisUrl;
  return url == null
      ? const UnavailableAiAnalysisGateway()
      : HttpAiAnalysisGateway(Uri.parse(url));
});

final aiAnalysisClientProvider = Provider<AiAnalysisClient>((ref) {
  return AiAnalysisClient(
    prefs: ref.watch(sharedPreferencesProvider),
    gateway: ref.watch(aiAnalysisGatewayProvider),
  );
});

// ─── Guided test (design: docs/design/guided-test/) ───────────────────────

/// The engine behind Ask → Plan → Run → Result. Wired by
/// `services/guided/plan_runner.dart`; UI tests override it with a fake.
final planRunnerProvider = Provider<PlanRunnerApi>((ref) {
  final runner = PlanRunner(ref.watch(planEnvironmentProvider));
  ref.onDispose(runner.dispose);
  return runner;
});

/// Turns the Ask screen's text or chip into a [PlanIntent]. The AI helper
/// when the analysis backend is configured (it falls back to keywords on
/// its own), else keywords only.
final planIntentParserProvider = Provider<PlanIntentParser>((ref) {
  final gateway = ref.watch(planIntentGatewayProvider);
  if (gateway == null) return const LocalPlanIntentParser();
  return AiPlanIntentParser(
    prefs: ref.watch(sharedPreferencesProvider),
    gateway: gateway,
  );
});

// ─── Guided test parser ───

/// The plan route of the AI analysis backend (same Function URL, same
/// install id and quota), or null while no backend is configured.
/// Overridden in tests with a `FakePlanIntentGateway`.
final planIntentGatewayProvider = Provider<PlanIntentGateway?>((ref) {
  const url = AppConstants.aiAnalysisUrl;
  return url == null ? null : HttpPlanIntentGateway(Uri.parse(url));
});

// ─── Guided test UI ───

/// The runner the guided-test screens talk to: the engine's
/// [planRunnerProvider], or the demo's scripted runner for `-demoScreen
/// guided` (screenshots, nothing over the air).
final guidedRunnerProvider = Provider<PlanRunnerApi>((ref) {
  if (DemoMode.enabled && DemoMode.screen == 'guided') return DemoPlanRunner();
  return ref.watch(planRunnerProvider);
});

/// The plan that is running or paused, if any (resume banner, Live row).
/// An error (engine not wired) reads as "none".
final activePlanProvider = StreamProvider<PlanRecord?>(
    (ref) => ref.watch(guidedRunnerProvider).watchActivePlan());

/// A map's plans, newest first (map detail's Tests section).
final mapPlansProvider = StreamProvider.autoDispose
    .family<List<PlanRecord>, int>(
        (ref, mapId) => ref.watch(guidedRunnerProvider).watchPlans(mapId));

/// Live state of a plan's current step (the Run screen).
final planProgressProvider = StreamProvider.autoDispose
    .family<PlanProgress, int>(
        (ref, planId) => ref.watch(guidedRunnerProvider).watch(planId));

/// "Change the base from here" outside a guided test. Not autoDispose:
/// leaving the screen mid-change must not stop the sequence halfway.
final remoteBaseChangeProvider = ChangeNotifierProvider<RemoteBaseChange>(
    (ref) => RemoteBaseChange(ref.watch(planEnvironmentProvider)));

/// Set once the full "Changing the base from here" risk sheet has been
/// read on this phone; afterwards a one-line reminder with ⓘ.
const guidedRiskSeenKey = 'guided_risk_seen_v1';

// ─── Guided test engine ───

/// Radio settings backups on disk (`Documents/radio_backups`).
final radioBackupServiceProvider =
    Provider<RadioBackupService>((ref) => RadioBackupService());

/// Everything the plan runner needs from the app, behind one seam
/// (`PlanEnvironment`); tests give the runner a fake instead.
final planEnvironmentProvider = Provider<PlanEnvironment>((ref) {
  final env = AppPlanEnvironment(
    db: ref.watch(databaseProvider),
    radio: ref.watch(meshRadioProvider),
    // Read live through getters; a roles notification (the base's new
    // setting recorded mid-change) must not replace the running engine.
    roles: ref.watch(radioRolesProvider.notifier),
    prefs: ref.watch(sharedPreferencesProvider),
    profiles: ref.watch(radioProfileServiceProvider),
    backups: ref.watch(radioBackupServiceProvider),
    gps: ref.watch(gpsServiceProvider),
    sessions: ref.watch(sessionManagerProvider),
    packets: ref.watch(packetProcessorProvider),
    probe: ref.watch(activeProbeServiceProvider),
  );
  ref.onDispose(env.dispose);
  return env;
});
