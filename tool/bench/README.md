# Meshurement bench (`tool/bench`)

Hardware-in-the-loop tests: two radios over USB, a phone over `devicectl`/`adb`,
or the iOS simulator with no radios. One command, one pass/fail report, and a
fastlane gate that reads the newest report before a TestFlight upload.
Design, phases and the scenario list: [docs/design/bench-rig/README.md](../../docs/design/bench-rig/README.md).

## Quickstart

```bash
cd tool/bench
uv sync                              # Python 3.13 venv (the Meshtastic API needs <= 3.13), pytest included
cp bench.toml.example bench.toml     # git-ignored: serial numbers, phone ids, report paths
uv run bench ports                   # what is plugged in (reads USB descriptors only, no side effects)
uv run bench prepare                 # Meshtastic radios: region + Bluetooth NO_PIN (reboots them)

# Phone (T2): a release build with the bench server compiled in
flutter build ios --release --dart-define=BENCH=true          # from the repo root
uv run bench install ../../build/ios/iphoneos/Runner.app
uv run bench launch -v               # -MeshBench; prints /state once the server answers
uv run bench run radio-setup -v      # or `bench run all`; writes a report

# Simulator (T1): the same bench without radios
flutter build ios --simulator --debug --dart-define=BENCH=true
uv run bench install ../../build/ios/iphonesimulator/Runner.app --phone sim
uv run bench run smoke --phone sim -v

uv run bench latest                  # what the release gate sees (bench_check)
uv run python -m pytest              # the bench's own tests, no hardware, < 10 s
```

## bench.toml

```toml
[bench]
reports_dir = "/Volumes/MiniSlo/develop/mesh-bench/reports"   # outside the repo
firmware_cache = "/Volumes/MiniSlo/develop/mesh-bench/firmware"
region = "US"

[radios.base]      # one table per radio; `bench ports` shows the serials
serial = "0001"
board = "heltec-v3"            # heltec-v3 | t1000-e | wio-tracker-l1
protocol = "meshtastic"        # what is flashed now; `bench flash` keeps flashed.json up to date
role = "base"

[radios.mobile]
serial = "24DC1A9C630B392E"
board = "t1000-e"
protocol = "meshtastic"
role = "mobile"

[phone]            # the default phone
platform = "ios"               # ios | android | ios-sim
id = "00008030-..."            # devicectl UDID / adb serial / simulator name

[phones.sim]       # more phones: `--phone sim`
platform = "ios-sim"
id = "iPhone 18 Pro Max"
```

`bench.toml` is never committed; `bench.toml.example` documents every key.

## Commands

| command | what |
|---|---|
| `bench ports` | USB serial ports with vendor/product guesses; flags a UF2 bootloader |
| `bench snapshot <radio> [--json]` | read a Meshtastic radio over USB (channels, lora, device, owner, security, modules) |
| `bench check <radio> --preset P --psk HEX` | snapshot + the Radio Setup checks for its role |
| `bench reboot <radio>` | reboot (a Heltec's Bluetooth comes back) |
| `bench prepare [radio…] [--mode NO_PIN]` | region + Bluetooth pairing mode on every Meshtastic radio |
| `bench firmware <meshtastic\|meshcore>` | downloadable releases, cached ones marked |
| `bench flash <radio> <protocol> <version>` | download (cached) + flash + prepare; `--dry-run` only downloads |
| `bench install <app> [--phone N]` | install Runner.app / .apk |
| `bench launch [--phone N] [-v]` | launch with the phone's bench arguments and print `/state` |
| `bench run <scenario\|all> [--phone N] [-o k=v] [-v] [--no-launch] [--ui]` | run scenarios, write a report; `--ui` opens the live view |
| `bench matrix [--dry-run] [--resume] [--unattended] [--ui]` | firmware matrix from `[matrix]` |
| `bench ui [report.json] [--seconds 45]` | replay a run report in the live view (no hardware) |
| `bench latest [--json] [--max-age-h N] [--commit SHA]` | the newest report judged as the gate does; exit 1 on any problem |

Scenarios (`bench/scenarios/`): `smoke` (bench server end to end, no radios;
the T1 scenario), `radio-setup` (Radio Setup base flow verified over USB on
both radios; first pass 2026-11-08, 31 checks). The rest of the design's §5
list comes next.

## Live view

`--ui` on `bench run` or `bench matrix` serves a page at
http://127.0.0.1:8770/ and opens it: the bench drawn like the beta site's
guides (the Mac, its USB cables, the phone on a stand, each radio with its
BASE / MOBILE sticker and firmware), animated as the run works, next to the
checklist ticking off.

| on the page | from |
|---|---|
| data running along a radio's cable | a serial session with it (`meshtastic.connect`) |
| orange spinner ring, fast orange data, new firmware label | `bench flash` / a matrix flash |
| blue dashed arc phone → radio | an app command that uses Bluetooth (scan, Radio Setup, connect, restore) and the app's `link` / `setup` events |
| orange rings and a packet between the radios, green rings for an answer | the app's `ping`, `beacon`, `remote` events |
| the phone's screen | the scenario, the current command or step, the Bluetooth pairing dialog |
| the checklist | `Context.check`; rows are pre-filled from the newest report that ran each scenario, matched by name with numbers and brackets ignored |
| PASSED / FAILED stamp | the end of the run (or of the matrix) |

The page is `bench/ui/index.html` (no build step, no libraries); the feed is
`bench/live.py`, an SSE stream at `/feed` that replays the run so far to a
page opened late. Every hook is a no-op without `--ui`. `--ui-port`,
`--no-browser`. The server stays up after the run (Ctrl-C quits). `bench ui`
replays a finished report in about 45 s with the same page (a report has
checks but no traffic, so the drawing guesses the traffic from check names);
"Play the replay again" restarts it.

## Tiers

| tier | needs | run with |
|---|---|---|
| T0 | Mac | `flutter test`, `uv run python -m pytest` |
| T1 | iOS simulator | `bench run smoke --phone sim` (bench + demo mode: pretend radio, demo DB, GPS from `gps.set`) |
| T2 | phone + 2 radios over USB | `bench run all` |
| T3 | same bench, firmware matrix | `bench flash …` per cell, then `bench run all` (`bench matrix` later) |

## Firmware and the matrix

`bench flash <radio> meshtastic 2.8.1` (or `latest`, `pre`, a full
`2.8.1.8e6a88d`) and `bench flash <radio> meshcore 1.18.0` download the GitHub
release into `firmware_cache/<protocol>/<version>/` (downloads are untrusted
data: nothing in there is executed on the Mac) and flash: ESP32 with esptool
(erase + factory image + OTA + littlefs at the `.mt.json` offsets), nRF52 with
adafruit-nrfutil serial DFU (1200-baud touch). `flashed.json` in the cache
records what each serial runs; `config.load` overlays it on `bench.toml`.
Which versions matter per release is the matrix question in the design (§6, §11).

## Hardware rules (learned the hard way)

- **Heltec V3 (ESP32): a serial API client turns Bluetooth off** until a
  reboot (`bench reboot base`, or a power cycle). The bench reads it once,
  caches the snapshot, and reboots it; never read it while the phone needs it.
  On nRF52 the phone's link only drops for a few seconds per serial connect.
- **Bluetooth `NO_PIN`** on every bench radio (`bench prepare`): with a PIN
  the first admin write fails ("Encryption is insufficient"). iOS still shows a
  confirm-only pairing alert once per radio; after that runs are hands-off.
- **An ESP32 flash erases its bonds**; iOS keeps its side and the next connect
  fails with "Peer removed pairing information": Settings → Bluetooth →
  Forget This Device on the phone, then rerun. nRF52 radios keep their bond
  across a serial DFU and can be reflashed unattended. Firmware 2.8 also purges
  ESP32 bonds on a 2.7 → 2.8 boot.
- **Bench phone: Auto-Lock Never** (Settings → Display & Brightness) and
  Developer Mode on; devicectl cannot launch an app on a locked phone.
- **Release builds only on a phone**: a Flutter debug build stalls when launched
  outside `flutter run` (iOS 14+ JIT). The simulator takes a debug build.
- Never `flutter install` (it wipes app data). Keep off a radio's USB port while
  the app is using it. Nothing goes on the public channel: `SessionManager`
  refuses a session when the primary key is 1 byte or shorter.

## Reports and the release gate

Every `bench run` writes `<started>-<commit>.json` + `.md` and overwrites
`latest.json` in `[bench].reports_dir` (outside the repo, by default on
MiniSlo). The report carries the commit (and whether the tree was dirty),
the phone, the tier (T1 simulator / T2 bench), the radios and every check.

`bench latest --json --max-age-h 48 --commit <HEAD>` judges it: a problem is a
failed scenario, a report older than the limit, a different commit, a T1
simulator run or no report at all. `fastlane bench_check` (ios/fastlane/
Fastfile) runs exactly that and prints the summary; it is the first step of
`fastlane beta`. By default problems are a **warning**; `BENCH_STRICT=1` makes
them fail the lane, `BENCH_MAX_AGE_H` changes the limit (default 48).

## Layout

```
bench/cli.py            the `bench` command
bench/config.py         bench.toml (+ flashed.json overlay)
bench/ports.py          USB serial ports, no side effects
bench/report.py         Report, latest(), evaluate() (the gate)
bench/app.py            AppLink: HTTP client for the app's bench server; Forward (iproxy/adb)
bench/firmware.py       GitHub releases, cache, esptool / nrfutil flashing
bench/radios/meshtastic.py   serial read-back, checks, Phase 1 stand-ins
bench/phones/{ios,android,simulator}.py
bench/scenarios/        smoke, radio_setup, … (see Scenarios)
bench/live.py           live view feed + page server (`--ui`, `bench ui`)
bench/ui/index.html     the live view page
tests/                  pytest, no hardware, no network
```

App side: `lib/bench/` (`BenchMode`, `BenchServer` on 127.0.0.1:8765,
`BenchLocationBackend`), compiled in only with `--dart-define=BENCH=true`.

## Scenario details (merged from the scenario branches)

```bash
uv run bench flash mobile meshtastic 2.7.26   # download (cached) + flash + region/NO_PIN
uv run bench matrix --dry-run        # [matrix] in bench.toml: what would be flashed, what reused
uv run bench matrix --resume         # flash per combo, run its scenarios, one matrix report
```

Reading a Meshtastic radio over USB turns an ESP32's Bluetooth off until a reboot
(`meshtastic.serial_session` / `read_then_reboot` is the one place that rule
lives; every command and scenario that reads a radio goes through it).

Phase 1 state (2026-11-08): read-back and checks for Meshtastic radios, the
serial stand-ins for the later hardware (`set_primary_psk`, `set_module_enabled`,
`reset_node_db`, `reboot` in `bench/radios/meshtastic.py`), phone control, the
bench server in the app (`lib/bench/bench_server.dart`, `-MeshBench`) and the
Phase 1 scenario set below.

## Scenarios (`bench run <name|all> [-o key=value] [-v]`)

`bench run all` runs them in this order; `radio-setup` first (it sets the roles
and the MeshTest channel everything else needs), `backups` last (it puts the
mobile back on its original settings). Every other scenario declares
`needs = ("radio-setup",)` and fails fast with one clear check when `/state`
shows no roles. Options are documented at the top of each module in
`bench/scenarios/`.

| scenario | what it proves | serial stand-in (Phase 1) |
|---|---|---|
| `radio-setup` | Radio Setup wrote both radios (read back over USB), 31 checks | — (passed on hardware 2026-11-08) |
| `public-channel-refusal` | the app refuses `session.start` on the public channel and starts once the key is back | mobile primary key → 1-byte default, then MeshTest |
| `recorded-session` | pings, beacon samples, out of range after 3 misses + reply timeout, re-entry after 2 answers, beacon absent/back, radio lost + auto-reconnect, DB counts | base key away/back, telemetry or range-test module off/on, mobile reboot |
| `pki-recovery` | received → `error:PKI_*` → received after the base forgets the mobile's key | base `reset_node_db` |
| `exports` | CSV v2 columns/rows and `maps.json` against `db.query` | — |
| `remote-base-change` | the mobile changes the base's preset from a distance (`setRemoteLora`), read back over USB, and back | — |
| `backups` | originals exist; "put back the way it was" verified over USB; **leaves the mobile un-set-up** | — |

Waits are computed from the session's own `ping_interval_sec` and the app's
rules (`bench/scenarios/common.py`: 30 s reply timeout, 3 × interval + reply
for out of range, 2 answers to re-enter, 3 beacon intervals to absent), plus the
serial write time and a 30 s margin. Every write to a Heltec base ends in
`mt.reboot` so its Bluetooth comes back.

**Not yet run on hardware:** everything but `radio-setup` was written 2026-11-08
against unit tests only (`tests/`, a simulated app and fake serial helpers).
First real runs will likely need timing tweaks.

## Tests

```bash
cd tool/bench
uv sync                              # once (adds pytest, the dev group)
uv run python -m pytest -q           # no hardware, < 1 s
```

The Dart side has `test/bench/*_test.dart` (the server's commands
and state against the fakes; part of `flutter test`).

`reset_node_db`, `reboot` in `bench/radios/meshtastic.py`). Phone control, the
bench server and scenarios come next.

## Phones

`bench.toml` lists phones as `[phones.<name>]` tables (a lone `[phone]` table
still works). `bench install`, `launch` and `run` take `--phone <name>` (or the
platform, `--phone android`); the default is the first phone listed.

```bash
# iOS (release build only; a debug build stalls outside `flutter run`)
flutter build ios --release --dart-define=BENCH=true
uv run bench install ../../build/ios/iphoneos/Runner.app --phone se
uv run bench run radio-setup -v --phone se

# Android (release, debug-signed without android/key.properties)
flutter build apk --release --dart-define=BENCH=true
uv run bench install ../../build/app/outputs/flutter-apk/app-release.apk --phone android
uv run bench launch --phone android          # /state through `adb forward tcp:8765`
uv run bench run radio-setup -v --phone android
```

Launch arguments reach Dart the same way on both: iOS gets them verbatim from
`devicectl process launch`; Android's `MainActivity` builds the same list from
Intent extras named like the flags (`--ez MeshBench true --ei benchPort 8765
--es demoScreen map`), which `bench/phones/android.py` emits. `adb install -g`
plus `pm grant` cover the runtime permissions (Nearby devices, location,
notifications); the Bluetooth pairing dialog is tapped by `accept_pairing()`
(`uiautomator dump` → Pair) while a scenario connects.

Tests: `uv run python -m pytest` (adb and devicectl are faked).
