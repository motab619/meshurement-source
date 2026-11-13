# Radio layer pre-field-test review (Opus, 2026-10-26)

Read all files in scope plus the code they call: `radio_profile_service.dart`, `packet_processor.dart` (stale filter), `range_stats.dart`, `export/kml.dart`, and the flutter_blue_plus 1.36.8 and protobuf 4.2.0 sources in the pub cache. No repository file was changed.

The three test files pass (63 tests). The real `MeshtasticRadio` link code (connect, reconnect, reading FromRadio, handling ping replies) has **no tests**: `BleTransport` is built inside the class (`meshtastic_radio.dart:282`) and can't be replaced with a fake. So every link finding below comes from reading the code, not from a reproduction. Line numbers are for the `field-build-oct23` working tree.

## 1. Ranked findings

| # | Sev | Conf. | Where | Symptom |
|---|---|---|---|---|
| 1 | **High** | High on the mechanism, medium on how often | `meshtastic_radio.dart:594, 660-692` | If the link drops during a reconnect's handshake, a **second reconnect loop** starts. Both loops re-handshake a link that is already up, leak subscriptions and heartbeat timers, and multiply on later drops. |
| 2 | **High** | Medium | `meshtastic_radio.dart:826-830`; `radio_types.dart:205-209`; `packet_processor.dart:199` | Packets the radio buffered while the phone was disconnected are replayed after `config_complete_id` and treated as live. They are recorded at the phone's reconnect position and reset the out-of-range clock. A radio with no GPS reports `rx_time` 0, so the stale check can't catch them either. |
| 3 | Medium | Medium | `:1072-1083, 968-977, 620-630` | Key recovery after a NAK ignores `PKI_SEND_FAIL_PUBLIC_KEY` (39), the sender-side "no key" error. `ensureContact` trusts the phone's node cache, which is never cleared when the phone switches radios, so it can skip `add_contact`. |
| 4 | Medium | Medium | `active_probe_service.dart:212`; `constants.dart:64`; `:857-868`; `airtime_model.dart:86-121` | The ACK timeout is a fixed 30 s for every preset. Slow presets get late ACKs counted as timeouts. The airtime estimate ignores the firmware's up to 3 retransmits, so duty is under-counted up to 4x when out of range. |
| 5 | Medium | High | `range_stats.dart:339-343`; `kml.dart:48`; `active_probe_service.dart:251-262` | Pings that never left the radio (`error:SEND_FAILED`, local PKI or NO_CHANNEL refusals) count as sent-and-lost in delivery %. The KML export never draws `error:<REASON>` pings as failures. |
| 6 | Medium | High | `:687, 738, 1046, 1085`; `connect_progress_view.dart:101-105` | Why a reconnect, read or ping failed is only `print()`ed, so it's lost in TestFlight builds. A lost iOS bond ("Peer removed pairing information") retries every 60 s forever and only shows "Lost the radio. Retry N". |
| 7 | Medium | Medium | `:612-614` | No liveness check: failed heartbeats are ignored. If the radio hangs but iOS never reports a disconnect, the app shows "ready" forever. |
| 8 | Medium (procedure) | Medium | outside the code | The official Meshtastic app can reconnect in the background over the same iOS link. Both apps then read FromRadio, and each frame goes to only one of them, so ACKs and beacons go missing. |
| 9 | Low | High | `:310, 321-325, 837-840` | `lastChannelStats` is never reset when the phone switches radios: the base's airtime figures show and are recorded on a mobile session. |
| 10 | Low | High | `active_probe_service.dart:172-184, 216-239` | If the session stops while a ping is being recorded, that ping is still sent and recorded to the ended session (`_activeSessionId` is never cleared). |
| 11 | Low | Low to medium | `:1054, 1086-1090` | The first reply wins: the firmware's implicit ACK can beat the base's real ACK, which is then dropped along with its signal. Depends on firmware. |
| 12 | Low | Medium | `:268, 642` | The handshake has a fixed 60 s total, not "60 s without progress": a big node list on a slow link fails and restarts from scratch each time. |
| 13 | Low | High on the mechanism, low on how often | `:812-814, 1234-1240`; protobuf `coded_buffer.dart:26-28, 74-81` | Enum values newer than the vendored 2.7.26 protos: an unknown Routing error decodes as NONE, so a NAK counts as an ACK. Changing a config field whose current value is unknown doesn't stick, because the old raw value is written last and the firmware keeps it. |
| 14 | Low | High | `:1141-1153` | If the write in `sendAdminAttempt` throws, the reply future is never awaited and later raises an unhandled `TimeoutException` (log noise, no crash). |
| 15 | Low | Medium | `:556-569, 588, 610` | Connecting to radio B while reconnecting to A can leave A's Bluetooth link open with nothing owning it. A then stops advertising. |
| 16 | Low | Medium | `:667-692` | Bluetooth turned off and on: the loop doesn't watch the adapter, so it can take about 75 s to come back. |
| 17 | Low | High | `radio_profile_service.dart:243-266, 297-319`; FBP `bluetooth_characteristic.dart:117,189,255` | A second link to the base mid-session stalls the mobile's reads and writes for 15–90 s, because flutter_blue_plus runs every operation one at a time across all devices. |

## 2. Details and mitigations

**F1 — Two reconnect loops (High).**
- **Cause:**
  - `_open` attaches the link-lost listener before the handshake (`:594`).
  - `_onLinkLost` (`:660-665`) checks only `gen == _linkGen && _wantConnected`, then always starts a new `_reconnectLoop(gen)`.
  - When the drop happens inside a loop's own `_open` (`:684`), that `_open` fails because teardown errors the config completer (`:709-714`). The loop catches it and keeps looping (`:686-690`) with the same `gen`. Now two loops run.
  - The loop never checks `_state == ready` before calling `_open` again.
  - `_open` overwrites `_linkSub`, `_fromNumSub` and `_heartbeatTimer` without cancelling them (`:594, 600, 612`).
  - flutter_blue_plus `connect()` on a device that is already connected returns at once (`bluetooth_device.dart:150-151`), so the redundant `_open` "succeeds".
- **What it does in the field:** a second `connecting → pairing → configuring → ready` shortly after a recovery (channels cleared, pings skipped, out-of-range monitor sees the radio go away); leaked heartbeat timers fire forever; leaked link listeners with the current `gen` each start another loop on the next drop, so loops multiply; two overlapping `_open` calls can tear down each other's working link.
- **Likely triggers:** a radio rebooting after the Radio Setup commit, a radio at the edge of BLE range, low battery.
- **Fix:**
```dart
bool _reconnecting = false;
void _onLinkLost(int gen) {
  if (gen != _linkGen || !_wantConnected) return;
  final wasReady = _state == RadioConnectionState.ready;
  unawaited(_teardown(sendDisconnect: false));
  if (wasReady && !_reconnecting) _reconnectLoop(gen); // lost mid-_open: its owner retries
}
// _reconnectLoop: if (_reconnecting) return; _reconnecting = true; try {...
//   if (_state == RadioConnectionState.ready) return; before _open ...} finally { _reconnecting = false; }
// top of _open: _heartbeatTimer?.cancel(); await _linkSub?.cancel(); await _fromNumSub?.cancel();
```
  Then let the constructor take a `BleTransport` so a fake can test a drop during the handshake.
- **Tester note:** a double "connecting" after one drop is this bug, not the radio. A relaunch clears it.

**F2 — Buffered packets treated as live (High, medium confidence).**
- **Cause:** the replay flag is `queued: !isReady` (`:828-829`). From memory of the firmware's `PhoneAPI` (check), buffered MeshPackets are only sent after `config_complete_id`. By then `_setState(ready)` has run (`:615`), so `queued` is almost never true. The other guard, `rxTime` (`radio_types.dart:205-209`), is 0 when the radio has no time. Radios without GPS (Heltec) have none, and the app never sends the time (no `set_time_only` anywhere in `lib/`).
- **Effect:** after a Bluetooth gap of a few minutes, the radio's backlog (beacons included) is recorded at the reconnect spot. It also counts as "base heard now" (`packet_processor.dart:222-224`).
- **Fix:** add `_replaying = true` in `_runHandshake`; in the drain, set it false at the first empty read once ready; use `queued: _replaying || !isReady`. Also send `AdminMessage(setTimeOnly: now ~/ 1000)` after each connect (field 43 exists in the vendored `admin.proto:423`). ACKs in the backlog still complete their pings: `_onPingReply` runs before the queued filter, which is correct.

**F3 — PKI recovery gaps (Medium).**
- **Cause:** the NAK handler matches only `PKI_UNKNOWN_PUBKEY || PKI_FAILED` (`:1072-1073`). The vendored proto defines 39 as the sender-side failure, "no public key for the remote node", distinct from 35. CLAUDE.md records a local 35 on 2.6, so which code you get may vary by firmware. `ensureContact` (`:968-972`) skips `add_contact` whenever the phone's cache has a 32-byte key, even after a local NAK proves the radio lacks it. `nodeInfos` and `myNodeNum` are never cleared in `_runHandshake` (`:620-630`), so after connecting to the base and then the mobile on the same instance, the cache still holds the base's own record. Radio Setup's `_introduce` papers over this only in its own flow.
- **Fix:** add `PKI_SEND_FAIL_PUBLIC_KEY` to the recovery set. On a NAK from our own node (`packet.from == myNodeNum`), call `ensureContact(force: true)` so it adds the saved contact regardless of the cache. Clear `nodeInfos` and `myNodeNum` when the descriptor id changes.
- **Re-flashed radio** (same node number, new key): firmware 2.6+ refuses to replace a known key from an over-the-air NodeInfo, and the saved contact holds the old key. **Procedure:** run Radio Setup on the re-flashed radio first, then on the other. If PKI NAKs persist, use "Clear nodes list" on the radio sending the pings and run Radio Setup again. Code option: `removeByNodenum` (`admin.proto:397`), then `addContact`.

**F4 — Fixed 30 s timeout and airtime that ignores retransmits (Medium).**
- **Cause:** the firmware retransmits a want-ack DM up to 3 times, with a wait that grows with airtime and slot length. Rough estimates (check):

  | Preset | Wait per retransmit | Effect of the fixed 30 s |
  |---|---|---|
  | LONG_FAST | ~6–7 s | fits (MAX_RETRANSMIT at ~25 s) |
  | LONG_MODERATE | ~12 s | ACKs after the 2nd retransmit arrive after 30 s |
  | LONG_SLOW | ~25 s | any ping that needs one retry times out |

  `_meterTx` counts one transmission per ping (`:922`), and `AirtimeModel` budgets one.
- **Effect:** late ACKs are recorded as `timeout`, biasing slow-preset maps toward "lost". Out of range, "Air x%" can read 5% while the real figure is about 20%. In EU_868 the firmware's own hourly limit (10% × 50%, so 5%) is exceeded, and pings start coming back `DUTY_CYCLE_LIMIT`.
- **Fix:** set the timeout per preset (for example 30 / 45 / 90 s), or keep the ping open until the firmware's `MAX_RETRANSMIT` NAK, with a cap. Count about 4x airtime for unanswered pings.
- **Tester note:** use LONG_FAST or faster for this test.

**F5 — Pings that never left the radio count as lost (Medium).**
- **Cause:** `range_stats.dart:339` skips only `throttled`. `kml.dart:48` checks membership in `{timeout, error, throttled}`, but stored errors are `error:<REASON>`, so they never match; `AckStatus.isError` exists and isn't used. A local NAK has `responder == myNodeNum`, so it takes the full ACK path (`active_probe_service.dart:262, 300-318`), counts in `pingsAnswered` and writes an ACK row from our own node.
- **Fix:** add a "not transmitted" set (`SEND_FAILED`, `PKI_SEND_FAIL_PUBLIC_KEY`, `NO_CHANNEL`, `TOO_LARGE`, `NO_INTERFACE`, plus `PKI_UNKNOWN_PUBKEY` when it comes from our own node) and skip it like `throttled`. Use `AckStatus.isError` in KML.

**F6 — Failure reasons invisible in the field (Medium).**
- **Cause:** `DiagLog` gets only state names (`app.dart:124-125`). The reconnect, read, ping and NAK errors are `print()` only. The "forget the device in iOS Settings" help appears only on a manual connect (`connection_banner.dart:295-303`).
- **Fix:** log those errors with `DiagLog.instance.log('ble', …)`. Carry the last error on `ConnectProgress` so the reconnect UI can show it. If the error matches `pairing information|insufficient|authentication`, stop the loop and show the forget-device help.

**F7 — No liveness watchdog (Medium).** Heartbeat failures are swallowed (`:612-614`). The radio sends its own DeviceMetrics to the phone about every 60 s (`:47-48`). **Fix:** if nothing has been read for about 3 minutes while ready, or 3 heartbeats fail in a row, force a teardown and reconnect.

**F8 — Official Meshtastic app (procedure).** iOS shares one link between apps, and each FromRadio frame reaches only one of them. Symptoms: random ping timeouts, handshakes that never finish, missed beacons. **Procedure:** in the Meshtastic app, disconnect both radios and turn off auto-reconnect (or delete the app), and force-quit it. If iOS Settings → Bluetooth shows the radio "Connected" while our app is closed, something else holds it.

**F9 — Stale channel stats.** `_lastChannelStats` is only ever set (`:323`). NodeDB values are used only while it is null (`:837-840`), and the session takes the last value if it's under 5 minutes old (`session_manager.dart:252-256`). So the base-then-mobile flow records the base's figures. **Fix:** reset it on handshake when the radio changes, and stamp NodeDB values with `lastHeard`, not now (`:101`).

**F10 — Stop race.** `_sendPing` checks `isActive` (`:208`), but `beforeSend` then awaits two DB calls (`:218-233`). If `stop()` clears `_pendingPings` in that window (`:183`), `beforeSend` adds the ping back (`:234`) and it is sent. `_activeSessionId` is never cleared, so the result is recorded. **Fix:** in `beforeSend`, after the awaits, `if (!isActive) throw StateError('stopped');`. The radio then returns a no-send `SEND_FAILED`, which is ignored. Also null `_activeSessionId` in `stop()`.

**F11 — Implicit ACK wins.** The first reply completes the ping (`:1054`). **Fix:** on implicit, wait a few seconds for the base's real ACK before recording. Unlikely to trigger with a private channel on its own frequency slot and LOCAL_ONLY on both radios.

**F12 — Handshake timeout.** Make it reset on every frame received (for example 20 s with no progress), or raise it to 120 s.

**F13 — Newer enum values.** protobuf.dart puts an unknown enum value into `unknownFields` and the getter returns the default (`coded_buffer.dart:74-81`). `Routing.error_reason` sits in a oneof, so a new NAK code reads as NONE (`:812-814`). When a config is modified with `deepCopy()..region = …`, protobuf writes our new value first and the old unknown value after it (`coded_buffer.dart:26-28`), and the firmware keeps the last value it decodes. Not an issue on 2.7.26. **Mitigation:** regenerate the protos before testing 2.8 radios. Treat a Routing reply with unknown fields as `error:UNKNOWN`. Clear the field and its unknown tag before setting it.

**F14.** Call `reply.ignore()` when `_write` throws (`:1141-1153`).

**F15.** On a generation mismatch in `_open` (`:588, 610`), disconnect the device that call connected.

**F16.** When the adapter turns `on`, cut the reconnect wait short. Tester: expect up to about 75 s.

**F17.** FBP's single global lock covers every device. Tester: change the base beacon before starting a session, not during one.

**Android note (required for BLE PRs):**
- **Background:** iOS uses `bluetooth-central` + `location` (`Info.plist:81-85`); Android needs a foreground service.
- **MTU:** the 512 request is Android-only (`ble_transport.dart:47`). iOS caps writes at MTU−3; the largest ToRadio here is about 120 B, so it fits.
- **Bonding:** Android needs an explicit `createBond()` and must handle GATT 5/137 errors on the notify subscribe.
- **Reconnect:** Android often fails with GATT 133; add about 1 s after disconnect before retrying.
- **Ids:** Android uses a MAC address, which is stable.
- **EU duty limits:** see F4.

## 3. Checked and correct

- **Ping registration:** pings are registered before sending, so a fast ACK can't be missed (`:1012-1025`). The DB row is written first (tested).
- **Late, duplicate and failed pings:** late and duplicate ACKs are ignored (`:1017, 1054`). A send failure cleans up (`:1040-1042`), and `ping()` never throws.
- **PKI retries:** key-exchange retries after a NAK are limited to once a minute, with errors caught. No retry loop.
- **`sendAdmin`:** retries only on timeout, never on a NAK or after link loss. A commit or reboot ACK lost to the reboot counts as success (`:1187-1209`).
- **Reading FromRadio:** one read loop at a time, stops on an empty read, exits on link loss, and errors are caught (`:721-742`).
- **Handshake:** FromNum is subscribed before `want_config` (`:600-607`); it also polls every 250 ms in case FromNum doesn't fire (`:639`); `config_complete_id` is matched against our nonce; a collision with the special nonces 69420/69421 is negligible.
- **Teardown and loops:** teardown cancels timers and subscriptions and fails a pending handshake; the generation counter stops old loops after a user disconnect or connect; backoff goes 2→60 s with a 15 s connect timeout; a 10-minute outage keeps retrying; pending pings keep their own timers across reconnects, and their ACKs are still matched.
- **Writes:** with response, under the iOS MTU limit. FBP's global lock serializes overlapping reads and writes.
- **Background:** with `pauseLocationUpdatesAutomatically: false` (`gps_service.dart:236`), timers keep running while locked.
- **ActiveProbeService:** no ping rows while the radio isn't ready, the key exchange re-runs on ready, and the public-channel guard is checked in both the service and the radio.
- **Ids and frames:** packet ids are never 0 or 0xFFFFFFFF. Unknown or undecodable frames are tolerated. Own-node packets are filtered after channel stats are read. ROUTING replies aren't double-recorded.
- **Config write-back:** new fields in 2.8 configs survive `deepCopy` and are written back. Only new enum values are a problem (F13).
- **Airtime and stats:** no division by zero.
- **Radio choice:** `LastRadio` never picks the base while the mobile is known. The base needs confirming in the connect list. The scan de-duplicates by device id.
- **Riverpod:** providers aren't rebuilt mid-session.
- **Contacts:** only users with a key are saved, and corrupt data reads as empty.

## 4. Bench checks (about 45 min)

1. **Double loop (F1):** in a session, power the mobile off and on, and power it off again while it shows "Reading radio settings". Share the diag log and count the `[ble] ready` lines per recovery; more than one means F1.
2. **Replay (F2):** with the base beaconing every 60 s, turn Bluetooth off in iOS Settings (not Control Center) for 3–4 minutes and walk 100 m, then turn it back on. Look for dots at the reconnect spot, or a missing "dropped N stale/replayed" line in the diag log. Results differ between the T1000-E (GPS) and the Heltec (no GPS).
3. **PKI (F3):** clear the mobile's node list without keeping the base, start a session, and note the exact error shown and whether pings recover within about 2 minutes.
4. **Locked phone:** 20-minute session with the phone locked. Expect the full ping count and no reconnects.
5. **Radio off 10 minutes:** expect a radio-lost alert, reconnect within about 75 s of power-on, and pings plus the key exchange resuming.
6. **Radio Setup reboot:** expect a single `ready` afterwards.
7. **Slow preset (F4):** only if you plan to use one. If `received` round trips go over 20 s, the 30 s timeout is too tight.
8. **Official app (F8):** confirm it doesn't hold either radio.
9. **Stats after switching (F9):** connect to the base, then the mobile. Does the Air/Channel readout match the mobile's own figures?

**Field procedure summary:** use LONG_FAST or a faster preset; close or delete the official Meshtastic app; set the base beacon before starting a session; if the pill keeps retrying with the radio in hand, Forget This Device in iOS Settings and reconnect; if you see a double "connecting" after one drop, or "ready" with no pings for minutes, relaunch the app (the session resumes); share the diag log after the walk.
