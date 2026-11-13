# Meshurement: release prep and Pro roadmap

Owner: Andy (Plateau Nerd). Phased delivery with a confirmation gate after
each phase; one branch/PR per phase. Don't start the next phase until Andy
confirms. Last updated 2026-10-15 (delta: Pro subscription, radio
interface, MeshCore, offline packs, renumbered 1–9).

## Decisions

- **License:** GPL-3.0-or-later, source on GitHub: development repo
  github.com/motab619/meshurement stays private (its history has a personal
  email); public snapshots per release at github.com/motab619/meshurement-source
  (`tool/publish_source.sh`, from 2026-11-13).
  Required because the app includes the GPL-3.0 Meshtastic protobufs.
- **Trademark:** Meshtastic® is a registered trademark of Meshtastic LLC.
  Never in the app name, icon, splash or branding; factual compatibility
  wording only. The same goes for MeshCore. Andy applies for a trademark
  grant before App Store submission. App name: **Meshurement** (formerly Mesh Analyzer, renamed 2026-11-05).
- **Free tier:** everything in Phases 1–3: radio setup, all three
  collection modes, map, local SQLite storage, CSV export, airtime model,
  estimated (interpolated and terrain-aware) coverage layer. **Basemaps
  stay free** (decided 2026-10-16): Standard and Terrain tiles are
  self-hosted (pennies a month), so there is no cost to pass on and a
  blank map would make the free tier look broken. Only the metered
  imagery is Pro: see Phase 6.
- **Pro (decided 2026-10-15):** **$6.99/year** auto-renewing subscription (raised from $4.99 on 2026-10-17; lifetime non-consumable $18.99, offer codes only)
  through StoreKit 2, 1-week free trial. Unlocks iCloud backup/sync,
  hardware profiles and comparison, placement advisor, MeshCore support,
  offline map packs and the coverage report.
  - **Beta testers get lifetime Pro** with App Store **offer codes** for the
    `com.andybrunker.meshAnalyzer.pro.lifetime` non-consumable. That product
    is never offered for sale in the app; it exists only for codes.
    (Subscription offer codes can't be "lifetime"; non-consumable codes
    work from iOS 16.3.) Testers redeem in the App Store; no in-app
    redeem-code UI.
  - Custom offer codes need the app **Ready for Distribution** and the IAP
    **Approved**, so redemption can't be verified on TestFlight before
    launch. Before then, TestFlight purchases are sandbox (free) and code
    offers can be tried in Xcode StoreKit testing.
  - **No tip jar** (removed 2026-10-13; the delta's "tip jar stays" line
    was written against an older baseline).
  - `ProEntitlement` (`lib/services/pro_entitlement.dart`) is the only code
    that talks to StoreKit; every Pro gate asks it. Debug override:
    `--dart-define=PRO_OVERRIDE=true`.
  - Paywall: one screen, shown only when a Pro feature is tapped (plus the
    Pro row on About). No launch nags, countdowns or "limited time" copy.
    Restore Purchases, Apple's subscription terms, privacy policy and EULA
    links.
  - **Lapsed Pro:** all data stays; existing comparisons, reports and
    profiles stay viewable and exportable. Only creating new Pro items is
    gated. Never hold data hostage.
  - Unobtrusive, disclosed affiliate links for suggested hardware are OK
    (placement advisor site sheet only).
- **Airtime etiquette is a selling point:** private test channel, public
  channel disabled, no mesh relay, conservative ping intervals, live
  airtime readout.
- **Platforms:** iOS first. **Android soon after** from the same Flutter
  codebase; the BLE transport split (Phase 1c) is what makes it cheap. Mac
  later, maybe. Any PR that touches BLE or StoreKit notes what Android
  needs (BLE plugin behaviour, Google Play Billing).

## Don't build (unless explicitly reopened)

Ad/analytics/tracking SDKs; cloud uploads to Plateau Nerd servers;
community maps; team workspaces; multi-base merging; remote
reconfiguration of the base radio; anything that transmits on the
public/default channel (except Network Mode's passive capture and
traceroutes, decided 2026-10-22, docs/design/network-mode.md); **any in-app redeem-code system** (Apple offer
codes cover it). Offline map packs moved off this list (now Phase 6).

## Phases, by priority

| # | Phase | Tier | Status |
|---|---|---|---|
| 1 | Licensing, attribution, release hygiene, Pro subscription, MeshRadio interface | Free / Pro plumbing | 1 + Pro merged; 1c radio interface in progress |
| 2 | Airtime-aware ping interval | Free | merged, awaiting phone gate |
| 3 | Estimated coverage (IDW + terrain) | Free | merged, awaiting real-session gate |
| 4 / 5 | Andy picks the order: hardware profiles + comparison · placement advisor · MeshCore | Pro | rig profiles merged (comparison not built) |
| 6 | Offline map packs | Pro | not started |
| 7 | Coverage report + iCloud sync | Pro | not started |
| 8 | Opt-in anonymized uploads for aggregate inference | — | future discussion, don't build |
| 9 | Shared group map (team workspace reframed) | — | almost never, don't build |

## Phase 1: licensing, attribution, release hygiene

Done: LICENSE (GPL-3.0), NOTICE, upstream protobufs vendored unmodified in
`lib/proto/` (v2.7.26), SPDX headers, About screen, README, App Store
description draft. Pro subscription plumbing (`ProEntitlement`, paywall,
`ios/Runner/Products.storekit`).

**1c: radio service interface.** Before more features land on it:

```
abstract class MeshRadio {
  Stream<RadioConnectionState> get connectionState;
  Future<void> connect(RadioDescriptor d);
  Future<void> disconnect();
  Future<RadioInfo> queryDevice();              // model, firmware, protocol version
  Future<void> applyTestProfile(TestProfile p);  // channel key + preset/radio params
  Future<void> setBeacon(BeaconConfig c);        // range-test beacon or equivalent
  Future<PingResult> ping(NodeId target, {Duration timeout});
  Stream<ReceivedPacket> get packets;            // SNR, RSSI, hops, source, type, payload
}
```

- `MeshtasticRadio` is the only implementation for now.
- `ReceivedPacket`, `TestProfile` and the ping result are protocol-neutral.
- Presets live behind `RadioPreset` (display name, SF, BW, CR, estimated
  airtime). `AirtimeModel` consumes `RadioPreset`, not a Meshtastic enum.
- Sessions get a `protocol` column (`meshtastic` | `meshcore`), default
  `meshtastic`.
- BLE transport (scan, connect, MTU, notify) is its own class, so Android
  or MeshCore's Nordic UART Service can reuse it without touching protocol
  code.

Gate: Andy confirms LICENSE/NOTICE, About, README, a radio test on the
vendored protobufs and the refactored radio layer, and the subscription
product configured in App Store Connect. Offer-code redemption is verified
once the app is Ready for Distribution (see Decisions).

## Phase 2: airtime-aware ping interval (merged)

`AirtimeModel` (firmware 2.7.26 preset table, Semtech formula, 16-symbol
preamble, 40-byte ping, 5% target, 5 s floor), live "Air x%" readout over
the last 60 s (amber above 4%), interval clamping, throttled pings logged
as their own result, sessions store interval and airtime.

Gate: Andy confirms the table, copy and HUD readout on the phone; field
check of throttling on the T1000-Es.

## Phase 3: estimated coverage layer (merged)

IDW interpolation on a 50 m grid (fades beyond 300 m), terrain-aware
option (Open Topo Data, cached; LOS + Fresnel, knife-edge diffraction,
calibrated per session), long-press line-of-sight profile. Elevation
source is abstracted; move to self-hosted tiles before a paid release
(Open Topo Data's public API is for light, non-commercial use).

Gate: Andy tries the Estimated layer on a real session.

## Phase 4 / 5 (Andy picks the order)

### Hardware profiles and comparison (Pro)

1. Rig profiles (done): radio, antenna gain, cable type/length/loss,
   connector loss, notes, net gain; sessions tagged with mobile and base
   rigs.
2. Comparison mode: overlay sessions per rig, delta view in dB, summary
   card, expected vs measured gain; route matching via the Phase 3 grid.
3. Rig profiles get a `protocol` field once MeshCore exists; comparison
   refuses cross-protocol overlays with a one-line explanation.

Gate: Andy confirms the profile model, delta rendering and paywall.

### Node placement advisor (Pro)

Weak/dead cells from the Phase 3 grid; candidate sites at local elevation
maxima with LOS to the base and the gaps; top 3–5 ranked pins ("would
likely cover N% of the dead zone"). One disclosed affiliate "Suggested
hardware" row on the site detail sheet only.

Gate: Andy reviews suggestions against the ranch property.

### MeshCore support (Pro)

One app maps both Meshtastic and MeshCore coverage: same UI, sessions and
map; protocol chosen at connect time.

MeshCore companion radios use the Nordic UART Service over BLE (RX
`6E400002-…`, TX `6E400003-…`), one complete binary frame per
write/notification, no protobufs. Dart references: MeshMapper Flutter App
(`DaveWoodCom/MeshMapper_Flutter_App`, MIT) and MeshCore Open
(`zjs81/meshcore-open`). Protocol doc `docs.meshcore.io/companion_protocol/`
is in progress; trust the reference implementations where they differ.

1. `MeshCoreRadio` implementing `MeshRadio`: NUS BLE, frame parser,
   `CMD_APP_START` → `CMD_DEVICE_QUERY` on connect (negotiate protocol
   version, log firmware), radio params read/write, TX power.
2. Test profile: no named presets; write frequency/SF/BW/CR directly. A
   MeshCore `RadioPreset` table mirrors the Meshtastic airtime rows plus
   MeshCore's defaults. Private channel = a MeshCore channel with a
   phone-generated key.
3. Collection modes:
   - Passive → log adverts and any packet heard. UI says "MeshCore radios
     don't chatter — use Range Test or Ping for dense samples".
   - Range Test → periodic discovery/advert request to the base, logging
     each response with SNR/RSSI.
   - Ping → `PAYLOAD_TYPE_RAW_CUSTOM` to the base with a direct path, base
     echoes, record RTT. Gate on a working ping before UI work.
4. Hops: MeshCore reports path length; normalize to `ReceivedPacket.hops`,
   keep direct-vs-relayed dot sizing.
5. Test hardware: the Heltec V3 pair flashed to MeshCore companion
   firmware; T1000-Es stay on Meshtastic.
6. About screen: MeshCore attribution (confirm its license terms then).

Gate: a MeshCore session on the ranch with all three modes producing dots.

## Phase 6: offline map packs (Pro)

Groundwork done 2026-10-16: self-hosted raster PMTiles for Southern
California (streets, hillshade, contours) on S3 + CloudFront, read by the
app's own PMTiles reader; Standard/Terrain style switcher live; OSM tiles
only as the fallback outside the region. Pipeline: `tool/tiles/`.

**Hosted region decisions (2026-11-05):** the hosted region grows to the
six western states (CA, NV, AZ, OR, WA, UT) as one file clipped to the
state outlines, with streets, hillshade *and* contours; all three stay
**free** (Terrain was considered for Pro because hosting costs money, and
rejected: the cost is per tile served, the same for streets, and the whole
bill is cents a month until thousands of active users; Terrain is the map
that makes sense for a LoRa app, so gating it would hobble the free app
where new users judge it). Pro stays offline packs and satellite. The
pipeline stays Geofabrik + Planetiler (Protomaps extracts reconsidered
only when the target becomes "anywhere": the lower 48, outside the US, or
offline packs). A commercial tile provider is not a cost lever (it charges
per request too, more than CloudFront); it would only be for areas we
don't host, if demand appears outside the US. Terrain outside the hosted
region shows a one-line hint instead of silently looking like Standard.

1. Protomaps **PMTiles** basemap self-hosted on Plateau Nerd AWS (S3 +
   CloudFront, range requests). Tile URL behind a config constant. No
   third-party tile subscription, no API key in the app.
2. Packs: user draws or picks a region (state/county-sized); download the
   zoom ≤ 14 subset with a size estimate first; stored in app support
   storage; manage/delete in Settings.
3. Rendering: flutter_map vector tiles, or pre-rasterized packs if vector
   is too slow on older phones; benchmark first.
4. Attribution: "© OpenStreetMap contributors" (ODbL) plus Protomaps, on
   the map and in About.
5. Online OSM raster tiles stay the default when connected; packs are
   used offline or with "prefer offline".
6. **Satellite imagery is Pro** (decided 2026-10-16). It is the one
   basemap that can't be self-hosted from free data, so it is bought per
   tile from a commercial provider (MapTiler Flex, ~$25/month for 500k
   requests, key in a gitignored config, never in chat) and paid for by
   Pro revenue. Standard and Terrain basemaps stay free for everyone
   (self-hosted PMTiles, groundwork in `tool/tiles/`); a $0.99 "basic
   maps" SKU was considered and rejected — no cost to pass on, a second
   SKU to maintain, and it anchors against $6.99/yr. If tile costs ever
   bite, the lever is making offline packs the default, not gating the
   basic map.

Gate: a pack downloaded at home renders the ranch route with no
connectivity.

## Phase 7: coverage report + iCloud sync (Pro)

One-page PDF (`pdf` package): map snapshot, headline stat, per-preset
table, dead zones with placement sites; share sheet. CloudKit private
database sync for sessions and rig profiles (no shared/public database).

Gate: Andy confirms the report layout.

### Candidate: session playback (Pro, suggested 2026-10-16)

"Play back my session": a smoothed replay of a recorded walk on the map —
position and signal animated over time with a scrubber and speed control,
dots appearing as they were heard, the readout showing SNR/RSSI at that
moment. Pure UI over existing data (no schema change). Fits Phase 7 next
to the coverage report; order to be picked when Phase 4/5 is done.

### AI session analysis (Pro, decided 2026-10-16)

"Reading it" card on the Compare screen: a plain-English read of a
comparison (headline, 3-5 bullets, caveats, next step). Decisions:

- **The app computes every statistic; the model only writes the narrative.**
  Model: Claude Haiku 5.5 (`claude-haiku-5-5`), a few thousand tokens per
  report (cents per thousand reports).
- **Aggregates only.** The digest (`SessionDigest`, `lib/services/ai_analysis.dart`)
  holds presets, rig names and net gain, durations, rx counts, SNR/RSSI
  summaries, ping outcomes, airtime and channel use, route overlap counts and
  (once `range_stats.dart` lands) per-distance results. Never GPS tracks, the
  base location, node ids or keys; `assertNoLocationData` runs before every
  send and the backend rejects the same things.
- **Opt-in per report**, with a one-time consent sheet listing what is and is
  not sent. Pro-gated (`ProFeature.aiAnalysis`); Pro revenue pays for it.
  Listed as shipped on the paywall only when `AppConstants.aiAnalysisUrl` is
  set; null hides the feature entirely.
- **The backend holds the API key** (`tool/ai-analysis/`: Lambda Function URL,
  per-device daily (25) and monthly (300) quotas, global daily budget,
  counts-only logging). The app never sees an Anthropic key.
- **Report a problem** on every result (Google Play's generative-AI policy):
  opens mail/support with the digest and result attached.
- Result cached per comparison so reopening does not re-bill.
- Privacy: About "Your data" gains a sentence when the feature is configured;
  the privacy policy must name Anthropic as a processor before release.

### Candidate: guided test (design 2026-10-31, not scheduled)

"Walk me through it": the user says what they want to find out ("test my
two antennas", "which range setting"), the app builds a step-by-step
plan and runs it one screen at a time, starting and stopping sessions
itself, changing the radios where it can (the base remotely on
Meshtastic, after a risk sheet; by Bluetooth otherwise) and ending in a
never-null result. Design and clickable concept:
`docs/design/guided-test/`. Builds on rig comparison, MeshCore and the
AI analysis backend; four build steps with gates are in the doc. Pro line
to decide (proposal: free for two variants, Pro for three or four and
the AI parts).

### Candidate: Field Report Story buttons (deferred 2026-11-05)

The Field Report (built 2026-11-05, `docs/design/field-report/`) shares a
PNG through the iOS share sheet, which reaches Instagram and Facebook feed
posts. Later: one-tap "Instagram Story" and "Facebook Story" buttons in
the report sheet, using Meta's story URL schemes (`instagram-stories://`,
`facebook-stories://`) with the image on the pasteboard. Needs a free Meta
App ID (developers.facebook.com, no SDK, so the no-tracking rule holds),
passed with `--dart-define` like the AI token, plus
`LSApplicationQueriesSchemes`. Buttons show only when the app is installed
and an ID is set; always the 9:16 Story layout. Neither app accepts a
pre-filled caption, so the link stays in the image footer.

## Phases 8–9 (future discussion, don't build)

8. Opt-in anonymized uploads for aggregate inference.
9. Shared group map (team workspace reframed).

## Beta and release (not app code)

- TestFlight testers: Dan and Matt. Public TestFlight link after scripted
  testing passes. Tester hub: beta.plateaunerd.com.
- Compatibility matrix: T1000-E ×2 (reference), RAK WisMesh Tag, Heltec V3
  ×2 (Meshtastic base, then MeshCore pair), LilyGO T-Echo or Seeed Wio
  Tracker L1 Pro. Exit: pass on nRF52 and ESP32, and ≥1 tester on
  hardware Andy doesn't own.
- Trademark grant application and public GPL repo before App Store
  submission.

## Working conventions

One PR per phase; stop at each gate. Keep BLE/protobuf code behind the
`MeshRadio` interface (firmware schema churn is the main maintenance
risk). Network dependencies: only the Phase 3 elevation API and the
Phase 6 PMTiles host (behind a config constant); both degrade gracefully
offline. PRs touching BLE or StoreKit include an Android note.
