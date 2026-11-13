# Mesh Analyzer: product review from a Meshtastic user's point of view (2026-10-17)

Reviewer lens: opinionated Meshtastic enthusiast who reads the firmware source. Nothing changed. Does not repeat the 2026-10-16 audit (public-channel guard holes, Range Test prompt dropping packets, GPS retry, privacy, compliance, default-PSK check).

## 1. What's genuinely good

- **Hop handling is right.** Hops are `hopStart - hopLimit`, guarded for `hopStart == 0` (`meshtastic_radio.dart:139-141`). Relayed packets are dropped by default so they neither become a measurement nor prove the base is in range (`packet_processor.dart:149-157`), and the comment explains why. That one detail puts it ahead of most hobby range-test tools.
- **The base's own packets are filtered properly.** Replayed packets from the radio's buffer are filtered via `queued` / `isStale`; local NAKs and our own node's packets are excluded; the radio's own `airUtilTx` / `channelUtilization` are read and stored.
- **The protocol work is competent.** Local admin over BLE correctly needs no session passkey. The PKI key exchange and the `add_contact` re-add on `PKI_UNKNOWN_PUBKEY` are real 2.6+ knowledge. The test channel has uplink and downlink off. Custom-modulation decoding uses the firmware's bandwidth codes.
- **Measuring both directions is the right product.** The "Signal (base → you) / Pings (you → base)" toggle and the "Relayed only" legend are exactly how a mesh person thinks about a link. Backups that also produce a standard `meshtastic.org/e/#` channel URL are a nice touch.

## 2. Findings, ranked

### MUST-FIX

**M1. The base's beacon silently dies after 8 hours, and the app doesn't know**
- Where: `meshtastic_radio.dart:1117-1123` turns the base's Range Test on with a sender interval. `setBeacon` (`:1216`) is never called anywhere in `lib/`.
- Firmware `RangeTestModule.cpp` turns the sender off after 8 hours ("If we have been running for more than 8 hours, turn module back off", `isWithinTimespanMs(started, 28800000)`). The clock starts at boot, and Radio Setup's commit reboots the base. Set the base up in the evening and walk the next morning: zero beacons, and the app shows a beautiful "out of range" map that is really "beacon expired". The firmware also only sends while channel utilisation is under 25%, so beacons vanish on a busy channel too. And the beacon is never turned off afterwards, against the docs' advice.
- Fix: store the base's setup/boot time and show "Beacon on until HH:MM" in Radio Setup and the session panel. When pings are being ACKed but no `seq` packet has arrived for 3 beacon intervals, say "Base is alive but its beacon is off (8-hour limit). Power-cycle the base." Add a "Stop base beacon" action and offer it at session end.

**M2. SNR of exactly 0.0 dB is thrown away**
- Where: `meshtastic_radio.dart:123` and `:1012` (`snr: packet.rxSnr != 0 ? ... : null`).
- SX126x SNR is quantised to 0.25 dB and 0.0 is a normal reading in the "getting marginal" band. In the demo session the median SNR is 1.5 dB. Every 0 dB reading becomes "no SNR", skewing colours, medians and IDW exactly at the interesting edge.
- Fix: SNR is valid whenever `rxRssi != 0`. Same rule on the ping ACK path.

**M3. "Pings (you → base)" never measures the uplink**
- Where: `meshtastic_radio.dart:940-1015`. A PRIVATE_APP DM with `want_ack`; the stored SNR/RSSI comes from the base's routing ACK as heard by the mobile.
- Each ping gives only a delivered bit; its SNR is the downlink again. The comment at `active_probe_service.dart:367` admits this, but the UI frames pings as the you → base layer. No TRACEROUTE_APP code exists.
- Any experienced user will ask "what SNR did the base hear me at?". `RouteDiscovery.snr_towards` / `snr_back` (firmware 2.3+) answers both directions in one exchange. Lopsided links (a 1 W base with a big antenna against a T1000-E) are the whole point.
- Fix: add a traceroute probe mode, base only, private channel, 30 s or more between. Record `snr_towards[0]` as uplink SNR and colour the Pings layer by it. Keep the PRIVATE_APP ping for delivery rate.

**M4. Radio Setup takes the user's real node off the mesh, and that's the common case**
- Where: `_testChannels` (`meshtastic_radio.dart:1198-1214`) writes MeshTest as PRIMARY and DISABLED on slots 1-7. `applyTestProfile` also changes the preset and sets `channelNum = 0` (`:1106-1114`).
- The person most likely to buy this wants to know how far *their roof node* reaches. That node is usually CLIENT or ROUTER on LongFast serving neighbours. Radio Setup silently removes it from the public mesh, its channels and its preset, renames it "MeshTest Base", and it stays off until a manual Restore. Expect "this app knocked my router off the mesh" posts.
- Fix: say plainly before applying that the radio leaves your mesh until you restore it. Show a persistent "Base is in test mode since <date>, restore?" banner whenever the phone connects to that node. Offer "Restore original settings" as a primary action at the end of a coverage map.

**M5. You can't measure your existing mesh at all, even passively**
- Where: `session_manager.dart:135-138` refuses any session when `onPublicChannel`.
- A receive-only session transmits nothing. The "never on the public channel" rule is about transmitting, but it's enforced as "never listen". Drive-testing your existing LongFast router's NodeInfo, telemetry and position packets, and every other direct node you hear, is the number one coverage use case. Zero airtime, no second radio, no reconfiguration. It's what people do today with the official app's Position Log plus spreadsheets.
- Fix: a "Listen-only" session type allowed on any channel. Pings and the NodeInfo exchange stay hard-disabled, the radio isn't touched. Plot every direct-hop node, not just the base; the relay filter already makes this honest.

### SHOULD-FIX

**S1. The preset table is incomplete and the fallback is wrong**

> **Correction (2026-10-18, verified against firmware source):** 2.7.26 does NOT implement the LITE/NARROW presets; `modemPresetToParams` in `src/mesh/MeshRadio.h` has no case for them, so the "firmware doesn't know them" comment was right for 2.7. Their parameters exist from 2.8.1. NARROW_SLOW is shorter on air than LONG_FAST, not ~4× longer. The remaining points (deprecated LONG_SLOW first, SHORT_TURBO offered in EU_868, LONG_TURBO never offered, no narrow presets for EU_N_868) stand and are fixed on `fix/eu-presets`.
- Where: `meshtastic_presets.dart:59-81`.
- The vendored v2.7.26 protos define LITE_FAST, LITE_SLOW, NARROW_FAST and NARROW_SLOW (EU 866 / 62.5 kHz; `config.proto:1036-1057`). Here they fall back to LONG_FAST parameters under a comment claiming the firmware "doesn't know" them. NARROW_SLOW at 62.5 kHz has roughly 4× LONG_FAST's symbol time, so airtime and the interval floor are badly wrong for exactly the duty-cycle-limited EU users. LONG_SLOW is "Deprecated in 2.7" (`config.proto:982-984`) but is first in `testPresets`. SHORT_TURBO (500 kHz) is offered regardless of region although EU_868's sub-band is only 250 kHz wide. LONG_TURBO is mapped but never offered. EU_N_868 is listed but no narrow preset is offered.
- Fix: add the four EU presets with real SF/BW/CR. Filter `testPresets` by region bandwidth. Drop or label LONG_SLOW deprecated. Offer LONG_TURBO only for `wideLora` regions.

**S2. The airtime model ignores retransmissions and the ACK**
- Where: `airtime_model.dart:37-41`.
- A `want_ack` DM is retransmitted by ReliableRouter up to 3 more times. Out of range, one ping is up to 4 transmissions; on LONG_FAST (about 0.56 s per ping) at 15 s that's about 15% duty. The headline "≈0.2 s of air per ping / 5%" is optimistic by 4× where it matters. The base beacon default of 15 s on every preset (`radio_setup_screen.dart:42,52`) contradicts the docs' 30 s recommendation on LongFast.
- Fix: budget worst case (4 × ping) or back off after N consecutive timeouts. Default the beacon to 30 s on Long presets.

**S3. Pings use the radio's hop limit, so "delivered" can be a relay**
- Where: `meshtastic_radio.dart:940-955` (no `hopLimit` on the packet). Both radios keep `hopLimit` 3 and default `rebroadcast_mode` ALL; nothing touches `Config.device`.
- Every Mesh Analyzer user shares one frequency slot, because the slot is hashed from the constant channel name "MeshTest" (`radio_profile_service.dart:37`). Another user's base, or any ALL-mode node on that slot and preset, will relay your pings and ACKs. A ping retry that succeeds 20 s later is plotted at the send position.
- Fix: send pings with `hop_limit` 0, or set lora hop limit 0-1 in Radio Setup. Set `rebroadcast_mode = LOCAL_ONLY` on both test radios (record it in the backup). Add a random suffix to the channel name per install (≤ 11 chars) so users don't share a slot. Store `relay_node` (2.6+).

**S4. Range Test `seq N` is never parsed, so there's no beacon loss rate**
- Beacon delivery rate vs distance is *the* number a range tester wants ("90% at 2 km, 50% at 3.5 km"). It's also how you tell "out of range" from "beacon stopped" (M1).
- Fix: parse and store `seq`; compute delivery rate per window and per grid cell; show "beacons 41/48" in the session panel; add to CSV.

**S5. The backups list is cluttered (the dev's suspicion is correct)**
- Where: `radio_backup_service.dart:172` returns every backup for every radio, newest first. `radio_backups_section.dart:220` only greys out Restore.
- Tiles are titled with the BLE name, which changes after renaming because it derives from the short name. "Saved by hand" backups taken while already on MeshTest add noise.
- Proposed design: group by node number, titled by the owner long name from the *oldest* backup plus `!nodeid` and hardware model. Connected radio's group on top and expanded, with one prominent button **"Restore original settings (LongFast, 3 channels, saved Oct 12)"**: the earliest "Before Radio Setup" backup, pinned, never auto-deleted. Other radios collapse to one line ("MeshTest Base: original settings saved, connect to restore"). Remaining history under "Older backups (n)"; skip or flag hand backups that only captured MeshTest. Role badge from `RadioRoles`. People trust a reconfiguration tool only if the undo is obvious.

**S6. "Clear nodes list" wipes the user's mesh NodeDB**
- Where: `meshtastic_radio.dart` `resetNodeDb`.
- On a personal mobile radio this throws away public keys, favourites and history for the whole local mesh. Firmware before 2.7 ignores favourites anyway.
- Fix: warn "removes every other node and its keys; your other apps will lose them too." Make clear it is rarely needed.

**S7. Firmware version is read but never used**
- Where: `queryDevice` (`meshtastic_radio.dart:~1232`); no UI or logic references `firmwareVersion`.
- The app assumes 2.6+. On 2.5 and below `add_contact` silently fails. No "your base runs 2.4" warning.
- Fix: show firmware on the radio sheet; warn below 2.5.

**S8. The node list is thin for a mesh user**
- Where: `node_list_screen.dart:97-110` shows only name, hardware model and last heard.
- Missing: hops away (already parsed into `RadioNode.hopsAway` but not stored or shown), last SNR/RSSI, battery and voltage, role, `!nodeid`, distance, firmware, "has public key", favourite. Their absence reads as unfamiliar with Meshtastic.

### NICE

- **N1. Branding leaks in the screenshots.** The demo radio is `Meshtastic_e4ea` (`demo_seeder.dart:287`), visible in screenshots 03 and 06. That's the trademark in App Store marketing. Raw enums ("MEDIUM_FAST") also show in screenshots 03 and 04.
- **N2. CSV interop.** Offer an export matching the official `rangetest.csv`. Add `distance_m`, `seq`, `region`, `frequency_mhz`, `tx_power`, `firmware`.
- **N3. Base position.** If the base has GPS (T1000-E does), prefer its own POSITION over the phone fix at setup. Show live distance to base in the HUD; people want "SNR −12 at 3.4 km".
- **N4. Record TX power per radio** from `loraConfig.txPower` so comparisons are fair.

## 3. What the community wants that this app lacks

- **Packet-loss / delivery rate vs distance from Range Test sequence numbers**, not just SNR dots ([Range Test docs](https://meshtastic.org/docs/configuration/module/range-test/), [Bern GIS mapping guide](https://bern-radio.onrender.com/gismapping.html)).
- **Uplink SNR via traceroute** (`snr_towards`), which the official clients already expose per hop.
- **Zero-config passive wardriving of the existing mesh.** The MeshMapper model for MeshCore ([App Store](https://apps.apple.com/app/id6758073991), [WebClient](https://tomevault.io/tome/MeshMapper/MeshMapper_WebClient)). Meshtastic has no good iOS equivalent; this is the real gap the app could own (M5).
- **Prediction vs measurement overlay.** People plan with the Site Planner and want to validate it ([article](https://adrelien.com/meshtastic-coverage-simulation-official-app/)). Importing a Site Planner GeoTIFF/KML as a layer next to measured dots would be a killer feature.
- **Airtime etiquette that matches the docs:** 30 s beacons on LongFast, beacon off after testing, the 8-hour auto-off ([Linux Magazine](https://www.linux-magazine.com/Issues/2025/299/Meshtastic/(offset)/12)).

### What would make the community distrust it
Silently reconfiguring and renaming a public router (M4). Airtime claims that ignore retransmissions (S2). A private repo while bundling GPL protos. "Meshtastic_" in the screenshots (N1). MeshCore support behind Pro (some grumbling for a GPL app; fine if the free tier is clearly useful).

### "This dev doesn't really understand Meshtastic" tells
The node list without hops, SNR or battery (S8). The fallback comment claiming 2.7 doesn't know presets that are in its own vendored protos (S1). The ping "SNR" that is really the downlink (M3). Everything else shows real firmware reading.
