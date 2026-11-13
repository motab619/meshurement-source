# Mesh Analyzer: security and data-protection audit (update)

Tree audited: `/Users/andybrunker/develop/mesh_analyzer`, branch `field-build-oct23` at `ab1a7cc` (98 commits ahead of `main`) plus the uncommitted working-tree changes (`map_screen.dart`, `coverage_map_detail_screen.dart`, `estimate_samples.dart`, icon script). Read-only; `flutter test` and `flutter analyze` were not run (another agent owns them). `docs/beta/` was not reviewed. Previous report: `docs/audit/2026-10-16/security.md`.

## Summary

The prior HIGH is fixed. The "never on the public channel" rule is now enforced where the packets are sent: `ActiveProbeService` checks before every ping and before every NodeInfo exchange, `MeshtasticRadio.ping` and `exchangeNodeInfo` refuse on their own, Restore is refused while a session records, and switching radios mid-session asks first. The 16-byte default key is now recognised. CSV formula injection is fixed, and the privacy screen now names every outside host with its own switch. No secrets, private keys, channel keys or personal coordinates were found anywhere in the tree or the full git history (all 268 commits).

The main new risk comes from the guided-test remote admin. Radio Setup writes the mobile radio's public key into the base's `security.admin_key` by default. Nothing in the app ever removes it, and "Put this radio back the way it was" does not touch it. Whoever later holds the mobile radio keeps full remote admin over what is often the user's own home node. The other new items are an unauthenticated AI endpoint whose quota and Pro gate are client-side only, home coordinates and logs surviving "Erase all app data", and a silent eviction of an existing admin key when the list is full. Data at rest is unchanged: the test channel key and every backup's channel keys are still plaintext.

**Counts:** HIGH 1 · MEDIUM 5 · LOW 11 · INFO 7

## Findings

### [HIGH] The base keeps the mobile radio as a remote admin forever, even after "Put this radio back"
- **Where:** `lib/ui/screens/radio_setup_screen.dart:83` (`_allowRemote = true`), `:1213-1224` (checkbox, on by default); `lib/services/radio_profile_service.dart:213-227, 245-251` (grant inside the setup transaction); `lib/data/radio/meshtastic/meshtastic_radio.dart:1446-1480, 1667-1722` (`applyTestProfile(remoteAdminKey:)`, `grantRemoteAdmin`); `lib/services/radio_backup_service.dart:864-905` (`_restoreMeshtastic` restores channels, LoRa, modules, device and owner, never `security`); `lib/ui/widgets/radio_backups_section.dart:114-116` (put-back only clears the app's `RadioRoles` entry); `lib/services/radio_roles.dart:324-343` (`clearNode` removes only the `base_remote_admin_node` pref).
- **What:** An `admin_key` entry gives the holder of the matching private key full remote administration of the node: read every channel and its key, change channels, owner and LoRa settings, reboot, factory reset. The grant is written by default in the base flow. No code path removes it (a search for any removal of `adminKey` finds none). Backups do not include the security config, so Restore and "Put this radio back the way it was" leave the key in place, while the app forgets that it ever granted it.
- **Why it matters:** The mobile radio is the device a tester carries, lends or hands back (the tester kit). Long after the test, that radio can still reconfigure the user's base remotely, often their personal or home node, and can read its channel keys. The put-back button promises the opposite.
- **Fix:** Snapshot `security.admin_key` in the backup, or at least record which key the app added. On "Put this radio back" and on Restore of the original, remove the key the app added (local admin: begin, `set_config(security)` without it, commit). Add a "Stop allowing remote changes" action next to the grant. Consider making the checkbox opt-in per guided test rather than on by default, and say in the subtitle that it lasts until removed.

### [MEDIUM] Test channel key still in plaintext SharedPreferences (unchanged)
- **Where:** `lib/services/radio_profile_service.dart:50, 143-150` (`test_channel_psk`, base64, `setString` not awaited); `lib/data/radio/meshtastic/meshtastic_radio.dart:1616-1618` (`positionPrecision: 32` on MeshTest); `lib/services/data_erase_service.dart:33-37` (kept by Erase).
- **What:** As in the prior report. The 32-byte key sits in `Library/Preferences/com.andybrunker.meshAnalyzer.plist`, which goes into iCloud and Finder backups. MeshCore radios get the first 16 bytes of the same key (`channelKey16`), so the one secret now protects both protocols.
- **Why it matters:** Anyone with the key can decrypt the radios' full-precision positions and the base location over the air.
- **Fix:** Move it to the Keychain (`flutter_secure_storage`, `first_unlock` accessibility so background sessions can read it), migrate once and delete the prefs copy; await the first write.

### [MEDIUM] Radio backups keep every channel secret in plaintext files (partly fixed)
- **Where:** `lib/services/radio_backup_service.dart:636-645` (`Documents/radio_backups/`), `:767-768` (`_write`, JSON with base64 protobuf channels incl. PSKs; MeshCore v3 files hold every slot's secret); `lib/ui/widgets/radio_backups_section.dart:33-34, 376-415`.
- **What:** Share file now asks first and warns that the file holds channel keys. Copy channel link still puts the keyed URL on the general pasteboard first and only warns afterwards in a snackbar. The files themselves are still plaintext in Documents with default file protection and are included in device and iCloud backups.
- **Why it matters:** These are the user's own long-lived mesh keys from before Radio Setup, for both protocols.
- **Fix:** Confirm before Copy link as well. Encrypt the backup bodies with a Keychain-held key, or set `NSFileProtectionComplete` on `radio_backups/` and exclude it from iCloud backup (`NSURLIsExcludedFromBackupKey`).

### [MEDIUM] "Erase all app data" leaves exports, the diagnostics log and the base (home) locations
- **Where:** `lib/services/data_erase_service.dart:126-138` (`eraseEverything` skips `BaseLocationStore.isKey`, deletes only `radio_backups` and `elevation_cache`); `lib/services/base_location.dart:28-36, 54-56` (`base_loc_<node>` = lat, lon, accuracy, time); `lib/services/csv_export_service.dart:218-225` (`Documents/Exports/`, never deleted); `lib/services/diag_log.dart:35-36, 73-78` (`Documents/diag.log`; `clear()` is never called); `lib/data/database/app_database.dart:443-457` (deletes rows, no `VACUUM`); dialog copy `lib/ui/screens/settings_screen.dart:421-429`.
- **What:** After "Erase all app data" the phone still holds: the base locations Radio Setup recorded (the phone stands next to the base, so usually the user's home, to within 50 m), every CSV, GeoJSON, KML and zip export (full GPS tracks), the diagnostics log (BLE names, other people's node names, session times), and the deleted SQLite pages. The dialog lists only the channel key and the Pro purchase as kept.
- **Why it matters:** The erase does not do what it says, and the leftovers are location history and the home location.
- **Fix:** Remove `base_loc_*` in `eraseEverything` (or list it in the dialog as kept). Delete `Documents/Exports/` in both erase jobs, or write exports to the temp directory and delete them after sharing. Call `DiagLog.instance.clear()`. Run `VACUUM` after the deletes.

### [MEDIUM] AI endpoint is unauthenticated; quota and the Pro gate are client-side only
- **Where:** `tool/ai-analysis/template.yaml:69-71` (`FunctionUrlConfig: AuthType: NONE`); `tool/ai-analysis/handler.py:58` (`DEVICE_ID` = any UUID-shaped string), `:1019-1046` (quota keyed by the caller's `X-Device-Id`); `lib/utils/constants.dart:16-17` (Function URL `https://3bci…lambda-url.us-west-2.on.aws/`, shipped in the binary and the repo); `lib/services/ai_analysis.dart:575-611`, `lib/services/guided/plan_intent_parser.dart:575-605`.
- **What:** Anyone who reads the URL from the app or the (soon public) repo can call it with a fresh random device id per request. The per-device daily and monthly limits are therefore no limit, and nothing server-side checks Pro. Only the global cap of 2000 calls per day bounds use. The routes are narrow (forced tool output, size limits, field whitelists and coordinate scans), so this is not an open LLM proxy, but the user question (300 chars) and plan text (500 chars) do reach the model.
- **Why it matters:** One script can spend the whole daily budget, which turns AI analysis off for every real user until the next UTC day (a cheap denial of service on a paid feature), and gives non-subscribers the feature.
- **Fix:** Require App Attest (DeviceCheck) assertions, or at least a signed StoreKit 2 JWS transaction for Pro, verified in the Lambda. Add a per-IP limit (Function URLs give `requestContext.http.sourceIp`) or put API Gateway with a usage plan and WAF rate rule in front. Keep the global cap.

### [MEDIUM] A full admin-key list silently loses one of the user's existing admin keys
- **Where:** `lib/data/radio/meshtastic/meshtastic_admin_keys.dart:17-37` (`adminKeysWith` evicts the oldest non-own key when 3 are present); `lib/data/radio/meshtastic/meshtastic_radio.dart:1695-1706` (the eviction is only `print`ed and written to `diag.log`).
- **What:** When the base already has three admin keys (for example the user's own phone node or another admin node they manage it from), the grant removes the oldest one without telling the user. The step list shows no line for it.
- **Why it matters:** The user can lose remote administration of a radio they manage from elsewhere and not find out until they need it.
- **Fix:** When the list is full, stop and ask which key to replace (show the 4-byte prefix and the node name if known), or skip the grant and say why.

### [LOW] Two send paths still lack a radio-level public-channel check; MeshCore and simple-key detection have gaps
- **Where:** `lib/data/radio/meshcore/meshcore_radio.dart:820-848` (`ping` has no `onPublicChannel` check, unlike `MeshtasticRadio.ping` at `meshtastic_radio.dart:1165`); `lib/services/guided/plan_runner.dart:1545-1572` (`_pingUntilHeard` calls `_env.ping` and `_env.prepareToPing` directly, bypassing `ActiveProbeService`); `lib/data/radio/meshtastic/meshtastic_radio.dart:1792-1843` (`setRemoteLora` sends on channel 0 with no check); `lib/data/radio/meshcore/meshcore_radio.dart:714-723` (public = exact match with the snapshot table); `meshtastic_radio.dart:520-530` (`isPublicPsk` accepts last bytes `0x01`-`0x0a` only).
- **What:** The guided-test listen loop pings without the probe service's guard; on MeshCore nothing below it refuses. Remote admin also has no guard. MeshCore "public" means only the parameters in the community table, so a local mesh on custom parameters passes. The firmware expands any 1-byte PSK value 1-255 into the default key with `last + index - 1`, so expanded forms with last bytes `0x0b`-`0xff` are equally well known.
- **Why it matters:** Defence in depth for the project's hard rule; today the mobile is normally on MeshTest when these run, so the practical exposure is small.
- **Fix:** Add `if (isReady && onPublicChannel) return fail(..., 'PUBLIC_CHANNEL')` to `MeshCoreRadio.ping` and a `StateError` to `setRemoteLora`. Treat any 16-byte key equal to the default in bytes 0-14 as public.

### [LOW] Over-the-air NodeInfo replaces a node's cached public key, which is then saved and pushed to the radio
- **Where:** `lib/data/radio/meshtastic/meshtastic_radio.dart:931-938` (any decoded `NODEINFO_APP` overwrites `nodeInfos[from].user`, key included); `:1094-1114` (`prepareToPing` calls `_rememberNode(target)`, saving that record in `radio_contacts_v1`); `:1121-1133, 1236-1245` (`ensureContact(force: true)` writes the saved key with `add_contact` after a PKI NAK).
- **What:** The app keeps the newest key it saw for the base, while the firmware refuses a key change for a known node. A NodeInfo that claims the base's node number with another key (needs the MeshTest key, or a node-number collision) becomes the saved contact and can be written back into the mobile with `add_contact`.
- **Why it matters:** Pings and remote admin would then be encrypted to the wrong key and fail, and remote-admin requests (LoRa settings) would be readable by that key's holder.
- **Fix:** Keep the first 32-byte key seen per node (trust on first use, like the firmware), never overwrite a saved key from the air, and save the base's key only from Radio Setup or a direct BLE connection to the base.

### [LOW] MeshCore adverts from the RF log are trusted without their signature
- **Where:** `lib/data/radio/meshcore/meshcore_radio.dart:493-499` (every logged advert goes to `_upsertNode`); `lib/data/radio/meshcore/meshcore_packets.dart:114-145` (`MeshCoreAdvert.tryParse` reads key, position and name, no Ed25519 check); `meshcore_radio.dart:568-584` (`_upsertNode` overwrites name, position and `publicKey` for the same 4-byte node number).
- **What:** `0x88` frames carry every packet the radio heard, including ones the firmware itself rejects. Any transmitter can send an advert with the base's key (or a key sharing its first 4 bytes, which is a feasible vanity search) and change the name, position and stored key the app shows for the base. The trace target prefix is the same 4 bytes, so a colliding repeater could also answer link checks.
- **Why it matters:** Spoofed base names and positions on the map and in exports; wrong attribution of link checks. Requires a deliberate attacker in RF range.
- **Fix:** Verify the advert signature (Ed25519 over key, timestamp and app data, as the firmware does) before using it, or take node data only from the radio's own contact frames. Never replace a stored 32-byte key with a different one for the same node number.

### [LOW] Second Bluetooth connections to "the base" do not check that they reached the base
- **Where:** `lib/services/radio_profile_service.dart:441-470` (`setBaseBeacon` connects to the stored `base_ble_id` and writes the beacon); `lib/services/guided/app_plan_environment.dart:257-279` and `radio_profile_service.dart:508-537` (`changeBaseBluetooth` → `applyToBase` → full base profile); `lib/services/radio_roles.dart:298-299` (role by node number, else by Bluetooth id).
- **What:** These flows connect by the remembered iOS peripheral id and then write settings without comparing `radio.myNodeId` with `RadioRoles.nodeOf(base)`. iOS ids are stable per phone, so this mainly matters after a factory reset or key regeneration (on 2.8 the node number follows the key), or a radio re-flashed to the other role.
- **Why it matters:** A radio that is no longer the base could be reconfigured as one, including a full Radio Setup with the test channel.
- **Fix:** After connect, refuse when the node number differs from the remembered base (and offer Radio Setup instead).

### [LOW] An imported backup can become a radio's "original"
- **Where:** `lib/services/radio_backup_service.dart:735-765` (`store` marks the first backup per node as `original`), `:772-792` (`import` calls `store`).
- **What:** A `.mabackup` received from someone else for a node number with no local backups becomes that node's pinned original. "Put this radio back the way it was" would then write its channels (and owner) to the radio. The restore diff and the node-number check limit the damage.
- **Why it matters:** A crafted file can replace the user's real original settings with someone else's channel table.
- **Fix:** Never mark imported files as original (or ask), and label imported backups in the list.

### [LOW] Node positions from the mesh are still not range-checked (unchanged)
- **Where:** `lib/data/radio/meshtastic/meshtastic_radio.dart:281-282`; `lib/data/radio/radio_types.dart:151-154`; MeshCore `meshcore_packets.dart:155-156`.
- **Fix:** In `RadioNode.hasPosition` also require `|lat| <= 90 && |lon| <= 180`.

### [LOW] Region setup still turns on transmit on the default public channel (unchanged)
- **Where:** `lib/data/radio/meshtastic/meshtastic_radio.dart:1578-1586` (`txEnabled = true`); `lib/ui/widgets/region_dialog.dart:80-83`.
- **Fix:** One line in the dialog ("the radio joins the public mesh until Radio Setup"), or chain Radio Setup after it.

### [LOW] Permission declarations (partly fixed)
- **Where:** `ios/Runner/Info.plist:50-53` (`NSBluetoothPeripheralUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription` still present); `ios/Podfile:47-50`.
- **What:** The permission_handler macros are now just `PERMISSION_BLUETOOTH=1`, but still assigned with `||=`, so they only apply when the key was nil. The Always and obsolete Peripheral strings remain although Always is never requested.
- **Fix:** As before: drop both keys, use `(... ||= ['$(inherited)']) << 'PERMISSION_BLUETOOTH=1'`, add `BYPASS_PERMISSION_LOCATION_ALWAYS=1` for geolocator.

### [LOW] Personal email in every commit (unchanged)
- **Where:** all 268 commits on all branches are authored `<personal address>`.
- **Fix:** Rewrite to the GitHub noreply address before the repo goes public, or accept it.

### [LOW] PMTiles directory parser trusts lengths from the network
- **Where:** `lib/data/tiles/pmtiles_archive.dart:213-261` (`gzip.decode` without a size cap; `List.filled(n)` with `n` from an unbounded varint).
- **What:** A corrupt or hostile archive (or a compromised CDN path) can make the app allocate without bound and crash. The source is the project's own CloudFront over HTTPS, so this is defence in depth.
- **Fix:** Cap `n` (for example by the directory byte length) and the decompressed size, and stop varints after 9 bytes.

### [LOW] Anthropic API key is a plain Lambda environment variable
- **Where:** `tool/ai-analysis/template.yaml:9-13, 60-61`; the handler already supports `ANTHROPIC_SECRET_ARN` (`handler.py:373-390`).
- **What / Fix:** Anyone with Lambda read access sees the key in the console and in `GetFunctionConfiguration`. Switch the template to the Secrets Manager ARN path the handler already has.

### [INFO] Public URLs in the source
- The AI Function URL (`constants.dart:16-17`) and the CloudFront tile URLs (`lib/utils/map_tiles.dart:68-78`) are in the repo and binary by design. Treat the AI URL as public (see the MEDIUM above).

### [INFO] Pro cache and test unlocks
- `pro_entitlement_v1` is plain JSON (`pro_entitlement.dart:436-454`). A forged `{"plan":"lifetime"}` (via backup editing) is honoured only until a refresh succeeds, because a successful refresh replaces the state with StoreKit 2 `currentEntitlements` (`:298-310`). Revenue-only.
- TestFlight unlock relies on `appStoreReceiptURL` ending in `sandboxReceipt` (`ios/Runner/AppDelegate.swift:38-41`), which users can't set; demo mode forces Pro only on the throwaway demo DB.

### [INFO] Internal docs
- `CLAUDE.md`, `docs/roadmap.md` and design docs still carry business and infrastructure notes; one doc in history lists SSM parameter names for the ops dashboard (names only, no values). Decide what goes public.

### [INFO] Root `.gitignore` still narrow
- No entries for `.env*`, `*.p8`, `*.sqlite*`, `*.csv`, `*.mabackup`, `diag.log`. Device pulls described in CLAUDE.md (`devicectl ... copy from`) land in the repo root by default.

### [INFO] One key, two protocols
- MeshCore's MeshTest channel uses the first 16 bytes of the Meshtastic 32-byte key. A leaked MeshCore backup reveals half of the Meshtastic key (still a 128-bit secret). Separate keys per protocol would remove the link.

### [INFO] Unused remote-admin entry point
- `RadioProfileService.grantRemoteAdminAtBase` (`radio_profile_service.dart:374-416`) has no caller in `lib/ui`. It refuses the mobile itself but not a radio that isn't the base; check that before wiring it to a picker.

### [INFO] Dependencies
- New runtime packages since the last audit: `file_picker`, `archive`, `flutter_compass`, `clock`; `uuid` is now used (AI device id). `riverpod_annotation` is still unused. Not checked against an advisory database.

## Prior findings

| Prior finding (2026-10-16) | Status | Evidence |
|---|---|---|
| [HIGH] Pings and NodeInfo exchange skip the public-channel guard after a session starts | Fixed | `active_probe_service.dart:148-157` (`_blockedByPublicChannel`), `:160-176` (key exchange gated), `:242-247` (checked before and after the exchange on every ping); `meshtastic_radio.dart:1081` (`exchangeNodeInfo`), `:1165` (`ping` returns `PUBLIC_CHANNEL`); `radio_backups_section.dart:52-55` (Restore refused while recording); `connection_banner.dart:539-562` (switch confirmation); `session_manager.dart:103-120` resumes and relies on the per-ping check. Residual gaps in the LOW above. |
| [MEDIUM] Public-channel detection misses the expanded 16-byte default key | Fixed (small residual) | `meshtastic_radio.dart:515-541` (`defaultPsk`, `isPublicPsk`, used by `onPublicChannel`); last bytes above `0x0a` still pass (LOW above). |
| [MEDIUM] Test-channel PSK in plaintext SharedPreferences | Still open | `radio_profile_service.dart:50, 143-150`; `positionPrecision: 32` at `meshtastic_radio.dart:1618`. |
| [MEDIUM] Radio backups keep channel keys in plaintext JSON, shared without warning | Partly fixed | Share asks first (`radio_backups_section.dart:376-408`); Copy link warns only after copying (`:411-415`); files still plaintext (`radio_backup_service.dart:767-768`). |
| [MEDIUM] CSV formula injection through node names | Fixed | `export/csv_v2.dart:147-157` (`csvSafeText` on every text cell); `export/meshtastic_csv.dart:40`; KML escapes names (`export/kml.dart:14, 81-103`); GeoJSON via `JsonEncoder`. |
| [MEDIUM] Erase all leaves CSV exports | Still open (and wider) | `data_erase_service.dart:126-138`; exports now in `Documents/Exports/` (`csv_export_service.dart:218-225`); base locations and `diag.log` also kept (MEDIUM above). |
| [LOW] Location / permission over-declaration | Partly fixed | Podfile macros trimmed (`ios/Podfile:47-50`) but still `||=`; Always and Peripheral keys remain (`Info.plist:50-53`). iPad targeting removed (`TARGETED_DEVICE_FAMILY = 1`). |
| [LOW] Region setup turns on transmit on the public channel | Still open | `meshtastic_radio.dart:1578-1586`; `region_dialog.dart:80-83`. |
| [LOW] Node positions not range-checked | Still open | `meshtastic_radio.dart:281-282`; `radio_types.dart:151-154`. |
| [LOW] Location sent to OpenTopoData / OSM without disclosure | Fixed | `lib/ui/screens/privacy_screen.dart:40-70` (per-host switches: map tiles, terrain, AI with Anthropic named); welcome flow links the policy (`onboarding/welcome_flow.dart:426`). |
| [LOW] Personal email in commit metadata | Still open | 268 commits, one author address. |
| [LOW] Shared backup files identify the radio (owner record) | Partly fixed | The pre-share warning exists but names only channel keys, not the node identity (`radio_backups_section.dart:33-34`). |
| [INFO] Internal planning docs become public | Still open | `CLAUDE.md`, `docs/roadmap.md`, design docs. |
| [INFO] Team ID and bundle IDs | No action needed | Unchanged; public by design. |
| [INFO] Dependencies | Partly | `uuid` now used; `riverpod_annotation` still unused; majors still behind. |
| [INFO] Demo mode grants Pro; Pro cache trusted offline | Unchanged (by design) | `providers.dart:213-218`; `pro_entitlement.dart:298-310, 436-454`. TestFlight unlock added (`test_build.dart`). |
| [INFO] Android project is a stub | Not re-checked | Out of scope for iOS. |

## Checked, OK

- **Secrets in the repo.** `git log -p --all` (excluding `docs/beta/`) for Anthropic, AWS, GitHub, Google and Slack key formats, PEM private keys, ASC key and issuer ids, `.p8`/`.p12`/`.mobileprovision`/`.env` files: nothing but placeholders (`sk-ant-...` in the AI README) and SSM parameter names. `tool/ai-analysis/samconfig.toml` holds only limits and the model id. `ios/fastlane/.env` is not tracked.
- **Channel keys and channel links.** No 32-byte base64 key, no `meshtastic.org/e/#` link and no non-test 64-hex value in the history (the hex strings are SHA-256 test vectors and pub lock hashes).
- **Coordinates.** Every precise latitude/longitude pair in the history and working tree rounds to 33.7, -116.2/-116.3 (Empire Polo Club demo and tests), plus synthetic test values (33.0, -116.0) and the San Francisco fallback in `constants.dart`. Nothing else.
- **Remote admin protocol.** Requests are PKI-encrypted DMs with `want_ack` (`meshtastic_radio.dart:1911-1936`); answers are matched by request id and sender (`:1938-1965`); the session passkey is taken from the node's own `get_config` response and only kept in memory for the exchange; the target is always `RadioRoles.nodeOf(base)` (`app_plan_environment.dart:111, 246-255`); the own node is refused (`:1813-1815`). `_securityWithAdminKey` refuses the radio's own key and refuses to write back a security config without the private key (`:1689-1714`). The radio's private key is read only over local admin, kept in memory and never logged or backed up (backups hold channels, LoRa, modules, device and owner only).
- **AI data.** The comparison digest (`ai_analysis.dart:24-260`) and the guided digest (`guided/plan_analysis.dart:760-810`) carry aggregates, rig labels, preset names and distances, never positions, node numbers or radio names from the mesh; `assertNoLocationData` runs before every send (`ai_analysis.dart:736`, `plan_analysis.dart:327`, `widgets/guided/plan_ai_card.dart:82`) and the Lambda repeats the scan (`handler.py:184-205`). Sending requires consent (`hasConsent`). HTTPS only, no certificate overrides or ATS exceptions; client timeouts 55 s and 8 s, server 45 s with no retries.
- **AI output.** Answers render as plain `Text`; the only links are the app's own mailto/support URLs. A plan reply must pass `PlanIntent.validate` (variant count, TX power 0-30 dBm, route length) and becomes a plan the user reviews; radio changes run only on the user's tap on the step's primary action (`plan_runner.dart:205-210`), with preflight, backups and rollback. Unknown preset ids fail rather than guess.
- **MeshCore codec.** `MeshCoreFrame.parse` reads through a bounds-checked `_Reader` and turns short frames into `MeshCoreMalformedFrame` (`meshcore_frames.dart:732-741, 1467-1531`); path lengths are validated (`:44-47, 362-388`); contact path slicing is bounded by the validated length; advert, trace and raw-packet parsers check lengths first; UTF-8 decodes with `allowMalformed`. Trace replies are matched by a random 32-bit tag.
- **Meshtastic protobuf handling.** Every `fromBuffer` on radio or mesh data is in a try/catch (`meshtastic_radio.dart:105-108, 181-185, 883-890, 932-969`; contacts and backups likewise).
- **Untrusted names.** Mesh node names reach CSV (escaped), KML (escaped), the stranger banner and `diag.log`; notifications use fixed text only (`out_of_range_monitor.dart`, `base_ride_along_detector.dart:383`); the Live Activity gets session and base names as plain strings; no mesh name reaches the AI digest.
- **Public-channel rule elsewhere.** The only `sendData` callers are `exchangeNodeInfo` and `ping`; Network Mode traceroutes are not implemented. Radio Setup writes MeshTest as the only enabled channel with MQTT uplink and downlink off (`meshtastic_radio.dart:1609-1623`). `onPublicChannel` is true while the channel table or MeshCore radio parameters are unknown.
- **Restore safety.** Restore checks node number and protocol (`radio_backup_service.dart:840-860`), shows a diff, and is refused while recording. Backup file names are hex node number plus timestamp (no traversal). No `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace = false`, and no open-in-place handler; imports go through the file picker.
- **Pro entitlement.** Only `ProEntitlement` touches StoreKit; a successful refresh replaces the cache with `currentEntitlements`; `PRO_OVERRIDE` is debug-only.
- **Randomness.** Channel key, packet ids and trace tags use `Random.secure()`; the AI device id is a UUIDv4 and is reset by Erase.
- **Logging.** `diag.log` holds no positions or keys (spot-checked all 39 `DiagLog` calls); admin-key log lines show 4-byte prefixes of public keys only.
- **Working-tree changes.** The uncommitted map, compass and estimate-samples changes add no network, file, preference or radio-write code.
