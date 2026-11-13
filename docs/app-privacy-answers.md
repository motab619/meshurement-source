# App Store Connect: App Privacy answers

What to set under App Store Connect → Meshurement → App Privacy, and why.
Mirrors `NSPrivacyCollectedDataTypes` in `ios/Runner/PrivacyInfo.xcprivacy`
(keep the two in step). Written 2026-11-04 from the audit
(`docs/audit/2026-11-04/compliance.md`, "App Privacy answers and the privacy
manifest do not cover the AI routes").

## "Do you or your third-party partners collect data from this app?"

**Yes.** Everything else the app records (sessions, positions, radio data,
backups) stays on the phone and is not "collected" in Apple's sense. The
off-device flows are:

| Flow | Goes to | When | Kept |
|------|---------|------|------|
| AI analysis (Analyze on a comparison or a guided-test result) | our Lambda, then Anthropic | only when the user taps Analyze with the AI switch on | Lambda: a random install id in quota counters, up to about 34 days; nothing else stored. Anthropic: per its API data policy |
| AI plan parsing (typed request on Plan a test → Ask) | our Lambda, then Anthropic | only when the AI switch is on and the user types a request and taps Next | as above |
| Terrain elevation | Open Topo Data | when terrain is on (Settings → Privacy) | third party; we have no control |
| Map tiles | OpenStreetMap or our CloudFront | when map tiles are on | standard web server logs (tile area, IP) |

## Data types to declare

For every type below: **Linked to the user's identity: No. Used for
tracking: No. Purpose: App Functionality** (only).

1. **Identifiers → Device ID**
   The random install id (`ai_device_id`, a UUID made by the app, not the
   IDFA or IDFV) sent as `X-Device-Id` and stored by the Lambda in DynamoDB
   counters (`dev#<id>#<day>` and `devm#<id>#<month>`, TTL up to about 34
   days) to enforce the daily and monthly limits. This is the part that
   clearly does not fit the optional-disclosure exception, because it is
   kept after the request.

2. **User Content → Other User Content**
   The sentence typed on the Ask screen (plan parser, up to 500 characters)
   and the optional question typed above Analyze (up to 300 characters),
   plus the names of saved antenna/radio profiles and range settings. Sent
   to Anthropic to produce the reply; not stored by our server.

3. **Usage Data → Other Usage Data**
   The numbers-only digest of a comparison or test result (packet counts,
   SNR/RSSI medians, ping success counts, airtime, distances from the base,
   app version). If you read this as measurement data rather than usage,
   "Other Data → Other Data Types" is the alternative; pick one and use the
   matching manifest key (`NSPrivacyCollectedDataTypeOtherUsageData` now,
   `NSPrivacyCollectedDataTypeOtherDataTypes` otherwise).

4. **Location → Precise Location**
   Measurement-point coordinates (and so the base location) sent to Open
   Topo Data when terrain elevation is on. Kept as recommended in the
   previous audit; drop it from both App Store Connect and the manifest
   only if you decide it qualifies for the real-time processing exception.

Do not declare: Contact Info, Health, Financial Info (StoreKit is Apple's),
Contacts, Browsing/Search History, Purchases (Apple handles them),
Diagnostics (no crash or analytics SDK), Sensitive Info.

## Privacy policy wording (hosted page, plateau-beta repo)

The hosted policy (`https://meshurement.com/privacy`)
currently mentions AI only for "Analyze with AI on a comparison". Suggested
replacement paragraph:

> **AI helpers (optional, off until you turn them on).** Meshurement has
> two AI helpers, both behind one switch in Settings → Privacy. *Analyze*
> sends a numbers-only summary of a comparison or test result (signal
> levels, counts, distances, the names you gave your antennas and radio
> setups, and any question you type) when you tap Analyze. *Plan a test*
> sends the request you type on the Ask screen, with the names of your saved
> setups and range settings, when you tap Next; picking a test from the list
> sends nothing, and with the switch off the app reads your request on the
> phone. Both go to our server and on to Anthropic, which writes the reply.
> Positions, routes, the base location, radio ids and keys are never sent.
> Our server keeps only a random install id and a request count, for up to
> about 34 days, to enforce usage limits; it does not store what you sent.

## In-app text already updated

- Settings → Privacy, the "AI helpers" switch (`lib/ui/screens/privacy_screen.dart`).
- The consent sheet (`showAiConsentSheet` in `lib/ui/widgets/ai_analysis_card.dart`).

Still saying "only when you tap Analyze" (owned by other changes): the
welcome flow's privacy page (`lib/ui/screens/onboarding/welcome_flow.dart`),
the About note (`_aiDataNote` in `lib/ui/screens/about_screen.dart`) and the
Ask screen's fine print (`lib/ui/screens/guided/ask_screen.dart`, which
should become conditional on the switch and name Anthropic).
