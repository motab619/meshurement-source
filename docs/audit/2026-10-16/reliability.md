# Field reliability audit (read-only)

Tree audited: `/private/tmp/claude-501/-Users-andybrunker-develop-mesh-analyzer/13132be7-c894-490b-a160-aef9add37105/scratchpad/beta-audit`. All paths below are relative to it. `lib/proto/**` and `docs/beta/` ignored.

## Summary

- The locked-phone design is sound on paper: `UIBackgroundModes` has `bluetooth-central` and `location`, the GPS stream is restarted with background updates when a session starts, auto-pause is off, and every packet and ping is written to SQLite immediately. A 90-minute walk should survive with the screen locked, at roughly 20-25% battery.
- The biggest data-loss risk is the Range Test confirmation prompt. Range Test packets (the main data source) are dropped until a dialog is answered. That dialog is dismissible by tapping outside, is never re-asked, and returns before the out-of-range monitor sees the packet. It re-arms at every session start, which is exactly when the phone goes into a pocket.
- After an iOS kill, crash or manual relaunch the session resumes in the DB but the BLE link does not. There is no auto-connect on launch and no CoreBluetooth state restoration, so recording stops silently until the tester reopens the app and taps Connect.
- GPS health is never surfaced. If location is denied or services are off, `startListening()` is never called and is never retried. Sessions then record rows with null position, and no warning appears.
- Radio Setup backs up before any destructive admin message, treats a lost commit ACK as success, and handles an UNSET region on the connected radio. The weak spots are the base-first flow (the mobile's region can silently become US) and half-applied transactions, which surface only as a raw exception string.
- Demo mode and PRO_OVERRIDE are not reachable by testers in release. `print` volume is low. Alert throttling and the radio-lost vs out-of-range distinction work as designed.

## Scenario walkthroughs

### 1. Phone locked for 90 minutes while recording: ✅ (with caveats)
- `ios/Runner/Info.plist:64-68` has `bluetooth-central` and `location`. CLAUDE.md is accurate on this.
- `SessionManager._startMonitoring` calls `_gps.setBackgroundMode(true)` (`lib/services/session_manager.dart:215`). That cancels and re-creates the stream with `allowBackgroundLocationUpdates` and `showBackgroundLocationIndicator` (`lib/services/gps_service.dart:63-81`).
- Geolocator settings: `LocationAccuracy.high` (about 10 m, not `best`), `distanceFilter: 5`, `ActivityType.fitness`, `pauseLocationUpdatesAutomatically: false`. Not wasteful. The GPS hardware stays on, which is the main battery cost.
- Only the foreground stream starts at launch (`lib/app.dart:98-99`). Background mode is switched on at session start while the app is in the foreground, which iOS requires.
- Dart timers (ping, 60 s heartbeat at `meshtastic_radio.dart:498`, out-of-range clock, 5 s Live Activity poll) keep firing because the location mode keeps the process running. The Live Activity poll only does work when state changed.
- Nothing in the app auto-ends a forgotten session (see F8). The map `_signalDots` list is capped at 5000. `SignalHistory` is trimmed to 2 h by time. Memory is bounded.
- Position quality caveats are in F5 and F9.

### 2. BLE link drops: ⚠️
- `_onLinkLost` tears down, then `_reconnectLoop` retries forever with 2 s, 4 s, ... 60 s backoff (`lib/data/radio/meshtastic/meshtastic_radio.dart:546-578`). Each attempt has a 15 s connect timeout and no `autoConnect` (`lib/data/radio/ble/ble_transport.dart:45`).
- Pings are paused implicitly. `ActiveProbeService._sendPing` returns silently while `!isReady` (`active_probe_service.dart:130`) and resumes on the next tick after reconnect. A ping in flight when the link drops is recorded as `error:SEND_FAILED` or `timeout`.
- Only radio packets are recorded. GPS is not logged as a track, so a radio-lost period leaves a hole in the data. The UI says so: "nothing is being recorded until it reconnects" (`lib/ui/widgets/session_panel.dart:151-159`).
- `OutOfRangeMonitor` distinguishes `radioLost` from `outOfRange` (`out_of_range_monitor.dart:88-119`). It pauses the clock, notifies "Radio disconnected" after a 30 s grace and notifies "Radio reconnected". ✅
- A drop mid-transaction (`beginEdit` to `commit`) leaves no recovery path. The UI shows `Failed: <raw exception>` (see F7).
- A radio that reboots after commit counts as success. `commitSettings` swallows a timeout or an error when `!isReady` (`meshtastic_radio.dart:1040-1049`). ✅

### 3. App killed or crashed mid-session: ⚠️
- Persistence is write-per-packet (`packet_processor.dart:178-196`, `active_probe_service.dart:142`). Nothing is lost except what arrives while the process is dead. ✅
- `SessionManager.initialize` resumes the session from the `active_session_id` pref (`session_manager.dart:62-77`) and re-attaches monitoring, pings and GPS background mode.
- The BLE connection is not resumed. `app.dart:117-121` only listens for state changes. Nothing calls `connect` except user taps. There is no state-restoration option and no `FlutterBluePlus.setOptions`. The mobile radio stays disconnected until the user opens the app and taps Connect (F2).
- In-memory buffers are bounded, as noted in scenario 1. The `ActiveProbeService._pendingPings` and radio `_pendingPings` maps clear on timeout.

### 4. GPS edge cases: ⚠️
- A packet arriving with no fix is stored with null `rxLat`/`rxLon` (`packet_processor.dart:157-190`). It is not dropped. The map skips it (`event.hasGps`).
- `defaultGpsBackfillWindowSec` is defined but unused (`lib/utils/constants.dart:39`), so there is no backfill.
- `lastPosition` is applied to every packet no matter its age. There is no timestamp on the stored fix and no stale check (F5).
- `gpsAccuracy` is stored per event (`all_tables.dart:117`) and exported to CSV, but nothing filters or flags poor accuracy.
- Denied or disabled location: `GpsService.initialize()` throws and `startListening()` is never reached (`app.dart:96-102`). There is no retry and no UI (F3).

### 5. Out-of-range alerts and Live Activity: ⚠️
- Clock: starts at `configure()` (session start), resets on any packet from the base (`out_of_range_monitor.dart:71-85`), timeout is `max(pref 90 s, 3 x ping interval)` (`session_manager.dart:227`).
- Notifications are suppressed in the foreground (line 149). They use a fixed id 0, so "Out of range" and "Back in range" replace each other and there is no stacking. One notification fires per transition. ✅
- Range Test packets that are gated by the confirmation prompt never reach `onPacketReceived`. With pings off that causes false "Out of range" alerts (F1). The timeout also ignores the base beacon interval (F6).
- The notification permission prompt is fired from `main()` at first launch via `DarwinInitializationSettings` (`lib/main.dart:25-34`). The app never checks the result, so denial means silent failure (F11).
- Live Activity: `start` on session, `update` when state changed (polled every 5 s plus on link and range changes), `end` on session end. Local updates carry a 10-minute `staleDate` (`ios/Runner/LiveActivityBridge.swift:86`). Update frequency is a few per minute at most, which is fine for local updates. `NSSupportsLiveActivitiesFrequentUpdates` is not set.
- If `start` returns "disabled", "unsupported" or "error", the service sets `problem` and prints. The notifier is never read by any UI, so the tester gets no explanation (F10).

### 6. Radio Setup robustness: ⚠️
- The backup is written before any admin message that changes settings (`radio_profile_service.dart:147`). `RadioBackupService.save` throws if the config was not read yet, which aborts before any change. ✅
- The backup is skipped if the radio is already on the MeshTest channel (line 81). That protects the original backup.
- Firmware differences: there is no firmware version gating at all. `metadata.firmwareVersion` is read but never used.
  - `add_contact` (2.6+) failures are caught and shown as "(Skipped: ...)" (`radio_profile_service.dart:189-195`). On older firmware that costs up to 10 s per contact (the `sendAdmin` timeout). The base then does not appear in the mobile's node list (F9).
  - `resetNodeDb` (2.7+ keeps favourites) forgets the base on older firmware, as the code comment says. It is reached from Settings, is blocked during a session, and its result message reports how many were forgotten.
- UNSET region on the connected radio is handled (`_ensureRegion`, `radio_setup_screen.dart:360-371`). The base-first flow has a hole (F4).
- The commit reboot is handled (see scenario 2). The app auto-reconnects.
- Picking the base as "mobile" and vice versa is only partly guarded (F6b / F8 area, see Findings).

### 7. First-run experience: ⚠️
- Prompt order: Notifications (at `main()`, before any UI or explanation), then Location (`GpsService.initialize()`, which requests When-in-use), then Bluetooth (on first Connect tap, `connection_banner.dart:~322`), then the iOS pairing PIN on first characteristic access.
- Empty states are decent. The Session panel says "Connect to your radio first". A public-channel radio gets an "Open Radio Setup" link. The Coverage tab has a "No coverage maps yet" state. Creating a map needs a known base node, and the empty-list text explains that.
- Stuck points: a tester who denies Location sees no warning (F3). On firmware without `add_contact`, a fresh private channel can leave the base missing from the picker, so "New map" stays disabled (F9). The Range Test prompt can eat data silently (F1).

### 8. Demo mode and debug leftovers: ✅
- Demo mode needs `-MeshDemo` launch args or the `MESH_DEMO` env var (`lib/demo/demo_mode.dart`). A TestFlight tester cannot set either. The AppDelegate only reports `ProcessInfo.arguments`.
- `PRO_OVERRIDE` is honoured only when `kDebugMode && fromEnvironment` (`lib/services/pro_entitlement.dart:237`). Release builds ignore it. The CLAUDE.md statement "debug builds only" is accurate.
- `print()` count outside proto and demo is 24. All are on error or event paths (link lost, reconnect failed, ping NAK), so volume is low. `debugPrint` of BLE device names in the connect dialog does run in release but only during user scans.
- `DemoMode.detect()` can add up to 3 s to launch if the `mesh_analyzer/app` channel is not ready (`MissingPluginException` retry). The AppDelegate registers it during engine init, so this is not seen in practice.

## Findings

### [HIGH] F1. Range Test packets are dropped until a dismissible, non-repeating dialog is answered
**Where:** `lib/services/range_test_detector.dart:25-37`, `lib/services/packet_processor.dart:142-154, 198-199`, `lib/ui/screens/map_screen.dart:127-137`, `lib/ui/widgets/range_test_dialog.dart`, `lib/services/session_manager.dart:158`.
**What:**
- The first Range Test packet from a node emits a prompt and is not logged. Every later packet from that node is also not logged while the state is "pending".
- `showDialog` in `_promptRangeTest` uses the default `barrierDismissible: true`. Tapping outside the dialog never calls `onResult`, so the node stays pending for the whole session and the prompt is never shown again.
- The `return` at `packet_processor.dart:149` happens before `_outOfRangeMonitor.onPacketReceived(fromNode)` at line 199. A pending or declined base is therefore never "heard" by the monitor.
- `startSession` calls `_rangeTestDetector.reset()`. A tester who confirmed the prompt while connecting gets prompted again at session start. A resumed session after relaunch starts with empty state and prompts again.
**Scenario:** Tester taps Start Session, locks the phone and pockets it. The base beacon arrives 15 s later. The dialog is raised in an app they cannot see, and no Range Test point is recorded for the whole walk. If pings are off there is also a false "Out of range" notification after 90 s. With pings on, only ACKs and pings are recorded, so the map is sparse.
**Fix:** Make the dialog `barrierDismissible: false`, or treat a dismiss as "ask again". Preferably auto-confirm Range Test packets from the session's base node (the map's base) and prompt only for other nodes. Call `_outOfRangeMonitor.onPacketReceived` for the base before the range-test gate. Do not `reset()` confirmations that the user already gave for the same map base.

### [HIGH] F2. After an app relaunch the radio never reconnects on its own, and iOS cannot restart the app for BLE
**Where:** `lib/app.dart:85-133` (no connect call), `lib/data/radio/ble/ble_transport.dart:45` (no `autoConnect`), no `FlutterBluePlus.setOptions(restoreState: ...)` anywhere, `lib/services/session_manager.dart:62-77`.
**What:**
- `SessionManager.initialize` resumes the DB session and background GPS, but the radio stays `disconnected`. The Live Activity goes to `link: disconnected` and eventually stale.
- The OutOfRangeMonitor starts in `radioLost` without arming the 30 s "Radio disconnected" timer (`configure` only sets state), so no notification either.
**Scenario:** iOS terminates the app under memory pressure at minute 50 of a 90-minute drive, or the tester force-quits it. No data is recorded for the rest of the trip. The tester has no hint, because a killed app cannot notify. When they reopen the app they must notice the red "Connect radio" pill and rescan.
**Fix:** Save the last mobile descriptor id and auto-connect on launch when a session is active (or always). Consider CoreBluetooth state restoration and `autoConnect` so iOS relaunches the app when the radio reappears. At minimum, show a persistent "Session resumed but radio not connected - tap to reconnect" banner on the Live tab.

### [HIGH] F3. GPS failure is invisible and never retried
**Where:** `lib/app.dart:96-102`, `lib/services/gps_service.dart:20-37`, `lib/services/session_manager.dart:97-165`, no UI reads GPS state (grep of `lib/ui` for gps/location finds only map centring).
**What:**
- Denied, restricted or disabled location makes `initialize()` throw. `startListening()` is skipped and only a `debugPrint` is emitted. There is no later retry when the tester enables location in Settings or toggles Location Services, until a full app restart.
- `startSession` does not check for a position. Approximate location (Precise off) is also not detected.
- Packets are stored with null lat/lon and a session that looks normal in the UI shows no dots.
**Scenario:** Tester taps "Don't Allow" on the first-launch prompt (which also stacks with the notification prompt) or has Precise Location off. They record an hour and get an empty coverage map.
**Fix:** Surface a GPS status chip (no permission / no fix / approximate). Refuse or warn at Start Session when there is no fix. Retry `initialize()` + `startListening()` on app resume and when the Start button is tapped. Explain why location is needed before the iOS prompt.

### [MEDIUM] F4. Base-first Radio Setup can give the mobile a different region than the base
**Where:** `lib/services/radio_profile_service.dart:101-104, 251-260`, `lib/data/radio/meshtastic/meshtastic_radio.dart:1144-1157`, `lib/ui/screens/radio_setup_screen.dart:285-301, 360-371`.
**What:** `regionName` reads the currently connected (`_mobile`) radio. In the base flow the base is configured first with a region the tester chose. `switchToAndApplyMobile` then connects the phone to the mobile and writes `regionName` from that radio. `_ensureRegion` is not called in that flow. If the mobile is a new radio (UNSET) this silently becomes `US`. If it has a different region it is applied as-is without checking it matches the base.
**Scenario:** An EU tester sets the base to EU_868 and then the new mobile to US. The radios are on different frequencies, never hear each other, and the US setting is illegal in the EU.
**Fix:** Pass the region used for the base through the flow (store the chosen region in prefs or the role record), or run `_ensureRegion` before step 2. Show the region in the confirm dialog.

### [MEDIUM] F5. Position fix has no age or accuracy gate
**Where:** `lib/services/packet_processor.dart:157-170`, `lib/services/active_probe_service.dart:139, 216`, `lib/services/gps_service.dart:83-86`.
**What:** `lastPosition` is applied no matter how old it is. With `distanceFilter: 5` a lost fix (tunnel, vehicle) looks the same as standing still, so old positions are stamped on new packets. Fix time is not stored. Accuracy is stored but never used to colour, filter or flag points. The first packets after an indoor start are stored without a position; there is no backfill. While moving fast (driving), the 1 Hz fix is up to 30 m out of date at 100 km/h.
**Scenario:** Drive through a tunnel or park garage: points are painted at the last outdoor fix. Start indoors: first points are missing or have 100 m+ accuracy.
**Fix:** Store the fix timestamp, drop or flag positions older than about 10 s or with accuracy worse than about 50 m, and show a "waiting for GPS" state. Use `ActivityType.otherNavigation` or `automotiveNavigation` when speed is high.

### [MEDIUM] F6. Out-of-range timeout ignores the base's beacon interval
**Where:** `lib/services/session_manager.dart:222-228`, `lib/services/radio_profile_service.dart` / Radio Setup beacon choices (`radio_setup_screen.dart:39-46`).
**What:** `timeoutSec = max(pref, 3 x pingInterval)` where `pingInterval` is 0 when pings are off. The beacon can be set to 120 s or 300 s. With pings off (or pings failing), a 300 s beacon makes the monitor flip to "Out of range" every cycle and back to "Back in range", each with a notification.
**Scenario:** Tester picks a 5-minute beacon and "Ping base node" off: a notification storm while standing next to the base.
**Fix:** Compute timeout from the base's known beacon interval (store it with the role or session) as well, for example `max(pref, 3 x max(ping, beacon))`.

### [MEDIUM] F7. Mid-transaction failure in Radio Setup gives a raw error and no recovery hint
**Where:** `lib/data/radio/meshtastic/meshtastic_radio.dart:1056-1117, 986-1009`, `lib/ui/screens/radio_setup_screen.dart:201-224`.
**What:** `applyTestProfile` sends `beginEdit`, 8 channels, LoRa, module config, owner, then `commit`, each with a 10 s ACK wait. If the link drops or a step times out between `beginEdit` and `commit`, the exception propagates. The UI shows `Failed: TimeoutException after 0:00:10...` or `Failed: Bad state: Not connected to a radio`. Nothing tells the tester that the radio may be half-configured, or to power-cycle it, restore from backup, or retry. The auto-reconnect continues in the background.
**Scenario:** Phone moved away or radio battery dips during the 12+ admin messages. The tester sees a cryptic error and may leave one radio on the new channel and the other not.
**Fix:** Catch failures in `_run` and show "Setup did not finish. Power-cycle the radio, reconnect, and run Radio Setup again; your original settings are in Backups." Optionally verify after reconnect that channel and preset match.

### [MEDIUM] F8. Wrong-role selection is only lightly guarded
**Where:** `lib/ui/screens/radio_setup_screen.dart:303-319, 81-84`, `lib/services/session_manager.dart:97-165`, `lib/services/radio_roles.dart:78-89`.
**What:**
- In Radio Setup, scan results are tagged with role chips, but tapping a radio whose role is already "mobile" as the base (or the reverse) shows only the generic confirm dialog. `assign()` silently moves the role.
- The default role for an unknown connected radio is "Mobile".
- `startSession` never checks that the connected radio is the base or is beaconing as a Range Test sender. Only the connect dialog (`_confirmBase`) and the banner colour flag a known base.
**Scenario:** Tester ends up with the phone on the radio that sends beacons. A session records only its own pings' ACKs and never hears the beacon, and the out-of-range monitor alerts.
**Fix:** Warn in Radio Setup when the chosen radio already has the other role, and warn or refuse at Start Session when the connected radio's role is base or its Range Test sender setting is on.

### [MEDIUM] F9. Base can be missing from the "New map" picker on firmware without add_contact
**Where:** `lib/services/base_node.dart:61-125`, `lib/ui/widgets/create_map_dialog.dart:76-95, 133-176`, `lib/services/radio_profile_service.dart:167-197`.
**What:** The picker only lists nodes the radio or the app DB knows. `knownBaseNodeNum` supplies the number, but no entry is synthesized for a base that has not been heard yet. On 2.6+ `add_contact` inserts the base. On 2.5 (or if the radios were not within range during setup) the list on a fresh private channel can be empty ("No nodes known yet"), which blocks map creation and therefore session start.
**Scenario:** Tester on 2.5 firmware sets up both radios, drives away, and cannot create a map until the base is heard.
**Fix:** Add a synthetic "YOUR BASE" option from `base_node_num` even when not heard. Also warn about firmware below 2.6 using `metadata.firmwareVersion`.

### [MEDIUM] F10. Live Activity failure is silent
**Where:** `lib/services/live_activity_service.dart:49-50, 102-120` (the `problem` notifier), grep shows no UI reader.
**What:** If `start` returns "disabled" (Live Activities off in Settings), "unsupported" or "error: ...", only a `print` runs. The tester believes the lock-screen view is working. A race exists where `_onSession(null)` can arrive while `start` is awaiting, leaving an orphaned activity (`_running` set true after `_end` already ran).
**Fix:** Show `problem` in the session panel ("Live Activity is off: enable it in Settings"). Re-check `_sessionId` after the `await`.

### [MEDIUM] F11. Notification permission is requested cold at launch and a denial is never reported
**Where:** `lib/main.dart:25-34`, `lib/services/out_of_range_monitor.dart:145-164`.
**What:** The permission prompt appears at first launch with no context, stacked with the Location prompt. If denied, `_notifications.show` fails silently (caught and printed). The out-of-range and radio-lost alerts, the app's main safety feature, never reach the locked phone, and nothing says so. Notifications use the default interruption level, so a Focus mode will hide them.
**Fix:** Request notification permission when the first session starts, with an explanation. Check the authorization status and show a banner in the Session panel when alerts cannot be delivered. Consider time-sensitive interruption level.

### [LOW] F12. Forgotten session keeps GPS running
**Where:** `lib/services/session_manager.dart:174-189`, `lib/services/gps_service.dart:63-81`.
**What:** A session never ends by itself; background GPS with the blue indicator continues until the tester ends it, even after the radio has been gone for hours.
**Fix:** Remind or auto-end after a long radio-lost period, or after N hours.

### [LOW] F13. Live Activity staleness and update budget
**Where:** `ios/Runner/LiveActivityBridge.swift:86`, `lib/services/live_activity_service.dart:120, 158-168`.
**What:** `staleDate` is only set on updates, and updates are skipped when state is unchanged, so a quiet but healthy session can grey out after 10 minutes (the initial request has `staleDate: nil`). `NSSupportsLiveActivitiesFrequentUpdates` is absent; local updates are fine today but may be throttled by the system if the cadence increases.
**Fix:** Send a heartbeat update every few minutes even if the state is the same.

### [LOW] F14. Smaller items
- `lib/services/range_test_detector.dart:30-36`: the pending state never times out (part of F1).
- `lib/app.dart:96-102`: the GPS stream runs in the foreground whenever the app is open, even with no session, to centre the map. Small battery cost.
- `lib/data/database/app_database.dart:320`: `getActiveSession` uses `getSingleOrNull`. A crash between `createSession` and `prefs.setInt` could leave an orphan active row and later throw "too many elements" if a second active row appears. Unlikely.
- Sessions resumed after relaunch keep the original `startedAt` with no marker for the gap.
- `ActivityType.fitness` is used for driving as well as walking.

## Checked, OK
- `UIBackgroundModes` has `bluetooth-central` and `location` (`ios/Runner/Info.plist:64-68`), with Always and When-in-use usage strings, plus `NSBluetoothAlwaysUsageDescription`.
- Geolocator settings: `high` accuracy, `distanceFilter: 5`, `pauseLocationUpdatesAutomatically: false`; background and indicator toggled together; stream restarted on mode change (`gps_service.dart:63-81`).
- Permission_handler iOS macros are set in the Podfile (`PERMISSION_BLUETOOTH`, `PERMISSION_LOCATION*`, `PERMISSION_NOTIFICATIONS`), so permission status is real.
- Persistence is per-packet, with no batching to lose in a crash. Each packet handler is wrapped in try/catch.
- Memory is bounded: map dots capped at 5000, `SignalHistory` trimmed to 2 h, ping maps cleared on timeout or outcome.
- Heartbeat 60 s and the FromNum drain are implemented as documented (`meshtastic_radio.dart:498, 607-628`).
- Reconnect loop: exponential backoff 2 s to 60 s, generation counter prevents stale loops, handshake clears stale config.
- `OutOfRangeMonitor` radioLost vs outOfRange logic, 30 s grace, single "Radio disconnected" notification, foreground suppression, fixed notification id so alerts replace each other (`out_of_range_monitor.dart`).
- `SessionManager.startSession` refuses on the public channel and when the radio is not ready (`session_manager.dart:108-115`); the Session panel explains both.
- Backup happens before any destructive admin message and aborts if config was not read (`radio_profile_service.dart:147`, `radio_backup_service.dart:136-141`); backup skipped when already on the test channel.
- Commit-reboot ACK loss treated as success; reconnect follows automatically.
- UNSET region is handled for the connected radio (`_ensureRegion`) and in the connect flow.
- Data erase is blocked during a session and keeps the channel key, roles and Pro cache (`data_erase_service.dart:31-37, 70-72`).
- `PRO_OVERRIDE` only in debug; demo mode only via launch args or env not available to testers; `print()` volume is low.
- `Live Activity` is ended on session end and leftover activities are cleared on start.
- DB uses `NativeDatabase.createInBackground`; no entitlements file overriding the default file protection, so writes continue with the phone locked after the first unlock.
