# Mesh Analyzer: App Store compliance, licensing, privacy and trademark audit (update)

Tree audited: `field-build-oct23` working tree in `/Users/andybrunker/develop/mesh_analyzer`, including the uncommitted changes (new app icon, compass changes, `estimate_samples.dart`). The branch is 98 commits ahead of `main`. Date: 2026-11-04. Read-only except this file. `docs/beta/` ignored as instructed. Prior report: `docs/audit/2026-10-16/compliance.md`.

## Summary

A lot of the 2026-10-16 list is done. The privacy policy and support pages now resolve and the policy text is accurate for map tiles, Open Topo Data and the AI comparison analysis. Both targets ship a privacy manifest. The Runner is iPhone-only. All map screens carry OSM credit. NOTICE matches the iOS runtime dependency graph exactly, including the elevation sources and the MeshCore protocol references. The in-app Privacy screen, welcome flow and AI consent sheet describe each off-device flow behind its own switch and name Anthropic before anything is sent.

Two things would still stop a release. The GPL "Source code" link still returns 404 while builds go to external TestFlight testers. The new TestFlight Pro unlock keys off a sandbox receipt, and App Review installs carry a sandbox receipt too, so the reviewer would get Pro for free, never see the subscription offer and could not review the in-app purchase.

The paywall improved but now mislabels two shipped Pro features (MeshCore, Guided tests) as "Coming soon" while still listing four unbuilt ones. The App Store description, `description.md` and README still say data leaves the phone only on CSV export, which is false since the AI backend and the CloudFront tile server were added. The App Privacy story needs updating for the AI routes (a persistent install id, typed text and a usage digest go to the developer's Lambda and on to Anthropic), and the guided-test plan parser sends typed text on every Next without the "only when you tap Analyze" moment the Privacy switch promises. The native CocoaPods that `file_picker` pulls in (SDWebImage, DKImagePickerController, DKPhotoGallery, SwiftyGif) are not credited anywhere.

Counts: 2 BLOCKER, 4 HIGH, 6 MEDIUM, 6 LOW, 1 INFO.

## Findings

### [BLOCKER] GPL corresponding source still not available (in-app link 404)
- **Where:** `lib/ui/screens/about_screen.dart:39` (`sourceCodeUrl = 'https://github.com/motab619/mesh-analyzer'`), shown at `about_screen.dart:181-187` and in the license-page legalese at `about_screen.dart:197-199`; `docs/app-store-description.md:56`; `docs/roadmap.md:10-11` ("private for now ... public before App Store submission").
- **What:** `curl -sI https://github.com/motab619/mesh-analyzer` returns 404 on 2026-11-04. The binary contains code generated from the GPL-3.0 Meshtastic protobufs (`lib/proto/`, copyright Meshtastic LLC). Builds now go to external TestFlight testers (`tool/testflight/submit_external.rb`), which is conveyance of object code to the public, so GPL-3.0 section 6 requires the Corresponding Source to be available to each recipient now, not at App Store time. A dead link in the binary also breaks 2.1(a).
- **Rule/Source:** GPL-3.0 section 6 (`lib/proto/LICENSE`); App Store Review Guideline 2.1(a).
- **Fix:** Make the repository public (after the hygiene pass from the 2026-10-16 README item 14) and tag each uploaded build. Until then, give every external tester the source (a section 6(b) written offer or repo access) and stop adding external testers who have neither.

### [BLOCKER] TestFlight Pro unlock also unlocks Pro for App Review, hiding the subscription
- **Where:** `ios/Runner/AppDelegate.swift:38-41` (`isTestFlight` = `Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"`); `lib/services/test_build.dart:19-28` (release builds only); `lib/providers.dart:218` (`proOverride: DemoMode.enabled || TestBuild.unlockPro ? true : null`); `lib/services/pro_entitlement.dart:286` (`refresh()` returns early when overridden); `lib/ui/screens/pro_paywall_screen.dart:100-102, 313` (an overridden user sees only "You have Pro / Pro is enabled for this build.").
- **What:** App Review runs submitted builds in the sandbox environment, and their receipt file is the sandbox receipt. This is the reason Apple tells servers to retry a production receipt check against sandbox (status 21007). So the same check that makes TestFlight installs Pro makes the reviewer's install Pro. The reviewer then never sees the plan card, price, trial or Restore button, cannot buy the yearly subscription and sees a "Pro is enabled for this build" card. That is a 2.1(b) rejection ("in-app purchase items not visible or not functional") and, because the switch is undocumented, a 2.3.1(a) hidden-feature risk. CLAUDE.md already notes "Remove before launch". Separately, `appStoreReceiptURL` is deprecated from iOS 18 in favour of `AppTransaction`, whose `environment` is also `.sandbox` for both TestFlight and review, so switching API does not solve this.
- **Rule/Source:** Guidelines 2.1(b), 2.3.1(a), 3.1.2(c); Apple "Validating receipts with the App Store" (sandbox receipts in review).
- **Fix:** Make the unlock a build-time choice, not a runtime one: compile it in only for TestFlight lanes (for example `--dart-define=TESTFLIGHT_PRO=true` set by `fastlane beta`) and build App Store submissions without it, with a lane check that refuses to submit a build that has it. Or drop the unlock and give testers lifetime offer codes as the roadmap planned. Add a test that a release build without the define never overrides.

### [HIGH] Paywall labels shipped Pro features "Coming soon" and still sells four unbuilt ones
- **Where:** `lib/ui/screens/pro_paywall_screen.dart:190-195` (`_shipped` = rigProfiles, rigComparison, aiAnalysis only); `:224-230` (everything else gets the schedule icon and "Coming soon."); `:107-111` ("Pro adds the extras listed below as they ship."). Gates that already work: MeshCore `lib/ui/widgets/connection_banner.dart:572-575`; guided tests `lib/ui/screens/guided/ask_screen.dart:211-213`.
- **What:** The "null Coming soon." bug is fixed and three features are marked shipped. But tapping a MeshCore radio opens a paywall that says "MeshCore radios is a Pro feature" and, a few lines lower, "Map and test MeshCore radios too. Coming soon." The same contradiction applies to "Guided tests, 3-4 setups". Node placement advisor, PDF coverage report, Offline map packs and iCloud backup & sync are listed under "Pro features" with no code behind them. Reviewers read a subscription paywall as the description of what the price buys now.
- **Rule/Source:** 3.1.2(a) ongoing value; 3.1.2(c) describe what the user gets; 2.3 accurate metadata; 2.1(a) no placeholder content.
- **Fix:** Add `ProFeature.meshCore` and `ProFeature.guidedTests` to `_shipped`. Remove the four unbuilt features from the paywall (or move them to a clearly separate "Planned, not included yet" note) and change the intro sentence to describe what Pro includes today. Add a widget test that every shipped feature row has no "Coming soon".

### [HIGH] Store description, description.md and README still say data leaves only on CSV export
- **Where:** `docs/app-store-description.md:43` ("No account, no cloud, no tracking, no analytics. Data leaves the phone only when you export a CSV."); `description.md:128-133` ("The app contacts only two services ... Data otherwise leaves the phone only when you export a CSV."); `README.md:28` ("Everything stays on your phone. No account, no cloud, no analytics.").
- **What:** The app contacts five services today (see the host list under Checked, OK): the developer's CloudFront tile server (`lib/utils/map_tiles.dart:67-78`), tile.openstreetmap.org outside Southern California (`map_tiles.dart:89`), api.opentopodata.org when terrain is on (`lib/services/terrain/open_topo_data_source.dart:29`), and the AI Lambda (`lib/utils/constants.dart:16-17`), which forwards to Anthropic. The in-app copy is now right (`about_screen.dart:265-276`, `privacy_screen.dart:35-66`, `welcome_flow.dart:370-410`) and so is the hosted privacy policy, so the store text contradicts both the app and the policy. "No cloud" is also hard to square with a cloud AI backend.
- **Rule/Source:** 2.3 and 2.3.1 (metadata, "including privacy information", must be accurate); 5.1.1(i).
- **Fix:** Replace the three passages with wording that matches the Privacy screen, for example: "No account, no analytics, no tracking. Your sessions stay on your phone. Map tiles come from our tile server or OpenStreetMap; the optional terrain view sends map coordinates to Open Topo Data; the optional AI analysis (Pro) sends a numbers-only summary to our server and Anthropic. Nothing else leaves the phone unless you export it."

### [HIGH] GPL-3.0 Meshtastic protobufs distributed through the App Store without permission
- **Where:** `lib/proto/` (upstream v2.7.26, `lib/proto/LICENSE` plain GPL-3.0); `LICENSE` (plain GPL-3.0, no section 7 additional permission); no permission letter or COPYING.iOS-style file anywhere in the repo.
- **What:** Unchanged since 2026-10-16. Apple's Usage Rules are widely held (FSF, the VLC removal) to be "further restrictions" under GPL-3.0 sections 10 and 12. Meshtastic LLC's own App Store app is their choice, not a grant to third parties. MeshCore support is now a second protocol, but Meshtastic support still links the generated protobuf code.
- **Rule/Source:** GPL-3.0 sections 6, 10, 12; Guideline 5.2.1.
- **Fix:** As before: public source first; ask Meshtastic LLC in writing (with the trademark request in `docs/roadmap.md:298`) for permission or a non-enforcement statement for App Store distribution; add a section 7 App Store permission for your own code; fallback is a hand-written wire codec for the handful of messages used (get advice).

### [HIGH] Reviewers cannot exercise the app or the Pro features without two radios
- **Where:** Demo mode only via the `-MeshDemo` launch argument or `MESH_DEMO` env (`lib/demo/demo_mode.dart:12-48`); no UI entry (no "demo" strings under `lib/ui` other than comments). No App Review notes draft in the repo (`docs/app-store-description.md` has listing text and "What to test" only).
- **What:** Since the last audit the paid tier grew to MeshCore radios, AI analysis of a comparison, Guided tests with 3-4 setups, and remote base changes. Every one needs at least two radios and recorded sessions. Once the TestFlight unlock is fixed (BLOCKER above), the reviewer will see a working paywall but no way to reach any Pro feature, which invites a 2.1 "unable to review" rejection or a 3.1.2 "subscription provides no value we can verify". Raised from MEDIUM because the subscription now depends on it.
- **Rule/Source:** Guideline 2.1 (provide a demo mode or video for hardware-dependent features); 2.3.1(a) (the launch-arg demo is a dev tool, not a reviewer path); 3.1.2(a).
- **Fix:** Write App Review notes: two radios required, a screen recording with real radios covering connect, Radio Setup, a session, out-of-range alert, Live Activity, paywall purchase and Restore, a MeshCore connection, an AI analysis and a guided test. Consider a visible "Try with sample data" entry that opens the existing demo database, which would also let the reviewer reach Compare, AI analysis and the guided-test screens.

### [MEDIUM] App Privacy answers and the privacy manifest do not cover the AI routes
- **Where:** `ios/Runner/PrivacyInfo.xcprivacy:9-10` (`NSPrivacyCollectedDataTypes` empty). Off-device data: `lib/services/ai_analysis.dart:586-595` (POST body = digest, headers `X-Device-Id`, `X-App-Version`); `ai_analysis.dart:700-707` (install id is a UUID kept in prefs `ai_device_id`); `lib/services/guided/plan_intent_parser.dart:701-746` (typed text, rig names, preset names); server side `tool/ai-analysis/handler.py:339-359` (DynamoDB items `dev#<id>#<day>` and `devm#<id>#<month>`, TTL `handler.py:279-289`, kept up to about 34 days) and the forward to Anthropic (`handler.py:396-400`).
- **What:** The developer's server receives and stores a persistent per-install identifier for up to a month and receives free text the user typed plus usage numbers, and a third party (Anthropic) processes them. Under App Privacy Details that is collection (it is kept longer than needed to answer the request, and it goes to a third party), so the App Store Connect answers and the manifest's `NSPrivacyCollectedDataTypes` should list it. The policy text already describes this well; the label and manifest just need to agree with it. Apple's optional-disclosure exception may cover the comparison digest (optional, user-initiated, prominently disclosed), but the stored identifier is the part that clearly does not fit it.
- **Rule/Source:** App Store Connect "App privacy details" (definition of collect, optional disclosure criteria); 5.1.1(i), 5.1.2(i); Apple "Privacy manifest files" (collected data types must match).
- **Fix:** In App Store Connect declare, not linked to identity, not used for tracking, purpose App Functionality: Identifiers / Device ID (the random install id), User Content / Other User Content (the typed question or plan text), Usage Data / Other Usage Data or Other Data (the digest). Keep Location (Precise) for Open Topo Data as recommended last time unless you decide it qualifies for the real-time exception. Mirror the same entries in `NSPrivacyCollectedDataTypes`.

### [MEDIUM] Guided-test plan parser sends typed text to the AI without the per-request step the copy promises
- **Where:** `lib/ui/screens/guided/ask_screen.dart:186-187` (every Next with typed text calls the parser); `plan_intent_parser.dart:694-706` (sends whenever consent is on; no Pro check, `providers.dart:539-546`); `lib/ui/screens/privacy_screen.dart:61-66` and `welcome_flow.dart:403-409` ("AI session analysis (Pro) ... only when you tap Analyze"); `ask_screen.dart:298-301` ("If you type, what you wrote is sent to an AI helper", no mention of Anthropic or of the consent switch). Hosted policy: describes AI only as "if you tap Analyze with AI on a comparison".
- **What:** The consent switch is labelled as a Pro comparison feature that sends only on Analyze, but once on, every typed request on the Ask screen also goes to the Lambda and Anthropic, for free users too, and a guided-test result (`kind: guidedTest`, `handler.py:1040-1041`) is a third route. The consent sheet does list "the question or context you type in the box", so the user did agree to typed text, but not to it being sent outside an Analyze tap. The Ask screen note also says the text "is sent" even when consent is off and nothing is sent. 5.1.2(i) now asks for clear disclosure of sharing with third-party AI.
- **Rule/Source:** 5.1.1(i), 5.1.2(i) (third-party AI disclosure and permission); 2.3.
- **Fix:** Reword the switch to "AI helpers" covering both uses ("a numbers-only summary when you tap Analyze, and what you type when planning a test, go to our server and Anthropic"). Make the Ask note conditional on consent and name Anthropic. Add the plan and guided-test routes to the hosted privacy policy (in the plateau-beta repo).

### [MEDIUM] Native iOS libraries from file_picker are not credited
- **Where:** `ios/Podfile.lock:2-20` (DKImagePickerController 4.3.9, DKPhotoGallery 0.0.19, SDWebImage 5.21.7, SwiftyGif 5.4.5, all pulled in by `file_picker`); `NOTICE` has no entry for any of them (only Dart packages and SQLite); `about_screen.dart:50-83` adds no native licences; Flutter's license page only adds Dart package LICENSE files.
- **What:** All four are MIT (`ios/Pods/*/LICENSE`: Bannings, Olivier Poitrey, Alexis Creuzot) and are compiled into the app. MIT requires the copyright and permission notice to accompany copies of the software. NOTICE is otherwise complete.
- **Rule/Source:** MIT License; project rule "Add new runtime packages to NOTICE" (CLAUDE.md).
- **Fix:** Add a "Native iOS libraries (via file_picker)" section to NOTICE with the four names, versions, copyright lines and MIT. The NOTICE text is already shown on the license page, so that covers the in-app display.

### [MEDIUM] Hidden lifetime non-consumable sold only via offer codes (unchanged)
- **Where:** `ios/Runner/Products.storekit:8-20` (`com.andybrunker.meshAnalyzer.pro.lifetime`, NonConsumable, now 18.99); `lib/services/pro_entitlement.dart:18-23` (`proProductIds = {proYearlyId}`, lifetime never queried), `:413` (honoured when owned).
- **What:** Same as last time: the IAP reviewer cannot find the product in the app, and 2.1(b) asks for IAPs to be visible and functional. The app handles ownership correctly ("Lifetime plan" card). The TestFlight unlock makes it worse, because the reviewer sees "You have Pro" without owning either product.
- **Rule/Source:** 2.1(b), 3.1.1; Apple "Create offer codes for in-app purchases".
- **Fix:** In the IAP review notes say it is distributed only through offer codes to beta testers, attach a StoreKit-test screenshot of the Lifetime card, and be ready to submit it after the app is approved.

### [MEDIUM] Commercial app still relies on free community services outside the self-hosted area
- **Where:** OSM fallback outside `hostedBoundsSWNE` (`lib/utils/map_tiles.dart:82, 89, 187-192`); Open Topo Data public API (`open_topo_data_source.dart:15-36`, 1000/day counted in memory).
- **What:** Partly fixed: streets and hillshade inside Southern California now come from the developer's own PMTiles on CloudFront, and elevations are disk-cached. Everywhere else the app still uses tile.openstreetmap.org ("commercial services ... access may be withdrawn at any point") and the Open Topo Data public API, which has no statement allowing production or commercial use.
- **Rule/Source:** https://operations.osmfoundation.org/policies/tiles/ ; https://www.opentopodata.org/
- **Fix:** Before a paid App Store release, either widen the self-hosted coverage or move the fallback to a provider whose terms allow commercial apps, and email Open Topo Data (or use GPXZ or self-host) for elevations.

### [MEDIUM] OSM attribution is collapsed (and partly covered) on Compare and the guided walk map
- **Where:** `lib/ui/widgets/base_map_layers.dart:158-160` (`RichAttributionWidget` with `popupInitialDisplayDuration: Duration.zero`, so only the "i" button shows until tapped), used in `lib/ui/screens/rig_comparison_screen.dart:496` and `lib/ui/widgets/guided/walk_map.dart:259`. On Compare it is listed before `PolygonLayer` (`rig_comparison_screen.dart:495-501`), so the coverage polygons paint over it.
- **What:** Partly fixed: the Live map (`map_screen.dart:583`) and coverage map detail (`coverage_map_detail_screen.dart:680-685`) show an always-visible "© OpenStreetMap contributors" chip, which is good. The other two maps show the credit only behind a tap.
- **Rule/Source:** OSM tile usage policy and attribution guidelines ("Do not hide attribution beneath UI, behind toggles, or off-screen"); ODbL.
- **Fix:** Use `MapCreditChip` on those two maps as well (or give `RichAttributionWidget` a non-zero initial display), and put the attribution after the data layers.

### [LOW] Bluetooth usage string and store text: Meshtastic-only wording, no registered mark
- **Where:** `ios/Runner/Info.plist:48-51` ("Connects to your Meshtastic-compatible radio to collect signal data."); `docs/app-store-description.md:18` ("Meshtastic-compatible Bluetooth radios", no ®; the ® appears only in the closing disclaimer at line 58).
- **What:** The app now also talks to MeshCore radios, so the permission prompt is inaccurate for MeshCore users and uses the Meshtastic mark in a system prompt without the symbol. The Meshtastic trademark policy asks for proper marks in connection with the name.
- **Rule/Source:** 5.1.1(ii) (purpose strings must describe the use); https://meshtastic.org/docs/legal/trademark/ ; 5.2.1.
- **Fix:** Make the string protocol-neutral ("Connects to your LoRa mesh radios to collect signal data."). Use "Meshtastic®-compatible" on first use in the store text, and mention MeshCore factually (as a Pro feature) if you want it in the listing.

### [LOW] Store description details no longer match the app
- **Where:** `docs/app-store-description.md:27` ("The base beacons every 15 seconds"); telemetry beacons are rounded up to whole minutes, at least 60 s (`lib/data/radio/radio_types.dart:485-491`), and firmware 2.8 always uses telemetry. `:18` says firmware 2.5 or later and only Meshtastic; MeshCore companion support is not mentioned while the paywall sells it.
- **Rule/Source:** 2.3, 2.3.1 (metadata must reflect the app's core experience).
- **Fix:** Say the base beacons on a schedule you choose (about once a minute on current firmware) and that pings default to 15 s; add a line on MeshCore companion radios with Pro.

### [LOW] flutter_compass runs device-motion updates for the whole app lifetime
- **Where:** `~/.pub-cache/hosted/pub.dev/flutter_compass-0.8.1/ios/Classes/SwiftFlutterCompassPlugin.swift:14-21` (`motion.startDeviceMotionUpdates` at 30 Hz in `init`, called from `register` at launch; never stopped; `onCancel` stops only heading).
- **What:** CLAUDE.md says the compass is "subscribed only while the mode is active", which holds for heading but not for the 30 Hz CoreMotion updates the plugin starts at launch. No usage string is needed (CMMotionManager device motion is not permission-gated) and the plugin uses no required-reason APIs, so this is not a privacy-manifest problem. It is a battery cost in an app that records for hours with the phone locked, and the plugin (0.8.1) is unmaintained.
- **Rule/Source:** Guideline 2.4.2 (use power efficiently); 2.5.4 spirit for background work.
- **Fix:** Replace the plugin with a small method channel that uses `CLLocationManager.startUpdatingHeading` only while heading up is active (or vendor a patched copy that starts motion in `onListen` and stops it in `onCancel`).

### [LOW] Unused Always-location key and iPad orientation keys remain
- **Where:** `ios/Runner/Info.plist:52-53` (`NSLocationAlwaysAndWhenInUseUsageDescription`), `:98-104` (`UISupportedInterfaceOrientations~ipad`).
- **What:** The When-In-Use string is now good (`Info.plist:54-55`) and only When-In-Use is requested (`lib/services/gps_service.dart:95-96`, Podfile no longer sets `PERMISSION_LOCATION_ALWAYS`). The Always key is harmless but suggests Always access to a reviewer. The iPad keys are dead since `TARGETED_DEVICE_FAMILY = 1`.
- **Rule/Source:** 5.1.1(ii), 2.5.4.
- **Fix:** Remove both keys.

### [LOW] SPDX header missing on the fastlane Fastfile
- **Where:** `ios/fastlane/Fastfile:1` (starts with a comment header, no SPDX line).
- **What:** The three files flagged last time now have headers (`ios/Runner/SceneDelegate.swift`, `ios/RunnerTests/RunnerTests.swift`, `tool/gen_protos.sh`), and every other authored source in `lib`, `test`, `tool`, `ios/Runner`, `ios/MeshActivity` and `ios/Shared` has one, including the new `lib/services/estimate_samples.dart`, `tool/ai-analysis/*.py`, `template.yaml`, `tool/testflight/*.rb` and `tool/tiles/render/render.mjs`. Not covered: the Fastfile (authored Ruby), `tool/ai-analysis/samconfig.toml`, and the JSON files `tool/tiles/render/style.json` and `package.json` (JSON cannot carry comments; fine to leave). `ios/RunnerUITests/SnapshotHelper.swift` is fastlane's MIT file and should keep its own header. The Objective-C/Flutter-generated `GeneratedPluginRegistrant.*` and `Runner-Bridging-Header.h` are generated or boilerplate.
- **Rule/Source:** Project convention (CLAUDE.md, Licensing).
- **Fix:** Add the 4-line header to `ios/fastlane/Fastfile` (and optionally `samconfig.toml`).

### [LOW] New icon artwork: origin not recorded
- **Where:** `tool/icon_art.png` (1254 px pixel art: a base node with signal arcs, green-to-red dots, a striped synthwave sun and purple mountains); `tool/make_icon.py:7-12`; CLAUDE.md "App icon: drawn by `tool/make_icon.py`" is now out of date.
- **What:** The artwork has nothing in common with the Meshtastic logo (a green "M" built from two chevrons) or the MeshCore wordmark, uses no text and no third-party marks, and the striped sun is a generic 1980s motif, so I see no confusion risk. What is missing is a note of where the PNG came from (drawn by you, commissioned, or made with an image generator) and under what terms, which matters for a GPL repo and for 5.2.1 if anyone ever asks. The rendered icons have no alpha channel (checked with `sips`), as App Store Connect requires.
- **Rule/Source:** Guideline 5.2.1; GPL source distribution hygiene.
- **Fix:** Add one line to `make_icon.py` (or NOTICE) stating the artwork's origin and licence, and update the CLAUDE.md icon line.

### [INFO] Export compliance: `ITSAppUsesNonExemptEncryption = NO` still defensible
- **Where:** `ios/Runner/Info.plist:42-43`; `lib/services/radio_profile_service.dart:142-146` and `lib/data/radio/meshcore/meshcore_radio.dart:75` (`Random.secure()` key and tag bytes); `lib/data/radio/meshcore/meshcore_sha256.dart:12` (SHA-256 for MeshCore packet ids).
- **What:** New since last time: a pure-Dart SHA-256 used only to compute packet ids, and remote admin (`MeshtasticRadio.setRemoteLora`) whose PKI encryption is done by the radio firmware. Hashing is not encryption for EAR purposes, and the app still implements no cipher itself. All network traffic (tiles, elevation, Lambda) is standard HTTPS, which is exempt.
- **Rule/Source:** Apple "Complying with encryption export regulations"; EAR Cat. 5 Part 2 Note 3.
- **Fix:** None. Revisit if the app ever encrypts backups or data itself.

## Prior findings (2026-10-16)

| Finding | Status | Evidence |
|---|---|---|
| [BLOCKER] Privacy Policy URL does not resolve | Fixed | `curl -sI https://beta.plateaunerd.com/privacy/mesh-analyzer` = 200; constant at `pro_paywall_screen.dart:16`; Privacy row on About `about_screen.dart:223-228`, Settings → Privacy `privacy_screen.dart:87`, welcome flow `welcome_flow.dart:426`. Policy text (effective 2026-11-01) covers CloudFront, OSM, Open Topo Data, AI comparison analysis, install id, Apple, children, contact. Missing only the plan-parser route (MEDIUM above). |
| [BLOCKER] GPL corresponding source not available | Still open | `about_screen.dart:39`; GitHub URL returns 404. |
| [BLOCKER] Paywall "Coming soon" on everything, "null" row | Partly fixed | All blurbs present (`pro_paywall_screen.dart:197-211`), shipped set exists (`:190-195`); MeshCore and Guided tests wrongly "Coming soon", four unbuilt features still listed (HIGH above). |
| [HIGH] Privacy claims contradict network behaviour | Partly fixed | In-app copy correct (`about_screen.dart:265-276`, `privacy_screen.dart:35-66`, `welcome_flow.dart:370-410`), terrain off by default with a switch, map tiles can be turned off (`privacy_settings.dart:52-55`, `base_map_layers.dart:54`). Store draft `docs/app-store-description.md:43`, `description.md:128-133`, `README.md:28` still wrong (HIGH above). |
| [HIGH] No privacy manifest | Fixed (data types open) | `ios/Runner/PrivacyInfo.xcprivacy` (UserDefaults CA92.1, FileTimestamp C617.1, no tracking) and `ios/MeshActivity/PrivacyInfo.xcprivacy`, both in Resources build phases (`project.pbxproj:17-18, 437, 445`). `NSPrivacyCollectedDataTypes` empty although the AI routes collect (MEDIUM above). |
| [HIGH] Terms of Use (EULA) link missing from metadata | Fixed in the draft | `docs/app-store-description.md:50-53` (price, trial, renewal terms, EULA and privacy links). App Store Connect fields not checkable from here. |
| [HIGH] GPL-3.0 protobufs on the App Store | Still open | `lib/proto/LICENSE`, `LICENSE`; no permission or section 7 text in repo. |
| [HIGH] No OSM attribution on the map screens | Partly fixed | Visible chip on Live (`map_screen.dart:583`) and map detail (`coverage_map_detail_screen.dart:680-685`); collapsed `RichAttributionWidget` on Compare (`rig_comparison_screen.dart:496`) and the guided walk map (`walk_map.dart:259`) (MEDIUM above). |
| [MEDIUM] Free community services under a commercial app | Partly fixed | Self-hosted PMTiles for Southern California (`map_tiles.dart:67-85`), CloudFront logging off (`tool/tiles/host_setup.sh:12-13, 64`); OSM elsewhere and Open Topo Data public API remain. |
| [MEDIUM] Universal (iPad) build | Fixed | `TARGETED_DEVICE_FAMILY = 1` in every configuration (`project.pbxproj:692, 799, 857, 911, 982, 1010, 1028, 1047, 1076`). Leftover `~ipad` orientations (LOW above). |
| [MEDIUM] Reviewers cannot exercise the app | Still open (raised to HIGH) | Demo only via launch arg (`demo_mode.dart:12-48`); no review notes draft. |
| [MEDIUM] Hidden lifetime non-consumable | Still open | `Products.storekit:8-20`, `pro_entitlement.dart:18-23`. |
| [MEDIUM] Location usage strings | Fixed | `Info.plist:54-55` mentions locked-screen recording; Always never requested (`gps_service.dart:95-96`); Podfile has only `PERMISSION_BLUETOOTH=1` (`ios/Podfile:49`). Unused Always key remains (LOW above). |
| [LOW] Price prominence and trial wording | Fixed | Plan card title leads with the billed amount, "Yearly · $6.99/year" in bold (`pro_paywall_screen.dart:140-148`); trial in the second line. |
| [LOW] SPDX headers missing | Fixed (one new gap) | SceneDelegate.swift, RunnerTests.swift, gen_protos.sh now have headers; `ios/fastlane/Fastfile` lacks one (LOW above). |
| [LOW] Trademark symbol on first use and in permission strings | Partly fixed | UI scan text now "Scanning for radios..." (`connection_banner.dart:675`); store text line 18 and the Bluetooth string still lack ® and the string is Meshtastic-only (LOW above). |
| [INFO] Export compliance | Still OK | See INFO above. |
| [INFO] NOTICE lacks elevation credit | Fixed | `NOTICE:51-69` (OpenMapTiles CC-BY-4.0, USGS 3DEP, NASA SRTM, Open Topo Data datasets); map credits `map_tiles.dart:93-98`. |

## Checked, OK

- **Complete list of hosts the app contacts** (grep of `http` in `lib`, `ios`, `tool`, excluding `lib/proto` and generated code):
  - `d13u6w4g5rrbl6.cloudfront.net` (own PMTiles: streets, hillshade, contours; `map_tiles.dart:67-78`), only when the Map tiles switch is on; resolves (200).
  - `tile.openstreetmap.org` (fallback outside the covered box, `map_tiles.dart:89`), with `userAgentPackageName` set (`base_map_layers.dart:63, 72`).
  - `api.opentopodata.org` (`open_topo_data_source.dart:29`), only when `terrain_online_enabled` is on (`providers.dart:309-313`, default off).
  - `3bcigbfgfzlr356zaubtr3lqju0rfkll.lambda-url.us-west-2.on.aws` (`constants.dart:16-17`), only with AI consent (`ai_analysis.dart:710`, `plan_intent_parser.dart:694`); the Lambda forwards to Anthropic (`handler.py:396-400`).
  - Apple StoreKit (OS-handled).
  - User-initiated links only (`url_launcher`): beta.plateaunerd.com privacy and support (200), plateaunerd.com (200), github.com repos (MeshCore, MeshMapper, meshcore-open, protobufs: 200; own repo 404), openstreetmap.org/copyright (200), apple.com EULA (200), apps.apple.com subscriptions (302 to account.apple.com), openmaptiles.org (200), usgs.gov 3DEP (403 to curl, a bot block; opens in a browser), `mailto:andy@plateaunerd.com` with the digest for "Report a problem".
  - Not requests: `meshtastic.org/e/#...` (built channel link, `radio_backup_service.dart:408`), `api.meshcore.nz` (doc comment for the preset snapshot, `meshcore_presets.dart:239`), `maps.google.com` icon URLs inside exported KML (`kml.dart:58, 88`, fetched by Google Earth, not the app), `http://localhost` (dev tile override).
- **Coordinates never go to the AI backend:** the digest is built from aggregates only (`ai_analysis.dart:69-171`, one decimal), `assertNoLocationData` runs before every send (`ai_analysis.dart:440-466, 735-736`) and rejects position, key and id fields and coordinate-like pairs or text; the plan parser refuses coordinate-like text (`plan_intent_parser.dart:696-699`). The Lambda logs only token counts and reasons (`handler.py:1055-1077`), and stores only counters with TTLs.
- **Third-party AI consent (5.1.2(i)):** a consent sheet lists what is and is not sent and names Anthropic before the first send (`ai_analysis_card.dart:389-435`), consent can be withdrawn in Settings → Privacy with an option to delete saved answers (`privacy_screen.dart:100-124`); AI output carries a clear disclaimer (`about_screen.dart:29-35`).
- **Background location:** `UIBackgroundModes` location and bluetooth-central (`Info.plist:83-87`); background updates only between session start and end (`session_manager.dart:338, 385`, `gps_service.dart:221-238`) with the blue indicator.
- **Usage strings vs requests:** location When-In-Use (`gps_service.dart:95-96`), Bluetooth (`connection_banner.dart:383-400`), notifications (`out_of_range_monitor.dart:104`, no plist key needed), photo library string present for `file_picker`'s DK pods; compass needs no key (heading is part of location authorization, CoreMotion device motion is not permission-gated).
- **Privacy manifests of shipped pods:** file_picker, DKImagePickerController, DKPhotoGallery, SDWebImage and SwiftyGif ship `PrivacyInfo.xcprivacy`; the sqlite3 pod does not, which is what the app-level FileTimestamp C617.1 entry covers. flutter_compass and flutter_blue_plus_darwin ship none and use no required-reason APIs. The Runner and MeshActivity Swift files use none (`ProcessInfo.arguments` and `appStoreReceiptURL` are not on the list).
- **Subscription paywall basics:** localized price and period, trial from StoreKit, full auto-renew disclosure (`pro_paywall_screen.dart:277-296`), Restore Purchases, Manage subscription, Privacy Policy and Terms of Use links, lapsed users keep viewing and exporting (`pro_entitlement.dart` `canView` = true), no nags. No alternative purchase path, no in-app code entry (3.1.1).
- **`PRO_OVERRIDE`:** only in debug builds (`pro_entitlement.dart:47-48, 240`). Demo mode needs a launch argument or environment variable, which App Store users cannot set.
- **NOTICE:** every package in `flutter pub deps --no-dev` that ships on iOS is listed with the exact `pubspec.lock` version (125 deps, 92 entries; the 33 omitted are Android, Linux, Windows and Web implementations, `flutter`, `sky_engine`, and Linux-only `bluez`, `dbus`, `xml`, `petitparser`, `rxdart`). Native gaps are the file_picker pods only (MEDIUM above). B612 (OFL) is bundled with its licence text and registered (`about_screen.dart:74-77`).
- **MeshCore MIT references:** NOTICE `:26-40` and the license page (`about_screen.dart:62-73`) credit MeshCore firmware, MeshMapper and meshcore-open with copyright lines and state that no code was copied; the preset table is a snapshot of factual radio settings. The MeshCore non-affiliation notice is on About (`about_screen.dart:302`) and in NOTICE.
- **Trademark:** app name, display name (`Info.plist:9-10`, extension `ios/MeshActivity/Info.plist`), icon and keywords use neither "Meshtastic" nor "MeshCore"; the Meshtastic disclaimer is on About, NOTICE, the license page, the store text and the hosted policy. UI uses the names only factually.
- **Live Activity:** `NSSupportsLiveActivities`, local updates only, no push entitlement; the extension's manifest declares nothing and it uses no required-reason APIs.
- **Remote base changes:** off unless the user leaves "Allow the mobile radio to change this base from a distance" on in Radio Setup; no App Store rule is touched, and the encryption is in the radio firmware.
- **Hosted privacy policy** is consistent with the in-app copy on CloudFront (no logs, matching `host_setup.sh:64`), OSM, Open Topo Data, the install id and its retention (matching `handler.py:279-289`), StoreKit, local notifications and children.
- App icon PNGs have no alpha channel; the 1024 px marketing icon is 1024 x 1024.

## Could not verify

- App Store Connect fields (App Privacy answers, age rating questionnaire, TestFlight test information, IAP review screenshots and notes). Check them against the MEDIUM privacy finding.
- Whether the current age-rating questionnaire asks about AI-generated content; answer it with the AI analysis and plan helper in mind.
- That the live CloudFront distribution really has logging disabled (only the setup script was read).
- Commercial-use terms of api.opentopodata.org, and any Meshtastic LLC reply on trademark or App Store distribution.
- The origin of `tool/icon_art.png`.
