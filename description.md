# Meshurement

*Updated 2026-10-12 · beta*

## What it is

An iPhone app that turns two Meshtastic® LoRa radios into a coverage-mapping
kit. Leave one radio at home (the **base**), carry the other (the **mobile**,
paired to your phone), and walk or drive around. The app records, every
15 seconds, how well you hear the base and whether the base hears you — tagged
with your GPS position — and shows it live on a map, in charts, in the Dynamic
Island and on the lock screen.

It answers the question every Meshtastic user has: **"How far does it really
reach, here, with my antenna and settings?"** — with measurements, not
predictions.

## First field test (2026-10-12)

A 19-minute walk on the Santa Rosa Plateau with two Seeed T1000-E radios on the
Medium Fast preset:

- Walked out to **2.3 km** from the base.
- Still heard the base at **1.47 km** (SNR −20 dB — right at the edge).
- **75 pings** sent every 15 s; **35 delivered**, the rest timed out as the
  walk went out of range — the map shows exactly where that happened.

## How it works

1. **Pair your radio** — connect to your Meshtastic radio over Bluetooth.
2. **One-tap radio setup** — the app puts both radios on a private, encrypted
   test channel with the same LoRa preset, and turns on the base's beacon.
3. **Start a session** and move around. Every 15 seconds the base beacons and
   your phone pings the base; each result is logged with your position.
4. **Watch it live** — dots on the map, charts, Dynamic Island — then review
   and compare sessions afterwards, or export the data.

## Features

### Live while you walk

- **Map dots** for every packet heard from the base, coloured green → red by
  signal strength (SNR or RSSI). Relayed packets are drawn smaller than
  direct ones.
- **Signal readout** (top right): SNR, RSSI, hops and the sender of the latest
  packet.
- **Live charts** — tap the readout and it expands into the top half of the
  screen:
  - SNR and RSSI over time (separate charts, shared time axis).
  - Ping strip: ✓ delivered, ⇄ relayed, ✗ failed, with a running count.
  - 5 min / 15 min / 1 hour windows; drag across to read any moment.
- **Dynamic Island & lock screen (Live Activity)** for the whole session:
  base in/out of range, latest SNR/RSSI, pings delivered, packet count, and
  "heard 30 s ago" that counts up on its own.
- **Base status badge** on the radio pill: base ✓ / base lost / base ?.

### Two-way measurement

| | Direction | What you learn |
|---|---|---|
| **Range Test beacon** (base sends every 15 s) | base → you | Signal strength (SNR/RSSI) at each spot |
| **Pings** (you send every 15 s, on by default) | you → base | Did it arrive? Delivered / relayed / failed, round-trip time and failure reason |
| **Other packets** (position, telemetry, ping replies) | base → you | Extra signal samples |

Coverage is often lopsided (antenna height, power, noise); measuring both
directions shows where you can hear the base but it can't hear you.

### Alerts that work in your pocket

- Keeps recording with the **phone locked** — GPS, pings and timers keep
  running during a session (blue location indicator shows while active).
- **Out-of-range alert** after 90 s without hearing the base, and a
  **back-in-range** alert when it returns.
- **Radio disconnected** alert if your phone loses its Bluetooth link to your
  own radio for 30 s (so a radio problem isn't reported as "out of range").
- Automatic Bluetooth reconnect with back-off; radio reboots are handled.

### Radio setup (Settings → Radio Setup)

- **Private test channel only** — both radios are put on an AES-256 encrypted
  "MeshTest" channel and every other channel (including the public one) is
  disabled. Tests never add traffic to the public mesh.
- **Public-channel guard** — a session won't start while your radio is on a
  public channel.
- **Modem preset picker** — Long Slow → Short Turbo (8 presets), applied to
  both radios, so you can compare speed vs. range.
- **Range Test beacon** interval for the base: off / 15 / 30 / 60 / 120 / 300 s.
- Done entirely from the phone over Bluetooth — no laptop or cable.
- Radios automatically swap identities/encryption keys so direct-message pings
  work.

### Sessions and coverage maps

- **Coverage maps** group sessions around one base radio (e.g. "Home – roof").
- **Sessions** record one walk or drive; each remembers the **preset** it used
  and survives app restarts.
- **Coverage map view** (Coverage tab → tap a map):
  - **Signal** layer (base → you) and **Pings** layer (you → base).
  - **Preset filter** to compare presets on the same route.
  - Show/hide individual sessions; auto-zoom to your data; legend.
  - Per-session summary: duration, packets, SNR range and median, pings
    delivered, and why pings failed (e.g. "3 no reply").

### Topo map (free)

- **Standard / Terrain** switch on every map. Terrain adds hill shading and
  100 ft contour lines, so you can see the ridge or valley between you and
  the base.
- **Where:** for now the contiguous US, Hawaii, and about 100 miles around
  Anchorage, Fairbanks and Juneau. More places can be added on request
  (support page). Elsewhere the map shows OpenStreetMap streets and says
  "No hillshade here".
- Elevation data: USGS 3D Elevation Program.

### Export

- **CSV per session** via the iOS share sheet — position, altitude, GPS
  accuracy, SNR, RSSI, hops, sender, packet type, ping status, round-trip
  time and preset. Opens in Google Earth, GIS tools or a spreadsheet.

### Connection

- Bluetooth connection to Meshtastic radios (tested: Seeed T1000-E,
  firmware 2.7.x).
- **Connect** button (bottom left) whenever you're not connected; compact
  radio status pill (top left) with radio details and Disconnect.
- Finds radios that are already connected to the phone by another app.

## Requirements

- iPhone with iOS 16.2+ for the Live Activity (the app itself runs on iOS 15+).
- **Two Meshtastic radios** (one base, one mobile). Tested with Seeed T1000-E;
  other Meshtastic BLE radios should work.
- Bluetooth and location permission ("While Using" is enough).
- Map tiles need a data connection.

## Privacy

Your sessions, positions and signal readings stay on your phone. No account,
no ads, no tracking, no analytics. These are the only things that can leave the
phone, each listed with a switch in **Settings > Privacy**:

- **Map tiles** from our map tile server (CloudFront) in the covered areas
  (contiguous US, Hawaii, around Anchorage, Fairbanks and Juneau) and from
  OpenStreetMap elsewhere. The tile server sees which map area you look at.
  Turn tiles off and no basemap is requested.
- **Terrain elevation** (off until you turn it on): the coordinates of your
  measurement points (and so your base) go to Open Topo Data to look up ground
  height for the terrain-aware estimate and the line-of-sight profile.
- **AI session analysis** (Pro, off until you turn it on): a numbers-only
  summary of a comparison (signal levels, counts, rig names; no positions,
  radio ids or keys) goes to our server (AWS Lambda) and on to Anthropic,
  which writes the analysis, only when you ask for one.
- **Purchases** go through Apple's App Store (StoreKit).

Nothing else leaves the phone unless you export it, and exports go only where
you send them. Radio traffic during tests is encrypted on a private channel.

Privacy Policy: https://meshurement.com/privacy ·
Support: https://meshurement.com/support

## Meshurement Pro (optional subscription)

Mapping, pings, charts, coverage layers and export are free. **Meshurement
Pro** adds guided tests with 3 or 4 setups (2 are free),
hardware profiles, rig comparison and AI analysis of a comparison. It is an
optional auto-renewable subscription: $6.99 per year, with a
1-week free trial for new subscribers. Payment is charged to your Apple ID
account at confirmation of purchase (after the trial ends). The subscription
renews automatically unless it is cancelled at least 24 hours before the end of
the current period. Manage or cancel it any time in Settings > Apple ID >
Subscriptions. If Pro lapses, everything you made stays on your device and
stays viewable and exportable.

Terms of Use (Apple standard EULA):
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/ ·
Privacy Policy: https://meshurement.com/privacy

## Trademark

Meshtastic® is a registered trademark of Meshtastic LLC. Meshurement is not
affiliated with or endorsed by Meshtastic LLC.

## Known limitations (beta)

- iPhone only; distributed to testers directly (not on the App Store).
- Changing presets needs both radios side by side (no remote reconfiguration
  of a placed base yet).
- SNR/RSSI describe the last radio hop; relayed packets are flagged but
  don't measure the base-to-you link directly.
- Live charts start fresh each time the app opens (recorded sessions are
  kept).
- No offline map download yet.
- Dev timing is fixed at 15 s pings / 90 s out-of-range alert (Settings
  sliders are disabled during the beta).
- Applying Radio Setup replaces the radio's channels — re-add your usual
  channels afterwards with your normal Meshtastic app.

## Ideas on the roadmap

Offline maps · heat-map coverage view · remote reconfiguration of a placed
base · traceroute-based two-way SNR · multiple bases for relay placement ·
shareable coverage maps · Android.
