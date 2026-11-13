# Quality and compliance sweep — 2026-11-04

Four independent read-only audits of `field-build-oct23` (98 commits past `main`, plus the uncommitted work of 2026-11-02/04: heading-up tied to follow, silence in the estimated layer, the new icon), each an update of the matching 2026-10-16 report. Detailed reports beside this file:

| Report | Model | Blocker | High | Medium | Low/Info | Prior findings |
|---|---|---|---|---|---|---|
| [compliance.md](compliance.md) | Opus | 2 | 4 | 6 | 7 | 8 fixed · 5 partly · 4 open |
| [security.md](security.md) | Opus | – | 1 | 5 | 18 | 4 fixed · 2 partly · 5 open |
| [quality.md](quality.md) | Opus | – | 0 | 4 | 15 | 13 fixed · 9 partly · 10 open |
| [ux.md](ux.md) | Opus | – | 3 | 9 | 12 | 3 fixed · 10 partly · 3 open |

`flutter analyze` clean · 973 tests pass · git history (268 commits, all branches) has no secrets, keys or home coordinates · the MeshCore frame codec is bounds-checked and protobuf decoding is wrapped · no coordinates reach the AI backend (`assertNoLocationData` before every send) · the AI consent sheet names Anthropic before anything is sent · NOTICE lists every Dart package at its exact version · the new icon does not resemble the Meshtastic or MeshCore logos.

Items marked ✔ were re-checked by reading the code after the agents reported. Two of the quality findings were in that day's uncommitted work and were fixed the same afternoon (see §5).

---

## 1. Must fix before App Store submission

| # | Finding | Why it blocks | Fix (size) |
|---|---|---|---|
| 1 | ✔ **GPL source still not available.** The repo is private (`gh repo view` → PRIVATE); the in-app "Source code" link 404s. Builds have gone to external TestFlight testers since build 10. | GPL-3.0 §6 on the bundled Meshtastic protobufs; guideline 2.1(a) dead link. | Make the repo public (after the hygiene pass: commit email, business notes in CLAUDE.md/roadmap, `.gitignore`), tag each uploaded build. **Decision.** |
| 2 | ✔ **TestFlight Pro unlock also unlocks App Review.** `TestBuild.unlockPro` keys off a sandbox receipt; App Review installs carry one too, so the reviewer never sees the paywall and cannot review the subscription (2.1(b), 2.3.1). CLAUDE.md already says "remove before launch". | Reviewer can't exercise the purchase. | Replace the receipt check with a build-time define set only by the `beta` lane, or drop the unlock before submission. **Small.** |
| 3 | **Paywall says MeshCore and Guided tests are "Coming soon"** though both ship and are gated (`_shipped` lists only rig profiles, rig comparison, AI), and still lists four unbuilt features next to the buy button. A MeshCore user taps a radio and is told MeshCore isn't out yet. | 3.1.2 ongoing value, 2.3 accuracy; also a UX HIGH. | Add MeshCore and guided tests to `_shipped`; drop or clearly separate the planned four. **Small.** |
| 4 | **Store draft, description.md and README still say data leaves the phone only on CSV export.** The in-app privacy copy and the hosted policy are now correct (tiles via CloudFront, AI Lambda → Anthropic). | 5.1.1 accuracy in metadata. | Update the three texts; set App Privacy answers for the AI routes (install id kept ~34 days server-side, typed text). **Small.** |
| 5 | **Guided-test plan parser sends typed text on every Next, free users included**, while the Privacy switch says "only when you tap Analyze" and the policy doesn't mention the route. | 5.1.1 consent vs behaviour. | Gate the parser call behind the same AI switch, or disclose it. **Small.** |
| 6 | ✔ **Remote admin grant never removed** (security HIGH, UX HIGH). Radio Setup writes the mobile's key into the base's `security.admin_key`; backups don't capture security config, so "Put this radio back the way it was" leaves it, and in the mobile-first flow there is no checkbox at all. A full key list silently drops the oldest key, which may be the user's own. | Whoever later holds the mobile radio can reconfigure the base and read its channel keys. | Snapshot `security` in `MeshtasticBackup` and restore it; add the consent line to the mobile-first flow; refuse (or ask) when the key list is full. **Medium.** |
| 7 | **Reviewers cannot exercise the app without two radios.** | 2.1(b) completeness. | Demo mode is already on a launch arg; add Review Notes with `-MeshDemo` instructions, or a demo-mode toggle in About for review builds, plus a video. **Small.** |

## 2. Should fix before the next external TestFlight build

- **AI Lambda is unauthenticated** (`AuthType: NONE`); the per-device quota trusts a client-made device id and nothing server-side checks Pro. One script can burn the 2000/day global cap and switch AI off for everyone. Add a signed app attestation or at least a shared token plus per-IP limits. (security MEDIUM)
- **Erase all app data** leaves `base_loc_*` prefs (home to 50 m), `Documents/Exports/`, `diag.log`, and never VACUUMs. The dialog says everything but the key and the purchase goes. (security MEDIUM)
- **MeshCore: a command or Bluetooth write timeout is recorded as a trace timeout** → beacon miss, out-of-range clock, and now a silence sample. Separate `_cmd.send` failures from "no reply". (quality MEDIUM; `meshcore_radio.dart:849-878`)
- **Per-packet DB fan-out grew**: every packet updates `nodes.last_heard_at`, which re-runs the all-nodes query and rebuilds any open map screen including the `EstimateSamples` pass; map watchers are still never disposed and four more non-disposing family providers were added. (quality MEDIUM)
- **Error text**: `userMessage` collapses every `StateError` into "Something went wrong while setting up the radio (StateError)", discarding the sentence it was given; ~15 places (every guided screen) still show raw `$e`. (ux HIGH)
- **Terminology**: MeshCore users still see "pings" (Settings "Ping Interval", Live Activity, the estimated-layer chip, guided result); raw preset ids (`MEDIUM_FAST`, `MC_SF9_BW125_CR5`) reach the lock screen, the radio sheet and the Compare picker; "Range preset" / "Preset" / "modem presets" / "range setting" mixed. (ux MEDIUM)
- **Two first-run checklists** (Live and Coverage) with different steps and separate dismissal. (ux MEDIUM)
- **Pro "3 to 4 setups"** is reachable only by typing a sentence; the Plan screen has no "Add a setup". (ux MEDIUM)
- **Colour-only encodings**: Live legend off by default, dots red→green, guided pre-check rows are colour squares whose text says "every row is green". (ux MEDIUM)
- **"Renews <date>"** shows after the subscription is cancelled. (ux MEDIUM)
- **Compass**: no visible cue when heading-up is paused; a pinch zoom (any two-finger gesture) drops follow and so pauses heading up, and after the recording resume timer the map starts turning by itself. (ux MEDIUM; the "pinch counts as a twist" half is fixed, see §5)
- **OSM attribution** collapsed behind a tap on Compare and the guided walk map, and covered by shading on Compare. (compliance MEDIUM)
- **file_picker's MIT pods** (SDWebImage, DKImagePickerController, DKPhotoGallery, SwiftyGif) not in NOTICE. (compliance MEDIUM)
- **Test channel key still in plaintext SharedPreferences**, and MeshCore uses half of the same key; backups still hold every channel secret in plain JSON; "Copy channel link" copies before it warns. (security MEDIUM, unchanged)

## 3. Before App Store release, lower priority

- GPL-3.0 protobufs on the App Store without a written grant from Meshtastic LLC (unchanged); hidden lifetime product sold only via offer codes (unchanged); reliance on free community services outside the self-hosted tiles (Open Topo Data).
- Security LOWs: `MeshCoreRadio.ping` and `setRemoteLora` have no radio-level public-channel check and the guided listen loop bypasses the probe service; MeshCore counts as public only on an exact preset match; expanded simple keys with last byte 0x0b–0xff pass; an over-the-air NodeInfo replaces the base's cached key and is pushed back to the mobile; MeshCore adverts trusted without signature; second connections to "the base" don't verify the node number; an imported backup can become a radio's "original"; node positions unranged; region setup enables TX on the public channel; personal email in commits; PMTiles directory parser trusts network lengths; Anthropic key as a plain Lambda env var.
- Quality LOWs: superseded Meshtastic `connect()` can tear down the newer link and the `_reconnecting` guard can leave a newer link without a loop; auto-reconnect after an iOS kill makes one attempt and there is no Bluetooth state restoration; `_retuneTrace` can resurrect an ended session; commander can take a late reply as the next answer; guided rollback can report "done" without changing anything; a remote commit lost over the mesh counts as applied; routing reply dispatch swallows every error; pings in flight on link drop become `timeout`; fire-and-forget futures without a lint; no fresh-vs-upgraded schema test; `moveSessions` ignores guided plans; ride-along "Stop & trim" is irreversible on untuned thresholds; tests use real-time sleeps; base-first Radio Setup can still set the mobile's region to US; no GPS fix-age check.
- UX LOWs: Get started "done" line shows hex ids; Coverage empty state wrong; Plan rename dialog antenna-only; guided test silently creates a map "Guided tests"; Ask chips' glyphs read aloud; out-of-range setting shows a window the app may widen; signal readout VoiceOver label hides values; two legends with two vocabularies; Welcome/About copy; Bluetooth permission string names only Meshtastic (no ®); Ask screen privacy note claims text is sent even when it isn't; Title Case vs sentence case and US/UK spelling; Settings rows Dynamic Type overflow; connect dialog dismissable mid-connect.
- Compliance LOWs: store description details stale; `flutter_compass` runs 30 Hz motion updates for the whole app lifetime (start it only while heading up is on); unused Always-location and iPad orientation keys; Fastfile SPDX header; icon artwork origin not recorded.
- Icon (ux MEDIUM): busy at 60 px, the sun is cropped at the right edge, dots run green→red (colour-only), more synthwave than "not overly so". Andy's call.
- Dependencies: 23 direct packages behind, five by a major (flutter_blue_plus, riverpod, geolocator, flutter_local_notifications, protobuf); `sqlite3_flutter_libs` EOL line; `riverpod_annotation`/`riverpod_generator` unused.
- Test gaps: session resume after a kill, auto-reconnect, `LiveActivityService`, `MeshCoreCommander`, the migration chain.

## 4. Prior (2026-10-16) blockers, where they stand

| 10-16 # | Finding | Now |
|---|---|---|
| 1 | Paywall "null Coming soon" | Fixed, but see §1.3: shipped features still labelled "Coming soon" |
| 2 | Privacy URL dead | Fixed (200) |
| 3 | Privacy copy wrong about network | Fixed in app and policy; store draft/README still wrong (§1.4) |
| 4 | GPL source unavailable | **Still open** (§1.1) |
| 5 | Public-channel guard bypass | Fixed (checked before every ping/NodeInfo, in the radio, restore and switching blocked while recording); LOW gaps remain on MeshCore |
| 6 | Range Test packets dropped while dialog pending | Fixed |
| 7 | GPS never starts without launch permission | Fixed |
| 8 | Live Activity status line | Fixed |
| 9 | No OSM attribution | Partly: present on all maps, collapsed/covered on two |

## 5. Fixed the same day (uncommitted work, 2026-11-04)

- **Estimated layer counted refused pings as silence.** NAK'd (e.g. local `PKI_SEND_FAIL_PUBLIC_KEY`) and throttled pings leave a reply row without a signal, which `EstimateSamples` painted as "no margin". It now decides silence from the ping's outcome: timeouts (at the send position) and received/implicit replies whose ack row carries no signal. The chip reads "N pings with no direct reply count as no margin" (or "no signal" in RSSI mode). Tests added.
- **A pinch zoom switched heading up off.** flutter_map with the gesture race off emits a rotate event on almost any two-finger gesture, which the new twist detector took as a user twist. `enableMultiFingerGestureRace` is now on: a two-finger gesture is either a zoom or a twist (20° before it counts), so a pinch never turns the map a few degrees off north. Test asserts the option.
- Still open from these two features: heading up has no "paused" cue, and the terrain-aware estimate ignores silence samples (so the reported green gap returns with terrain on).

## 6. Fix pass (same day, five Opus agents, merged as commits 4711997…1b14092)

Everything in §1 and §2 that is code was fixed and merged onto `field-build-oct23`, except the decisions, plus most of §3. `flutter analyze` clean, 1071 tests pass. Nothing has been tried on a phone.

| Area | Done | Left |
|---|---|---|
| Paywall / store | TestFlight Pro unlock is now a build define that only `fastlane beta` passes; a new `fastlane release` lane builds without it and **only `release` builds may be submitted for review**. Paywall lists MeshCore and Guided tests as included, unbuilt features removed, "active until" instead of "renews". Store draft, description.md, README privacy text; `docs/app-review-notes.md`; hidden long-press on the About title turns demo mode on for reviewers; Fastfile SPDX header. | GPL source link (repo is private: your decision). |
| Security | `MeshtasticBackup` v4 carries the base's admin keys so Restore and "Put back" remove the mobile's grant; same consent switch in both Radio Setup flows; "Stop allowing" revoke row; a full admin list asks (Skip default) instead of dropping a key; Erase all data removes base locations, exports, diag.log and VACUUMs; Copy channel link warns first; public-channel check in `MeshCoreRadio.ping`, `setRemoteLora` and the guided listen loop; expanded simple keys caught; over-the-air NodeInfo can't replace a saved key; second connections verify the base's node number. | Channel key still in SharedPreferences (Keychain is a separate change). Needs the hardware checks listed in security.md's hand-back: restore removes the key (`--get security`), revoke keeps the key pair, full-list prompt, wrong-node refusal, erase on device. |
| AI / privacy | Plan parser honours the AI switch and stays local without a token; consent sheet offered once on Ask; Privacy switch is "AI helpers" covering both routes; Lambda requires `X-App-Token`, per-IP daily limit, Anthropic key from Secrets Manager; `PrivacyInfo.xcprivacy` declares the data types; `docs/app-privacy-answers.md`; compass subscribed lazily; unused Always-location and iPad keys removed; PMTiles parser bounds-checked. | **Andy: redeploy the Lambda** (`tool/ai-analysis/README.md`: token, secret ARN, `IpDailyLimit`), put `AI_APP_TOKEN` in `ios/fastlane/.env` and add the `--dart-define` to the Fastfile build. Existing TestFlight builds lose AI when the new Lambda goes live, so ship a tokened build with it. flutter_compass's native side still starts CoreMotion at launch (plugin). Pro is still only checked client-side. |
| Quality | MeshCore command/write failures are `error:RADIO_BUSY` / `error:LINK_LOST`, never a trace timeout; last-heard writes throttled to 30 s; `_retuneTrace` can't revive an ended session; commander drops late replies; rollback reads the radio back and retries an unconfirmed remote commit once; routing dispatch logs instead of swallowing; pending pings end as `LINK_LOST` on teardown; migration-chain test (v1 → v11 equals fresh); `moveSessions` clears plan links; export TODOs resolved. | `unawaited_futures` lint not enabled (15 sites in UI files); map-detail family providers still not autoDispose; `test/guided/plan_runner_test.dart` "silent base, old setting answers" flakes about one run in three on real timers. |
| UX / copy | `userMessage` keeps worded errors, raw `$e` gone from lib/ui; `probeNoun` ("ping" / "link check") in Settings, Live Activity, estimate chip, guided screens and the reach result; preset display names everywhere incl. the lock screen; one Get started checklist (Live shows a pill); "Add a setup" on the Plan screen (Pro for 3 and 4); colour key on by default, check rows have words, "every check passes"; paused-heading cue on the compass; always-visible OSM credit on Compare and the guided walk map; file_picker pods in NOTICE; the ux.md LOWs; Bluetooth usage string names both radio kinds. | Dynamic Type on the map-detail segments and the map pill; session-tile copy in map detail; the icon critique (your call). |
