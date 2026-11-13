# Field-test readiness audit — 2026-10-26

Five independent read-only Opus reviews of `field-build-oct23` @ `7e0e7fc`, plus firmware research against the Meshtastic firmware source (tags `v2.7.26.54e0d8d`, `v2.8.1.8e6a88d`) and protobufs. Detailed reports beside this file:

| Report | Scope | High | Medium | Low/Info |
|---|---|---|---|---|
| [firmware.md](firmware.md) | Firmware 2.5 → 2.8.1 changes vs app assumptions | 4 | 8 | 6 |
| [radio.md](radio.md) | BLE transport, reconnect, handshake, pings, contacts | 2 | 6 | 9 |
| [session.md](session.md) | Recording pipeline, beacons, GPS, alerts, DB, exports | 2 | 6 | 7 |
| [radio-setup.md](radio-setup.md) | Radio Setup admin sequence, roles, backups | 3 | 6 | 9 |
| [ux.md](ux.md) | Field usability, alerts, readability, handover items | 4 | 9 | 15 |

`flutter analyze` clean · 469 tests pass · no repository file was changed by the reviews. Severity below is my consolidated call. ✔ = I re-checked the evidence myself (code line or firmware source); the rest is the reviewer's evidence, with their confidence noted in the detailed report. Three findings were reproduced with scratch tests (session F1/F4, setup F1/F3/F4).

**Firmware landscape today:** ✔ 2.7.26 is still "Latest"; both 2.8.0 builds are **revoked** (one fails LR1110 init on the T1000-E, one has a signing bug); 2.8.1.8e6a88d (2026-10-01) is the newest pre-release. There is no 2.8.2 or 2.9. The vendored v2.7.26 protos decode everything 2.8.1 sends; only new enum *values* are a problem (§1.7).

---

## 1. Fix before the field day (all small; one phone build)

**Status (2026-10-26, same day):** all nine applied on `field-build-oct23` (uncommitted): 1 (+ `ensureContact(force:)` on a local NAK, node cache and airtime stats cleared when switching radios), 2, 3, 4 (+ `BeaconTracker.skipSlots`), 5 (pre-send check only; the post-reboot read-back is not built), 6, 7 (lora/device unknown tags cleared; unknown Routing error → `error:UNKNOWN`), 8 (timeout includes `2 × beacon + 30` with pings off; the same alert isn't repeated within 2 min), 9 (key row wraps; light warning text #9A6600; base status bar 17 pt). Analyzer clean, 476 tests pass, iOS simulator build compiles. Not done from this list: Time Sensitive entitlement, ping-key icons-only variant. Also landed after the bench (same commit): replayed-packet filter (§3 first item), self-base refusal at session start, base picker hides the mobile and shows `!hex` ids, "Stop beacon…" with confirmation, session-start warning when the recorded beacon is off, "Start beacon" on the beacon card, lost-bond (code 14) hint and no endless retry, reconnect failures in the diag log, `role = CLIENT` in Radio Setup (+ Role row in the restore diff), snackbars cleared on tab change with a hard timeout, anchored share sheet.

| # | Finding | Why it matters on the day | Fix |
|---|---|---|---|
| 1 | ✔ **Pings can't self-heal a missing key on 2.7.19+.** Since firmware 2.7.19 (#9485) a DM to a node whose key the radio lacks is refused *locally* with `PKI_SEND_FAIL_PUBLIC_KEY` (39), nothing goes on air (2.7.26 `Router.cpp:664`). The recovery branch at `meshtastic_radio.dart:1072-1073` only matches `PKI_UNKNOWN_PUBKEY`/`PKI_FAILED`, so `ensureContact` never runs. CLAUDE.md's "2.6+, local PKI_UNKNOWN_PUBKEY" is wrong. | Every ping `error:PKI_SEND_FAIL_PUBLIC_KEY` with a ~0 s round trip after a node-list clear or a re-flash; no recovery. | Add `PKI_SEND_FAIL_PUBLIC_KEY` to the condition; on a NAK from our own node call `ensureContact` ignoring the phone's node cache (radio F3). Fix the CLAUDE.md note. |
| 2 | ✔ **Foreground alerts are probably silent.** `AppDelegate.swift` never sets `UNUserNotificationCenter.current().delegate`, which flutter_local_notifications needs to present a banner/sound while the app is open. Lock-screen alerts are fine. (session F8, ux 1; TC-38 on the beta site documents the bug as intended behaviour.) | "Out of range"/"Radio lost" never heard with the app open. | One line in `didFinishLaunching`; verify on the phone. Consider `interruptionLevel: timeSensitive` so Focus modes don't hide it. |
| 3 | ✔ **A drop during a reconnect handshake starts a second reconnect loop.** `_onLinkLost` always starts `_reconnectLoop(gen)`; a loop whose own `_open` fails keeps looping with the same gen, and `_open` overwrites `_linkSub`/`_fromNumSub`/`_heartbeatTimer` without cancelling (`meshtastic_radio.dart:660-692, 594-612`). Loops multiply on later drops. | Double "connecting…" after one drop, leaked heartbeat timers, overlapping opens tearing down a working link. Likely triggers: radio reboot after Radio Setup, edge of BLE range. | `_reconnecting` guard, don't start a loop when the loss happened inside an `_open`, cancel leftovers at the top of `_open` (sketch in radio F1). |
| 4 | **Fabricated `telemetry_miss` rows after a BLE outage** (reproduced). `tickBeacons` returns early while the radio isn't ready *before* `dueMisses()` consumes the slots (`packet_processor.dart:128-129`), so on reconnect every slot of the outage is emitted as a miss at an interpolated position (30 min at 60 s = 29 misses). | "~missed" jumps after every radio-lost episode; maps show holes that weren't measured. | Consume the slots while not ready (`beacons.dueMisses(now); return;`), or add link-down/link-up to the tracker; add a test that ticks after `ready`. (session F1) |
| 5 | ✔ **Radio Setup reports "Done" when the link was lost before the commit was sent.** `sendAdminAttempt` throws `StateError('Radio not ready')` before writing (`:1138`); `commitSettings` (`:1187`) catches `StateError` and treats it as "commit reply lost to reboot". Settings stay in RAM only. Restore uses the same path. This matches the solar node's state from 2026-10-24. | A radio that looks configured reverts on the next power-cycle. On 2.8 the 60 s edit auto-commit then persists a *partial* config instead. | Only swallow the error when the write was actually sent; after the reboot, reconnect and read back channel 0, preset, region, rebroadcast and beacon config, logging ✓/✗. (setup F1, firmware F9) |
| 6 | **"Beacon is off" false positive when coming back from a dead zone** (reproduced). The rule is "silent > 3 intervals AND base heard within 3 intervals", so the first ping ACK after a long gap satisfies it (`beacon_tracker.dart:185-191`). | False "Base reachable but beacon off" banner (and a "Switch to telemetry" button on Range Test sessions) until the next beacon. | Track `reachableSince`, measure silence from `max(lastBeacon, reachableSince)`. (session F4) |
| 7 | ✔ **Unknown enum values silently undo preset/region writes.** Dart protobuf keeps an unknown enum value (2.8's MEDIUM_TURBO=16, TINY_*, 70 cm regions) in `unknownFields`; `deepCopy()..modemPreset = x` writes the new value *then* the old unknown one, and the firmware keeps the last. Also a Routing error code newer than the protos decodes as NONE, so a NAK counts as an ACK. (setup F4 reproduced the byte layout; radio F13; firmware F4) | A 2.8 radio on MEDIUM_TURBO "succeeds" setup and stays on MEDIUM_TURBO; app shows LONG_FAST. | Clear the unknown tag before setting (or build the LoRa config fresh); treat a Routing reply with unknown fields as `error:UNKNOWN`. Regenerate protos from `v2.8.1` before testing 2.8 radios (wire format verified compatible). |
| 8 | **Out-of-range alert flaps with pings off.** Timeout is `max(90 s, 3 × pingInterval)` and ignores the beacon interval (`session_manager.dart:294-298`); a 120/300 s telemetry beacon trips "Out of range" every cycle, and there's no hysteresis or rate limit. | Phone buzzes constantly on a telemetry-only session. | Include `2 × beaconInterval + 30` in the max; delay "Back in range" ~2 min; cap sounding alerts to one per 5 min. (session F3) |
| 9 | **Charts ping-key row overflows on every phone narrower than a Pro Max** (screenshot: 51 px over on the SE); amber warning text is ~2.9:1 contrast at 11.5–13 pt, unreadable in sun. | The "failed" key is cut off; "nothing is being recorded"/Start errors are hard to read outdoors. | `Wrap` the keys; darker amber for text (~#8A5A00), keep #C98A00 for fills; base status bar 17–20 pt. (ux 3, 4) |

## 1b. Bench pass 1 (2026-10-26 afternoon, T1000-E 2.7.15 mobile + Heltec V3 2.8.1 base)

| Test | Result | Evidence |
|---|---|---|
| 1 Setup commit survives a reset | Pass | Heltec read back over USB after reset: MeshTest Base, MEDIUM_SLOW, US, LOCAL_ONLY, telemetry 60 s |
| 2 Local PKI NAK | Not run (both Seeed radios are 2.7.15, before the 2.7.19 refusal; needs the 2.8.1 Heltec as mobile) | |
| 3 Foreground alert | Pass | banner + sound with the app open; vibration on the lock screen |
| 4 No fabricated misses | Pass | 0 `telemetry_miss` rows over a 9-minute Bluetooth outage |
| 5 Double reconnect loop | Pass | 5 drops incl. a reboot during the reconnect's own connect; one `ready` per recovery, no overlap |
| 7 Replayed packets | **Reproduced then fixed** | 2 beacons stamped at reconnect time (15:41:17) before the fix; none after it (15:57 outage) |
| 8 Alert repeat limit | Changed | a second real "Out of range" 95 s after the first was dropped; now posted silently instead |
| Mixed 2.7.15 / 2.8.1 | Pass | the 2.7.15 mobile decodes the 2.8.1 base's signed telemetry directly (SNR ~13 dB) |
| 2.8 node number = crc32(pubkey) | Confirmed on hardware | Heltec 1759606987 == zlib crc32 of its public key; old number 3176152732 still in the T1000-E's node list |

Found on the bench, not in the list:
- **"Stop it" on the end-of-session snackbar switches the base beacon off** with one tap, no confirmation, and nothing later says the beacon is off: the next sessions ran with beacon kind "none", the ACKs kept the bar green, and no beacon line was shown. Fix queued: label "Stop base beacon" + confirm; warn at session start when the recorded beacon is off; beacon card "off since hh:mm, start it".
- **A map was saved with the mobile radio as its base** (map 7), so the session pinged the T1000-E itself and every ping read "delivered" (the radio ACKs locally, no signal values) while "base not heard" stayed red. Fixed: session start refuses a map whose base is the connected radio; the picker hides the mobile and shows `!hex` ids.
- **iOS bond left over from the 2.8 flash** (firmware F5) hit on the first connect to the Heltec: "code 14 peer removed pairing information"; "Forget This Device" fixed it. Queued: detect code 14 and show that hint.
- **Snackbars followed the user into Settings and a snackbar with an action never auto-dismissed** (iOS accessibility navigation keeps action snackbars up). Fixed: cleared on tab change, hard 12 s timeout, close icon.
- **Share diagnostics did nothing** on the phone (cause unknown; no exception surfaced). Worked around with `xcrun devicectl device copy from … --domain-type appDataContainer` for diag.log, the sqlite DB and the prefs plist; the share is now anchored and reports errors.

## 2. Procedure mitigations for the day (no code needed)

**Firmware**
- ✔ Never run **2.8.0** (revoked; its signatures are incompatible with 2.8.1, so a 2.8.0 base's beacons are dropped by a 2.8.1 mobile). Check the firmware line on both radios.
- ✔ **After any 2.7 → 2.8 upgrade, redo Radio Setup on both radios and start a new map.** On the first 2.8 boot the node number becomes `crc32(public_key)` (2.8.1 `NodeDB.cpp:537`) so roles, contacts, base location and the map's base all point at a dead number; and ✔ a one-time migration forces `device_telemetry_enabled=false` (`NodeDB.cpp:2932-2942`), silencing a telemetry beacon.
- ✔ After flashing an **ESP32** radio (Heltec V3) to 2.8, "Forget This Device" in iOS Bluetooth settings (bond purge, #10741). nRF52 (T1000-E) is unaffected.
- A **classic ESP32** base (T-Beam, Heltec V2, T-LoRa, Station G1) on 2.7 has no Range Test and the app can't tell: pick the telemetry beacon by hand.
- 2.6.x mobile can't turn telemetry broadcast off (no `device_telemetry_enabled`); accept the extra airtime.
- Use **LONG_FAST or faster**. The fixed 30 s ACK timeout is too short for LONG_MODERATE/LONG_SLOW, and 2.8 retries a DM up to 5 times so airtime is under-counted at the edge.

**Radios, the day before**
- Don't reinstall the app or "Erase all app data": the MeshTest key and backups live only on the phone. Share each radio's *Original settings* backup to the Mac. Note: importing a backup for a radio that already has one gets pruned immediately (setup F3), so only import before any setup on that radio.
- Originals taken before 2026-10-23 lack device/telemetry config, so "Put back" leaves LOCAL_ONLY and the beacon telemetry in place (setup F2). Note each radio's normal rebroadcast mode in the official app so you can restore it by hand.
- Run Radio Setup **mobile-first** (base-first never asks the mobile's region and defaults it to US; handover item 2 is still open).
- After "Done" on each radio: **power-cycle it, reconnect, confirm** MeshTest, preset, role and the ✓ line (works around §1.5). Solar node: power-cycle *before* re-running setup.
- Close or delete the official Meshtastic app and make sure iOS Settings → Bluetooth doesn't show either radio "Connected" while ours is closed; two apps on one link each get only some FromRadio frames.
- A re-flashed radio keeps its node number but has a new key; firmware 2.6+ won't replace a known key from NodeInfo. Run Radio Setup on the re-flashed radio first, then the other; if PKI NAKs persist, "Clear nodes list" on the pinging radio and redo setup.

**Morning of**
- Restart a Range Test base (2.6/2.7): the module switches itself off 8 h after boot.
- Set the base location on site (map menu → Set base location…, or "I'm standing at the base"). Untick "use my position" if you create the map away from the base; it's on by default whenever GPS is good.
- Pan the map over the whole test area at the zooms you'll use while still on Wi-Fi/cell: hosted PMTiles are cached only in memory, so a blank map offline is expected. Don't swipe the app away afterwards.
- Phone: Location "While Using" with Precise on; Notifications with sound; Live Activities on; Driving Focus off or the app allowed; Low Power Mode off; text size default or one step up (larger sizes break the map header and pill).

**During**
- Never tap **Disconnect** in the radio sheet during a session: it turns auto-reconnect off and the panel keeps saying "until it reconnects".
- Never open Radio Setup or "Switch base to telemetry" mid-session (no session guard; the tracker never retargets, so misses stop counting).
- A double "connecting…" after one drop is §1.3; relaunch the app, the session resumes.
- Write down times of BLE drops and radio reboots: misses in those windows may be fabricated (§1.4) and the radio's buffered backlog may be recorded at the reconnect position (§3).
- If iOS kills the app there is no alert at all; the Live Activity keeps showing old values. Reopen it and the session resumes.
- End the session explicitly, "Stop it" for the base beacon while in BLE range of the base, export the full CSV right away.

## 3. Fix soon (medium; next field-build PR or own PRs per the batching rule)

- ✔ **Buffered packets replayed after reconnect look live.** `queued: !isReady` (`meshtastic_radio.dart:829`) is set before the firmware sends its backlog, and the app never sends `set_time_only`, so a GPS-less radio reports `rx_time` 0 and the stale filter can't catch them. They're recorded at the reconnect spot and reset the out-of-range clock. Fix: a `_replaying` flag cleared at the first empty read, plus `AdminMessage(setTimeOnly)` on connect. Bench-check needed (radio F2, session F6).
- **Local NAKs count as sent-and-lost** in range stats and get an ACK row from our own node; KML never matches `error:<REASON>` (radio F5, session F9/F14).
- **No alert when iOS kills the app** mid-session: dead-man local notification rescheduled every tick; ask "continue or end?" on resume after a long gap (session F2).
- **Imported backup pruned on import**; **originals without device/telemetry config**; **Radio Setup and Restore don't block each other**; **no session guard on Radio Setup** (setup F2, F3, F7, F12).
- **2.8 node-number change**: detect in `RadioRoles.learn()` when a known Bluetooth id reports a new node number, remap roles/contacts/base, warn the user; skip `add_contact` when `crc32(key) != num` (firmware F1). **Telemetry force-off after upgrade**: compare the base's `deviceTelemetryEnabled` with the stored beacon on connect and offer a one-tap re-enable (firmware F2).
- **Fresh 2.8 radio changes node number when its region is first set** without a reboot; the following commit goes to the stale `myNodeNum` (firmware F8). Wait for the new `myInfo` or reconnect after the region write.
- **Region list** offers EU_866/EU_874/EU_917/EU_N_868 and ITU regions that 2.7.26 maps to the US band and 2.8.1 rejects (firmware F12). Filter by firmware; on 2.8+ use `FromRadio.region_presets`.
- **ACK timeout per preset/firmware** and retransmit-aware airtime (radio F4, firmware F10); **implicit ACK pre-empts the real ACK** and on 2.8.1 stores the relay's SNR on the row (radio F11, firmware F11).
- **No liveness watchdog** (failed heartbeats ignored) and **failure reasons only `print()`ed**, lost in TestFlight; a lost iOS bond retries forever with no "forget the device" hint (radio F6, F7).
- **GPS fixes attached regardless of age/accuracy**; `gpsAccuracy` is never read (session F7). **GPS "fix" status never goes stale** (ux 25).
- **Live map keeps the previous session's dots**; no base marker; per-packet full rebuilds (ux 7, 24, 26). **Session sheet opens at 50 %** so Start and its refusal text are below the fold on an SE (ux 10).
- **Live Activity never goes stale** after a kill, and iOS ends it after ~8 h while Dart thinks it's running (ux 11, session F12).
- `lastChannelStats` not reset when switching radios (base's airtime recorded on a mobile session); stop race lets one ping land after `endSession`; `endSession` errors unhandled; orphaned `isActive` rows after a crash (radio F9/F10, session F10/F11, ux 21).
- Settings: "Signal Direction" does nothing; "Keep Screen On" copy is inaccurate; `.mabackup` document type registered but not handled (ux 18, 19; setup F14).

## 4. Firmware compatibility matrix

| Firmware | App impact | Status |
|---|---|---|
| ≤ 2.6.7 | No `add_contact` (ACKed, ignored); DMs without a key go out channel-encrypted, so pings still work. Mobile can't disable telemetry broadcast. | OK |
| 2.6.8 – 2.7.13 | `add_contact` works; `nodedb_reset` does **not** keep favourites (comment at `meshtastic_radio.dart:1161` says "before 2.7"). | OK |
| 2.7.14 – 2.7.18 | Favourites survive reset. NodeInfo want_response replies suppressed 12 h per requester from 2.7.17 (key exchange relies on `add_contact`). | OK |
| 2.7.19 – 2.7.26 | **Local `PKI_SEND_FAIL_PUBLIC_KEY` refusal** not handled (§1.1). Range Test compiled out on classic ESP32 with no `excluded_modules` bit. EU_866/EU_874/EU_917/EU_N_868 map to the 902–928 MHz row. | Fix §1.1 |
| 2.8.0 (both builds) | **Revoked.** LR1110 init failure on T1000-E; signatures incompatible with 2.8.1. | Don't use |
| 2.8.1 | Node number = crc32(pubkey) on first boot and on first region set; telemetry forced off once on upgrade; ESP32 bond purge; new presets/regions as unknown enum values; 5 DM attempts; 60 s edit auto-commit; signed broadcasts (+64 B per beacon); `region_presets` frame (ignored safely); `use_aead` channel flag (default off). BLE UUIDs, handshake, admin shapes, port numbers, Routing.Error, Range Test payload and frequency-slot hashing are **unchanged**. | Procedure §2 + fixes §1.7, §3 |

## 5. Bench checks before the day (priority order, ~1.5 h)

1. **Local PKI NAK:** on a 2.7.26 mobile, clear the node list without keeping the base, start a session: expect `error:PKI_SEND_FAIL_PUBLIC_KEY`; confirm the §1.1 fix recovers within ~2 min.
2. **Foreground alert:** app open, base off: does a banner with sound appear after the §1.2 fix?
3. **Double loop:** in a session, power the mobile off/on, and off again while "Reading radio settings"; count `[ble] ready` lines per recovery in the diag log.
4. **Replay:** base beaconing at 60 s, iOS Bluetooth off (Settings, not Control Center) for 3–4 min while walking 100 m, then on: look for dots at the reconnect spot and the "~missed" count (T1000-E with GPS vs Heltec without).
5. **Setup commit:** confirm a single `ready` after the Radio Setup reboot, then power-cycle and confirm settings held.
6. **Locked phone 20 min:** full ping count, no reconnects, Live Activity updating.
7. **Radio off 10 min:** radio-lost alert, reconnect within ~75 s of power-on, pings and key exchange resume.
8. **Telemetry-only session (pings off)** at 120 s: watch for flapping alerts (§1.8).
9. If any radio goes to 2.8.1: node number before/after, key unchanged, telemetry state, MeshTest/preset/rebroadcast kept, iOS bond.
10. If a 2.8 radio is on MEDIUM_TURBO: does Radio Setup's change to LONG_FAST stick (§1.7)?

## 6. Doc and site corrections

- **CLAUDE.md:** the local refusal is from **2.7.19**, code `PKI_SEND_FAIL_PUBLIC_KEY` (39), nothing goes on air; `PKI_UNKNOWN_PUBKEY` is the *base's* NAK (~1 s round trip) and the firmware answers it with a NodeInfo. Add: on 2.8 the node number is crc32(public key) and changes on the first 2.8 boot and on the first region set. Base-first setup does not give the base the mobile's key (the NodeInfo exchange covers it).
- `meshtastic_radio.dart:1161` comment: keep-favourites applies from 2.7.14. `meshtastic_presets.dart:161-165` comment: newer enum values read as LONG_FAST in Dart.
- `radio_backups_section.dart:90-92` still says "reboots" (handover item 4 leftover).
- **Beta site (for the website agent, not edited here):** TC-37 describes a "Reconnecting… button" that doesn't exist; TC-38 documents the missing foreground alert as intended; TC-39/40 say "Tap Connect"; TC-41's "Packets still goes up" no longer applies (Start is refused without location); TC-44 should say previously viewed hosted-region areas are blank offline too.

## 7. Handover findings (beta_handover_findings.md) status

| # | Item | Status |
|---|---|---|
| 1 | Base location on fresh install | Partly fixed: opting out of the Radio Setup location is remembered; still on by default, saved position has no age check, GPS still `request:false` at launch, "use my position" default is a new risk, long-press text wrong. |
| 2 | Base-first sets region US silently | **Not fixed** (`_switchToMobile` never calls `_ensureRegion`). |
| 3 | Stale "Tap Connect" wording | Fixed. |
| 4 | Wording (public key / restarts / While Using / "Reading it") | Fixed except `radio_backups_section.dart:90-92`. |
| 5 | "base ?" badge | Unchanged (cosmetic). |
| 6 | Bluetooth prompt at launch | Unchanged (likely at launch). |
| 7 | AI consent sheet | Fixed. |
| 8 | CLAUDE.md alert note | Code comments stale; foreground banner it promises probably doesn't fire (§1.2). |

## What was verified as fine

Ping registration before send and late/duplicate ACK handling; public-channel guard in session start, pings and key exchange (including after resume); admin NAKs never retried and every step has a timeout; local admin needs no passkey on any version (unless `is_managed`); backup taken before any admin write; MeshTest in slot 0 with slots 1–7 disabled and both radios on the same frequency slot; telemetry intervals rounded up to whole minutes; miss rows kept out of maps, counts and all exports but the full CSV; relayed packets excluded from recording and from "base heard"; Range Test seq reset on base reboot not counted as a gap; migrations v1→v7 additive only; CSV in UTC with offset and formula-injection guarding; `LastRadio` never auto-picks the base; delete/erase confirmations; "Stop it" failure stays retryable; Live Activity doesn't orphan if the session ends during start.
