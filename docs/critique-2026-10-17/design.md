# Mesh Analyzer: product design critique (2026-10-17)

Reviewer lens: senior iOS product designer (field/outdoor utility apps). Read-only review of `lib/app.dart`, all of `lib/ui/`, the Live Activity Swift code, the out-of-range monitor, the roadmap, the App Store copy and the prior UX audit. Skips what the 2026-10-16 audit already covers.

**First, the store screenshots are stale.** All six in `ios/fastlane/screenshots/en-US/` date from 2026-10-13. They show four tabs ("Map / Maps / Nodes / Settings"), "Preset: MEDIUM_FAST", no base-status bar and the old Radio Setup. The code now has three tabs ("Live / Coverage / Settings"), a first-run card, a BaseStatusBar, a role picker and a draggable sheet on map detail.

---

## 1. What the design gets right

- **The map is the home screen.** The Live tab is a full-bleed map with floating chrome, the right call for a walk-test tool. The connection pill doubles as the connect control.
- **BaseStatusBar** (`base_status_bar.dart:59-89`) answers the one question that matters ("am I hearing the base?") in a sentence, with a ticking age. This is the best element in the app; the rest should be built around it.
- **Measuring both directions** ("Signal from base" and "Pings to base") is a real differentiator, framed well on the coverage map detail screen. The ping strip under the charts (`signal_charts_panel.dart:472`) is a good glanceable pattern.
- **The first-run card** (`first_run_card.dart:85-94`) derives each step from real state and hides itself once done.
- **The Live Activity** (`ios/MeshActivity/MeshActivityWidget.swift`) shows range state, SNR, RSSI, pings, base name and "heard X ago". Right content.
- **Etiquette is built into the flow.** Public-channel guard, airtime floor and amber "faster than recommended" copy turn a constraint into a selling point.
- **The paywall tone is right.** Quiet, no countdowns, exemplary lapsed-Pro wording.

---

## 2. Findings, ranked

### HIGH 1: The store screenshots tell the wrong story, and the hero shot leads with a debug panel
**Where:** `01-live-map.png`, `03-session.png`, `06-radio-setup.png`; `lib/demo/`.

- Stale (see above).
- The hero shot's most prominent element is a six-line monospace readout: "SNR / RSSI / Hops: 0 (direct) / Dir: RX / Polo Field Base / Air 1.1%".
- The base is nowhere on the map, dots are mid-tone orange and olive on beige OSM tiles, the only button is "Session".
- `03-session.png` is a plain list of text lines with a red "End Session" button whose label is dark blue on red.
- `06-radio-setup.png` sells a settings form.
- Nothing says "two radios, one stays home, walk and see where the link holds".

**Fix:** regenerate from the current build; recompose around the story with caption bands (fastlane `frameit`):
1. "See where your link holds": live map with base pin, track line, dots and a green "Hearing the base · 3 s ago" band.
2. "Both directions": the Pings layer.
3. "Works in your pocket": the Live Activity on the lock screen. The most persuasive shot, and there isn't one.
4. "Compare presets and antennas": the comparison screen.
5. "Private test channel, one tap": Radio Setup as a success state, not a form.
Drop the session-controls shot.

### HIGH 2: The Live map shows where you heard the base but not where you didn't, and not where the base is
**Where:** `map_screen.dart:239-243` (layers are tiles, signal dots and my-location only), `:130-150`.

- No base marker on the Live map (coverage detail has one at `:445`, behind "Set base location").
- No GPS track is drawn. Failed/timed-out pings are not plotted live. No scale bar.
- A stretch with no dots could mean "no coverage", "I wasn't recording" or "GPS dropped"; the map can't tell them apart.

**Why:** a coverage tool's product is the edge of coverage. CellMapper draws your serving tower and a line to it. NetSpot overlays your survey path on the heatmap.

**Fix:** always draw the walked track as a thin neutral line; segments where the base was silent longer than the timeout get a dashed red line. Plot ping outcomes live as rings (filled = answered, hollow = no reply). Pin the base with a distinct glyph plus a faint line from you to the base labelled with distance ("1.4 km"). Scale bar bottom-left above the credit.

### HIGH 3: Three status surfaces that disagree in vocabulary, and the readout isn't glanceable
**Where:** pill badge "base ✓ / base lost / base ? / base …" (`connection_banner.dart:162-184`); BaseStatusBar; readout card border colour plus seven rows (`signal_display.dart`); "Air x%".

- During a session the top of the screen says the same thing three times, in three styles.
- Readout values are 14 pt with 12 pt labels. "Hops" and "Direction" are almost always "0 (direct)" and "Received".
- The readout keeps showing the last packet's SNR with no age, so a three-minute-old −2 dB looks live.
- In a car mount at arm's length, in sun, only the coloured border reads.

**Fix:** merge into one HUD band across the top while recording; the pill goes back to being just the radio connection.

```
┌──────────────────────────────────────────┐
│ ● HEARING BASE        3 s ago   1.4 km   │  ← full-width, state colour + icon
│  SNR  +4.5      Pings ▮▮▮▯▮▮▮▮  7/8      │  ← 28–34 pt numerals, last-8 strip
└──────────────────────────────────────────┘
```

Values grey out and show "(42 s old)" when stale. Hops, direction, RSSI, Air% and source name go into the charts/detail view, reached by tapping the band. Add a "Large readout" (car) toggle.

### HIGH 4: Starting a session is a form, and the three collection modes are invisible
**Where:** `session_panel.dart:308-450` (start form), `range_test_dialog.dart`.

- To start: map dropdown + "New map", name field, two rig dropdowns + "New rig (Pro)", a ping switch with a three-clause subtitle, an airtime explainer, a GPS line, a notifications line, then Start.
- Passive, range-test and ping modes are never named as choices. Range test appears as a modal AlertDialog mid-walk, exactly when the phone is in a pocket.
- The FAB says "Session" with a record icon even when idle, and opens a sheet titled "Session Controls".

**Fix:** one-tap start with an editable summary.

```
Start recording
  Empire Polo · Base: MeshTest Base        [Change]
  Measuring:  ✓ How well I hear the base (base beacon every 15 s)
              ✓ Whether the base hears me (ping every 15 s)
  Antennas:   Stock whip → Stock whip            [Change]
[ ●  Start ]                     (name it afterwards)
```

Name field moves to the post-session summary. Rigs hide behind "Change" (Pro lock only after that tap). FAB reads "Record" when idle; while recording it becomes a red pill with elapsed time. Replace the range-test dialog with a non-modal HUD banner: "Also hearing test beacons from Hilltop: [Record] [Ignore]", default Record.

### HIGH 5: There is no end-of-session moment; the payoff lives in another tab
**Where:** `session_panel.dart:272-304`.

After "End" the sheet silently flips back to the empty start form. The data shows up three levels deep in Coverage → map → session.

**Fix:** a summary sheet: duration, distance, farthest point heard, ping success %, mini map, name field, [View on coverage map] [Export CSV] [Done]. This is where Strava and Gaia hook the user; it's the screen people screenshot and share.

### HIGH 6: Radio Setup is a long scrolling form that mixes status, configuration, actions, log, tips and backups
**Where:** `radio_setup_screen.dart:484-748`; screenshot `06`.

One ListView holds: intro, connected status, role picker, rename checkbox, preset dropdown + airtime explainer, beacon dropdown, footnote, "1." and "2." step headings with buttons (including an inline scan list), bullet log, error/success, a tip, divider, the whole Backups section. The progress log and success message land below the fold of the button you pressed. "What happens to my radio?" is answered only in a confirm dialog. Reachable only from Settings, not from the connect flow where it's needed.

**Fix:** split into a status hub plus a wizard.

```
┌ Base ─────────────┐ ┌ Mobile (connected) ┐
│ MeshTest Base     │ │ MeshTest Mobile    │
│ Medium Fast · ✓   │ │ Medium Fast · ✓    │
│ Last heard 3 s    │ │ Battery 82%        │
└───────────────────┘ └────────────────────┘
[ Set up radios ]  [ Change preset ]
```

Wizard (full-screen, 4 steps, progress dots): 1. Which radio is connected? (two big cards: "I carry it" / "It stays put"). 2. Choose a preset as cards with a range/speed sketch; beacon interval under "Advanced". 3. "Here's what will change": private channel replaces all channels, public channel off, radio restarts, backup saved first. 4. Live checklist with ticks per radio, ending on a success screen with "Start recording". When connect detects a radio on the public channel, route straight into the wizard.

### MEDIUM 7: Backups are a long list of every snapshot of every radio, with four actions each
**Where:** `radio_backups_section.dart` build and `_BackupTile`.

- Each tile shows name plus raw node id, a hard-coded US-format date with reason, owner, preset, region and channel summary, and Restore / Share file / Copy link / Delete.
- Restore is greyed out for any radio that isn't the connected one and nothing says why (`canRestore: … radio.myNodeId == b.nodeNum`).
- It sits at the bottom of the setup screen, where people go to make changes, not to undo them.

**Recommendation (the developer's instinct is right):**
- Move backups into the radio's own detail view: Radios → [radio card] → "Settings history". Filter to that radio by default.
- Pin the original settings, labelled "Before Mesh Analyzer (original)": earliest backup per node, never auto-pruned. Below it, the last 3 automatic snapshots, then "Show all (12)".
- Name rows by what they captured: "Original: LongFast, 2 channels (Primary, Friends)" and "Oct 16: MeshTest, Medium Fast".
- Restore is the single primary action; Share file, Copy channel link and Delete go in a "…" menu (the channel link exposes keys).
- For a non-connected radio: "Connect to MeshTest Base to restore" with a Connect button, not a dead control.
- One prominent entry, "Put this radio back the way it was", on the radio card and linked from wizard step 3.

### MEDIUM 8: Settings is a junk drawer of view filters, physical properties and policy
**Where:** `settings_screen.dart:113-447`.

| Item | Belongs in | Reason |
|---|---|---|
| Signal Direction, Color Metric, Count relayed packets, Show colour key | Map **layers sheet** | They are how you look at the map. Hidden in Settings, users never discover RSSI colouring. |
| Base / Mobile antenna height (global sliders) | **Rig profile** (mobile) and the **coverage map's base** | Physical facts about a setup or place; a global value is wrong with two bases. |
| Ping interval + "Faster than recommended" | Start sheet "Measuring" row (Advanced) | Per-session choices already recorded per session. |
| Nodes, Rig profiles | **Radios** area | Inventory, not preferences. |
| Online terrain data | Stays (privacy choice), also prompted in context from the Estimate menu | — |
| Keep screen on | Automatic while recording in foreground, one preference | Off by default today: in a car mount the screen locks. |
| Pro | Top of Settings ("Mesh Analyzer Pro: Free / Active") | Today only reachable via About. |

After this, Settings holds Notifications, Units, Terrain privacy, Data, Pro and About.

### MEDIUM 9: Field ergonomics: no haptics, alerts can be silenced by Focus, screen can lock
**Where:** no `HapticFeedback` calls anywhere in `lib/`; `out_of_range_monitor.dart:218-225`; `main.dart:37`.

- Out-of-range / back-in-range produce a notification banner with sound but no haptic.
- The notification is not time-sensitive, so a Driving or Fitness Focus suppresses it.
- Keep-screen-on defaults to off. Targets are standard size (44 pt pill, 40 pt locate button, 12 pt chart chips).

**Fix:** distinct haptic per transition; optional audio cue mode (soft tick per base packet heard, Geiger-counter style) for driving; time-sensitive interruption level for range alerts; auto wake-lock while recording in foreground; 56 pt+ recording pill and Start/End buttons.

### MEDIUM 10: The same colours mean different things, and SNR thresholds ignore the preset
**Where:** `signal_legend.dart:20-23` (Strong/OK/Weak/Lost at SNR 10/0/−10/−20); coverage detail legend "SNR ≥ 10 / ≈ 0 / ≤ −15" (screenshot `05`); Pings legend green/yellow/red = replied/relayed/no reply (`04`).

- Two legends use different thresholds for the same metric. On Pings, yellow means "relayed" not "weak".
- SNR is only meaningful relative to the preset's demodulation floor (about −7.5 dB at SF7, −20 dB at SF12). "Red at −15" is marginal on Long Slow and impossible on Short Turbo. Since the headline feature is comparing presets, the colour scale should be normalised.

**Fix:** colour by link margin (SNR minus the preset floor). One legend everywhere: "Strong margin / Some margin / At the edge / Below floor". Raw SNR in the readout. Pings use shape plus colour: ● replied, ◐ relayed, ○ no reply. Pin the legend to the layers button.

### MEDIUM 11: Coverage map detail hides its best tools
**Where:** `coverage_map_detail_screen.dart:329-385`, `comparison_actions.dart:49-58`.

Estimated coverage, terrain-aware estimate, "Set base location…" and a disabled menu item used as a hint ("Long-press the map for a line-of-sight profile") sit in an overflow menu behind a terrain glyph. Two unlabeled app-bar icons (bookmarks, compare). Session tiles are one dense subtitle string.

**Fix:** a map-style **Layers** button on the map: Measured: Signal / Pings; Estimate: Off / Simple / Terrain-aware; Base: Set location. "Compare" as a text button in the sheet header next to the session list; saved comparisons as a section there. Two-line session rows ("18 min · 56 heard · 35/74 pings") with a mini sparkline. One-time coach mark for the long-press profile.

### MEDIUM 12: The IA has two meanings of "map", and radios have no home
**Where:** `app.dart:66-70` and the 3-tab bar.

"Live" is a map; "Coverage" is a list of maps. The radio pair is the core physical object yet is spread across the pill sheet, Settings → Radio Setup, Settings → Nodes, Settings → Rig profiles, and backups. "Where do I set up my radios?" requires knowing Settings is the answer. See §3.

### MEDIUM 13: Pro is legible but under-delivered and in the wrong places
**Where:** `pro_paywall_screen.dart:186-230`, `session_panel.dart:512-518`, `about_screen.dart:132-136`.

- Five of eight listed features are still "Coming soon" under a paid yearly plan.
- The only non-contextual entry point is buried in About.
- The one place a free user meets a lock is inside the Start-session form ("New rig (Pro)"), on the critical path.
- `ai_analysis_card.dart` sends a comparison digest to a backend; this conflicts with "data only leaves on CSV export" unless disclosed.

**Fix:** split the paywall into "Included now" and "On the roadmap" ("planned, no date"). Pro row at the top of Settings. Rig lock only on the Rigs screen. Disclose the AI analysis host on the card and in the privacy policy.

### LOW 14: Naming
- "Session": fine as a noun; the button verb should be **Record**.
- "Rig": ham slang newcomers don't know. Use **Antenna setup**.
- "Base / Mobile": good. Retire "Remote" and "node" in user text.
- "Range Test": a module name. Use **Base beacon** in the UI, keep "Range Test" in a help line.
- "Ping": fine; label the map layer "Base heard me".
- "Coverage map": good, but then the Live tab should be "Record", not another map name.
- "Air 1.1%": opaque. "Airtime 1.1%" with an info popover.

### LOW 15: The charts half-earn their place
**Where:** `signal_charts_panel.dart`; `02-live-charts.png`.

SNR and RSSI stacked with no reference line for the preset floor, so the chart can't answer "how close am I to losing it?". The panel covers the top half of the map. Time on the x-axis is less useful than distance from the base.

**Fix:** dashed "floor" line and shaded margin; x-axis toggle Time/Distance; tapping a sample highlights its dot; RSSI behind a toggle; keep the ping strip.

### LOW 16: Visual language
Material 3 on iOS (extended FAB, Material segmented buttons, Material dropdowns) reads as an Android port. Use iOS-style sheets with detents, inline menus, SF-style segmented controls. The chrome is dark but OSM tiles are bright beige; in sun the 0.85-alpha dots with a 1 pt black stroke wash out. Offer a high-contrast/dark basemap while recording, 2 pt white strokes, 9 pt dots.

---

## 3. Proposed information architecture

```
Tab 1  Record            (was Live)
  Full-bleed map: track, dots, ping rings, base pin + distance line, scale bar
  Top: radio pill (connection only) | HUD band while recording
  Bottom-right: [● Record] → start summary sheet → recording pill "● 12:04"
  Layers button: Signal/Pings, colour by margin/SNR/RSSI, relayed on/off, legend
  First-run checklist card (as now)
  End → Session summary sheet → "View on coverage map"

Tab 2  Maps              (was Coverage)
  List with thumbnail, base name, sessions count, last walked
  Map detail: map + Layers button (Measured / Estimate / Base location)
              sheet: sessions (select) → [Compare] ; saved comparisons ; export

Tab 3  Radios            (new)
  Base card + Mobile card (preset, channel ✓, last heard, battery)
  [Set up radios] wizard · [Change preset]
  Radio detail → Settings history (backups, filtered), Restore original, Rename
  Antenna setups (rigs, incl. antenna height) · Heard radios (nodes)

Settings (gear in Maps/Radios nav bar, or 4th tab)
  Mesh Analyzer Pro · Notifications & alerts (timeout, haptics, audio cue)
  Units · Recording (keep screen awake) · Terrain data (privacy) · Data · About
```

The main structural change is promoting **Radios** to a tab.

---

## 4. Patterns worth borrowing

1. **CellMapper: draw the station and the link.** Serving station pin, your pin, a line between them. ([CellMapper First Time Startup](https://www.cellmapper.net/First_Time_Startup/en))
2. **NetSpot: show the survey path and an explicit, adjustable scale.** ([NetSpot heatmaps](https://www.netspotapp.com/wifi-heat-map/wifi-heatmaps-with-netspot.html), [toggle path](https://www.netspotapp.com/help/toggle-path/), [Macworld](https://www.macworld.com/article/215476/netspot_helps_you_optimize_your_wi_fi_networks.html))
3. **Gaia GPS: lock-screen live tiles plus a prominent record state.** ([App Store](https://apps.apple.com/de/app/gaia-gps-mobile-trail-maps/id1201979492?l=en-GB))
4. **MeshMapper (MeshCore): one-tap start.** Connect, tap, drive. It auto-uploads to a community map, so "on-device, private channel" is the contrast to lead with. ([App Store](https://apps.apple.com/app/id6758073991))
5. **Meshtastic Range Test docs: fixed sender, mobile receiver, CSV into Google Earth.** Say "replaces the Range Test → CSV → Google Earth dance". ([docs](https://meshtastic.org/docs/configuration/module/range-test/))
6. **WiFiman: one big gauge, not a table.** ([Gigazine](https://www.gigazine.net/gsc_news/en/20251004-wifiman-wi-fi-mobile-bluetooth-analyze))
7. **Workout apps: audio/haptic cues and large-numeral pages** for use without looking.

---

**Top 5 to do first:**
1. Regenerate and recompose the store screenshots around the story, including a Live Activity shot.
2. Base pin, track line, live ping rings and a scale bar on the Live map.
3. Merge the pill badge, BaseStatusBar and readout into one large HUD band that shows staleness.
4. One-tap Start with an editable summary, plus an end-of-session summary.
5. Radios hub plus a 4-step wizard, with backups moved there and filtered per radio ("Restore original" pinned).
