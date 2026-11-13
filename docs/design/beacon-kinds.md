# Beacon kinds: surviving the removal of Range Test

Status: design, 2026-10-18. Gated on the hardware spike in §1. Implementation is its own PR (protocol + schema).

## 0. Why

Meshurement's "Signal (base → you)" layer is the base radio running as a Meshtastic **Range Test sender**. Verified against the firmware repo on 2026-10-17:

- **Firmware 2.8 compiles Range Test out of every target.** PR meshtastic/firmware#11150 "Always exclude range test" (merged 2026-07-22 into `develop`) sets `-DMESHTASTIC_EXCLUDE_RANGETEST=1` in the global `[env] build_flags` and always sets `RANGETEST_CONFIG` (0x0010) in `DeviceMetadata.excluded_modules`. Issue #8438 closed 2026-09-03 by garthvh: "Range Test bugs and feature requests are not being worked on." Releases: v2.7.26 stable/latest (2026-06-24); v2.8.0 and v2.8.1 pre-release (2026-09-01, 2026-10-01).
- **2.7.26 already excludes Range Test on classic ESP32** (`variants/esp32/esp32.ini:18`, `variants/esp32/rak11200/platformio.ini:21`): T-Beam, Heltec V1/V2/V2.1/WSL, every T-LoRa, Station G1, Nano G1, M5Stack, RAK11200 and others. nRF52 (T1000-E, RAK4631, T-Echo) and ESP32-S3 (Heltec V3) have it. **2.7.26 does not set the `excluded_modules` bit** for it (`src/main.cpp` ~1086-1120 has no RANGETEST case), so on 2.7 the app cannot ask the radio.
- The 2.7 Range Test sender **auto-disables 8 h after boot** (`RangeTestModule.cpp:88-90`, `isWithinTimespanMs(started, 28800000)`), only sends while channel utilisation < 25%, sends with `hop_limit = 0` and payload `"seq %u"`.
- The config field `module_config.range_test` still round-trips through admin on 2.8, so `setModuleConfig(rangeTest)` succeeds and nothing is sent. Failure is silent: the app draws a dead zone.

## 1. Hardware spike (Andy, before the PR)

Goal: confirm a MeshTest-only base honours a short telemetry broadcast interval on 2.7.26 and 2.8.1, and that 2.8.1 reports Range Test as excluded.

1. Flash the spare Heltec V3 to **v2.8.1.8e6a88d** (web flasher, pre-release). Keep a T1000-E on 2.7.26.
2. Run today's Radio Setup against each as **base** (MeshTest only channel, chosen preset). This makes `channels.hasDefaultChannel()` false, which is what lifts the 30-minute telemetry floor (see §2).
3. Over USB with the Python CLI, on the base:
   ```
   meshtastic --set telemetry.device_telemetry_enabled true --set telemetry.device_update_interval 20
   meshtastic --get telemetry
   meshtastic --info          # 2.8.1: metadata.excluded_modules should include RANGETEST_CONFIG (0x10)
   ```
   Also note `metadata.firmware_version`.
4. On the phone, connect to the mobile radio and watch the packet log (or `meshtastic --listen` on a third radio / the mobile over USB) for 10 minutes. Expected: a TELEMETRY_APP packet from the base **about every 20 s** on both firmware versions. If instead it arrives every 30 min, the floor applied and §2's assumption is wrong (then fall back to Option A in §4).
5. On 2.8.1 confirm **no** RANGE_TEST_APP `seq` packets arrive even with Range Test enabled via admin. On 2.7.26 T1000-E confirm `seq` packets still arrive.
6. Bonus: leave the 2.8.1 base running overnight and confirm telemetry is still arriving in the morning (no auto-off).

Record results at the bottom of this file.

## 2. Firmware facts the design relies on (read from source, not yet run on hardware)

| Beacon candidate | 2.7.26 | 2.8.1 | Verdict |
|---|---|---|---|
| **Range Test** (`seq N`, hop_limit 0) | nRF52 + ESP32-S3 only; 8 h auto-off; util < 25% | compiled out everywhere | Use where present, never depend on it |
| **Position broadcast** | honours configured interval; fixed_position OK | `PositionModule::runOnce` applies a **6-hour floor** when `fixed_position` or stationary (`effectiveBroadcastIntervalMs`, `default_position_stationary_broadcast_secs = 6*60*60`) | **Dead on 2.8** for a base |
| **Device telemetry broadcast** | interval honoured unless `channels.hasDefaultChannel()`, then clamped to `min_default_telemetry_interval_secs` = 30 min (`NodeDB.cpp` ~336-339) | same clamp, same condition (`NodeDB.cpp` ~581-592); **requires `device_telemetry_enabled = true`** (opt-in since PR #10929); no auto-off in either version | **Primary beacon** |

Telemetry gates (both versions): `airTime->isTxAllowedChannelUtil(polite)` (25% for CLIENT roles), `isTxAllowedAirUtil()`, interval scaling only above 40 online nodes (`congestionScalingCoefficient`), and a per-region profile multiplier (`telemetryThrottle`: 1 for STD/EU868/NARROW, 10 for LITE regions, 2 for the ham 20 kHz profile).

`hasDefaultChannel()` is true only when `use_preset` is on, the default frequency slot is used, no override frequency, **and** some channel has the default name + PSK. Radio Setup's MeshTest-only channel set makes it false.

2.8 traffic management: position dedup only on `isWellKnownChannel` (public) channels, so it never touches MeshTest. The generic rate limiter (`rate_limit_window_secs`/`rate_limit_max_packets`) defaults were not checked; verify in the spike if telemetry arrives at the mobile less often than the base sends.

Telemetry payload bonus: every beacon carries the base's `battery_level`, `voltage`, `channel_utilization`, `air_util_tx`, `uptime_seconds`. Store channel_utilization per beacon sample: it is noise/busy context at the base end.

What telemetry lacks: a sequence number. Miss detection is by time gap against the known interval (and the base skips a send when its channel is busy, so misses are slightly over-counted; the base's own `air_util_tx` in the next packet helps).

Hop limit: the firmware replaces `hop_limit == 0` with the configured default for want_ack packets from the phone (`Router.cpp:274-276`), so pings cannot be sent with 0; use 1. Telemetry/Range Test from the base use the radio's lora `hop_limit`; set `rebroadcast_mode = LOCAL_ONLY` on both test radios so *they* never relay third parties, and keep the receive-side `hops > 0` filter.

## 3. Uplink: traceroute

Pings measure round-trip delivery only; the SNR stored with an ACK is measured by the mobile (base → you again). Real uplink dB comes from **TRACEROUTE_APP (70)**: `RouteDiscovery.snr_towards[0]` is the SNR the base heard the request at, `snr_back[0]` the return leg, both in quarter-dB (`/4.0`, `INT8_MIN` = unknown). No firmware-side rate limit found in `TraceRouteModule.cpp` 2.8.1; the official apps enforce 30 s client-side. Use ≥ 30 s, interleaved with pings. Works on 2.3+. This is PR 3, after the beacon PR.

## 4. Design

### Capabilities (read at connect)

```dart
class RadioCapabilities {
  final String firmwareVersion;      // DeviceMetadata.firmwareVersion
  final bool rangeTestExcluded;      // excluded_modules & 0x0010 (2.8+); false on 2.7 even when absent
  final bool hasTraceroute;          // firmware >= 2.3
}
```

`MeshtasticRadio` already stores `pb.DeviceMetadata? metadata` (`meshtastic_radio.dart:355, 689`). Expose it through `MeshRadio.capabilities` (protocol-neutral; MeshCore fills in its own).

### Beacon kind

```dart
enum BeaconKind { none, rangeTest, telemetry }   // position deliberately absent
class BeaconConfig { final BeaconKind kind; final int intervalSec; }
```

`TestProfile.beacon` becomes `BeaconConfig`. Selection in `applyTestProfile` for the **base**:

1. `rangeTestExcluded` → `telemetry`.
2. firmware ≥ 2.8 → `telemetry`.
3. otherwise → `rangeTest` (densest, has `seq`, hop_limit 0), **and** telemetry disabled, so only one beacon is on air.

Runtime override: if a session has been receiving ping ACKs from the base but no beacon packet for 3 × interval, the beacon is absent (classic ESP32 on 2.7, or the 8-hour auto-off). Show "Base is reachable but its beacon is off" with a one-tap "Switch base to telemetry beacon" (admin write of the telemetry config; requires BLE to the base, so usually offered at the next connect to the base) and never draw a dead zone from silence alone.

Option A (fallback if the spike shows the telemetry floor applies): keep Range Test where present and enable telemetry at the clamped interval as a liveness signal only; document that 2.8 bases get the ping-ACK downlink samples plus traceroute, and the independent beacon is lost.

### Admin writes (base)

In the existing beginEdit → … → commitEdit transaction:

- `ModuleConfig.telemetry.device_telemetry_enabled = (kind == telemetry)`, `device_update_interval = intervalSec` (default 30; 15 when "faster than recommended").
- `ModuleConfig.range_test = (kind == rangeTest) ? {enabled, sender: intervalSec} : {enabled: false}`.
- `Config.device.rebroadcast_mode = LOCAL_ONLY` on base and mobile (restore puts the original back).
- Mobile: telemetry broadcast off (it already sends own-node telemetry to the phone regardless; the app reads it for `RadioChannelStats`).

Backups (v2, see data-export-backups.md §3B) must include `ModuleConfig.telemetry` and `Config.device` so Restore returns the owner's original telemetry interval and rebroadcast mode.

### Packet processing

`PacketProcessor` today treats TELEMETRY_APP from **our own node** as `RadioChannelStats` before the own-node filter. Add: TELEMETRY_APP **from the session's base node**, hops == 0 → a beacon sample (`direction rx`, `source kind telemetry`), with `snr`/`rssi` from the packet and `baseChannelUtil` from the payload. RANGE_TEST_APP from the base → beacon sample `source kind rangeTest` with parsed `seq`.

Schema (one bump): `packet_events.seq INTEGER NULL`, `packet_events.source_kind TEXT` (`range_test | telemetry | position | ack | traceroute | passive`), `packet_events.base_channel_util REAL NULL`; `sessions.beacon_kind TEXT`, `sessions.beacon_interval_sec INTEGER`. CSV v2 appends `seq`, `source_kind`, `base_channel_util`.

Miss detection: for `rangeTest`, gaps in `seq`. For `telemetry`, a miss is synthesised when `now - lastBeacon > 1.5 × interval` while the BLE link is up and the session is recording; synthesised misses get a time-interpolated GPS position and `source_kind = telemetry_miss`. These feed the loss layer (PR 4), never the IDW.

### UI

- Radio Setup: no visible choice; the summary line reads "Base beacon: telemetry every 30 s" or "Base beacon: Range Test every 30 s". Default interval 30 s (official docs' guidance for LongFast); 15 s only with "faster than recommended".
- Session panel: "Beacons 41 heard · 3 missed" (seq) or "Beacons 41 heard · ~3 missed" (timing).
- Beacon-absent message as above, replacing the false out-of-range state.
- "Stop base beacon" at session end when the base is reachable; the "base in test mode since <date>" banner on connect.
- Firmware version on the radio sheet (PR 1 does this).

### App Store copy

"Meshtastic-compatible radios running firmware 2.5 or later" (PR 1). Remove any mention of Range Test from user-facing text; call it "the base beacon".

## 5. Spike results (2026-10-23, run from the Mac over USB)

Setup: base = Heltec V3 ("H1", Muzi Works case) first on **2.7.26.54e0d8d**, then fully erased and flashed to **2.8.1.8e6a88d**; listener = T1000-E "Procrastin8r A" on **2.7.15.567b8ea** (not 2.7.26). Both on the same private MeshTest channel (32-byte key, MEDIUM_SLOW, US), no default channel. Logs: `spike_listen.py` (packet, gap since last of that kind from that node).

| | 2.7.26 Heltec V3 | 2.8.1 Heltec V3 |
|---|---|---|
| Telemetry beacon arrives? | **Yes, every 60 s** (set 20 s); 4/4 at 60 s | **Yes, every 60 s** (set 20 s); 5/5 at 60 s |
| Needs `device_telemetry_enabled = true` | **Yes** (off by default; nothing sent until set) | Yes |
| 30-minute floor on a private channel | Not applied | Not applied |
| `excluded_modules` RANGETEST bit | n/a (not set) | **Set**: `excludedModules` 1296 = 0x510 |
| `seq` packets with Range Test enabled | **Yes**, every 30 s, payload exactly `seq N` | None; and the `range_test` config **does not persist** (writes accepted, reads back `enabled: false, sender: 0`) |
| Own telemetry to the client with broadcast off | 2.7.15 T1000-E: yes, device metrics every 60 s | Yes, every 60 s |
| Still beaconing after 12 h | (Range Test 8 h auto-off not re-tested) | ✅ telemetry every 60 s at 20 h 40 m uptime (no reboot), heard by the T1000-E 2026-10-24 10:11 |

Corrections to §0/§2 from this:
- **Device telemetry wakes once a minute** (`DeviceTelemetry.h` `sendToPhoneIntervalMs = 60 s`, `runOnce` returns it; same in 2.7.26 and 2.8.1). A telemetry beacon is at most every 60 s and otherwise on the next whole minute. Fixed on `feat/beacon-kinds` (59d6ca7): telemetry intervals are rounded up to whole minutes, minimum 60 s; Range Test keeps 15/30 s.
- **`device_telemetry_enabled` gates broadcast on 2.7.26 too** (`DeviceTelemetry.cpp:33` at the 2.7.26 tag), not only from 2.8. The PR already sets it for a telemetry beacon.
- **2.8.1 drops the `range_test` module config** rather than round-tripping it. Harmless: the app reads the `excluded_modules` bit.
- The protobuf comment on `device_telemetry_enabled` confirms metrics still go to the connected client every minute when broadcast is off, and the hardware agrees: the mobile's radio-measured airtime readout keeps working with the mobile's broadcast off.

Bench notes (not app issues):
- Opening the Heltec V3's USB serial port resets the board (CP2102 DTR/RTS). A config write followed within seconds by another serial connect is lost before the radio saves it. Write over one held-open connection and wait ~20 s. BLE (the app) is unaffected.
- The Meshtastic CLI needs Python ≤ 3.13 (on 3.15 pip only finds 2.3.11, which predates `device_telemetry_enabled`). `~/meshcli` is a 3.13 venv with CLI 2.7.11 and esptool.
- Andy's H1 and this T1000-E had different MeshTest keys and presets before the spike (H1 MEDIUM_SLOW, T1000-E LONG_MODERATE), so they were not a working pair. Original configs are saved in the session scratchpad.
