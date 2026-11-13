# Network Mode: implementation plan

Status: plan, 2026-10-22, from the Network Mode handoff (same date). Nothing built. All decisions (D1–D6, §4) made 2026-10-22; ready to build in phase order after the beacon-kinds PR.

## 0. Summary

Network Mode fits the code better than the handoff assumes in one place and worse in two:

- **Better:** "Continue from a previous drive" maps directly onto the existing CoverageMap → Sessions hierarchy. A *network map* is a coverage map with no base; continuing a drive is just a new session in that map. No session-to-session lineage needed.
- **Worse (policy):** the mobile has to leave MeshTest to hear the mesh at all, so Network Mode runs on the community's channel, which is usually the public one. Passive capture is fine. Auto-traceroute is the app transmitting on the public channel; allowed for Network Mode as a new use case (**D1**, decided).
- **Worse (RF):** "only direct receptions count" would throw away most of what you hear on a real mesh. A relayed packet is still a direct RF reception, from the *relay* rather than the sender. Attribution needs `relay_node` (**D2**).

Sequencing: Network Mode Phase 1 changes `packet_events` and `PacketProcessor`, and so does the beacon-kinds PR (schema v7, `source_kind`). Build Network Mode on top of it (schema v8). The traceroute API it needs is the one the Traceroute probe PR (next-steps item 3) builds, so build it once there.

## 1. Facts from the code and firmware that shape this

1. **MeshTest is on its own frequency.** The frequency slot is hashed from the primary channel name, and Radio Setup sets `channelNum = 0` with primary "MeshTest" (`radio_profile_service.dart:37`, `meshtastic_radio.dart` `applyTestProfile`). A MeshTest radio hears none of the local mesh. Network Mode therefore needs the mobile back on the community channel/preset/slot, which means reconfiguring it (reboot) or restoring its backup.
2. **The phone only sees packets the radio can decrypt** (channel PSK match), and only the first copy of each (the router drops duplicates before the phone API). Strangers' PKI DMs and other channels' traffic are invisible. Coverage and density are lower bounds. *To confirm on hardware: whether firmware forwards undecodable packets to the phone at all.*
3. **Traffic is sparse on default settings.** On the public channel a node sends NodeInfo every 3 h, position every 15 min (less when stationary on 2.8) and device telemetry every 30 min. Away from busy routers, minutes of silence are normal. This is why the silence-timer traceroute matters, and why "covered route %" needs a defined time window (**D4**).
4. **`hops > 0` packets are dropped at ingest today** (`packet_processor.dart`, "Count relayed packets" setting). The handoff wants ingest to capture everything. That moves the relay filter from ingest to the queries/renderers, which changes Base Mode code paths (see §3, Phase 1).
5. **`MeshPacket.relay_node`** (firmware 2.6+) is the last byte of the node that transmitted what we heard. It isn't read yet (critique S3 already asks to store it).
6. **`coverage_maps.base_node_id` is NOT NULL.** A network map has no base. Making it nullable needs a drift `TableMigration` (SQLite rebuild), not an `ALTER`.
7. `PacketProcessor` feeds `OutOfRangeMonitor` and `RangeTestDetector`. Both are base-centric. Strangers' Range Test packets would trigger the "log this node's range test?" prompt in Network Mode, so Network sessions bypass the detector.

## 2. Decisions needed

**D1. Transmitting on the public channel: DECIDED 2026-10-22.** Allowed for Network Mode: it is a new use case, and listening and traceroutes on the mesh's own channel (public included) are part of it. Base Mode keeps its rule and still refuses to start on the public channel. Recorded in CLAUDE.md and the roadmap.

**D2. What counts as "heard" for painting: DECIDED 2026-10-22.** A `hops == 0` packet paints for `from`. A `hops > 0` packet paints for its **relay** when `relay_node` resolves to exactly one node heard directly in this map (1-byte match on the node number); otherwise it is stored but doesn't paint. A relayed packet's SNR is never attributed to its originator.

**D3. Tier: DECIDED 2026-10-22 (B adjusted).** Free: Network capture, map, tap popover, summary card with both KPIs (nodes per mile, covered route %), exports. Pro: density toggle (both renderings), tap-to-filter, rig/antenna comparison across Network drives, base-logger merge and report. Sessions store `recorded_with_pro` at start; drives recorded with Pro keep density and filter after Pro lapses (never lock data), drives recorded free never had them. Gate via `ProEntitlement.canCreate`/`canView` with new `ProFeature` values.

**D4. Covered route %: DECIDED 2026-10-22.** Route distance = sum of steps between consecutive GPS fixes, skipping fixes with accuracy worse than 50 m. A step is covered if its midpoint is within ±60 s and 500 m of a paintable reception (the density window, §4 Q2). Stretches where the radio link was down (`radioLost`) or GPS had no usable fix are **unknown**: left out of the percentage, drawn grey dashed, and reported ("68% covered · 3% radio offline"). Nodes per mile or per km by locale. The per-drive card shows the drive; the network map header shows the combined figure across its drives (phase 4).

**D5. Getting the mobile onto the mesh: DECIDED 2026-10-22.** The mobile radio switches back and forth; no separate "Network" radio role. Start sheet: if the radio is already on a mesh channel, show its channel + preset and start with one tap. If it is in MeshTest, Start is disabled and it offers "Put this radio back the way it was" (backup restore, needs `feat/backups-redesign`) or "Public default" (LongFast for the region), each with a reboot warning. No channel editor (club channels are set up in the official app first). Starting a Base session with the radio off MeshTest offers Radio Setup.

**D6. Shared cards: DECIDED 2026-10-22.** The card shows both KPIs, unique node count, hop mix, duration, the user's rig and the coverage route image (no node positions). Strongest node appears without a name ("Strongest: 9.5 dB SNR, direct"). Per share: "Show node names" switch, **off every time** (not remembered), and "Hide start and end" privacy zone (first/last ~500 m of the route), **on by default**. Both affect only the shared image, never stored data, the in-app map or exports (CSV/GeoJSON keep names).

## 3. Phases (handoff §9), mapped to code

### Phase 1: ingest and session plumbing (schema v8, own PR: schema + protocol)

Radio layer:
- `ReceivedPacket` gains `to`, `hopStart`, `hopLimit` (raw; `hops` stays derived), `relayNode` (int?, null when unknown/pre-2.6). Filled in `receivedPacketFrom`.

Schema v8:
- `packet_events`: `from_node_num INTEGER` (mesh number, denormalised so exports and merges don't go through local ids), `to_node_num`, `hop_start`, `hop_limit`, `relay_node`, `radio_rx_time` (the radio's clock, for the merge). `source_kind` comes from the beacon PR (`passive` here).
- `sessions`: `recorded_with_pro BOOL` (D3), `mode TEXT DEFAULT 'base'` (`base | network`), `uuid TEXT` (for cross-device merge, backfilled), `channel_name`, `region`.
- `coverage_maps`: `kind TEXT DEFAULT 'base'`, `base_node_id` nullable (TableMigration).

Ingest:
- `PacketProcessor` records every non-stale packet while a session is active, relayed ones included. Base Mode keeps its current behaviour by filtering `hop_count = 0` in its queries and in the `OutOfRangeMonitor` call (unless "Count relayed packets" is on). This is the risky part for Base Mode: regression tests on the base map queries, stats, CSV v2 and `RangeStats` before anything else.
- Network sessions skip `RangeTestDetector`, `OutOfRangeMonitor` and `ActiveProbeService`; GPS background mode and the Live Activity are the same as Base Mode.
- `SessionManager.startNetworkSession(...)`: allowed on any channel (the `onPublicChannel` refusal stays for Base Mode); records mode, channel, preset, mobile rig (base rig null).

UI:
- Start sheet: mode choice (Base / Network, kept separate as the handoff says), D5 channel/preset row, rig picker (mobile only), "Continue a previous drive" = pick a network map, or "Start from scratch" = new network map.
- Node list: filter "My radios / Heard on drives", otherwise hundreds of strangers bury the base and mobile.

Gate: drive, then inspect raw rows (CSV v2 export with the new columns).

### Phase 2: map and popover

- Aggregate per 50 m cell (`CoverageInterpolation.cellMeters`): best paintable SNR, and per node: best SNR, min hops, last heard.
- Hue thresholds: whatever Base Mode uses when this ships. If link-margin colouring (next-steps item 4) lands first, use margin here too; one legend.
- Tap a cell → popover with the node rows (short name, SNR, hops, last heard). Each row is the tap-to-filter entry for Phase 4.
- Continued drives: earlier sessions in the same map render as the base layer.

### Phase 3: auto-traceroute, silence timer, stats

- `MeshRadio.traceroute(target, {hopLimit, timeout})` → `TracerouteResult` (route, `snrTowards`, routeBack, `snrBack`; quarter-dB, `INT8_MIN` = unknown). Built in the Traceroute probe PR and reused here.
- `NetworkProbeService`: silence timer from the last paintable reception; quiet window = 60 s scaled by `AirtimeModel` relative to LONG_FAST, user-overridable with the same inline explanation as slow presets; never below 30 s (official apps' client floor). Skips when the radio's channel utilisation is above 25%.
- Target: see §4 Q1. Path nodes are logged for hop analysis, never painted (handoff §3.2).
- Bonus: `snrTowards[0]` from a directly-heard target is how well *it* hears *us*. Store it; it's the start of the uplink story the base logger completes.
- Stats panel items 1–5 in the existing expander.

### Phase 4: density, filter, summary

- Legend toggle: Signal only / Signal + density. Density = unique paintable nodes per cell; saturation by default, blue shift as the alternate.
- Tap-to-filter from the popover and stats panel; clear-filter chip.
- Summary card: nodes per mile (per km by locale), covered route % (D4), unique nodes, strongest node, hop mix, duration, rig. Respect D6.

### Phase 5: base-side logger data contract

- The merge key is **`(from_node_num, mesh_packet_id)`**, not the packet id alone: ids are chosen by the sender, so the same transmission has the same pair at both ends. Collisions within a drive are negligible (32-bit random). Use time only as a sanity check (±30 s on phone UTC, `radio_rx_time` when set).
- Each log carries `sessions.uuid`, a device role (`mobile | base_logger`) and an install id, so files from two phones join without guessing.
- Export: the CSV v2 / zip format with the v8 columns, so the merge can be done on any machine.
- Note: in Network Mode the mobile transmits little (its own NodeInfo/position/telemetry, plus its traceroutes), so mobile→base samples will be sparse between traceroutes. Worth saying in the report UI.

## 4. Answers to the handoff's open questions

1. **Traceroute target and pacing: DECIDED 2026-10-22.** Target = strongest-SNR node heard directly (hops == 0) in the last **5 min**, not traced in the last **10 min**; fallback the map's base, then the 2nd/3rd strongest outside cooldown. Nothing eligible: back off, doubling the quiet window up to 5 min (don't stop). Quiet window 60 s on LONG_FAST scaled by preset airtime, 30 s floor, user-overridable. Hop limit **2**. Skip while the radio reports channel utilisation > 25%. Hard cap **30 traceroutes per hour**. No want_response NodeInfo broadcast probes (reply storm; firmware throttles them).
2. **Density: DECIDED 2026-10-22 (windowed).** Each track point is credited with every paintable node heard within **±60 s and 500 m** of it; a **150 m** cell's density is the union of its track points' node sets, unioned across the map's sessions (continued drives deepen it). Hue stays measured: best paintable SNR at actual receptions, 50 m cells. Popover lists real receptions only. Legend: "Depth = nodes heard within ~500 m". The same window defines covered route % (D4), so map and summary agree.
3. **Parked-car pollution: DECIDED 2026-10-22 (mark stops, don't pause).** A stop = moved < **30 m in 3 min** (displacement, not GPS speed: a parked phone's speed jitters 0.5–2 m/s). Stop receptions count for hue, popover and raw data, and are excluded from density and nodes per mile; the map shows a small "stopped N min" marker. No "Include stops" toggle unless testers ask.

## 5. Out of scope (agreeing with handoff §8)

No Network-on-Base overlays, CarPlay, PAX counters, merged session type, painting of nodes known only from the node DB, or server upload.
