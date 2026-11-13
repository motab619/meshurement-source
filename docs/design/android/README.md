# Android / Google Play

Status and plan for shipping Meshurement on Android (Google Play). Written
2026-11-06 for Andy and for future sessions. Play policy facts were checked
on 2026-11-06 at the URLs given; re-check before relying on them later.

Fixed facts (Andy): application ID **`com.plateaunerd.meshurement`** (the
iOS bundle ID `com.andybrunker.meshAnalyzer` and the StoreKit product IDs
never change); Play closed-testing builds get Pro automatically, like
TestFlight; the Play developer account, Play Console actions, the upload
keystore and the store listing are Andy's, by hand. Test phone: Samsung
Galaxy A16 (One UI, Android 14/15).

Files: `android/fastlane/` (lanes `beta`, `release`, `version_codes`),
`tool/android/` (`make_keystore.sh`, `install_debug.sh`, `pull_diag.sh`),
`lib/services/test_build.dart` (`TESTER_PRO`).

## 1. Audit

Status: **works** = no Android work; **config** = manifest/Gradle only;
**code** = Dart or Kotlin changes; **no-op** = feature absent on Android
by design. Versions are the resolved ones in `pubspec.lock`.

### Runtime plugins

| Plugin (resolved) | Android | What's needed | Owner / phase |
|---|---|---|---|
| flutter_blue_plus 1.36.8 (android 7.0.4, minSdk 21) | config + code | Declares **no** permissions on purpose; app manifest adds `BLUETOOTH_SCAN` (`neverForLocation`), `BLUETOOTH_CONNECT`, legacy `BLUETOOTH`/`BLUETOOTH_ADMIN` maxSdk 30. Runtime request of Nearby devices before scanning. Bonding/PIN via the system dialog. | shell agent (manifest, done), Dart guards agent / P2 |
| geolocator 13.0.4 (android 4.6.2) | config + code | Plugin ships `GeolocatorLocationService` (`foregroundServiceType="location"`). App adds `ACCESS_FINE/COARSE_LOCATION`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `WAKE_LOCK`; `AndroidSettings(foregroundNotificationConfig: …)` while recording. No `ACCESS_BACKGROUND_LOCATION`. | shell + Dart guards agents / P3 |
| flutter_local_notifications 18.0.1 | config + code | Plugin declares `POST_NOTIFICATIONS`, `VIBRATE`; Android 13+ runtime prompt; notification channel(s); needs core library desugaring (added in `build.gradle.kts`). | Dart guards agent / P3 |
| permission_handler 12.0.1 (android 13.0.1) | works | Requests the runtime permissions above; nothing in its manifest. | P2 |
| share_plus 10.1.4 | works | Uses its own FileProvider; `<queries>` SEND entry added. | P2 check |
| file_picker 8.3.7 | works | App uses `pickFiles()` (any type), so the unknown `.mabackup` extension is not a problem (a `FileType.custom` filter would fail on Android). | P2 check |
| url_launcher 6.3.3 | config | `<queries>` for `https` and `mailto` (added). | shell agent, done |
| wakelock_plus 1.5.1 | works | Uses window `FLAG_KEEP_SCREEN_ON`; no permission. | — |
| package_info_plus 9.0.1 | works | — | — |
| in_app_purchase 3.3.1 (android 0.5.0 → Play Billing **8.0.0**) | code | Needs a Play `ProStoreGateway`; product IDs lowercase (proposed `pro_yearly`, `pro_lifetime`). Billing 8 is accepted for new apps/updates until 2027-08-31 ([deprecation FAQ](https://developer.android.com/google/play/billing/deprecation-faq)). `BILLING` permission comes from the library. | Billing agent / P4 |
| in_app_purchase_storekit 0.4.13+2 | no-op | iOS only; harmless on Android as long as Dart only touches it on iOS. | P4 |
| flutter_compass 0.8.1 | works (check) | Rotation-vector sensor, no permission. Old plugin (compileSdk 34, conditional namespace): builds with AGP 8; verify heading-up on the A16. | P2 |
| sqlite3_flutter_libs 0.5.42 | works | Bundles native sqlite per ABI. | — |
| path_provider 2.1.5 | works | Documents = `/data/data/<id>/app_flutter/`. | — |
| shared_preferences 2.5.4 | works | `shared_prefs/FlutterSharedPreferences.xml`. | — |
| drift 2.28.2, flutter_map 8.2.2, http 1.6.0, archive, csv, intl, uuid, protobuf, fixnum, clock, flutter_riverpod | works | Pure Dart. `INTERNET` permission added for tiles/AI. | — |

### iOS-only features

| Feature | Android | What's needed | Owner / phase |
|---|---|---|---|
| Live Activity (ActivityKit, `mesh_analyzer/live_activity`) | no-op | `LiveActivityService` does nothing on Android; the foreground-service notification is the lock-screen presence. A richer ongoing notification is a later nice-to-have. | Dart guards agent / P3 |
| Demo launch args (`-MeshDemo`, `-demoScreen`) | code (done) | `MainActivity` answers `mesh_analyzer/app` `launchArguments` from Intent extras: `adb shell am start -n com.plateaunerd.meshurement/.MainActivity --ez MeshDemo true --es demoScreen map` (`tool/android/install_debug.sh --demo map`). | shell agent / P1 |
| Background location (UIBackgroundModes `location`) | code | Foreground service of type `location` while a session records, with an ongoing notification; started from the visible app when the user starts a session; stopped at End session. | Dart guards agent / P3 |
| Local notifications (out-of-range, radio lost) | code | Channel, Android 13 permission, sound; heads-up while in the app as on iOS. | Dart guards agent / P3 |
| Compass heading-up | works (check) | See flutter_compass. | P2 |
| Share sheet (CSV, field report PNG, backups) | works | share_plus. | P2 check |
| `.mabackup` import / open-with | code | Import via file_picker works. Open-with: `VIEW` intent filter + `openedFile` on `mesh_analyzer/app` exist in `MainActivity`; the Dart consumer is not written yet. The filter matches by path (`*.mabackup`), so Files' storage documents match but Downloads (`msf:123`) and Drive URIs (no name in the path) don't; a MIME filter for `application/octet-stream`/`application/json` is to be added with the Dart consumer, which must then reject non-backups politely. | shell agent (native, done) / Dart P2 |
| Native splash / launch screen | config (done) | `launch_background.xml` / styles; Android 12+ system splash shows the icon on the theme colour, then `SplashOverlay`. | shell agent |
| App icon | config (done) | `tool/make_icon.py` writes legacy mipmaps, the adaptive icon (foreground on the 108 dp canvas, logo in a 50 dp square so a round mask keeps the node and arcs, navy background colour) and the themed-icon monochrome layer. | shell agent |
| StoreKit → Play Billing | code | `PlayStoreGateway` behind `ProStoreGateway`; offer codes → Play promo codes; lifetime still never offered in-app. | Billing agent / P4 |
| TestFlight lane / `TESTFLIGHT_PRO` | done | `android/fastlane` `beta` passes `TESTER_PRO=true`; `TestBuild.unlockPro = TESTFLIGHT_PRO \|\| TESTER_PRO`. | this doc / P5 |
| AI token (`AI_APP_TOKEN`) | done | Both Android lanes pass it from `android/fastlane/.env`. | P5 |
| Release signing | config (done) | `android/key.properties` → release `signingConfig`; debug key when absent (Play rejects that; the lanes check). | shell agent + Andy |
| Live data copy (`devicectl … copy from`) | done | `tool/android/pull_diag.sh` (`adb exec-out run-as`, debug builds only). | — |

Toolchain facts (shell agent, 2026-11-06): Flutter 3.41.4 defaults are
compileSdk/targetSdk **36**, minSdk **24**, NDK 28.2; Android SDK at
`/opt/homebrew/share/android-commandlinetools`, JDK 21 (Homebrew
`openjdk@21`, set as `flutter config --jdk-dir`).

Release build facts (review, 2026-11-06): R8 + resource shrinking run on
release; R8 reports no missing rules. Resources looked up by name from
Dart (`ic_stat_notify`) are invisible to the shrinker and were stripped
until `res/raw/keep.xml` listed them: add any new name-only resource
there. The bundle has arm64-v8a, armeabi-v7a and x86_64. targetSdk 36
enforces edge-to-edge (the opt-out attribute is ignored from 36), so
every screen must pad for the system bars itself.

Known limitation (plugin, 2026-11-06): geolocator_android 4.6 creates its
foreground-service channel with `IMPORTANCE_NONE`
(`BackgroundNotification.updateChannel`), so the "Meshurement is
recording" notice is silenced: the service runs and Android 13+ lists it
in the foreground-services task manager, but the shade shows no row.
Pre-creating the channel doesn't help (the plugin recreates it, which can
only lower importance). Options if testers miss it: a small Kotlin
foreground service of our own, or an upstream PR. Decide after the A16
run.

## 2. Phased plan

| Phase | Goal | Done when |
|---|---|---|
| 1 Build + toolchain | `flutter build apk --debug` and `appbundle --release` green; SDK 36, JDK 21 | **Done** (shell agent). |
| 2 Core BLE + GPS on the A16 | Scan, pair, connect to Heltec V3 (Meshtastic) and T1000-E / L1 (MeshCore); Radio Setup; GPS fixes; map tiles; compass | Section 7 steps 1 to 6 pass. Samsung: app's battery setting **Unrestricted**, app not in "Sleeping"/"Deep sleeping apps" (section 6). PIN entry via the system pairing dialog. |
| 3 Background recording | Foreground service (location) + ongoing notification while recording; out-of-range alerts; survives 10 min locked | Section 7 steps 7 to 9 pass, including with the phone still (Doze). |
| 4 Play Billing | `PlayStoreGateway`, products in Play Console, licence testers | Test purchase of `pro_yearly` by a licence tester; a debug build without products shows "unavailable" gracefully. |
| 5 Release lanes | `fastlane beta` to internal/closed testing with `TESTER_PRO` + AI token; `fastlane release` to production as draft | First manual AAB upload done, then `fastlane beta` uploads build 2. |
| 6 Play Console | Listing, Data safety, content rating, permission declarations, closed test with 12 testers for 14 days, production access | Production access granted, `fastlane release` build rolled out. |

### Play policy facts (checked 2026-11-06)

| Fact | Source |
|---|---|
| The API track id of the first Closed testing track is `alpha` (fastlane/supply convention; the help page does not name it). Check in Play Console before `PLAY_TRACK=alpha`. | fastlane `supply` docs, not re-checked |
| From **2026-08-31** new apps and app updates must target **Android 16 (API 36)**; extension possible to 2026-11-01 (now past). Flutter 3.41's default targetSdk 36 meets it. | <https://developer.android.com/google/play/requirements/target-sdk> |
| New **personal** developer accounts (created after 2023-11-13) must run a **closed test with at least 12 testers opted in continuously for at least 14 days** before applying for production access; 12 must be opted in when applying; testers who leave early or re-join do not carry days over. | <https://support.google.com/googleplay/android-developer/answer/14151465> |
| Internal testing: up to **100 testers** by email, builds available within minutes. A user opted into the internal test **cannot receive the closed or open test** until they opt out of internal. | <https://support.google.com/googleplay/android-developer/answer/9845334> (closed tests also take Google Groups) |
| Apps targeting Android 14+ must **declare each foreground service type** in Play Console (App content): description, user impact if deferred/interrupted, and a **video link** showing the feature being triggered. | <https://support.google.com/googleplay/android-developer/answer/13392821> |
| Location in a foreground service must start as a continuation of an in-app, user-initiated action and end when that task ends; if it is equivalent to background access, the **background location** rules apply. Prominent in-app disclosure rules (must say "location", before the permission prompt). | <https://support.google.com/googleplay/android-developer/answer/9799150> |
| Play Billing Library 7 accepted until 2026-08-31 (ext. 2026-11-01); **8 until 2027-08-31**. in_app_purchase_android 0.5.0 uses 8.0.0. | <https://developer.android.com/google/play/billing/deprecation-faq> |
| Data safety: "collect" = sent off the device; on-device-only data need not be disclosed; ephemeral in-memory processing can be left out of the public label (still answered in the form); user-initiated transfers with consent are not "sharing"; **a privacy policy link is required for every app**. Precise = `ACCESS_FINE_LOCATION`-level. | <https://support.google.com/googleplay/android-developer/answer/10787469> |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (direct exemption prompt) is only allowed for listed use cases; others may open the battery settings list (`ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`). A Bluetooth companion app that only connects periodically is "not acceptable". | <https://developer.android.com/training/monitoring-device-state/doze-standby#exemption-cases> |

Recommendation from the last row: do **not** declare
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`. The location foreground service
already exempts the app from App Standby while recording; for Samsung's own
sleep lists, show a one-time tip that opens the app's battery settings
(`ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS` or App info).

## 3. Release lanes (`android/fastlane`)

```sh
cd android
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8   # fastlane refuses a non-UTF-8 locale
fastlane beta                 # TESTER_PRO=true, track PLAY_TRACK (internal)
PLAY_TRACK=alpha fastlane beta  # closed testing (the 12-tester track)
fastlane release              # no TESTER_PRO, production track, draft
fastlane version_codes        # highest versionCode on Play
```

Both upload lanes: clean tree, `flutter analyze`, `flutter test`;
`android/key.properties` and its keystore present; versionCode = highest on
any Play track (`google_play_track_version_codes` over internal, alpha,
beta, production) + 1, or pubspec's `+N` if higher (`pubspec.yaml` is
`0.9.0+1` and is not edited, as on iOS; Android and iOS numbers are
independent); `flutter build appbundle --release --verbose
--build-number=N --dart-define=AI_APP_TOKEN=… [--dart-define=TESTER_PRO=true]`
with the log in `build/android-fastlane-build.log` (holds the token in
base64; `build/` is git-ignored).

**How the tester unlock is verified.** `bool.fromEnvironment` is folded at
compile time, so the AAB itself carries no trace of the define. What is
reliable: `flutter build` passes the defines to Gradle as
`-Pdart-defines=<base64,base64,…>` (flutter_tools `build_info.dart`
`toGradleConfig`/`encodeDartDefines`), Gradle hands the same value to
`flutter assemble --DartDefines=…`, which compiles the AOT snapshot
(`BaseFlutterTaskHelper.kt`), and `--verbose` traces the Gradle command line
(`executing: … gradlew … -Pdart-defines=…`). The lane decodes every
`-Pdart-defines` value in the log and fails if `TESTER_PRO=true` (or
`TESTFLIGHT_PRO=true`) is present on `release` or missing on `beta`, or if
`AI_APP_TOKEN` is empty. `release` also refuses to start when `TESTER_PRO`
or `TESTFLIGHT_PRO` is set in the shell environment. Then `keytool
-printcert -jarfile` refuses a debug-signed AAB (and checks
`UPLOAD_CERT_SHA256` when set). Not yet run end to end (no Play app yet);
the regex and decode were checked on a real Flutter 3.41.4 `--verbose`
log (`[   +1 ms] executing: [...android/] .../gradlew ... -Pdart-defines=...`),
and the debug-key check on a debug-fallback AAB (keytool prints
`Owner: C=US, O=Android, CN=Android Debug`).

Upload: `upload_to_play_store` with the service-account JSON
(`PLAY_JSON_KEY`), metadata/screenshots skipped (listing is by hand).
Production releases are always **draft** (Andy rolls out in Play Console).
Testing releases use `PLAY_RELEASE_STATUS` (`draft` until the app's first
review, then `completed`). The **first AAB must be uploaded by hand** in
Play Console; the API cannot create the app.

Never promote a `beta` (Pro-unlocked) build to production in Play Console:
build production with `release`. Like App Review, Play's reviewers install
the real binary.

## 4. Data safety form (draft answers)

Mirrors the iOS answers in `docs/app-privacy-answers.md` (keep in step).
Off-device flows: AI analysis and AI plan parsing (Andy's Lambda, then
Anthropic; only with the AI switch on and a tap; numbers-only digest, the
scrubber in `ai_analysis.dart` refuses coordinates and node ids; random
install id `X-Device-Id` kept in quota counters up to ~34 days), terrain
elevation (Open Topo Data, opt-in, default off, sends point coordinates),
map tiles (CloudFront `d13u6w4g5rrbl6.cloudfront.net` and
`tile.openstreetmap.org`; tile area + IP in server logs; switch in Settings
→ Privacy, default on). Everything else (sessions, GPS track, radio data,
backups) stays on the phone. No account, no ads, no analytics or crash SDK.

| Question | Answer |
|---|---|
| Does the app collect or share any required user data types? | **Yes** |
| Is all user data encrypted in transit? | **Yes** (HTTPS only) |
| Way to request data deletion? | No account; the only stored item is the install id, deleted automatically within ~34 days. Answer per the form's options; say so in the privacy policy. |
| Privacy policy | <https://meshurement.com/privacy> |

| Data type | Collected | Shared | Optional | Ephemeral | Purpose | Why |
|---|---|---|---|---|---|---|
| Device or other IDs | Yes | No | Yes (AI switch) | No (kept ~34 days) | App functionality (usage limits) | Random install id for AI quotas |
| App activity → Other user-generated content | Yes | No¹ | Yes | Yes (not stored by our server) | App functionality | Typed AI question / plan request, profile names |
| App info and performance → Other (or "Other" data type) | Yes | No¹ | Yes | Yes | App functionality | Numbers-only measurement digest (choose one category, as on iOS) |
| Location → Precise location | Yes | No¹ | Yes (terrain, default off) | Yes | App functionality | Point coordinates to Open Topo Data |
| Location → Approximate location | Decide² | No | Yes (map tiles switch) | Yes | App functionality | Tile requests reveal the map area |

¹ User-initiated, disclosed and consented in the app (consent sheet /
terrain opt-in), and Anthropic acts for Andy's backend: excluded from
"sharing" per the Data safety help page. ² Many map apps leave tile fetches
out as ephemeral; declaring it is the cautious choice. Andy decides.

Do not declare: personal info, financial info (Play Billing purchases are
Google's), health, messages, photos, audio, files, calendar, contacts, web
browsing, crash logs/diagnostics (the diag log leaves only via the share
sheet, by the user).

## 5. Permission declarations (texts to paste)

**Foreground service: location** (App content → Foreground service
permissions). Use case: "Background location updates – other" (closest
preset: navigation / ride tracking). Video: start a session on the Live tab,
lock the phone, show the ongoing notification, unlock, show new points.

> Meshurement maps the radio coverage of a LoRa mesh radio the user owns.
> When the user taps Start session, the app records the phone's GPS position
> together with each signal report from the user's Bluetooth radio, so the
> map shows where the signal was strong or weak. Walks and drives take tens
> of minutes and the phone is usually locked in a pocket or mount, so the
> location foreground service keeps recording GPS-tagged signal samples
> while the screen is off. It starts only from the user's Start session tap,
> shows an ongoing notification for the whole time, and stops when the user
> ends the session. If the system deferred or stopped it, the recording
> would have gaps and the coverage map would be wrong, and the out-of-range
> alert would not fire.

**Location permission** (only foreground `ACCESS_FINE_LOCATION`; no
`ACCESS_BACKGROUND_LOCATION`, so no background-location declaration should
be needed. Risk: Play's policy says FGS location "equivalent to background"
falls under background rules; if review asks, answer with the text above.)
Prominent disclosure before the system prompt, in the app's normal flow:

> Meshurement uses your location to place each signal measurement on the
> map. While a session is recording it keeps using location when the
> screen is off or the app is in the background, until you end the session.
> Locations stay on this phone.

**Nearby devices** (`BLUETOOTH_SCAN` with `neverForLocation`,
`BLUETOOTH_CONNECT`): no Play declaration. Rationale for the in-app text:
"Meshurement finds and connects to your mesh radio over Bluetooth. It does
not use Bluetooth to work out where you are."

**Notifications** (`POST_NOTIFICATIONS`): "Out-of-range and radio-lost
alerts while recording, and the recording notification."

Other declarations Andy will meet: content rating questionnaire (no user
interaction, no UGC shared between users), target audience (not children),
ads (**No**), news app (No), government app (No), financial features (No).

## 6. Andy's checklists

**Decided 2026-11-09:** personal Play account; Android ships **free with
every Pro feature unlocked** and no Play Billing (`TestBuild.androidProFree`),
declared "not a trader" so the store page shows no address. Pro on Play
comes with an LLC (organisation account, non-home address) planned for
January 2027; products, merchant profile and trader status wait until then.

### Open questions (answer first)

1. **Approximate location for map tiles**: declare in Data safety, or treat
   tile fetches as ephemeral (section 4, note 2)?
2. **12 testers for 14 days**: who are the 12 (Matt, beta-site list)? Is
   the Play account personal or an organisation (D-U-N-S)? The rule applies
   to personal accounts only.
3. **Play product IDs**: confirm `pro_yearly` (with a 1-week free trial
   offer, $6.99/yr base plan) and `pro_lifetime` (promo codes only, never
   shown), and the price per country.
4. **Battery tip**: OK to show a one-time "set battery to Unrestricted" tip
   on Samsung (opens settings), instead of the restricted exemption prompt?
5. **Foreground-service video**: record it on the A16 (screen recording) or
   from the emulator in demo mode?
6. Should `fastlane beta` default to **internal** (fast, but those testers
   cannot also be in the closed test) or **alpha** (closed; counts for the
   14 days)?
7. Store listing: reuse iOS screenshots or take Android ones (Play wants
   phone screenshots; demo mode works on Android too)?

### What only Andy can do in Play Console

1. Create the developer account (personal or organisation), pay the
   registration fee, complete identity verification (and the device
   verification in the Play Console app if asked).
2. Create the app: name Meshurement, default language, App, Free (with
   in-app purchases). Package name is fixed by the first upload:
   `com.plateaunerd.meshurement`.
3. App integrity: keep **Play App Signing** (Google holds the app signing
   key). Create the upload key with `tool/android/make_keystore.sh`, write
   `android/key.properties`, back both up.
4. Upload the first AAB by hand: `flutter build appbundle --release
   --dart-define=TESTER_PRO=true --dart-define=AI_APP_TOKEN=…` to Internal
   testing (draft is fine).
5. API access: Google Cloud project → enable "Google Play Android
   Developer API" → service account → JSON key (save as
   `~/.play/meshurement-play-publisher.json`); Play Console → Users and
   permissions → invite the service account email with release rights for
   the app. Fill `android/fastlane/.env`.
6. App content: privacy policy URL, ads (No), app access (no login; explain
   the demo: long-press the app name on About, or "no radio needed for
   demo"), content rating, target audience, Data safety (section 4),
   foreground service declaration (section 5), government/financial/health
   (No).
7. Monetise → Products → Subscriptions `pro_yearly` (base plan yearly,
   free-trial offer) and In-app products `pro_lifetime`; payments profile
   / merchant account; licence testers (Settings → License testing).
8. Testing → Closed testing (track "alpha"): tester list (emails or a
   Google Group), opt-in link to the 12+ testers, keep them opted in 14
   days. Then Dashboard → Apply for production access.
9. Store listing: short and full description, icon 512x512, feature
   graphic 1024x500, phone screenshots, category (Tools), contact email
   support@meshurement.com, website meshurement.com. Trademark wording as
   on iOS (no "Meshtastic" in name or icon).
10. Production: review the `fastlane release` draft and roll it out.

### Galaxy A16 first run

1. Settings → About phone → Software information → tap **Build number** 7
   times (enter PIN). Settings → Developer options → **USB debugging** on.
2. USB-C cable to the Mac; on the phone accept "Allow USB debugging?" (tick
   Always allow). `adb devices -l` shows `device` (not `unauthorized`).
3. `tool/android/install_debug.sh` (builds, `adb install -r`, launches).
   Demo check: `tool/android/install_debug.sh --no-build --demo map`.
4. In the app grant **Location: While using the app** (Precise on) and
   **Nearby devices: Allow**, **Notifications: Allow**. Location must be on
   in Quick settings.
5. Samsung battery: Settings → Apps → Meshurement → Battery →
   **Unrestricted**. Settings → Battery → Background usage limits: make
   sure Meshurement is not under Sleeping / Deep sleeping apps; add it to
   **Never sleeping apps**; consider turning off "Put unused apps to sleep"
   on test phones. Paths vary by One UI version
   (<https://dontkillmyapp.com/samsung> has no One UI 7 paths; it notes One
   UI 6 honours properly declared foreground services).
6. Keep the Heltec's USB port free while the app uses it (CLAUDE.md bench
   note: ESP32 BLE goes off while a serial client is connected).
7. Logs: `flutter logs` or `adb logcat`; data: `tool/android/pull_diag.sh`.

## 7. Verification on the A16

Debug build from `tool/android/install_debug.sh`, real radios. Note pass /
fail and the diag log (`tool/android/pull_diag.sh`) for each failure.

| # | Check | Pass when |
|---|---|---|
| 1 | Fresh install, welcome flow, permissions prompts | Each prompt appears once with the app's rationale first; denying Nearby devices shows the app's own explanation, no crash |
| 2 | Connect list scan | Heltec V3 (Meshtastic), T1000-E and L1 (MeshCore) appear with names and RSSI |
| 3 | Connect Heltec V3 | System pairing dialog takes the PIN; config completes; node list fills; reconnects after radio power-cycle |
| 4 | Connect T1000-E / L1 (MeshCore) | Handshake completes, contacts and channels load, stats appear within 60 s |
| 5 | Radio Setup (Meshtastic pair, then MeshCore pair) | Both radios on MeshTest; roles tagged in the connect list; backups saved |
| 6 | Map + GPS idle | Position dot, Streets tiles from CloudFront/OSM, compass heading-up turns with the phone |
| 7 | Short recording walk (~10 min) | Ongoing notification while recording; pings/link checks and base beacon samples on the map; session ends cleanly and the notification goes |
| 8 | Lock 10 minutes while recording (walk, then also lying still on a table) | After unlock the track and samples have no gap > 2 probe intervals; `adb shell dumpsys deviceidle` state noted for the still case |
| 9 | Out-of-range | Switch the base off during a session: radio-lost/out-of-range notification with sound, on lock screen and in-app banner; back in range after base on |
| 10 | Field report | Share sheet opens with the PNG (feed, story, wide); Streets background loads |
| 11 | CSV export | Share sheet with the CSV; opens in Google Sheets/Drive |
| 12 | Import `.mabackup` | Settings → Radios → Backups → Import picks the file from Downloads/Drive and lists it; opening a `.mabackup` from Files opens the app (once the Dart side exists) |
| 13 | Paywall in a debug build | Tapping a Pro feature shows the paywall with "unavailable" (no products / no Play account) without a crash; `--dart-define=PRO_OVERRIDE=true` unlocks |
| 14 | Demo mode | `install_debug.sh --demo report` opens the field-report demo with no permission prompts |
| 15 | Rotation, dark mode, back gesture | No layout overflow; system back leaves sheets and screens as expected |
