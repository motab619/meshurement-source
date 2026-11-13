# MeshCore support: protocol design

Status: implemented 2026-10-29 (`MeshCoreRadio`, services, UI on `field-build-oct23`); **first session over the air the same day** (L1 base at 918.000 MHz, T1000-E mobile, Fast, link checks every 10 s: 8/8 answered, SNR 12–14 dB, RSSI −39 to −74 dBm walking away). Reference for `lib/data/radio/meshcore/`. Every protocol fact is read from source and cited; two were corrected while implementing (marked **corrected**). Hardware checks in §10 are still open.

Citation keys (all line numbers are at these commits):

| Key | Repo | Commit | Notes |
|---|---|---|---|
| `fw` | meshcore-dev/MeshCore `main` | `81dbae5` (81dbae592ffad40b4212bc0b37e82b38da08f4bc, 2026-10-15) | = tags `companion-v1.18.0`, `repeater-v1.18.0`; `FIRMWARE_VER_CODE 14` |
| `MM` | `fw:examples/companion_radio/MyMesh.cpp` | `81dbae5` | companion command handler |
| `RM` | `fw:examples/simple_repeater/MyMesh.cpp` | `81dbae5` | repeater |
| `mo` | zjs81/meshcore-open `dev` | `caee4d5` | MIT, Dart |
| `mm` | DaveWoodCom/MeshMapper_Flutter_App `dev` | `bbd723b` | MIT, Dart |
| `api` | `https://api.meshcore.nz/api/v1/config` | fetched 2026-10-24 | official app preset list (`fw:docs/radio_presets.md`) |

All multi-byte integers below are **little-endian** (firmware `memcpy`s native values; every MeshCore MCU is LE). Offsets are from byte 0 = the code byte.

## 1. Sources, versions, licence

- Firmware read: companion and repeater v1.18.0 (`fw:examples/companion_radio/MyMesh.h:7-14`, `fw:examples/simple_repeater/MyMesh.h:70-77`). Companion protocol level = `FIRMWARE_VER_CODE` 14.
- In-repo protocol doc `fw:docs/companion_protocol.md` (same commit) mostly matches the code. Where it differs, this doc follows the code:
  - Doc lists `APP_START` then `DEVICE_QUERY` (`companion_protocol.md:75-76`). The code only learns the app's protocol version in `DEVICE_QUERY` (`MM:1056-1057`) and that version picks the V3 message frames that carry SNR (`MM:443`, `MM:561`). **Send `DEVICE_QUERY` first.**
  - Doc calls `0x88` "RF log data (can be ignored)" (`companion_protocol.md:668`). For us it is the main data source (§4, §7a).
  - Doc suggests MTU 512 (`companion_protocol.md:105`); ESP32 firmware caps it at 176 (§2).
- Reference apps disagree with the official list on at least one preset: `mo` has EU/UK (Narrow) as CR 4/5 (`mo:lib/models/radio_settings.dart:145-152`), `api` says CR 8. Use `api`.
- **Licence:** firmware is MIT, "Copyright (c) 2025 Scott Powell / rippleradios.com" (`fw:license.txt`). `mo` is MIT "(c) 2025 zjs81", `mm` is MIT "(c) 2026 MeshMapper". Implementing the wire protocol from scratch needs no notice. If we copy code or tables (e.g. a preset table, a parser), add that project's MIT notice to `NOTICE` and the About license page. MIT is GPL-3.0-compatible. Unverified: whether "MeshCore" has trademark terms; until checked, treat it like the other name (factual compatibility wording only, no branding).

## 2. Transport (BLE)

| Item | Value | Source |
|---|---|---|
| Service | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` (Nordic UART) | `fw:src/helpers/esp32/SerialBLEInterface.cpp:7` |
| App → radio (write) | `6E400002-…` "RX", write-with-response, needs encrypted+MITM link | `…SerialBLEInterface.cpp:8, 49-50` |
| Radio → app (notify) | `6E400003-…` "TX", read+notify, needs encrypted+MITM | `…SerialBLEInterface.cpp:9, 45-47` |
| Framing | **one complete frame per write and per notification**; no length prefix, no escaping | `…SerialBLEInterface.cpp:114-128` (onWrite queues each write as a frame), `:194-201` (one notify per queued frame); `companion_protocol.md:851-854` |
| Max frame | `MAX_FRAME_SIZE` = 176 bytes; longer writes are dropped | `fw:src/helpers/BaseSerialInterface.h:5`, `…SerialBLEInterface.cpp:119-120, 169` |
| MTU | ESP32 sets local MTU 176 → at most 173 bytes per ATT write/notify | `…SerialBLEInterface.cpp:29` |
| Radio → app pacing | queue of 4 frames, one notify per ≥ 60 ms; `writeFrame` **silently drops** when the queue is full | `fw:src/helpers/esp32/SerialBLEInterface.h:28`, `…SerialBLEInterface.cpp:168-201` |
| Advertised name | `"MeshCore-" + node name` | `fw:examples/companion_radio/MyMesh.h:66`, `main.cpp:209` |
| Pairing | static passkey, LE Secure Connections + MITM + bonding | `…SerialBLEInterface.cpp:31-33` |
| PIN value | prefs `ble_pin` if set; else build flag `BLE_PIN_CODE` (123456). Boards with a display and the default 123456 (Heltec V3 BLE build) get a **random 6-digit PIN each boot**, shown on the OLED | `fw:examples/companion_radio/main.cpp:188-202`, `fw:variants/heltec_v3/platformio.ini:159-168` |
| Set PIN | `CMD_SET_DEVICE_PIN` (37): u32 0 (= back to default behaviour) or 100000-999999 | `MM:1839-1852` |

Notes for `BleTransport`:

- Our existing `BleTransport` fits as is: write with response (`ble_transport.dart` `write`, `withoutResponse: false`), one notification = one frame.
- **iOS pairing:** the first access to the encrypted characteristics makes iOS show its system passkey prompt; the app cannot supply the PIN (same as today). On a Heltec V3 the user reads it off the screen. After bonding, reconnects should not prompt (unverified, §10). Radio Setup should offer `CMD_SET_DEVICE_PIN` with a phone-generated PIN so a headless base keeps a known PIN.
- **Frames 174-176 bytes** (e.g. a `0x88` log of a 173-byte packet) may be truncated by the 173-byte ATT payload on ESP32 (unverified, §10). Parse defensively; drop frames whose inner packet fails to parse.
- On connect: discover service, enable notify on `6E400003`, then the handshake in §3. MeshCore sends nothing unsolicited until then (except pushes, which may arrive any time once connected).
- Command/response is one-at-a-time by response code (`companion_protocol.md:120-125`); responses carry no request id. Keep a single in-flight command per response type; pushes (`≥ 0x80`) can interleave at any time.

## 3. Connect handshake

| Step | Send | Expect | Notes |
|---|---|---|---|
| 1 | `CMD_DEVICE_QUERY` `[22, app_ver]` | `RESP_CODE_DEVICE_INFO` (13) | `app_ver` ≥ 3 gets V3 message frames with SNR (`MM:443, 561`). Send **3** (only `>= 3` is tested in this firmware; `mo` sends 4, `mm` sends 1 — `mo:lib/connector/meshcore_protocol.dart:371`, `mm:lib/services/meshcore/protocol_constants.dart:8`). Reply byte 1 = firmware's `FIRMWARE_VER_CODE` (14 on v1.18.0) → `RadioInfo.protocolVersion`. |
| 2 | `CMD_APP_START` `[1, app_ver, 0×6, "MeshAnalyzer"]` | `RESP_CODE_SELF_INFO` (5) | min length 8; name starts at byte 8 (`MM:1076-1081`). Resets any running contacts iterator (`MM:1083`). |
| 3 | `CMD_SET_DEVICE_TIME` `[6, u32 epoch]` | OK / ERR 6 if earlier than the radio clock | `MM:1287-1296`. Needed: contact `lastmod` and advert timestamps use the radio clock. |
| 4 | `CMD_GET_CONTACTS` `[4]` (opt. `u32 since`) | `CONTACTS_START` (2, u32 total) → `CONTACT` (3) ×n → `END_OF_CONTACTS` (4, u32 newest lastmod) | `MM:1238-1258`, iterator `MM:2392-2409` (one contact per loop when BLE not busy). Store `since` to resync incrementally. |
| 5 | `CMD_GET_CHANNEL` `[31, idx]` for idx 0..max-1 | `CHANNEL_INFO` (18) or ERR 2 | max = DEVICE_INFO byte 3 (40 on Heltec V3 BLE). Only needed to find/verify the test channel slot. |
| 6 | `CMD_SYNC_NEXT_MESSAGE` `[10]` repeat | message frame, or `NO_MORE_MESSAGES` (10) | Drains the offline queue (`MM:1415-1423`); also do this on every `PUSH_CODE_MSG_WAITING` (0x83). Queue holds only DMs/channel messages (`MM:467, 583, 627`), not packet logs. Mark these `ReceivedPacket.queued = true`. |
| 7 | `CMD_GET_STATS` `[56, 1]` (v8+) | `RESP_CODE_STATS` (24) | optional; seeds channel stats (§5). |

There is no "config complete" marker: the radio is ready when SELF_INFO is parsed, the contacts iterator has ended and the message queue is empty. `mo` retries APP_START every 3.5 s until SELF_INFO arrives (`mo:lib/connector/meshcore_connector.dart:4083-4097`); do the same (BLE writes can be lost right after bonding). No heartbeat is required by the firmware (unverified whether iOS idles the link; `companion_protocol.md:84` recommends auto-reconnect with backoff, which `MeshtasticRadio` already has).

### DEVICE_INFO (13), 82 bytes on v1.18.0 (`MM:1059-1075`)

| Off | Size | Field |
|---|---|---|
| 0 | 1 | 13 |
| 1 | 1 | `FIRMWARE_VER_CODE` (protocol level; 14) |
| 2 | 1 | `MAX_CONTACTS / 2` (v3+) |
| 3 | 1 | `MAX_GROUP_CHANNELS` (v3+) |
| 4 | 4 | BLE PIN from prefs (u32; 0 = not set) |
| 8 | 12 | build date, ASCII, zero-padded ("15 Oct 2026") |
| 20 | 40 | manufacturer/board name, zero-terminated → `RadioInfo.model` |
| 60 | 20 | firmware version string ("v1.18.0") → `firmwareVersion` |
| 80 | 1 | client repeat enabled (v9+) |
| 81 | 1 | path hash mode 0-2 (v10+): flood path entries are mode+1 bytes |

### SELF_INFO (5), 58 + name bytes (`MM:1084-1117`)

| Off | Size | Field | Units |
|---|---|---|---|
| 0 | 1 | 5 | |
| 1 | 1 | advert type (1 = chat/companion) | |
| 2 | 1 | TX power | dBm, int8 (range -9..max) |
| 3 | 1 | max TX power | dBm (22 on Heltec V3, `variants/heltec_v3/platformio.ini:20`) |
| 4 | 32 | public key (Ed25519) | node identity |
| 36 | 4 | advert latitude | int32 ×1e6 |
| 40 | 4 | advert longitude | int32 ×1e6 |
| 44 | 1 | multi_acks | |
| 45 | 1 | advert location policy (0 none, 1 share) | |
| 46 | 1 | telemetry modes: env<<4 \| loc<<2 \| base | |
| 47 | 1 | manual_add_contacts | |
| 48 | 4 | frequency | u32 **kHz** (MHz×1000) |
| 52 | 4 | bandwidth | u32 **Hz** (kHz×1000) |
| 56 | 1 | spreading factor | 5-12 |
| 57 | 1 | coding rate | 5-8 (= 4/5..4/8) |
| 58 | n | node name, UTF-8, no terminator | |

## 4. Codes and frame layouts we need

Codes: `MM:9-68` (commands), `MM:75-104` (responses), `MM:117-133` (pushes), `MM:135-140` (errors). Generic replies: `RESP_CODE_OK` `[0]`; `RESP_CODE_ERR` `[1, err]` with err 1 unsupported, 2 not found, 3 table full / send queue full, 4 bad state, 5 file IO, 6 illegal arg (`MM:153-163`).

`RESP_CODE_SENT` (6), 10 bytes, is the reply to every send that expects something back: `[6, flood?1:0, u32 tag_or_ack, u32 est_timeout_ms]` (`MM:1167-1171`, `1830-1834`).

Contact record (`RESP_CODE_CONTACT` 3, `PUSH_CODE_NEW_ADVERT` 0x8A, and the body of `CMD_ADD_UPDATE_CONTACT` 9), 148 bytes (`MM:171-192`, parse `MM:194-217`):

| Off | Size | Field |
|---|---|---|
| 0 | 1 | code |
| 1 | 32 | public key |
| 33 | 1 | type: 0 none, 1 chat, 2 repeater, 3 room, 4 sensor (`fw:src/helpers/AdvertDataHelpers.h:7-11`) |
| 34 | 1 | flags (bit0 favourite, bit1-3 telemetry perms, bit4 remote CLI; `fw:src/helpers/ContactInfo.h:29-33`) |
| 35 | 1 | out_path_len (encoded, §8; 0xFF = unknown → flood) |
| 36 | 64 | out_path |
| 100 | 32 | name, zero-padded |
| 132 | 4 | last advert timestamp (sender's clock) |
| 136 | 4 | lat int32 ×1e6 |
| 140 | 4 | lon int32 ×1e6 |
| 144 | 4 | lastmod (radio clock) |

| Code | Name | App → radio frame | Radio → app reply / push | Source |
|---|---|---|---|---|
| 22 | DEVICE_QUERY | `[22, app_ver]` | DEVICE_INFO (§3) | `MM:1056-1075` |
| 1 | APP_START | `[1, ver, 6×0, name…]` | SELF_INFO (§3) | `MM:1076-1117` |
| 11 | SET_RADIO_PARAMS | `[11, u32 freq_kHz, u32 bw_Hz, sf, cr, (repeat 0/1, v9+)]` 11-12 B | OK; ERR 6 if out of range (freq 150000-2500000, bw 7000-500000, sf 5-12, cr 5-8) or repeat=1 at a non-allowed frequency | `MM:1424-1459` |
| 12 | SET_RADIO_TX_POWER | `[12, int8 dBm]` | OK; ERR 6 outside -9..max | `MM:1460-1469` |
| 31 | GET_CHANNEL | `[31, idx]` | `CHANNEL_INFO [18, idx, name[32], secret[16]]` 50 B; ERR 2 | `MM:1752-1766` |
| 32 | SET_CHANNEL | `[32, idx, name[32], secret[16]]` **exactly 50 B** | OK; a 32-byte secret (66 B frame) → ERR 1 "not supported (yet)" | `MM:1767-1780` |
| 4 | GET_CONTACTS | `[4, (u32 since)]` | §3 step 4 | `MM:1238-1258` |
| 9 | ADD_UPDATE_CONTACT | contact record, code 9, ≥ 36 B (lat/lon/lastmod optional) | OK; ERR 3 table full | `MM:1328-1348` |
| 15 | REMOVE_CONTACT | `[15, pubkey[32]]` | OK / ERR 2 | `MM:1349-1358` |
| 2 | SEND_TXT_MSG | `[2, txt_type(0 plain), attempt, u32 ts, pubkey_prefix[6], text…]` | SENT (expected ACK crc + timeout); later `PUSH_CODE_SEND_CONFIRMED` | `MM:1132-1177` |
| 62 | SEND_CHANNEL_DATA | `[62, idx, path_len (0 = zero-hop, 0xFF = flood), path…, u16 data_type, payload ≤165]` | OK | `MM:1198-1237` |
| 25 | SEND_RAW_DATA | `[25, path_len, path…, payload ≥4]` direct only (0xFF → ERR 1) | OK | `MM:1557-1576` |
| 36 | SEND_TRACE_PATH | `[36, u32 tag, u32 auth, flags, hashes…]`; flags bits0-1 = path_sz (hash = 1<<path_sz bytes, v1.11+); hash bytes a multiple of that; ≥1 byte | SENT `[6, 0, tag, est_timeout]`; later `PUSH_CODE_TRACE_DATA` | `MM:1813-1838` |
| 27 | SEND_STATUS_REQ | `[27, pubkey[32]]` | SENT; later `PUSH_CODE_STATUS_RESPONSE` (repeater needs a prior login, §7c) | `MM:1630-1650` |
| 26 | SEND_LOGIN | `[26, pubkey[32], password…]` | SENT; later 0x85 / 0x86 | `MM:1577-1598` |
| 7 | SEND_SELF_ADVERT | `[7, (1 = flood, else zero-hop)]` | OK | `MM:1297-1316` |
| 8 | SET_ADVERT_NAME | `[8, name…]` | OK | `MM:1259-1265` |
| 10 | SYNC_NEXT_MESSAGE | `[10]` | message frame / `[10]` none | `MM:1415-1423` |
| 56 | GET_STATS (v8+) | `[56, 1]` radio | `[24, 1, i16 noise_floor_dBm, int8 last_rssi, int8 last_snr×4, u32 tx_air_s, u32 rx_air_s]` 14 B | `MM:1928-1942` |
| 37 | SET_DEVICE_PIN | `[37, u32 pin]` | OK / ERR 6 | `MM:1839-1852` |
| 66 | RUN_CLI_COMMAND (v14) | `[66, text…]` | `[29, reply text…]` | `MM:1118-1131` |
| 0x88 | **PUSH LOG_RX_DATA** | — | `[0x88, int8 snr×4, int8 rssi, raw packet…]` for **every** LoRa frame received, before parsing, decryption or duplicate checks; only while the app is connected | `MM:291-302`, called from `fw:src/Dispatcher.cpp:196-199` |
| 0x89 | PUSH TRACE_DATA | — | `[0x89, 0, path_len (hash bytes), flags, u32 tag, u32 auth, hashes[path_len], snrs[path_len>>path_sz] (int8 ×4), int8 final_snr×4]` | `MM:855-886` |
| 0x82 | PUSH SEND_CONFIRMED | — | `[0x82, u32 ack_crc, u32 round_trip_ms]` | `MM:417-431` |
| 0x83 | PUSH MSG_WAITING | — | `[0x83]` → drain with SYNC_NEXT_MESSAGE | `MM:469-473` |
| 0x80 | PUSH ADVERT | — | `[0x80, pubkey[32]]` known contact re-advertised (no SNR) | `MM:363-365` |
| 0x8A | PUSH NEW_ADVERT | — | contact record (no SNR) | `MM:360-361` |
| 0x84 | PUSH RAW_DATA | — | `[0x84, snr×4, rssi, 0xFF, payload…]` zero-hop RAW_CUSTOM addressed to nobody | `MM:832-853`, `fw:src/Mesh.cpp:292-298` |
| 0x87 | PUSH STATUS_RESPONSE | — | `[0x87, 0, pubkey_prefix[6], status…]` (repeater: 56-byte `RepeaterStats`, `fw:examples/simple_repeater/MyMesh.h:44-60`) | `MM:724-738` |
| 16 | CONTACT_MSG_RECV_V3 | — | `[16, snr×4, 0, 0, prefix[6], path_len (0xFF = direct), txt_type, u32 ts, text…]` | `MM:440-466` |
| 17 | CHANNEL_MSG_RECV_V3 | — | `[17, snr×4, 0, 0, ch_idx, path_len, txt_type, u32 ts, text…]` | `MM:558-583` |
| 27 | CHANNEL_DATA_RECV | — | `[27, snr×4, 0, 0, ch_idx, path_len, u16 data_type, len, data…]` | `MM:601-627` |

Raw packet inside `0x88` (`fw:src/Packet.cpp:52-63`, header bits `fw:src/Packet.h:8-32`):

```
header (1)  bits0-1 route: 0 transport-flood, 1 flood, 2 direct, 3 transport-direct
            bits2-5 payload type: 0 REQ, 1 RESPONSE, 2 TXT_MSG, 3 ACK, 4 ADVERT, 5 GRP_TXT,
                    6 GRP_DATA, 7 ANON_REQ, 8 PATH, 9 TRACE, 0xA MULTIPART, 0xB CONTROL, 0xF RAW_CUSTOM
            bits6-7 version (0)
[transport codes (4)]  only for route 0 and 3
path_len (1)  bits0-5 hash count, bits6-7 hash size-1  (§8)
path (count × size)
payload
```

Payload starts we can parse without keys: ADVERT `pubkey[32], u32 ts, sig[64], app_data` with app_data `flags (type | 0x10 latlon | 0x20/0x40 extra | 0x80 name), [lat, lon int32 ×1e6], [u16], [u16], name` (`fw:src/Mesh.cpp:252-289`, `fw:src/helpers/AdvertDataHelpers.cpp:4-29`); REQ/RESPONSE/TXT_MSG/PATH `dest_hash(1), src_hash(1), mac+ciphertext` (`fw:src/Mesh.cpp:130-136`); TRACE `u32 tag, u32 auth, flags, hashes…` with per-hop SNRs in the path field (`fw:src/Mesh.cpp:42-61`).

## 5. MeshRadio mapping

| `MeshRadio` member | MeshCore | Fallback / note |
|---|---|---|
| `protocol` | `RadioProtocol.meshcore` | exists |
| `state`, `connectionState`, `connectProgress*` | BLE link + §3 steps ("Downloading contacts", n of `CONTACTS_START.total`) | `pairing` while iOS passkey prompt is up, as today |
| `connect` / `disconnect` / `descriptor` / `displayName` | `BleTransport(serviceUuid: 6E400001…, chars: [6E400002, 6E400003])`; name = SELF_INFO name, else BLE name | scan filter: NUS service UUID or name prefix `MeshCore-` |
| `isDemo` | demo radio | same pattern as today |
| `capabilities` | `firmwareVersion` = DEVICE_INFO string; `rangeTestExcluded` = true (MeshCore has none); `hasTraceroute` = true when `FIRMWARE_VER_CODE` known (path_sz traces need v1.11+, code level for that unverified) | **`selectBeaconKind` must not run for MeshCore**: it would return `telemetry`, which MeshCore doesn't have. See new fields below. |
| `queryDevice` | DEVICE_INFO → `RadioInfo(model: manufacturer, firmwareVersion, protocolVersion: FIRMWARE_VER_CODE)` | |
| `myNodeId` | first 4 bytes of own public key as u32 (big-endian, so it reads like the hex prefix the official apps show) | node identity is the 32-byte key; collisions at 4 bytes are negligible for our use |
| `nodes`, `nodeUpdates` | contacts (§3 step 4) + `0x8A` new adverts + adverts parsed from `0x88`. `RadioNode(num: key prefix, longName: name, shortName: first 4 hex of key, hwModel: '' , lat/lon, hopsAway: out_path_len count or null if 0xFF, lastHeard: lastmod)` | no hardware model in MeshCore adverts → `hwModel` empty; node type (repeater/chat) needs a field |
| `currentPreset` | SELF_INFO sf/bw/cr → matching `MeshCorePresets` row (§6) else `RadioPreset.custom` | |
| `regionFrequencyMHz` | SELF_INFO frequency / 1000, snapped to the matching community preset's frequency when within 1 kHz | **corrected:** SELF_INFO carries `(uint32)(freq_MHz × 1000)`, truncated (`MM:1105`), so 869.618 reads back as 869617 kHz. Match presets with ±1 kHz and write the preset's exact value back. |
| `regionName` | title of the matching preset ("USA", "EU/UK (Narrow)") else "" | display only |
| `primaryChannelName` | name of the test channel slot if present, else "" | MeshCore channels carry only group messages (§6) |
| `onPublicChannel` | **true when radio params equal a community preset** (§6 table) | reinterpretation: our test traffic never rides a channel, so "public" means "on the community mesh's frequency/modulation". Sessions refuse then, same policy. |
| `packets` | one `ReceivedPacket` per `0x88` frame (§7a), `from` = sender when knowable (§8), `type` by payload type, `snr` = byte1/4, `rssi` = byte2 (unwrap, §9), `packetId` = first 4 bytes of the packet hash (**corrected:** SHA-256 of the payload type byte, then for TRACE packets only the `path_len` byte, then the payload, `fw:src/Packet.cpp:41-50`), `rxTime` = phone clock | there is no radio packet id and no RX timestamp; `0x88` is never queued, so stale replays only come from the message queue |
| `txAirtimeStream` | our own LoRa time-on-air estimate per send (we know every frame length) | same as today |
| `channelStats` / `lastChannelStats` | poll `GET_STATS` radio (v8+) every 60 s: `airUtilTxPercent` = Δtx_air_s over a rolling hour, `channelUtilizationPercent` = Δrx_air_s / Δt over the last minute | rx_air counts only decoded packets (`fw:src/Dispatcher.cpp:204-209`), so it under-reads channel busy vs the other protocol's figure. The CLAUDE.md note "MeshCore may never report" is too pessimistic. |
| `prepareToPing` | trace ping: nothing (no keys needed). DM fallback: `ADD_UPDATE_CONTACT` both ways (Radio Setup does it) | |
| `ping` | **trace** (§7c): `pingId` = random u32 tag; `beforeSend(tag)`; send `SEND_TRACE_PATH`; outcome on `0x89` with that tag | `received` on trace return; `timeout` after `max(est_timeout × 2, 5 s)` (tune on hardware); `error:<ERR name>` on RESP_CODE_ERR. MeshCore never NAKs for duty cycle: its airtime budget **delays** sends (`fw:src/Dispatcher.cpp:92-106`), so `throttled` never occurs; `implicit` never occurs either. |
| `applyTestProfile` | §6 sequence, no reboot | returns `BeaconConfig(kind: trace…)` for a base, see below |
| `setBeacon` | no radio-side beacon exists (§7b) | trace beacons are scheduled by the app on the mobile; `setBeacon` on a MeshCore base returns `BeaconConfig.off()` |
| `dispose` | | |

Neutral types that need new **optional** fields (do not edit them in the codec PR; list only):

| Type | Field | Why |
|---|---|---|
| `PingOutcome` | `double? uplinkSnr` (and `int? uplinkRssi`) | trace gives the SNR the base heard us at; the other protocol's traceroute (`beacon-kinds.md` §3) can fill it too |
| `ReceivedPacket` | `bool? routeDirect`, `int? lastHopId` | direct packets don't say how far they came; flood packets name the last relay; dot sizing needs "heard from the sender itself" vs "relayed" |
| `ReceivedPacket` | `int? hops` nullable, or keep `hops` and add `hopsKnown` | direct packets: travelled hops unknown |
| `RadioNode` | `Uint8List? publicKey`, `String? nodeKind` (chat/repeater/room/sensor) | identity is a key; repeaters are what coverage maps care about |
| `BeaconKind` | `trace` (app-scheduled trace from the mobile) | the base sends nothing on its own (§7b); `selectBeaconKind` needs a protocol check |
| `RadioCapabilities` | `bool canRelay` (repeat on / repeater firmware), `int? pathHashBytes`, `int? protocolLevel` | trace needs a relaying base; hash width affects path parsing |
| `TestProfile` | `double? frequencyMHz`, `int? txPowerDbm`, `bool baseRelays` | MeshCore has no region→frequency table; client repeat is only allowed on fixed frequencies (§6) |
| `TestProfile.channelKey` | document "first 16 bytes used on MeshCore" | `SET_CHANNEL` accepts 16-byte secrets only |
| `RadioPreset` | `double? frequencyMHz` (optional) | MeshCore "presets" are full parameter sets including frequency |
| `PacketType` (`utils/constants.dart`) | `advert`, `trace`, `group`, `direct`, `raw` | new packet kinds for logs/filters |

## 6. Radio params, presets, test profile

MeshCore has no named modem presets. Firmware default (no app): 869.618 MHz / BW 62.5 / SF 8 / CR 5 (`fw:platformio.ini:29-31`, `fw:examples/companion_radio/MyMesh.h:48`). The official apps fetch suggestions from `api` (`fw:docs/radio_presets.md`). Current list (2026-10-24):

| Title | MHz | BW kHz | SF | CR | path hash bytes |
|---|---|---|---|---|---|
| USA | 910.525 | 62.5 | 7 | 5 | |
| Canada | 910.525 | 62.5 | 7 | 5 | 3 |
| USA - Southern California | 927.875 | 62.5 | 7 | 5 | 3 |
| Costa Rica | 910.525 | 125 | 11 | 5 | |
| Brazil | 923.125 | 62.5 | 8 | 8 | |
| EU/UK (Narrow) | 869.618 | 62.5 | 8 | 8 | |
| EU/UK (Deprecated) | 869.525 | 250 | 11 | 5 | |
| EU 433MHz (Long Range) | 433.650 | 250 | 11 | 5 | |
| EU 433MHz (Narrow) | 433.650 | 62.5 | 8 | 8 | |
| Czech Republic (Narrow) | 869.432 | 62.5 | 7 | 5 | 2 |
| Hungary / Slovakia | 869.618 | 62.5 | 7 | 5 | 2 |
| Netherlands | 869.618 | 62.5 | 7 | 5 | |
| Netherlands (Limburg) | 869.618 | 62.5 | 8 | 8 | 2 |
| Portugal 433 | 433.375 | 62.5 | 9 | 6 | |
| Portugal 868 | 869.618 | 62.5 | 7 | 6 | |
| Switzerland | 869.618 | 62.5 | 8 | 8 | |
| Australia | 915.800 | 250 | 10 | 5 | |
| Australia (Narrow) | 916.575 | 62.5 | 7 | 7 | |
| Australia (Mid) | 915.075 | 125 | 9 | 5 | |
| Australia: SA, WA | 923.125 | 62.5 | 8 | 8 | |
| Australia: QLD | 923.125 | 62.5 | 8 | 5 | |
| New Zealand (Narrow) | 917.375 | 62.5 | 7 | 5 | 2 |
| New Zealand (Gisborne) | 917.375 | 250 | 11 | 5 | 1 |
| Vietnam (Narrow) | 920.250 | 62.5 | 8 | 5 | |
| Vietnam (Deprecated) | 920.250 | 250 | 11 | 5 | |

`mo` adds three "Off-Grid" rows at the client-repeat frequencies (433.000, 869.495, 918.000 MHz; BW 250 / SF 11 / CR 8; `mo:lib/models/radio_settings.dart:514-544`). Bundle the `api` table in the app (no network calls; refresh it by hand per release). Ship it as `MeshCorePresets` (the `MeshtasticPresets` counterpart) so `AirtimeModel` works on `RadioPreset`.

**Changing params needs no reboot on a companion:** `SET_RADIO_PARAMS` saves prefs and calls `radio_driver.setParams` at once (`MM:1443-1454`); TX power likewise (`MM:1465-1468`). A repeater's CLI `set radio` says "reboot to apply" (`fw:src/helpers/CommonRadioPrefs.cpp:39-58`).

**Client repeat** (needed for a companion base, §7): `SET_RADIO_PARAMS` with repeat=1 is refused unless the frequency is exactly 433000, 869495 or 918000 kHz (`MM:1032-1048`, `1439-1440`). Builds may override the list (`ALLOWED_REPEAT_FREQ_RANGE`); `CMD_GET_ALLOWED_REPEAT_FREQ` (60) returns it (`MM:2036-2044`).

**Private channel:** `SET_CHANNEL [32, idx, "MeshTest" (32 B zero-padded), 16 random bytes]`. Channel id on air = first byte of SHA-256(secret) (`fw:src/helpers/BaseChatMesh.cpp:933-945`). Slot 0 is "Public" with the well-known key `izOH6cXN6mrJ5e26oRXNcg==` (`MM:114`, `MM:1002`). Pick the first empty slot (or reuse one named "MeshTest"); never overwrite slot 0. Delete = write empty name + zero secret (as `mo`/`mm` do, unverified in firmware).

But: in MeshCore, channels only carry group text/data (`GRP_TXT`, `GRP_DATA`). Adverts, DMs, ACKs and traces are not on any channel. So the channel is **optional** for our test modes; the isolation comes from the radio params. The "never test on the public channel" rule maps to "never test on community params" (`onPublicChannel`, §5).

Test profile sequence (`applyTestProfile`, all over BLE, no reboot):

| # | Command | Mobile | Base (companion) |
|---|---|---|---|
| 1 | `SET_ADVERT_NAME` | "MeshTest Mobile" (opt.) | "MeshTest Base" (opt.) |
| 2 | `ADD_UPDATE_CONTACT` other radio's key | yes | yes (only needed for DM/status fallbacks) |
| 3 | `SET_CHANNEL` MeshTest | yes | yes (optional) |
| 4 | `SET_RADIO_TX_POWER` | chosen | chosen |
| 5 | `SET_DEVICE_PIN` (phone-generated) | optional | recommended (headless) |
| 6 | `SET_RADIO_PARAMS` freq/bw/sf/cr, repeat | repeat 0 | **repeat 1** (allowed frequency only) |

Do the base first, then the mobile, as Radio Setup's base flow already does; the two radios can't hear each other until both are switched.

**Range settings (2026-10-29, after the first bench setup):** the table above is frequency + modulation, but Radio Setup only takes the modulation from it and writes the relay frequency, so a radio set up from "USA - Southern California" reads back as none of the rows (first field result: a false "Radios don't match — base on USA - Southern California, this radio on CUSTOM" banner). The app therefore picks from `MeshCoreModulations`, the 10 distinct SF/BW/CR combinations in the table ordered by link-check airtime (Fast = SF7/62.5/4/5 ≈ 0.23 s … Longest = SF11/125/4/5 ≈ 1.6 s), with ids `MC_SF7_BW62.5_CR5` etc. `currentPreset`, sessions and `RadioRoles` hold the ladder id whatever the frequency; the community row only names what a radio is on (`regionName`) and decides `onPublicChannel`. The frequency is shown, not asked (one relay slot per band; an "Other…" field for experiments).

**Backup (2026-10-29):** Radio Setup saves what it changes before the first write, like on Meshtastic: `MeshCoreSettings` = SELF_INFO's name, TX power and freq/bw/sf/cr, DEVICE_INFO's client-repeat flag and every GET_CHANNEL slot (secrets included), stored as a v3 `.mabackup` (`protocol: meshcore`). Restore replays `SET_ADVERT_NAME` (when it differs), `SET_CHANNEL` for every slot (the test slot goes back to empty name + zero secret, which is how an unused slot reads), `SET_RADIO_TX_POWER`, then `SET_RADIO_PARAMS` with the saved repeat flag, and re-reads DEVICE_INFO/SELF_INFO. No reboot. A restore cannot delete a slot, only empty it; a firmware without the repeat byte in DEVICE_INFO (< v9) gets `SET_RADIO_PARAMS` without the flag.

Test frequency: use the client-repeat slot for the region (US 918.000, EU 869.495, 433.000) with the user's chosen BW/SF/CR. Bonus: 918.000 is off the US community frequency, so test traffic stays off the local mesh. (EU caveat: 869.495 at BW 250 overlaps 869.618 at 62.5.)

## 7. Collection modes (mobile companion + base)

### Base firmware choice

| | Companion BLE firmware, client repeat ON | Repeater firmware |
|---|---|---|
| Answers traces (forwards + adds SNR) | yes: `allowPacketForward` = repeat flag (`MM:487-489`, `fw:src/Mesh.cpp:58`) | yes (`RM:434-436`) |
| Set up from the app | yes, over BLE with the §6 sequence (existing base-then-mobile Radio Setup flow) | no BLE (`variants/heltec_v3/platformio.ini:40-58`). Over the air: `SEND_LOGIN` with the admin password (Heltec build default "password", `platformio.ini:48`), then CLI DMs `set radio …`, `reboot`; or USB serial CLI |
| Frequencies | 433.000 / 869.495 / 918.000 only | any |
| Relays third-party floods | yes (it is a repeater then) | yes |
| Periodic beacon on its own | none (adverts only on button/app command, `MM:2436-2449`) | local advert ≥ 60 min (`fw:src/helpers/CommonCLI.cpp:160, 503-510`) |
| Phone needed after setup | no | no |

**Recommend: companion firmware with client repeat for the base** (both Heltecs run the same build, the whole setup is app-driven over BLE). Support an existing repeater as base later (Pro "existing network" case): same trace ping, configured by the user.

### (a) Passive

Every received LoRa frame arrives as `0x88` with SNR×4 and RSSI, including packets the companion can't decrypt or has seen before (`fw:src/Dispatcher.cpp:196-199`). Record each as a sample; attribute it (§8) and keep only frames whose transmitter is the base for the base→you layer.

What the base transmits unprompted: nothing periodic. So passive on a quiet test frequency gives only trace returns and whatever the base relays. On a community frequency (Network Mode, later) passive is rich: every repeater relay is a sample with a known last hop.

Burst caveat: 4-frame BLE queue, 60 ms per notify, drops when full (§2). Under heavy traffic expect lost `0x88` frames; count `GET_STATS` packet counters (type 2, `MM:1943-1961`) against frames seen if this matters.

### (b) Base beacon equivalent

No radio-side beacon suits us: companions have no advert timer; repeaters floor local adverts at 60 min; node-discover replies are repeater-only and rate-limited to 4 per 2 min (`RM:786-813, 868`). A base that sends its own beacon would need a second phone running the app at the base (`SEND_CHANNEL_DATA` zero-hop with a seq number every N s). Not worth it.

**Recommend: "pulled beacon" = the mobile sends a trace to the base every N s** (`BeaconKind.trace`). Each exchange is one base→you sample (final SNR + RSSI from the matching `0x88`) and one you→base sample (hop SNR). Misses = trace timeouts (better than telemetry gap counting: every miss is known, with a tag). Interval floor = `AirtimeModel` over both legs (≈ 230 ms per exchange at USA params, below).

Consequence for the UI: on MeshCore "base beacon" and "ping" are the same mechanism; Radio Setup's beacon options become the trace interval.

### (c) Ping

| Option | Gives | Needs | Airtime per ping (USA 62.5/SF7/CR5; EU 62.5/SF8/CR8) |
|---|---|---|---|
| **Trace** `[base key prefix, path_sz 2]` | delivery, RTT, **uplink SNR** (base's hop SNR) and **downlink SNR** (final SNR) + downlink RSSI | base relays; both ≥ v1.11 | out 15 B + back 16 B ≈ 109 + 119 ms; EU ≈ 280 + 280 ms |
| DM + ACK | delivery, RTT (`0x82` trip time), ACK SNR/RSSI via `0x88` (downlink only) | keys exchanged both ways; companion base (repeaters treat DMs as admin) | DM ~30-40 B + ACK; roughly 1.5-2× a trace |
| Status request | uplink SNR/RSSI of the base's *last* heard packet (`RepeaterStats.last_snr`, `last_rssi`) | repeater base + login | REQ + 56-byte response, ≈ 3× a trace |
| RAW_CUSTOM (roadmap idea) | nothing back: firmware never echoes raw data | a phone at the base | — |

**Recommend: trace.** How it works (`fw:src/Mesh.cpp:42-66`, `fw:src/Mesh.cpp:696-715`): the mobile sends a direct TRACE whose payload lists hashes; the base matches its hash, appends the SNR it heard as a path byte and retransmits; the mobile receives a trace whose path is exhausted and pushes `0x89`. `path_snrs[0]/4` = you→base dB; `final_snr/4` = base→you dB; RSSI from the `0x88` of the same frame (payload type 9, same tag at payload bytes 0-3). Use path_sz = 2 (4-byte key prefix) so another relay sharing a 1-byte prefix can't answer. `RESP_CODE_SENT.est_timeout` = 500 + (airtime×6 + 250) × 2 ms for one hop (`MM:891-896`); expected RTT ≈ two airtimes + the base's random direct-retransmit delay (≤ 5 × 0.2 × airtime, `MM:282-285`, factor default `MM:919`): ~250-350 ms at USA params. No firmware rate limit on traces was found (unlike discover).

## 8. Hops and paths

`path_len` byte (flood packets, contact `out_path_len`, message frames): bits 0-5 = hash count, bits 6-7 = hash size − 1 (1-3 bytes; 4 reserved) (`fw:src/Packet.h:79-83`, `fw:src/Packet.cpp:13-18`). Flood relays append their own hash (`fw:src/Mesh.cpp:344-351`); direct relays remove theirs (`fw:src/Mesh.cpp:102-106`). Message frames send 0xFF for direct (`MM:453`, `MM:572`); contacts use 0xFF for "no path known" (`fw:src/helpers/ContactInfo.h:6`).

Normalising a `0x88` frame to `ReceivedPacket`:

| Route | `hops` | Transmitter (whose SNR this is) | `from` |
|---|---|---|---|
| flood, count 0 | 0 | the sender | sender if known (advert key; else src hash of REQ/RESP/TXT/PATH matched against contacts) |
| flood, count n > 0 | n | relay = last path hash | sender as above; `lastHopId` = last hash |
| direct, path empty (zero-hop) | 0 | the sender (for TRACE: the last hop that appended an SNR) | as above |
| direct, path not empty | unknown (not travelling to us) | the previous relay, which removed itself: unknown | skip for coverage, keep in the log |
| TRACE return (our tag) | 0 | the base | base |

Keep "direct vs relayed" dot sizing: relayed = flood count > 0. Hash widths: path hash mode from DEVICE_INFO byte 81 for our own floods; for received packets always read bits 6-7.

## 9. Comparability with the other protocol on one map

| Topic | MeshCore | Effect |
|---|---|---|
| SNR source | RadioLib `getSNR()` on the SX1262 (`fw:src/helpers/radiolib/RadioLibWrappers.cpp:219-221`), sent as int8 ×4 (0.25 dB, clips at ±32 dB) | same chip register as the other firmware; comparable |
| RSSI source | RadioLib `getRSSI()` (`RadioLibWrappers.cpp:216-218`), sent as **int8** (`MM:296`) | **wraps below -128 dBm** (possible at SF11-12 / narrow BW). Unwrap: a positive value v → v − 256 (positive RSSI is impossible in practice). Unverified on hardware. |
| Link margin | SNR floor depends on SF only (`RadioPreset.snrFloorDb`) | works unchanged: colour by margin, not raw SNR, when mixing protocols |
| Bandwidth | community presets mostly 62.5 kHz (vs 125/250 on the other protocol) | noise floor ~3 dB lower than at 125 kHz: same RSSI gives higher SNR; compare margin, store BW with the session (sessions already store preset) |
| Preamble / sync word | preamble 16, sync word `RADIOLIB_SX126X_SYNC_WORD_PRIVATE` (`fw:src/helpers/radiolib/CustomSX1262.h:56`) | the two protocols never hear each other; mixed maps only by overlaying sessions |
| RX gain | SX1262 boosted RX gain on by default (`MM:936-941`, Heltec `SX126X_RX_BOOSTED_GAIN=1`) | other firmware's default not checked here: note it per session if it matters |
| TX power | per radio, SELF_INFO byte 2 | store with the session as today |
| Uplink | trace gives real you→base SNR every ping | richer than pings on the other protocol (which need traceroute) |
| Clock | `0x88` has no RX time; stamp on the phone | fine (never queued) |

Sessions should store `protocol` (schema v5 already does) and the exact freq/BW/SF/CR; the map's compare view should warn when protocols or bandwidths differ.

## 10. Hardware checks (Andy, first MeshCore session)

Bench on 2026-10-29: Wio Tracker L1 and T1000-E (both nRF52, MeshCore companion BLE v1.18.0). Implementation notes from reading the firmware while building: trace frames use flags 2 (4-byte hashes, `MM:1813-1838`); `est_timeout = 500 + (airtime × 6 + 250) × (hops + 1)` ms (`MM:108-111, 891-896`); the `0x88` of a frame is pushed before the packet is parsed (`Dispatcher.cpp:196-199`), so it always precedes the `0x89`; a repeat request off the allowed list answers ERR 6 before any range check (`MM:1439-1440`), and the list is exactly 433000 / 869495 / 918000 kHz (`MM:1032-1040`); both the ESP32 and nRF52 builds advertise the Nordic UART service (`esp32/SerialBLEInterface.cpp:53`, `nrf52/SerialBLEInterface.cpp:197`).

1. Connect to each radio from the connect list (MeshCore tag; Pro). Expect the iOS PIN prompt (PIN on the official app / default 123456), then "Downloading contacts n of N" and ready. `diag.log` must not say "no answer to DEVICE_QUERY".
2. Power-cycle the radio: the app reconnects by itself without a new PIN prompt.
3. Radio Setup with the L1 as base: 918.000 MHz, a 62.5 kHz preset, repeat on → OK, no reboot, the read-back shows the new values. Then try 910.525 with repeat on → the "only relay on 433.000, 869.495, 918.000 MHz" error. Then switch to the T1000-E as mobile.
4. Start a session (base beacon = link check every 10 s): each check should come back `received` with both an uplink and a downlink SNR, an RSSI, and a round trip of about 250-350 ms. Turn the base's repeat off: checks time out and the beacon goes absent after 3.
5. 10 minutes of checks every 5 s: count missed checks and look for lost `0x88` frames (the radio's BLE queue holds 4).
6. Compare the GET_STATS airtime readout with the app's own "Air x%".
7. At a weak link (SF11, or distance), confirm RSSI below -128 dBm appears unwrapped (negative), not positive.
8. Save the real DEVICE_INFO and SELF_INFO bytes into `test/meshcore/` fixtures (the fake guesses the manufacturer string).
9. Backups: after Radio Setup, Settings → Radio Setup → Backups shows the radio's original settings (community frequency, name, Public channel). "Put this radio back the way it was" must return it to the community preset with repeat off and the MeshTest slot empty (check in the MeshCore app), with no reboot and the BLE link kept.

Record results at the bottom of this file.
