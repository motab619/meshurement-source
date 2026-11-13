# Quality / correctness audit (read-only)

Tree: .../scratchpad/beta-audit (paths below are relative to it).

## Summary
- `flutter analyze`: **No issues found**. `flutter test`: **223 tests, all passed**. `dart fix --dry-run`: **Nothing to fix**.
- No TODO/FIXME/HACK comments and no unreferenced files, but several dead members (see Housekeeping).
- No crash-class bug found in the service layer. The serious problems are silent-data problems: GPS never starts if permission is not granted at first launch (packets recorded with no position, no UI warning), and deleting a coverage map while its session records orphans every later packet.
- Connect/reconnect generation handling has holes (a superseded `connect()` can tear down the newer connection). Node identity (`nodeId` vs `id`) was checked at every call site and is consistent.
- Tests are strong on pure logic and widgets; there are none for SessionManager, CSV export, DB migrations, reconnect, SignalHistory or LiveActivityService.

## Findings

### [HIGH] GPS never starts if permission is not granted at launch; recording continues with null positions and no warning
**Where:** `lib/app.dart:96-102`, `lib/services/gps_service.dart:20-37,72`
**What:**
```dart
try {
  final gps = ref.read(gpsServiceProvider);
  await gps.initialize();      // throws on denied / services off
  gps.startListening();        // skipped when initialize() throws
} catch (e) { debugPrint('GPS init failed: $e'); }
```
`startListening()` is the only call site (grep). `PacketProcessor` / `ActiveProbeService` then use `_gps.lastPosition == null`, so every `packet_events` row gets null `rx_lat/rx_lon`. `SessionManager.startSession` does not check GPS, and nothing in `lib/ui` mentions GPS/location permission (only `debugPrint`). Map dots are skipped (`event.hasGps`), the coverage map shows "No points with GPS yet".
**Trigger:** Tester taps "Don't Allow" on the location prompt (or has Location Services off), later enables it in iOS Settings and starts a session without killing the app. The whole session has no coordinates.
**Fix:** Retry `initialize()+startListening()` in `startSession` and on app resume (`didChangeAppLifecycleState`); show a banner/refuse to start a session when there is no location permission; also treat a stale `lastPosition` (check `Position.timestamp` age) as null.

### [HIGH] Deleting a coverage map while its session is recording orphans all further data
**Where:** `lib/ui/screens/coverage_map_list_screen.dart:86-90`, `lib/data/database/app_database.dart:180-191`
**What:** The delete action has no active-session check (compare `DataEraseService._checkIdle`). `deleteCoverageMap` deletes the map's sessions and packet events, but `SessionManager._activeSession`, `PacketProcessor.activeSessionId`, the ping timer and the `prefActiveSessionId` pref still point at the deleted session id. The DB has no `PRAGMA foreign_keys` (no `beforeOpen`), so `insertPacketEvent` keeps succeeding with a dangling `session_id`. The panel's packet counter (`watchPacketCount(sessionId)`) keeps counting, so it looks like it is recording, but the rows belong to no session/map and cannot be shown or exported. `endSession` updates 0 rows. Also `ping_correlations` of the deleted events are never deleted (orphan rows, and the method is not in a transaction).
**Trigger:** Start a session, switch to Coverage tab, delete that map.
**Fix:** Refuse (or end the session first) when `sessions.activeSession?.coverageMapId == map.id`; wrap `deleteCoverageMap` in `transaction()` and delete `pingCorrelations` for the map's events first.

### [MEDIUM] Superseded `connect()` / reconnect attempt tears down the newer connection
**Where:** `lib/data/radio/meshtastic/meshtastic_radio.dart:442-455, 465-504, 553-578`
**What:** `connect()` captures `gen` but its `catch (_)` does not compare it:
```dart
} catch (_) {
  _wantConnected = false;
  await _teardown(sendDisconnect: false);
  _setState(RadioConnectionState.disconnected);
  rethrow;
}
```
If the user starts connection B while A is still in `_open` (or a reconnect loop is mid-`_open`), B's `_teardown` disconnects A, A throws, and A's catch sets `_wantConnected = false` (disables auto-reconnect for B) and tears down B's link/subscriptions. `_reconnectLoop`'s catch (`_teardown` at line 574) has the same missing gen check. Related: `_open` does `if (gen != _linkGen) return;` (lines 474, 496) without disconnecting `_transport`, so `connect()` completes "successfully" with no link, and if `disconnect()` ran between lines 474-486 the BLE connection and `_fromNumSub` are leaked.
**Trigger:** Tap a second radio / Retry / Radio Setup `switchToAndApplyMobile` while the first connect is in progress; or Disconnect during a reconnect.
**Fix:** In both catch blocks `if (gen != _linkGen) rethrow/return;` before touching state; in `_open` on stale gen call `_transport.disconnect()` and throw instead of returning.

### [MEDIUM] "Signal Direction" setting does nothing
**Where:** `lib/ui/screens/settings_screen.dart:144-158`; only other references are `AppConstants.prefSignalDirection`, unused `CoverageMaps.signalDirection` column, and `getEventsInBounds(directionFilter)` which has no callers.
**What:** The Rx/Tx/Both selector persists a pref that no map/chart code reads.
**Trigger:** Any tester changing it sees no change.
**Fix:** Wire it into the map layer or remove the control (and `SignalDirection`, the DB column and `getEventsInBounds`).

### [MEDIUM] Range Test prompt appears while idle, and dismissing it silently disables logging
**Where:** `lib/services/packet_processor.dart:142-154`, `lib/services/range_test_detector.dart:25-37`, `lib/ui/screens/map_screen.dart:128-137`, `lib/ui/widgets/range_test_dialog.dart`
**What:** `shouldLogRangeTest` (which fires the prompt) runs for every Range Test packet even when `activeSessionId == null`, so connecting to a mobile near a beaconing base pops a modal dialog outside any session. `showDialog` is dismissible by tapping the barrier; that path never calls `onResult`, leaving the node `null` ("pending") so `shouldLogRangeTest` returns false forever (until the next session start calls `reset()`), and the first beacon is always dropped. Beacons from several nodes stack several dialogs.
**Fix:** Skip the detector when `activeSessionId == null`; `barrierDismissible: false` (or treat dismissal as decline and re-prompt next session).

### [MEDIUM] Radio setup / restore leaves the radio in an open edit transaction on failure
**Where:** `lib/data/radio/meshtastic/meshtastic_radio.dart:1062-1100 (applyTestProfile), 1128-1142 (setRegion), 1186-1200 (setBeacon)`; `lib/services/radio_backup_service.dart:191-220`
**What:** `beginEditSettings` is sent first and `commitSettings()` last; any exception in between (NAK, 10 s timeout, BLE drop) propagates with no cleanup/commit, so the radio keeps an open edit transaction (Meshtastic firmware defers saving config until commit). The UI just shows "Failed: <raw exception>". Also, a NAK on a mid-sequence step leaves the radio partially configured (e.g. new channels but old preset).
**Trigger:** Link drop or timeout during Radio Setup.
**Fix:** try/catch around the sequence that, on failure, attempts `commitSettings()` (or reboot) and reports which step failed; use the pre-saved backup path in the error text.

### [MEDIUM] `watchEventsForMap` providers are never disposed and re-query the whole map on every packet
**Where:** `lib/ui/screens/coverage_map_detail_screen.dart:29-42`, `lib/data/database/app_database.dart:338-346,349-367`
**What:** `_sessionsForMapProvider/_eventsForMapProvider/_pingsForMapProvider` are non-autoDispose `StreamProvider.family`. After a map's detail screen is opened once, its drift watchers stay alive; each insert into `packet_events` (every packet and ping while recording) re-runs the full select (and the ping join) for every visited map, and while the screen is open rebuilds it with all rows.
**Trigger:** Open a map with thousands of points, go back, start recording.
**Fix:** `StreamProvider.autoDispose.family`; throttle the stream for the active session.

### [MEDIUM] Map screen keeps old sessions' dots and shows unrecorded packets
**Where:** `lib/ui/screens/map_screen.dart:77-110,144-150`
**What:** `_signalDots` is only appended to (`_addDot` for every live packet, even with no session; `_loadSessionDots` inserts at index 0). A new session never clears the previous session's dots, so the live map mixes sessions up to 5000 dots; dots for packets received outside a session are drawn though they are not stored.
**Fix:** Clear `_signalDots` when the active session id changes, and only add dots while a session is active.

### [MEDIUM] No auto-connect after app restart; resumed session pings never run the key exchange
**Where:** `lib/app.dart:96-121`, `lib/services/session_manager.dart:62-77,214-237`, `lib/services/active_probe_service.dart:34-42`
**What:** On launch with an active session the radio is not connected (no auto-connect code exists, grep "autoConnect/lastRadio" empty). `_startMonitoring` -> `ActiveProbeService.start` calls `prepareToPing` immediately, which fails (`Radio not ready`, only printed). When the user later connects, `prepareToPing` is not called again, so DM pings can NAK with `PKI_UNKNOWN_PUBKEY` until the 60 s-throttled NAK handler (`_onPingReply`) fixes it. Same after any BLE reconnect where the radio lost keys.
**Fix:** Run `prepareToPing(base)` on every transition to `ready` while a session is active (ActiveProbeService can subscribe to `connectionState`).

### [LOW] `upsertNode` overwrites names and `firstSeenAt` on conflict
**Where:** `lib/data/database/app_database.dart:83-99`
**What:** `insertOnConflictUpdate` updates every provided column on an existing `node_id`: `longName/shortName/hwModel` become `''` and `firstSeenAt` resets. All current callers check `getNodeByMeshId` first, so it only triggers in a race (two packets from a new node processed concurrently: `_ensureNodeExists` has no lock and `_onPacketReceived` runs unawaited per packet). Also on conflict drift returns the last insert rowid, not the existing row's id, so the race can yield a wrong local id for that packet.
**Fix:** `insertOnConflictUpdate` only for names, or `insert(mode: insertOrIgnore)` then select; serialise `_ensureNodeExists` per node id with a pending-future map.

### [LOW] `endSession()` and `startSession()` are not re-entrancy safe
**Where:** `lib/services/session_manager.dart:97-189`
**What:** `endSession` reads `_activeSession!.id` after two awaits (line 182); a second concurrent `endSession` (UI is guarded by `_busy`, but Live Activity/other callers are not) nulls `_activeSession` first and the first throws on `!`. `startSession` awaits `_rigById` before checking `_activeSession`, so two overlapping calls both create sessions. Currently only reachable if the UI guard is bypassed.
**Fix:** Serialise lifecycle calls with a single in-flight Future/lock; capture `final s = _activeSession!` once.

### [LOW] `ActiveProbeService.stop()` does not stop an in-flight ping
**Where:** `lib/services/active_probe_service.dart:58-66,72-116`
**What:** `_activeSessionId` is never cleared. A `_sendPing` that already entered `ping()` (awaiting `beforeSend` DB work) when `stop()` ran still inserts the TX event into the ended session, registers a pending entry after `_pendingPings.clear()` and transmits a ping after End Session. `stop()` also fires `_db.timeoutPendingPing` unawaited. Pings in flight when BLE drops are recorded as `timeout` (same as out-of-range), so link loss looks like lost range in the data.
**Fix:** Null `_activeSessionId` in `stop()` and re-check it inside `beforeSend`; await the timeout updates.

### [LOW] `sendAdmin` leaves an unhandled `TimeoutException` when the write fails
**Where:** `lib/data/radio/meshtastic/meshtastic_radio.dart:992-1007`
**What:** `reply = routingStream.firstWhere(...).timeout(timeout)` is created before `await _write(...)`. If `_write` throws (not connected, BLE timeout), `reply` is never awaited and later completes with an uncaught `TimeoutException` (10 s later).
**Fix:** `reply.ignore()` in a catch around the write, or create the future after a successful write using a pre-registered completer.

### [LOW] Timestamps stored at 1 s resolution; CSV timestamps have no timezone
**Where:** `lib/data/database/tables/all_tables.dart` (all `dateTime()` columns, drift default = unix seconds, no `build.yaml` override); `lib/services/csv_export_service.dart:75`
**What:** Packet events within the same second tie in `ORDER BY timestamp` (order then arbitrary), and `SignalHistory._loadSession` / ping RTT ordering uses these. CSV writes `event.timestamp.toIso8601String()` of a local `DateTime`, i.e. `2026-10-15T22:24:10.000` with no offset/`Z`, ambiguous when files are shared across timezones. The CSV formula-injection case (node names starting with `=`) is not handled either; quoting of commas/quotes/newlines is handled by the `csv` package.
**Fix:** Export `timestamp.toUtc().toIso8601String()`; order by `timestamp, id`.

### [LOW] Missing `mounted` check and unguarded failure paths in dialogs
**Where:** `lib/ui/widgets/session_panel.dart:390-398` (`_newRig`: `setState` after `await getRigProfile`, only checked before it); `lib/ui/widgets/create_map_dialog.dart:76-97` (`_create` has no try/catch, so a DB error leaves `_saving = true` and the Create button permanently disabled); `lib/ui/screens/node_list_screen.dart:~97` (`TextEditingController` never disposed).
**Fix:** Add `if (!mounted) return;`, try/finally resetting `_saving`, dispose the controller.

### [LOW] Raw exceptions shown to users
**Where:** `radio_setup_screen.dart:_run` (`'Failed: $e'`), `settings_screen.dart:_erase`, `session_panel.dart:_startSession` (`Could not start session: $e` shows `Bad state: ...`), `connection_banner.dart:_connectHelp` ("Details: $text" is intentional).
**Fix:** Map `StateError`/`TimeoutException` to plain messages.

### [LOW] `ProEntitlement.refresh()` is not re-entrant
**Where:** `lib/services/pro_entitlement.dart:~290-310`
**What:** `_collecting = []` / `finally { _collecting = null }` are shared state. App resume + `restore()` (or start) overlapping makes the first call null `_collecting` while the second still reads `_collecting!` (caught, logged as a failed refresh), and late native events after the five microtask yields are merged by `_onPurchases` only afterwards (momentary downgrade then self-heal). Not reproducible without a device, flagged from reading.
**Fix:** Coalesce concurrent refreshes into one in-flight Future.

### [LOW] Disconnect from the radio sheet during a session has no confirmation
**Where:** `lib/ui/widgets/connection_banner.dart:~262` (`radio.disconnect(); Navigator.pop`).
**What:** Disables auto-reconnect while the session keeps "recording" (monitor goes `radioLost`).
**Fix:** Confirm when `activeSessionProvider` is non-null.

## Checked, OK
- `PacketProcessor` single subscriber: `start()` is guarded by `isRunning`; cancelled in `stop()/dispose()`.
- `nodeId` (mesh) vs `id` (DB) usage: every call site (`baseMeshNodeIdForMap`, `OutOfRangeMonitor`, `LiveActivityService`, `SessionRadios`, `node_list_screen`, `create_map_dialog`, `coverage_map_detail_screen:159`, CSV) uses the right one.
- Packet ids: `newPacketId()` yields 1..0xFFFFFFFE; broadcast `0xFFFFFFFF` is only used as a destination; protobuf uint32 maps to non-negative Dart ints and SQLite holds them.
- `ActiveProbeService._pendingPings` is cleaned on outcome, timeout (radio-side timer) and `stop()`; `outcome.responder!` at line 174 is safe (the null-responder error case returns earlier; NAK replies carry `packet.from`).
- Drift migrations v1->v6: every step (2,3,4,5,6) has a matching `addColumn/createTable`; none destructive. (Indexes only in `onCreate`, which is correct since v1 had them.) Unverifiable here: whether `Nodes.lastLat/lastLon`, `Sessions.pingIntervalSec/rangeTestActive/packetCount`, `PacketEvents.channelIndex/viaMqtt` existed in v1, since no git history/migration tests; if any was added after a released v1 it has no migration step.
- Erase flows: `DataEraseService` never closes the DB (deletes rows, refuses during a session), so there are no writes-after-close; `deleteAllMeasurements` deletes in FK-safe order inside a transaction.
- `RadioBackupService` round-trip: backups store exact protobuf bytes (channels, lora, rangeTest, owner) and restore writes the same bytes; node number is verified before restore.
- Timers/subscriptions: `ActiveProbeService`, `OutOfRangeMonitor`, `SignalHistory`, `LiveActivityService`, `AirtimeMeter`, `_ScanDialog`, `_ProgressLabel`, `CoverageMapDetailScreen` cancel theirs; `radioChannelStatsProvider` and `airtimeMeterProvider` cancel on dispose; app-lifetime `.listen` in `app.dart:117` is intentional.
- BLE awaits have timeouts: connect 15 s, pairing 90 s, handshake 60 s, `_write` 15 s, `sendAdmin` 10 s, ping 30 s; `read`/`discover` rely on flutter_blue_plus defaults.
- Airtime/duty math: all divisions are by constant-positive quantities (`bwKHz`, `denominator`, `intervalSec` guarded `<= 0`); `fit()` guards `samples.isEmpty` and `sxx`.
- `.first/.last/.reduce` uses reviewed: all guarded by emptiness checks or constructed non-empty (`rig_comparison.dart:204`, `coverage_calibrator.dart:138`, `terrain_profile.dart:142`, `signal_charts_panel.dart:339,398`).
- CSV column count matches the header (25 columns) and quoting is delegated to `ListToCsvConverter`.
- Role/RadioRoles notifier: `RadioSetupScreen` passes the provider's `RadioRoles` instance, so UI refreshes after `assign`.

## Untested risk areas
No test file references these:
- `SessionManager` (`lib/services/session_manager.dart`): start/end/resume (`initialize`), double calls, stats tracking.
- DB migrations (`app_database.dart` `onUpgrade`) and `deleteCoverageMap`/`deleteUnusedNodes`.
- `CsvExportService.exportSession` (only `csvFileName` is tested).
- `MeshtasticRadio` connect generations, `_reconnectLoop`, `_onLinkLost`, `_teardown`, `resetNodeDb`, `commitSettings` NAK-vs-reboot logic; `BleTransport`, `RadioScanner`.
- `RadioBackupService.save/list/restore` against files.
- `SignalHistory._loadSession`, `LiveActivityService` (incl. the Swift bridge), `GpsService` permission paths.
- `OutOfRangeMonitor` radioLost/notification timing paths with real timers; `PacketProcessor` concurrent packets for a new node.
- `ProEntitlement.refresh` overlap and late-event ordering against real StoreKit.

## Housekeeping
- `dart fix --dry-run`: Nothing to fix. `flutter analyze`: clean. No TODO/FIXME/HACK in `lib/` or `test/`.
- Dead code (definition with no other reference): `AppConstants.defaultGpsBackfillWindowSec`, enums `CollectionTier` and `SignalDirection` (`lib/utils/constants.dart`), `AppDatabase.getActiveSession`, `watchActiveSession`, `insertPacketEventsBatch`, `getEventsInBounds`, `PacketEvent`-model getter `ProcessedSignalEvent.isDirect`, `OutOfRangeMonitor.isMonitoring`, `OpenTopoDataSource.requestsToday`, `MeshtasticRadio.sendText`, DB columns `CoverageMaps.colorMetric/signalDirection` (settings use prefs instead), `Sessions.packetCount` (written at end, read nowhere beyond schema).
- Missing from `keptPrefs` but intentionally erased: `radio_contacts_v1` (own radios' keys) is wiped by Erase everything; after that, ping key exchange relies on over-the-air NodeInfo until Radio Setup is re-run. Consider keeping it with the channel key.
- `lib/data/radio/meshtastic/meshtastic_regions.dart:17` `pbCode` uses `firstWhere` with no `orElse` (a region code missing from the vendored proto would throw `StateError`); safe today, but worth a unit test iterating `MeshtasticRegions.all`.
