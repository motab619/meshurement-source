# Release-readiness audit: first TestFlight public beta

Tree: beta-audit worktree @ 5806515. Read-only audit.

## Summary
- No upload-blocking defects found: version/build wiring for app and MeshActivity extension is consistent (both derive from Flutter's `FLUTTER_BUILD_NAME/NUMBER`), icons complete with no alpha, PRO_OVERRIDE is debug-only, secrets are gitignored.
- `flutter analyze`: No issues found. `flutter test`: 223 tests, all passed, no skips, ~11 s.
- Main gaps are process and metadata: no CI, `beta` lane runs no tests, no fastlane metadata, no feedback email in repo, README/description.md stale on pricing and tab names, iPad is still a targeted device family.
- Version is 0.1.0+1 (build number is overwritten by the lane to TestFlight latest + 1).

## Findings

### [HIGH] iPad is a targeted device but the app says iPad is unsupported
**Where**: ios/Runner.xcodeproj/project.pbxproj (project-level and Profile config `TARGETED_DEVICE_FAMILY = "1,2"`; extension/tests use `1`); Runner/Info.plist has `UISupportedInterfaceOrientations~ipad`; README.md "Not supported: ... iPad-only setups".
**What**: Runner ships as iPhone+iPad universal. TestFlight will offer it to iPad testers and App Store submission will demand iPad screenshots (only iPhone 18 Pro Max screenshots exist). Live Activity does not exist on iPad, and the UI has not been verified there (no iPad snapshot, no layout tests).
**Fix**: Either set `TARGETED_DEVICE_FAMILY = 1` on the Runner target (all configs) and remove the `~ipad` orientation key, or test on an iPad simulator and add iPad screenshots. For a BLE+GPS walking tool, iPhone-only is the simpler choice.

### [HIGH] `beta` lane has no safety gate before uploading
**Where**: ios/fastlane/Fastfile (lane `beta`).
**What**: The lane goes straight from `flutter build ios --release` to upload. It does not run `flutter analyze`/`flutter test`, does not check for a clean git tree, and does not verify the extension's version/build equals the app's after the build. A broken or dirty build ships to testers. (It correctly uses `--release`, passes no dart-defines, so PRO_OVERRIDE cannot leak; and PRO_OVERRIDE is additionally `kDebugMode && ...` in lib/services/pro_entitlement.dart:237.)
**Fix**: Add at the top of the lane `sh("cd .. && flutter analyze && flutter test")` and `ensure_git_status_clean`; after `build_app`, optionally assert both Info.plists in the .ipa have equal `CFBundleShortVersionString`/`CFBundleVersion`.

### [MEDIUM] No CI
**Where**: no `.github/`.
**What**: Nothing runs analyze/tests on PRs or main.
**Fix**: Add `.github/workflows/ci.yml` on `push`/`pull_request`, `runs-on: macos-latest` (or ubuntu; tests are pure Dart/widget): `actions/checkout@v4`, `subosito/flutter-action@v2` with `channel: stable` and `flutter-version: 3.41.4`, `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs` (only if `app_database.g.dart` is not committed), `flutter analyze`, `flutter test`.

### [MEDIUM] No TestFlight/App Store metadata in fastlane; feedback email not in repo
**Where**: ios/fastlane/ has only `Fastfile`, `Snapfile`, `.env.example`, `screenshots/`. docs/app-store-description.md has a "What to test" and support URL suggestion but no feedback email, no beta description, no review contact.
**What**: TestFlight external review needs Beta App Description, feedback email, privacy policy URL, review contact and (if sign-in needed) none. Privacy URL exists only as a constant: `https://beta.plateaunerd.com/privacy/mesh-analyzer` (lib/ui/screens/pro_paywall_screen.dart:14); not verified live here (docs/beta is out of scope). The app also needs the IAP products (`com.andybrunker.meshAnalyzer.pro.yearly`, `.lifetime`) created and attached/"Ready to Submit" in App Store Connect, otherwise the paywall shows no offer to testers and reviewers.
**Fix**: Fill in App Store Connect > TestFlight > Test Information by hand (draft below), confirm the privacy URL returns 200, make sure the subscription group has localization, price and a review screenshot. Optionally add `fastlane/metadata/en-US/` for later.

### [MEDIUM] README says App Store build is "a paid convenience build"
**Where**: README.md "Get it" section (line ~87).
**What**: Contradicts the shipped model (free core + Pro $4.99/yr with 1-week trial; CLAUDE.md Monetization). Testers/reviewers reading the repo get wrong pricing.
**Fix**: "Free on TestFlight/App Store; optional Pro subscription for creating rig profiles and comparisons. Source is GPL-3.0; build it yourself as above."

### [MEDIUM] description.md uses old tab name
**Where**: description.md:97 "Maps tab -> tap a map".
**What**: Tabs are now Live, Coverage, Settings (lib/app.dart:212-222). Nodes moved into Settings. description.md also has no mention of Pro/pricing or roles (base vs mobile).
**Fix**: "Coverage tab". Add a short Pro section if description.md is used as the store text.

### [MEDIUM] Declared dependency on end-of-life package
**Where**: `sqlite3_flutter_libs` (pubspec.lock 0.5.42; latest 0.6.0+eol).
**What**: Package is marked end-of-life upstream; fine for the beta, but drift's recommended setup has changed. No package is flagged `discontinued` in pubspec.lock.
**Fix**: Post-beta task: follow drift 2.3x migration (sqlite3 3.x build hooks). Do not change before beta.

### [LOW] Version 0.1.0 reads as pre-alpha for public testers
**Where**: pubspec.yaml `version: 0.1.0+1`; ios/Flutter/Generated.xcconfig is untracked/generated.
**What**: Not an error. Build number comes from the lane (TestFlight latest + 1), so `+1` in pubspec is ignored.
**Fix**: Set `version: 0.9.0+1` for the beta (1.0.0 for App Store release). If any build with a higher version string was ever uploaded for this bundle id, the new train must be >= it.

### [LOW] SPDX header missing on a few authored files
**Where**: ios/Runner/SceneDelegate.swift, ios/RunnerTests/RunnerTests.swift, tool/gen_protos.sh. (ios/RunnerUITests/SnapshotHelper.swift is fastlane's MIT-licensed generated file; leave it, mention in NOTICE if desired.)
**Fix**: Add the 4-line header (CLAUDE.md rule) to the three files.

### [LOW] Demo mode is reachable in release builds
**Where**: lib/demo/demo_mode.dart `DemoMode.detect()` reads `MESH_DEMO` env / `-MeshDemo` launch argument without a debug guard; ios/Runner/AppDelegate.swift exposes launch args.
**What**: TestFlight users cannot pass launch args, so practical risk is nil; only Xcode-attached/UITest runs can. The Runner scheme itself has no `-MeshDemo` arguments (verified; only the Screenshots scheme's UI test sets them).
**Fix**: Optional: guard with `kDebugMode || const bool.fromEnvironment('ALLOW_DEMO')` plus profile/UITest build flag. Not required for beta.

### [LOW] Screenshots not verified as current
**Where**: ios/fastlane/screenshots/en-US/ (6 PNGs, all 1320x2868, correct for iPhone 6.9").
**What**: ScreenshotTests.swift captures map, charts, session, coverage, pings, radio via `-demoScreen`, so names do not depend on tab labels; but they predate recent UI changes (tabs, radio pill, region setup, role names). Files are named `iPhone 18 Pro Max-...` which App Store Connect upload tooling does not care about. No iPad set (see HIGH).
**Fix**: Re-run `cd ios && fastlane snapshot` after the last UI change and before App Store submission (not needed for TestFlight).

### [LOW] Many direct deps have major upgrades
**Where**: `flutter pub outdated`.
**What**: Behind a major: csv 6->8, flutter_blue_plus 1.36->2.3, flutter_local_notifications 18->22, flutter_riverpod 2->3, geolocator 13->14, intl 0.19->0.20, latlong2 0.9->0.10, package_info_plus 9->10, permission_handler 12->13, protobuf 4->6 (CLAUDE.md pins ^4 for the vendored generated code), share_plus 10->13, riverpod_annotation 2->4. Minor/patch ones resolvable now: drift 2.35.2, flutter_map 8.3.2, shared_preferences, uuid, path_provider, in_app_purchase_storekit.
**Fix**: Freeze for beta; schedule after. Do not upgrade BLE/StoreKit packages mid-beta.

## Checked, OK
- Versioning: Runner Info.plist uses `$(FLUTTER_BUILD_NAME)`/`$(FLUTTER_BUILD_NUMBER)`; MeshActivity Info.plist uses `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)` which MeshActivity.xcconfig sets from Flutter's Generated.xcconfig (referenced by all 3 extension configs). Runner target has no hard-coded MARKETING_VERSION. The only `MARKETING_VERSION = 1.0` entries are RunnerTests (not shipped).
- Fastfile: build number = `latest_testflight_build_number + 1`, `flutter build ios --release --no-codesign --build-number`, then `build_app` Release config; API key passed only via `xcargs`; ExportOptions method `app-store`, team P68H74992L, automatic signing, uploadSymbols.
- Secrets: `.gitignore` ignores `fastlane/.env` and `*.p8`; tracked files contain only `.env.example`; no key material tracked.
- Bitcode: `ENABLE_BITCODE = NO`. Deployment target 15.0 for Runner, Podfile (15.0, forced for pods); extension 16.2 (ActivityKit; acceptable, lower-than-host is not required).
- Signing: DEVELOPMENT_TEAM P68H74992L on Runner, extension, UI tests; bundle ids com.andybrunker.meshAnalyzer / .MeshActivity / .RunnerTests / .RunnerUITests.
- Info.plist: DisplayName "Mesh Analyzer", `ITSAppUsesNonExemptEncryption` false, Bluetooth and Location usage strings present, UIBackgroundModes bluetooth-central + location, NSSupportsLiveActivities.
- App icon: all 19 Contents.json entries have files, 1024 marketing icon present and `hasAlpha: no` (all icons no alpha). Launch screen storyboard present.
- Pro override: `kDebugMode && bool.fromEnvironment('PRO_OVERRIDE')`; no dart-defines in Fastfile.
- Legal: LICENSE is stock GPL-3.0 text; NOTICE mentions all 24 runtime deps in pubspec `dependencies:` (mechanical comparison: no omissions); NOTICE and lib/proto/LICENSE are in pubspec `assets:`. SPDX present on all other lib/, test/, tool/, ios Swift files.
- Referenced paths in CLAUDE.md exist (mesh_radio.dart, radio_roles.dart, make_icon.py, gen_protos.sh, LiveActivityBridge.swift, MeshActivityAttributes.swift, Products.storekit, UPSTREAM.md, roadmap.md).
- SDK: pubspec `sdk: ^3.5.0`; installed Flutter 3.41.4 / Dart 3.11.1.
- Roadmap: tip jar removal and Pro-only-on-create model match code.

## Release checklist
1. `git status` clean on the release branch; merge field-build branches; ensure `ios/Flutter/Generated.xcconfig` is regenerated (the lane does it).
2. Edit pubspec `version: 0.9.0+1`; fix README pricing line and description.md "Maps tab"; add the 3 SPDX headers; (decide iPad: set `TARGETED_DEVICE_FAMILY = 1` for Runner).
3. `flutter pub get && flutter analyze && flutter test`.
4. App Store Connect: app record for com.andybrunker.meshAnalyzer exists; create IAPs (yearly sub in group "Mesh Analyzer Pro" with 1-week trial, lifetime non-consumable for offer codes); TestFlight > Test Information: beta description, feedback email, privacy URL (verify https://beta.plateaunerd.com/privacy/mesh-analyzer loads), review contact, What to Test.
5. Ensure `ios/fastlane/.env` has ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (Admin key).
6. `cd ios && fastlane beta`; wait for processing; answer export compliance (already NO via plist).
7. Install via TestFlight on a real iPhone and check: About shows version 0.9.0 (N), connect, Radio Setup, start session, Live Activity, paywall shows price from sandbox, no demo/Pro override.
8. Add an internal group first, then submit the build to Beta App Review and create the external public link.
9. Tag the commit (`git tag beta-0.9.0-<build>`) after upload.

## Draft TestFlight "What to Test" (build 2)
You need two Bluetooth LoRa radios (one fixed base, one carried). Close the official radio app before connecting.

New in this build:
- Tabs are now Live, Coverage and Settings; the node list moved to Settings.
- Radio roles: Radio Setup asks whether the connected radio is the Mobile or the Base, remembers each radio, tags them in the connect list and radio pill, and can rename them "MeshTest Base" / "MeshTest Mobile".
- First connect to a new radio asks for the LoRa region.
- Session screen shows the mobile and base radios by name and offers "Change preset" (opens Radio Setup).
- Radio-measured airtime and channel utilization are shown next to our estimate.
- Settings > Data: clear nodes list, delete sessions/maps, erase all app data. Backups link from the Radio Setup apply dialog.
- Optional "Faster than recommended" ping interval override (Settings > Active Probing).
- Fix for pings failing with PKI_UNKNOWN_PUBKEY after a node-list reset; CSV export has readable names; connect screen shows progress.
- Live Activity now tells you why it did not start. New app icon.
- Rig profiles and rig comparison are Pro features (1-week free trial); viewing and exporting always work.

Please test: pairing/connecting, Radio Setup on both radios (it replaces channels; a backup is saved first), a short walk session with pings, locking the phone during a session, and export. Report spots where the map says out of range but you can still hear the base, and anything confusing in Radio Setup. Send feedback via TestFlight (screenshot feedback) or the feedback email.
