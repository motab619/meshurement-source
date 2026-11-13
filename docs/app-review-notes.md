# Meshurement - App Review notes (paste into App Store Connect > App Review Information > Notes)

Submit only builds made by `cd ios && fastlane release`. Builds from `fastlane beta` unlock Pro for testers (`TESTFLIGHT_PRO`) and would hide the subscription from the reviewer.

## Notes (text for App Store Connect)

Thank you for reviewing Meshurement.

WHAT THE APP NEEDS
Meshurement measures the radio link between two LoRa mesh nodes (small LoRa radio devices): a fixed "base" node and a "mobile" node paired to the iPhone over Bluetooth (Meshtastic®-compatible nodes, or MeshCore companion nodes). With real hardware you connect the mobile node, run Settings > Node Setup on both nodes, leave the base somewhere fixed, start a session and walk or drive. One node is not enough, and without nodes the Live map stays empty.

SAMPLE DATA (DEMO) WITHOUT NODES
So you can see every screen without hardware, the app has a sample-data demo:
1. Open Settings (bottom tab) > About Meshurement (at the bottom).
2. Long-press the Meshurement wordmark at the top (above the version number).
3. Tap "Open demo", then close the app (swipe it away in the app switcher) and open it again.
The app now runs on sample data: a pretend connected node and a recorded walk at the Empire Polo Club, with live map dots, charts, pings, coverage maps, Compare and the guided-test planner. Nothing is sent over Bluetooth, no permission prompts appear, and the demo uses its own database. Every Pro feature is on in the demo, so please check the subscription (below) before turning it on. To leave the demo, long-press the same title again, tap "Leave demo" and reopen the app.

SUBSCRIPTION (MESHUREMENT PRO)
Auto-renewable yearly subscription "Meshurement Pro" ($6.99/year, 1-week free trial). The core app is free. Outside the demo you can open the paywall without nodes:
- Settings > About Meshurement > "Meshurement Pro", or
- Settings > Rig profiles > "New rig (Pro)".
The paywall shows the price, trial, auto-renew terms, Restore Purchases, Terms of Use and Privacy Policy. Pro includes: guided tests with 3 or 4 setups (2 are free), hardware profiles, rig comparison and AI analysis of a comparison. If Pro lapses, everything already made stays viewable and exportable.

Where the Pro features are, in the demo:
- Rig comparison and AI analysis: Coverage tab > open the map > Select... > pick the two sessions > Compare. AI analysis must first be turned on in Settings > Privacy; it sends a numbers-only summary of the comparison (no positions) to our server and to Anthropic, only when you tap "Analyze with AI".
- Guided tests: Coverage tab > "Plan a test".
- Hardware profiles: Settings > Rig profiles > New rig.
- Live Activity: start a session (Live tab > Session > Start) and leave the app; without Pro the session panel says it comes with Pro and offers "See Pro". Out-of-range alerts are free.
- Faster than recommended: Settings > Active Probing; the switch carries a PRO tag and opens the paywall when turned on without Pro.

The lifetime product (com.andybrunker.meshAnalyzer.pro.lifetime) is not sold in the app. It exists only so beta testers can redeem App Store offer codes for it in the App Store; the app recognises it as Pro when owned.

DATA
No account, no ads, no analytics, no tracking. Map tiles come from our tile server (CloudFront) or OpenStreetMap. Optional terrain lookups go to Open Topo Data, optional AI analysis to our AWS server and Anthropic; both are off until turned on in Settings > Privacy. Nothing is sent on public mesh channels.

Contact: https://meshurement.com/support

## Still to do before submission

- Attach a screen recording with two real nodes: connect, Node Setup, a session with the phone locked, the out-of-range alert, the Live Activity, the paywall purchase and Restore (sandbox), a MeshCore connection, an AI analysis and a guided test.
- Fill in the IAP review notes for the lifetime product (offer codes only) with a StoreKit-test screenshot of the "Lifetime plan" card.
