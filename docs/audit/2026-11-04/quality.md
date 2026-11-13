# Quality and reliability audit, update (read-only)

Tree: `field-build-oct23` at `ab1a7cc` plus the uncommitted working tree (map_screen.dart, coverage_map_detail_screen.dart, the new estimate_samples.dart and its test, tool/make_icon.py and tool/icon_art.png). 98 commits ahead of `main`, 280 files changed. `lib/proto/**` and `docs/beta/` were not audited. This report replaces both `2026-10-16/quality.md` and `2026-10-16/reliability.md` for these areas.

## Summary

- `flutter analyze`: **No issues found** (6.5 s).
- `flutter test` (full suite, once): **973 tests, all passed, 0 failed, 0 skipped** (about 45 s). The only noise is the expected `DiagLog: no documents dir: MissingPluginException(...)` line from path_provider in the test host.
- `dart pub outdated`: 23 direct dependencies are behind; the big ones are major versions (flutter_blue_plus 1.36 to 2.3, flutter_riverpod 2.6 to 3.4, geolocator 13 to 14, flutter_local_notifications 18 to 22, share_plus 10 to 13, file_picker 8 to 13, protobuf 4 to 6). `sqlite3_flutter_libs` is still on the EOL line (latest is `0.6.0+eol`). `riverpod_annotation` (and the dev `riverpod_generator`) still have no import anywhere. `uuid` is now used (`lib/services/ai_analysis.dart`). Every other declared package is imported. NOTICE lists the new runtime packages (`flutter_compass`, `archive`).
- Of the 32 prior quality and reliability findings: **13 fixed, 9 partly fixed, 10 still open** (table below). The three prior reliability HIGHs are fixed (Range Test prompt, GPS) or mostly fixed (auto-reconnect after relaunch, one attempt only).
- New findings: **0 HIGH, 4 MEDIUM, 15 LOW**.
- The two uncommitted features each have a real bug that the new tests do not reach: the estimate layer paints locally refused pings (NAKs, throttling) as "no margin" silence, contrary to its own doc comment; and with the rotate gesture now always on, an ordinary two-finger pinch zoom counts as a "twist" and switches heading up off for good.
- The MeshCore trace ping turns a command or Bluetooth write timeout into a ping `timeout`, so a busy radio looks like lost range in the data, the beacon miss count and the out-of-range clock.
- The service layer is in much better shape than on 10-16: node creation is serialised, map delete is guarded and transactional, the Live Activity start race has a generation guard, the out-of-range window accounts for beacons and flapping, and beacon misses are not synthesised while the radio link is down.

## Findings

### [MEDIUM] Estimated layer counts locally refused pings as "no margin" silence (uncommitted)
**Where:** `lib/services/estimate_samples.dart:46-47, 63-75`; `lib/services/active_probe_service.dart:311-352`; `lib/data/radio/meshtastic/meshtastic_radio.dart:232-236, 1216-1264`; chip text in `lib/ui/screens/coverage_map_detail_screen.dart:722-729`.
**What:** The doc comment says "NAKs and throttled pings are not silence: the radio refused to send, nothing was on air", and the `pings` loop honours that by status. But the `rx` loop also turns every `ack` event with no SNR/RSSI into a silence sample, whatever its correlation status. `ActiveProbeService._onOutcome` inserts an `ack` row for every outcome with a responder, including `throttled` and `error:<reason>`. A locally generated NAK (firmware 2.7.19+ `PKI_SEND_FAIL_PUBLIC_KEY`, duty-cycle or rate-limit NAKs) comes from our own node with `rxRssi == 0`, so `_rxSnrOf`/`_rxRssiOf` return null and the row has no signal. Each of those rows becomes a 0 dB sample at the phone's position, and is counted in "N unanswered pings count as no margin".
**Why it matters:** After a node list reset every ping is refused locally until the key is re-added, and with "Faster than recommended" the duty-cycle limiter can refuse many pings in a row. Both paint a red stretch where nothing was transmitted, which is exactly the false picture the change was meant to remove, and the chip overstates the count. The new test only covers the status branch for pings (`test/estimate_samples_test.dart:577-594`), not ack rows from refused pings.
**Fix:** Decide silence from the ping correlation, not from the ack row: build the silence set from `pings` only (timeout: tx position; received/implicit with an ack event that has no usable signal: ack position via `correlation.ackEventId`), and skip `ack` rows in the `rx` loop unless they carry a signal. Add a test with a `throttled` and a local `error:PKI_SEND_FAIL_PUBLIC_KEY` ping whose ack row has null SNR.

### [MEDIUM] A pinch zoom turns heading up off (uncommitted)
**Where:** `lib/ui/screens/map_screen.dart:92-101, 395-397`; flutter_map 8.2.2 `lib/src/gestures/map_interactive_viewer.dart:598-631, 709-730`; test `test/map_compass_test.dart:110-114, 166-194`.
**What:** The map now always uses `InteractionOptions(flags: InteractiveFlag.all)` with the default `enableMultiFingerGestureRace: false`. In that mode flutter_map applies pinch zoom, pinch move and rotate together and starts rotating as soon as `currentRotation != 0.0`, i.e. on almost every two-finger gesture; it then calls `moveAndRotateRaw(..., source: MapEventSource.onMultiFinger)`, which emits a `MapEventRotate`. The new listener treats any `MapEventRotate` whose source is not `mapController`/`fitCamera` as a deliberate twist and calls `_setHeadingWanted(false, keepRotation: true)`, which also writes `prefMapHeadingUp = false`.
**Why it matters:** Zooming in or out with two fingers, the most common map gesture in a car, silently switches heading up off, leaves the map a few degrees off north and forgets the preference. Before this change the rotate flag was off while heading up was on, so this could not happen. The test simulates a twist by calling `rotateRaw` directly, so it cannot catch it.
**Fix:** Only treat a real twist as taking over: either set `enableMultiFingerGestureRace: true` with a `rotationThreshold` (about 15 to 20 degrees), or track the rotation at `MapEventRotateStart` and turn heading up off only when the gesture has rotated past a threshold by `MapEventRotateEnd`. Prefer an allow list of user sources (`onMultiFinger`, `cursorKeyboardRotation`, `keyboard`) over a deny list. Add a widget test that pinches with a small rotation and expects heading up to stay wanted.

### [MEDIUM] MeshCore: a command or write timeout is recorded as a trace timeout
**Where:** `lib/data/radio/meshcore/meshcore_radio.dart:849, 868-878`; `lib/data/radio/meshcore/meshcore_commander.dart:95-108`.
**What:** `ping()` wraps both `await _cmd.send(frame)` (the SEND_TRACE_PATH command, 5 s idle timeout, 15 s write timeout) and the wait for the trace reply in one `try`, and the single `on TimeoutException` returns `PingStatus.timeout`. The commander throws `TimeoutException` when the radio never confirms the command, and a Bluetooth write timeout surfaces the same way. Neither means the trace went on air.
**Why it matters:** A radio that is busy, mid-reboot or briefly unreachable over Bluetooth produces `timeout` rows. On MeshCore those rows are counted as beacon misses (`SessionManager._followTraces`, 3 in a row marks the beacon absent), feed the out-of-range window, and with the uncommitted change become "no margin" silence samples on the estimate layer. Link problems on the phone side are reported as range problems.
**Fix:** Catch the command phase separately and return `PingStatus.error` with a reason such as `error:NO_COMMAND_REPLY` (nothing confirmed sent); keep `timeout` only for the wait after `MeshCoreSent`. Add a fake-transport test where the radio never answers SEND_TRACE_PATH.

### [MEDIUM] Per-packet database fan-out grew: every packet re-queries the node list and rebuilds open maps
**Where:** `lib/services/packet_processor.dart:296` (`updateNodeLastHeard` per packet); `lib/providers.dart:395-397` (`nodesProvider` = `watchAllNodes`); `lib/ui/screens/coverage_map_detail_screen.dart:43-54, 518`; non-autoDispose families `lib/providers.dart:271, 381, 574, 578`, `lib/ui/widgets/comparison_actions.dart:141`, `lib/ui/screens/guided/run_screen.dart:29`.
**What:** Every received packet updates `nodes.last_heard_at`, which re-runs `watchAllNodes` and notifies every widget watching `nodesProvider`. The coverage map detail screen watches it in `build`, so while a session records, an open detail screen rebuilds per packet, re-filters all events and pings and rebuilds `EstimateSamples` (a full pass plus `Object.hashAll` over every id). Separately, the prior finding still stands (map watchers are never disposed) and four more `StreamProvider.family` instances were added without `autoDispose`, so every session or plan looked at keeps a live drift query for the app's lifetime. There are only 2 `autoDispose` uses in `lib/`.
**Why it matters:** CPU and battery on long recordings with the Coverage tab open, and a slow growth of live queries over a long app run. Not a crash.
**Fix:** Make the families `autoDispose`; in the detail screen `ref.watch(nodesProvider.select(...))` only the base node, or read the base once; throttle `updateNodeLastHeard` (once per node per 30 s is plenty).

### [LOW] Meshtastic reconnect guard can leave a newer link without a reconnect loop
**Where:** `lib/data/radio/meshtastic/meshtastic_radio.dart:767-790`.
**What:** `_onLinkLost(gen)` returns early while `_reconnecting` is true. If a reconnect loop for an older generation is still inside `_open` (up to the 90 s pairing timeout) when the user's newer `connect()` succeeds and that link drops, no loop is started for the new generation; the old loop then exits on `gen != _linkGen`.
**Why it matters:** Auto-reconnect silently does not happen after a manual connect that raced a reconnect.
**Fix:** Track the generation of the running loop and start a new loop when the dropped link's generation is newer, or let the running loop adopt the newest generation.

### [LOW] Retuning a MeshCore trace can resurrect an ended session in memory
**Where:** `lib/services/session_manager.dart:507-549`.
**What:** `_retuneTrace` checks `_activeSession` at the start, awaits a DB update, and at the end assigns `_activeSession = await _db.getSessionById(sessionId)` and emits it. If `endSession()` runs during those awaits (Radio Setup beacon change while the user taps End), the ended row is put back as the active session and pushed to `sessionStream` (Live Activity and the session panel follow it).
**Fix:** Re-check `_activeSession?.id == sessionId` after each await and before the final assignment.

### [LOW] MeshCore commander takes a late reply as the next command's answer
**Where:** `lib/data/radio/meshcore/meshcore_commander.dart:62-75, 98-108`.
**What:** Responses carry no request id, so after a command times out its late reply is delivered to whatever command is active next. Callers check the frame type (`expect<...>`, `resp is! MeshCoreSent`), so the effect is one spurious error per late reply, and the queue usually heals when idle; under a busy queue (handshake retries, stats plus traces) the offset can persist for several commands.
**Fix:** After a timeout, drop the next non-push frame whose code does not fit the active command (each command knows its expected reply codes), or insert a short quiet period before the next command.

### [LOW] Guided change rollback can report "done" without changing anything
**Where:** `lib/services/guided/plan_runner.dart:1247-1253, 1474-1486`.
**What:** In the silent-base branch `back = oldPreset ?? preset`. For a TX power change (`preset == null`) on a radio whose preset was unknown when the step started (`fromPreset` not stored), `back` is null, `changeMobile` is skipped, and the row "Your radio: back to N dBm" is still marked `done`.
**Fix:** When `back` is null use `_env.currentPreset`, and if that is null too mark the row failed ("could not restore, set N dBm in Radio Setup").

### [LOW] Remote commit lost over the mesh is treated as applied, without a retry
**Where:** `lib/data/radio/meshtastic/meshtastic_radio.dart:1888-1900`.
**What:** "Lost commit ACK = success" came from Bluetooth, where the reboot eats the ACK. Over the mesh at range, the commit packet itself is often what gets lost; the base then keeps an open edit transaction on the old setting. The plan's listen and rollback catch it, but only after a full settle, mobile change, 120 s listen, rollback and 60 s check.
**Fix:** Re-send `commitEditSettings` once on timeout before treating it as sent (a second commit after a reboot is harmless), and say "may not have saved" in the step text.

### [LOW] New guided screens show raw exception text
**Where:** `lib/ui/screens/guided/ask_screen.dart:229`, `run_screen.dart:90`, `plan_screen.dart:48, 133`, `result_screen.dart:53`; also older `coverage_map_list_screen.dart:79`, `settings_screen.dart:516`, `radio_backups_section.dart:119, 334, 349, 407`, `region_dialog.dart:64`, `export_dialog.dart:31`, `terrain_profile_sheet.dart:139`, `connection_banner.dart:498`, `about_screen.dart:144`.
**What:** `userMessage()` (`lib/utils/user_errors.dart:28`) now exists and is used in 10 files, but these sites still interpolate `$e`, which shows `Bad state: ...` or `PlanError(...)` text.
**Fix:** Route them through `userMessage(e)`; let `PlanError` and `SessionStartError` pass their message through as is.

### [LOW] Routing reply dispatch swallows every error
**Where:** `lib/data/radio/meshtastic/meshtastic_radio.dart:946-963`.
**What:** The `try { ... _routingController.add(reply); _onPingReply(reply); } catch (_) {}` wraps the dispatch as well as the protobuf parse, so a bug in `_onPingReply` or a synchronous listener throwing loses a ping reply with no log line.
**Fix:** Limit the `try` to `Routing.fromBuffer` and log parse failures to DiagLog.

### [LOW] Pings in flight when the link drops become `timeout`; Meshtastic dispose never completes them
**Where:** `lib/data/radio/meshtastic/meshtastic_radio.dart:1171-1181, 2043-2048`; compare `lib/data/radio/meshcore/meshcore_radio.dart:1100-1108`.
**What:** Meshtastic `disconnect()`/`_teardown` leave pending pings to their 30 s timer, so a ping in flight at a Bluetooth drop is recorded as `timeout` (and now as silence on the estimate layer). `dispose()` cancels the timers but never completes the completers, so a caller awaiting `ping()` (a SwitchableRadio switch disposes the old inner radio) waits forever. MeshCore completes them with an error.
**Fix:** On teardown complete pending pings with `PingStatus.error` and reason `LINK_LOST`; in `dispose()` complete them as MeshCore does.

### [LOW] make_icon.py: silent fallback and fragile cropping (uncommitted)
**Where:** `tool/make_icon.py` `from_art()` and `main()`.
**What:** `tool/icon_art.png` is untracked; if it is not committed the script silently falls back to the old drawn icon and overwrites the iconset with it. `side = min(w, h)` crops from the top-left, so non-square art is cut off-centre. `floodfill(..., thresh=60)` from a white corner can spread into pale artwork that touches the corner. `bg` is sampled at y = 2 inside the trimmed square, i.e. artwork, not the outline the comment describes. An all-white image raises `IndexError` on `xs[0]`. LANCZOS softens pixel art at the 1024 size (fine for the small sizes).
**Fix:** Commit the PNG with the script; print a warning (or exit non-zero) when the art is missing; centre the square crop; lower `thresh` or only fill pixels that are near-white; fix the comment. The output PNGs are RGB with no alpha, which is what App Store Connect needs.

### [LOW] Fire-and-forget futures with no error handling, and no lint for them
**Where:** `analysis_options.yaml` (no `unawaited_futures` / `discarded_futures`); examples `lib/services/active_probe_service.dart:216-218, 302`, `lib/services/session_manager.dart:363-364`, `lib/ui/screens/map_screen.dart:141-143`.
**What:** DB writes such as `timeoutPendingPing` and `updateSessionRadioStats` are not awaited and have no `catchError`, so a failure becomes an unhandled async error instead of a log line; intentional ones are not marked `unawaited`.
**Fix:** Enable `unawaited_futures`, wrap intentional ones in `unawaited(...)`, and add `.catchError` logging to background DB writes.

### [LOW] Migration chain has no fresh-versus-upgraded schema check
**Where:** `lib/data/database/app_database.dart:40-143`; tests `test/rig_test.dart:183` (v3), `test/beacon_kinds_test.dart:800-886` (v6), `test/session_base_test.dart:32-124` (v7), `test/radio_settings_test.dart:187-259` (v8), `test/meshcore_services_test.dart:656-696` (v9).
**What:** Every step v2 to v11 has a matching `addColumn`/`createTable`, and per-step tests start from v3, v6, v7, v8 and v9 (so v10 and v11 run indirectly). None compares the migrated `sqlite_master` with a fresh install, there are no drift schema snapshots (`drift_dev schema dump`), and there is no v10-only start. The v8 step uses `alterTable(TableMigration(coverageMaps))`, which rebuilds the table from the current definition: a future column added to `coverage_maps` would break every pre-v8 upgrade unless the step is revisited.
**Fix:** Add drift schema snapshots and a `SchemaVerifier` test per version, or one test that upgrades from the oldest DDL and compares table and index SQL with a fresh database.

### [LOW] moveSessions ignores guided plans; doc comments are swapped
**Where:** `lib/data/database/app_database.dart:341-364`; `lib/ui/screens/coverage_map_detail_screen.dart:364-410`.
**What:** A session that belongs to a guided test step can be moved to another map while its plan stays on the old map; deleting the new map later deletes the session without unlinking the step (`deleteCoverageMap` only cleans plans of the map being deleted), leaving `test_steps.session_id` dangling. The "Delete sessions..." doc comment sits above `moveSessions`, and `deleteSessions` has none.
**Fix:** Refuse (or warn) when a picked session has `testStepId`, or null the step's `session_id` in `deleteCoverageMap` for sessions referenced by other maps' plans; move the comment.

### [LOW] Stale TODOs in exports
**Where:** `lib/services/export/csv_v2.dart:58`, `lib/services/export/meshtastic_csv.dart:21, 41-48`.
**What:** They wait for a "schema PR" with the base position; schema v8 added `coverage_maps.base_lat/base_lon`, so base distance and bearing could be filled now.
**Fix:** Fill the columns from the map's base location, or drop the TODOs.

### [LOW] Ride-along "Stop & trim" is irreversible with untuned thresholds
**Where:** `lib/services/base_ride_along_detector.dart:25-65, 144-228`; `lib/ui/widgets/ride_along_banner.dart:31-46`.
**What:** The rule is conservative (60 s grace, 20 s of driving, every base sample strong, distance growing from the map's base location), but the thresholds are untuned and the distance uses the map's location, which can be stale now that a map is a place and the base moves with the session. "Stop & trim" deletes rows at once with no undo.
**Fix:** Keep trimmed rows recoverable (mark them, or keep a short undo snackbar), and log the rule inputs to DiagLog when it fires so the thresholds can be tuned from field logs.

### [LOW] Tests rely on short real-time sleeps
**Where:** for example `test/meshcore_services_test.dart:48, 566`, `test/coverage_map_detail_fit_test.dart:77`, `test/session_panel_test.dart:46`, `test/rig_comparison_ui_test.dart:129`, `test/range_comparison_ui_test.dart:137` (about 34 real `Future.delayed` calls, 65 `runAsync` uses).
**What:** 30 to 100 ms waits inside `runAsync` let drift streams settle. They passed here, but are the usual source of flakes on a loaded CI machine.
**Fix:** Await the stream's next value (`stream.firstWhere(...)`) or pump until a condition holds, instead of fixed sleeps.

## Prior findings

Quality (2026-10-16/quality.md):

| Finding | Status | Evidence |
|---|---|---|
| [HIGH] GPS never starts if permission not granted at launch | Fixed | `GpsService.ensureStarted` at launch and on resume (`lib/app.dart:114, 143`); `startSession` retries and refuses on denied/off (`lib/services/session_manager.dart:224-238`); GPS status shown via `gpsStatusProvider` (`lib/providers.dart:430`). |
| [HIGH] Deleting a map while its session records orphans data | Fixed | `isRecordingInto` guard on both delete paths (`lib/ui/screens/coverage_map_list_screen.dart:96, 130`); `deleteCoverageMap` is one transaction and deletes plans, steps and ping correlations (`lib/data/database/app_database.dart:309-339`). |
| [MEDIUM] Superseded `connect()` tears down the newer connection | Still open (Meshtastic); fixed in MeshCore | Meshtastic `connect` catch has no gen check (`meshtastic_radio.dart:659-664`), `_open` returns silently on a stale gen (`:696, :719`), reconnect catch tears down unconditionally (`:806`); see also the new reconnect-guard LOW. MeshCore checks gen in its catch and `_checkGen` (`meshcore_radio.dart:186-193, 236-238`). |
| [MEDIUM] "Signal Direction" setting does nothing | Still open | Only `settings_screen.dart:58-59, 189-201` read or write `prefSignalDirection`. |
| [MEDIUM] Range Test prompt while idle; dismiss disables logging | Fixed | Detector only consulted with a session (`packet_processor.dart:300-304`); pending packets are recorded (`range_test_detector.dart:52`); dialog `barrierDismissible: false` (`range_test_dialog.dart:35`). |
| [MEDIUM] Radio Setup/restore leaves an open edit transaction on failure | Partly fixed | UI now says the radio may be half-configured and points to Backups (`radio_setup_screen.dart:1282-1284`); still no try/commit around begin..commit (`meshtastic_radio.dart:1511-1563, 1587-1589, 1677-1680, 2004-2016`). |
| [MEDIUM] `watchEventsForMap` providers never disposed, re-query per packet | Still open | `coverage_map_detail_screen.dart:43-54` are plain `StreamProvider.family`; more families added (see new MEDIUM). |
| [MEDIUM] Live map keeps old sessions' dots, draws unrecorded packets | Partly fixed | A new session clears the dots (`map_screen.dart:297-306`); `_addDot`/`_addPingDot` still add dots with no session (`:274-292`) and the session load inserts without the 5000 cap (`:321`). |
| [MEDIUM] No auto-connect after restart; key exchange not redone | Partly fixed | Key exchange redone on every transition to ready (`active_probe_service.dart:138-145`); auto-connect to `LastRadio` on resume (`app.dart:178-226`) but a single attempt (a failed first `connect` sets `_wantConnected = false`) and no CoreBluetooth state restoration. |
| [LOW] `upsertNode` overwrites names and `firstSeenAt`; creation race | Partly fixed | Packet path serialised with `_nodeLookups` (`packet_processor.dart:423-432`); `upsertNode` still `insertOnConflictUpdate` with empty names (`app_database.dart:150-165`), and `ActiveProbeService._localNodeId` / `SessionManager._baseNodeRow` bypass the lock. |
| [LOW] `endSession`/`startSession` not re-entrancy safe | Still open | `endSession` reads `_activeSession!.id` after several awaits (`session_manager.dart:327-349`); no lifecycle lock. |
| [LOW] `ActiveProbeService.stop()` doesn't stop an in-flight ping | Partly fixed | Re-checks `isActive` after the key exchange (`active_probe_service.dart:245`); `_activeSessionId` is still not cleared in `stop()` (`:207-217`), so a ping already inside `ping()` records into the ended session. |
| [LOW] `sendAdmin` leaves an unhandled `TimeoutException` when the write fails | Still open | `sendAdminAttempt` creates `reply` before `_write` with no `ignore()` (`meshtastic_radio.dart:1322-1335`); the newer `_remoteAdmin` does it right (`:1922-1926`). |
| [LOW] 1 s timestamps; CSV without timezone; formula injection | Partly fixed | CSV v2 has `timestamp_utc` (`export/csv_v2.dart:71`) and neutralises formulas (`:144-149`); drift still stores seconds and map queries order by `timestamp` only (`app_database.dart:614`). |
| [LOW] Missing `mounted` checks, unguarded dialog failures, undisposed controller | Still open | `session_panel.dart:809-814` (`setState` after a second await), `create_map_dialog.dart:180-199` (no try/finally around `_saving`), `node_list_screen.dart:106` (controller not disposed). |
| [LOW] Raw exceptions shown to users | Partly fixed | `userMessage` added (`utils/user_errors.dart:28`) and used in Radio Setup, session panel, connection banner; about 17 sites still show `$e` (see new LOW). |
| [LOW] `ProEntitlement.refresh()` not re-entrant | Still open | Shared `_collecting` set and nulled per call (`pro_entitlement.dart:296-312`). |
| [LOW] Disconnect during a session has no confirmation | Still open | `connection_banner.dart:313-316` disconnects at once (switching radios does confirm, `:540-589`). |
| Housekeeping: dead code | Still open | Still single-reference: `getActiveSession`, `watchActiveSession`, `insertPacketEventsBatch`, `getEventsInBounds`, `defaultGpsBackfillWindowSec`, `CollectionTier`, `SignalDirection`, `sendText`, `OutOfRangeMonitor.isMonitoring`, `requestsToday`. |
| Housekeeping: `MeshtasticRegions.pbCode` `firstWhere` without `orElse` | Still open | `meshtastic_regions.dart:17`. |
| Housekeeping: SPDX headers, unused `uuid`, EOL `sqlite3_flutter_libs`, unused `riverpod_annotation` | Partly fixed | SPDX headers present (`SceneDelegate.swift`, `gen_protos.sh`); `uuid` now used; `sqlite3_flutter_libs` 0.5.42 still EOL; `riverpod_annotation`/`riverpod_generator` still unused. |

Reliability (2026-10-16/reliability.md):

| Finding | Status | Evidence |
|---|---|---|
| [HIGH] F1 Range Test packets dropped until a dismissible dialog is answered | Fixed | See the Range Test row above; base packets reach the monitor before any gate (`packet_processor.dart:272-274`); session base trusted (`session_manager.dart:383-386`). |
| [HIGH] F2 No reconnect after relaunch | Partly fixed | Auto-connect on resume with adapter wait and a notice on failure (`app.dart:178-226`), base excluded when the mobile is known (`last_radio.dart:39-48`); one attempt only, no state restoration (no `restoreState` anywhere). |
| [HIGH] F3 GPS failure invisible and never retried | Fixed | See the GPS row above. |
| [MEDIUM] F4 Base-first Radio Setup can give the mobile a different region | Still open | `switchToAndApplyMobile` applies `regionName` read from the newly connected mobile, US when UNSET (`radio_profile_service.dart:153-156, 584-603`); `_ensureRegion` is not called in `_switchToMobile` (`radio_setup_screen.dart:579-600`). |
| [MEDIUM] F5 No fix age or accuracy gate | Still open | `lastPosition` used regardless of age (`gps_service.dart:123, 240-245`; `packet_processor.dart:398`; `active_probe_service.dart:255`). |
| [MEDIUM] F6 Out-of-range timeout ignores the beacon interval | Fixed | `2 * beaconSec + 30` with pings off and `3 * interval + reply` with pings (`session_manager.dart:465-473`); flap quieting (`out_of_range_monitor.dart`). |
| [MEDIUM] F7 Mid-transaction failure gives raw error and no recovery hint | Partly fixed | Hint text added (`radio_setup_screen.dart:1282-1284`), `userMessage` used; no commit or verification attempt. |
| [MEDIUM] F8 Wrong-role selection lightly guarded | Partly fixed | Roles are chosen explicitly; start refuses when the base is the connected radio (`session_manager.dart:200-207`); no warning when a radio with the other role is picked in Radio Setup. |
| [MEDIUM] F9 Base missing from the New-map picker | Fixed (superseded) | Since schema v8 a map is a place and the session takes its base from Radio Setup (`session_manager.dart:194-198`). |
| [MEDIUM] F10 Live Activity failure silent; start race | Fixed | `problem` shown in the session panel (`session_panel.dart:189`); generation guard ends an overtaken activity (`live_activity_service.dart:99, 126-136`); retry on resume. |
| [MEDIUM] F11 Notification permission asked cold; denial never reported | Fixed | Asked at session start (`session_manager.dart:288-290`), checked on resume (`app.dart:115-117`), banner when denied (`session_panel.dart:297, 717`). |
| [LOW] F12 Forgotten session keeps GPS running | Still open | No auto-end or reminder in `session_manager.dart`. |
| [LOW] F13 Live Activity staleness, no heartbeat | Still open | Initial `staleDate: nil`, updates only when state changes (`LiveActivityBridge.swift:78, 98`; `live_activity_service.dart:185-195`). |
| [LOW] F14 Smaller items (pending prompt, foreground GPS, `getSingleOrNull`, resume gap, `ActivityType.fitness`) | Partly fixed | Pending prompt no longer drops data; the rest unchanged (`gps_service.dart:233-236`, `app_database.dart:585-587`). |

## Checked, OK

- Uncommitted map changes: `_syncHeading` subscribes and cancels the compass correctly, `dispose` cancels every subscription and timer, programmatic rotations use `MapEventSource.mapController` so the compass never cancels itself, the resume-follow timer restores heading up, and the compass tap cycle matches the CLAUDE.md description. The only defect found is the pinch zoom one above.
- Uncommitted estimate change: ids, values and positions stay aligned; the cache key includes the silence ids so a new timeout invalidates it; the cache is bounded (6 estimates, 4 terrain); silence values are preset-neutral (0 dB margin, -130 dBm); session and preset filters apply to pings the same way as to events.
- Session lifecycle: resume restarts monitoring, background GPS, the probe and beacon tracking with the session's own protocol (`session_manager.dart:375-445`); MeshCore resume works because the Switchable radio may switch to the session's protocol and refuses any other (`providers.dart:82-88`, `switchable_radio.dart:109-121`).
- OutOfRangeMonitor: radioLost pauses the clock, a 30 s grace before "Radio disconnected", re-entry needs 2 answers, flaps within 5 min are quiet, repeats within 2 min are quiet, the clock starts at configure (also when resumed before the radio is back).
- BeaconTracker: no synthesised misses while the phone-radio link is down (`packet_processor.dart:143-151` skips slots), absent requires the base heard recently, trace kind counts consecutive timeouts only.
- Live Activity: start/end race handled by generation, overtaken activities are ended, `problem` surfaced, retry on resume.
- PacketProcessor: stale/replayed packets dropped before they become samples, relayed packets kept out by default, `log_only` and `telemetry_miss` excluded from map queries and counts (`SourceKind.notSamples`).
- Database: every step v2 to v11 has a matching schema change; destructive operations (`deleteCoverageMap`, `deleteSessions`, `trimSessionAfter`) are single transactions and clean up ping correlations and guided steps; `moveSessions` refuses the recording session; "Stop & trim" ends the session before trimming and moves `endedAt` back.
- MeshCore: connect and reconnect check generations; `failAll` on teardown fails queued commands; each command has an idle timeout that restarts per frame; the codec returns `MeshCoreMalformedFrame` instead of throwing and decodes names with `allowMalformed`; trace answers are matched by tag and use 4-byte hashes so a relay cannot answer for the base; the ladder maps pre-ladder community ids (`MeshCoreModulations.ladderId`).
- Guided tests: one plan at a time, `_serial` chain for every mutation, stale-generation checks after each await in the change sequence, `fromPreset`/`fromTxPower` persisted before any change so a kill mid-change keeps the original, a crash-left "running" plan is paused, a walk recording at kill time is ended and walked again, the result is never null (`plan_analysis.dart:165-185` covers no base location, `decodePlanResult` failures fall back to the screen's error text). `DemoPlanRunner` no-ops are fine for its screenshot-only role.
- Logging: no keys, PSKs, passkeys or positions in `print`/DiagLog lines; DiagLog is capped at 256 KB.
- CSV/KML/GeoJSON timestamps are UTC; CSV cells are formula-neutralised.
- App icon PNGs are RGB without alpha.
- CLAUDE.md descriptions checked against code for the radio setup admin order, out-of-range window, beacon kinds, MeshCore trace ping, heading up and estimated layer: they match (except for the estimate silence rule, see the first finding).

## Test gaps

1. `SessionManager.initialize` (resume after a kill) and `_autoReconnect` in `app.dart`: no test starts the app with `prefActiveSessionId` set.
2. `LiveActivityService`: no test at all (start race, overtaken start, retry on resume, update dedup).
3. `MeshCoreCommander`: no direct test of a late reply after a timeout, a write failure, or `failAll` with queued jobs; and no `MeshCoreRadio.ping` test where SEND_TRACE_PATH gets no reply.
4. Heading up with a pinch zoom (the twist test bypasses the gesture code).
5. `EstimateSamples` with ack rows of throttled and locally NAKed pings, and with pings timed out during a radio-lost period.
6. Migrations: no fresh-versus-upgraded schema comparison and no v10 start (see LOW above).
7. `AppPlanEnvironment` (the real `PlanEnvironment`), `BleTransport`, `SignalHistory`: no tests.
8. Meshtastic superseded connect and the reconnect guard race.
9. OutOfRangeMonitor going radioLost while outOfRange and back (state returns to unknown, skipping re-entry rules).
10. `moveSessions` with sessions that belong to a guided step; `_retuneTrace` racing `endSession`.
