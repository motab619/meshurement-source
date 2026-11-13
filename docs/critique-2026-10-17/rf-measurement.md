# Mesh Analyzer: measurement methodology review (RF field-test view, 2026-10-17)

Reviewer lens: skeptical drive-test / propagation measurement engineer. Scope: the measurement path (radio → PacketProcessor/ActiveProbe → DB → map, charts, estimate, comparisons, CSV) and the six App Store screenshots. Items already in the 2026-10-16 audit are only mentioned where they change a measurement conclusion.

---

## 1. What the app gets right

- **Relayed packets are excluded by default, and the code says why.** `packet_processor.dart:148-158` drops `hops > 0` because last-hop SNR describes the relay. Few hobby tools do this.
- **Replayed and stale packets are dropped** (`packet_processor.dart:139-146`, `radio_types.dart:183`).
- **The two directions are labelled.** "Signal (base → you)" / "Pings (you → base)", "Signal from base", polar plot "Base signal (SNR)" (`range_polar_plot.dart:24`).
- **Ping bookkeeping is clean.** Registered before send, matched on `requestId`. Throttled pings are left out of the denominator (`range_stats.dart:339`). Implicit (relay) ACKs are counted separately and not treated as success (`range_stats.dart:340-344`).
- **Robust statistics in most places.** Medians for dB values (`rig_comparison.dart:82`); "flattered by pings within 200 m" warning (`range_stats.dart:593`); "routes barely overlap" caveat; same-map rule; preset-mismatch warning; rig snapshot per session.
- **The estimate is honestly badged.** "Estimated — not measured" chip (`coverage_map_detail_screen.dart:1047`), fades to transparent 300 m from data, terrain fit RMSE displayed. Terrain maths is textbook: k = 4/3, ITU-R P.526 J(v), Deygout capped at 3 edges and 50 dB; `los_verdict.dart` avoids calling every flat Fresnel graze "blocked".
- **The airtime model is correct.** Semtech formula, 16-symbol preamble, explicit header, CRC on, LDRO when Tsym > 16 ms (`airtime_model.dart:68-79`), matching RadioLib. The preset table in `meshtastic_presets.dart` matches firmware 2.7's `modemPresetToParams`. Radio-measured channel utilization / air_util_tx are captured next to the app's estimate.
- **Charts break the line across silences** (`signal_charts_panel.dart:383`), and GPS horizontal accuracy is stored on every event.

---

## 2. Findings, ranked

### M1 — MISLEADING: the map and the estimate are built only from successes, so dead zones become coverage
**Where:** `coverage_map_detail_screen.dart:287-295`, `coverage_interpolation.dart:215-226` (IDW over received samples only, alpha 1 to 50 m, fading to 0 at 300 m from the nearest *received* sample), `terrain_coverage.dart:207-209`.

A missed beacon or a timed-out ping produces no sample. Two good readings 400 m apart along a road paint the 400 m between them in a blended colour at 60-100% alpha, even if 15 consecutive beacons were lost there. Ping timeouts exist in the DB but never feed the Signal layer or the estimate. This is the classic drive-test error, and it overstates coverage exactly at the edge.

**Fix:** treat expected-but-missing beacons (M4) and ping timeouts as explicit "no link" samples. Render a delivery-ratio (PDR) layer per 50-100 m bin, or at least hatch/grey bins with losses. Never interpolate across a bin with recorded misses. Draw misses as hollow or × markers.

### M2 — MISLEADING: one fixed SNR colour scale for every preset, three inconsistent legends, and a received packet labelled "Lost"
**Where:** `signal_color_mapper.dart:14-19` (ramp −20 to +15 dB, so yellow = −2.5 dB); `signal_legend.dart:19-24` (Strong 10 / OK 0 / Weak −10 / **Lost −20**); `coverage_map_detail_screen.dart:1143-1150` ("SNR ≈ 0" painted with the −2.5 colour, "≤ −15" with the −20 colour, "RSSI ≥ −70" with the −60 colour); `constants.dart:75-79` (`snrExcellent/Good/Fair/Poor` defined but unused).

LoRa demodulation floors by SF: about −7.5 dB (SF7), −10 (SF8), −12.5 (SF9), −15 (SF10), −17.5 (SF11), −20 (SF12). On SHORT_FAST a "Weak" −10 dB packet is already below the floor; on LONG_FAST it has 7.5 dB of margin. "Lost" at −20 dB labels a packet that was received. The demo data is implausible: screenshot 05 is MEDIUM_FAST (SF9, floor −12.5) yet shows "SNR −21.0…11.3". A tester who knows LoRa will distrust the app on sight.

**Fix:** colour by **link margin = SNR − SNRmin(SF)** from the session's `loraPreset`. Legend in dB of margin, showing preset and floor. One shared legend component generated from `SignalColorMapper`. Fix the demo walk so SNR never sits more than about 2 dB below the floor.

### M3 — MISLEADING: "Pings (you → base)" is not an uplink measurement
**Where:** `active_probe_service.dart:288-305`, `meshtastic_radio.dart:1012-1015`, `range_stats.dart:139-141`, `range_comparison_section.dart:336`.

A ping succeeds only if the uplink DM **and** the downlink ACK both survive: round-trip delivery, not you → base. The firmware's reliable router retransmits want_ack DMs (up to 3 attempts) before NAKing, so "delivered" can be the third try: ARQ-assisted delivery, systematically higher than single-packet PDR. The SNR/RSSI stored with the ACK is measured *by the mobile*, so it is base → you again. The app never measures the uplink as a quantity.

**Fix:** rename the layer "Round trip (you ⇄ base)". Record attempt count, or flag round-trip times above about 1.5× one-shot airtime as "retried"; report first-attempt success separately. For true uplink SNR, use Meshtastic **traceroute** (port 70): `RouteDiscovery.snr_towards` is the SNR the base measured for your request, `snr_back` the return. Mind the firmware rate limit; one every 30-60 s is enough.

### M4 — INCOMPLETE: no beacon delivery ratio; the Range Test sequence number is thrown away
**Where:** `packet_processor.dart:187-190`. The payload ("seq N") is never parsed; no seq handling anywhere in `lib/services` or `lib/ui`.

Seq gaps give exact expected-vs-received counts, the single most important coverage metric and the input M1 needs.

**Fix:** parse seq into a new column. Synthesise "missed" rows (time-interpolated GPS) for gaps while the BLE link was up. Show PDR in the session tile, charts, distance bands and a map layer. Export it.

### I1 — INACCURATE: SNR of exactly 0.0 dB is recorded as "no data"
**Where:** `meshtastic_radio.dart:123` and `:1012` (`packet.rxSnr != 0 ? … : null`).

SX126x SNR is quantised at 0.25 dB; 0.0 dB is a common valid mid-range reading. Every such packet loses its SNR: grey on the map, excluded from IDW, medians and rig deltas. Biases statistics away from the midpoint.

**Fix:** use `rxRssi != 0` as the "radio measured it" flag for both values.

### I2 — INACCURATE: position tagging can be off by kilometres when driving
**Where:** `packet_processor.dart:139` (accepts packets up to 2 min old by `rxTime`), `:193-197` (tags with `lastPosition` and `DateTime.now()`, not `rxTime`), `gps_service.dart:233-246` (no fix age; `distanceFilter: 5`), `active_probe_service.dart:288` (ACK row gets the position at ACK time; round trip up to 30 s).

A packet 90 s old at 25 m/s is plotted 2.2 km from where it was heard. Under GPS loss every packet inherits the last fix indefinitely. `gpsAccuracy` is stored but never used to filter, weight or flag.

**Fix:** interpolate the GPS track at `rxTime` (short position ring buffer). Cut the stale window to a few seconds or make it speed-dependent. Drop or flag samples with fix age > 5 s or accuracy > 25 m; render low-accuracy dots hollow. Record speed and course.

### M5 — MISLEADING: the terrain calibration fits a censored, floor-compressed sample
**Where:** `coverage_calibrator.dart:114-167`, `terrain_coverage.dart:209`, `coverage_map_detail_screen.dart:503-504`.

- **Survivorship bias.** Only received packets are fitted. Near the edge only fading-high packets get through, so the fit is biased optimistic (Tobit/censoring).
- **Floor compression.** SX126x packet RSSI includes noise, so below about SNR 0 it flattens near the noise floor (screenshot 02: RSSI about −112 while SNR swings 0 to −20). Signal power ≈ RSSI + SNR when SNR < 0 is the usual correction.
- **Understated error.** The "±x dB" is in-sample RMSE on 100 m bin *means* (`terrain_coverage.dart:146-176`), averaging away the 6-8 dB of fast fading a single packet sees.

**Fix:** fit to signal power (RSSI + min(SNR, 0)). Include misses as censored observations, or report the fraction of misses inside the footprint. Label the RMSE as "fit error of bin means" and add a per-packet spread.

### M6 — MISLEADING: the distance-band preset comparison is tuned for one 1 km walk and declares winners without a sample size
**Where:** `range_stats.dart:21-36` (fixed bands 0/300/500/700/1000 m, headline band 300-1000 m), `:510-525` (winner on a 5-point gap, no minimum n), `:372-379` (`farthestAck` single max, `firstMiss` single min), `range_polar_plot.dart:14` (fixed 250 m rings).

A rooftop base reaching 8 km dumps nearly everything into "1000+ m"; the polar plot would draw 32 rings. 2/3 vs 1/3 pings in a band "decides" a winner. "Farthest ACK" is one lucky packet.

**Fix:** data-derived bands (quantiles or log-spaced). Require n ≥ 20 per band, show Wilson 95% intervals, call a winner only when they separate. Replace farthest/first-miss with "distance where binned PDR falls below 50%" (logistic fit against log distance). Scale ring step to extent.

### M7 — MISLEADING: rig comparison counts interpolated cells as evidence and compares SNR across presets
**Where:** `rig_comparison.dart:92-131`, `:171-196`, `rig_math.dart:191`, `rig_comparison_screen.dart:184-195`.

- Delta comes from IDW-smoothed grids (50 m cell, 75 m match radius); one reading influences about 7 cells, so "Compared cells" overstates independent evidence. No CI; the 3 dB threshold is inside single-packet fading spread.
- SNR is not gain-transparent: saturates near the base (about +10 to +13 dB on SX126x); in noise-limited settings a higher-gain antenna raises noise too.
- Mixed presets are only a warning, yet SNR shifts about 3 dB per bandwidth halving before any hardware difference.
- `RigSpec` has no **TX power**; per-board RSSI calibration differs by several dB (T1000-E vs Heltec V3). Body loss and orientation not captured. No filter by source node or hops.

**Fix:** paired raw samples (nearest neighbour within about 25 m, one pair per bin). Median delta with bootstrap 95% CI and number of independent bins. Use RSSI + min(SNR, 0); refuse SNR deltas across bandwidths. Add TX power and radio model to the expectation.

### I3 — INACCURATE: ping ACKs bypass the relay filter
**Where:** `active_probe_service.dart:268-305`, `meshtastic_radio.dart:1000-1004`.

`received` is assigned whenever `packet.from == target`, whatever `hops` is. The ACK row (with the relay's last-hop SNR) is shown on the Signal layer, fed to the estimate and included in the median SNR (`range_stats.dart:384-388`). `hopStart == 0` is also treated as direct (`meshtastic_radio.dart:139`).

**Fix:** apply the `hops > 0` policy to ACK rows. Count a relayed ACK as "delivered via relay". Use `relay_node` (firmware 2.6+) to confirm the last hop was the base.

### I4 — INCOMPLETE: dwell-time and sampling bias in the summary statistics
**Where:** `coverage_map_detail_screen.dart:967-1013`, `range_stats.dart:382-388`.

Medians over raw packets, so 10 minutes next to the base dominates "median SNR". The session tile uses `snrs[n ~/ 2]`, the upper median. "SNR min…max" are extreme-value statistics.

**Fix:** one sample per spatial bin (or per bin and minute) before medians and percentiles. Show P10/P50/P90.

### I5 — INACCURATE: the airtime budget ignores retransmissions and self-interference
**Where:** `airtime_model.dart:118-120` (`dutyFor`), `:107-110` (`fastestIntervalSecFor`).

The duty figure assumes one transmission per ping. Out of range, each ping costs up to 3 airtimes plus retries. "Fastest" mode allows 2 × airtime + 1 s spacing while the ACK timeout is 30 s. Both ends are half-duplex: while the mobile transmits it cannot hear the beacon, and the base cannot receive while beaconing, so aggressive pinging lowers the beacon PDR you are measuring.

**Fix:** count observed attempts (or apply 3× worst case) in the HUD duty figure. Disallow intervals below one ACK round trip. Note that pings and beacons contend.

### I6 — INCOMPLETE: CSV export is not analysis-grade
**Where:** `csv_export_service.dart:35-100`.

`timestamp` is local with no UTC offset, second resolution. Missing: node id, `meshPacketId`, `channelIndex`, Range Test seq, radio `rxTime`, ping↔ACK link, ACK hops and responder, distance and bearing to base, base position, speed and course, fix age, region and frequency, TX power, firmware, antenna heights. The "matching Meshtastic range test convention" comment is not accurate.

### N1 — NIT: smaller items
- `PathLossModel` defaults to 915 MHz (`path_loss_model.dart:75`); fall back to the region's centre frequency.
- Default base height 2 m (`coverage_calibrator.dart:93`) under-predicts a mast base. Prompt for it.
- Elevation source is SRTM-class 30 m with no clutter; say so in the LOS verdict.
- `_maxGap` of 2 min (`signal_charts_panel.dart:310`) bridges 7 missed beacons at 15 s. Tie it to about 2.5× the interval.
- "Large dot: direct · small: relayed" (`signal_legend.dart:106`) describes a state that is off by default.
- `estimateBase` averages start and end points (`range_stats.dart:99-124`); distance stats inherit tens of metres of error.

---

## 3. Measurement features serious testers will expect

1. **Beacon PDR from sequence numbers**, per bin and distance band.
2. **Link margin rather than raw SNR**, per preset.
3. **True uplink SNR via traceroute** (`snr_towards`/`snr_back`), showing link asymmetry.
4. **Explicit "miss" markers and a loss layer.** Where you didn't hear is the finding.
5. **Sample quality gating**: fix age, accuracy, speed, stale-packet window of seconds.
6. **Spatial binning with percentiles and confidence intervals**; "not enough data" instead of a headline when n is small.
7. **Signal-power estimate** (RSSI + min(SNR, 0)) for calibration and rig deltas.
8. **A/B protocol helpers**: same route, alternating order and direction, paired delta with bootstrap CI, TX power and radio model in the rig.
9. **Noise-floor and interference context**: channel utilisation per sample, RSSI on packets with SNR < 0.
10. **Full-fidelity export**: UTC ms timestamps, node and packet ids, seq, `rxTime`, hops and `relay_node`, ping↔ACK linkage, distance to base, session sidecar.

Bottom line: the plumbing is careful, but what reaches the user shows only successes. Until misses, link margin and the real uplink appear on the map, the coverage picture is optimistic in exactly the places a tester cares about.
