# Ops dashboard concept

`concept.html` is a static mock of an **Ops** tab for office.plateaunerd.com.
Every number on it is a sample. It exists to agree on *what* the page shows
before any of it is wired to a live source.

The eventual home is `~/develop/office-plateaunerd` (React + Vite frontend,
SAM backend, Cognito auth). The mock uses that app's CSS tokens so a port is
mostly a matter of splitting it into components.

## What the page answers, top to bottom

1. **Today.** Four ranked lists of four, one per concern, each the top of
   its section below: top bugs, top security findings, top cost escapes
   (spend outside plan: an idle resource, a forecast crossing a budget, a
   one-off fee, a runaway API) and top development needs. Development
   needs are drawn from Projects milestones, GitHub issues, and the other
   three lists, ranked by deadline then by what they unblock.
2. **Apps.** One card per thing you ship (Meshurement, Coachella Mesh,
   Lumen, beta site) plus a table of every live site with health, last
   deploy, month-to-date cost and the owner used for the cost split.
3. **Meshurement, App Store Connect.** TestFlight numbers now; the App
   Store tiles (downloads, Pro trials, proceeds, ratings) are drawn greyed
   until the app is on sale.
4. **Bugs and feedback.** One list merging TestFlight screenshot feedback,
   TestFlight crash feedback, beta-site bug reports and failed test cases,
   with build adoption and test-plan progress beside it.
5. **Security.** Three questions, in order: is this thing in the news in
   my stack at all (a search box over a nightly inventory of every runtime,
   framework, package and host package you run); which published advisories
   match a version I actually run (a table with a "Mark checked" button so
   you can see what you have and have not looked at); and is the account
   itself in order (MFA, CloudTrail, GuardDuty, open security groups, key
   ages, cert expiry, pending host patches).
6. **Costs.** AWS by owner for 12 months (same split as `~/develop/aws-billing`),
   Anthropic API by API key against the $10 budget alert, and hand-entered
   fixed subscriptions with renewal dates.
7. **Sources.** Which API feeds each panel and how often.

## How you would hear about "the PHP issue"

Awareness comes from matching, not from reading news. The collector builds
an inventory every night, then matches advisory feeds against it:

1. **Inventory.** From each repo: `package-lock.json`, `pubspec.lock`,
   `requirements.txt`, the `Runtime:` in every SAM template, Docker image
   tags in compose files and Dockerfiles. From the trails EC2 box: the
   installed-package list via SSM Inventory (the SSM agent is on Ubuntu
   images by default). This is the list of what you actually run. Today it
   contains no PHP, so a PHP advisory shows as "not in your stack".
2. **Feeds matched against it.**
   - GitHub Dependabot alerts, per repo (free on private repos; enable it on
     every repo, the concept shows 11 of 15).
   - OSV.dev batch query (`POST /v1/querybatch`) for every package and
     version in the inventory. Covers npm, PyPI, pub.dev, Ubuntu, Debian
     and container base images. Free, no key.
   - AWS Health API events for the account: Lambda runtime deprecations,
     security bulletins for services you use.
   - CISA Known Exploited Vulnerabilities feed, to flag a match as actively
     exploited.
   - endoflife.date API for support-end dates of runtimes and frameworks.
3. **Account posture** from read-only AWS calls: IAM credential report (key
   ages, root MFA), Security Group rules, GuardDuty and CloudTrail status,
   S3 account public-access block, ACM certificate expiry, SSM patch
   compliance for the box.

A match lands in the advisories table and in Needs attention. "Mark checked"
writes who looked and when, so an advisory never silently disappears.

Caveat: the trails box runs production from an uncommitted working tree
built into Docker on the host, so its Node image version is only knowable
from the box itself, not from the repo. SSM Inventory covers the Ubuntu
packages; the container images need a `docker image ls` step in the same
collector, or the box moving to a committed deploy first.

## Data sources

| Panel | Source | Notes |
|---|---|---|
| TestFlight builds, testers, usage | App Store Connect API: `builds`, `betaGroups`, `betaTesters`, `GET /v1/builds/{id}/metrics/betaBuildUsages`, `GET /v1/betaTesters/{id}/metrics/betaTesterUsages` | Key already exists in `ios/fastlane/.env`; spaceship recipe in memory `asc-api-via-spaceship`. App id 6822128892. |
| TestFlight feedback | `GET /v1/apps/{id}/betaFeedbackScreenshotSubmissions`, `GET /v1/apps/{id}/betaFeedbackCrashSubmissions` (+ `/crashLog`) | Added to the ASC API in 2025; the same data Xcode Organizer shows. Verify the field names against the current OpenAPI spec before building. |
| App Store, after launch | `analyticsReportRequests` (ONGOING) → reports → instances → segments CSV; `salesReports` (SUBSCRIPTION, SUBSCRIPTION_EVENT); `customerReviews`; `appStoreVersions` state | Reports are CSV, daily, a day or two behind. |
| Beta site | GitHub issues in `motab619/beta-feedback` (labels `bug`, `test-results`, `activity-log`, `tester-account`, `name-idea`) | Formats are documented in `~/develop/plateau-beta/CLAUDE.md`; results JSON sits in an HTML comment. |
| Other repos | GitHub REST: open issues, last push, per repo | |
| AWS | Cost Explorer `get-cost-and-usage` by SERVICE and by `Project` / `Client` tag; ownership fallback table from `~/develop/aws-billing/CLAUDE.md` | $0.01 per request, so fetch once a day and cache. Activate the cost allocation tags first. |
| Anthropic | Admin API `GET /v1/organizations/cost_report` and `usage_report/messages`, grouped by `api_key_id` | Needs an **Admin** API key (separate from the per-project keys), stored in SSM. One API key per use (office receipts, office insights, mesh `tool/ai-analysis`). |
| Site health | HEAD request per site; last CloudFront invalidation / Amplify job | |
| Visitors, 30 days | CloudFront standard logs already landing in `pn-client-site-logs-*` (and the lygl bucket in us-west-2): daily unique IPs after the monthly-ops bot filter. Amplify sites (beta) from CloudWatch request metrics. Cloudflare-hosted sites (Michelle) from the Cloudflare analytics API. | The bot filter code lives in `functions/monthly-ops/`; reuse it rather than re-implementing. Sites with no logging yet show "no logs". |
| Subscriptions | DynamoDB rows, hand-entered | Claude plan, Apple Developer Program, domains, Atlas/RunPod. |

## Suggested build

- `functions/ops-collect/`: one Lambda on an EventBridge schedule (hourly;
  the daily-only sources check a "last fetched" stamp) writing into a
  `pn-ops-cache` table, one item per panel, with the fetch time and any
  error so the page can show "stale since …" instead of failing.
- `GET /ops-summary`: reads the cache, same shape as `/hq-summary`.
- Frontend: an **Ops** tab after HQ, one component per section above.
- Secrets in SSM SecureString: ASC `.p8` + key id + issuer, GitHub token,
  Anthropic Admin key.
