# Radio Setup, admin configuration and radio backups review (Opus, 2026-10-26)

Branch `field-build-oct23`, HEAD 7e0e7fc. No repository files changed. The six named test files pass: 95/95. Three scratch repros (`scratchpad/enumcheck/check.dart`, `t2_test.dart`, `commit_test.dart`) confirmed F1, F3 and F4.

Confidence key: High = traced in code or reproduced. Med = the code is clear, but the firmware behaviour it relies on wasn't checked on hardware. Low = speculative.

## 1. Ranked findings

| # | Sev | Conf | Location | Symptom |
|---|---|---|---|---|
| F1 | **High** | High (repro) | `meshtastic_radio.dart:1187-1197`, `:1138` | If the BLE link drops after the last acknowledged write but before the commit is sent, setup reports "Done". The settings stay in RAM only and revert at the next power-cycle or brown-out. Nothing checks the radio after it reboots. |
| F2 | **High** | High | `radio_profile_service.dart:99`, `radio_backup_service.dart:560-576`, `restoreDiff` `:67-72` | Radios whose original backup predates 2026-10-23 (commit 4ef244a) have no telemetry or device config in any backup. "Put back" leaves them relaying LOCAL_ONLY with the beacon telemetry settings, and the preview hides those rows. |
| F3 | **High** | High (repro) | `radio_backup_service.dart:461-466`, `:499-517` | Importing a backup for a radio that already has a backup on this phone drops its "original" flag, and prune deletes it immediately. The snackbar still says "Imported…". |
| F4 | Med | High (repro) | `meshtastic_radio.dart:1234-1241` | A preset or region newer than the vendored v2.7.26 protos (e.g. 2.8 MEDIUM_TURBO) survives Radio Setup, and the app reads it as LONG_FAST. |
| F5 | Med | High | `radio_setup_screen.dart:374-396`, `radio_profile_service.dart:116-119`, `:346-356` | Handover item 2 is **not fixed**. In the base-first flow the mobile gets its own region (US if unset), not the base's, and is never asked. |
| F6 | Med | Med | `meshtastic_radio.dart:1121-1129` | `sendAdmin` retries on a new connection. If the radio rebooted mid-sequence, the rest of the writes are saved one by one outside the edit transaction, leaving a partly saved config. |
| F7 | Med | High | `radio_setup_screen.dart:259-289` | Radio Setup has no "session recording" guard (Restore has one). Changing settings mid-session reboots the radio, and the session keeps the wrong preset. |
| F8 | Med | High (design doc) | `radio_types.dart:351-357` | Bases on 2.6/2.7 use the Range Test beacon, which turns itself off 8 h after boot. A base set up the night before is silent on the day. |
| F9 | Med | High | `radio_profile_service.dart:106-113` | The MeshTest key lives only in SharedPreferences. After a reinstall or on a new phone there is no way to adopt the key from a radio, and the mismatch banner doesn't compare keys. |
| F10 | Low | High | `radio_setup_screen.dart:281` | "Your radio may be half-configured" also shows when nothing was written (a BLE connect failure or a failed backup read). |
| F11 | Low | High | `radio_profile_service.dart:211-214` | In the base-first flow the base never gets the mobile's public key. The NodeInfo exchange before pings recovers this. |
| F12 | Low | High | `radio_setup_screen.dart:104`, `radio_backups_section.dart:252` | Setup and Restore don't block each other. Re-opening the screen mid-run re-enables Apply. |
| F13 | Low | Low | `radio_profile_service.dart:182` vs `meshtastic_radio.dart:624` | The region is re-read after the commit. A racing reconnect handshake can make it record "US". |
| F14 | Low | High | `SceneDelegate.swift`, `Info.plist:11-22` | `.mabackup` is registered as a document type but nothing handles opening it. "Open in Mesh Analyzer" from Files or AirDrop does nothing. |
| F15 | Low | High | `radio_backups_section.dart:90-92` | Handover item 4 leftover: the restore dialog still says "The radio reboots". |
| F16 | Low | High | `radio_setup_screen.dart:168-174` | The base location is saved from `lastPosition` with no age check. |
| F17 | Low | Med | `meshtastic_radio.dart:1259-1264` | 2.6.x has no `device_telemetry_enabled`, so a 2.6 mobile keeps broadcasting telemetry. A classic ESP32 on 2.7 gets Range Test even though it isn't compiled in (no such radio in this fleet). |
| F18 | Low | High | `radio_roles.dart:185-196` | Making a second radio the base leaves the old one beaconing as "MeshTest Base" with no role tag. |

## 2. Details for the top findings

**F1: a link lost before the commit counts as success**
- **Cause:** `commitSettings` catches `StateError` and only rethrows when the radio is ready. `sendAdminAttempt` throws `StateError('Radio not ready')` *before writing anything* when the link is down. So a commit that was never sent is logged as "commit reply lost to reboot", and `applyTestProfile` logs "Done".
- **Repro:** a subclass with `isReady == false` completes `commitSettings()` normally.
- **Also affected:** Restore uses the same `commitSettings`.
- **No check afterwards:** `applyToBase` disposes the base connection straight after the commit. The ✓ line only proves the RAM state unless a reboot really happened.
- **Why it matters here:** this is the same state the solar node is in now, per the memory note.
- **Fix:**
  - In `commitSettings`, if not ready, throw "Lost the radio before saving: nothing was saved. Power-cycle it and run Radio Setup again."
  - Better: mark errors raised before the write as "not sent".
  - Add a check after the reboot that reads back channel[0] name and key, preset, region, LOCAL_ONLY and the beacon config, and logs ✓ or ✗.
  - For the base, either reconnect about 15 s later, or have the mobile confirm it hears the base on MeshTest.

**F2: Put back can't undo relay and telemetry changes on older originals**
- **Cause:** backups gained telemetry and device config in 4ef244a (2026-10-23); before that, setup didn't write them. Originals are pinned, and re-runs skip the backup while the radio is on MeshTest. So no backup holds the pre-LOCAL_ONLY state. Restore and `restoreDiff` simply omit fields the backup lacks.
- **Likely affected:** probably the T1000-E and H1, which were used with the app before the spike (beacon-kinds §5) — not confirmed.
- **Field impact:** a solar node that normally serves the mesh would stop relaying.
- **Fix:**
  - Always show the Telemetry and Relaying rows; when the backup lacks them, say "not in backup, stays X" in amber.
  - On Put back, when the backup has no device config, set rebroadcast to ALL. When it has no telemetry, set `deviceTelemetryEnabled=false`.

**F3: an imported backup is deleted on import**
- **Cause:** `store` sets `original: existing.isEmpty`, then `prune` keeps only the original, five manual saves and the newest automatic one.
- **Repro output:** `imported original flag=false exists=false`. The only "original" left is the MeshTest state.
- **When it bites:** after a reinstall, on a new phone, or after "Erase all app data" (which deletes `radio_backups/`), if a setup or manual backup runs before the import.
- **Fix:** an import keeps its original flag when it is older than the current original (and un-flags the old one). Never prune the file just imported; treat imports like manual saves. Don't flag a MeshTest-channel snapshot as the original.

**F4: unknown preset or region survives setup**
- **Cause:** Dart protobuf keeps an unknown enum value in `unknownFields`. `deepCopy` keeps it, and `writeToBuffer` writes it *after* the field we set.
- **Repro:** `[8,1,16,6,56,1,16,99]` — field 2 appears twice, with 99 last. The firmware keeps the last value.
- **Fix:** call `lora.unknownFields.clearField(...)` for the modem_preset and region tags (and rebroadcast_mode on the device config) before writing. Longer term, regenerate the protos from a 2.8 tag.

**F5: base-first mobile region**
- **Cause:** `_switchToMobile` never calls `_ensureRegion`. `_profile` uses the newly connected mobile's region, falling back to US. The mismatch banner only catches it after both radios are recorded.
- **Impact:** small for a US-only owner.
- **Fix:** after connecting, use `_roles.regionOf(base)`; if there is none and the mobile's region is unset, show the region dialog.

**F6: retry on a new connection**
- **Cause:** the reconnect starts after 2 s and can reach "ready" inside the 10 s acknowledgement timeout. If the radio itself rebooted, the edit transaction is gone.
- **Fix:** track a connection counter. Don't retry, or restart the whole sequence from `beginEditSettings`, when it has changed.

**F7: no session guard.** Use the same guard as Restore (`radio_backups_section.dart:51-53`). The mismatch banner's "Tap to fix in Radio Setup" invites exactly this mid-session.

**F8: 8-hour Range Test auto-off.** Mitigated by absent-beacon detection and the Restart button, so treat it as a procedure step.

**F9: losing the channel key.** Offer "Use this radio's MeshTest key" when a connected radio's MeshTest key differs from the stored one, and keep the key in the Keychain.

**F10–F18 fixes**
- **F10:** only show the half-configured warning once the first admin write has started.
- **F11:** correct CLAUDE.md, which claims setup always swaps keys both ways.
- **F12:** share one "busy" lock between Setup and Restore.
- **F13:** read the region once at the start of `_apply`.
- **F14:** add an `openURLContexts` handler, or drop the document-type claim.
- **F15:** change "reboots" to "restarts".
- **F16:** only save the position if it is a couple of minutes old at most.
- **F18:** when a new base is assigned, prompt to turn off the old base's beacon.

## 3. Handover items 1, 2 and 4

- **Item 1 (base location): partly fixed.**
  - Fixed: new-map defaults follow what exists (072bc96), and declining the Radio Setup location is remembered and honoured (`create_map_dialog.dart:174`, `coverage_map_detail_screen.dart:216-219`).
  - Not fixed: GPS still starts with `request:false` (`app.dart:88,108`), and Radio Setup only reads `lastPosition`, so a fresh install saves nothing. A saved location is still where setup happened, with no age check. "I'm standing at the base" is still greyed out without a fix.
- **Item 2 (base-first mobile region): not fixed** — see F5.
- **Item 4 (wording): mostly fixed** in 149c7f9.
  - Fixed: "public key" (`radio_profile_service.dart:219`), "restarts" (`meshtastic_radio.dart:1313`), "While Using the App" (`session_manager.dart:147`), and the two card titles.
  - Left: "The radio reboots" at `radio_backups_section.dart:90-92`.

## 4. Edge cases checked and found correct

- **Backup comes first:** it runs before `_introduce` and before any admin write, and `snapshot` refuses to run on incomplete settings.
- **Re-running and swapping roles:** these skip the backup. The original is pinned, and a save identical to the newest backup only updates its date.
- **Admin writes:** refusals (NAKs) are never retried and show "Radio rejected setting: X". Every step has a timeout, so nothing hangs. Local admin over BLE needs no passkey. On 2.8 the Range Test module write is accepted and simply not kept (spike §5).
- **Channels:** slot 0 is the primary MeshTest channel with a 32-byte key; slots 1–7 are disabled, so a radio that already has 8 channels is fine. The name is within the 11-character limit, and both radios land on the same frequency slot.
- **What setup keeps:** LoRa, device and telemetry settings are copied from the radio, so only the intended fields change. Owner names fit the limits.
- **Beacon choice:** telemetry for 2.8+, a reported Range Test exclusion, or unknown firmware. Telemetry intervals are rounded up to whole minutes (at least 60 s). `device_telemetry_enabled` is set only for a telemetry beacon. The packet processor only counts the beacon kind the session expects.
- **Firmware version parsing** handles suffixes and a leading "v".
- **Region:** the connected radio's unset region is caught before setup in the mobile-first flow and in base step 1. Presets are filtered by region.
- **Roles:** `assign` clears a conflicting role, and Put back clears the radio's roles only after a successful restore.
- **Restore safeguards:** it refuses while recording or for the wrong radio, and writes exact protobuf bytes.
- **Backup files:** v1 `.json` files are still read, damaged files are skipped, and name collisions get a suffix.
- **Contacts:** only records with 32-byte keys are kept.
- **Base step:** the second BLE connection is always disposed.

## 5. Radio preparation for the field day

**The day before (at home, phone beside the radios)**
1. Don't reinstall the app or use "Erase all app data" — the channel key and backups live only on the phone.
2. For each radio:
   - Check that Backups shows an **Original settings** entry.
   - Open Restore on it and check the preview lists **Telemetry beacon** and **Relaying**. If they're missing, note the radio's rebroadcast mode and telemetry settings from the official app first.
   - Share each original to the Mac as an off-phone copy. Don't re-import it unless the phone has lost its copy, and then do it before running any setup on that radio.
3. In the official app, check each radio: the preset is a classic one (no MEDIUM_TURBO or TINY_* on 2.8); the region is US; Tx power is the same on both; `security.is_managed` is off; power saving is off on the Heltec and the solar node.
4. Any radio that was re-flashed or reset: "Forget This Device" in iOS Bluetooth settings first.

**Setup (mobile-first: it asks for the region and swaps keys both ways)**
5. Connect to the radio you'll carry, open Radio Setup, choose Mobile, then Find base radio and wait for "Done", then Apply to this radio.
6. Connect to the base: check it shows the base role, MeshTest and the ✓ line. **Power-cycle it, reconnect and check again** (works around F1). Do the same for the mobile.
7. Solar node: power-cycle it *before* re-running setup (it reverts to its last saved settings). Re-run until "Done", then verify after another power-cycle.
8. Run only one base at a time.

**Morning of the test**
9. Restart the base so a Range Test beacon gets its full 8 hours. This applies to the T1000-E on 2.7.x and the solar node on 2.6.9; a 2.8 Heltec uses telemetry with no auto-off.
10. Set the base location on site: map menu → Set base location…, or "I'm standing at the base".
11. Start a session only once there's no mismatch banner and pings come back. Never open Radio Setup while recording.

**After the test**
12. End the session. Put each radio back, power-cycle it, and check in the official app that the channels, preset, name, **rebroadcast mode** (normally ALL) and telemetry are right. Fix them by hand where the original had no Relaying row.

**Firmware notes**
- **2.6.x (solar node):** add_contact can be slow over BLE (the step is skippable). The mobile can't turn telemetry broadcast off. The beacon is Range Test with the 8-hour auto-off.
- **2.7.26:** the T1000-E and Heltec V3 have Range Test. Classic ESP32 boards don't, and the app can't tell.
- **2.8.x:** the beacon is telemetry at 60 s or more. Make sure the preset is one the app knows (F4).
