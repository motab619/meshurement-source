# Field UX failure-mode review (Opus, 2026-10-26)

Method: code reading, 8 UI test files (31 tests, all pass), and the existing simulator debug build (`build/ios/iphonesimulator/Runner.app`, built 13:29 today) run in demo mode on an iPhone SE (3rd gen) simulator at default, XXL and AX-Medium text sizes. No repository file changed. Screenshots in the scratchpad: `se-charts.png`, `se-map.png`, `se-session.png`, `se-xxl-map.png`, `se-xxl-base.png`, `se-ax-map.png`, `se-ax-session.png`.

Confidence: **H** = confirmed by a screenshot, a test or unambiguous code. **M** = strong code evidence, needs a device check. **L** = inference.

## 1. Ranked findings

| # | Sev | Conf | Where | Symptom |
|---|---|---|---|---|
| 1 | High | M | `ios/Runner/AppDelegate.swift:13-18`, `out_of_range_monitor.dart:218-231` | No `UNUserNotificationCenter` delegate, so iOS suppresses banner and sound while the app is open. The plugin README and Flutter's `FlutterPlugin.h:498-501` both say the app must set it. TC-38 ("no notification while open") matches this bug, not the intended behaviour. |
| 2 | High | H | `pmtiles_archive.dart:151-152`, `map_tiles.dart:67-82`, `base_map_layers.dart:60-67` | PMTiles tiles are kept only in memory. The OSM fallback's disk cache never holds tiles for the hosted region. Offline means blank grey and there is no "offline" hint. `TILES_STREETS_URL=''` can't turn hosting off (`_define('')` is null, so it falls back to the hosted URL). |
| 3 | High | H | `signal_charts_panel.dart:503-527` | Ping key row: fixed widths about 350 pt against 303 pt available on the SE and 321 pt on a 393-pt iPhone. Charts title also truncates to "Signal from b…". |
| 4 | High | H | `status_colors.dart` (light warning #C98A00), `app_theme.dart:503-518`, `signal_display.dart:64-75` | Amber text on off-white about 2.9:1; bodyMedium 13 pt, bodySmall 11.5 pt; the "big" base status bar is 13 pt. The yellow RSSI value on the light readout is about 2:1. |
| 5 | Med | H | `connection_banner.dart:95-125`, `map_screen.dart:301-363` | Larger text breaks the Live map header. At XXL the name shows as "T…" and the pill overflows on the base screen. At AX-M the pill overflows by 37 px and "Hearing the base" wraps one word per line, because the readout has no max width. |
| 6 | Med | H | `connection_banner.dart:267-276`, `meshtastic_radio.dart:572-577`, `session_panel.dart:247-255` | Disconnect in the radio sheet has no confirmation during a session and turns off auto-reconnect. The panel then says "until it reconnects", which never happens. |
| 7 | Med | H | `map_screen.dart:163-189` | `_signalDots` is never cleared. A new session's Live map still shows the previous session's dots and any pre-Start packets. |
| 8 | Med | H | `create_map_dialog.dart:47-48, 63-67, 83-84, 172-174` | "I'm standing at the base — use my position" is ticked by default whenever GPS is good, so a map created away from the base gets the wrong base. The test asserts this default. The subtitle says long-press moves the base; it doesn't (long-press opens the profile). |
| 9 | Med | H | `radio_setup_screen.dart:373-390`, `radio_profile_service.dart:116-119, 346-356` | Base-first "Find mobile radio" never calls `_ensureRegion`, so a region-less mobile is set to US. |
| 10 | Med | H | `session_panel.dart:76-80, 275-283, 494-507` | The sheet opens at 50%. On an SE, Start/End Session and the Start error text are below the fold, so a refusal can go unseen. |
| 11 | Med | M | `LiveActivityBridge.swift:69, 86`, `MeshActivityWidget.swift` | No stale date at start and the widget never checks `isStale`. After a kill or force-quit the lock screen keeps "Base in range". The "Greyed out" comment is false. |
| 12 | Med | M | `connection_banner.dart:580-615` | The connect-failure help sits in a fixed 300-pt dialog column with no scroll, so it overflows at larger text. |
| 13 | Med | M | `coverage_map_detail_screen.dart:205-224` vs `422`, `465-470` | The marker and terrain estimate ignore the Radio Setup base location; long-press uses it. A profile can open from an undrawn base. Only older maps are affected. |
| 14 | Low-Med | H | `signal_display.dart:20-23` | The readout shows the last SNR/RSSI with a coloured border forever, with no age. |
| 15 | Low-Med | H | `session_panel.dart:270-273, 491-507`, `session_manager.dart:145-152` | Location and notifications refusals give text paths only, no Open Settings button (Bluetooth has one). |
| 16 | Low-Med | M | `connection_banner.dart:37`, `providers.dart:317` | Watching the Bluetooth adapter at launch very likely shows the Bluetooth prompt on first launch (handover #6). |
| 17 | Low | H | `out_of_range_monitor.dart:141-162` | A phone↔radio reconnect resets the state, so a second "Out of range" alert fires. "base ?" never shows (handover #5). |
| 18 | Low | H | `settings_screen.dart:183-199` | The Signal Direction setting does nothing; its pref is never read. |
| 19 | Low | H | `settings_screen.dart:151-155` | Keep Screen On says it "Prevents iOS from suspending BLE", which is inaccurate. |
| 20 | Low | H | `beacon_status.dart:216-266` | Base beacon card: Restart and Stop sit side by side with no confirmation. An error replaces the status text and stays. The button row can overflow at large text. |
| 21 | Low | H | `session_panel.dart:313-322`, `session_manager.dart:225-241` | An `endSession` error is unhandled (try/finally, no catch). The tester sees nothing and the session is half torn down. |
| 22 | Low | H | `base_status_bar.dart:99-101` | A VoiceOver live region wraps text that changes every second, so it announces constantly. |
| 23 | Low | H | `coverage_map_detail_screen.dart:41-44, 378-409, 748-758` | With a map's detail open while recording, every packet re-runs the full events query and rebuilds every session tile. |
| 24 | Low | H | `map_screen.dart:163-169, 189` | Resumed dots are added with no cap (5000 can be exceeded). A full MapScreen rebuild happens per packet. |
| 25 | Low | H | `gps_service.dart:241-246` | GPS "fix" status never goes stale. |
| 26 | Low | H | `map_screen.dart:266-270` | No base marker on the Live map. |
| 27 | Low | H | `MeshActivityWidget.swift:144-150` | Live Activity SNR colours use fixed thresholds, not the app's margin-based colours. |
| 28 | Low | H | various | Wording: `radio_stats_readout.dart:91-93` "TX 1.2%/h"; `radio_backups_section.dart:90, 92` still says "reboots"; stale "only while backgrounded" comments at `app.dart:77` and `out_of_range_monitor.dart:22, 52`. |

## 2. Mitigations
1. Add `import UserNotifications` and `UNUserNotificationCenter.current().delegate = self` in `didFinishLaunching`. Test with the app open and the base off.
2. Cache PMTiles tile bytes on disk, or pre-fetch the test area as an offline pack. Show a "tiles unavailable offline" hint.
3. Put the ping keys in a `Wrap`, use icons only, or move them to a second line.
4. Use a darker amber for text (about #8A5A00) and keep #C98A00 for fills and icons. Raise the base status bar to 17–20 pt. In light mode, draw readout values in ink with a coloured border.
5. Cap the readout at about 45% width, as was done for the base beacon card. Make the pill's role label and range badge Flexible. Consider clamping text scaling on map chrome.
6. While recording, confirm Disconnect and change the panel text for a manual disconnect.
7. Clear the dots when the session id changes.
8. Default "use my position" off, or ask "Are you at the base now?". Point the subtitle to Menu → Set base location….
9. Call `_ensureRegion` after switching to the mobile.
10. Pin Start/End outside the scroll view, or open the sheet at 0.85, and also show the start error in a SnackBar.
11. Set a stale date at start and render `isStale` as "app stopped — open it".
12. Make the connect error scrollable.
13. Use one base resolver for the marker, terrain estimate and long-press.
- Low items: add an age to the readout, Open Settings buttons, remove Signal Direction, reword Keep Screen On, confirm Stop, catch `endSession` errors, put the live region on the state only.

## 3. Handover status

| # | Item | Status |
|---|---|---|
| 1 | Base location on a fresh install | Partly fixed. Opting out of the Radio Setup location is remembered and honoured; the subtitle explains where it comes from. It is still on by default, and the new "use my position" default is a new risk (finding 8). Long-press is unchanged and the dialog text about it is wrong. |
| 2 | Base-first sets US | Not fixed. |
| 3 | Stale "Connect" wording | Fixed (`app.dart:164, 183`, `radio_setup_screen.dart:548`, `session_panel.dart:384`, backups text gone). |
| 4a | Channel key vs public key | Fixed (`radio_profile_service.dart:219`). |
| 4b | reboot vs restarting | Partly fixed: `meshtastic_radio.dart:1313` says "restarts", `radio_backups_section.dart:90, 92` still says "reboots". |
| 4c | "While Using or Always" | Fixed. The Always key is now in Info.plist, but geolocator asks for When-In-Use first, so the message is right. |
| 4d | Two "Reading it" cards | Fixed. |
| 5 | "base ?" badge | Unchanged; cosmetic, since the status bar shows "Radio link lost". |
| 6 | Bluetooth prompt timing | Unchanged; likely at launch. |
| 7 | AI consent sheet | Fixed; it now lists the typed question. |
| 8 | CLAUDE.md | Fixed, but the code comments are stale, and the foreground banner it promises probably doesn't happen (finding 1). |

**Mismatches in `docs/beta` for the website agent (not edited):**
- TC-37 describes a "greyed-out Reconnecting… button" at the bottom left. It doesn't exist.
- TC-38 expects no notification while the app is open.
- TC-41: with Location set to Never, Start Session is now refused with a message, so "Packets still goes up" no longer applies.
- TC-39 and TC-40 say "Tap Connect"; it's the pill now.
- TC-44 should mention that previously viewed areas inside the hosted region are blank offline too.

## 4. Checked and fine
- **Permission order:** location is asked at the first Start Session, notifications right after start, and resume re-checks without prompting.
- **"While Using" is enough:** background location and Bluetooth modes are set, and the blue indicator is expected.
- **Denied or off states:** Precise Location off, GPS denied and Location Services off are flagged or refused clearly. Bluetooth off or denied shows on the pill, and the dialog offers Open Settings.
- **Refusals and warnings:** the public channel is refused. Connecting to the base is warned about in four places.
- **Reconnect and resume:** reconnect progress is shown with a 30 s grace before alerting. A session resumed after a kill reconnects by itself, with a notice if it can't.
- **End Session:** confirmed. "Stop it" failures stay readable with Retry.
- **Deletes:** session deletes need selection plus a confirm, and the recording session or map can't be deleted. Erase is guarded and confirmed. Exports work per session, per map and as one zip.
- **Catching up after unlock:** charts keep 2 h of history and the counts are stream-backed.
- **Beacon wording:** clear, and beacon-off is kept apart from out-of-range.
- **Counts:** ping counts handle relayed and throttled pings correctly, including on the Live Activity.
- **Code quality:** mounted checks and timer disposal were consistent in the code read; no setState-after-dispose path found.

## 5. Field-day runbook

Before you leave, on Wi-Fi:
1. In iOS Settings → Mesh Analyzer, set Location to While Using with Precise ON, allow Notifications with sound and banners, and turn on Live Activities and Bluetooth.
2. Charge the phone and both radios. Turn off Low Power Mode if you can.
3. Keep the iOS text size at default or one step up.
4. Pan over the whole test area at the zooms you'll use in the app, then don't swipe the app away. Tiles are only kept in memory.
5. Run Radio Setup mobile-first, to avoid the US-region bug.
6. Create the coverage map standing at the base, or untick "use my position". Move the base with Menu → Set base location…, not by long-pressing.

First five minutes:
1. The pill should be green with the mobile radio's name, not "· Base".
2. Open Session and check the preset, "GPS: fix ±N m" and the map. Drag the sheet up to reach Start, and read any message under it.
3. Check the bar turns from "Waiting…" to "Hearing the base · N s ago" and Packets recorded goes up.
4. Lock the phone and check the Live Activity, then unlock.
5. If you start a second session, the Live map still shows the first one's dots.

Recovery:
- **"Radio link lost":** wait 30–60 s. Never tap Disconnect during a session, because it stops the retries. If it stays lost, power-cycle the mobile radio.
- **Red "Base not heard":** walk back towards the base and check its battery. "Beacon is off" means switch the base to the telemetry beacon when you're in Bluetooth range. The amber 8-hour warning means restart the base.
- **No banner with the app open:** expected in this build. Watch the bar, or lock the phone.
- **Start does nothing:** scroll the sheet to the bottom for the reason.
- **Blank map:** keep recording; the dots are saved.
- **Connect fails:** close the Meshtastic app. If iOS asks for a PIN, use the one on the radio's screen (123456 if it has none). If the radio was reset, forget it in iOS Bluetooth settings.
- **App killed:** recording stops and the Live Activity may show old values. Reopen the app; the session resumes.
- **End of day:** End Session, tap "Stop it" for the base beacon while you're in Bluetooth range of the base, then export.

Tests run (all passed): `connection_banner_test`, `session_panel_test`, `first_run_card_test`, `gps_status_test`, `create_map_dialog_test`, `widget_test`, `recording_ui_test`, `recording_reliability_test`.
