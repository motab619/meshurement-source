# Visual identity: the app theme (2026-10-25)

Why: a Flutter app shipping stock Material 3 with Roboto looks like every
other Flutter app, including the MeshCore companion. This note is the
theming layer only (`lib/ui/theme/`); the screen redesigns from
`docs/critique-2026-10-17/design.md` (HUD band, one-tap Record, Radios
tab) sit on top of it later. Before/after screenshots:
`docs/design/theme-screens/`.

## Direction in one line

An instrument with a quiet 80s-arcade streak: warm paper-and-ink
neutrals, arcade-orange highlights with cyan as the foil, a cockpit
typeface with monospaced readouts and captions, flat panels with hairlines
instead of shadows, squared corners instead of pills. Retro in the
details (mono captions, lit orange on charcoal, boxy keys), never a
scanline or a glow.

## Accent colour

**Arcade orange `#FF6A13`** (`AppTheme.seed`), the node-ring colour of the
app icon, through `ColorScheme.fromSeed`. Andy's call (2026-10-25):
orange highlights, retro but not overly so. `fromSeed` alone washes the
dark primary out to peach, so the primaries are pinned:

| Token | Dark | Light |
|---|---|---|
| primary | `#FF7A1F` (lit orange) | `#B83E00` (burnt, 4.6:1 on paper) |
| primaryContainer (selected tab, FAB, chips) | `#6B2A00` | `#FFDBC8` |
| secondary (the 80s foil; also `status.info`) | `#2BD9E6` cyan | `#007C87` |

Known tension, accepted: the signal ramp (`SignalColorMapper`, untouched:
green `#27AE60` → amber `#F1C40F` → red `#C0392B`) passes through orange
between amber and red. Mitigation: the accent is a red-orange (hue 22°),
the ramp's "marginal" is yellow-amber (hue 48°), and chrome never draws
dots; dots only ever sit on map tiles with a stroke. The screenshots are
the check: a mid-ramp dot should never read as a button.

Rejected: Material blue / the old `#2E5090` (the default look, and
MeshCore's family), violet (Material 3's own default seed), green or olive
(collides with "good signal"), teal (clean, but not what Andy wants).

## Surfaces

`fromSeed` tints every surface with the seed. The theme overrides them
with the neutral set the charts already use (`ProfileChartColors`), so a
chart and the sheet around it are the same paper:

| Token | Dark | Light |
|---|---|---|
| surface (page) | `#141413` | `#F7F6F3` |
| surfaceContainerLow (cards, sheets) | `#1A1A19` | `#F0EFEC` |
| surfaceContainerHigh (dialogs, menus) | `#262625` | `#E2E0D9` |
| onSurface (ink) | `#F0EFEC` | `#1A1A19` |
| onSurfaceVariant (soft ink) | `#C3C2B7` | `#4A4943` |
| outlineVariant (hairline) | `#34342F` | `#D8D6CE` |

Rules: elevation 0 everywhere, a 1 px `outlineVariant` hairline where an
edge is needed (app bar bottom, nav bar top, cards, dialogs, map panels).
Bottom sheets: `surfaceContainerLow`, 16 px top radius; the draggable
sheets draw their own handle (the theme's is off so there is only one).
Cards: `surfaceContainerLow`, 12 px radius, hairline, no shadow.

Map overlays (`MapChrome` extension): the radio pill, base band, readout,
legend and layer toggles use a translucent tint of the same surface
(`overlay`), ink text (`onOverlay` / `onOverlayMuted`) and a hairline, in
place of `Colors.black87` with white text. In light mode they are paper over
the tiles; in dark mode charcoal.

## Typeface

**B612** (body) and **B612 Mono** (readouts), bundled in `assets/fonts/`.
SIL Open Font License 1.1, © 2012 The B612 Project Authors
(https://github.com/polarsys/b612), unmodified; added to `NOTICE` and the
in-app licence page. Designed by Airbus and Intactile Design for cockpit
displays: legible at small sizes, in glare, at arm's length, which is the
job here. It has only Regular and Bold (plus italics), so the text theme
asks for 400 and 700 only, and since it runs wider than Roboto the scale
sits one step down (body 15/13, labels 13/12/11, title 19/15/13).

Readouts (`ReadoutStyles` extension): measured values (SNR, RSSI, Air %,
seq, counts) use `readout.value` (B612 Mono 14 bold) or `readout.valueLarge`
(24 bold) with `readout.label` captions, so columns line up and digits do
not jump. Section labels (`SectionLabel`) are B612 Mono in orange with
1 px tracking: the arcade "HI-SCORE" caption, one size, no uppercase.

## Shapes and buttons

One radius family (`AppTheme.radius*`): 6 (chips), 8 (buttons, inputs,
segmented buttons, nav indicator, snack bar), 12 (cards, FAB, menus),
16 (sheets, dialogs). No `StadiumBorder` anywhere: Material's pills are
the biggest tell.

Buttons are 44 px keys: `FilledButton` for the one primary action on a
screen, `OutlinedButton` (1 px `outline`) for secondary, `TextButton` for
dialog actions and inline links. Destructive actions (End session, Delete,
Erase) are a `FilledButton` in `status.danger` / `status.onDanger`, never a
raw `Colors.red[800]`.

## Status colours (`StatusColors` extension)

The meaning colours, each with `on*` text and a quiet `*Container` pair for
bands and badges. `warning` and `danger` equal the chart tokens so chart
and caption agree.

| Role | Used for | Dark | Light |
|---|---|---|---|
| ok | hearing the base, connected, success | `#3DC46E` | `#1E8E4E` |
| warning | reconnecting, airtime high, faster than recommended, public channel | `#FAB219` | `#C98A00` |
| danger | base lost, errors, destructive buttons | `#E2473E` | `#C12B2B` |
| info | connecting / busy (= secondary) | `#2BD9E6` | `#007C87` |
| neutral | unknown / waiting band | `#3A3F42` | `#DCDBD5` |
| muted | "not set", hints, footnotes | `#9A988F` | `#6E6C65` |

Bands (`BaseStatusBar`) use the container pairs: `okContainer` /
`onOkContainer` and so on, so they sit on the page instead of shouting.
The signal ramp is not a status colour and stays in `SignalColorMapper`.

## Empty states

One pattern, `EmptyState` (`lib/ui/widgets/empty_state.dart`): a 72 px
hairlined tile with the section's icon in `primary`, a `titleMedium`
line, one `bodyMedium` sentence in soft ink saying what to do, and an
optional action. Centred, max 320 px wide. Replaces the grey icon + grey
text stacks.

## Light and dark

Both themes are built (`AppTheme.light()`, `AppTheme.dark()`) and the app
follows the system (`themeMode: ThemeMode.system`). Before this the app was
dark only. One line in `app.dart` pins it back to dark if the light theme
should wait.

## What the theme cannot express (left inline on purpose)

- Signal colours and the link-margin ramp (`SignalColorMapper`,
  `link_margin_color`): data, not chrome.
- Chart painters (`ProfileChartColors`, `signal_charts_panel.dart`,
  `range_polar_plot.dart`): they draw with a `Canvas` and keep their own
  token set, which matches the surfaces above; the series line is the
  theme's cyan secondary (was Material blue). The live charts panel is
  dark in both modes: it floats over the map tiles like the other
  overlays, and making its painter brightness-aware is a follow-up.
- B612 draws parentheses almost square, like brackets: "(+2.0 dB)" reads
  as "[+2.0 dB]". Part of the face's character; worth a look in the
  screenshots before committing to it.
- Map marker colours (my location, base pin, dot strokes) drawn by
  `flutter_map`.
- Layout paddings (`EdgeInsets`): spacing is per widget; the theme sets
  only the component defaults (list tile, buttons, dialogs).
