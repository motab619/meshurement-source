# Session recording pipeline review (Opus, 2026-10-26)

Reviewed: branch `field-build-oct23` @ 7e0e7fc. No repository files changed. Listed tests plus active_probe_service_test pass (148). F1 and F4 reproduced with a scratch test.

## 1. Ranked findings
| # | Sev | Conf | Where | Symptom |
|---|---|---|---|---|
| F1 | High | High (reproduced) | packet_processor.dart:125-130; beacon_tracker.dart:194-204 | After a BLE outage or radio reboot, every telemetry slot that passed while the link was down becomes a `telemetry_miss` row at an interpolated position. A 30-min outage at 60 s gave 29 made-up misses. |
| F2 | High (field risk) | Medium | app.dart:137-142; session_manager.dart:79-96 | If iOS kills the app (memory pressure, crash, force-quit, OS update), recording stops with no alert at all. Nothing relaunches it, and opening the app later quietly resumes the same session with a hole in it. |
| F3 | Medium | High | session_manager.dart:294-298; out_of_range_monitor.dart:124-196 | Out-of-range alerts flap: no hysteresis or rate limit, so every in/out change buzzes the phone. With pings off, the timeout is max(90 s, 0) and ignores the beacon interval, so telemetry at 120/300 s (or one missed 60 s beacon) sets off "Out of range" every cycle. |
| F4 | Medium | High (reproduced) | beacon_tracker.dart:185-191 | Coming back from a dead zone longer than 3 intervals, the first ping ACK flips "beacon off" to true. That shows the false "Base is reachable but its beacon is off" banner, and in Range Test sessions a "Switch base to telemetry" button, until the next beacon. |
| F5 | Medium | High | beacon_status.dart:55-69; radio_profile_service.dart:271; session_manager.dart:288 | "Switch base to telemetry beacon" mid-session never updates the BeaconTracker. For the rest of the session, telemetry beacons are logged as `passive`, no misses are counted, and the "beacon off" banner stays up. |
| F6 | Medium | Medium-low (depends on firmware) | meshtastic_radio.dart:614-616, 826-830; radio_types.dart:205-209 | Packets the radio buffered while the phone was away arrive after `config_complete`, when `isReady` is already true, so they aren't marked `queued`. The app never sets the radio's clock (no `set_time_only`), so `rx_time` is 0 and the stale check can't catch them. They get recorded with the current GPS position and count as "base in range". |
| F7 | Medium | High (code) | gps_service.dart:230-246; packet_processor.dart:255; active_probe_service.dart:217,300 | Packets get `lastPosition` whatever its age or accuracy. Nothing ever reads `gpsAccuracy`, and the fix age isn't stored. With `distanceFilter: 5` you can't tell "standing still" from "GPS lost", so stale or coarse fixes go into maps and distance stats. |
| F8 | Medium | Medium-low (check on device) | AppDelegate.swift; out_of_range_monitor.dart:220-227 | No `UNUserNotificationCenter.current().delegate = self` in AppDelegate, which flutter_local_notifications 18 requires before it can present while the app is open. So the promised foreground banner+sound likely never appears; lock-screen alerts are fine. Alerts aren't Time Sensitive either, so Driving Focus or other Focus modes hide them, and the silent switch mutes them. |
| F9 | Low-Med | High | range_stats.dart:339-358, 155 | `error:*` ping outcomes count as sent and missed in range stats, including local NAKs that never went on air (PKI_UNKNOWN_PUBKEY, SEND_FAILED, NO_CHANNEL). Result: a "first miss" near 0 m and lower band success rates. A local NAK (responder = our own node) also gets an `ack` row with a position. |
| F10 | Low | High | session_manager.dart:170-205; coverage_map_detail_screen.dart:1134,1149 | A crash between `createSession` and saving `active_session_id` leaves an `isActive` row that is never resumed or ended. It shows "(recording)" forever and can't be deleted. A session resumed after a long kill also never asks whether to continue. |
| F11 | Low | High | session_manager.dart:225-233 | `endSession` awaits the DB before clearing `activeSessionId`. Packets in flight land after `endedAt`, and `packetCount` was already counted without them. |
| F12 | Low | Medium | LiveActivityBridge.swift; live_activity_service.dart | iOS ends a Live Activity after about 8 h, but Dart still thinks it's running and its updates silently do nothing. |
| F13 | Low | High | app_database.dart:457-475 | `watchBeaconStats` counts Range Test rows from any node and, with "count relayed" on, relayed copies. Interleaved sequence numbers then produce fake "missed" counts. Unlikely on the private channel. |
| F14 | Low | High | coverage_map_detail_screen.dart:394-401 | Coverage dots include rx/ack rows from every node, not just the base, including our own node's local-NAK ack rows. |
| F15 | Low | Low (speculative) | active_probe_service.dart:212 | The 30 s ACK timeout may be shorter than the firmware's retransmit cycle on the slowest presets, so a late ACK would be recorded as `timeout`. |

## 2. Details and fixes

**F1.** `tickBeacons` returns early when `!_radio.isReady`, before `dueMisses()` moves `_nextSlot` forward. When the link returns, the next tick emits every slot since the last beacon. The existing test "no misses while the phone is not linked" only checks during the outage. Scratch test: 60 s telemetry, 30 min `reconnecting`, then `ready` gives 29 misses.

Fix:
```dart
if (!_radio.isReady) { beacons.dueMisses(now); return; } // consume the slots: we could not have heard them
```
Better: add tracker `linkDown`/`linkUp` that sets `_nextSlot` to the first slot after the reconnect, plus a test that ticks after `setState(ready)`.

**F2.** Nothing is scheduled ahead of time and CoreBluetooth state restoration isn't set up, so a killed process sends no alert. The Live Activity only goes grey after its 10-min `staleDate`.

Fix: a dead-man's switch. While a session records, schedule one local notification about 4 min ahead ("Mesh Analyzer is not running – open it to keep recording") and reschedule it every tick; cancel it in `endSession`. Use `zonedSchedule`, or a native `UNTimeIntervalNotificationTrigger` through the app channel. On resume, if the newest event is more than about 15 min old, ask "Continue session or end it at hh:mm?". On the day: never swipe the app away, and keep the phone charged.

**F3.** Fix the timeout:
```dart
timeoutSec: [pref, 3 * pingSec, if (pingSec == 0 && beaconSec > 0) 2 * beaconSec + 30].reduce(max)
```
Also send "Back in range" only after the base was out for at least about 2 min (or make it silent), and send at most one sounding alert every 5 min.

**F4.** The absent rule is: silent for more than 3 intervals AND the base heard within 3 intervals. One fresh ACK satisfies it. Scratch test: interval 300, beacon at 0, silence to 1800 s, `onBaseHeard(1810)` gives absent = true.

Fix: track `_reachableSince` (reset when the gap between base-heard packets is longer than 1.5 intervals) and measure the silence from `max(lastBeacon, reachableSince)`.

**F5.** The only `startBeaconTracking` caller is `_startMonitoring`, and `accepts()` rejects the new kind. Fix: after a successful switch, call something like `SessionManager.retargetBeacon(kind, interval)`, which runs `startBeaconTracking` and `db.updateSessionBeacon`. Or let `accepts()` take a new kind while the tracker is absent.

**F6.** `_open` sets `ready` as a microtask right after `configCompleteId`, before the next BLE read comes back. The firmware's PhoneAPI sends its to-phone queue after the complete id. Not checked against firmware source, hence medium-low confidence.

Fixes (either one):
1. Mark everything read in the drain loop after `configCompleteId`, up to the first empty read, as `queued` (a `_replaying` flag).
2. Send `AdminMessage(setTimeOnly: now)` to our own radio after each handshake, so `rx_time` is valid and the 2-min stale rule works.

Bench check: turn the phone's BLE off for 3 min while the base beacons, reconnect, and watch the DiagLog "dropped N stale" line.

**F7.** Fix: use `distanceFilter: 0` while recording (GPS is on anyway). Store `gps_age_s`, or null out lat/lon when the age is over 15 s or accuracy over 50 m. Skip rows with `gpsAccuracy > 50` in maps and range stats.

**F8.** Add the delegate line in `didFinishLaunching`. Consider the Time Sensitive capability plus `interruptionLevel: timeSensitive`.

**F9.** Leave out errors that never transmitted (SEND_FAILED, PKI_UNKNOWN_PUBKEY, NO_CHANNEL, NO_INTERFACE, PUBLIC_CHANNEL, TOO_LARGE). Keep MAX_RETRANSMIT and NO_RESPONSE as real misses.

**F10.** In `initialize`, end every `isActive` row except the one in the pref (`endedAt` = its last event time). Save the pref right after `createSession`.

**F11.** Clear `activeSessionId` and stop beacon tracking before writing `endedAt`.

**F12.** Watch `activityStateUpdates` and restart the activity while the session is still active.

**F13 / F14.** Filter by the base node (and hops == 0 for beacon stats).

**F15.** Derive the timeout from the preset's airtime (about 3 retransmits plus margin).

## 3. Edge cases checked and found correct
- **Starting a session** is refused when the radio isn't ready, it's on the public channel, location is denied or off. Pings and the key exchange also re-check the public channel, including after reconnects and on resume.
- **Double start** ends the previous session first, and the UI's busy flag stops double taps.
- **Ping bookkeeping:** each ping is recorded before it is sent; outcomes after `stop()` are ignored and pending pings are marked timeout. `throttled` is left out of the stats, `implicit` is kept separate, and relayed ACKs keep their row but drop their signal values.
- **Packet filtering:** our own radio's packets and node 0 are dropped. Relayed (hops > 0) packets are excluded from recording, from out-of-range "heard", and always from beacon samples; base telemetry with hops > 0 is never a beacon (tested). Concurrent packets from a new node don't create duplicate node rows.
- **Range Test sequence numbers:** a counter reset on base reboot isn't counted as a gap (tracker and `BeaconStats`).
- **Telemetry misses:** intervals are rounded up to whole minutes, and learning only ever shortens the interval. No misses before the first beacon, while the base is unreachable, or while "beacon off" applies. Each slot is emitted once; misses stop at session end.
- **Miss rows stay out of real data:** excluded from map dots, packet counts, GeoJSON, KML and the Meshtastic CSV; included only in the full CSV.
- **Out-of-range monitor:** its clock starts at configure, so a base that's never heard still goes out of range. A BLE drop pauses the clock as `radioLost` with a 30 s grace before notifying. A session resumed before the radio connects starts in `radioLost`.
- **Resume after relaunch:** the session resumes, the radio auto-reconnects (never to the base), and the key exchange runs again once ready.
- **Background:** background location is applied by restarting the stream; `pauseLocationUpdatesAutomatically` is false; Info.plist has the `location` and `bluetooth-central` background modes.
- **DB durability:** each insert autocommits, so a crash loses at most the write in flight.
- **Migrations:** v1→v7 only add nullable or defaulted columns, with a v6→v7 test. v5 devices run the `<6` and `<7` steps.
- **Session fields:** radio stats keep the max seen; preset, protocol, beacon kind and interval are snapshotted at start, and a learned kind is written back.
- **CSV:** UTC, local time with offset, and `unix_ms`, with formula-injection guarding. Timestamps are whole seconds (drift default).
- **Live Activity:** no orphan if the session ends while it's starting (tested).

## 4. Pre-flight checklist
**Phone**
- Location set to **While Using** (not "Allow Once") with **Precise Location on**.
- Notifications allowed with sounds.
- Driving Focus auto-activation off, or Mesh Analyzer allowed in Focus.
- Ring switch on ring (or rely on vibration). Live Activities allowed.
- Battery above 80% or a power bank. Never swipe the app away.

**Radios**
- Run Radio Setup on both today. If the base runs Range Test, restart it right before leaving: Range Test switches itself off 8 h after boot.
- If telemetry is 120 s or more, keep Pings on, or the alerts will flap (F3).
- Don't use "Switch base to telemetry" mid-session; if you must, end and restart the session (F5).

**First 5 minutes, next to the base**
- GPS shows "fix ±≤10 m" with no "(approximate)".
- The pill goes to in range; pings show `received`, not `error:PKI_UNKNOWN_PUBKEY` (if they do, run Radio Setup again).
- "Beacons N heard" goes up at the expected interval, and "~missed" stays at 0.
- Lock the phone for 2 min: the counters keep going, and the blue location indicator and Live Activity are showing.
- Switch the base off briefly with the phone locked: "Out of range" arrives on the lock screen, then "Back in range". Repeat with the app open to check the banner (F8).
- Optionally switch the mobile radio off for 1 min: expect "Radio disconnected", then "Reconnected". Ignore the ~missed count for that window (F1).

**During the test**
- Check the session panel every time you take the phone out.
- Write down the times of BLE drops and radio reboots; misses there may be made up (F1) and replayed packets may appear (F6).
- At the end, stop the session explicitly and export the full CSV straight away.
