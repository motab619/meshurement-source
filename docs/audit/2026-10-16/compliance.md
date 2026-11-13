# Mesh Analyzer: App Store compliance, licensing and privacy audit

Tree audited: `scratchpad/beta-audit` (read-only). Date: 2026-10-16. `docs/beta/` ignored as instructed.

## Summary

Two things would fail a public TestFlight or App Store submission, or create legal exposure. The in-app and store privacy-policy URL (`https://beta.plateaunerd.com/privacy/mesh-analyzer`) does not resolve (NXDOMAIN). The GPL "Source code" link (`github.com/motab619/mesh-analyzer`) returns 404 because the repo is private, so the binary ships GPL-3.0 Meshtastic code without its corresponding source.

The paywall sells a subscription where every listed Pro feature says "Coming soon", including the two that already work. The "Hardware profiles" row renders as the literal text `null Coming soon.`

Privacy claims ("data leaves the phone only when you export a CSV") are contradicted by the code. Map tiles go to tile.openstreetmap.org, and the opt-in terrain layer sends GPS coordinates to the third-party api.opentopodata.org. The map screens show no OSM attribution.

There is no `PrivacyInfo.xcprivacy`, and the statically linked sqlite3 pod (which calls `stat`/`fstat`) ships none. That risks ITMS-91053 rejection at upload.

Subscription disclosure, Restore Purchases, the EULA link, background-location use, export compliance, trademark wording and the NOTICE coverage are otherwise in good shape.

## Findings

### [BLOCKER] Privacy Policy URL does not resolve
- **Where:** `lib/ui/screens/pro_paywall_screen.dart:14` (`privacyPolicyUrl = 'https://beta.plateaunerd.com/privacy/mesh-analyzer'`), used by the paywall's "Privacy Policy" button. `docs/app-store-description.md` also suggests `https://beta.plateaunerd.com` as the Support URL.
- **What:** `dig beta.plateaunerd.com` returns nothing and WebFetch fails with `ENOTFOUND`. `https://plateaunerd.com/privacy/mesh-analyzer` returns 404. `plateaunerd.com` itself is up (CloudFront, HTTP 200). There is no privacy policy text in the repo outside `docs/beta/`, so its content could not be reviewed. The privacy link also appears only on the paywall, not on About or Settings.
- **Rule/Source:** 5.1.1(i): "All apps must include a link to their privacy policy in the App Store Connect metadata field and within the app in an easily accessible manner." 2.1(a): "fully functional URLs". Schedule 2 of the Paid Apps Agreement requires a working privacy link in the binary for subscriptions. https://developer.apple.com/app-store/review/guidelines/
- **Fix:** Publish the policy at a URL that resolves (deploy the beta subdomain, or use `https://plateaunerd.com/privacy/mesh-analyzer`). Point `privacyPolicyUrl` and the App Store Connect Privacy Policy URL (including TestFlight Test Information) at it. Add a "Privacy Policy" row to the About screen. The policy must list OSM tile requests, Open Topo Data elevation lookups (coordinates sent), StoreKit (Apple handles payment), on-device storage, CSV export and contact details (see the next privacy finding).

### [BLOCKER] GPL corresponding source is not available (repo private, in-app link 404)
- **Where:** `lib/ui/screens/about_screen.dart:18` (`sourceCodeUrl = 'https://github.com/motab619/mesh-analyzer'`), also the license-page legalese and the "OPEN SOURCE" section of `docs/app-store-description.md`. `gh repo view` reports `"visibility":"PRIVATE"`, and an unauthenticated `curl` returns 404. `docs/roadmap.md:10-11` says "private for now ... public before App Store submission".
- **What:** The app ships code generated from the GPL-3.0 Meshtastic protobufs (copyright Meshtastic LLC and contributors, not Andy). Each public TestFlight install conveys object code. GPL-3.0 §6 then requires the Corresponding Source to be available to every recipient. "Before App Store submission" is too late: a public TestFlight link is already public distribution. A dead link also breaks 2.1(a).
- **Rule/Source:** GPL-3.0 §6 (`lib/proto/LICENSE`, byte-identical to upstream); Guideline 2.1(a).
- **Fix:** Make the repo public before the public TestFlight link goes live. Tag every uploaded build (e.g. `v0.1.0+N`) so the source matches the binary. If the repo must stay private, use §6(b): ship a written offer, and give testers access. Public is simpler.

### [BLOCKER] Paywall sells a subscription whose features all say "Coming soon"; one row shows "null"
- **Where:** `lib/ui/screens/pro_paywall_screen.dart`, `_FeatureList`. `_blurbs` has no entry for `ProFeature.rigProfiles`, and the subtitle is `'${_blurbs[f]} Coming soon.'`. Every `ProFeature` gets "Coming soon." The intro says "Pro adds the extras listed below as they ship."
- **What:**
  - The "Hardware profiles" row renders `null Coming soon.`
  - Hardware profiles and Rig comparison are implemented and gated (`ProGate` in `rig_profiles_screen.dart:27`, `session_panel.dart:375`, `comparison_actions.dart:53`), yet they are labelled "Coming soon".
  - The other five (placement advisor, PDF report, MeshCore, offline maps, iCloud sync) are not implemented.
  - A reviewer sees a $4.99/yr subscription whose screen says it currently delivers nothing.
- **Rule/Source:** 3.1.2(a): "you must provide ongoing value to the customer". 3.1.2(c): "Before asking a customer to subscribe, you should clearly describe what the user will get for the price". 2.1(a): placeholder or temporary content must be scrubbed. 2.3: metadata must reflect the app.
- **Fix:**
  - Add the missing blurb.
  - Show the shipped features (Hardware profiles, Rig comparison) as included now.
  - Drop the "Coming soon" items from the paywall, or move them to a clearly separate "Planned" note that does not promise them for the price. Apple reviewers commonly reject subscriptions sold on future features.
  - Make sure at least the shipped Pro features are reachable for the reviewer: explain in Review Notes and in the video (see the hardware-review finding).
  - Add a widget test that no subtitle contains "null".

### [HIGH] Privacy claims contradict network behaviour (OSM tiles, Open Topo Data)
- **Where:**
  - Tiles: `lib/ui/screens/map_screen.dart:170`, `coverage_map_detail_screen.dart:343` and `rig_comparison_screen.dart:249` (`https://tile.openstreetmap.org/{z}/{x}/{y}.png`).
  - Elevation: `lib/services/terrain/open_topo_data_source.dart:29` (`https://api.opentopodata.org/v1`, datasets `ned10m`/`srtm30m`), used via `default_elevation_source.dart` when the "Terrain-aware" chip is on (`coverage_map_detail_screen.dart:501-505`).
  - Copy: `docs/app-store-description.md` says "Data leaves the phone only when you export a CSV", and `description.md` and `README.md` repeat it.
- **What:** The full list of hosts the app contacts:
  - `tile.openstreetmap.org` (OSMF): tile x/y/z, which reveals the viewed area and, during recording, roughly where you are, plus IP.
  - `api.opentopodata.org` (third party, run by GPXZ): exact lat/lon of the base, sample points and the route, plus IP.
  - Apple StoreKit and App Store (OS-handled).
  - User-initiated links only (`url_launcher`): plateaunerd.com, github.com, openstreetmap.org/copyright, apple.com EULA, apps.apple.com subscriptions.

  `meshtastic.org/e/#...` (`radio_backup_service.dart:71`) is a string built for sharing, not a request. No analytics, crash-reporting or upload code exists.

  The "only when you export a CSV" claim is therefore false. Location leaves the device to a third party when terrain is on.
- **Rule/Source:**
  - 5.1.1(i): the policy must identify what data is collected and how.
  - 5.1.2(i): "You must provide access to information about how and where the data will be used."
  - 2.3: accurate metadata, "including privacy information".
  - App Privacy Details: data sent off-device counts as "collected" unless it is only used to service the request in real time. Open Topo Data does not say whether it logs requests (opentopodata.org has no privacy statement).
- **Fix:**
  - Reword the copy, e.g. "No account, no analytics, no tracking. Your sessions stay on your phone. Map tiles come from OpenStreetMap, and the optional terrain view sends map coordinates to Open Topo Data to look up elevation."
  - Show a one-time notice before the first terrain lookup.
  - Put the same text in the privacy policy.
  - In the App Privacy questionnaire, conservatively declare Location (Precise), App Functionality, not linked, not tracking. If you rely on the real-time exception, document why.

### [HIGH] No privacy manifest; statically linked SQLite uses file-timestamp APIs without one
- **Where:**
  - No `PrivacyInfo.xcprivacy` under `ios/` (Runner or MeshActivity), and none referenced in `project.pbxproj`.
  - The `sqlite3` pod 3.52.0 (via `sqlite3_flutter_libs` 0.5.42) and `flutter_blue_plus_darwin` 7.0.3 ship none either (checked the pub cache and CocoaPods cache).
  - `sqlite3.c` contains 46 `stat`/`fstat`/`lstat` references.
  - These plugins do ship their own manifests: flutter_local_notifications, geolocator_apple, in_app_purchase_storekit, package_info_plus, permission_handler_apple, share_plus, shared_preferences_foundation, url_launcher_ios, wakelock_plus. `path_provider_foundation` 2.6.0 has no native pod (FFI via `objective_c`).
- **What:** `stat`/`fstat` are in the File Timestamp required-reason category, and SQLite is compiled into the app bundle with no declaration. Apple: "Starting May 1, 2024, apps that don't describe their use of required reason API in their privacy manifest file aren't accepted by App Store Connect." The Runner and extension Swift code use no required-reason APIs (only `ProcessInfo.arguments`).
- **Rule/Source:** https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api (quote fetched from Apple's doc JSON). Third-party SDK list: https://developer.apple.com/support/third-party-SDK-requirements/. sqlite3, flutter_blue_plus and permission_handler are not on that list; the plugins that are have manifests.
- **Fix:**
  - Add `ios/Runner/PrivacyInfo.xcprivacy` to the Runner target (Copy Bundle Resources, via the xcodeproj gem) with:
    - `NSPrivacyTracking` = false and empty `NSPrivacyTrackingDomains`.
    - `NSPrivacyCollectedDataTypes` matching the App Privacy answers.
    - `NSPrivacyAccessedAPITypes`: FileTimestamp with reason `C617.1` (files inside the app container; confirm the code on Apple's page) and UserDefaults with `CA92.1` (shared_preferences declares this itself, but harmless).
  - The MeshActivity extension needs none today.
  - Do an archive and upload to TestFlight early and read any ITMS-91053 email.

### [HIGH] Subscription Terms of Use (EULA) link missing from App Store metadata
- **Where:** `docs/app-store-description.md` (draft listing) has no Terms of Use or EULA link and no mention of the Pro subscription. In-app, the paywall links Apple's standard EULA (`termsOfUseUrl`), which is fine.
- **What:** Apps with auto-renewable subscriptions must have a functional Terms of Use link in the App Store metadata too: in the description, or a custom EULA in App Store Connect. Reviewers routinely reject under 3.1.2 for this.
- **Rule/Source:** 3.1.2(c); Paid Apps Agreement Schedule 2 §3.8(b) (subscription information must be in the app and the metadata). https://developer.apple.com/app-store/review/guidelines/
- **Fix:** Add to the description: "Mesh Analyzer Pro: optional yearly subscription ($4.99/yr, 1-week free trial for new subscribers). Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/ · Privacy: <working URL>". Fill the App Store Connect Privacy Policy URL field.

### [HIGH] GPL-3.0 Meshtastic protobufs distributed through the App Store
- **Where:** `lib/proto/` (upstream `meshtastic/protobufs` v2.7.26). `lib/proto/LICENSE` is byte-identical to upstream's current LICENSE: plain GPL-3.0, no additional permission or App Store exception (fetched raw; grep found no exception text). The generated `*.pb.dart` is compiled into the binary.
- **What:**
  - Andy can license his own code as he likes, but not Meshtastic's.
  - The FSF view, and the reason VLC was pulled in 2011, is that Apple's Usage Rules and EULA (device limits, no redistribution) are "further restrictions" barred by GPL-3.0 §10/§12.
  - Mosh (COPYING.iOS) and libsignal solved this with explicit copyright-holder permissions; Meshtastic has none.
  - The official Meshtastic iOS app (`meshtastic/Meshtastic-Apple`, GPL-3.0, same protobufs submodule) is on the App Store without a published exception. That suggests Meshtastic LLC tolerates it, but it is not a licence grant to third parties, and individual contributors who own copyright in the .proto files could still complain.
  - No Meshtastic CLA or copyright assignment for the protobufs repo could be confirmed.
- **Practical risk:** Low probability, real consequence: a DMCA or takedown notice to Apple removes the app, as with VLC. Shipping without public source (the source-availability blocker above) makes the case much worse.
- **Rule/Source:** GPL-3.0 §6, §10, §12; Guideline 5.2.1 (don't use third-party copyrighted material without permission); https://github.com/meshtastic/protobufs; https://github.com/meshtastic/Meshtastic-Apple; Mosh COPYING.iOS (https://sources.debian.org/src/mosh/1.2.4a-1/COPYING.iOS).
- **Fix (recommended order):**
  1. Make the source public (the source-availability blocker above). This removes the strongest complaint.
  2. In the trademark grant request already planned, also ask Meshtastic LLC in writing for permission to distribute the protobuf-derived code via the App Store (a Mosh-style "won't enforce solely due to App Store terms" statement). Keep the reply in the repo.
  3. Add a COPYING.iOS-style additional permission for Andy's own code (GPL-3.0 §7), so contributors to Mesh Analyzer can't object either.
  4. Fallback if Meshtastic refuses: replace the generated code with a hand-written minimal protobuf wire codec for the messages used. Wire formats and interface facts are weakly protected, but this is a legal judgment; get advice.

  OK for TestFlight once step 1 is done. Do steps 2 and 3 before App Store release.

### [HIGH] No OpenStreetMap attribution on the map screens
- **Where:** All three `TileLayer`s (`map_screen.dart:169`, `coverage_map_detail_screen.dart:341`, `rig_comparison_screen.dart:247`) have no `RichAttributionWidget` or `SimpleAttributionWidget`. Attribution exists only in About (`about_screen.dart:132`), on the license page and in NOTICE.
- **What:** The OSM tile usage policy requires the notice "clearly on the map, typically bottom-right. Do not hide attribution beneath UI, behind toggles, or off-screen". ODbL also requires attribution where the map is shown. Not complying can get the app's User-Agent blocked without notice.
- **Rule/Source:** https://operations.osmfoundation.org/policies/tiles/ ; https://www.openstreetmap.org/copyright
- **Fix:** Add `RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors', onTap: open osmCopyrightUrl)])` (or `SimpleAttributionWidget`) to each `FlutterMap`, clear of the session panel and pills. Screenshots will then show it as well.

### [MEDIUM] Commercial app depends on free community services (OSM tiles, Open Topo Data public API)
- **Where:** As in the network-behaviour finding. `userAgentPackageName: 'com.andybrunker.meshAnalyzer'` is set (good), and flutter_map 8.2.2 has built-in tile caching (`BuiltInMapCachingProvider`).
- **What:**
  - OSM: "Commercial services, or those that seek donations, should be especially aware that access may be withdrawn at any point". Bulk or offline prefetch from tile.openstreetmap.org is prohibited, so the planned Pro "Offline map packs" can't use it.
  - Open Topo Data's public API is "for testing", limited to 1000 calls/day, 1 call/s and 100 locations per request, with no statement on commercial or production use. The app enforces those limits per device and in memory only.
- **Rule/Source:** https://operations.osmfoundation.org/policies/tiles/ ; https://www.opentopodata.org/ and https://www.opentopodata.org/api/
- **Fix:**
  - Before App Store release, move tiles to a provider whose terms allow commercial apps (MapTiler, Stadia, Thunderforest, or self-hosted), and elevation to GPXZ (paid) or self-hosted Open Topo Data. Or email the operators to confirm use is acceptable.
  - Make the elevation daily counter persistent.
  - Name the elevation source and datasets (USGS 3DEP/NED and SRTM, public domain, credit appreciated) in NOTICE and the About/licenses page.

### [MEDIUM] App builds as universal (iPhone + iPad) although it is iPhone-only
- **Where:** `ios/Runner.xcodeproj/project.pbxproj`. The Runner target sets no `TARGETED_DEVICE_FAMILY` and inherits project-level `"1,2"` (lines 684, 849, 903). The MeshActivity extension and test targets are `1`. `README.md` says "iPad-only setups" are not supported, and `Info.plist` lists iPad orientations.
- **What:** A universal binary needs iPad screenshots, is reviewed on iPad, and must work there (2.4.1).
- **Rule/Source:** Guideline 2.4.1; App Store Connect screenshot requirements.
- **Fix:** Set `TARGETED_DEVICE_FAMILY = 1` on the Runner target (all configs, via the xcodeproj gem). Otherwise produce iPad screenshots and test on iPad.

### [MEDIUM] Hardware-dependent app: reviewers cannot exercise it
- **Where:** Core function needs two Meshtastic radios. Demo mode (`lib/demo/`) is reachable only with the `-MeshDemo` launch argument or the `MESH_DEMO` env var. There is no user-facing entry (no UI hits for "demo").
- **What:** Without hardware, reviewers see an empty map and a Connect button. That commonly leads to a 2.1 "unable to review" rejection or a request for a video. The launch-arg demo is invisible to them.
- **Rule/Source:** Guideline 2.1 (App Completeness; reviewer must be able to review it; provide a demo or video for hardware-dependent features). Guideline 2.3.1(a): "Don't include any hidden, dormant, or undocumented features". The launch-arg demo is a dev and screenshot tool, which is borderline at most.
- **Fix:**
  - In App Review Notes (and TestFlight "What to Test"), attach or link a screen recording with real radios covering connect, Radio Setup, session, alerts, Live Activity, paywall and Restore.
  - State that two radios are required.
  - Optionally add a visible "Try demo" entry, which also lets reviewers reach the shipped Pro features.

### [MEDIUM] Hidden lifetime non-consumable (offer codes only) must survive IAP review
- **Where:** `ios/Runner/Products.storekit` (`com.andybrunker.meshAnalyzer.pro.lifetime`, NonConsumable, 14.99). `lib/services/pro_entitlement.dart:18-22` never offers it, and the app has no in-app redeem UI or offer-code text.
- **What:** Offer codes for non-consumables are supported (iOS 16.3+, App Store Connect "Create offer codes for in-app purchases"). Custom or one-time codes need the app "Ready for Distribution" and the IAP "Approved" (roadmap notes this).
  - Submitting the IAP for review requires a review screenshot, and the reviewer cannot find it in the app.
  - 2.1(b) says IAPs must be "visible to the reviewer and functional".
  - The app does handle the entitlement once owned: the `_ActiveCard` shows "Lifetime plan". Mentioning "redeem a code in the App Store" in the app is allowed; it is Apple's own flow, and no alternative purchase path is involved (3.1.1). The app currently says nothing about it anyway.
- **Rule/Source:** 2.1(b), 3.1.1; https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-offer-codes-for-in-app-purchases
- **Fix:** In the IAP review notes, explain that the product is distributed only via offer codes to beta testers, and attach a screenshot of the "You have Pro · Lifetime" card (StoreKit test). Be ready to submit it after the app is approved if review pushes back.

### [MEDIUM] Location usage strings do not explain the locked-phone recording
- **Where:** `ios/Runner/Info.plist`:
  - `NSLocationWhenInUseUsageDescription` = "Records your position for signal strength mapping."
  - `NSLocationAlwaysAndWhenInUseUsageDescription` = "Records your position in the background for signal mapping."
- **What:** geolocator_apple 2.3.13 calls only `requestWhenInUseAuthorization` because the WhenInUse key is present (`PermissionHandler.m:72-73`). Background use relies on `allowsBackgroundLocationUpdates` and the blue indicator (`gps_service.dart:74-80`), with `UIBackgroundModes` location. That pattern is fine (2.5.4), but the only string the user ever sees doesn't mention that recording continues while the phone is locked during a session. The Always string is unused (and `PERMISSION_LOCATION_ALWAYS=1` is set in the Podfile).
- **Rule/Source:** 5.1.1(ii) (purpose strings must clearly describe use), 2.5.4, 5.1.2.
- **Fix:** Set WhenInUse to e.g. "Mesh Analyzer tags each signal measurement with your position. While a session is recording, it keeps doing this with the phone locked (the blue indicator shows when it is active)." Keep the Always key only if needed, or drop it and the Podfile macro.

### [LOW] Price prominence and trial wording on the paywall
- **Where:** `pro_paywall_screen.dart` `_yearlyHeadline` builds "1 week free, then $4.99/year". The disclosure hard-codes "1 year subscription, $price per year".
- **What:** Apple's subscription guidance wants the billed amount to be the most prominent pricing element. Here the trial leads in the same style. Low risk, but some reviewers flag it.
- **Rule/Source:** 3.1.2(c); Apple auto-renewable subscription marketing guidance.
- **Fix:** Lead with "$4.99/year" and put "Includes a 1-week free trial for new subscribers" on a second line.

### [LOW] SPDX headers missing
- **Where:** Missing the 4-line header:
  - `ios/Runner/SceneDelegate.swift`
  - `ios/RunnerTests/RunnerTests.swift`
  - `tool/gen_protos.sh` (has a comment header but no SPDX line)

  `ios/RunnerUITests/SnapshotHelper.swift` is fastlane's MIT file (Felix Krause). It should keep its own header, not get a GPL one, and is test-only and not shipped. Every `lib/` (excluding `lib/proto/` and generated `*.g.dart`), `test/`, `tool/make_icon.py`, `ios/Runner/*.swift`, `ios/MeshActivity/*.swift` and `ios/Shared/*.swift` file has the header.
- **Rule/Source:** Project convention (CLAUDE.md, Licensing).
- **Fix:** Add headers to the three files (shell uses `#` comments after the shebang). Optionally add an `SPDX-License-Identifier: MIT` line to SnapshotHelper.swift.

### [LOW] Trademark symbol on first use and in permission strings
- **Where:**
  - `docs/app-store-description.md` "WORKS WITH: Meshtastic-compatible Bluetooth radios" has no ® (® appears only in the closing disclaimer).
  - `Info.plist` `NSBluetoothAlwaysUsageDescription` / `NSBluetoothPeripheralUsageDescription`: "Connects to your Meshtastic node ...".
  - UI strings such as `connection_banner.dart:551/559` ("Scanning for Meshtastic devices...").
- **What:** The Meshtastic trademark policy requires "proper trademark symbols are used in connection with the Meshtastic Trademarks" and the statement "Meshtastic® is a registered trademark of Meshtastic LLC." in support documentation. Name and branding are fine: "Mesh Analyzer", keywords deliberately exclude "meshtastic", and the disclaimer is in About, NOTICE, the license page and the description.
- **Rule/Source:** https://meshtastic.org/docs/legal/trademark/ ; Guideline 5.2.1.
- **Fix:**
  - Use "Meshtastic®-compatible" on first use in the store text.
  - Make the Bluetooth string protocol-neutral ("Connects to your LoRa mesh radio to collect signal data."), which also suits MeshCore later.
  - Keep the grant request planned in the roadmap before App Store release. Optionally use the M-PWRD compatibility logo instead of wording.

### [INFO] Export compliance: `ITSAppUsesNonExemptEncryption = NO` is defensible
- **Where:** `ios/Runner/Info.plist`; `radio_profile_service.dart:90-94` (`Random.secure()` 32-byte PSK); `meshtastic_radio.dart`.
- **What:** The app performs no encryption itself. It generates random bytes and writes them as a configuration value over BLE. AES on the channel and PKI DMs run in the radio firmware, and BLE link encryption is done by iOS.
  - The only cryptography in the app is TLS for HTTPS (Dart's BoringSSL inside Flutter) for tiles and elevation. That is standard, non-proprietary encryption used for data-in-transit authentication/confidentiality and is exempt.
  - No `crypto` or encryption calls exist in app code (`crypto` is a transitive dependency, used only for hashing).
- **Risk:** Low. Someone could argue that an app whose purpose includes configuring encryption keys on a radio is "key management". Its primary function, though, is RF coverage measurement, not information security (EAR Cat. 5 Pt. 2 Note 3/mass-market). If App Store Connect ever asks, answer: uses only exempt encryption (HTTPS) and does not implement encryption.
- **Rule/Source:** https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations (page body not retrievable, so the reasoning is from the export-compliance questionnaire categories).
- **Fix:** None. Keep the key. Don't add in-app AES (e.g. encrypted backups) without revisiting this.

### [INFO] NOTICE does not mention the elevation data source
- **Where:** `NOTICE`, `about_screen.dart` `registerAppLicenses()`.
- **What:** Open Topo Data (MIT software, GPXZ-hosted API), USGS 3DEP/NED (public domain) and SRTM (public domain) are not credited. No licence requires it, but the "Terrain-aware" view uses them.
- **Fix:** Add an entry to NOTICE and the license page.

## Could not verify

- **Privacy policy content:** the URL doesn't resolve, and `docs/beta/` (likely its source) was out of scope. Check manually that it covers OSM, Open Topo Data, StoreKit, local storage, CSV export, data deletion (there is `data_erase_service.dart`), children, contact and effective date.
- **Whether App Store Connect actually raises ITMS-91053 for the sqlite3 framework:** only an upload shows this. Do a TestFlight upload and check email. Confirm the exact FileTimestamp reason code (`C617.1` vs `DDA9.1`) on Apple's "Describing use of required reason API" page; the page body could not be fetched and secondary sources disagree.
- **Whether Meshtastic LLC has a CLA/copyright assignment** covering `meshtastic/protobufs`, or any informal App Store stance. Ask them directly together with the trademark grant.
- **Whether "Meshtastic-compatible" in an App Store description needs a written grant.** The trademark page bans the mark in "primary or secondary branding" and gives no rules for compatibility statements or app store listings.
- **Whether an offer-code-only non-consumable gets through IAP review** without being purchasable in the app. Apple documents offer codes for non-consumables but not reviewer handling.
- **TestFlight external-testing field requirements** (Beta App Description, feedback email, privacy policy URL, contact info) and the current age-rating questionnaire (13+/16+/18+ tiers introduced 2025). Check in App Store Connect. Expected answers: 4+, no UGC, no web access, not Made for Kids.
- **Commercial-use terms of api.opentopodata.org:** not stated on the site. Email the operator.
- **Apple's encryption-export page text:** the body did not render, so the reasoning above relies on the standard questionnaire categories.

## Checked, OK

- Paywall shows price, period ("1 year subscription, $4.99 per year", localized `displayPrice`), trial terms from StoreKit, and the full auto-renew disclosure (24 h cancel window, Apple ID charge, trial forfeit).
- "Restore Purchases" button is present when not Pro. Active Pro shows "Manage subscription" linking to apps.apple.com subscriptions.
- Terms of Use links to Apple's standard EULA (acceptable).
- Paywall appears only on a gated tap or the About row. No nags or urgency copy.
- The yearly subscription period (P1Y) and the P1W free trial meet the 3.1.2(a) minimum of 7 days.
- No alternative purchase path, no license keys and no in-app code entry (3.1.1). `PRO_OVERRIDE` only works when `kDebugMode` (`pro_entitlement.dart:237`).
- Lapsed Pro keeps viewing and exporting data. Nothing is locked.
- No ad, analytics, crash-reporting or tracking SDKs in pubspec or Podfile.lock. No HTTP code beyond tiles and elevation.
- `UIBackgroundModes` `location` and `bluetooth-central` are used only during a recording session, with the blue indicator (`gps_service.dart`). Only When-In-Use is requested (2.5.4, 5.1.2).
- Live Activity (`NSSupportsLiveActivities`); no entitlements file needed (no push, iCloud or app groups today).
- NOTICE covers every package in the runtime dependency graph that ships on iOS (85 entries, versions match `pubspec.lock`).
  - Omitted, all correctly: Android, Linux, Windows and Web implementations, plus `dbus`/`xml`/`petitparser`/`bluez` (Linux only) and `rxdart` (drift dev dependency).
  - All licences are permissive (BSD-2/3, MIT, Apache-2.0, ISC, public-domain SQLite). No copyleft besides the Meshtastic protobufs (GPL-3.0, listed).
- The licenses page registers NOTICE, the protobuf LICENSE and the OSM notice (`registerAppLicenses()`). Flutter adds package LICENSE files automatically. NOTICE and `lib/proto/LICENSE` are bundled assets.
- `lib/proto/LICENSE` is identical to upstream. `UPSTREAM.md` records the tag and commit and that the files are unmodified.
- The app name, display name ("Mesh Analyzer"), icon and keywords don't use "Meshtastic". The disclaimer is shown in About (`trademarkNotice`), NOTICE, the license page and the store description.
- Region dialog wording ("Using the wrong region can be illegal where you are") and airtime explainer ("in some regions regulations limit ...") make no compliance claims.
- No medical, safety, emergency or SOS claims in description.md, the store draft, README or UI strings.
- Screenshots use demo data, and README discloses that. Store copy describes the real UI.
- MeshActivity extension uses no required-reason APIs.

## Release checklist

**Before the public TestFlight link**
1. Publish the privacy policy at a URL that resolves. Update `privacyPolicyUrl`, add a Privacy row to About, and enter the URL in App Store Connect (App Privacy and TestFlight Test Information).
2. Make `github.com/motab619/mesh-analyzer` public, and tag the exact commit of each uploaded build.
3. Fix the paywall feature list: add the missing `rigProfiles` blurb, mark the shipped features as available, remove or separate the "Coming soon" ones, and add a test against "null".
4. Add `ios/Runner/PrivacyInfo.xcprivacy` (FileTimestamp, UserDefaults, no tracking, collected data matching the App Privacy answers) to the Runner target. Upload a build and check for ITMS-91053.
5. Add on-map OSM attribution to all three maps.
6. Correct the privacy wording ("data leaves the phone only when ...") in the store draft, description.md and README. Add a first-use notice for the terrain lookup.
7. Set Runner `TARGETED_DEVICE_FAMILY = 1`, unless iPad support is intended.
8. Improve `NSLocationWhenInUseUsageDescription` (and the Bluetooth string).
9. Fill in App Store Connect:
   - TestFlight Beta App Description, feedback email, contact info, "What to Test" (two radios required), and a review-notes video link.
   - App Privacy questionnaire (Location, App Functionality, not linked, no tracking).
   - Age rating questionnaire.
   - Export compliance: already answered by the plist key.
10. Add the SPDX headers to SceneDelegate.swift, RunnerTests.swift and gen_protos.sh.

**Before App Store release**
11. Write to Meshtastic LLC. Ask for (a) the trademark grant for compatibility wording and (b) written permission or a non-enforcement statement for App Store distribution of the GPL-3.0 protobuf-derived code. Archive the reply in the repo.
12. Add a COPYING.iOS-style §7 additional permission for Andy's own code. Consider a custom App Store Connect EULA referencing GPL-3.0 for the app's own code.
13. Add the Terms of Use (EULA) and privacy links plus a Pro subscription summary to the App Store description. Check the subscription group display name, localization and review screenshot.
14. Make sure at least one Pro feature is fully shipped and reachable for review. Submit the yearly subscription with the app version, and the lifetime non-consumable with notes explaining it is offer-code only.
15. Move map tiles and elevation to providers whose terms allow commercial use, or get written OK from OSMF and Open Topo Data. Never use tile.openstreetmap.org for offline packs.
16. Credit Open Topo Data, USGS 3DEP/NED and SRTM in NOTICE and on the license page.
17. Lead the paywall price line with the billed amount ($4.99/year) and put the trial second.
18. App Review Notes: hardware requirement, demo video with real radios, how to reach the Pro features, and that no account is needed.
19. Use "Meshtastic®-compatible" on first mention in the store text, and re-check the screenshots for any Meshtastic branding.
