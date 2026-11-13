# Field Report styles (design note, 2026-11-09)

Andy, 2026-11-09: one card look will not suit everyone. The single-session Field Report gets a **Style** choice in the share sheet. Every style shows the same numbers under the same privacy rules (`README.md`); only layout, palette and how much is shown change.

## Decided

- **Five styles**, each with its own layout for feed, story and wide (a re-layout, not a recolour):

| Style | Look | Shows |
|---|---|---|
| Night | Today's dark card (default, unchanged) | Everything |
| Basic | Light, minimal, prints well | Less: headline, route, four stats, one margin bar |
| Pop | Pastel, bubbles and pills | Everything |
| Bridge | Generic sci-fi starship console | Everything |
| Mission | 1960s technical-report page | Everything |

- **Bridge is not LCARS.** No curved elbow frames, no peach/lavender palette, no Star Trek words, insignia or font imitation.
- **Mission is not NASA.** No agency or mission names, no logo lookalikes.
- Fonts: B612 / B612Mono, plus two added 2026-11-09 (Andy): Courier Prime for Mission's typed text and Fredoka (variable, weight set on the wght axis) for all of Pop. Both SIL OFL 1.1, unmodified, in `assets/fonts/` with their licence texts (NOTICE, About → licences).

## Decided 2026-11-09 (Andy, after seeing the first renders)

- All four new styles ship; Night stays the default.
- The picker shows thumbnails of the real card, for single and comparison reports.
- Comparison cards get every style (2 to 4 setups, three formats).
- Pro: Night and Basic are free; sharing in Pop, Bridge or Mission needs Pro (`ProFeature.reportStyles`). Every style can be previewed without Pro; only Share is gated.
- Bridge was pushed further from LCARS: no solid colour blocks or amber, thin tick rulers and corner brackets, a pale yellow-white accent.
- Numbers that can hold a decimal point use B612, not B612Mono (the mono full stop leaves a wide gap: "0. 2 mi"). Night got the same fix (`ReportStyle.figure`: headline, stat values, comparison distance and margin, scale bar).

## How it is built

- `ReportTheme` (`lib/ui/widgets/field_report/report_theme.dart`), remembered in pref `field_report_theme`; `isPro` marks the Pro styles.
- `FieldReportCard(theme:)` hands every style but Night a `ThemedReport`, and `ComparisonReportCard(theme:)` a `ThemedComparison`: the data plus routes that have already been through `PrivateRoute` (a comparison's routes share one rotation and are drawn on one `RouteFrame`). A style never reads positions from the data, so Hide base area and the rotation cannot be bypassed by a style.
- Two files per style under `lib/ui/widgets/field_report/themes/` (`<style>_card.dart`, `<style>_comparison_card.dart`).
- The sheet's Style row (`field-report-theme`) draws each tile as the real card at feed size, scaled down, on the plain background; Share goes through `ProGate` for a Pro style.
- `test/field_report/render_themes_test.dart` writes every style and format as a PNG when `REPORT_RENDER_DIR` is set (skipped otherwise): `<style>-<format>.png`, `<style>-compare2-…`, `<style>-compare4-…`.

## Not in this pass

- Streets / Terrain backgrounds: Night only; the other styles draw the plain route.
- Not yet seen on a phone or simulator: the picker and the cards were checked through tests and rendered PNGs only. Three-setup comparisons, long titles and sessions with no distance are handled in code but were only spot-checked by the agents' scratch renders.

Renders from the test fixtures (2026-11-09): `themes/<style>-<format>.png` and `themes/<style>-compare<2|4>-<format>.png`.
