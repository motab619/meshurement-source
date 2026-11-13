// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/radio/ble/radio_scanner.dart';
import 'data/radio/mesh_radio.dart';
import 'data/radio/meshtastic/meshtastic_contacts.dart';
import 'data/radio/meshtastic/meshtastic_radio.dart';
import 'data/radio/switchable_radio.dart';
import 'bench/bench_mode.dart';
import 'bench/bench_server.dart';
import 'demo/demo_mode.dart';
import 'demo/demo_plan_runner.dart';
import 'demo/demo_profile.dart';
import 'demo/demo_seeder.dart';
import 'services/radio_roles.dart';
import 'services/screen_wake.dart';
import 'providers.dart';
import 'services/diag_log.dart';
import 'services/last_radio.dart';
import 'services/map_base_migration.dart';
import 'services/radio_profile_service.dart';
import 'ui/layout/app_nav_shell.dart';
import 'ui/widgets/field_report/field_report_sheet.dart';
import 'ui/widgets/field_report/report_style.dart';
import 'ui/screens/coverage_map_detail_screen.dart';
import 'ui/screens/radio_setup_screen.dart';
import 'ui/screens/rig_comparison_screen.dart';
import 'ui/screens/map_screen.dart';
import 'ui/screens/onboarding/welcome_flow.dart';
import 'ui/screens/coverage_map_list_screen.dart';
import 'ui/screens/guided/guided_test_flow.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/widgets/guided/resume_banner.dart';
import 'ui/widgets/splash_overlay.dart';
import 'ui/theme/app_theme.dart';
import 'utils/app_channel.dart';
import 'utils/app_info.dart';
import 'utils/map_tiles.dart';

class MeshAnalyzerApp extends ConsumerWidget {
  const MeshAnalyzerApp({super.key, this.showSplash = false});

  /// Hold the launch splash briefly over the first screen (real launches;
  /// off in tests and demo screenshots).
  final bool showSplash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: AppInfo.displayName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(appearanceProvider).themeMode,
      home: const MainScaffold(),
      builder:
          showSplash ? (context, child) => SplashOverlay(child: child!) : null,
    );
  }
}

class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold>
    with WidgetsBindingObserver {
  final _screens = const [
    MapScreen(),
    CoverageMapListScreen(),
    SettingsScreen(),
  ];
  BenchServer? _benchServer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
    // Needs only prefs and the DB, so it doesn't wait for the radio or
    // StoreKit to come up.
    _maybeShowWelcome();
  }

  /// First launch: the welcome flow over the home screen, once. Never in
  /// demo mode (screenshots); existing installs count as seen.
  Future<void> _maybeShowWelcome() async {
    if (DemoMode.enabled) return;
    try {
      final show = await shouldShowWelcome(
          ref.read(sharedPreferencesProvider), ref.read(databaseProvider));
      if (!show || !mounted) return;
    } catch (e) {
      debugPrint('Welcome check failed: $e');
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showWelcomeFlow(context);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_benchServer?.stop());
    super.dispose();
  }

  /// Out-of-range notifications are only sent while backgrounded.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    DiagLog.instance.log('app', state.name);
    ref.read(outOfRangeMonitorProvider).isAppInForeground =
        state == AppLifecycleState.resumed;
    ref.read(gpsServiceProvider).appInForeground =
        state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed && !DemoMode.enabled) {
      ref.read(proEntitlementProvider).refresh(); // notice expiry/renewal
      ref.read(liveActivityServiceProvider).appResumed();
      // Location may have been allowed (or Location Services turned on) in
      // Settings meanwhile. No prompt here: resume also fires when the
      // permission alert itself closes.
      ref.read(gpsServiceProvider).ensureStarted(request: false);
      if (ref.read(sessionManagerProvider).activeSession != null) {
        ref.read(outOfRangeMonitorProvider).checkNotificationPermission();
      }
    }
  }

  Future<void> _initializeServices() async {
    // Listen for packets for the app's lifetime; the radio's streams
    // survive reconnects.
    ref.read(packetProcessorProvider).start();
    ref.read(signalHistoryProvider); // start collecting for live charts
    ref.read(
        screenWakeWiringProvider); // screen stays on while a session records

    if (DemoMode.enabled) {
      await _startDemo();
      // T1: the bench on the simulator, no radios (bench-rig §8), driving
      // the demo's pretend radio and database. Started after seeding so
      // /state only answers once the demo data is in place.
      _startBench();
      return;
    }

    // Maps keep their own base location since schema v8; copy over what
    // older versions kept in preferences (once).
    try {
      await MapBaseMigration.run(
          ref.read(sharedPreferencesProvider), ref.read(databaseProvider));
    } catch (e) {
      debugPrint('Map base back-fill failed: $e');
    }

    // No prompt at launch: the first Start Session asks for location (and
    // says why). Starts right away if already allowed; retried on resume.
    await ref.read(gpsServiceProvider).ensureStarted(request: false);

    try {
      await ref.read(sessionManagerProvider).initialize();
    } catch (e) {
      debugPrint('Session resume failed: $e');
    }

    // Remember the Bluetooth id of radios whose role is known by node
    // number, so the connect list can tag them.
    final radio = ref.read(meshRadioProvider);
    // Keys of our own radios, to give back to a radio that lost one (also
    // to the new Meshtastic radio after a protocol switch).
    void giveContacts(MeshRadio r) {
      radioAs<MeshtasticRadio>(r)?.contacts =
          MeshtasticContacts(ref.read(sharedPreferencesProvider));
    }

    giveContacts(radio);
    if (radio is SwitchableRadio) radio.innerChanged.listen(giveContacts);
    // The connected node's GPS stands in when the phone has no good fix
    // (a Wi-Fi iPad has no GPS). Bluetooth only, nothing goes on air; the
    // node is within Bluetooth range, so its position is the phone's.
    final gps = ref.read(gpsServiceProvider);
    radio.ownFixes.listen(gps.addNodeFix);
    // ...and the node is only asked for them while they're needed.
    radio.ownFixesWanted = gps.nodeFixWanted;
    gps.nodeFixWantedChanges.listen((w) => radio.ownFixesWanted = w);
    final lastRadio = LastRadio(ref.read(sharedPreferencesProvider));
    radio.connectionState.listen((s) {
      DiagLog.instance.log('ble', '${s.name} ${radio.descriptor?.name ?? ''}');
      if (s == RadioConnectionState.ready) {
        ref.read(radioRolesProvider).learn(radio);
        // Remembered so a session resumed after relaunch can reconnect.
        final d = radio.descriptor;
        if (d != null) lastRadio.save(d);
        if (mounted) {
          ref.read(autoReconnectNoticeProvider.notifier).state = null;
        }
      }
    });

    // A session resumed after the app was killed records nothing until the
    // radio is back: reconnect to it without waiting for the user.
    if (ref.read(sessionManagerProvider).activeSession != null &&
        radio.state == RadioConnectionState.disconnected) {
      unawaited(_autoReconnect(radio, lastRadio));
    }

    // Dynamic Island / lock screen view of the recording session.
    ref.read(liveActivityServiceProvider).start();

    // Hardware bench (tool/bench): the Mac drives services over USB.
    _startBench();

    // Purchases: listen from launch so renewals and interrupted
    // transactions are handled.
    try {
      await ref.read(proEntitlementProvider).start();
    } catch (e) {
      debugPrint('Pro service start failed: $e');
    }
  }

  /// Bench mode (`-MeshBench`, `BENCH=true` builds only): the HTTP server
  /// the Mac drives services through. Dead code in store builds.
  void _startBench() {
    if (!BenchMode.build || !BenchMode.enabled) return;
    _benchServer = BenchServer(ref.read);
    unawaited(_benchServer!.start());
  }

  Future<void> _autoReconnect(MeshRadio radio, LastRadio lastRadio) async {
    final target = lastRadio.load();
    void notice(String text) {
      if (mounted) ref.read(autoReconnectNoticeProvider.notifier).state = text;
    }

    if (target == null) {
      notice(
          'Session resumed, but no node is remembered. Tap Connect a node on the Live map.');
      return;
    }
    final label = target.name.isNotEmpty ? target.name : 'your node';
    try {
      final scanner = ref.read(radioScannerProvider);
      if (scanner.adapterStateNow != RadioAdapterState.on) {
        await scanner.adapterState
            .firstWhere((s) => s == RadioAdapterState.on)
            .timeout(const Duration(seconds: 10));
      }
      // The user may have started connecting meanwhile.
      if (radio.state != RadioConnectionState.disconnected) return;
      print('Session resumed: reconnecting to ${target.name} (${target.id})');
      await radio.connect(target);
    } catch (e) {
      print('Auto-reconnect to ${target.id} failed: $e');
      if (radio.state != RadioConnectionState.ready) {
        notice('Session resumed, but $label did not reconnect. '
            'Tap Connect a node on the Live map.');
      }
    }
  }

  /// Demo mode (screenshots): seed the demo data, then open the screen
  /// named by `-demoScreen`.
  Future<void> _startDemo() async {
    final radio = ref.read(meshRadioProvider);
    await DemoSeeder.run(
      db: ref.read(databaseProvider),
      radio: radio,
      sessions: ref.read(sessionManagerProvider),
      monitor: ref.read(outOfRangeMonitorProvider),
      gps: ref.read(gpsServiceProvider),
      airtime: ref.read(airtimeMeterProvider),
      channelKey:
          RadioProfileService(radio, ref.read(sharedPreferencesProvider))
              .channelKey,
    );
    ref.read(liveActivityServiceProvider).start();
    if (!mounted) return;

    // 'base': the phone is connected to the base radio itself, with a
    // beacon running, so the Live map shows the beacon card.
    if (DemoMode.screen == 'base') {
      final roles = ref.read(radioRolesProvider);
      await roles.assign(RadioRole.base, nodeNum: radio.myNodeId);
      await roles.recordBeacon(
          const BeaconConfig(intervalSec: 30, kind: BeaconKind.rangeTest));
      if (!mounted) return;
    }

    switch (DemoMode.screen) {
      case 'coverage':
      case 'pings':
      case 'estimated':
      case 'profile':
      case 'terrain':
        // 'terrain': the signal map on the Terrain base map (hillshade and
        // contours). The style is remembered, so the screenshot test takes
        // this screen last.
        if (DemoMode.screen == 'terrain') {
          ref.read(mapStyleProvider.notifier).set(MapStyle.terrain);
        }
        final maps = await ref.read(databaseProvider).getAllCoverageMaps();
        if (!mounted || maps.isEmpty) return;
        ref.read(mainTabProvider.notifier).state = 1;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CoverageMapDetailScreen(
            map: maps.first,
            showPings: DemoMode.screen == 'pings',
            showEstimated: DemoMode.screen == 'estimated',
            openProfileAt:
                DemoMode.screen == 'profile' ? demoProfileTarget() : null,
          ),
        ));
      case 'compare':
        final maps = await ref.read(databaseProvider).getAllCoverageMaps();
        if (!mounted || maps.isEmpty) return;
        final sessions = await ref
            .read(databaseProvider)
            .watchSessionsForMap(maps.first.id)
            .first;
        // Seeded order: original walk first (side A), second lap second.
        final ids = [for (final s in sessions) s.id]..sort();
        if (!mounted || ids.length < 2) return;
        ref.read(mainTabProvider.notifier).state = 1;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RigComparisonScreen(
            map: maps.first,
            sessionIdsA: [ids.first],
            sessionIdsB: [ids[1]],
          ),
        ));
      case 'report':
      case 'report-story':
      case 'report-wide':
      case 'report-compare':
        // Field Report sheet over the map detail, in the named format.
        final db = ref.read(databaseProvider);
        final maps = await db.getAllCoverageMaps();
        if (!mounted || maps.isEmpty) return;
        final ids = [
          for (final s in await db.watchSessionsForMap(maps.first.id).first)
            s.id,
        ]..sort();
        if (!mounted || ids.isEmpty) return;
        ref.read(mainTabProvider.notifier).state = 1;
        unawaited(Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CoverageMapDetailScreen(map: maps.first),
        )));
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        final format = switch (DemoMode.screen) {
          'report-story' => ReportFormat.story,
          'report-wide' => ReportFormat.wide,
          _ => ReportFormat.feed,
        };
        if (DemoMode.screen == 'report-compare' && ids.length > 1) {
          unawaited(showComparisonFieldReport(context,
              coverageMapId: maps.first.id,
              sides: [
                ('Stock stubby', [ids.first]),
                ('5.8 dBi whip', [ids[1]]),
              ]));
        } else {
          unawaited(showSessionFieldReport(context, ids.first, format: format));
        }
      case 'settings':
        ref.read(mainTabProvider.notifier).state = 2;
      case 'radio':
        ref.read(mainTabProvider.notifier).state = 2;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RadioSetupScreen()),
        );
      case 'guided':
        // The Run screen on the second walk, from the scripted demo runner
        // (guidedRunnerProvider picks it in this mode).
        ref.read(mainTabProvider.notifier).state = 1;
        GuidedTestFlow.openRun(context, DemoPlanRunner.planId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(mainTabProvider);
    // Android back from Coverage or Settings returns to Live first (the
    // platform convention for a tab shell); from Live it puts the app
    // behind the home screen rather than finishing it: finishing destroys
    // the Flutter engine, and a recording session, its BLE link and the
    // foreground service die with it (first walk on the Galaxy A16,
    // 2026-11-08: Back on Live ended the session silently). iOS has no
    // system back, so this never fires there.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (currentIndex != 0) {
          ref.read(mainTabProvider.notifier).state = 0;
        } else {
          AppChannel.moveToBack();
        }
      },
      child: AppNavShell(
        selectedIndex: currentIndex,
        onSelect: (index) {
          // Snackbars belong to the tab they came from ("The base is
          // still sending its beacon" after End Session); don't let one
          // follow the user to Settings and cover the rows there.
          if (index != currentIndex) {
            ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
          }
          ref.read(mainTabProvider.notifier).state = index;
        },
        destinations: const [
          AppNavDestination(
            icon: Icons.radar_outlined,
            selectedIcon: Icons.radar,
            label: 'Live',
          ),
          AppNavDestination(
            icon: Icons.layers_outlined,
            selectedIcon: Icons.layers,
            label: 'Coverage',
          ),
          AppNavDestination(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            label: 'Settings',
          ),
        ],
        body: Column(
          children: [
            // A guided test under way: one slim line, Live and Coverage only.
            if (currentIndex != 2) const GuidedResumeBanner(),
            Expanded(
              child: _FadeIndexedStack(
                index: currentIndex,
                children: _screens,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [IndexedStack] that cross-fades between tabs (150 ms) and keeps every
/// tab's state. Hidden tabs ignore touches and are left out of semantics.
class _FadeIndexedStack extends StatelessWidget {
  final int index;
  final List<Widget> children;

  const _FadeIndexedStack({required this.index, required this.children});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          IgnorePointer(
            ignoring: i != index,
            child: ExcludeSemantics(
              excluding: i != index,
              child: AnimatedOpacity(
                opacity: i == index ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: children[i],
              ),
            ),
          ),
      ],
    );
  }
}
