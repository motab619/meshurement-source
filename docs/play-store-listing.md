# Meshurement - Google Play listing (Android)

Adapted from `docs/app-store-description.md` (2026-11-11). Differences: no
Live Activity (the recording notification instead), no purchases (Android
ships with every Pro feature free until Pro goes on sale on Play, planned
for January 2027), Google Play instead of Apple. Keep the two in step.

## App name (max 30)
Meshurement

## Short description (max 80)
Map your LoRa mesh radio's real range: walk, measure, see it live on a map.

## Full description (max 4000)
Meshurement turns two LoRa mesh radios into a coverage-mapping kit. Leave one radio at home (the base), carry the other paired to your phone, and go for a walk or a drive. The app records how well you hear the base and whether the base hears you, tagged with your GPS position, and shows it live on a map.

It answers a simple question with measurements instead of predictions: how far does my setup really reach, here, with my antenna and settings?

WORKS WITH
Meshtastic®-compatible Bluetooth radios running firmware 2.5 or later. Tested with the Seeed T1000-E and Heltec V3. MeshCore companion radios work too. You need two radios: one fixed base and one mobile.

LIVE WHILE YOU MOVE
- Map dots for every packet heard, coloured green to red by SNR or RSSI
- Live SNR and RSSI charts over 5 minutes, 15 minutes or 1 hour
- Ping results shown as delivered, relayed or failed

MEASURES BOTH DIRECTIONS
The base sends a beacon on a schedule you choose (about once a minute on current firmware), so you see how well you hear it. Your phone pings the base, every 15 seconds by default, so you see whether it hears you. Coverage is often lopsided, and seeing both shows where one side cannot reach the other.

WORKS IN YOUR POCKET
- Keeps recording with the screen off, with an ongoing "recording" notification until you end the session
- Alert after 90 seconds out of range, and when you are back
- Alert if your phone loses its Bluetooth link to your radio

PRIVATE-CHANNEL TESTING
Radio Setup puts both radios on a private, encrypted test channel with the same settings. The public channel is turned off, and a session will not start on a public channel. Meshurement does not use the public mesh and adds no traffic to it. Pings use a 15 second interval by default, limited by an airtime budget. Radio Setup replaces the channels on both radios and saves a backup first.

COMPARE, PLAN AND SHARE
- Guided tests: say what you want to find out (antennas, range settings, radios, power) and the app plans the walks and talks you through them
- Try range settings from Long Slow to Short Turbo and compare them on the same route
- Coverage maps group sessions around one base, with Signal and Pings layers
- Share a field report card of a session or a comparison
- Export any session as CSV for Google Earth, GIS tools or a spreadsheet

YOUR DATA STAYS YOURS
No account, no ads, no analytics, no tracking. Your sessions, routes and radios stay on your phone. Map tiles come from our tile server or OpenStreetMap, which see the area you view (tiles can be turned off). The optional terrain view sends measurement-point coordinates to Open Topo Data. The optional AI analysis sends a numbers-only summary, never positions, to our server and on to Anthropic, only when you ask. Nothing else leaves the phone unless you export it.

GOOD TO KNOW
- A radio accepts only one Bluetooth app connection at a time. Close other radio apps before connecting.
- Map tiles need a data connection. Map data © OpenStreetMap contributors.
- Needs Bluetooth (Nearby devices), location and notification permission.

EARLY ACCESS
Every feature is free on Android during early access, including guided tests with 3 or 4 setups, hardware profiles, rig comparison and AI analysis.

OPEN SOURCE
Meshurement is free software under the GPL-3.0.

Meshtastic® is a registered trademark of Meshtastic LLC. This app is not affiliated with or endorsed by Meshtastic LLC.

Built by Plateau Nerd, https://plateaunerd.com

## Graphics (in ~/Desktop/Meshurement-Play)
- App icon 512x512: `icon-512.png` (from the iOS 1024 icon)
- Feature graphic 1024x500: `feature-graphic-1024x500.png` (logo + wordmark from `assets/brand/splash.png`)
- Phone screenshots 1080x2160 (2:1, Play's limit): demo mode on the Galaxy A16, status and navigation bars cropped

## Contact details (Store settings)
Email support@meshurement.com, website https://meshurement.com, no phone. Category: Tools.
