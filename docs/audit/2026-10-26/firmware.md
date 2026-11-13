# Mesh Analyzer vs Meshtastic firmware 2.5 → 2.8.x (Opus, 2026-10-26)

**Sources**
- Firmware source read at tags `v2.7.26.54e0d8d` and `v2.8.1.8e6a88d`, plus spot checks at 2.5.0, 2.5.20, 2.6.0, 2.6.11 and 2.7.0–2.7.25.
- Release notes via `gh` (2.8.0 ×2, 2.8.1) and the PR bodies of #9485, #9962, #10171, #10675, #10736, #10741, #10929 and #11637.
- Protobuf diff v2.7.26 → v2.8.1 → master (2026-10-21), and the Dart `protobuf-4.2.0` runtime source.
- Clones in the scratchpad: `fw/repo` and `pb/repo`, with the extracted firmware files in `fw/src/<tag>/`.
- [C] = confirmed in source or release notes. [I] = inferred, not run on hardware.

**Which firmware exists today**
- **2.7.26** is still the "Latest" stable release.
- **2.8.0.7239fe8** and **2.8.0.47db0e3** were both **revoked**: one fails LR1110 init on the T1000-E, the other has a signing bug.
- **2.8.1.8e6a88d** is a pre-release (2026-10-01) and is the newest build.
- There is no 2.8.2 or 2.9. `develop` has 118 commits since 2.8.1; the only relevant one is #12191 (XEdDSA policy rework).
- The protobufs `master` adds only PAGING_APP, LORA_OTA_APP and new hardware IDs. None of that breaks the wire format.

## 1. Summary table

| # | Firmware | Change | App impact | Severity |
|---|---|---|---|---|
| F1 | 2.8+ | Node number becomes `crc32(public_key)`. Every existing radio gets a **new node number** on its first 2.8 boot, and its old self entry is removed. [C] | Maps, RadioRoles, contacts and BaseLocationStore keep the old number. Pings go to a dead number, beacons aren't counted as the base, and the map becomes a dead zone. | **High** |
| F2 | 2.8+ (#10929) | A one-time upgrade migration forces `device_telemetry_enabled=false`, on private channels too. [C] | A base beaconing with telemetry goes silent after an upgrade. | **High** |
| F3 | 2.7.19+ (#9485) | A DM to a node whose key is unknown is refused locally with **PKI_SEND_FAIL_PUBLIC_KEY (39)**. Before 2.7.19 it was silently sent channel-encrypted. [C] | The recovery code only handles PKI_UNKNOWN_PUBKEY and PKI_FAILED (`meshtastic_radio.dart:1072-1073`), so pings fail every time with no self-heal. The CLAUDE.md statement ("2.6+, local PKI_UNKNOWN_PUBKEY") is wrong. | **High** |
| F4 | 2.8+ | New enum values: MEDIUM_TURBO=16, TINY_FAST=14, TINY_SLOW=15, ITU*_70CM=34-36, ITU2_125CM=37. [C] | Dart stores an unknown enum value as an unknown field, and the field reads LONG_FAST or UNSET. `deepCopy` then writes that unknown value *after* the new one, the firmware takes the last value, and the preset or region change is silently undone. | Medium |
| F5 | 2.8 ESP32 (#10741) | NimBLE bonds in the old format are wiped on first boot, then the radio reboots. [C] | iOS keeps a stale bond, so pairing fails or loops until the user taps "Forget This Device". | Medium |
| F6 | 2.8.0 vs 2.8.1 | Signatures are incompatible. A bad signature is dropped even under the default COMPATIBLE policy. [C] | A 2.8.0 base's signed telemetry beacons are dropped by a 2.8.1 mobile. | High if present |
| F7 | 2.7.x on classic ESP32 | Range Test is compiled out, and the `excluded_modules` bit is not set. [C] | `selectBeaconKind` (`radio_types.dart:351`) picks rangeTest for every 2.7 radio, so a T-Beam, Heltec V2, T-LoRa or Station G1 base never beacons. | Medium |
| F8 | 2.8+ | Setting the first region on a fresh radio creates its keys and moves `my_node_num` without a reboot. [C] | Later admin messages go to the stale `myNodeNum` (`:1143`) and probably fail with PKI_SEND_FAIL_PUBLIC_KEY. [I] | Medium |
| F9 | 2.8+ | An open edit transaction auto-commits after 60 s idle, without a reboot. [C] | A Radio Setup that stops partway leaves the radio half-configured, and that is persisted. On 2.7 it would have been lost on reboot. | Medium |
| F10 | 2.8+ | DM want_ack attempts go from 3 to **5**. [C] | One ping can cost up to 5 transmissions, while AirtimeModel assumes 1. On slow presets, late ACKs after the 30 s timeout are discarded. [I timing] | Medium |
| F11 | all; 2.8.1 adds relay rssi/snr | An implicit ACK from an overheard rebroadcast reaches the phone with `from == own node`. [C] | `_onPingReply` (`:1053-1103`) takes the first reply, so the base's real ACK is lost. On 2.8.1 the relay's SNR/RSSI is stored on the implicit row. | Low–Med |
| F12 | 2.7.26 / 2.8.1 | 2.7.26 has no RDEF entry for EU_866, EU_874, EU_917, EU_N_868 or ITU*_2M, so it falls back to the **UNSET row (902–928 MHz)**. 2.8.1 rejects UA_868, EU_874 and EU_917, and the ham regions need a licence. [C] | `MeshtasticRegions.all` (`meshtastic_regions.dart:23-57`) offers all of them on any firmware. | Medium (EU) |
| F13 | 2.7.17+ / 2.7.20+ | NodeInfo want_response replies are suppressed for 12 h per requester and have a 10-min cooldown. [C] | `exchangeNodeInfo` rarely gets a reply; the base's key effectively comes only from `add_contact`. | Low |
| F14 | 2.7.0–2.7.13 | `nodedb_reset` only keeps favourites from **2.7.14**. [C] | The comment at `:1161` says "before 2.7". | Low (doc) |
| F15 | 2.8 protos | `rx_rssi` and `rx_time` became optional (0 dBm is a legal reading), and `hop_start==0` now means "unknown". [C] | Edge cases in `_rxRssiOf` and `_hopsOf`. | Low |
| F16 | 2.8.1 | Broadcasts are XEdDSA-signed (+64 bytes). [C] | Beacon airtime roughly doubles. If the base's key changes, the mobile drops its signed beacons. | Low/Med |
| F17 | <2.6.8 | No `add_contact`; the radio ACKs it but ignores it. [C] | Harmless, because those versions fall back to channel-encrypted DMs. | Info |
| F18 | 2.8 | "Lockdown" builds are opt-in and off by default. [C] | Stock builds are unaffected. | Info |

## 2. Detailed findings

### F1. Node number derived from the public key on 2.8 (High) [C]
**What changed:** 2.8.1 `NodeDB.cpp:505,529` calls `pickNewNodeNum()` then `generateCryptoKeyPair(nullptr)`, which calls `createNewIdentity()` (`:4710-4752`). That sets `my_node_num = crc32Buffer(public_key)` and removes the old self entry. The private key is kept, so the public key stays the same (a low-entropy key is regenerated, `:4614-4627`). 2.7.26 still uses the MAC-derived number (`NodeDB.cpp:1171`). Release notes: "Node numbers (ID) are now derived from the public-key identity…".

**Where the app depends on it:** `session_manager.dart:276-303` takes the base from `baseMeshNodeIdForMap`; `radio_roles.dart` `learn()` (`:220-225`) maps node number → Bluetooth id only, never the other way round; contacts and BaseLocationStore are keyed by node number; `ensureContact` (`meshtastic_radio.dart:968-977`) will re-add the *old* number with the correct key, so the mobile PKI-encrypts pings to a number nobody answers.

**Field symptom:** after a 2.7 → 2.8 upgrade, every ping times out, the base appears as a new node, and the map is all dead zone.

**Mitigation:** procedure: after any upgrade, re-run Radio Setup on both radios and start a **new map**. Code: in `learn()`, when `roleOfDevice(id)` is set but `nodeOf(role) != myNodeId`, update the node number and warn the user; work out the new number as `crc32(savedUser.publicKey)` to remap contacts, roles and the map's base (bench-check that `crc32Buffer` equals zlib `crc32`); skip `add_contact` when `crc32(key) != num` on 2.8+.

### F2. Upgrade turns the telemetry beacon off (High) [C]
PR #10929 adds a one-time migration on the first 2.8 boot (`POSITION_TELEMETRY_OPTIN_VER=26`) that forces `device_telemetry_enabled` and the other telemetry flags off for everyone ("Telemetry force-off clobbers deliberate opt-ins"). Position on private channels is kept. Depends: the telemetry beacon written by `applyTestProfile` (`:1256-1263`) and `setBeacon` (`:1380-1386`). Symptom: "Base is reachable but its beacon is off", or a dead zone. Mitigation: re-apply the beacon after every firmware update; code: on connect to the base, compare `moduleConfigs[telemetry].deviceTelemetryEnabled` with the RadioRoles beacon record and offer a one-tap re-enable.

### F3. Local refusal is PKI_SEND_FAIL_PUBLIC_KEY, from 2.7.19 (High) [C]
- **2.5.0–2.7.18:** the PKI branch in `Router.cpp` `perhapsEncode` requires `node && public_key.size==32`. If the key is missing it falls back to channel encryption and the DM is still delivered (checked at 2.5.20, 2.6.0, 2.6.11, 2.7.0, 2.7.10, 2.7.15, 2.7.17, 2.7.18).
- **2.7.19+:** commit 7b03980e0 (#9485, 2026-01-30) makes the firmware return `PKI_SEND_FAIL_PUBLIC_KEY`. `abortSendAndNak` delivers that NAK to the phone immediately and nothing goes on air (2.7.26 `Router.cpp:661-665`, 2.8.1 `:1354`).
- **PKI_UNKNOWN_PUBKEY (35)** is different: the base sends it when it doesn't have *our* key, after a round trip (2.7.26 `ReliableRouter.cpp:117-121`); the sending firmware then automatically sends its NodeInfo (`:133-139`).

Depends: recovery branch at `meshtastic_radio.dart:1072`, plus the key exchange in `ActiveProbeService` (session start / reconnect only). Symptom: every ping is `error:PKI_SEND_FAIL_PUBLIC_KEY` with a near-zero round trip. **Fix:** add `pb.Routing_Error.PKI_SEND_FAIL_PUBLIC_KEY` to the condition at `:1072` (value 39 is in the vendored protos). Correct CLAUDE.md and `meshtastic_contacts.dart:14-15`.

### F4. Unknown enum values silently undo preset/region writes (Medium) [C mechanism]
In `protobuf-4.2.0` (`coded_buffer.dart:74-82`) an unknown enum value goes into the UnknownFieldSet and the field stays at its default; on write, unknown fields are serialised after the known ones (`:7-30`) and setting the field does not clear the unknown entry. `applyTestProfile` (`:1234-1240`) and `setRegion` (`:1333`) deep-copy `loraConfig`, so the old raw value is written last and the firmware keeps it. The comment at `meshtastic_presets.dart:161-165` can't happen in Dart. Symptom: a radio on MEDIUM_TURBO shows as "Long Fast" and stays on MEDIUM_TURBO after a "successful" setup. **Fix:** regenerate protos at `v2.8.1` (§3 shows nothing breaks), or build the LoRa config fresh / `clearUnknownFields()`; optionally warn when `loraConfig.unknownFields` has tag 2 or 7.

### F5. ESP32 bond purge on upgrade (Medium) [C]
2.8.1 `NimbleBluetooth.cpp:40-86` `purgeIncompatibleBleBonds()` wipes `nimble_bond` when the record size differs, then restarts; a stale-bond reconnect fails in the encryption step (`:692-709`). Symptom: a Heltec V3 flashed to 2.8 fails at "Pairing" or loops. nRF52 (T1000-E) unaffected. **Fix:** "Forget This Device" after flashing an ESP32; code: after 2+ pairing failures on a previously paired radio, show that tip.

### F6. 2.8.0 is revoked and its signatures are incompatible (High if present) [C]
2.8.1 notes: "2.8.1 signatures are not compatible with the revoked 2.8.0". `Router.cpp:730-778`: a signature that fails verification is dropped under the default COMPATIBLE policy. 2.8.1 signs non-PKI broadcasts (`:1259-1276`), including the telemetry beacon. 7239fe8 also fails LR1110 init on the T1000-E. **Mitigation:** check `firmwareVersion` on both radios and warn on `2.8.0.`.

### F7. No Range Test on classic ESP32 under 2.7 (Medium) [C, also beacon-kinds.md §0]
`selectBeaconKind` returns rangeTest for any 2.7 radio. **Fix:** prefer telemetry when the base's `hw_model` is a classic ESP32 board (TBEAM, HELTEC_V1/V2.x, TLORA_*, STATION_G1, NANO_G1*, M5STACK, RAK11200…), or use telemetry everywhere.

### F8. A fresh 2.8 radio changes node number when its region is first set (Medium) [C firmware / I app]
Key generation is blocked while region is UNSET (`NodeDB.cpp:4636`); `AdminModule.cpp:1037-1046` calls `ensurePkiIdentity()` on the first region, which moves the node number, bumps `identityGeneration` and calls `nudgeFromNum` (no reboot; LoRa changes apply live, #9962). Local admin is sent `to: myNodeNum` (`:1143-1153`) and `myNodeNum` only updates on a new `myInfo` frame (`:759-761`); `setRegion` (`:1337-1339`) sends begin → lora → commit. Likely symptom: the commit goes to the old number and fails ("Radio rejected setting: PKI_SEND_FAIL_PUBLIC_KEY"), the 60 s auto-commit (F9) saves the settings, and the app keeps the stale number until reconnect. **Fix:** after any lora write that takes the region off UNSET, re-drain and wait for the new `myInfo`, or reconnect before the next write.

### F9. Abandoned edit transaction auto-commits on 2.8 (Medium) [C]
2.8.1 `AdminModule.h:45` `EDIT_TRANSACTION_IDLE_MS=60000`; `AdminModule.cpp:1886-1898` saves what was applied, no reboot. 2.7.26 has no expiry. The commit itself still calls `disableBluetooth()` then saves with a reboot in both (2.7.26 `:335-341`, 2.8.1 `:485-492`), so "ACK lost to reboot" handling stays right. **Fix:** after a mid-setup failure, warn the radio may be partly configured and offer Retry or Restore (same class as the 2026-10-24 solar node).

### F10. More DM retries on 2.8 (Medium) [C]
2.8.1 `NextHopRouter.h:115` `NUM_RELIABLE_UNICAST_ATTEMPTS=5` (2.7 used 3); spacing ≈ 2 × airtime + contention window (`RadioInterface.cpp:807-819`); 2.8.1 keeps retrying after a DUTY_CYCLE NAK (`ReliableRouter.cpp:51-53`). Symptom: at the edge, real airtime up to 5× the model; on LONG_SLOW the 4th/5th attempt can land after the 30 s timeout (`constants.dart:64`). [I] **Fix:** firmware- and preset-aware ACK timeout, and a grace map so a late ACK can still update its row.

### F11. Implicit ACK wins over the real ACK (Low–Med) [C]
2.7.26 `ReliableRouter.cpp:38-58`: implicit ACK generated locally with `from == own node`, rssi 0. 2.8.1 (`:76-92`, `MeshModule.cpp:79-88`) also copies the relay's `relay_node`, rssi and snr. The first reply completes the ping and the base's real ACK is dropped; on 2.8.1 the relay's SNR is stored on the implicit row with hops = 0. Bites with hop limit 1 plus a third-party router in ALL mode nearby. **Fix:** keep the ping pending after an implicit ACK and upgrade to `received` if the base's ACK arrives; never store signal values on implicit rows.

### F12. Region tables (Medium for EU) [C]
2.7.26 `RadioInterface.cpp:37-217` defines only the classic set; `initRegion` (`:493-506`) falls back to the UNSET row (902–928 MHz) for EU_866, EU_874, EU_917, EU_N_868 and ITU*_2M. 2.8.1 removes UA_868, EU_874 and EU_917; `checkConfigRegion` (`:1068-1085`) rejects unknown codes and requires a licence for ham regions. EU_868/EU_866/EU_N_868 swap automatically with the preset (#10675). **Fix:** filter the region list by firmware version; on 2.8+, use `FromRadio.region_presets` (field 19, #10736), which needs regenerated protos.

### F13 to F18
- **F13:** 2.7.26 `NodeInfoModule.cpp:30-45,127-161`: 12 h per-requester suppression from 2.7.17, 10-min scaled cooldown from 2.7.20, no reply above 40 % channel utilisation. The base still learns our key from our NodeInfo; it's the reply that is unreliable. Optional: `Heartbeat{nonce:1}` forces a NodeInfo broadcast on the 60 s path (2.7.26 `PhoneAPI.cpp:216-233`).
- **F14:** keep-favourites honoured from `v2.7.14.e959000`. `add_contact` marks the contact as a favourite (2.8.1 `NodeDB.cpp:3754-3778`), so contacts survive a reset on 2.7.14+.
- **F15:** wire format unchanged; after regenerating, prefer `hasRxRssi()`.
- **F16:** signing adds 64 bytes per beacon; a base key change means the mobile drops its beacons until it relearns the key. #12191 on develop stops signing under Compatible.
- **F17:** `add_contact` added in proto v2.6.8 (2025-05-14); `SharedContact{node_num=1,user=2,should_ignore=3,manually_verified=4}` unchanged; 2.8.1 `addFromContact` never erases a stored key.
- **F18:** `MESHTASTIC_ENABLE_LOCKDOWN` defaults to 0.
- **Version-independent:** a base with role **CLIENT_HIDDEN** never sends the telemetry beacon; it also needs channel utilisation under 25 %, air utilisation within half the regional duty cycle (5 %/h on EU_868), and the `TELEMETRY_CONFIG` bit not set (2.8.1 `DeviceTelemetry.cpp:26-34`). US LongTurbo default (#11637) applies only to region selection on the device screen; the app writes the preset explicitly.

## 3. Verified as unaffected
- **BLE:** service and ToRadio/FromRadio/FromNum UUIDs identical at 2.7.26 and 2.8.1; pairing modes and encrypted-read/write flags the same; a FromRadio read blocks up to ~20 s then returns 0 bytes, so read-until-empty works.
- **Handshake:** `want_config_id` → config stream → `config_complete_id` unchanged. 2.8's `region_presets` frame (FromRadio field 19) decodes as an unknown oneof member and falls into `default:`. A heartbeat with nonce 0 is still a plain keepalive.
- **Admin:** local admin (`from == 0`) needs no session passkey on 2.5 through 2.8.1 (2.8.1 `AdminModule.cpp:236-244`); exception: if `is_managed` is set, local admin is silently ignored. All admin message shapes the app uses are unchanged to master, and commit still reboots.
- **Protobuf wire:** no field the app uses renumbered or removed; Routing.Error identical (0–9, 32–39); port numbers unchanged; DeviceMetrics and LocalStats unchanged (`noise_floor=15` also available); `RANGETEST_CONFIG` still 0x10; only removals are TrafficMgmt bools and renamed hardware models; new channel field `use_aead` defaults to false.
- **Frequency slot:** with `channel_num=0`, US and EU_868 use `hash("MeshTest") % slots` in both versions, so mixed 2.7/2.8 pairs land on the same frequency.
- **Routing:** want_ack hop limit 0 is still replaced by the default, so `pingHopLimit=1` is right; variable hop limits only apply to broadcasts; 2.8 Traffic Management rate limiting only applies to traffic not to or from us; DUTY_CYCLE_LIMIT is still NAKed to the phone.
- **Other:** Range Test payload still `"seq %u"`, hop limit 0, auto-off after 8 h, only when channel utilisation under 25 %. "MeshTest Base"/"MeshTest Mobile" fit 2.8's 25-byte long-name limit. Position precision 32 is allowed on a private channel.

## 4. Bench checks needed
1. Upgrade a 2.7.26 radio (Heltec V3 and T1000-E) to 2.8.1: does the node number become crc32(pubkey)? key unchanged? telemetry off? MeshTest, preset and rebroadcast mode kept? does iOS need "Forget This Device"?
2. Fresh 2.8.1 radio with region UNSET: run the app's region dialog. Does the commit fail, and is a new `myInfo` frame pushed?
3. 2.7.26 mobile without the base's key: confirm the immediate PKI_SEND_FAIL NAK and that nothing is transmitted.
4. Radio on MEDIUM_TURBO: run Radio Setup to LONG_FAST and check whether the change sticks.
5. LONG_SLOW and LONG_MODERATE on 2.8.1 with the base out of range: time to the MAX_RETRANSMIT NAK vs the 30 s timeout, and the TX count (LocalStats).
6. Third radio in ALL mode near the mobile: how often does an implicit ACK pre-empt the real one?
7. Classic ESP32 base on 2.7.26: no `seq` packets.
8. Mixed pair (2.8.1 base, 2.7.x mobile): do signed beacons decode, and is it still hops 0?
9. EU_866 on 2.7.26: does the radio tune to US frequencies? Use a shielded or dummy-load setup.
10. crc32Buffer: does it equal zlib crc32 of the 32-byte public key?

## 5. Doc corrections
- **CLAUDE.md PKI note:** the local refusal is from **2.7.19**, code **PKI_SEND_FAIL_PUBLIC_KEY (39)**, and nothing goes on air. PKI_UNKNOWN_PUBKEY is the base's NAK (~1 s) and the firmware answers it with a NodeInfo. Before 2.7.19 a DM without a key goes out channel-encrypted.
- **`meshtastic_radio.dart:1161`:** keep-favourites applies from 2.7.14.
- **`meshtastic_presets.dart:161-165`:** values newer than the vendored enum never reach `fromModemPreset`; Dart reads them as LONG_FAST.
- **CLAUDE.md:** on 2.8 the node number is crc32(public key); it changes on the first 2.8 boot and on the first region set.

## What to do before the field test
1. Fix F3: add PKI_SEND_FAIL_PUBLIC_KEY to the recovery branch.
2. Never run 2.8.0.
3. After any 2.7 → 2.8 upgrade, redo Radio Setup on both radios and the base beacon, and start a new map (F1, F2).
4. Forget ESP32 radios in iOS Bluetooth settings after flashing them (F5).
5. Use telemetry, not Range Test, on any 2.7 classic-ESP32 base (F7).
6. Regenerate the protos at v2.8.1, or stop deep-copying `loraConfig` (F4).
