# Bench rig: hardware-in-the-loop release tests

Status: ideation, 2026-11-07. Nothing built yet. Open questions in §11 decide the shape; §12 is the build order.

## 0. Goal

Andy plugs a phone (iPhone or Android) and two radios into the Mac, runs one command, and gets a pass/fail report that says the whole stack works on real hardware: BLE link, Radio Setup writing both radios, a recorded session with beacons and pings, out-of-range and radio-lost alerts, backups, guided test with a remote base change, exports and the field report. Optionally across several firmware versions. `fastlane beta`/`release` refuses to upload a build that has no fresh passing report.

What we have today (survey 2026-11-07): 1,118 pure-Dart unit and widget tests (1 min 22 s, green), fakes for the radio, the MeshCore transport, GPS and StoreKit, demo mode, and a screenshot XCUITest that asserts nothing. Nothing exercises BLE, GPS, background mode, Live Activity, firmware behaviour or the Android build automatically.

## 1. Test tiers

| Tier | Needs | Runs | Time | Catches |
|---|---|---|---|---|
| T0 unit | Mac | every commit (pre-commit hook or CI later) | ~1.5 min | logic, schema, parsers |
| T1 flows | iOS simulator / Android emulator | before every TestFlight | ~10 min | UI flows end to end in demo mode (no BLE) |
| T2 bench | phone + 2 radios + hub over USB | before every TestFlight, one command | ~20 min | BLE, Radio Setup, sessions, alerts, firmware behaviour on the pinned firmware |
| T3 matrix | same bench | nightly or on demand | 1–2 h | firmware versions, both protocols, both phones |

T2 is the one Andy asked for; T1 is its cheap sibling that reuses almost all of its Dart test code with the fake radio instead of the real one. T3 is T2 in a loop over a firmware list.

## 2. Bench hardware

```
 Mac ──USB──> hub (per-port power switching, uhubctl)
               ├── radio A  (Heltec V3, ESP32, Meshtastic)
               ├── radio B  (T1000-E or L1, nRF52, Meshtastic or MeshCore)
               ├── radio C  (optional observer: hears the test channel, never BLE)
               └── phone    (iPhone via devicectl, Android via adb)
 RF: radio A ──SMA──> step attenuator ──SMA──> radio B   (antennas off, 50 Ω)
```

- **Per-port power switching** solves two bench problems at once: a clean "radio lost" (cut the mobile's power, then restore it) and the Heltec's rule that Bluetooth stays off after a serial API client until a reboot (CLAUDE.md, Bench) — power-cycle it after every USB write. `uhubctl` lists supported hubs; a 4- to 7-port one is ~$30–60.
- **Cabled RF with an attenuator** replaces distance. A programmable step attenuator (0–90 dB, USB or GPIO, ~$100–300) lets the orchestrator script "the phone walks away": link margin falls, pings go from `received` to `timeout`, beacons go missing, the coverage map turns from green to red *in the right order*. Nothing goes on the air, which also keeps the bench off the public band. Without it, fixed SMA attenuators swapped by hand still give two or three repeatable points; the base in a metal tin is the zero-cost fallback.
- **Observer radio** (any spare node, USB API client, on the MeshTest channel): shows what was actually transmitted, independent of the app and of the two radios under test. Checks "pings are PRIVATE_APP DMs, never text", "nothing on the public channel", beacon kind and interval.
- **Phone**: a dedicated test device, not Andy's daily iPhone. The rig reinstalls and wipes the app (memory: `flutter install` wipes app data; the bench *wants* a wipe). The Galaxy A16 is the Android candidate; iOS needs an older iPhone or an agreement that the rig only touches a bench-only install.

## 3. Orchestrator (Mac, `tool/bench/`)

Python 3.13 (`uv`, because the Meshtastic CLI needs ≤ 3.13), one `bench` command with subcommands: `flash`, `prepare`, `run <scenario|all>`, `matrix`, `report`. Modules:

- `radios/meshtastic.py` – Meshtastic Python API over serial: factory reset, set region, read back channels/lora/device/owner/security after the app wrote them, `--enter-dfu`, node list clear, `excluded_modules`/firmware version read. Never hold the serial API open while the phone is using the radio (BLE off on ESP32, link drops on nRF52): connect, act, disconnect, power-cycle.
- `radios/meshcore.py` – `meshcore-cli`/`meshcore_py` against a **USB companion build**. Constraint: the MeshCore BLE companion build is silent on USB (memory: l1-on-meshcore), so a MeshCore radio is either the phone's (BLE build) or the Mac's (USB build), never both. The bench therefore runs the MeshCore base as the Mac's radio (the Mac is its companion app) and the mobile as the phone's; see §9 for what that leaves out.
- `radios/flash.py` – ESP32: `esptool` with the release's `firmware-update` image (or the release's `device-update.sh`); nRF52: `--enter-dfu` then copy the UF2 to the mounted volume (the "Device not configured" error is success). Downloads from GitHub releases (meshtastic/firmware, meshcore-dev/MeshCore), cached on MiniSlo. Verifies the version over serial after boot.
- `rf/attenuator.py` – set dB; `NullAttenuator` when there is none (scenarios then skip their RF steps and say so).
- `hub.py` – `uhubctl` power on/off per port, with a port map in `bench.toml`.
- `phones/ios.py` – `xcrun devicectl device install app`, `… process launch --device … com.andybrunker.meshAnalyzer -MeshBench -benchServer http://<mac>:<port>` (devicectl passes launch arguments and `-e` environment, checked 2026-11-07), `… copy from … appDataContainer` to pull `diag.log`, `mesh_analyzer.sqlite` and the preferences plist after the run. Lock screen: not available from devicectl; §10.
- `phones/android.py` – `adb install -r`, `adb shell am start … --es benchServer …`, `adb shell appops set … android:mock_location allow` if we ever use a system mock provider (we don't need to, §4), `adb shell input keyevent 26` to lock, `adb pull`/`run-as` for app data, `adb logcat` for the diag log.
- `server.py` – a small HTTP server the app's bench mode talks to (§4). It hands out the scenario script, receives progress events, and executes the Mac-side steps the script asks for ("attenuate 40", "power-cycle mobile", "clear base node list", "observer: expect a DM within 10 s").
- `report.py` – one JSON + Markdown report per run: app build, commit, phone, firmware versions, per-scenario pass/fail with timings and the assertions that failed, links to the pulled diag.log/sqlite and the field report PNG. Reports live outside the repo (`/Volumes/MiniSlo/develop/mesh-bench/reports/`), the latest one is what the fastlane gate reads.

## 4. App side: bench mode

A third launch mode next to real and `-MeshDemo`: `-MeshBench`. Real BLE, real radios, real DB (a separate `mesh_analyzer_bench.sqlite`), but:

- **GPS from a script.** `GpsService` already sits on a backend seam (`test/fakes/fake_location_backend.dart`). Bench mode installs a `ScriptedLocationBackend` that replays a track the server provides, stepping in time with the attenuator so position and signal agree. No system mock location, same code on both platforms. Background mode is still requested so the iOS blue bar / Android foreground service path is real.
- **A bench client** (`lib/bench/bench_client.dart`, compiled in only with `--dart-define=BENCH=true`, like `PRO_OVERRIDE`): long-polls the server for the next step, posts events (connected, session started, ping outcome, alert fired) and answers queries (DB counts, provider state). This is what makes a Mac-side script able to say "wait until the app has 5 beacon samples, then raise attenuation".
- **Deterministic settings**: ping interval 10 s, beacon 10 s, out-of-range window at its floor, notifications allowed. The server writes them through the client before each scenario.
- **Driving the UI.** Two options, decided in §11:
  1. *In-process `integration_test`* (`integration_test/bench/*_test.dart`, run with `flutter test integration_test -d <device> --dart-define=BENCH=true`): taps widgets, asserts on the DB, and talks to the server. Real plugins, real BLE. Cannot tap system dialogs (Bluetooth pairing PIN, notification permission).
  2. *Patrol*: same Dart test API plus native automation (XCUITest/UiAutomator) for the pairing prompt and permission sheets. Adds a dev dependency and a native test target per platform.
  Either way the same tests run on the simulator in demo mode (T1) by swapping the radio for `FakeMeshRadio`; only the bench steps are skipped there.
- **Pairing.** First-pair prompts are the one thing the app can't dismiss. Mitigations in order: radios set to `bluetooth.mode = NO_PIN` during `prepare` (Meshtastic; MeshCore's companion pin is also settable), a one-time manual pair the rig then relies on (iOS keeps the bond across app reinstalls, maybe not across firmware flashes; to verify), Patrol as the fallback. *Seen 2026-11-08 on the SE (iOS 17.5.1):* with RANDOM_PIN the first admin write failed with `Encryption is insufficient (apple-code 15)`; with NO_PIN iOS still puts up a confirm-only pairing alert once per radio (the app logged `[app] inactive` 1 s after connecting and the `beginEditSettings` ACK timed out while the alert waited). Once confirmed, runs are hands-off. *Android* (2026-11-08): a stale bond (radio reflashed) fails every connect with `Encryption failure 6` in logcat and `requestMtu, device is disconnected` in the app; `ble.removeBond` drops the phone's side and the scenario re-pairs, tapping the dialog through `uiautomator` (§10.7).

## 5. Scenario list ("complete functionality test")

Each is a Dart test file plus the Mac-side steps it asks for. ✔ = only hardware can prove it.

1. **Fresh install & connect** – wipe, launch, welcome flow, Settings → Radios → connect the mobile. Assert: link ready, own node saved to `MeshtasticContacts`, `LastRadio`, `RadioRoles` learns the Bluetooth id. ✔
2. **Radio Setup, base flow** – connected radio = base, then `switchToAndApplyMobile`. Assert over USB on both radios after the reboot: MeshTest is the only enabled channel with the same 32-byte PSK, chosen preset, `CLIENT`/`LOCAL_ONLY`, owner names, telemetry/range-test module config, base `security.admin_key` holds the mobile's key. ✔ The strongest single assertion the rig can give; today this is checked by eye.
3. **Public channel refusal** – `prepare` leaves the base on LongFast; start session must refuse with the `onPublicChannel` message. Then Radio Setup, then it starts.
4. **Recorded session** (the centrepiece, ~6 min) – create map, start session, scripted walk away and back while the attenuator ramps 0 → 60 → 0 dB. Assert: beacon samples arrive at the interval (kind chosen by firmware: telemetry on 2.8, Range Test on 2.7.x with the module), `telemetry_miss` rows appear when the link is gone, ping outcomes go `received` → `timeout` → `received`, out-of-range fires after exactly the window (three misses), re-entry needs two answers, no flapping; coverage layer ordering green near / red far; radio channel stats present; session stores preset/protocol/radio settings; `OutOfRangeMonitor` notification posted (Android: read via `adb shell dumpsys notification`; iOS: the app reports it through the client). ✔
5. **Radio lost** – hub cuts the mobile's power mid-session; assert `radioLost` state and alert, then restore power and assert auto-reconnect with backoff and the session continuing. ✔
6. **PKI recovery** – over USB, clear the mobile's node list; next ping yields a local `PKI_SEND_FAIL_PUBLIC_KEY` NAK; assert `ensureContact` re-adds the base and the following ping is `received`. Then the mirror case on the base (`PKI_UNKNOWN_PUBKEY`). ✔ Firmware ≥ 2.7.19 only; skipped and reported on older.
7. **Backups** – original backup exists after setup; change something; "Put this radio back the way it was"; assert over USB the radio matches the original (role, relaying, owner). Import a `.mabackup` file pushed to the phone. ✔
8. **Guided test with remote base change** – antennas/range-settings plan, `changeRadios` step: assert over USB (after the base reboots) that the base's LoRa config changed, that the mobile followed, the 120 s listen, and the roll-back path when the observer radio is told to stay silent. ✔ "Not yet tried on hardware" in CLAUDE.md; the rig makes it a regression test.
9. **Observer checks** – throughout: pings are `PRIVATE_APP` with `want_ack`, nothing on the public channel, beacon kind and interval as configured, no text messages. ✔
10. **Export & report** – CSV v2 columns, maps.json, Field Report PNG renders and the PNG is pulled into the report.
11. **Pro gates** – with `TESTFLIGHT_PRO` off, the Pro features show the paywall; with it on they open. StoreKit purchase itself stays a unit test plus a manual sandbox check (§10).
12. **MeshCore pair** – flows 1, 3, 4, 5, 7, 10 on the L1/T1000-E: trace pings with `uplinkSnr`, `beacon_kind = 'trace'`, Radio Setup writing `SET_CHANNEL`/`SET_RADIO_PARAMS`, `MeshCoreBackup` restore. Verified from the app's side, not over USB (§5.1): `radio-setup-meshcore` and `meshcore-session` written 2026-11-08, not yet run on hardware. ✔
13. **Background** – Android: lock the phone during flow 4 and assert the session kept recording. iOS: see §10.

### 5.1 MeshCore: verified from the app's side, not over USB

A MeshCore `companion_radio_ble` build is silent on its USB serial port (the companion protocol runs over BLE only; memory: l1-on-meshcore), so the Mac cannot read a MeshCore radio back the way `radios/meshtastic.py` reads a Meshtastic one. Scenario 12 therefore gets its truth from the radio over BLE, through the app, and the §9 choice is made: accept the app's own read-back rather than reflash the base to the USB build after every run.

What the bench reads (bench-server commands, `lib/bench/bench_server.dart`):

- `radio.snapshot` – the connected radio's settings, either protocol, as the radio reported them after the write: for MeshCore the `MeshCoreSettings` (advert name, TX power, frequency / bandwidth / SF / CR, client-repeat flag from DEVICE_INFO, every channel slot with its 16-byte secret as hex) plus the ladder id; for Meshtastic channels / LoRa / owner / device / telemetry / Range Test / admin keys. Built from the same read a radio backup uses, so a check sees exactly what Restore would write back.
- `radio.settings` – the MeshCore settings alone (refuses on a Meshtastic radio).
- `backups.list` – the `.mabackup` files on the phone (node, protocol, `original`, reason, times).
- The Radio Setup commands take a MeshCore ladder id as `preset` (`MC_SF7_BW62.5_CR5`), plus `frequencyMHz` / `txPowerDbm`; the frequency defaults like the screen (the base's recorded test frequency for the mobile, else the connected radio's band's client-repeat frequency).

Scenarios (`tool/bench/bench/scenarios/`):

- **`radio-setup-meshcore`** – scan, pick the two MeshCore devices (remembered role ids → `base_name`/`mobile_name` options → the role word in a renamed advert name → the only two, in scan order), `radio.setupBase` (ladder modulation, repeat on, 918.000 MHz: the firmware relays only on 433.000 / 869.495 / 918.000), `radio.switchToAndApplyMobile`, then read the mobile back, connect to the base and read it back, check both originals in `backups.list`, reconnect the mobile. Checks per radio: one MeshTest slot (never 0) whose secret is the first 16 bytes of the phone's `test_channel_psk`, the requested modulation, the frequency, repeat on (base) / off (mobile), the names, not on a community setting. Skips without a MeshCore pair in `bench.toml`.
- **`meshcore-session`** – on the set-up pair: map, scripted GPS, a session with pings every 10 s (the trace beacon is put in the prefs when Radio Setup left it off, because `startSession` throws `SessionProbeOffError` with both off), wait for a few trace outcomes, check `received` ones carry downlink SNR, RSSI and the base's uplink SNR (events and `packet_events.uplink_snr`), none are `implicit`/`throttled`, the session row says `protocol = meshcore`, `beacon_kind = trace`, then end.

What this proves: the companion accepted and now reports the settings the app asked for, the two radios hear each other on the test frequency, and the app's own pipeline (trace → `PingOutcome` → DB) works on real MeshCore firmware. What stays unverifiable without a second observer (a MeshCore radio on the USB companion build, or an SDR, listening on the test channel): that the base actually transmits nothing on its own, that the trace frames carry the expected flags and hashes, the on-air airtime, and that nothing goes out on the community frequency. A read-back also cannot catch firmware that reports a setting it did not apply; the session scenario's `received` outcomes are the indirect check for the frequency and modulation (a mismatch hears nothing). Nothing in §5.1 has run on hardware yet (written 2026-11-08, unit-tested against the scripted companion only).

## 6. Firmware matrix (T3)

`bench.toml` lists firmware per radio, e.g. Heltec: 2.7.19, 2.7.26, 2.8.1, latest beta; nRF52 Meshtastic: same; MeshCore companion: 1.18.0, latest. `bench matrix` flashes, verifies the version, runs the T2 scenario set and files one report per cell. Expected per-version differences are data, not failures: Range Test present/absent → beacon kind, `excluded_modules`, telemetry forced off on upgrade (memory: firmware-2-8), local vs remote PKI NAK. A cell is red only when the app's *behaviour* is wrong for that firmware, so each scenario states its expectation as a function of the reported version. Cross-protocol flashes (Meshtastic ↔ MeshCore on nRF52) work with the UF2 recipe already in memory; the ESP32 Heltec stays Meshtastic unless we add a MeshCore ESP32 image.

Cost: flash + boot + `prepare` ≈ 2–3 min per radio, scenario set ≈ 20 min, so a 4-version Meshtastic column is about 1.5 h. Nightly, not per build.

## 7. Release gate

`fastlane beta`/`release` gets a `bench_check` step beside `flutter analyze`/`flutter test`: the latest report must be for the current commit (or an ancestor within N commits, configurable), on the pinned firmware set, with no failed scenario, and younger than 24 h. Otherwise the lane stops with "run `bench run all` first" unless `SKIP_BENCH=1` is set deliberately. The report's path and hash go into the TestFlight changelog so a build can be traced to its bench run.

## 8. T1 on the simulator (free side effect)

The same `integration_test` files run on the iOS simulator and Android emulator with `-MeshDemo`-style fakes (`FakeMeshRadio`, `FakeLocationBackend`, a `NoopBenchServer`). Covers the UI flows the unit tests don't: welcome → checklist → map → session → end → field report, settings, backups UI, guided flow with `DemoPlanRunner`. Runs in ~10 min, needs no hardware, and could go to GitHub Actions later (private repo, free minutes; Andy's call, costs nothing until a macOS runner is used for the iOS half).

## 9. Known holes the rig will not close

- **MeshCore Radio Setup base flow** needs BLE to the base, but a BLE-companion base is invisible to the Mac. Decided 2026-11-08 (§5.1): verify the base through the app's own read-back (`radio.snapshot` over a second BLE connection) and accept it; flashing the base to the USB build after the flow stays an option for the matrix (adds ~2 min, loses the bond).
- **iOS lock screen / Live Activity** can't be driven from devicectl. Live Activity stays a manual check; the Dart side (`LiveActivityService`) can at least assert the method-channel calls happened via the bench client.
- **StoreKit purchase** on a real device needs a sandbox Apple ID and Apple's sheets; not worth automating. Keep the fake-gateway unit tests and a manual checklist item in the report.
- **Real RF propagation** (terrain, antennas) is what the attenuator replaces; the rig proves the pipeline, not the field.

## 10. Spikes before committing to the design

Each is an hour or two on the bench and may change §3–4:

1. Does a plain serial *log* reader on the Heltec also turn Bluetooth off, or only an API client? (Decides whether the observer-style passive monitoring of the radios under test is possible.)
2. Does an iOS Bluetooth bond survive a Meshtastic reflash on the Heltec and on the T1000-E? And does `bluetooth.mode = NO_PIN` remove the prompt entirely on iOS 26? *Answered 2026-11-08 (iOS 17.5.1):* NO_PIN is required (a PIN mode breaks the first admin write) but does not remove the one-time confirm alert; see §4 Pairing. Bonds: the **nRF52** keeps its bond across a serial DFU (the T1000-E reconnected straight after `bench flash mobile meshtastic 2.7.26`); the **ESP32** loses it with the erase (`apple-code 14 | Peer removed pairing information` on the next connect) and iOS offers no API to drop its side, so a Heltec flash costs one manual Settings → Bluetooth → Forget This Device on the phone. Firmware 2.8 also purges ESP32 bonds on a 2.7 → 2.8 boot. For the matrix this means: nRF52 radios can be reflashed unattended; an ESP32 reflash is a semi-attended step (or the base in the matrix is an nRF52 board).
3. ~~`xcrun devicectl … process launch` with `-MeshBench`: do the arguments reach `AppDelegate`'s method channel the same way `-MeshDemo` does from XCUITest?~~ **Done 2026-11-08** on the iPhone SE (iOS 17.5.1): yes — a release build launched with `-MeshDemo -demoScreen map` created `mesh_analyzer_demo.sqlite` with the Cove sessions. Two findings: (a) a *debug* build stalls when launched outside `flutter run` (iOS 14+ JIT needs the tool's debugger), so bench launches use release/profile builds with `--dart-define`s; (b) the SE had to be registered in the team profile once via `xcodebuild -allowProvisioningDeviceRegistration` with the ASC API key. The app's `diag.log` is not written in demo mode; bench mode must write it.
4. Pick the attenuator: USB-programmable 0–90 dB vs a Raspberry Pi/ESP32 driving a PE4312-type module, vs none to start.
5. `meshcore-cli` from `uvx --python 3.13` against the L1 flashed with the USB companion build: can it read and set channels/radio params?
6. Patrol on a real iPhone with cloud-managed signing (the Runner target's signing is managed by fastlane); check the native test target builds without fighting the MeshActivity extension's embed phase.

7. **Android path** (2026-11-08, Galaxy A16 SM-A166U, Android 16, `bench/android` = `claude/auto-testing-bcd722` + `claude/android-prep-e8f640`). *Launch arguments*: one convention on both platforms, the iOS flag list; Android's `MainActivity.launchArgumentsOf` builds it from Intent extras named like the flags without the dash — a boolean extra is the bare flag, a string or int extra is the flag plus value, `--esa args` is appended verbatim: `am start -S -W -n com.plateaunerd.meshurement/.MainActivity --ez MeshBench true --ei benchPort 8765` (demo: `--ez MeshDemo true --es demoScreen map --es demoSite cove`). `BenchMode.parseArguments` is the pure Dart side (tested), `bench/phones/android.py::extras_for` the Python side (tested). *Build/install/launch*: `flutter build apk --release --dart-define=BENCH=true` (75 MB, debug-signed, 2 min) → `bench install … --phone android` (`adb install -r -g` + `pm grant` for BLUETOOTH_SCAN/CONNECT, fine/coarse location, POST_NOTIFICATIONS; no permission sheet ever appeared) → `bench launch --phone android`: `/state` answered through `adb forward tcp:8765 tcp:8765` **3.6 s after `am start`** (iOS: ~10 s). A debug APK would launch the same way (unlike iOS) but the bench keeps the release build; only `pull` (run-as) needs a debuggable one. *Radio Setup run* (`bench run radio-setup -v --phone android -o before=fresh`): USB read of both radios 34 s (Heltec reboot included), BLE scan 20 s found `BASE_3e9c`, `MOBL_d5b5` (and a `MeshCore-MeshTest Base` advertising from somewhere), then `radio.setupBase` **failed 5 s in**: `PlatformException(requestMtu, device is disconnected)`. logcat: the link came up, the stack tried to encrypt with the bond it still held for the Heltec and got `Encryption failure 6` (HCI key missing), so it dropped the link — the Heltec had been factory-flashed that day and lost its keys; the Android twin of iOS's "Peer removed pairing information". Unlike iOS, Android lets the app drop its side: `BleTransport.removeBond` (flutter_blue_plus `removeBond`, Android only) is now a bench command `ble.removeBond`, and the scenario retries a connect that fails like that once after dropping the bond (`_with_bond_retry`), with the pairing watch running so the fresh Just-Works pairing dialog gets tapped (`AndroidPhone.accept_pairing`: `uiautomator dump` → the clickable "Pair" in a Settings/Bluetooth package → `input tap`). *Pairing dialog*: not yet observed on the A16 — both radios were already bonded from the earlier Android walk, and the run that would have re-paired is pending (below). *Keep-awake*: bench mode now holds a wakelock (`main.dart`), because Android freezes a cached (backgrounded) app and with it the bench server; the iOS bench phone's Auto-Lock → Never is the same need. *Stopped by*: right after the failed run the A16's `adbd` stopped answering shell commands (`adb devices` still listed it; `adb kill-server` then left it **offline** for 15+ min; `adb reconnect`, `adb reconnect device`, `adb usb` did not help). About 1 h 45 later it came back as `unauthorized` (adbd restarted and wants the "Allow USB debugging" tap on its screen; the bench's `ready()` says so). The run with the fixes therefore has not happened; after the tap: `bench install build/app/outputs/flutter-apk/app-release.apk --phone android` (the APK with the fixes is built) and `bench run radio-setup -v --phone android` again. Candidate causes to check then: the `uiautomator dump` polling during the connect (a known way to wedge adbd on some Samsung builds), or the Heltec reboot on the same USB tree.

## 11. Decisions (Andy, 2026-11-07) and open questions

Decided:
- **Phones**: an iPhone SE (MX9E2LL/A, 2nd generation, A13, on iOS 17.5.1 as of 2026-11-08; Lock Screen Live Activities, no Dynamic Island) dedicated to the bench, plus the Galaxy A16 for Android. Bench-phone settings: Developer Mode on, Auto-Lock **Never** (devicectl cannot launch an app on a locked phone; the SE locked itself mid-run on 2026-11-08), the Meshtastic radios bonded once by hand (§4 Pairing).
- **Radios run both protocols.** The rig flashes every radio Meshtastic ↔ MeshCore as a scenario needs: Heltec V3 via esptool (MeshCore ships `Heltec_v3_companion_radio_{ble,usb}` images), T1000-E and L1 via the UF2 recipe. So the Meshtastic pair is Heltec + T1000-E (or L1) after a flash, and the MeshCore pair the same radios after another; `bench.toml`'s `protocol` is the *current* state, kept up to date by `bench flash`. Bonds: a reflash likely drops the iOS pairing, so the NO_PIN approach (§4) matters more.
- **Phases** as in §12: 1 without hub/attenuator, 2 hub, 3 attenuator.

Still open:

1. **Patrol vs plain `integration_test`**: Patrol handles pairing and permission sheets but adds a dependency and native targets; plain integration_test needs the NO_PIN/one-time-pair approach. Decide after spike §10.2.
2. **Scope of "complete"**: is §5 the list, and which three come first? Current pick: 2 (Radio Setup verified over USB), 4 (recorded session, serial stand-ins until Phase 3), 8 (remote base change).
3. **Matrix**: which firmware versions matter for the next release?
4. **Gate strictness**: hard refusal in `fastlane beta` without a fresh report, or a loud warning for the first weeks?

## 12. Phases (Andy, 2026-11-07)

**Phase 1 — no hub, no attenuator.** The Mac stands in for both over the radios' serial ports:

| Bench event | Phase 1 substitute (serial) | Phase 2/3 |
|---|---|---|
| phone walks out of range | change the *base's* channel PSK (pings time out, beacons stop); restore it for re-entry | attenuator ramp |
| base beacon off | disable the base's telemetry / Range Test module | same |
| radio lost | `meshtastic --reboot` on the *mobile* (BLE down ~30 s; on the Heltec the serial write already drops BLE until that reboot) | hub cuts the port |
| coverage ordering green → red | two or three fixed SMA pads swapped by hand, or skipped | attenuator |

Everything else in §5 (Radio Setup read-back, backups, PKI recovery, remote base change, exports, observer checks) needs neither device. The base's serial port never touches the phone ↔ mobile BLE link, so these are clean.

**Phase 2 — uhubctl hub** (Plugable USB3-HUB7BC, in uhubctl's table): real radio-lost by power, Heltec power-cycle after every serial write, unattended firmware flashing (power-cycle into a known state).

**Phase 3 — programmable attenuator**: used Mini-Circuits RUDAT-6000-30 (~$175 on eBay, USB, 0–30 dB in 0.25 dB steps) plus a fixed 30 dB pad in series; new RCDAT-6000-90 is ~$1,000, Adaura AD-USB1AR36G95 ~$550. Enables the §5.4 ramp and the matrix's RF assertions.

## 13. Build order

1. ~~`tool/bench/` skeleton: config, hub control, Meshtastic serial read-back, iOS/Android install + launch, report.~~ **Done 2026-11-08** except hub control (Phase 2); the Android launch path landed with `bench/android` on 2026-11-08 (§10.7). `bench prepare` today only sets Bluetooth NO_PIN; factory reset waits for `bench flash`.
2. ~~App: `-MeshBench` launch mode, scripted GPS backend, bench client behind `BENCH=true`.~~ **Done 2026-11-08** as an HTTP server *in the app* (`lib/bench/bench_server.dart`, loopback 127.0.0.1:8765, reached over USB via `iproxy` / `adb forward`), not a client polling a Mac server: no Wi-Fi, no local-network prompt, the Mac stays in charge. GPS: `BenchLocationBackend` + the `gps.set` command (a scripted track comes with scenario 4).
3. ~~Scenario 2 (Radio Setup) end to end, Heltec + T1000-E, current firmware. First real pass/fail report.~~ **Passed 2026-11-08 12:44** on the SE: 31 checks, 196 s, Heltec 2.8.1 base + T1000-E 2.7.26 mobile, MEDIUM_FAST (`bench run radio-setup -v`).
4. Scenario 4 with `NullAttenuator` (two fixed points by hand), then with the real attenuator. **Written 2026-11-08** as `recorded-session` with the Phase 1 serial stand-ins (§12), plus `public-channel-refusal` (3), `pki-recovery` (6, base side), `backups` (7), `exports` (10, data half); bench-server commands `radio.reconnect`, `beacon.state`, `backups.list`, `backups.restoreOriginal`, `export.session`, `export.mapsJson`, `export.all`, a `beacon` event and `/state.range` / `/state.beacon`; scenarios declare `needs = ("radio-setup",)`. Unit-tested only (Dart fakes, a Python simulation of the recording rules): **none of these has run on the bench yet.**
5. Scenarios 1, 5 (real power cut, Phase 2), 9; observer radio; Field Report PNG in `exports`; first hardware runs of the 2026-11-08 set.
6. ~~`bench_check` in fastlane (warning mode), T1 simulator run of the same tests.~~ **Done 2026-11-08**: `bench latest --json --max-age-h N --commit SHA` + `report.evaluate()`, Fastfile `bench_check` (warns; `BENCH_STRICT=1` fails) runs first in `beta`; `[phones.sim]` (`ios-sim`, `xcrun simctl`, `-MeshBench -MeshDemo`) and the radio-free `smoke` scenario passed on the iPhone 17 Pro Max simulator (24 checks, 29 s). The gate deliberately flags a T1 report as a problem: the gate is about hardware.
7. Scenario 8, 6, 13; **12 (MeshCore) written 2026-11-08** as `radio-setup-meshcore` + `meshcore-session`, verified through the app (`radio.snapshot`, `backups.list`; §5.1), hardware run pending; firmware matrix (`bench matrix` and the `remote-base-change` scenario written 2026-11-08 with unit tests, hardware run pending); gate to hard mode.

State at the end of 2026-11-08: everything in items 1–7 that says "written" exists with unit tests (pytest 181, Dart bench tests) and has not run on the bench. Hardware queue, in order: SE → Forget `BASE_3e9c` → `bench run all` on the SE (radio-setup first, then the new Meshtastic set); A16 → tap "Allow USB debugging" → `bench run radio-setup --phone android` (expects one stale-bond retry); `bench run radio-setup-meshcore meshcore-session` on the MeshCore pair; `bench matrix --dry-run`, then a 2-combo matrix.
