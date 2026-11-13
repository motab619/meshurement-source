# iPad and iPhone Duo layouts (plan, 2026-11-10)

Status: **agreed with Andy 2026-11-10**, being built on `claude/ipad-duo-4d5723`.

Decisions (Andy, 2026-11-10):
- iPhone in landscape keeps today's phone layout.
- iPad allows Split View / Stage Manager (no `UIRequiresFullScreen`).
- The mobile node's GPS (step 5) is **required before any iPad build goes to
  TestFlight**: this branch doesn't merge into `field-build-oct23` (which ships
  with every `fastlane beta`) until step 5 is done, or the device family change
  stays off until then.
- Breakpoints: start with 600 / 720 as named constants, then decide from
  simulator screenshots at the borderline sizes (iPad mini portrait 744, iPad 11"
  portrait 834, Split View halves) showing sheet vs side panel side by side.

## Where the app stands today

- `TARGETED_DEVICE_FAMILY = 1` (iPhone only) in every Runner and MeshActivity
  build configuration. On an iPad the App Store still offers it, and it runs in
  **iPhone compatibility mode** (a scaled iPhone-sized window, no Split View).
- `Info.plist`: portrait + both landscapes for iPhone, no `~ipad` list, no
  `UIRequiresFullScreen`. Already scene-based (`UIApplicationSceneManifest`), which
  the iOS 27 SDK requires.
- No screen adapts to width. The shell is a bottom `NavigationBar` (`app.dart`,
  `mainTabProvider`); Live is a full-screen map with the session panel as a modal
  bottom sheet (`map_screen.dart` `_showSessionPanel`); Coverage map detail is a map
  under a draggable results sheet (`coverage_map_detail_screen.dart`,
  `_sheetFraction`); charts open over the top half of the Live map; Settings,
  Node Setup, guided test and the Field Report sheet are single phone columns that
  stretch edge to edge on a wide window. A few overlays size themselves from
  `MediaQuery.sizeOf(context).width * 0.46` and similar; those are fine.

## iPhone Duo: what we know (third-party sources, not yet tried)

- Apple publishes only screenshot pixel sizes: outer 1398 × 2034, inner
  2007 × 2853 (both orientations). Point sizes (outer ≈ 466 × 678, inner ≈ 669 × 951
  at 3x) are inferred by developers, not from Apple.
- The Duo is an iPhone: no iPad device family needed. An iPhone-only app runs on
  the unfolded screen at "a familiar size"; built with the iOS 27 SDK it grows a
  little; **built with the iOS 27.1 SDK it fills the inner screen**. This Mac has
  Xcode 27.0 (SDK 27.0), so the full-screen Duo layout needs Xcode 27.1.
- Fold/unfold just resizes the window (one discrete size change). Flutter sees
  that as a new `MediaQuery` size and rebuilds; no fold/hinge API is needed for
  our layouts. The Duo also gets Split View, so widths in between happen too.
- Xcode 27.0 here has **no Duo simulator**; fastlane 2.241 as installed has **no
  Duo screenshot type** in `deliver` (despite what we heard). Duo screenshots are
  required from April 2027 for apps built with the 27.1 SDK; until fastlane adds
  the type they would be uploaded by hand in App Store Connect.

## The rule: layout follows the window, not the device

One helper, `lib/ui/layout/window_class.dart`:

- **compact**: anything else. Today's phone layout, unchanged pixel for pixel.
- **wide**: width ≥ 600 pt **and** height ≥ 480 pt. iPads held upright (mini,
  10.5", 11"), large Split View panes, the Duo unfolded upright. The height test
  keeps an iPhone turned sideways (≈ 440 pt tall) on the phone layout it has
  today, and iPad Slide Over / ⅓ Split View (≈ 320–375 wide) stays compact.
  Settings-like screens centre at 640; the Live map docks the session panel
  **under** the map, full width (the floating 640 sheet on Andy's iPad Pro 10.5,
  2026-11-10, covered half the map and left the map buttons sticking out).
- **side panel**: wide and width ≥ 860 pt (iPad 13" upright, any iPad sideways,
  the Duo unfolded sideways): the session panel and Coverage results sit beside
  the map. 720 was tried first: iPad mini (744) overflowed the Live map and the
  iPad Pro 10.5 (834) left Coverage ~330 pt of map.
- **Tab bar: the bottom bar on every size.** A NavigationRail on wide windows was
  built and dropped the same day (Andy: "a terrible use of real estate" on an
  upright iPad).

Everything reads `MediaQuery.sizeOf`, so Android tablets and foldables get the
same layouts for free.

## Screens

| Screen | Wide layout |
| --- | --- |
| Shell (`app.dart`) | Bottom tab bar as on the phone (a rail was tried and dropped). |
| Live map | Map fills the rest. From 860 pt across (`WindowClass.liveDockMinWidth`; iPad mini portrait at 744 overflowed the base pill and squeezed the banners, simulator 2026-11-10): the session panel docks in a 380 pt column on the right instead of a modal sheet (Session button toggles it, ✕ closes it; the map keeps its camera). Charts still open over the map's top half (on an iPad that leaves plenty of map). Without: today's sheet, capped at 640 pt wide (Material 3 default). |
| Coverage list | Cards in a centred column, max 720 pt (two columns later if it looks empty). |
| Coverage map detail | With a side panel: map left, results (sessions, stats, layer chip) in a 400 pt column on the right instead of the draggable sheet. |
| Compare / charts | Content capped at 900 pt; the polar plot and range section side by side when there is room. |
| Settings, Node Setup, backups, About, paywall, privacy | Centred column, max 640 pt. No other change. |
| Guided test (ask, plan, run, result) | Centred column, max 640 pt; run step map gets the extra height. |
| Field Report sheet | For now the bottom sheet at 640 pt (Material 3 cap); a two-pane version only if the iPad screenshots show it's needed. Card images unchanged. |
| Modal sheets and dialogs | Max 640 pt wide (Material 3 default for sheets; check each). |

Stays phone-only / unchanged: the Field Report card pixels, onboarding pages
(centred, otherwise same), Live Activity.

## Orientation and Info.plist

- Runner `TARGETED_DEVICE_FAMILY = "1,2"`. MeshActivity to `"1,2"` as well so the
  archive validates (it simply never shows on iPad); confirm with an archive.
- Add `UISupportedInterfaceOrientations~ipad`: all four orientations. Apple wants
  all four for an app that takes part in Split View / Stage Manager; we do **not**
  set `UIRequiresFullScreen` (a field app next to Maps or Notes is useful).
- iPhone list stays as it is.

## App Store and screenshots

- Once iPad is in the device family, App Review needs **iPad 13" screenshots**
  (2064 × 2752). Add `"iPad Pro 13-inch (M5)"` to `ios/fastlane/Snapfile`;
  `ScreenshotTests.swift` runs unchanged (demo mode picks the screen), maybe with
  longer waits for tiles on the bigger map.
- Duo screenshots: by hand until fastlane supports them; not required before
  April 2027.
- Store copy ("iPhone" mentions) is the beta-site agent's.

## Risks and gaps

- **GPS on iPad**: Wi-Fi-only iPads have no GPS; outdoors their location is
  coarse or missing. Until step 5 (the node's GPS) lands, coverage walks need a
  cellular iPad (or the Duo). Worth a line in the store text / support page, and
  the app should keep its usual "no GPS fix" handling.
- BLE, background location and notifications behave the same on iPad.
- **Live Activity is iPhone-only**: on iPad `areActivitiesEnabled` is false, so
  today the session panel would say "Live Activity is off … turn it on in
  Settings", which is wrong. Report `unsupported` on iPad (`userInterfaceIdiom`
  in `LiveActivityBridge.swift`) and say nothing. Paywall line "Live Activity on
  iOS" becomes "on iPhone".
- **Share sheets on iPad need an anchor**: `guided/result_screen.dart`
  `Share.share` has no `sharePositionOrigin` (the others do); on iPad that can
  fail or crash. Fix with the rest.
- Duo: untested until there is a simulator (Xcode 27.1) or a device. Widget tests
  at 466 × 678 and 669 × 951 stand in.
- iPad mini portrait (744): Coverage map detail docks its results fine; the Live
  map did not (≈ 290 pt of map, overflow), hence its own 860 pt breakpoint.
- Landscape and Split View widths are covered by widget tests only: the
  simulator panel's rotate needs Andy's OK and this Mac has no Simulator app.

## Tests and checks

- Widget tests per changed screen at phone (390 × 844), phone landscape
  (844 × 390), Duo outer (466 × 678), Duo inner (669 × 951), iPad mini (744 × 1133)
  and iPad 13" landscape (1376 × 1032): the right shell (bar vs rail), panel vs
  sheet, no overflow.
- Phone stays pixel-identical: a golden of the shell and Live/Coverage at 390 × 844
  taken before the change, compared after.
- Simulator: iPad Pro 13-inch (M5) and iPad mini in demo mode
  (`-MeshDemo -demoScreen map|charts|session|coverage|pings|radio|settings|report`),
  portrait, landscape and a Split View width.

## What was built (2026-11-10)

- `lib/ui/layout/window_class.dart`: `WindowClass` (`compact` / `wide` /
  `sidePanel`, constants `wideMinWidth` 600, `wideMinHeight` 480,
  `sidePanelMinWidth` 860, `columnMaxWidth` 640) and `WideColumn`.
- `lib/ui/layout/app_nav_shell.dart`: `AppNavShell`, the bottom bar at every size.
- Live map (`_withDockedPanel`, `SessionPanel(onClose:)` = docked) and Coverage
  map detail (`coverage-results-docked`, the map stack under a `GlobalKey`).
- `WideColumn` on Settings, Node Setup, Coverage list, Nodes, backups, About,
  paywall, privacy, Change the base, rig profiles, Compare (900), guided ask /
  plan / run / result, welcome flow.
- `LiveActivityService.deviceSupported` (native `supported`: iPhone with iOS
  16.2+); on iPad no Live Activity line, no paywall row.
- Tests: `test/layout/` (sizes in `window_sizes.dart`).

## Order of work

1. `WindowClass` helper + shell rail + Info.plist / device family + Live Activity
   and share-anchor fixes.
2. Live map side panel; Coverage map detail side panel.
3. Centred columns (Settings, Node Setup, guided, About, paywall); Field Report
   sheet two-pane; Compare.
4. Tests, simulator screenshots, Snapfile iPad device.
5. **The mobile node's GPS as the location source** (Andy, 2026-11-10: required
   before any iPad build goes to TestFlight), so a Wi-Fi-only iPad can record.

   Firmware findings (read 2026-11-10):
   - **Meshtastic 2.8.1** (`PositionModule::sendOurPositionToPhone`,
     v2.8.1.8e6a88d): the node hands the phone its own position every 60 s
     (`sendToPhoneIntervalMs`, a constant), full precision, **never on air**. The
     node's own fix only refreshes every `position.gps_update_interval`
     (default 120 s), so without a change the phone sees a new place every
     2 minutes. A position request to our own node is throttled to one per
     3 minutes, and a "nodes only" config re-read (`want_config_id` 69421) would
     hold back packets while it streams, so neither is used.
   - **Meshtastic 2.7.26** has no phone-only path: the phone only sees its own
     position when the node broadcasts it. Node Setup already sets the test
     channel's `position_precision` to 32 (full), so a GPS mobile does
     broadcast on MeshTest at the firmware's normal (slow) interval; this step
     adds no traffic and doesn't speed that up.
   - **MeshCore 1.18** (`CMD_SEND_TELEMETRY_REQ` with exactly 4 bytes, "self"):
     answered at once over Bluetooth with Cayenne LPP including the GPS
     (0.0001° ≈ 11 m), nothing on air. A T1000-E updates it every second, but
     only while its GPS is switched on (custom var `gps`, **off by default**).
     No fix quality is reported; a lost fix keeps the last position.

   Built (2026-11-10): `MeshRadio.ownFixes` / `lastOwnFix` (`NodeFix` in
   `radio_types.dart`); Meshtastic from our own NodeInfo / POSITION_APP
   (`ownFixFromNodeInfo`); MeshCore polls the self telemetry every 5 s (60 s
   once it answers without GPS; `meshcore_lpp.dart`, commander `post()`).
   `GpsService.addNodeFix` (wired in `app.dart`): the phone wins with a fix
   within 30 m (its age says nothing: the stream only reports after 5 m of
   movement); otherwise a node fix under 2 minutes old is the position, the
   state says `GpsSource.node` and the session panel "GPS: from your node ±N m".

   Node Setup (Andy, 2026-11-10: on by default): for the **mobile** only,
   Meshtastic gets `position.gps_mode` ENABLED (if DISABLED) and
   `gps_update_interval` 30 s (`mobileGpsConfig`; skipped for no GPS chip, a
   fixed position, or already ≤ 30 s), written in the same edit transaction;
   smart broadcasts stay capped at one per 5 min, so nothing more goes on air.
   MeshCore gets custom var `gps:1` where the board has it (GET/SET_CUSTOM_VARS,
   `MeshCoreRadio.readCustomVars`). Backups keep the old values
   (`MeshtasticBackup.position`, `MeshCoreSettings.gps`) and Restore writes them
   back; the restore diff shows a "GPS" line. The confirm dialog says so.

   **Firmware 2.7 too** (2026-11-10: 2.8 is still alpha, 2.7.26 is the
   stable release testers have): on firmware before 2.8 with the node's GPS
   on, `MeshtasticRadio` re-reads the node list every 30 s
   (`want_config_id` 69421, "nodes only"; our own NodeInfo comes first with
   the GPS's latest fix), Bluetooth only. Packets wait in the node's queue for
   the second or so it takes. Only while `ownFixesWanted` (GpsService: the
   phone has no fix within 30 m), which also gates the MeshCore polling, so
   an iPhone with its own GPS costs nothing.

   Still to do: a walk with a T1000-E and a Wi-Fi iPad (or the phone with
   Location off), Meshtastic 2.8.1 and MeshCore. Not tried on hardware yet.
