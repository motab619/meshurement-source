# UX / copy / accessibility audit (pre-beta)

## Summary
- Core flow works, but a first-run user is never told the order: connect radio, Radio Setup (Settings tab, buried), create map (needs a connected radio), start session. No onboarding, and empty states do not point to Radio Setup.
- Two likely-embarrassing defects: the Pro paywall lists "null Coming soon." for Hardware profiles, and every Pro feature is "Coming soon" while a $4.99/yr subscription is on sale.
- Copy leaks developer terms and raw exception text (`Bad state: ...`, `Failed: $e`, MEDIUM_FAST, "base node", "modem preset", "NodeInfo", hex ids).
- Signal colour (green/yellow/red) is the only encoding on the live map and there is no legend on the Live tab; no Semantics on the tappable signal readout.
- App is dark-only (theme: dark ColorScheme, no darkTheme/themeMode, so light mode is effectively never shown; acceptable). Text scale is not overridden (good) but several fixed-width rows will break at large Dynamic Type.

## Findings

### [HIGH] Paywall shows "null Coming soon." and sells only unreleased features
**Where** lib/ui/screens/pro_paywall_screen.dart:180-210 (`_blurbs`, `_FeatureList`); enum in lib/services/pro_entitlement.dart:27-37.
**What** `_blurbs` has no entry for `ProFeature.rigProfiles`, so that row renders `'${_blurbs[f]} Coming soon.'` = "null Coming soon." Also Rig profiles (gated, exists) and Rig comparison (exists, seen in Compare screen) are labelled "Coming soon" with a schedule icon. The whole list says "Coming soon" next to a purchasable yearly plan and "Pro adds the extras listed below as they ship." Testers will be confused; Apple review commonly rejects subscriptions whose advertised benefits are not delivered.
**Fix** Add a blurb for rigProfiles ("Save radio, antenna and cable setups to compare hardware."). Split the list into "Included now" (rig profiles, rig comparison, with a check icon) and "Planned" (others). Reword intro: "Mesh Analyzer is free for mapping, pings, charts, coverage layers and export. Pro adds hardware comparison tools; more are planned." Consider hiding the purchase card in the beta if nothing planned is shipping.

### [HIGH] No first-run guidance; core flow order is undiscoverable
**Where** lib/ui/screens/map_screen.dart (Live tab), coverage_map_list_screen.dart:21-40, session_panel.dart:_startForm, settings_screen.dart.
**What** Fresh install: Live shows a blank map, red pill "Connect radio" and a "Connect" FAB, plus a "Session" FAB. Nothing says a radio must first be set up (Settings -> Radio Setup, a tab away) to leave the public channel, and that the session refuses on the public channel. Coverage tab empty state: "Create a map and assign a base node to start." (jargon, and the + button opens a dialog that says "No nodes known yet. Connect to your radio first..." with no Connect button). Session panel when disconnected says "Connect to your radio first (tap Connect on the banner)" (there is a pill and a FAB; "banner" is not a term the user sees). A tester can also reach "Your radio is on the public channel" only after connecting.
**Fix** Add a 4-step checklist empty state on the Live tab (or a dismissible first-run card): 1 Connect your radio, 2 Run Radio Setup (both radios), 3 Create a coverage map, 4 Start a session and walk. Make each step a button (Connect / Open Radio Setup / New map). Coverage empty state: "No coverage maps yet. A map groups your walks around one fixed radio (the base). Connect your radio, then tap + to create one." Add a "Connect radio" button inside the create-map dialog's no-nodes message. Add a "Set up your radios" tile at the top of Settings until completed.

### [HIGH] Raw exception text shown to users
**Where** session_panel.dart:~378 `'Could not start session: $e'`; settings_screen.dart:429 `'Failed: $e'`; radio_setup_screen.dart:154,219 (`'Scan failed: $e'`, `'Failed: $e'`); radio_backups_section.dart (`'Could not back up: $e'`, `'Restore failed: $e'`, `'Share failed: $e'`); region_dialog.dart:62; coverage_map_detail_screen.dart:829 (`'Export failed: $e'`); terrain_profile_sheet.dart:132; connection_banner.dart `_connectHelp` ("Details: $text", 'Scan failed: $e'); list screens `'Error: $e'`.
**What** Dart exceptions stringify as "Bad state: Radio is on the public channel — run Settings → ...", "Bad state: Radio not ready", "Radio rejected setting: NOT_AUTHORIZED", "TimeoutException after 0:00:30...", "Exception: Location permission denied". A non-developer sees these (most common: starting a session while the link just dropped).
**Fix** Add one `friendlyError(Object e)` helper: strip "Bad state: "/"Exception: " prefixes, map TimeoutException to "The radio didn't respond. Check it's on and nearby, then try again.", map "Radio not ready/not connected" to "Your radio isn't connected yet." Show details only behind a "Copy details" action. Replace "Failed: $e" with an action-specific sentence ("Couldn't set up the radio.").

### [MEDIUM] Developer jargon and enum leaks (copy table)
| Where | Current | Proposed |
|---|---|---|
| session_panel.dart active session; radio_setup_screen.dart "Connected" block; connection_banner `_RadioSheet`; map detail session tile; node chips | `Preset: MEDIUM_FAST` / `MEDIUM_FAST` in session subtitle (raw `loraPreset` id; elsewhere "Medium Fast") | `Preset: Medium Fast` everywhere (use displayName) |
| coverage_map_list_screen.dart:34 | "Create a map and assign a base node to start." | "Tap + to create your first coverage map." |
| create_map_dialog.dart | "Base node (the fixed node you measure against)", "No nodes known yet. Connect to your radio first so its node list can be used to pick the base node." | "Base radio (the one that stays put)", "No radios known yet. Connect to your radio first so you can pick your base." |
| session_panel.dart | "Ping base node", "Pinging base node every 15 s", "Sends a DM every 15 s and records whether it was acknowledged" | "Ping the base", "Pinging the base every 15 s", "Sends a small test message every 15 s and records whether the base replied" |
| session_panel / signal_display | "SNR", "RSSI", "Hops: 0 (direct)", "Dir: RX" with no explanation; Settings "Color Metric: SNR (dB)" | Add info affordance/help sheet: "SNR: how clearly the signal stands out from noise (higher is better). RSSI: raw signal strength (closer to 0 is stronger)." Show "Dir: Received". |
| radio_setup_screen.dart | "Modem preset", "Base Range Test beacon", "Name the radios BASE and MOBL", "Preset: ..." | "Range preset (speed vs. distance)", "Base test beacon: how often the base sends a test signal", "Name the radios BASE and MOBL on their screens" |
| radio_setup_screen.dart `_confirm` | "replaces ALL channels ... sets the modem preset, then reboots it." | Keep warning, say "restarts it"; lead with consequence in bold; "Backups…" first button is confusing - label "View backups" |
| radio_setup_screen.dart `_presetLabel` | "Long Slow (deprecated in 2.7)", "Long Fast (Meshtastic default)" | "Long Slow (longest range, slowest; being retired)", "Long Fast (default)" |
| session_radios.dart / radio sheet / banner | `!b8f4`, `Node: !a1b2c3d4`, node list `0x1a2b...` hex ids | Show names; put ids in secondary "ID" line only when no name |
| connection_banner `_RadioSheet` | "Preset: ... · Region: ?" "(unnamed)" | "Range preset", "Region: not set" |
| connect dialog | "Connect to Node", "Scanning for Meshtastic devices...", "RSSI: -62 dBm" | "Connect to a radio", "Looking for radios…", "Signal strength: strong/medium/weak" (or hide dBm) ; use real ellipsis character consistently ("..." vs "…") |
| map pill | "base ✓ / base lost / base ? / base …" | "Base in range / Base lost / Base unknown / Checking base…" (the ✓ and ? are unclear and read poorly in VoiceOver) |
| settings_screen.dart | "Out-of-Range Timeout: 2 min without hearing the base → alert" | "Alert me after 2 min with no signal from the base" |
| settings `_directionLabel` | "Rx only (Base→Remote signal)" uses "Remote" | "Received only (base to you)"; "Sent only (you to base)". Remove "Remote". |
| map detail | "Signal (base → you)", "Pings (you → base)" (arrows in segmented labels, wraps at large text) | "Signal from base", "Pings to base" |
| map detail session tile | "56 rx", "SNR -21.0…11.3 (median 1.5)", "pings 35/74 ok (39 no reply)", failure reasons come from raw Routing_Error names (e.g. "NO_RESPONSE", "PKI_UNKNOWN_PUBKEY") | "56 packets received", "Signal quality (SNR) -21 to 11 dB, typical 1.5", "Pings answered: 35 of 74"; translate NAK reasons to plain words |
| map detail legend | 'throttled' lowercase, "small dot = relayed", "No reply / rejected" | "Held back by radio", "Small dot: passed through another radio", "No reply or refused" |
| radio_backups_section.dart | "Each radio's name, channels, LoRa and Range Test settings..." / "Copy link" / "Channel link ... includes the channel keys" | "Your radios' names, channels and test settings are saved automatically..." ; "Copy channel link" |
| settings_screen.dart | "Clear nodes list ... Make your radio forget the other nodes it has heard" ; "Nodes: Radios the app has heard; give one a nickname" | OK wording but "Nodes" vs "Radios" is inconsistent: pick "Radios" for user-facing text. |
| about / connection help | "close the Meshtastic app", "no screen: 123456" | fine factually; add "Settings → Bluetooth → Forget" path in plain steps |

### [MEDIUM] Terminology inconsistency
**Where** across ui.
**What** radio / node / device / rig / base / base node / remote / mobile / "you" are mixed. Examples: "Connect to Node" vs "Connect radio" vs "Connect to your radio"; "Coverage Maps" (title) vs "Coverage map" vs "map"; "Session" FAB vs "Session Controls" vs "Start Session"; "Rig" (Rig profiles, Mobile rig) vs "Hardware" section vs "Hardware profiles" (paywall) vs "radio setup"; "Remote" appears once in Settings. "Rig" is not understood by non-hobbyists.
**Fix** Glossary: radio (device), base / mobile (roles), coverage map, session. Replace "node" in user text, "Remote" -> "mobile", "Hardware profiles"/"Rig profiles" -> one name (suggest "Setups": radio + antenna + cable). Rename FAB "Session" -> "Record" or "Start session" (it opens controls, and shows a record icon even when idle).

### [MEDIUM] Capitalisation inconsistency
**Where** various.
**What** Title Case: "Coverage Maps", "New Coverage Map", "Map Name", "Keep Screen On", "Signal Direction", "Color Metric", "Base Antenna Height", "Ping Interval", "Out-of-Range Timeout", "End Session", "Start Session", "Range Test Detected", "Log Packets", "Set Node Label", "Delete Map?", "Restore Purchases", "Connect to Node". Sentence case: "Rig profiles", "Radio Setup" (Title), "Clear nodes list", "Delete all sessions and maps", "Erase all app data", "Faster than recommended", "Back up ... now", "Set up this radio as base". Also US/UK mix: "Color Metric" vs "RSSI colours" vs "Metres above ground".
**Fix** Choose iOS-style sentence case for all titles, buttons, labels; one spelling (US: "color", "meters") since beta is US region. Fix "Metres" -> "Meters" (settings_screen.dart:~238; terrain sheet).

### [MEDIUM] End Session has no confirmation; Delete map swipes lose data silently
**Where** session_panel.dart `_endSession`; coverage_map_list_screen.dart delete.
**What** One tap on a big red "End Session" ends and (per design) stops pinging; accidental tap in the field is easy while walking. Delete map has a dialog but says "Delete "X" and all its sessions?" without counts and offers no undo; the trailing popup is a 3-dot menu with a single "Delete" item (no tooltip).
**Fix** Confirm End Session ("End session? You can't resume it. N packets recorded.") or add a 3-second undo snackbar. Delete map dialog: include session/packet counts and "Export CSV first" hint like Settings does; add tooltip "More" to PopupMenuButton.

### [MEDIUM] Colour-only signal encoding, no legend on Live tab
**Where** map_screen.dart `_dot`; signal_color_mapper.dart; coverage_map_detail_screen.dart `_Legend`.
**What** Dots go red→yellow→green (C0392B / F1C40F / 27AE60): problematic for red-green colour blindness (red vs green are close in luminance); relayed vs direct uses size only, and the only legend lives in the detail screen, not on Live. The live readout border/number colours are also colour-only. Screenshots show orange/olive/green dots difficult to tell apart.
**Fix** Use a colour-blind-safe ramp (e.g. viridis-like or blue→yellow) or add a setting; show a compact legend on the Live map when a session records; keep numeric SNR visible; add a tap-on-dot label. Add Semantics label to the readout.

### [MEDIUM] Accessibility: tappable readout and several controls lack semantics / small targets
**Where** map_screen.dart (GestureDetector wrapping `SignalDisplay`), connection_banner.dart pill, coverage list `FloatingActionButton` (+), node_list edit icon, `PopupMenuButton` in list.
**What** (a) Signal readout opens charts via GestureDetector with no label/button role: VoiceOver cannot discover charts. (b) Status pill height ~ 10+13pt text+10 = about 38pt (< 44pt). (c) "+" FAB on Coverage has no tooltip ("Add"). (d) Node list edit IconButton has no tooltip. (e) Pill status dot is colour-only (green/red/blue/amber) though text accompanies it (OK when connected, but "Reconnecting" and "connecting" states show only a progress label).
**Fix** Wrap in `Semantics(button: true, label: 'Signal readout, tap for charts')`/use InkWell; `ConstrainedBox(minHeight: 44)` on pill; tooltips "New coverage map", "Edit label", "More options"; `Semantics(liveRegion: true)` for the status pill.

### [MEDIUM] Contrast of low-emphasis text
**Where** signal_display.dart (white38 source name 10pt, white54 labels), radio_setup etc. (Colors.grey 12pt), amber/orange warnings, 10–11pt legend text.
**What** Computed WCAG ratios: AppColors.accent FF6A13 on 121212 = 6.5:1 (OK). Colors.grey (9E9E9E) on 121212 = 7.0:1 (OK). Colors.red text (errors) on 121212 about 5.0:1 (OK) but on the lighter dialog surface about 4.2:1 (borderline, 12pt). white38 on black87 overlay over map tiles about 2.6:1 (FAIL; 10pt "Polo Field Base" source name, 'Waiting for signal…' uses white54 about 4.7:1 marginal at 12pt). Fixed fontSizes of 10-11 are below iOS minimum guidance.
**Fix** Raise to white70 min for all overlay text, min 12pt; make error text use `colorScheme.error` rather than Colors.red.

### [MEDIUM] Dynamic Type: fixed-size rows will overflow/wrap badly
**Where** settings_screen.dart (ListTile with `SegmentedButton` trailing: "Signal Direction", "Color Metric"; `SizedBox(width: 200)` sliders in trailing), radio_setup_screen.dart (SegmentedButton "Mobile (I carry it)" / "Base (stays put)"), coverage_map_detail_screen.dart (segmented "Signal (base → you)"), connection_banner.dart pill (fontSize 13 hard-coded, role text outside Flexible), signal_display.dart overlays.
**What** No `textScaler` clamp or override anywhere (good, system size respected), but at XL+ sizes trailing SegmentedButtons in ListTile squeeze the title/subtitle to 1-2 characters wide, 200 pt sliders leave little room, and pill content overflows ("Row" with non-flexible role text and range badge).
**Fix** Move segmented controls and sliders below the title (use Column layout, not trailing); Make `Text(' · role')` and badge part of a `Wrap`. Test at accessibility XXL.

### [MEDIUM] Connect dialog: dismissable mid-connect, fixed height, small text
**Where** connection_banner.dart `_ScanDialog` (SizedBox height: 300).
**What** Tapping outside during connecting closes the dialog while connection continues (no visible progress other than the pill); scanning error in 12pt red; fixed 300pt content height clips the progress view + hint + error at large text or in landscape. "Cancel" does not cancel an in-flight connection.
**Fix** `barrierDismissible: false` while `_connecting`; make Cancel call disconnect when connecting; use a scrollable content with min/max constraints.

### [MEDIUM] Radio Setup is the hardest screen and is under-guided
**Where** radio_setup_screen.dart.
**What** Requires understanding two radios and roles; the "step 2" text depends on role selection; success string "Base radio set up and rebooting. Now apply the same preset to this radio (step 2)." scrolls off; "Put both radios side by side while applying." is tiny grey 12pt; Apply has a dialog (good) but the sheet text is long. Log lines "• Backing up current settings…" are fine. Region row: "United States, Canada, Mexico (915 MHz)" wraps with "Change" (see radio.png).
**Fix** Add a short intro at top ("You need two radios: one stays put (base) and one you carry (mobile). This sets both to a private channel."), a progress indicator "Step 1 of 2" and keep success/error banner pinned (SnackBar or card with icon), enlarge the grey hints to 13-14pt.

### [LOW] Status messages use bare coloured text, not a consistent component
**Where** radio_setup_screen.dart (green/red Text), session_panel.dart (orange), settings (amber), connection_banner sheet (amber 12pt).
**What** Warnings/errors/success are plain coloured Text with differing colours (orange vs amber vs Colors.red vs green) and no icon; colour is the only differentiator.
**Fix** One `StatusMessage(kind, text)` widget with icon + theme colours.

### [LOW] Dates and units
**Where** coverage_map_list_screen.dart:41 `map.createdAt.toLocal().toString().substring(0,16)` ("2026-10-16 11:21"); comparison_actions.dart "Saved 2026-..."; radio_backups_section `_date` ("10/16/2026 11:21", 24h, US order hard-coded); session panel "Started: 11:02"; node list "5m ago".
**What** Three date formats, ISO-like strings shown raw, hard-coded US order, 24h clock regardless of locale. Distances and heights are metric only ("Metres above ground", "km²", "75 m") with no imperial option (US beta testers).
**Fix** Use `intl` DateFormat (already a dependency via about screen) with a shared helper; add a metric/imperial setting or at least show ft in parentheses.

### [LOW] Misc copy and polish
| Where | Current | Proposed |
|---|---|---|
| connection_banner.dart `_ScanDialog` | "No Meshtastic devices found. Tap Rescan to try again." | "No radios found. Make sure yours is on and nearby, then tap Rescan." |
| connection_banner.dart `_confirmBase` | buttons "Use it anyway" (left) / "Pick the mobile" (primary) | Fine; consider "Connect anyway" |
| range_test_dialog.dart | "Range Test Detected / Range Test beacon detected from 0x1a2b... Log these packets for signal mapping?" | "Test signal detected: <name> is sending range-test signals. Record them for mapping?" ; buttons "Ignore"/"Record"; hex fallback -> "an unnamed radio" |
| session_panel.dart | "Radio not connected — nothing is being recorded until it reconnects." | good; use consistent dash style (em dash vs "-" in 'Empire Polo – Medium Fast') |
| map detail | "Long-press the map for a\nline-of-sight profile" hard-coded newline in menu item (disabled item looks like an item) ; "Where is the base?" dialog ; "Set the base location to use terrain / Menu (top right) → Set base location" | Move the hint to a tooltip/inline text; ellipsis "…" in menu labels consistent |
| node_list_screen.dart | "Connect to your Meshtastic node and nearby nodes will appear here." | "Connect to your radio and the radios it hears will appear here." |
| pro_paywall_screen.dart | "Restore Purchases", "Privacy Policy" etc. Title Case | sentence case; privacyPolicyUrl points to beta.plateaunerd.com (confirm it is live before public beta) |
| settings_screen.dart | Section "Hardware" with only "Rig profiles"; "Radios" has "Nodes" | Fold into Radios section |
| about_screen.dart | muted 12pt disclaimer text | OK; ensure contrast |
| rig_comparison_screen.dart | "A better -6 dB", "B better by 3 dB or more", "Median B - A (RSSI)" | Explain A/B with the labels (sessions' names) rather than letters; add "what does this mean" line |

## Screenshots reviewed
(Simulator, demo mode, iPhone 18 Pro Max, dark. Files in /private/tmp/claude-501/-Users-andybrunker-develop-mesh-analyzer/13132be7-c894-490b-a160-aef9add37105/scratchpad/audit/shots/)
- map.png: Live tab, connected pill "Meshtastic_e4ea · base ✓" with green dot, readout card top right (SNR/RSSI/Hops/Dir/Air), dots orange/olive/green, "Session" FAB. No legend; dot colours hard to distinguish; readout looks fine but tiny source name is dim.
- session.png: Session Controls sheet; raw "Preset: MEDIUM_FAST", "Pinging base node every 15 s"; plain text stack with no grouping/cards, long.
- radio.png: Radio Setup; raw "Preset: MEDIUM_FAST" next to "Modem preset: Medium Fast"; region line wraps; reasonable layout otherwise.
- coverage.png: map detail; tiles blank grey in simulator (offline) so not a bug per se; legend OK; session tile subtitle very long and jargon heavy ("56 rx", "pings 35/74 ok (39 no reply)"), the "Estimated" chip alone; segmented labels with arrows.
- charts.png, pings.png, estimated.png, profile.png, compare.png: captured but not individually reviewed (time budget); code reviewed instead. Light mode not checked in simulator because the app is dark-only by construction.

## Checked, OK
- Theme is dark-only via a single dark ColorScheme; consistent with scaffold 121212; no light/dark mismatch risk.
- Accent AppColors.accent contrast 6.5:1 and Colors.grey hint text 7.0:1 on 121212 (computed).
- Destructive Settings actions (Clear nodes list, Delete all sessions and maps, Erase all app data) have clear confirm dialogs with consequences, red confirm button, "can't be undone", export hint, and are blocked during a session.
- Radio Setup Apply and Restore backup are confirmed and explain the radio will restart; region dialog is non-dismissible while saving.
- Public-channel guard has a clear message and an "Open Radio Setup" button.
- Base-radio mix-up dialog on connect is clear.
- Several icon buttons already have tooltips (Close charts, Export CSV, Compare, Saved comparisons, Delete backup).
- No custom text scaling or textScaleFactor clamp; system text size is respected.
- Back navigation uses standard push routes; no custom WillPopScope traps seen; loading indicators exist for lists and connect progress.
- Connect progress view gives step, elapsed time and hints (good).
