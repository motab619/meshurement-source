# Meshurement - App Store listing (DRAFT for review)

## App name (max 30)
Meshurement: LoRa Range Test  (28; set in App Store Connect 2026-11-13. The home-screen name stays "Meshurement", CFBundleDisplayName)

## Subtitle (max 30)
Compare Mesh Radio Performance  (30; set in App Store Connect 2026-11-13)

## Promotional text (max 170)
Walk or drive with two LoRa mesh nodes and see exactly where your link holds and where it drops, live on a map. Private channel, on-device, no account.  (151)

## Description (max 4000; 3998 chars)
Meshurement turns two LoRa mesh nodes into a coverage-mapping kit. Leave one node at home (the base), take the other with you, connected to your iPhone over Bluetooth, and go for a walk or a drive. The app records how well you hear the base and whether the base hears you, tagged with your GPS position, and shows it live on a map.

It answers a simple question with measurements instead of predictions: how far does my setup really reach, here, with my antenna and settings?

WORKS WITH
Meshtastic®-compatible Bluetooth nodes running firmware 2.5 or later. Tested with the Seeed T1000-E and Heltec V3. MeshCore companion nodes work too. You need two nodes: one fixed base and one you carry.

LIVE WHILE YOU MOVE
- Map dots for every packet heard, coloured green to red by SNR or RSSI
- Live SNR and RSSI charts over 5 minutes, 15 minutes or 1 hour
- Ping results shown as delivered, relayed or failed
- Dynamic Island and lock screen Live Activity with range, signal and pings

MEASURES BOTH DIRECTIONS
The base sends a beacon on a schedule you choose, so you see how well you hear it. Your phone pings the base, every 15 seconds by default, so you see whether it hears you. Coverage is often lopsided; seeing both shows which side falls short.

WORKS IN YOUR POCKET
- Keeps recording with the phone locked
- Alert after 90 seconds out of range, and when you are back
- Alert if your phone loses its Bluetooth link to your radio

PRIVATE-CHANNEL TESTING
Radio Setup puts both nodes on a private, encrypted test channel with the same settings. The public channel is turned off, and a session will not start on a public channel. Meshurement does not use the public mesh and adds no traffic to it. Radio Setup replaces the channels on both radios and saves a backup first.

TOPO MAP, FREE
Switch the map to Terrain for hill shading and 100 ft contours to see the ridge that blocks your link. For now it covers the contiguous US, Hawaii and around Anchorage, Fairbanks and Juneau; more places on request via the support page.

COMPARE AND EXPORT
- Try radio presets from Long Slow to Short Turbo and compare them on the same route
- Coverage maps group sessions around one base, with Signal and Pings layers
- Export any session as CSV for Google Earth, GIS tools or a spreadsheet

YOUR DATA STAYS YOURS
No account, no ads, no analytics, no tracking. Your sessions, routes and radio settings stay on your phone. Map tiles come from our tile server or OpenStreetMap, which see the area you view (tiles can be turned off). The optional terrain view sends measurement-point coordinates to Open Topo Data. The optional AI analysis (Pro) sends a numbers-only summary, never positions, to our server and on to Anthropic, only when you ask. Purchases go through Apple. Nothing else leaves the phone unless you export it.

GOOD TO KNOW
- A radio accepts only one Bluetooth app connection at a time. Close other radio apps before connecting.
- Map tiles need a data connection. Map data © OpenStreetMap contributors.
- Requires Bluetooth and location permission.

MESHUREMENT PRO
Optional subscription that adds guided tests with 3 or 4 setups (2 are free), hardware profiles, rig comparison and AI analysis of a comparison. Everything else listed above is free. $6.99 a year with a 1-week free trial. Payment is charged to your Apple Account when you confirm. The subscription renews automatically unless you turn it off at least 24 hours before the end of the current period. Manage or cancel it in your App Store account settings. If Pro lapses, everything you made stays viewable and exportable.
Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://meshurement.com/privacy

OPEN SOURCE
Meshurement is free software under the GPL-3.0. Source code: https://github.com/motab619/meshurement-source

Meshtastic® is a registered trademark of Meshtastic LLC. This app is not affiliated with or endorsed by Meshtastic LLC.

Built by Plateau Nerd, https://plateaunerd.com

## Keywords (max 100, comma-separated)
<!-- Deliberately excludes "meshtastic": it is a registered trademark of Meshtastic LLC, which we do not own. Apple rejects trademarked keywords the developer has no rights to. Describe compatibility in the description instead. -->
node,coverage,signal,snr,rssi,gps,map,antenna,off-grid,walk test,link,repeater,preset,hiking,ham,ble  (100; drops the words already in the name and subtitle: lora, range, test, mesh, radio, compare, performance. Apple counts each word once across name, subtitle and keywords. No other apps' names or brands: meshtastic, meshcore, heltec, t1000)

## Support URL
https://meshurement.com/support

## Privacy Policy URL
https://meshurement.com/privacy

## Marketing URL (optional)
https://plateaunerd.com

## What to test (TestFlight, external testers)
You need two LoRa mesh nodes (Bluetooth radios, e.g. Seeed T1000-E). Close the official radio app, connect, run Settings > Radio Setup on both nodes, leave the base somewhere fixed, start a session and walk. Please report: pairing problems, where the map says out of range but you could still hear the base, and anything confusing in Radio Setup. Radio Setup replaces channels on both radios (a backup is saved first).
