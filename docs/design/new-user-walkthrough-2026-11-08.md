# New-user walkthrough, 2026-11-08

A pass through the app on the iPhone 18 Pro simulator as a **mid-skilled mesh
user**: someone who runs the Meshtastic app, knows presets (LONG_FAST), channels
and PSKs, reads SNR/RSSI, has two T1000-Es, and is not an RF engineer. Two
runs: a fresh install (welcome flow → Coverage → Live → Settings) and demo mode
(`-demoScreen session|coverage|compare|radio|report`). Branch
`claude/first-run-notes-77c276` at `9c1262a`.

Companion to `first-run-walkthrough-2026-11-06.md` (Andy's run on the phone).
Each item is a recommendation with a rough size, **ranked by how much it
would help that user**, not by screen.

**Status 2026-11-08 (Andy: "do all of them"):** everything below was built the
same day on this branch, seven agents in parallel by file area. Notes on how
each landed are in the "Built" section at the end.

## Top ten

| # | Where | What a new user sees | Recommendation | Size |
|---|-------|---------------------|----------------|------|
| 1 | Recording panel (Live → Session while recording) | Thirteen plain text lines in one block: map, hardware, started, preset, packets, beacons, ping interval, airtime, radio stats, GPS, Live Activity note. The numbers that matter during a walk look the same as facts the user already knows. **End session is below the fold** at the sheet's half height. | A 2×3 stat grid at the top (Readings · Beacons heard / expected · Pings ok · GPS · Airtime · Elapsed), the setup facts collapsed under a "Setup" row, and End session pinned at the sheet's bottom edge so it is always visible. | M |
| 2 | Recording panel | "Beacons 15 heard · ~19 missed" reads as a failure with nothing to measure it against. | "Beacons 15 of 34 (44 %)" coloured by band (≥ 80 % ok, 50–80 % amber, below red), with the same figure on the session tile. | S |
| 3 | Live map | A light OSM basemap inside a near-black UI: the map is the brightest thing on screen and the orange / red dots fight yellow roads. Coverage detail already dims its map; Live does not. | Dim the Live basemap the same way (the detail screen's wash), or a dark style for the self-hosted streets layer; at least a "Dim map" switch in Display. | S (wash) / L (dark tiles) |
| 4 | Radio Setup | One long scroll that mixes status, choices, three explanatory paragraphs, the two steps and Backups. The big orange button is step 2 ("Apply to this radio") under the outlined step 1 ("Find base radio"): the brightest control is the second thing to do. | Three cards in order: **Who is this radio?** (the segment) → **Settings** (range, beacon; explanations behind ⓘ) → **Apply** (base first when the role is mobile, with the primary style on whichever step is next). Move Backups to Settings → Backups and leave one "Put this radio back" link here. | L |
| 5 | Coverage tab (home after onboarding) | "Plan a test" is the largest orange button while the checklist is at 1 / 4. A new user taps the brightest thing and lands in a guided flow that needs both radios set up. | Tonal / outlined while steps 1–2 are open; primary once Radio Setup is done. | S |
| 6 | Welcome 02 Privacy, 03 Permissions | Both pages run past the fold with no hint that they scroll: the AI helpers text is cut behind the Next button; the Notifications **Allow** button is off screen, so a user taps Next believing all three were asked. | One-sentence blurbs with a "Details" disclosure on Privacy; a compact row on Permissions (icon · title · Allow on one line, the reason under it); bottom padding equal to the button bar on both. | S |
| 7 | Welcome 01 | The trademark paragraph is body text on the first screen the user ever sees. | One small line at the foot ("Meshtastic® is a trademark of Meshtastic LLC; not affiliated") and the full notice stays on About. | XS |
| 8 | Live map chrome | Compass, layers, Session: three glyph buttons, and the compass means two things (north up, then heading up) that only trial reveals. Tooltips exist but iOS users never see them. | Change the compass glyph when heading up is on (a filled arrow), and show a one-time toast "Heading up" / "North up" on toggle. Session is already an extended FAB; make the layer button one on first use. | S |
| 9 | Map detail | The legend chip and the attribution strip overlap at the bottom left; the session tile's subtitle is a nine-line sentence (setup · duration · distance · rx · SNR range · pings). | Stack legend above attribution; split the tile into a setup line and a stats line, bold the two numbers a tester scans for (base heard %, farthest). | S |
| 10 | Compare | The attribution chip sits under the mode selector at the top left, on the route. Otherwise the best screen in the app: the verdict sentence is exactly the right voice. | Move attribution to the bottom edge as on map detail. Reuse the verdict pattern on the session panel after End session ("Base heard 41 % · farthest 2.2 mi · median +7 dB"). | XS / S |

## The rest, by screen

### Welcome flow
- 04 "Two nodes, one private channel" is half empty: room for the one picture that explains the app (base ● ─── ● mobile + phone on a route). S.
- Body paragraphs are set in the mono face. Fine for readouts; heavy for four pages of prose. Proportional for paragraphs, mono for numbers. S (theme).
- Permissions page buttons are teal while every other primary is orange: on purpose (secondary), but it is the first teal the user sees. Consider tonal orange. XS.

### Coverage tab
- Bottom centre shows the empty-state `layers_outlined` icon in a rounded square: it reads as a third button next to +. Drop the square, or make the empty state a sentence ("No maps yet"). XS.
- The + FAB duplicates the card's New map while the card shows; hide the FAB until the card is dismissed or a map exists. XS.

### Live, idle sheet
- With nothing connected the sheet still shows Guided test, the warning, the map row, the name field and two hardware-profile dropdowns at "None". Blockers first, then the form; hardware profiles under "Hardware profiles (optional)". S.
- "Connect radio" pill reads as status. When disconnected give it a button shape and verb ("Connect a node"). XS.

### Recording
- "Direction: Received" in the signal readout is jargon: "Heard from base" / "Reply to your ping". XS.
- "Radio: TX 0.9 %/h · channel 6 % · just now" is in mono and a different voice from the lines around it; label it "Airtime" and set it like the others. XS.
- GPS "fix ±5 m": green when ≤ 10 m, amber above, red when none. XS.

### Map detail
- App bar: share, compare, terrain as glyphs; the compare glyph is not a known icon. Text actions in an overflow, or labels under the icons. XS.

### Radio Setup
- "Range setting" is this app's word; a Meshtastic user knows "modem preset". Say both once: "Range setting (modem preset)". XS.
- Beacon paragraph + airtime line + channel / region sentence are three explanations between two controls; fold into helper text under each dropdown. S.
- The remote-admin checkbox ("Let the mobile radio change this base from a distance") is four lines inside step 1. A one-line switch with ⓘ. XS.

### Settings
- "Count relayed packets" is a five-line explanation under a switch; keep "Off: only packets straight from the base count" and put the rest behind ⓘ. XS.
- "Keep screen on — Recommended for field sessions" yet off by default. Either turn it on automatically while a session records (the app already holds GPS in the background) or drop "recommended". S.

### Field Report
- The single-far-reading note overlaps the BASE label and the top of the route; move it under the map panel. XS.
- Otherwise the strongest visual in the app.

## Cross-cutting
- Glyph-only buttons everywhere (compass, layers, compare, share, terrain, +). Tooltips exist but are invisible on iOS without a long press. Prefer extended FABs and labelled actions where there is room; keep glyphs only in app bars with an overflow of text items.
- Explanations are long and placed inline. The app explains well; it explains too often at once. Pattern: one sentence inline, the paragraph behind ⓘ or a "Details" disclosure.
- Two voices: "node" in the welcome flow and session panel, "radio" in Radio Setup and Settings. That is by design (node = mesh participant, radio = hardware), and the node-wording session owns it; listed here only because a new user notices the switch on the same screen (welcome 04, step 01).

## Built (2026-11-08)

- **1 Recording panel:** `SessionStatsGrid` (`lib/ui/widgets/session_stats_grid.dart`): Readings · Beacons · Pings ok / GPS · Airtime · Elapsed; setup facts under a collapsed "Setup" row; problems stay visible under the grid; End session pinned in a bottom bar (`end-session`).
- **2 Beacons:** `beaconStatsText` says "Beacons 15 of 34 (44 %)" ("of ~34" when misses are approximate, "Link checks … answered" on MeshCore), coloured by `heardBandColor` (≥ 80 % ok, 50–80 % amber, below red).
- **3 Dim map:** `BaseMapLayers(dim:)` wraps only the tile layers in a desaturate + darken `ColorFiltered`; on by default for Live (`live_map_dim` pref, Settings → Display → Dim map). The detail screen turned out to have no wash; it is unchanged.
- **4 Radio Setup:** three cards (Who is this radio? → Settings → Apply to the radios), one-sentence helper text with ⓘ sheets (`InfoButton`), the next step filled and the other outlined, remote admin as a one-line switch, "Range setting (modem preset)" on Meshtastic. Backups moved to Settings → Radios → Radio backups (`RadioBackupsScreen`); Radio Setup keeps "Put this radio back the way it was" and "Backups…" links.
- **5 Plan a test:** outlined until Radio Setup is done (`radioSetupDone`), filled after (and in demo mode / checklist hidden).
- **6 Welcome 02/03:** one-sentence privacy blurbs with Details disclosures; permissions as one-line rows (icon · title · Allow) with the reason under; 76 pt bottom padding; a 402×874 test proves the Notifications Allow button sits above the Next bar.
- **7 Trademark:** one dimmed line at the foot of page 01 (`welcomeTrademarkLine`); the full notice stays on About.
- **8 Compass:** the glyph already changed with the mode (filled when heading up); added a 1.5 s floating toast per mode change ("Heading up: the map turns with you" / "North up" / "Heading up off"). Layers shows a "Layers" label until first opened (`map_layers_opened_v1`).
- **9 Map detail:** credit chip in its own right-aligned bottom row, legend above it; session tile is a dimmed setup line, a stats line with **Base heard N %** and **Farthest X** in bold (Field Report formulas), and a dimmed detail line; app bar = labelled Compare + a More menu with text items.
- **10 Compare:** attribution chip at the bottom right above the results sheet (follows the sheet). The verdict voice is reused on the session panel after End session ("Base heard 49 % · farthest 400 m · median +6 dB", never empty).
- **Rest:** page 04 `CoverageDiagram`; welcome prose in the system face; tonal orange Allow buttons; "No maps yet" empty state without the tile, + hidden while the card shows with no map; idle sheet blockers first, hardware profiles under a collapsed "Hardware profiles (optional)", Guided test last; `signalOriginLabel` ("Heard from base" / "Reply to your ping" / …); Airtime cell with the radio-measured figure as sub-label; `gpsStateColor`; "Count relayed packets" one line + ⓘ; `ScreenWake` keeps the screen on while a session records (the switch means always on); Field Report notes moved under the map panel (`RouteCaption`) in all three formats; "Connect a radio" is a tonal button when disconnected, and the three sentences that said "Connect radio pill" now say "Connect a radio".
- **Left alone:** the node/radio voice (node-wording session); dark tiles for the self-hosted streets layer (the wash covers it).
