# Guided test: "walk me through it" (design, 2026-10-31)

Andy's ask: a "dummies" mode. The user says what they want to find out
("I want to test two antennas", "which range setting is best here") and
the app turns that into a plan and walks them through it, one simple
screen at a time, doing itself everything a radio or the phone can do,
and asking the person only for the things that need hands (swap an
antenna, walk the route). Low friction, matching UI. Where a radio can be
changed without touching it, the app does that too, and says what the
risk is.

`concept.html` beside this file is a clickable mock of the whole flow
(phone frame, dark theme tokens from `docs/design/theme.md`); every number
on it is a sample. Status: **design only, nothing built.** Roadmap slot:
after MeshCore and the comparison work (it is built on both).

User-facing name: **Guided test**. Never "wizard", never "dummies", never
"AI test plan" in the UI. The AI is a helper that understands the request
and writes the words; the plan itself is deterministic app code.

## 1. What it feels like

Four screens, in order. One job each, one primary key each.

1. **Ask.** "What do you want to find out?" A text field with the keyboard
   up, and five chips under it for the common cases. Typing is optional:
   tapping a chip and **Next** is the whole input for most people.
2. **Plan.** The plan as a vertical track of steps (the arcade
   level-select: numbered stops on a line, the current one lit orange).
   Each stop says what happens in one line and who does it (you · radios ·
   automatic). A total time at the top. Anything the user might want to
   change is a tappable value on the card (the antenna names, the route
   length, repeat on/off); nothing is a form. **Start** at the bottom.
3. **Run.** One step at a time, full screen: a mono caption `STEP 3 OF 7`,
   a short title, two sentences of instruction at most, one big key
   (56 px: this is used outdoors with gloves), and whatever that step
   needs to show (a progress list for radio changes, a mini map with the
   ghost route for walks). Pause and "I'm stuck" are always there, small.
   The plan survives the app being killed; reopening lands on the current
   step.
4. **Result.** "What you found out", written to the never-null rule
   (memory `analysis-never-null-result`): what the test proved, one number
   with its margin per variant, one next step. The AI narrative is the
   optional second half of the page behind the existing consent sheet. The
   result is kept as a **Test** under the map, next to sessions.

Three rules make it feel easy:

- **The app never asks for something it can work out.** It names the map,
  the sessions ("Antenna test · 2 of 4 · Stock whip"), the rig profiles,
  the ping interval and the beacon; it checks both radios are on MeshTest
  and on the same setting before every walk; it starts and stops the
  sessions itself when the user taps **I'm here** / **Done walking**.
- **Fairness is built in, not taught.** Same route (a ghost line plus a
  live "Route match 72%"), same start point, same ping interval, the base
  untouched between variants, and an optional second pass in the other
  order (ABBA) offered as "+12 min, makes the result trustworthy". The
  result says when a variant was walked at a different time of day or
  with the base moved.
- **Every readout is a sentence, every number has a unit and a margin.**

## 2. The five templates (v1)

The user's words map onto one of these. Each template is a pure function
`PlanBuilder.build(intent) -> List<PlanStep>`; the AI only fills the
intent. Variables that change between variants are in bold.

| Template | What varies | Who changes it | Steps per variant |
|---|---|---|---|
| **Compare antennas** (mobile or base) | the antenna on one radio | the person, at the radio | swap → walk → (auto stop) |
| **Compare range settings** | modem preset / MeshCore modulation on both radios | the app (base remotely or by Bluetooth, then the mobile) | change radios → go to start → walk |
| **Compare radios** | the mobile radio itself | the person swaps the connected radio | connect the other radio → setup check → walk |
| **Compare TX power** | `tx_power` on the mobile (or the base) | the app | change radio → walk |
| **How far does it reach** (one variant) | nothing | nobody | walk until the base is lost, come back |

Deferred, with the reason:

- *Where should the base go*: `PlacementAdvisor` exists, but moving the
  base between variants is a different kind of test (the route stays, the
  reference point moves). Second release.
- *Hop limit / relaying*: our setup is LOCAL_ONLY by design.
- Anything on the public channel: never (CLAUDE.md).

### The intent object

What the Ask screen produces, by chip or by AI:

```json
{ "template": "antennas",
  "side": "mobile",
  "variants": ["Stock whip", "5.8 dBi fiberglass"],
  "repeat": false,
  "route": { "kind": "walk", "minutes": 12 },
  "question": "which antenna gets me further up the hill" }
```

`PlanBuilder` validates it (2 to 4 variants, names unique, template known,
side allowed for the template) and builds the steps. An intent the app
cannot build is answered on the Ask screen with one line and the nearest
chip pre-selected, never an error dialog.

## 3. Step kinds

Every step is one of these; the runner knows how to show and finish each.
Kinds marked ⚙ are automatic (the user watches a short progress list);
🙋 needs the person; 🚶 is a recorded walk.

| Kind | Screen | Finishes when |
|---|---|---|
| ⚙ `preflight` | "Checking your setup" list: mobile connected, base known, both on MeshTest, same setting, base backup exists, base location known, GPS ok | all green; a red row has its own fix key ("Open Radio Setup", "Set base location") |
| 🙋 `swapHardware` | photo-free card: "Put the **5.8 dBi fiberglass** on the mobile radio. Screw it on hand-tight, then stand it upright." Variant name editable here | **Done, it's on** |
| 🙋 `switchRadio` | "Connect the other radio" with the connect list filtered to the other protocol-compatible radios | the new radio is ready and `RadioRoles` says mobile |
| ⚙ `changeRadios` | the base first, then the mobile; progress list from `onStep`; see §5 for the remote path and §6 for the safety sequence | both answer on the new setting |
| 🙋 `goTo` | "Walk to where you started last time" with a compass arrow, distance and the start pin; or "Stand within sight of the base" for radio changes | within 15 m, or **I'm here** |
| 🚶 `walk` | the Live map chrome (HUD band, dots) with the ghost route, route match %, elapsed vs planned; the session is started by the app on entry | **Done walking** (enabled at 80 % route match or planned time), or the ride-along / out-of-range flows end it |
| ⚙ `settle` | 20 s "Letting the radios settle" (after a change or a reboot) | timer |
| ⚙ `analyze` | spinner into the Result screen | result computed |

`walk` reuses `SessionManager.startSession` with the plan's names and
rigs, and `endSession`; the session row gets `test_step_id`. An ended
session with under 2 minutes or under 10 pings asks "Keep it or walk this
one again?" before moving on (a rescue, not a failure).

## 4. Data model (schema v11)

```
test_plans   id, coverage_map_id, title, goal_text, template, intent_json,
             status (draft|running|paused|done|abandoned), current_step,
             remote_changes (bool), created_at, finished_at, result_json,
             ai_result_json
test_steps   id, plan_id, ordinal, kind, variant (nullable), title,
             instruction, params_json, status (todo|active|done|skipped),
             session_id (nullable), started_at, ended_at, note
sessions     + test_step_id (nullable)
```

`result_json` is the N-way analysis (§7); `ai_result_json` the cached
narrative so reopening does not re-bill. A plan is a child of a map, so
map delete / move / export carry it.

## 5. Changing the base without touching it

Only **Meshtastic** can do this. MeshCore's companion protocol has no
remote administration for a companion node (repeaters have a CLI login;
our base is a companion with repeat on), so on MeshCore a base change is
always the Bluetooth path below. The app says so in the plan: "MeshCore:
the base is changed by walking to it; the app connects over Bluetooth".

### Two paths, chosen per step

1. **Bluetooth path** (both protocols, lowest risk). The step is `goTo`
   the base, then the app connects to the base over BLE and runs the
   existing Radio Setup base flow for the new setting (`applyToBase` with
   the same channel key), then switches back to the mobile
   (`switchToAndApplyMobile`). This is what Radio Setup already does. The
   base needs to be within Bluetooth reach (~10 to 30 m).
2. **Remote path** (Meshtastic only). An admin message over the mesh.
   Needs, on the base, our mobile radio's public key in
   `Config.SecurityConfig.admin_key` (up to three 32-byte keys, firmware
   2.5+). The messages are PKI-encrypted DMs on `ADMIN_APP` and the base
   checks the sender's key against that list. Firmware 2.5+ also wants a
   **session passkey**: the first request is a `get_config_request`; the
   reply carries `session_passkey`, valid 300 s, and every set must
   include it. Sequence: `begin_edit_settings` → `set_config(lora)` →
   `commit_edit_settings`. The commit reboots the base, so a lost ACK on
   the commit counts as sent (same rule as local Radio Setup).

The grant is made once, over Bluetooth, in **Radio Setup's base flow**:
a new line "Allow the mobile radio to change this base's settings from a
distance" (on by default; it only names our own other radio's key).
`RadioRoles` remembers it (`base_remote_admin` = the mobile node num the
grant was for), and the grant is re-made whenever the mobile radio
changes (the key is per radio). Existing setups: the guided test's
preflight shows "Remote changes: not enabled" with the fix "Enable at the
base (Bluetooth)", which is the `goTo` base step plus the one admin write.

Preflight picks the path: remote when the grant exists and the base is
heard; otherwise Bluetooth, with the distance to the base shown so the
user knows what they are walking into.

### Saying the risk, once, in words

Before the **first** remote change of a plan, a sheet:

> **Changing the base from here**
>
> The app will tell the base radio to switch to **Long Fast**, then switch
> your radio to match. The base restarts to do it.
>
> **What can go wrong:** if the base restarts on a setting your radio
> can't reach from here, you will have to walk to the base and fix it in
> Radio Setup. The base is **340 m** away right now.
>
> **What the app does to keep you safe:** it checks the base's settings
> are saved · it changes the base first and your radio second · it listens for
> the base for two minutes on the new setting · if the base stays silent it
> puts your radio back and stops the plan with directions to the base.
>
> ☐ I can get to the base if I need to
>
> [ Change base from here ]   [ I'll walk to it instead ]

The checkbox gates the key. The same sheet, shorter, sits behind an ⓘ on
every later `changeRadios` step. The plan also places every range-setting
change at the **start point near the base** (`goTo` "Stand within sight of
the base") so the two-minute listen happens where the link is strongest,
which is also where a failed change is cheapest to fix.

## 6. The safety sequence for a remote range-setting change

```
check the base's saved settings (remote path: Radio Setup's
  backup must exist; Bluetooth path: a fresh backup is taken)  ⚙
base: begin_edit, set_config(lora: new), commit  (remote)     ⚙  ack or lost-on-commit
settle 20 s                                                   ⚙
mobile: Radio Setup profile with new preset (local BLE)       ⚙  reboots, reconnects
listen for the base beacon / ping it, up to 120 s             ⚙
  heard  → step done, next
  silent → mobile back to old preset (local)                  ⚙
           ping base on old preset, 60 s
             answers → "The base didn't take the change." Offer: try
                       again · walk to it (Bluetooth path) · stop
             silent  → "The base is on the new setting but out of reach
                       from here." Directions to the base; plan paused,
                       not lost: Bluetooth path from there.
```

Nothing in the plan ever changes the channel or the key, only the modem
preset / MeshCore modulation and TX power, so the worst case is the
walk to the base the sheet warned about, and Radio Setup's "Put this
radio back the way it was" is always behind it. `SessionManager` keeps its
refusal to run on the public channel; the plan cannot get around it.

## 7. The result

`PlanAnalysis` runs over the plan's sessions grouped by variant:

- Two variants: the existing `RouteComparison` (50 m cells, median delta
  and % cells better) plus `SideRangeStats` (farthest answered ping, first
  miss, per-distance bands) and `rangeNarrative`.
- Three or four variants: each against the first ("your current setup")
  with the same machinery, and one table: variant · farthest reach ·
  median SNR on shared cells · pings answered. The headline names the
  winner by the measure the user asked about (reach for "further",
  margin for "more reliable"), with the margin, or states equivalence as
  the finding.
- Range-setting comparisons add airtime: "Medium Fast carried the same
  route with 0.9 s less airtime per ping", `fasterPresetFor`'s rule.
- Data problems are rescues: "Variant 2 was walked 40 min later and the
  base had moved 20 m; shown but marked."

The AI card is the existing `AiAnalysisCard` with a `question` built from
the goal text, a digest extended with the per-variant table (numbers
only; `assertNoLocationData` unchanged). One new backend route, `plan`,
for the Ask screen (§8).

## 8. Where the AI is, and where it is not

| Job | Who | Notes |
|---|---|---|
| Turn "test my two antennas up the hill" into an intent | Claude Haiku 5.5 via the existing Lambda, new route `plan` | Input: the typed text and the app's list of templates, the user's rig names, the radios' protocol. Output: strict JSON intent, validated by `PlanBuilder`; anything unknown becomes the nearest chip. Quota and consent as today (the typed text is already allowed: `question`). Offline or no consent: the chips do the same job without the model. |
| Write the plan's one-line "why" per step | app strings | Deterministic; no model in the loop while radios are being changed. |
| Decide step order, radio commands, safety sequence | app code only | The model never emits a radio command, never sees node ids, keys or positions. |
| Write the result narrative | existing AI analysis | Opt-in, cached. |

Backend: `tool/ai-analysis/handler.py` gains `POST /plan` sharing the
quotas (counted as one analysis), a system prompt that lists the
templates and the JSON schema, and the same counts-only logging. A plan
request is a few hundred tokens.

## 9. Where it lives in the app

- **Coverage tab:** a "Plan a test" key at the top, under the Get started
  card (and the Get started card's last step, "Record your first walk",
  gains a second key "Walk me through a test").
- **Live tab, idle sheet:** a "Guided test" row above the Start controls.
- **Compare screen:** "Make this a guided test" (pre-fills the two rigs).
- **Map detail:** a **Tests** section next to Sessions; a test row opens
  its Result screen; a paused test shows **Continue**.
- **Settings → Radio Setup (base):** the remote-changes grant line.

Pro: the guided test itself and two-variant comparisons are **free** (it
is the onboarding story and the thing the beta needs tested); three or
four variants and the AI parts are **Pro** (`ProFeature.guidedTests` for
3+ variants; `aiAnalysis` as today). Decision for Andy; the paywall copy
would be "Compare up to four setups in one guided test".

## 10. Code shape

```
lib/services/guided/
  plan_intent.dart        PlanIntent, templates, validation (pure, tested)
  plan_builder.dart       intent -> steps (pure, tested)
  plan_runner.dart        state machine: current step, pause/resume, the
                          safety sequence; talks to SessionManager,
                          RadioProfileService, RadioRoles, GpsService
  plan_analysis.dart      N-way result over RouteComparison/SideRangeStats
  plan_intent_parser.dart chips + AiAnalysisGateway 'plan' route
lib/data/radio/meshtastic/meshtastic_radio.dart
  grantRemoteAdmin(pubKey)             local: set_config(security.admin_key)
  setRemoteLora(nodeNum, preset)       passkey handshake, begin/set/commit
lib/ui/screens/guided/
  ask_screen.dart, plan_screen.dart, run_screen.dart, result_screen.dart
  widgets: step_track.dart, risk_sheet.dart, ghost_route_layer.dart
```

`MeshRadio` gains `Future<bool> get supportsRemoteAdmin` (MeshCore: false).
`RadioProfileService` gains `grantRemoteAdmin` in the base flow. Demo mode
gets `-demoScreen guided` for screenshots.

## 11. Build order and gates

1. **Antennas + runner + result** (no radio changes at all): Ask with
   chips only, Plan, Run with `swapHardware` / `goTo` / `walk`, Result
   with two variants. Gate: Andy runs a two-antenna test on the ranch
   from the first screen to the result without opening Settings.
2. **Range settings by Bluetooth**: `changeRadios` on the Bluetooth path,
   both protocols; the "same as your mesh" MeshCore ladder. Gate: a
   Medium Fast vs Long Fast walk, and a MeshCore ladder step.
3. **Remote base changes (Meshtastic)**: the grant in Radio Setup, the
   passkey flow, the risk sheet, the safety sequence. Gate: a deliberate
   failure (wrong preset on purpose) recovers to the old preset and the
   directions screen.
4. **AI Ask**: the `plan` route, typed requests, 3 to 4 variants, the
   Pro line. Gate: ten real sentences from Dan and Matt land on the right
   template.

Android note (CLAUDE.md rule): remote admin is protocol-level, nothing
platform-specific; the BLE path is the existing transport.

## 12. Decisions (Andy, 2026-10-31)

- **Free vs Pro:** two setups free; three or four setups and the AI parts
  need Pro (`ProFeature.guidedTests`). The paywall line: "Guided test
  with three or four setups in one go (two are free)."
- **Second pass:** off by default, offered on the Plan screen as "Second
  pass, other order · +N min · makes the result trustworthy".
- **Base location:** a guided test may set it when the map has none; the
  first go-to step reads "Stand next to the base, tap Set".
- **Remote grant:** Radio Setup's base flow gives the base the mobile
  radio's key by default, with one line saying so and a switch to turn
  it off.
- **Risk sheet:** the full sheet with the checkbox appears once ever on
  this phone (`guided_risk_seen_v1`); after that a one-line reminder with
  an ⓘ that reopens it.
- **Where it lives:** "Plan a test" key on the Coverage tab plus a row in
  the Live tab's idle sheet, links from Compare and map detail; no new
  tab.
- **Name:** "Guided test"; the key reads "Plan a test".
- **Build:** all four pieces at once (engine + schema, remote admin,
  UI, AI parser) on worktrees `gt-core`, `gt-remote`, `gt-ui`, `gt-ai`
  off `field-build-oct23`, merged by hand.

### Status

Contract committed 2026-10-31 (`lib/services/guided/plan_models.dart`,
`MeshRadio` remote-admin members, `ProFeature.guidedTests`, placeholder
providers). The four pieces are being built in parallel.
