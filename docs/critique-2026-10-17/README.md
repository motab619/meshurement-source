# Mesh Analyzer product critique — 2026-10-17

Five independent read-only reviews of `field-build-oct17` (HEAD `4f342fc`), each from a different seat, plus my own verification of the headline claims. The 2026-10-16 audit covered compliance, security and crash bugs; this one is about whether the *product* is right for mesh people and whether a design-minded person would respect it.

| Report | Lens | Headline |
|---|---|---|
| [meshtastic-power-user.md](meshtastic-power-user.md) | Eagle-eyed Meshtastic enthusiast | Base beacon dies after 8 h unnoticed; pings never measure the uplink; Radio Setup knocks a real router off the mesh; no listen-only mode |
| [rf-measurement.md](rf-measurement.md) | Drive-test / propagation engineer | Map and estimate are built from successes only, so dead zones become coverage; SNR colour scale ignores the preset floor |
| [design.md](design.md) | Senior iOS product designer | Stale, debug-panel store screenshots; three status surfaces that disagree; Start is a form; no end-of-session moment; Radios needs a home |
| [data-export-backups.md](data-export-backups.md) | GIS / data power user | CSV timestamps have no timezone; base position is a pref, not data; CSV-only per-session export; backups unfiltered and unimportable |
| [community-competitive.md](community-competitive.md) | Community and market researcher | **Firmware 2.8 removes Range Test entirely**; community wants passive one-radio surveys, KML/GeoJSON, adaptive pinging; the subscription model (not the price) is the friction |

Items marked ✔ I re-checked myself in the code or at the source.

---

## 1. The one that changes the roadmap

✔ **Meshtastic firmware 2.8 compiles the Range Test module out of every build.** PR meshtastic/firmware#11150 ("Always exclude range test", merged 2026-07-22) sets `MESHTASTIC_EXCLUDE_RANGETEST=1` globally and reports `RANGETEST_CONFIG` in `DeviceMetadata.excluded_modules`. Issue #8438 was closed 2026-09-03: "Range Test bugs and feature requests are not being worked on." 2.8 is still alpha; 2.7.26 is the current beta.

Mesh Analyzer's "base → you" direction *is* the Range Test sender. On 2.8 the base will accept the module config, send nothing, and the app will draw an honest-looking "out of range" map. Nothing in `lib/` reads `excluded_modules`, and the listing pins "firmware 2.7.x".

Two reviewers converged on the replacement, and it is a better product anyway:

- **Traceroute to the base (TRACEROUTE_APP = 70, already in constants).** `RouteDiscovery.snr_towards` is the SNR *the base heard you at*; `snr_back` is the return. One exchange gives both directions as numbers, which the app does not have today (see §2). Rate-limit to one per 30–60 s.
- **The ping ACK's own rx SNR** already gives a base → you sample on every delivered ping, at zero extra airtime.
- **A fixed-interval position/telemetry broadcast from the base** on the private channel as the passive beacon.

Detect 2.8 via `excluded_modules` (bit `0x0010`) and switch modes automatically; until then keep Range Test as the 2.7 path. The community has already moved: MeshMonitor dropped its active range-test replacement for a passive, zero-hop coverage report.

---

## 2. Measurement honesty (where an enthusiast would catch you)

1. ✔ **Only successes reach the map and the estimate.** Missed beacons and timed-out pings produce no sample; IDW paints between two good dots 400 m apart even if 15 beacons were lost between them. Where you *didn't* hear is the finding in drive testing. Record misses as explicit samples, never interpolate across a bin with losses, draw misses hollow. (rf M1, mesh S4)
2. ✔ **The Range Test `seq N` payload is thrown away** (`packet_processor.dart:187`), so beacon delivery ratio vs distance, the number every range tester quotes, cannot be computed. It also distinguishes "out of range" from "beacon stopped". (rf M4, mesh S4, data M2)
3. ✔ **"Pings (you → base)" is round-trip delivery, not an uplink measurement.** The SNR stored with an ACK is measured by the mobile, so it is base → you again. The firmware's ReliableRouter also retries a want_ack DM up to 3 times, so "delivered" is ARQ-assisted. Rename the layer, record attempt count, and get real uplink dB from traceroute. (rf M3, mesh M3)
4. ✔ **SNR of exactly 0.0 dB is stored as null** (`meshtastic_radio.dart:123`, `:1012`). SX126x SNR is quantised at 0.25 dB and 0.0 is a normal marginal reading; every such packet goes grey and drops out of medians and IDW. Use `rxRssi != 0` as the validity flag. Trivial fix, real bias. (rf I1, mesh M2)
5. **One fixed SNR colour ramp for every preset, three legends that disagree, and "Lost" at −20 dB on a received packet.** LoRa demod floors run from about −7.5 dB (SF7) to −20 dB (SF12). Colour by **link margin = SNR − floor(SF)** from the session's stored preset, one shared legend component. The demo data (MEDIUM_FAST, SF9) shows SNR down to −21, which is below the floor and will make a LoRa-literate tester distrust the app on sight. (rf M2, design M10)
6. ✔ **Pings go out with the radio's hop limit (3) and no `hopLimit` on the packet**, and ACKs bypass the relay filter. Every install shares one frequency slot because the channel name "MeshTest" is constant, so another user's base or any ALL-mode node on that slot can relay your pings. Send pings with hop_limit 0 (as the firmware's Range Test does), set `rebroadcast_mode = LOCAL_ONLY` on both test radios, apply the `hops > 0` policy to ACK rows, and salt the channel name per install. (mesh S3, rf I3)
7. **Airtime budget ignores retransmissions.** Out of range, one ping is up to 4 transmissions, so the "5%" figure is optimistic by about 4× exactly where testers push. Budget worst case or back off after N consecutive timeouts. Default the beacon to 30 s on Long presets, per the official docs. (mesh S2, rf I5)
8. **Position tagging uses `lastPosition` at processing time, not `rxTime`**, with a 2-minute stale window and no fix-age or accuracy gating. At 25 m/s a 90 s-old packet lands 2.2 km off. (rf I2)
9. **Statistics without sample sizes.** Winner declared on a 5-point gap with no minimum n; fixed 0/300/500/700/1000 m bands tuned for one 1 km walk; "farthest ACK" is one lucky packet; rig deltas count IDW-smoothed cells as independent evidence; medians over raw packets are dominated by dwell time near the base. Bin spatially first, show Wilson/bootstrap intervals, say "not enough data" when n is small. (rf M6, M7, I4)
10. **Terrain calibration fits only received packets** (survivorship bias) on RSSI alone (floor-compressed below SNR 0). Fit RSSI + min(SNR, 0), label the RMSE as "fit error of bin means". (rf M5)
11. ✔ **The EU presets table is incomplete, but not for the reason first claimed.** Correction after checking firmware source (2026-10-18): firmware 2.7.26's `modemPresetToParams` (`src/mesh/MeshRadio.h:132-181`) has no case for LITE_FAST/LITE_SLOW/NARROW_FAST/NARROW_SLOW, so on 2.7 they really do run as LONG_FAST; the old code comment was right. The real parameters arrive in 2.8.1 (`MeshRadio.h:265-284`: LITE 9-10/125 kHz/4-5, NARROW 7-8/62.5 kHz/4-6). NARROW_SLOW is *shorter* on air than LONG_FAST (4.096 ms vs 8.192 ms symbol), not 4× longer. Still true: LONG_SLOW is deprecated yet first in `testPresets`; SHORT_TURBO (500 kHz) is offered in EU_868 where the sub-band is 250 kHz; LONG_TURBO is never offered; EU_866/EU_N_868 regions are selectable but their presets were not modelled. Fixed on branch `fix/eu-presets` (per-region preset lists from the 2.8.1 PRESETS_* tables). Open: radios on 2.7.26 have no EU_866/EU_N_868 region at all and would fall back to the UNSET (US) frequencies; the region picker should hide those regions below 2.8. (mesh S1, corrected)

---

## 3. What a Meshtastic person will say in the first hour

- ✔ **The base beacon silently stops after 8 hours.** Firmware `RangeTestModule.cpp` disables the sender after 28,800,000 ms from boot, and only sends while channel utilisation is under 25%. Radio Setup's commit reboots the base, so "set up tonight, walk tomorrow" yields zero beacons and a convincing dead map. Show "beacon on until HH:MM", detect "pings ACKed but no seq for 3 intervals", offer "Stop base beacon" at session end. Moot once §1 lands, urgent until then. (mesh M1)
- **Radio Setup takes the user's real node off the mesh**, replaces all 8 channels, changes the preset and renames it "MeshTest Base", and it stays that way until a manual Restore buried at the bottom of a Settings sub-screen. The buyer most likely wants to know how far *their roof router* reaches. Expect "this app knocked my router off the mesh" posts. Say it plainly before Apply; show a persistent "in test mode since <date>, restore?" banner on connect; make "Put this radio back the way it was" a primary action. (mesh M4, design M7, data §3B)
- **You cannot survey your existing mesh, even passively.** `startSession` refuses on a public channel, but a receive-only session transmits nothing. Logging zero-hop NodeInfo/position/telemetry from your own router while driving is the number one coverage use case, costs no airtime, needs no second radio, and is where MeshMapper and MeshMonitor live. A "Listen-only" session type with pings hard-disabled is the single biggest onboarding unlock. (mesh M5, research gap 6)
- **The node list is thin**: name, hardware, last heard. No hops (already parsed into `RadioNode.hopsAway`), SNR, battery, role, `!nodeid`, distance or key status. Reads as unfamiliar with Meshtastic. (mesh S8)
- ✔ **"Meshtastic_e4ea" is in the store screenshots** (`demo_seeder.dart:287`), which puts the trademark in primary marketing. Raw `MEDIUM_FAST` enums too. (mesh N1, research §9)
- Firmware version is read but never shown or used; "Clear nodes list" wipes the whole NodeDB including keys with a soft warning. (mesh S6, S7)

---

## 4. Design

The design reviewer's full IA proposal is in [design.md](design.md). The parts that matter most:

- **The six store screenshots are from 2026-10-13 and show a UI that no longer exists** (four tabs, old Radio Setup, no base status bar). The hero shot's dominant element is a six-line monospace debug readout. Recompose around the story: base pin + track + "Hearing the base · 3 s ago"; the Pings layer; the Live Activity on a lock screen; comparison; Radio Setup as a success state.
- **The Live map never shows where the base is, where you walked, or where pings failed**, and has no scale bar. Add a base glyph with a distance line, a track line (dashed red where the base was silent), ping rings (filled/hollow).
- **Three status surfaces say the same thing in three vocabularies** (pill badge, BaseStatusBar, readout card). Merge into one HUD band with 28–34 pt numerals, a staleness age, and a last-8 ping strip; the pill goes back to being just BLE state.
- **Start is a form; End is nothing.** One-tap "Record" with an editable summary; a post-session summary sheet (duration, farthest heard, ping %, mini map, name, export) is the screen people screenshot and share.
- **Radio Setup is a 768-line scrolling form mixing status, config, actions, log, tips and backups**, reachable only from Settings. Split into a Radios hub (base card, mobile card) plus a 4-step wizard that says what will change before it changes it. Promote **Radios** to a tab.
- **Settings is a junk drawer.** Colour metric, direction and relayed toggles belong in a map Layers sheet; antenna heights belong on the rig and the map's base; ping interval belongs on the Start sheet; Pro belongs at the top of Settings, not only in About.
- **No haptics anywhere in `lib/`**, alerts are not time-sensitive (a Driving Focus silences them), keep-screen-on defaults off. Add a Geiger-tick audio option for driving.
- Material 3 widgets on iOS read as an Android port; dark-only theme with bright beige tiles washes out in sun.

---

## 5. Data, export and backups

- ✔ **CSV timestamps are local time with no offset at whole-second resolution** (`csv_export_service.dart:75`). QGIS and Google Earth will misread them. Export UTC ISO 8601 with `Z`, plus `unix_ms`.
- **The base position is a SharedPreferences entry, not data**, never snapshotted on the map or session, never exported; distance stats silently change when the base node's position updates. The CSV has no base lat/lon, distance or bearing. Promote it to columns on `coverage_maps` and `sessions`.
- **Export is per-session CSV only**: no KML, GeoJSON or GPX, no per-map or all-data export, no archive/import, files invisible in Files. A map with 12 sessions is 12 share sheets, and there is no way to move data to a new phone except iOS backup, which sits badly next to "never hold data hostage". Full proposed column list and formats in [data-export-backups.md §3A](data-export-backups.md).
- **Node identity in the export is a mutable display name**; re-exporting after Radio Setup renames changes the data. Always export `!hex` and node num.
- **Sessions have no rename, delete, move, trim or notes**, and Radio Setup can change the preset mid-session while the session keeps the old `loraPreset`.
- **Backups (your hunch, confirmed by all three reviewers who looked):** one flat newest-first list of every radio ever connected, four actions per tile, Restore greyed for non-connected radios with no reason given, every Restore → Setup cycle adds a duplicate "Before Radio Setup" copy, no import. Consensus design: group by node, connected radio on top, the earliest pre-setup backup pinned as **"Original settings"** and never pruned, dedupe by comparing protobuf bytes, auto-prune the rest, one primary **"Put this radio back the way it was"** action with a diff in the confirm dialog, "Connect to X to restore" instead of a dead button, Share/Copy-link/Delete in an overflow menu, and a registered document type so a shared backup file can be opened back in.

---

## 6. Market and positioning

- **The price is not the friction; the model is.** $6.99/yr is cheap next to Gaia ($39.99) or Strava ($79.99), but every other tool in the mesh space is free and OSS, MeshCore's £8 licence drew "deal killer" comments, and most Pro features (rig comparison, placement, PDF, MeshCore) are on-device with no recurring cost. Expect "another subscription for a hobby tool".
- **Lifetime-only-via-offer-codes will leak.** The product ID and $18.99 price are in a soon-to-be-public GPL repo. Once people learn a lifetime SKU exists but is not for sale, it reads as gatekeeping. Sell it openly next to yearly.
- **MeshCore behind Pro is the most likely flashpoint**: every MeshCore iOS option is free, including MeshMapper, which the roadmap uses as the reference implementation.
- **Offline maps behind Pro** while the free official app ships them with terrain.
- **"Adds no traffic to the public mesh" is false in EU_868**, where there is effectively one frequency slot; a private key does not create private airtime. 15 s ping + 15 s beacon is twice the docs' 30–60 s. Say what is true: nothing on the public channel, airtime shown live, duty-cycle budget enforced.
- **Differentiators to lead with:** the safest test setup in the ecosystem (exactly where Meshtastic itself is heading: Android 2.8 refuses Range Test on the default channel); real two-way dB between your own radios once traceroute lands; measured + predicted in one place ("Site Planner said −110, you measured −118"); on-device, no account, GPL; the iOS CSV export the official app declined to build (Meshtastic-Apple #803, closed "not planned").

---

## 7. Suggested order

1. **Decide the 2.8 strategy now** (traceroute + ACK rx SNR + passive base broadcast, gated on `excluded_modules`). It fixes §1, gives real uplink dB (§2.3), and removes the 8-hour trap (§3). Everything else is polish on a feature that is about to stop working.
2. **Cheap correctness wins in one PR:** SNR 0 → valid; parse `seq`; hop_limit 0 on pings; relay filter on ACKs; EU presets; UTC timestamps; `!hex` node ids in CSV; demo radio rename.
3. **Link-margin colouring and a loss layer** (misses as samples, hatch bins with losses, one legend).
4. **Listen-only sessions on any channel.** Biggest onboarding unlock and the community's preferred method.
5. **Backups redesign + "Restore original" as a primary action + explicit "this radio leaves your mesh" copy.** Trust.
6. **Store screenshots, HUD band, one-tap Record, end-of-session summary, Radios hub.**
7. **Export: GeoJSON/KML, per-map and all-data, base position as data.**
8. **Revisit the Pro split:** sell lifetime openly, consider MeshCore collection free, keep subscriptions for what actually recurs (satellite tiles, AI, sync).
