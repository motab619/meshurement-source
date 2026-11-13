# Beta readiness audit — 2026-10-16

Six independent read-only audits of the beta candidate (`main` + PRs #23 radio-contacts, #24 field build, #25 region setup; tree `5806515`). Each detailed report is beside this file:

| Report | Model | Blocker | High | Medium | Low/Info |
|---|---|---|---|---|---|
| [security.md](security.md) | Opus | 0 | 1 | 5 | 11 |
| [compliance.md](compliance.md) | Opus | 3 | 5 | 5 | 5 |
| [quality.md](quality.md) | Sonnet | – | 2 | 7 | 9 |
| [reliability.md](reliability.md) | Sonnet | – | 3 | 8 | 3 |
| [release.md](release.md) | Sonnet | 0 | 2 | 5 | 5 |
| [ux.md](ux.md) | Sonnet | – | 3 | 10 | 3 |

`flutter analyze` clean · 223 tests pass · no secrets or home coordinates anywhere in git history · no analytics/tracking · protobuf parsing is wrapped in try/catch · subscription disclosure, Restore Purchases and EULA link on the paywall are fine · `ITSAppUsesNonExemptEncryption = NO` is defensible.

Severity below is my consolidated call after re-checking the code; where agents disagreed I say so. Items marked ✔ were verified by reading the code myself.

---

## 1. Must fix before any public TestFlight link

| # | Finding | Why it blocks | Fix (size) |
|---|---|---|---|
| 1 | ✔ **Paywall shows "null Coming soon." and labels every Pro feature "Coming soon"** — `pro_paywall_screen.dart:208`; `_blurbs` has no entry for `ProFeature.rigProfiles`, and the "Coming soon." suffix is appended to all seven features although Hardware profiles and Rig comparison already work. | App Review 3.1.2 / 2.3: selling a subscription whose listed features are all unreleased; literal "null" on a purchase screen. | Add the missing blurb; mark only unreleased features "Coming soon" (icon ✓ vs schedule). **Small.** |
| 2 | ✔ **Privacy policy URL is dead** — the in-app/ASC URL `beta.plateaunerd.com/privacy/mesh-analyzer` has no DNS record; `plateaunerd.com/…` is 404. | 5.1.1(i): privacy policy must be reachable from the app and ASC. | Deploy the privacy/support pages (plateau-beta branch `privacy-support-pages` is waiting for your deploy approval) **and** rewrite the policy text — see #3. **Small, but needs your deploy OK.** |
| 3 | ✔ **Privacy copy is wrong about network traffic** — app text says data only leaves the phone on CSV export, but map tiles come from `tile.openstreetmap.org` (every map view reveals the viewed area) and the opt-in terrain layer sends coordinates (often the base = your home) to `api.opentopodata.org`. Those are the only two hosts. | 5.1.1 accuracy; App Privacy label must list "Location → app functionality, not linked". | Disclose both hosts in the policy and About; set the App Privacy answers accordingly. **Small.** |
| 4 | ✔ **GPL corresponding source isn't available** — the app bundles Meshtastic LLC's GPL-3.0 protobufs; the in-app "Source code" link 404s because the repo is private. A public TestFlight link is distribution under GPL §6. | Licence compliance (third-party code, not just yours). | Make the repo public before the public link (check #14 first). For the two named friends, sending them the source archive satisfies §6 meanwhile. **Decision + hygiene pass.** |
| 5 | ✔ **"Never on the public channel" guard can be bypassed mid-session** — only `SessionManager.startSession` checks `onPublicChannel`; `ActiveProbeService._sendPing`, `prepareToPing` and the NodeInfo exchange never do. After an app relaunch (`initialize()` resumes the session with whatever radio connects), switching radios while recording, or restoring a backup mid-session, pings go out on the public mesh. | Project rule; etiquette toward the public mesh. | Check `onPublicChannel` in `_sendPing`/`ping`/`prepareToPing`; block Restore and radio switching while a session is active. **Small.** |
| 6 | ✔ **Range Test packets are dropped until the "Range Test detected" dialog is answered** — `RangeTestDetector.shouldLog` returns false while pending; tapping outside the dialog leaves it pending for the whole session, it is never re-asked, and `startSession` resets confirmation so it reappears exactly when the phone goes into a pocket. Base packets also never reach `OutOfRangeMonitor` meanwhile → false out-of-range alerts when pings are off. | Core workflow silently records nothing. | Log packets while pending (mark them, don't drop); make the dialog non-dismissable or re-ask; don't reset confirmation per session for the known base. **Medium.** |
| 7 | ✔ **GPS never starts if location permission isn't granted at launch** — `app.dart:96-102` is the only `startListening()` call and it's skipped when `initialize()` throws; later grants are never retried; nothing in the UI shows GPS state. Sessions then record null positions. | Core data loss for a first-time tester who taps "Don't Allow" once. | Retry on app resume and at `startSession`; refuse to start a session with no fix and say why; show a GPS indicator in the pill/session panel. **Medium.** |
| 8 | ✔ **Live Activity status line was never committed** — commit `98a3932` changed only `LiveActivityBridge.swift` and `LiveActivityService` (`problem` notifier); no widget reads it. The build on your phone does **not** show the "Live Activity: …" line I described. (Reliability F10.) | My regression; the diagnosis you were going to do on the phone isn't possible yet. | Add the reader in the recording view; also re-check `_sessionId` after the `await` in `start` (orphaned-activity race). **Small.** |
| 9 | ✔ **No OpenStreetMap attribution** on any of the three map screens (`map_screen.dart:170`, `coverage_map_detail_screen.dart:343`, `rig_comparison_screen.dart:249`). | OSM tile usage policy + ODbL require visible credit. | `RichAttribution` with "© OpenStreetMap contributors" on each `FlutterMap`. **Small.** |

## 2. Should fix before the beta build (HIGH)

| # | Finding | Source | Fix |
|---|---|---|---|
| 10 | **No reconnect after an iOS kill / relaunch** — session resumes in the DB but nothing connects (no auto-connect to the last radio, no CoreBluetooth state restoration). Also the resumed session never redoes the ping key exchange. | reliability F2, quality | Auto-connect to the last mobile radio on launch when a session is active; run `prepareToPing` on every `ready`. |
| 11 | **Deleting a coverage map while its session records orphans all later data** — `deleteCoverageMap` doesn't check for an active session; the writer keeps going. UX: swipe-to-delete has no confirmation. | quality, ux | Refuse delete while a session on that map is active; confirm swipe deletes. |
| 12 | **Raw exception text shown to users** (`'Failed: $e'`, `Bad state: …`) in Radio Setup, Restore, Connect. Mid-transaction failure leaves the radio in an open `beginEditSettings` and gives no recovery hint. | ux, quality, reliability F7 | Map errors to plain sentences; on failure attempt `commit` or tell the user to power-cycle and Restore. |
| 13 | **No first-run guidance** — the order connect → Radio Setup → create map → start session is undiscoverable; Radio Setup is buried under Settings; empty states don't point to it. | ux | A 4-step checklist card on the Live tab until the first session exists. |
| 14 | **Repo hygiene before going public** — author email on all commits (decide: keep or rewrite with a noreply address before the first public push), `CLAUDE.md`/`docs/roadmap.md` carry business notes, `docs/beta/` not audited, Android project still `com.example`, root `.gitignore` is narrow. | security | Secret-scan all branches, broaden `.gitignore`, review docs, then flip to public. |
| 15 | **iPad is targeted** (`TARGETED_DEVICE_FAMILY = "1,2"`) but untested and the app says iPhone-only. | release, compliance | Set to `1`. |
| 16 | **`fastlane beta` has no gate** — no analyze/test, no clean-tree check, no app↔extension version assert. | release | Add them to the lane. |
| 17 | **Location permission strings** don't explain locked-phone recording; `NSLocationAlwaysAndWhenInUseUsageDescription` is declared but Always is never requested. | compliance, security | Rewrite When-In-Use string; drop the Always key. |
| 18 | **Store metadata**: `description.md` lacks Terms of Use (EULA) + privacy links and doesn't mention the subscription; still says "Maps tab"; README says the App Store build is "a paid convenience build". | compliance, release | Update both; ASC needs the EULA link in the description for auto-renewables (3.1.2). |
| 19 | **Default 16-byte key passes as "private"** — `onPublicChannel` only catches PSKs ≤ 1 byte; the expanded default LongFast key (and simple1–10 expansions) is treated as private. | security | Compare against the known default keys too. |
| 20 | **Version 0.1.0+1** reads as pre-alpha to public testers. | release | `0.9.0` for the beta. |

## 3. Before App Store release (not blocking the beta)

- **GPL-3.0 protobufs on the App Store** — upstream `meshtastic/protobufs` LICENSE is plain GPL-3.0 with no App Store exception; the official Meshtastic iOS app being on the store is their grant, not yours. Options: ask Meshtastic LLC in writing for a non-enforcement statement (bundle with the trademark request); add a COPYING.iOS-style App Store permission for your own code; fallback is replacing the generated code with a hand-written codec. (compliance)
- **Privacy manifest** — no `PrivacyInfo.xcprivacy` for app or extension; bundled SQLite uses `stat`/`fstat`. Build 1 uploaded fine, so Apple's scanner didn't flag it — check the ASC email for an ITMS-91053 warning on build 1; add a manifest with `CA92.1` (UserDefaults) and `C617.1` (file timestamps) regardless. (compliance; downgraded from HIGH because build 1 was accepted)
- **Free community services under a paid app** — OSM tile policy and Open Topo Data's public API aren't meant for commercial apps; the roadmap's PMTiles host covers tiles, terrain needs a plan. (compliance)
- **Hidden lifetime non-consumable** sold only via offer codes may get purchase-review pushback; be ready to explain. Reviewers can't exercise the app without two radios — prepare a demo video + notes. (compliance)
- **Test-channel PSK in plaintext SharedPreferences** (goes into iCloud/device backups); move to Keychain. **Radio backups** hold the user's original personal channel keys in plaintext JSON and are shared/copied without a warning. (security)
- **CSV formula injection** via node names from other people's radios; **Erase all data** leaves CSV exports (full GPS tracks) in Documents. (security)
- **Reliability MEDIUMs**: base-first Radio Setup can give the mobile a different region than the base (F4); no fix age/accuracy gate (F5); out-of-range timeout ignores the base's beacon interval (F6); base missing from New-map picker on firmware < 2.6 (F9); notification permission asked cold at launch, denial never reported (F11). Superseded `connect()` can tear down the newer connection (quality).
- **Quality MEDIUMs**: "Signal Direction" setting does nothing; `watchEventsForMap` providers never disposed and re-query the whole map per packet; live map keeps old sessions' dots.
- **UX MEDIUMs**: developer jargon (PSK, NodeDB, PKI, raw `MEDIUM_FAST`, hex ids, Routing_Error names); radio/node/device/rig/remote inconsistency; Title Case vs sentence case; End Session has no confirmation; colour-only signal encoding with no legend on Live; `white38` overlay text at ~2.6:1 contrast; Dynamic Type overflow in Settings rows; connect dialog dismissable mid-connect; no imperial units.
- **Housekeeping**: SPDX header missing on `ios/Runner/SceneDelegate.swift`, `ios/RunnerTests/RunnerTests.swift`, `tool/gen_protos.sh`; `sqlite3_flutter_libs` is EOL; `uuid` and `riverpod_annotation` unused; many direct deps a major behind; no CI (a 4-step GitHub Actions workflow is sketched in release.md); screenshots predate the tab rename; elevation data source not credited in NOTICE; "Meshtastic" lacks ® on first use in store text.
- **Untested areas** (quality): `SessionManager`, DB migrations, CSV export, BLE reconnect, `SignalHistory`, `LiveActivityService`.

## 4. Release checklist (condensed; full versions in compliance.md and release.md)

**Before the public TestFlight link**
1. Fix §1 items 1, 5–9 in code (one field-build PR, plus the public-channel/ping change as its own protocol PR).
2. Approve the plateau-beta deploy; rewrite the privacy text (OSM + Open Topo Data); set App Privacy answers in ASC.
3. Hygiene pass (§2 #14) → make the repo public; confirm the in-app Source link resolves.
4. §2 #15–#20; bump to 0.9.0; `fastlane beta`.
5. ASC: Beta App Description, feedback email, privacy URL, "What to Test" (draft in release.md).

**Before App Store submission**: §3 licensing letter to Meshtastic LLC, privacy manifest, tile/terrain hosting plan, reviewer demo video, Keychain for the PSK, screenshots regenerated.
