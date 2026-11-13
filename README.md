# Meshurement

(Formerly Mesh Analyzer; renamed 2026-11-05. Website: https://meshurement.com)

An iPhone app that measures how far your LoRa mesh nodes really reach. Leave one node at home, carry the other, and walk or drive. The app logs signal strength with your GPS position and draws it on a map as you go.

Built by [Plateau Nerd](https://plateaunerd.com). Works with Meshtastic®-compatible nodes running firmware 2.7.x (see Supported nodes).

<p>
<img src="ios/fastlane/screenshots/en-US/iPhone%2018%20Pro%20Max-01-live-map.png" width="220" alt="Live map with dots coloured by signal strength">
<img src="ios/fastlane/screenshots/en-US/iPhone%2018%20Pro%20Max-02-live-charts.png" width="220" alt="Live SNR and RSSI charts with ping results">
<img src="ios/fastlane/screenshots/en-US/iPhone%2018%20Pro%20Max-04-pings-map.png" width="220" alt="Coverage map, Pings layer">
</p>

The demo walk in the screenshots is sample data recorded at the Empire Polo Club, not a real test.

## What it does

- Uses two nodes: a fixed **base** and a **mobile** node paired to your phone.
- Live map with a dot for every packet heard from the base, coloured green to red by SNR or RSSI.
- Pings in both directions: the base beacons every 15 s (how well you hear it), and your phone pings the base every 15 s (whether it hears you). Results are shown as delivered, relayed or failed.
- Live charts of SNR, RSSI and ping results over 5 min, 15 min or 1 hour.
- Live Activity: Dynamic Island and lock screen show in/out of range, latest signal and pings delivered.
- Background recording: keeps logging with the phone locked.
- Alerts when you have been out of range for 90 s, when you are back, and when your phone loses its Bluetooth link to your node.
- Presets comparison: apply a modem preset (Long Slow to Short Turbo) to both nodes and compare sessions on the same route.
- Coverage maps group sessions around one base, with Signal and Pings layers.
- CSV export per session (position, SNR, RSSI, hops, ping status, round-trip time, preset) for Google Earth, GIS tools or a spreadsheet.

Your sessions, routes and node settings stay on your phone. No account, no ads, no analytics, no tracking. The only things that can leave the phone, each with a switch in Settings > Privacy: map tiles (our CloudFront tile server in Southern California, OpenStreetMap elsewhere; the server sees the area you view), terrain elevation lookups at Open Topo Data (off until you turn it on; sends the coordinates of your measurement points), and AI analysis (Pro, off until you turn it on; a numbers-only summary of a comparison goes to our AWS Lambda and on to Anthropic, only when you ask). Purchases go through Apple. Nothing else leaves the phone unless you export it.

## What you need

- An iPhone (iOS 16.2+ for the Live Activity; the app itself runs on iOS 15+).
- **Two** Bluetooth-capable nodes, one as base and one to carry. One node is not enough: the app measures the link between them.
- Bluetooth and location permission. Map tiles need a data connection.

### One Bluetooth connection at a time

A node accepts only one Bluetooth app connection at a time. Close the official Meshtastic app (force-quit it) before connecting Meshurement, or the connection will fail.

## Airtime etiquette

LoRa airtime is shared. The app is built to stay off the public mesh:

- Node Setup puts both nodes on a private, encrypted test channel ("MeshTest", AES-256 key generated on your phone). It is the only enabled channel; the public channel is disabled.
- A session will not start while your node is on a public channel.
- Pings are direct messages on the private channel, sent at a conservative 15 s interval.
- Node Setup replaces the channels on both nodes. It saves a backup of each node's settings first; restore from Node Setup > Backups, or re-add your usual channels afterwards.

## Supported nodes

Tested:

- Seeed T1000-E, firmware 2.7.x (2.7.26). Two of them, one base and one carried.
- Muzi Works H1 (Heltec LoRa 32 V3 with a screen): connects and pairs; type the PIN shown on its screen.

Should work, untested: other Bluetooth nodes such as RAK WisBlock (RAK4631), Heltec Mesh Node T114 and LoRa 32 V3, LILYGO T-Echo and T-Beam (S3 Core), Seeed Wio Tracker L1.

Not supported: nodes without Bluetooth or reachable only over Wi-Fi or USB (for example a Linux meshtasticd node); Android and iPad-only setups.

Before the first session:

- Update both nodes to current stable firmware (2.5 or newer; pings need 2.5+) at flasher.meshtastic.org.
- Pairing code: nodes without a screen usually use 123456; nodes with a screen show a random code.
- Set your region on the nodes (Node Setup uses the node's region, or US).
- Charge both nodes and put the base up high, outdoors or by a window.

## Build from source

Requires macOS, Xcode, the Flutter SDK (stable) and a physical iPhone (Bluetooth does not work in the simulator).

```bash
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs   # drift database code
flutter run                                                        # on a connected iPhone
flutter test
flutter analyze
```

Re-run `build_runner` after changing database tables or queries.

Screenshots (demo mode, iPhone simulator, about 5 minutes): `cd ios && fastlane snapshot`. Output goes to `ios/fastlane/screenshots/en-US/`.

TestFlight: `cd ios && fastlane beta`. This needs an App Store Connect API key (Admin role) in `ios/fastlane/.env`; see `ios/fastlane/.env.example`. Set your own signing team first.

## Get it

App Store build: coming soon. The core app is free (mapping, pings, charts, coverage layers, export). An optional Pro subscription ($6.99/year, 1-week free trial) adds extra features. The source is free here; you can build it yourself as above.

Source: https://github.com/motab619/meshurement-source

## License

GPL-3.0. See `LICENSE` and `NOTICE`. The protobuf definitions come from [meshtastic/protobufs](https://github.com/meshtastic/protobufs), also GPL-3.0. Map data (c) OpenStreetMap contributors.

## Trademark

Meshtastic® is a registered trademark of Meshtastic LLC. This app is not affiliated with or endorsed by Meshtastic LLC.
