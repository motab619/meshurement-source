# Mesh Analyzer: data and workflow review (2026-10-17)

Reviewer lens: GIS / spreadsheet power user who keeps logs. Scope: the data model, export, backups, the session and map lifecycle, rig profiles, nodes and storage. Nothing modified. Leaves out what the 2026-10-16 audit already covers (orphaned rows on map delete, CSV formula injection, leftover CSVs after Erase, plaintext PSK in backups, GPS fix age, Range Test packets dropped while the dialog is pending).

## 1. What's solid

- **The restore guard works.** You cannot restore one radio's backup onto another: `RadioBackupService.restore` refuses when `myNodeNum != backup.nodeNum` (`radio_backup_service.dart:197`), and the UI disables the button (`radio_backups_section.dart:220-221`). Restore is blocked while a session records and asks for confirmation.
- **Backups cover what Radio Setup changes.** All 8 channel slots, the full `LoRaConfig`, Range Test and the owner `User` (`radio_backup_service.dart:150-166`).
- **The backup file format is good.** Format/version, human-readable summary, exact protobuf bytes, plus a standard `meshtastic.org/e/#` channel URL.
- **Rig snapshots keep history honest.** `mobileRigJson`/`baseRigJson` are copied at session start (`all_tables.dart:88-90`); profiles are archived, never deleted (`app_database.dart:313`).
- **Session metadata is better than most hobby tools.** Preset, protocol, ping interval, per-ping airtime, max radio air-util/channel-util, Range Test flag. Pings have outcome plus round trip.
- **CSV columns go beyond the firmware's.** ack_status, RTT, gps_accuracy, preset and rig gain, 7-decimal lat/lon. Sortable file names (`csv_export_service.dart:130`).
- **`SessionDigest` is a clean aggregate** with distance bands, not coordinates; `assertNoLocationData` checks that (`ai_analysis.dart:174-213`).
- **Erase is properly tiered** and refuses while recording (`data_erase_service.dart`).
- **Storage growth is a non-issue.** A 2-hour session is under 300 KB.

## 2. Findings, ranked

### HIGH

**H1. CSV timestamps have no timezone and only whole seconds.**
- Where: `csv_export_service.dart:75`, `app_database.dart:27`, no `build.yaml`.
- drift stores `DateTime` as Unix seconds and reads it back as local time; `toIso8601String()` emits `2026-10-17T14:03:22.000` with no `Z` or offset. QGIS, Google Earth time sliders and spreadsheets misread it; it can't be joined with radio logs or weather data; wrong across DST or when shared across zones.
- Fix: export `timestamp.toUtc().toIso8601String()`; add `timestamp_local` with offset and `unix_ms`; consider text or millisecond storage in a future schema change.

**H2. The base position is not data: it lives in SharedPreferences and is never exported.**
- Where: stored `constants.dart:126` (`terrain_base_location_<mapId>`), `create_map_dialog.dart:159-163`, `base_location.dart:28`; resolved `coverage_map_detail_screen.dart:183-195`, `range_stats.dart:80`.
- Fallback is `nodes.lastLat/lastLon`, overwritten live by every position packet. Neither the map nor any session snapshots it. The CSV has no base lat/lon, distance or bearing. Old sessions' distance stats silently change when the base's position updates or the user re-pins. Deleting a map leaves the pref behind.
- Fix: `coverage_maps.base_lat/base_lon/base_alt/base_source/base_accuracy_m`; snapshot on `sessions` at start; export `base_lat`, `base_lon`, `distance_m`, `bearing_deg` per row.

**H3. Radio Setup can change the preset mid-session, and the session keeps the old one.**
- Where: `session_manager.dart` `startSession` captures the preset once; `radio_setup_screen.dart` has no `activeSession` guard (hint text only at `:743`). Restore is guarded; Apply is not.
- Fix: block Apply while recording, like Restore, or auto-end and start a new session.

**H4. Export is per session and CSV-only, with no GIS-native format and no full-data export.**
- Where: `coverage_map_detail_screen.dart:897-912` (only call site), `csv_export_service.dart:23`.
- No KML, GPX or GeoJSON. No per-map or all-data export. No JSON or SQLite archive, no import. Files land in `Documents/` reachable only via share sheet; no `UIFileSharingEnabled`/`LSSupportsOpeningDocumentsInPlace`, so invisible in Files.
- A map with 12 sessions means 12 share sheets. The DB is the only copy of the user's data; no way to move it to a new phone except iOS backup. iCloud sync is a Pro roadmap item, but the free tier has no manual escape hatch, which conflicts with "never hold data hostage".
- Fix: see §3A. Minimum: per-map CSV and GeoJSON, plus "Export all data".

### MEDIUM

**M1. The CSV says it matches the Meshtastic convention, but it doesn't.** (`csv_export_service.dart:34`) The firmware's `rangetest.csv` header is `time,from,sender name,sender lat,sender long,rx lat,rx long,rx elevation,rx snr,distance,hop limit,payload,rx rssi`. Ours has no sender position, distance or payload. Fix the comment or add a compatible variant.

**M2. The Range Test sequence number is thrown away.** (`packet_processor.dart:187-229`; `ReceivedPacket.payload` exists but is never stored.) Without `seq`, packet loss in Range Test mode is unmeasurable. Add `packet_events.seq`, export `seq` and `missed_since_prev`.

**M3. Node identity in the export is a mutable display name.** (`csv_export_service.dart:66-72`) Names are overwritten in place with no history; re-exporting after Radio Setup renames changes the data; two radios with the same name are indistinguishable. Export `source_node_id` (`!hex`) and `source_node_num`, plus long/short names; snapshot base and mobile node num and names on the session.

**M4. Sessions have no lifecycle tools.** No rename, delete, move or merge queries in `app_database.dart`. In order of value: rename, delete (cascade), move to map (same base node), trim by time, merge.

**M5. You can't write down the test conditions.** (`all_tables.dart:61-100`) `hwNotes` isn't editable later. Antenna height is one global pref. No weather, foliage, vehicle/on-foot or notes. Mobile node num, firmware, region, frequency slot and tx power aren't recorded although `loraConfig` has them. Add editable session `notes`, `mobile_height_m`, `base_height_m`, `mobile_node_num`, `firmware`, `region`, `tx_power_dbm`, `hop_limit`, `frequency_mhz`.

**M6. "A map is one base location" is neither stated nor enforced.** (`create_map_dialog.dart:136-165`) A map binds a base node, not a place. Snapshot the base position per session; at start, if more than about 50 m from the map's base, prompt "Base has moved, new map?".

**M7. Fix metadata is incomplete.** (`packet_processor.dart:192-207`, `active_probe_service.dart:211-225`) Only lat, lon, alt and accuracy are kept; `timestamp`, `speed`, `heading` are dropped. Store `gps_fix_time`, `speed_mps`, `heading_deg`; export `gps_age_s`.

**M8. Relayed packets are dropped by default, and the export never says so.** (`packet_processor.dart:150-158`) Store a per-session `relayed_ignored` count and the setting value at start; put them in the export header or sidecar.

**M9. Backups pile up, aren't grouped, and can't be imported.** (`radio_backup_service.dart:136-188`, `radio_backups_section.dart:216-226`) One JSON per save, named `<nodehex>_<local time without offset>.json`, written only when the radio is not already on MeshTest plus every "Back up now". Every Restore followed by Radio Setup adds another "Before Radio Setup" copy of the same original config. Every radio ever connected shows in one flat newest-first list; other radios' Restore is greyed with no explanation. No dedupe, no pinned original, no import (no document types or file picker). After a restore, `RadioRoles` and `base_loc_*` still tag the radio as base or mobile. See §3B.

### LOW

- **L1.** Re-export overwrites the same filename (`csv_export_service.dart:129`). Add `_s<sessionId>`.
- **L2.** Rig model gaps (`all_tables.dart:40-57`): no tx power, height AGL, polarization or mount. No "Duplicate" for A/B variants.
- **L3.** Saved comparisons live in prefs (`rig_comparison.dart:319`), never removed with their map, not exportable. A "Share summary" (`SessionDigest` JSON plus matched-cell CSV) would be cheap.
- **L4.** No storage readout; DB is in `Documents` (`app_database.dart:519`) so it goes into iCloud/Finder backups with GPS tracks of the user's home. Acceptable, but say so. Add "N maps · M packets · X MB" under Settings → Data.
- **L5.** Export gives no privacy warning. Base coordinates are usually home. Offer "Hide base position" once H2 lands.
- **L6.** `firstSeenAt` would be reset by `upsertNode`'s `insertOnConflictUpdate` (`app_database.dart:89-97`); fragile. Use `insertOrIgnore` and update names separately.

## 3A. Proposed export spec

**Scopes:** session · coverage map · all data. **Entry points:** map menu "Export…" and Settings → Data → "Export all". **Delivery:** share sheet, plus `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` with an `Exports/` folder.

1. **CSV (analysis)**, UTF-8, RFC 4180, one row per packet event:

   `event_id, session_id, session_name, map_id, map_name, timestamp_utc (ISO 8601 Z), timestamp_local (with offset), unix_ms, direction (rx|tx|ack), packet_type (range_test|ping|ack|nodeinfo|position|telemetry|text|other), mesh_packet_id, seq, source_node_id (!hex), source_node_num, source_long_name, source_short_name, lat, lon (WGS84, 7 dp), alt_m, gps_accuracy_m, gps_age_s, speed_mps, heading_deg, snr_db, rssi_dbm, hop_count, via_mqtt, channel_index, base_lat, base_lon, distance_m, bearing_deg, ping_status (received|implicit|timeout|throttled|error), ping_error, round_trip_ms, lora_preset, region, frequency_mhz, tx_power_dbm, protocol, ping_interval_sec, packet_airtime_ms, mobile_node_id, mobile_rig, mobile_net_gain_db, mobile_height_m, base_rig, base_net_gain_db, base_height_m, radio_air_util_tx_pct, radio_channel_util_pct, app_version`

   Session metadata in a sidecar `.json` rather than comment lines (some tools choke on comments).

2. **CSV (Meshtastic-compatible):** exactly the firmware header, rx rows only.
3. **GeoJSON** (RFC 7946): Points with lon,lat order and the CSV properties; a base Point (`role: "base"`); one `LineString` per session track. Best for QGIS.
4. **KML:** Folder per session; placemarks styled by SNR/RSSI bucket; `TimeStamp` for the Google Earth time slider; base placemark; ping failures as a separate style; `ExtendedData`.
5. **GPX 1.1:** `trk` per session, samples as `wpt`, signal values in `<extensions>`.
6. **Archive (`.meshanalyzer`, zip):** `manifest.json`, `data.json` (maps, sessions, events, pings, nodes, rigs, base positions, comparisons), the CSVs. Import via a registered UTI, remap ids, match nodes by node num, never overwrite. Radio backups excluded unless ticked (channel keys). Needs the `archive` package (add to NOTICE).

**Comparison export:** `SessionDigest` JSON plus a cell CSV (`cell_lat, cell_lon, a_rssi, b_rssi, delta_db, a_n, b_n`).

## 3B. Proposed backups design

**Where they live.** Keep per-file JSON. Show backups on a **per-radio card**, not a flat list. Radio Setup shows the connected radio's card on top (name, `!hex`, role); other radios collapse under "Other radios (n)". A disabled Restore says why: "Connect to *MeshTest Base* to restore".

**Pinned original.** The first backup taken before Radio Setup for a node is marked `original: true` and pinned ("Original settings (saved 10/12)"). Auto-prune never deletes it. Before writing a new backup, compare protobuf bytes with the newest for that node; if identical, update `lastConfirmedAt` instead of adding a file. That kills the restore → setup duplicates.

**Auto-prune.** Per radio, keep the original, the 5 newest manual saves and the newest automatic one.

**Restore as a first-class action.** Radio Setup gets a top-level **"Put this radio back the way it was"** button, visible when the connected radio is on MeshTest and has an original. The confirm dialog shows a diff (name, channels with "public LongFast" called out, preset/region, Range Test on/off) and says pings and sessions stop working on this radio until Radio Setup runs again. On success, clear that radio's role in `RadioRoles`. Offer "Restore both radios" as a guided two-step flow.

**Export and import.** "Share file" stays, with a channel-keys warning (currently only Copy link warns, `radio_backups_section.dart:131`). Register a document type so a file opened from Files or AirDrop lands in Backups for its node. Bump `version` to 2 with `original`, `lastConfirmedAt`, `firmwareVersion`, `appVersion`. If the PSK moves to Keychain, consider encrypting backup files at rest.
