# AI session analysis backend

A small AWS Lambda (Python 3.12, Function URL) that receives the app's
numbers-only digest of a comparison, asks **Claude Haiku 5.5**
(`claude-haiku-5-5`) to write the narrative, and returns strict JSON:

```json
{ "headline": "...", "bullets": ["..."], "caveats": ["..."], "next_step": "...", "model": "claude-haiku-5-5" }
```

The Anthropic key lives in AWS Secrets Manager, never in the app or a
Lambda environment variable. Every request must carry the shared app token
(`X-App-Token`, see [App token](#app-token)); without it the answer is 401
and nothing is counted or spent. The handler validates the digest (<= 32 KB,
known schema, rejects any coordinate-like field or value, node ids, keys),
enforces per-device daily and monthly quotas, a per-source-IP daily quota
and a global daily budget in DynamoDB, and logs counts only (token counts,
status codes; never digest bodies).

The same Function URL also serves the Guided test's **plan** route (below):
a body with `"kind": "plan"` is a plan request; a body without `kind` is a
digest and is handled exactly as before.

## Plan route (Guided test)

`lib/services/guided/plan_intent_parser.dart` (`AiPlanIntentParser`) turns
the sentence typed on the Ask screen into a plan intent. The model only fills
the intent: it never sees node ids, keys or positions and never emits a
radio command (design: `docs/design/guided-test/README.md` §8). Same
headers as an analysis (`X-App-Token`, `X-Device-Id`, `X-App-Version`),
same consent switch in the app (off: the app parses the text on the phone
and sends nothing; the Ask screen offers the consent sheet once), and **one plan request costs one analysis** of the
device's daily and monthly quotas and the global budget. Replies are never
cached (the text differs every time).

Request:

```json
{ "kind": "plan",
  "text": "test the stock whip vs the 5.8 dBi fiberglass twice, 20 minute walks",
  "templates": [ { "id": "antennas", "chip": "Compare antennas",
                   "variantsMean": "antenna names, e.g. \"Stock whip\"" }, "..." ],
  "protocol": "meshtastic",
  "rigNames": ["Stock whip", "5.8 dBi fiberglass"],
  "presets": { "LONG_FAST": "Long Fast", "MEDIUM_FAST": "Medium Fast" },
  "limits": { "minVariants": 2, "maxVariants": 4,
              "minRouteMinutes": 5, "maxRouteMinutes": 60 } }
```

Checks (400 otherwise): `text` 1 to 500 characters with no coordinate-like
pair; up to 10 templates of short strings (absent: the app's five);
`rigNames` and `presets` (a list or an id-to-name object) up to 40 short
entries; the same forbidden-field and coordinate scan as a digest over the
whole body. The app itself refuses to send a text that matches the
coordinate pattern or is over 500 characters, and falls back to its
keyword parser.

Reply (200):

```json
{ "intent": { "template": "antennas", "side": "mobile",
              "variants": ["Stock whip", "5.8 dBi fiberglass"],
              "repeat": true, "route": { "kind": "walk", "minutes": 20 },
              "question": "test the stock whip vs ..." },
  "confidence": 0.92, "clarification": null, "model": "claude-haiku-5-5" }
```

The model answers through a forced tool call (`fill_plan_intent`,
`max_tokens` 300, a few hundred input tokens) and the handler re-validates:
template id known, `side` in mobile/base (radios always mobile), 2 to 4
unique variants (reach: exactly one), TX power variants 0 to 30, route
minutes clamped to the limits, confidence clamped to 0 to 1, clarification
≤ 200 characters or null; `question` echoes the text. A reply that fails
these is a 502 `{"error": "plan failed"}` with the quota refunded, like a
failed analysis; 429 is the same shape as for analyses. Logs carry token
counts, the template id and the variant count only.

## Guided-test digest (Result screen)

The Guided test's Result screen has its own AI card. It sends the plan's
numbers-only digest (`PlanAnalysisResult.digest`, built by
`lib/services/guided/plan_analysis.dart`, run through the app's location
scrubber first) through the same `AiAnalysisClient` path, consent and
cache, with `"kind": "guidedTest"` at the top level:

```json
{ "schema": 1, "kind": "guidedTest",
  "template": "antennas", "side": "mobile", "repeat": false,
  "routeMinutes": 12, "protocol": "meshtastic",
  "question": "which antenna gets me further up the hill",
  "variants": [ { "name": "Stock whip", "sessions": 1, "presets": ["MEDIUM_FAST"],
                  "pingsTotal": 20, "pingsOk": 15, "pingFailures": {"timeout": 5},
                  "snrMedianDb": 4.5, "farthestAckM": 840, "firstMissM": 640,
                  "heardOutToM": 1040, "farthestWalkedM": 1200, "pingsImplicit": 0,
                  "ackRate300to1000mPct": 75.0,
                  "successPerBand": [{"fromM": 0, "toM": 250, "ok": 5, "total": 5}, "..."],
                  "airtimePerPingMs": 180.0, "routeMatchPct": 91.0, "..." },
                "..." ],
  "comparisons": [ { "a": "Stock whip", "b": "5.8 dBi fiberglass",
                     "meaning": "delta is B minus A; positive means B is stronger",
                     "cellMeters": 50, "cellsMatched": 38, "snrMedianDeltaDb": 3.5,
                     "pctBBetterBy3Db": 55.0, "pctABetterBy3Db": 10.0,
                     "rssiMedianDeltaDb": 3.0 } ],
  "appReading": { "headline": "...", "fairness": "...", "nextStep": "...",
                  "dataNotes": [], "winner": "5.8 dBi fiberglass" } }
```

Validation (400 otherwise): known keys only at every level (top level,
each variant, each band, each comparison, `appReading`; the variant keys
are `SideStats.toJson` plus the per-setup range figures), `schema` 1, 1 to
4 variants each with a `name`, up to 3 comparisons, `question` ≤ 300
characters, `dataNotes` ≤ 8, and the same forbidden-field and coordinate
`scan()` as a comparison digest over the whole body. One request costs one
analysis of the quotas. The model gets a guided-test variant of the system
prompt (multi-setup, must not contradict `appReading`'s winner or tie, no
positions) and answers through the same forced `write_analysis` tool, so
the reply is the same `{headline, bullets, caveats, next_step, model}` as
an analysis; failures are 502 `{"error": "analysis failed"}` with the quota
refunded. Logs carry token counts and the variant count only.

A body without `kind` is a comparison digest and is handled exactly as
before (a comparison digest carrying any `kind` is rejected as an
unexpected field).

## Limits and parameters

| Template parameter   | Env var                | Default            | What it caps |
|----------------------|------------------------|--------------------|--------------|
| `DeviceDailyLimit`   | `DEVICE_DAILY_LIMIT`   | 25                 | analyses (and plan requests) per device per UTC day |
| `DeviceMonthlyLimit` | `DEVICE_MONTHLY_LIMIT` | 300                | analyses per device per UTC month |
| `IpDailyLimit`       | `IP_DAILY_LIMIT`       | 100                | analyses per source IP per UTC day (a script inventing install ids still hits this) |
| `GlobalDailyLimit`   | `GLOBAL_DAILY_LIMIT`   | 2000               | analyses per UTC day across everyone (the budget) |
| `ModelId`            | `MODEL_ID`             | `claude-haiku-5-5` | the Anthropic model; change it with a parameter override, not a code edit |

The device is the app's random install id (`X-Device-Id`); the IP is the
Function URL's `requestContext.http.sourceIp`. Each request takes the
device's daily count, then its monthly count, then the IP's daily count,
then the global count, all or nothing: if a later counter is full, the ones already taken
are refunded, so a device over its own limit never burns the global budget,
and a failed analysis (502) refunds all three. Counters are DynamoDB items
(`dev#<id>#YYYY-MM-DD`, `devm#<id>#YYYY-MM`, `ip#<address>#YYYY-MM-DD`,
`global#YYYY-MM-DD`) with a TTL a few days after the day or month ends.

A cap answers HTTP 429:

```json
{ "error": "monthly limit reached", "reason": "monthly",
  "message": "You've used this month's 300 analyses; more on the 1st (UTC)." }
```

`reason` is `daily`, `monthly`, `ip` or `global`; `message` is the line the app
shows (it falls back to its own text for the reason, and older app builds
just read the status). `error` keeps its old wording.

## App token

A shared secret between the app and the function. It is not a strong
credential (it ships inside every app binary), but it stops anyone who only
has the public Function URL from spending the budget, and it can be rotated
by changing it in both places. Pro is still only checked in the app; App
Attest or a StoreKit JWS check in the function would be the next step.

Make one (keep it out of git; a password manager is a good home):

```bash
openssl rand -hex 32
```

Function side: the `AppToken` stack parameter becomes the `APP_TOKEN`
environment variable. With no `APP_TOKEN` the function refuses every
request (fail closed).

App side: the token is read at build time from
`--dart-define=AI_APP_TOKEN=...` (`aiAppToken` in
`lib/services/ai_analysis.dart`), never from a committed literal. A build
without it makes no AI request at all: the Ask screen parses on the phone,
and the AI cards show "AI analysis is unavailable." A 401 or 403 from the
function shows the same.

```bash
# Debug run on the phone
flutter run --dart-define=AI_APP_TOKEN="$AI_APP_TOKEN"
```

TestFlight (`cd ios && fastlane beta`): the lane compiles Dart with
`flutter build ios`, and Xcode's archive reuses the defines that command
writes into `Generated.xcconfig` (`DART_DEFINES`), so the token only has to
be added there. Put `AI_APP_TOKEN=...` in `ios/fastlane/.env` (git-ignored,
next to the App Store Connect key) and add one argument to the
`sh("flutter", "build", "ios", ...)` call in `ios/fastlane/Fastfile`:

```ruby
sh("flutter", "build", "ios", "--release", "--no-codesign",
   "--build-number=#{build}",
   "--dart-define=AI_APP_TOKEN=#{ENV.fetch("AI_APP_TOKEN")}")
```

(`ENV.fetch` makes the lane fail early rather than upload a build without
AI.) Builds made before the token existed send no `X-App-Token`, so they
lose AI analysis once the function is redeployed with it.

## Deploy (you run this; nothing here creates AWS resources by itself)

Before the first deploy (or the first one after 2026-11-04), store the
Anthropic key in Secrets Manager:

```bash
aws secretsmanager create-secret --region us-west-2 \
  --name mesh-analyzer-ai/anthropic-api-key \
  --secret-string 'sk-ant-...'
# note the ARN it prints
```

First deploy:

```bash
cd tool/ai-analysis
sam build
sam deploy --guided   # region: us-west-2
```

Answer the prompts: stack name `mesh-analyzer-ai`, region `us-west-2`,
allow SAM to create IAM roles, and "Function may not have authorization
defined, is this okay?" **y** (the Function URL is public; the app token
and the quotas protect it). For `AnthropicSecretArn` paste the secret's
ARN, for `AppToken` the token from [App token](#app-token) (the parameter
is `NoEcho`). Take the defaults for the limits and model (table above).

Later deploys (non-interactive; the stack keeps the stored secret ARN and
app token because they are not overridden):

```bash
cd tool/ai-analysis
sam build
sam deploy --no-confirm-changeset \
  --parameter-overrides DeviceDailyLimit=25 DeviceMonthlyLimit=300 IpDailyLimit=100 GlobalDailyLimit=2000 ModelId=claude-haiku-5-5
```

`--parameter-overrides` on the command line replaces the
`parameter_overrides` line in your local (git-ignored) `samconfig.toml`, so
list every limit you want. To keep them there instead, set that line to
`parameter_overrides = "DeviceDailyLimit=\"25\" DeviceMonthlyLimit=\"300\" IpDailyLimit=\"100\" GlobalDailyLimit=\"2000\" ModelId=\"claude-haiku-5-5\""`
and run `sam deploy --no-confirm-changeset`. Changing the model is the same
command with another `ModelId`.

The stack output `FunctionUrl` is the endpoint. Put it in
`lib/utils/constants.dart`:

```dart
static const String? aiAnalysisUrl = 'https://xxxxxxxx.lambda-url.us-west-2.on.aws/';
```

While it is `null` the app hides the whole feature and makes no request.
Also set `AppConstants.supportEmail` if you want "Report a problem" to open
Mail instead of the support page.

### Anthropic key

The stack passes only the secret's ARN (`ANTHROPIC_SECRET_ARN`) and grants
the function `secretsmanager:GetSecretValue` on that one secret; the key is
never a Lambda environment variable, so `GetFunctionConfiguration` and the
console do not show it. The handler reads either a bare key or
`{"ANTHROPIC_API_KEY": "..."}`. To rotate it:

```bash
aws secretsmanager put-secret-value --region us-west-2 \
  --secret-id mesh-analyzer-ai/anthropic-api-key --secret-string 'sk-ant-...'
```

A warm function keeps the old key until it is recycled; redeploy (or
change any setting) to pick up the new one at once. `ANTHROPIC_API_KEY` as
an environment variable is still read when no ARN is set, for local runs
only.

**Migrating the stack from before 2026-11-04** (it had the key as the
`AnthropicApiKey` parameter / `ANTHROPIC_API_KEY` variable): create the
secret above, then deploy once with the new parameters, which removes the
old variable:

```bash
sam build
sam deploy --no-confirm-changeset --parameter-overrides \
  AnthropicSecretArn=arn:aws:secretsmanager:us-west-2:...:secret:mesh-analyzer-ai/anthropic-api-key-xxxxxx \
  AppToken=<token> \
  DeviceDailyLimit=25 DeviceMonthlyLimit=300 IpDailyLimit=100 GlobalDailyLimit=2000 ModelId=claude-haiku-5-5
```

Then ship an app build made with the same token (see [App token](#app-token)).

Set a monthly spend limit in the Anthropic Console as a second backstop.

## Cost

Claude Haiku 5.5 is $0.10 per million input tokens and $0.50 per million
output tokens for prompts up to 100,000 tokens (Anthropic pricing page,
https://platform.claude.com/docs/en/about-claude/pricing, which redirects
from docs.anthropic.com; read 2026-10-16. Check it before launch).

A report is roughly 1,500 input tokens (system prompt plus digest) and 400
output tokens (`max_tokens` is 700):

- 1,500 x $0.10 / 1M = $0.00015
- 400 x $0.50 / 1M = $0.0002
- about **$0.00035 per report**, i.e. about $0.35 per 1,000 reports.

Worst case at the default caps: 2,000 analyses a day x ~$0.0005 (700 output
tokens) is about **$1 a day**, so the global cap bounds spend at roughly $30
a month even under abuse. One device at its limits costs at most about
1.3 cents a day (25 x ~$0.0005) and about 15 cents a month (300 x ~$0.0005). Lambda, DynamoDB (on-demand) and the
Function URL are cents per month at this volume and inside the free tier.

## Tests

```bash
cd tool/ai-analysis
python3 -m pip install pytest botocore
python3 -m pytest
# or, without installing anything:
uv run --python 3.12 --with pytest --with boto3 --with anthropic python -m pytest -q
```

The Anthropic client and DynamoDB are faked; no network, no AWS, no API key.
