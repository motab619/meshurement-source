# Mesh Analyzer: competitive and community research report (2026-10-17)

*Limitation: Reddit refused fetches and the Meshtastic Discourse did not resolve, so community sentiment comes from GitHub issues, project wikis, App Store reviews, Lemmy/feddit threads and practitioner blogs. Read "community wants" as indicative, not a survey.*

---

## 0. The headline: Meshtastic firmware 2.8 removes Range Test

Meshtastic **compiles Range Test out of every firmware 2.8 build** (`MESHTASTIC_EXCLUDE_RANGETEST`, firmware PR #11150, merged 2026-07-22). The firmware reports the missing module in `DeviceMetadata.excluded_modules`. The core maintainer closed the open Range Test issues on 2026-09-03 ("Range Test bugs and feature requests are not being worked on") and said on Discord "Range test is totally gone in 2.8." 2.8.0/2.8.1 are still alpha; 2.7.26 beta is "Latest", but 2.8 will ship.

Mesh Analyzer's "base → you" direction depends on the base being a Range Test sender. When people update to 2.8, half the headline feature stops working without any error. The listing pins "firmware 2.7.x". Nothing in `lib/` reads `excluded_modules`.

**What the community moved to:** MeshMonitor dropped its planned active Range Test replacement and built a **passive** coverage report fed by smart-position zero-hop packets. A contributor called sequence-text range tests "completely obsolete"; a Meshtastic collaborator said "logging using smart positioning is the preferred approach now."

**Fix options:** (a) take the "you hear base" sample from the rx SNR/RSSI of the ping ACK (already travels base → mobile); (b) **TRACEROUTE_APP (70)** to the base: `RouteDiscovery` carries `snr_towards` and `snr_back`, both directions in one exchange; (c) a fixed-interval position/telemetry broadcast from the base on the private channel. Detect 2.8 through `excluded_modules` and switch automatically.

---

## 1. Competing and adjacent tools

| Tool | What it is | Price / model | What users praise or complain about |
|---|---|---|---|
| **Meshtastic iOS app** (official) | Full client. Watch app, CarPlay (2.7.11), offline basemaps with terrain (2.7.17/2.7.20), **Site Planner coverage overlay in-app** (2.7.18). Range Test config only. | Free, 4.1★ / 827 | Complaints: slow CarPlay, BLE crashes. **iOS cannot export range-test CSV**: Apple issue #803 closed "not planned" (2025-07-18). |
| **Meshtastic Android** | Exports `rangetest.csv`. 2.8.x **blocks Range Test on the public/default channel** (PR #5986). | Free | Only official path to get a CSV off a phone. Guides assume Android plus Google Earth Pro. |
| **Site Planner** | SPLAT!/ITM Longley-Rice in WASM, SRTM 90 m (30 m option). | Free, OSS | No clutter. Docs say "always verify predictions… using real-world testing." Nobody publishes predicted vs measured: an opening. |
| **MeshMapper** (MeshCore) | Wardriving: BLE, GPS pings, community upload. Watch app, **Live Activities, Siri Shortcuts**, offline maps, **audio cues entering/leaving coverage**. Modes Passive / Hybrid / Active / Trace, **Smart Pinging**, auto-stop, regional admin TX slots. | Free, MIT (Flutter, iOS+Android), 4.4★ / 23 | Praise: "most well refined purpose built product." Complaints: "hard to use," missed ping responses, Google Play dependence. |
| **MeshCoreScanner** | Discovery scans, local-only, **GeoJSON export**. | Free | — |
| **mapme.sh** (HanseMesh) | Browser BLE, hex cells, leaderboard, privacy delay. | Free | "Like my own version of Pokémon Go." |
| **MeshMonitor coverage report** | Self-hosted, passive; median-SNR grid, "likely gap" lines, fixes heard vs expected, **CSV + GeoJSON**. | Free, OSS | Designed so the tool adds no airtime. |
| **Rangetest Mapper**, **barryhunter/rangetest** | Browser viewers for rangetest.csv. | Free | Exist because the official export-and-view path is painful. |
| **MeshTenna** | Antenna/location scoring from RSSI/SNR to a fixed node. | Free, MIT, **archived** | Demand for antenna A/B comparison; nothing maintained covers it. |
| **liamcottle meshtastic-map / meshmap.net** | MQTT node maps. | Free | "A node map shows you where devices are, not where the signal reaches." |

**Paid tools in this space are rare and get pushback.** No paid third-party Meshtastic iOS client found. MeshCore's £8 premium license drew "deal killer" comments. PommeCore monetises with a tip jar plus a **$1.99 one-time** Watch unlock.

---

## 2. What the community asks for

- **Get data off iOS and into Google Earth/GIS** (Apple #803; the ndoo.sg Google Earth Pro import workflow).
- **Automatic save/restore of radio settings around a test** (ndoo.sg toggles MQTT, position and range test by hand on both radios).
- **Hop data and RSSI in range-test logs** (firmware #967; #7731 because SNR saturates at about 11).
- **Antenna comparison** ("change one variable at a time… same route, same preset").
- **Heatmaps / grid summaries** (network-management-client #454; MeshMonitor's grid; MeshMapper squares; mapme.sh hexes).
- **Low or no airtime.** Passive modes, smart pinging, auto-stop. "Rather choose an option that does not transmit anything over the mesh."
- **In-vehicle use.** Audio cues, CarPlay. A car body costs about 40% of green squares.
- **Watch / Live Activity / Shortcuts.** MeshMapper and the official app set the bar.
- **Offline maps.** Free in the official app, with terrain.
- **Android.**

No evidence of demand for MQTT in a coverage tool; MQTT is seen as a spam source during tests.

---

## 3. Community sensitivities

- **Airtime.** Docs: Range Test "will use a lot of time on air, slow down your mesh, and spam your channel"; suggest 30-60 s. **A private channel key does not create private airtime.** In EU_868 there is effectively one frequency slot, so MeshTest shares the air with LongFast users. In the US "MeshTest" hashes to a different slot, so the claim is mostly true there.
- **Public channel.** Android 2.8 refuses Range Test on the default channel; firmware 2.8 clamps position precision on known keys. Mesh Analyzer's refusal matches the project's direction.
- **Trademark.** The policy forbids Meshtastic marks "in either the primary or secondary branding"; silent on "compatible with" wording. **No app holds a trademark grant.** The M-Powered logo is the sanctioned compatibility mark. Apple 2.3.7 rejections for trademarks in name or subtitle are common.
- **Open source.** The ecosystem is overwhelmingly free and OSS; closed or paid clients get criticised. GPL earns credibility, but anyone can build Pro for free from the public repo (`PRO_OVERRIDE`). Frame Pro as convenience and supporting development, not a lock.
- **Subscriptions.** Acceptable where costs recur (cloud, AI, tiles), resented on offline utilities.

---

## 4. Design expectations (outdoor/field-tool category)

- **Map-first, floating status, collapsible panels.** The opaque dark HUD over light tiles is the right pattern.
- **Contrast.** The app is **dark-theme only** (`Brightness.dark` in `app.dart`). A high-contrast light theme for midday would help. Small grey secondary text will wash out in sun.
- **Glanceable + eyes-free.** Live Activity is table stakes (MeshMapper has it). Watch apps are common (Strava and Komoot added offline Watch maps Jan 2026; MeshMapper and the official app have Watch apps). Audio or haptic cues are a proven win for drivers.
- **Offline-first.** onX, Gaia and the official Meshtastic app treat offline maps as core.

---

## 5. Pricing sanity

Comparables: Gaia GPS $39.99/yr; Strava $79.99/yr; MeshCore premium £8 one-time; PommeCore $1.99 one-time plus tips; everything else in the mesh tool space free.

**$6.99/yr is cheap. The price is not the friction; the model is.** Most Pro features (rig profiles, comparison, placement advisor, MeshCore, PDF report) are on-device with no recurring cost. Only satellite tiles and AI analysis recur; iCloud sync runs in the user's own storage. Expect "another subscription for a hobby tool" comments.

**Lifetime only via offer codes is risky.** The source is public GPL and the `pro.lifetime` product ID and $18.99 price are in the repo and roadmap. Once people learn a lifetime SKU exists but is not for sale, it reads as gatekeeping. Recommendation: **sell lifetime openly** (about $19-25) next to yearly.

**Gating MeshCore behind Pro** is the most likely to draw criticism. The MeshCore iOS options are free (MeshMapper, which the roadmap uses as reference, MeshCoreScanner, free clients). Consider making MeshCore collection free and gating only analysis.

---

## 6. Feature comparison

| Want / competitor feature | Mesh Analyzer |
|---|---|
| Live GPS-tagged SNR/RSSI map | **Has** |
| Both-direction measurement | **Has** (base→you depends on Range Test, **breaks on 2.8**). Per-direction SNR numbers: **missing** |
| Private-channel test setup + public-channel refusal | **Has** (stronger than any competitor) |
| Settings backup/restore around tests | **Has** |
| Airtime readout + channel utilisation | **Has** |
| Passive / no-TX mode | **Partial** (built around two radios and active pings) |
| One-radio survey of an existing mesh | **Missing** (MeshMapper and MeshMonitor do this) |
| Smart pinging / distance-gated / auto-stop | **Missing** |
| CSV export on iOS | **Has** (fills Apple #803) |
| KML / GeoJSON export | **Missing** |
| Hop count / relayed vs direct | **Has** |
| Traceroute / per-hop view | **Missing** |
| Preset comparison | **Has** |
| Antenna / rig comparison with dB deltas | **Pro** |
| Predicted coverage | **Has, free** |
| Predicted vs measured validation | **Partial** |
| Placement advisor | **Pro, not built** |
| Grid/hex summary | **Partial** |
| Live Activity / background / out-of-range alerts | **Has** |
| Audio/haptic cues | **Missing** |
| Apple Watch / Shortcuts / CarPlay | **Missing** |
| Offline maps | **Pro, not built** (free in the official app) |
| Share a map (image/link) | **Missing** |
| Community/shared maps | **Deliberately not built** |
| MeshCore | **Pro, not built** |
| Android | **Missing** (planned) |

---

## 7. Gaps most likely to matter (ranked)

1. **Firmware 2.8 Range Test removal.** Re-base "you hear base" on ACK rx SNR and/or traceroute before 2.8 goes stable. Gate on `excluded_modules`.
2. **No Android.** An iOS-only app with a paid tier looks boutique.
3. **Per-direction SNR numbers, not just ping success.** Traceroute gives this.
4. **KML/GeoJSON export plus a free "share map image."** Google Earth is the default viewer; screenshots are how results reach Reddit and Discord.
5. **Adaptive pinging** (distance-gated, auto-stop when stationary, back-off when solid). MeshMapper's main etiquette argument.
6. **One-radio mode.** The two-radio requirement is the biggest onboarding barrier.
7. **Offline maps behind Pro** while the free official app offers them with terrain.
8. **Driving ergonomics.** Audio cues, daylight theme, Watch or Shortcuts.

## 8. Differentiators to lean on

1. **Safest test setup in the ecosystem.** Exactly where Meshtastic is heading.
2. **Real two-way link measurement between your own radios.** Once fixed for 2.8 with dB both ways, nothing else offers this.
3. **Measured plus predicted in one place.** Be the verification Site Planner tells users to do ("Site Planner said −110, you measured −118").
4. **On-device, no account, GPL.**
5. **Native iOS polish:** Live Activity, background recording, alerts, the iOS CSV export the official app declined to build.

## 9. Risks

- **Trust and airtime.** "Adds no traffic to [the public mesh]" is not true in EU_868. 15 s pings plus a 15 s beacon is twice the docs' 30-60 s suggestion, so "conservative" invites pushback. Say what is true: nothing on the public channel; airtime shown live; interval limited by a duty-cycle budget.
- **Naming and trademark.** The name is clean, but **screenshots show "Meshtastic_e4ea"**. Rename demo radios; consider the M-Powered logo.
- **Pricing.** Subscription on offline features, hidden lifetime SKU, MeshCore behind a paywall. The AI narrative sends data to Anthropic, awkward next to "No cloud"; keep it opt-in and out of the headline listing.
- **Firmware churn.** 2.8 changes node numbers (derived from PKI) and makes position/telemetry opt-in. Watch `RadioRoles` node-number memory and `MeshtasticContacts`.

---

## 10. App Store listing critique

**Good:** "measurements instead of predictions" fits what Site Planner users are told to do. Two-radio requirement stated plainly. Private-channel, no-account, GPL and trademark disclaimer all good. Keywords avoid "meshtastic."

**Fix:**
1. "firmware 2.7.x" will date fast and hides the 2.8 break.
2. "adds no traffic" / "conservative 15 second interval": reword; show the airtime number.
3. Pro section describes billing but not what Pro includes; list only shipped items.
4. Disclose demo data in a caption.
5. Screenshots: remove "Meshtastic_e4ea"; "Medium Fast" not `MEDIUM_FAST`; captions ("Hear the base / Does the base hear you").
6. Subtitle lacks a searchable term: "LoRa mesh range, mapped live" (28 chars).
7. One line each on MeshCore and Android status.
8. Lead with the safety angle: "Never transmits on the public channel."

---

## Sources

- Range Test removal: https://github.com/meshtastic/firmware/issues/8438 · https://github.com/Yeraze/meshmonitor/issues/5031 · https://github.com/Yeraze/meshmonitor/pull/5458 · https://github.com/Yeraze/meshmonitor/issues/5277
- Firmware 2.8: https://newreleases.io/project/github/meshtastic/firmware/release/v2.8.0.47db0e3 · https://github.com/meshtastic/firmware/releases
- Android 2.8 Range Test block: https://github.com/meshtastic/Meshtastic-Android/releases · https://newreleases.io/project/github/meshtastic/Meshtastic-Android/release/v2.8.0-open.3
- Range Test docs: https://meshtastic.org/docs/configuration/module/range-test/
- iOS CSV export not planned: https://github.com/meshtastic/Meshtastic-Apple/issues/803
- Official iOS app: https://apps.apple.com/us/app/meshtastic/id1586432531 · https://github.com/meshtastic/Meshtastic-Apple
- Site Planner: https://github.com/meshtastic/meshtastic-site-planner · https://meshtastic.org/docs/software/site-planner/ · https://meshtastic.org/blog/meshtastic-site-planner-introduction/
- MeshMapper: https://apps.apple.com/app/id6758073991 · https://github.com/MeshMapper/MeshMapper_Flutter_App · https://wiki.meshmapper.net/app_wardriving_modes/ · https://hub.lorameshdevices.com/discussions/meshcore-wardriving-with-meshmapper · https://nodakmesh.org/blog/meshmapper-wardriving-coverage-guide
- MeshCoreScanner: https://apps.apple.com/bb/app/meshcorescanner/id6761951768
- mapme.sh: https://www.rblind.com/post/20663502
- Rangetest viewers: https://meshtasticmapper.com/ · https://github.com/barryhunter/rangetest
- MeshTenna: https://github.com/OE3JGW/MeshTenna · MeshPulse: https://github.com/maxg10/meshpulse
- MQTT maps: https://meshtastic.liamcottle.net/ · https://wiki.seeedstudio.com/meshtastic_node_map_l1/
- Practitioner workflows: https://ndoo.sg/projects:amateur_radio:meshtastic:range_testing · https://nodakmesh.org/blog/meshtastic-range-test-guide · https://meshcola.com/2024/10/31/how-to-use-range-test-in-meshtastic-for-optimal-network-coverage/ · https://www.sdrstore.eu/meshtastic-range-guide-how-far-lora-mesh-nodes-reach/
- Feature requests: https://github.com/meshtastic/Meshtastic-device/issues/967 · https://github.com/meshtastic/firmware/issues/7731 · https://github.com/meshtastic/Meshtastic-device/issues/671 · https://github.com/meshtastic/network-management-client/issues/454
- Forum threads (seen in search only): https://meshtastic.discourse.group/t/whats-the-best-way-to-test-and-compare-antennas/3294 · https://meshtastic.discourse.group/t/practical-range-test-results/692
- Trademark: https://meshtastic.org/docs/legal/licensing-and-trademark/ · https://meshtastic.org/docs/legal/trademark-grants/
- Apple 2.3.7: https://developer.apple.com/forums/thread/791158
- EU duty cycle: https://meshtastic.org/docs/overview/radio-settings/ · https://meshtastic.discourse.group/t/etsi-violations/2719
- MeshCore licensing: https://www.cnx-software.com/2025/07/19/meshcore-lightweight-alternative-to-meshtastic-for-lora-based-off-grid-messaging/ · https://hackaday.com/2025/12/06/lessons-learned-after-trying-meshcore-for-off-grid-text-messaging/ · https://mtlynch.io/first-impressions-of-meshcore/
- MeshCore iOS clients: https://apps.apple.com/app/meshcore/id6742354151 · https://apps.apple.com/us/app/meshcore/id6760626211
- Pricing: https://www.jmpeltier.com/best-hiking-gps-app/ · https://9to5mac.com/2026/01/28/apple-watch-offline-map-routes-debut-for-strava-and-komoot-apps · https://stora.sh/blog/2026-04-06-subscription-fatigue-one-time-purchases-comeback
- onX CarPlay: https://onxmaps.com/offroad/app/features/carplay
