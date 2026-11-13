# Ops tab: build plan

Target: `~/develop/office-plateaunerd`. Adds an **Ops** tab (last, after Jim)
backed by one collector Lambda, one summary Lambda and one DynamoDB table.
`concept.html` beside this file is the agreed layout; `README.md` lists the
data sources. This plan says how to build it, in deployable phases.

Everything follows the house rules in `.design/PATTERNS.md` and
`.design/DECISIONS.md`: ESM `.mjs` on `nodejs22.x`, DocumentClient,
`response(status, payload)`, the origin-aware CORS block from
`functions/hq-summary/index.mjs`, routes on the existing RestApi behind the
Cognito authorizer, no new API Gateway, no new frameworks. Solo user, keep
it small.

## 1. Shape

```
functions/ops-collect/     scheduled; fetches every source, writes pn-ops
functions/ops-summary/     GET /ops-summary, POST /ops/refresh, PUT /ops/checks/{id},
                           GET|PUT /ops/subscriptions
pn-ops (DynamoDB)          pk = item key, see §2
frontend/src/api/ops.js
frontend/src/components/Angela/Ops/   OpsSection.jsx + one file per panel
```

**Why a cache table.** Cost Explorer bills per call, App Store Connect
rate-limits, OSV batches are slow, and the page must open instantly and
keep working when a source is down. The collector pays those costs on a
schedule; the page reads the cache and shows "stale since …" per panel
when a fetch failed.

**Collector schedule.** One EventBridge rule, hourly
(`cron(7 * * * ? *)`, like `MonthlyOpsFunction`'s `Type: Schedule`). Each
source declares its own cadence; the collector skips a source whose
`fetched_at` is newer than that cadence unless `POST /ops/refresh`
invoked it with `{ panel }`. Timeout 300 s, 1024 MB. Sources run with
`Promise.allSettled`; one failure never blocks the others.

**Secrets** in SSM SecureString, same IAM shape as the Anthropic key
(`ssm:GetParameter` on the exact ARN plus `kms:Decrypt` on `alias/aws/ssm`):

| Parameter | Used for |
|---|---|
| `/office-plateaunerd/asc-key-id`, `/office-plateaunerd/asc-issuer-id`, `/office-plateaunerd/asc-private-key` | App Store Connect JWT (ES256, `node:crypto` `createSign('sha256')` with the `.p8`; no library needed) |
| `/office-plateaunerd/github-token` | Fine-grained token: Issues read on `motab619/beta-feedback`; Contents read and Dependabot alerts read on the app repos |
| `/office-plateaunerd/anthropic-admin-key` | Anthropic Admin API (`sk-ant-admin…`), cost and usage reports only |
| `/office-plateaunerd/cloudflare-token` | Phase C, Michelle's site analytics; optional |

## 2. `pn-ops` table

On-demand, PITR on like the others. Single partition key `pk` (string).
Items:

| pk | Written by | Body |
|---|---|---|
| `panel#<name>` | collector | `{ data, fetched_at, cadence_sec, error, error_at }` where `data` is the JSON that panel renders from. Names: `testflight`, `feedback`, `beta`, `repos`, `aws`, `anthropic`, `sites`, `visitors`, `inventory`, `advisories`, `posture`, `appstore` |
| `check#<advisory_id>` | summary (PUT) | `{ checked_at, checked_by, note }`. Advisory ids are stable: GHSA id, OSV id, `runtime:<fn>:<runtime>`, `patch:<instance>:<pkg>`, `posture:<rule>` |
| `subs` | summary (PUT) | `{ items: [{ name, amount_cents, period: monthly\|yearly, renews_on, note }] }` hand-entered |
| `meta#ce-calls#<YYYY-MM>` | collector | `{ count }` so the "47 Cost Explorer calls" escape can be computed from our own counter |

The `/ops-summary` response is `{ today, panels, generated_at }` where
`panels` is the raw `panel#*` map (each with `fetched_at`, `error`,
`stale`) and `today` is computed on read (§4). The frontend never
computes rankings.

## 3. Phases

Each phase deploys on its own (`sam build && sam deploy`, then the
frontend `npm run build`, `aws s3 sync`, CloudFront invalidation from
`CLAUDE.md`). Order is by value per unit of new credential.

### Phase A: skeleton, costs, Today (first deploy)

- `pn-ops` table, both Lambdas, the hourly rule, the four routes, IAM.
- Sources: **aws** (Cost Explorer: 12 months by `SERVICE`; MTD by
  `SERVICE` and by `Project` and `Client` tag; forecast via
  `GetCostForecast`; untagged spend mapped by the ownership table copied
  from `~/develop/aws-billing/CLAUDE.md` as a const, by resource-name
  pattern), **anthropic** (`GET /v1/organizations/cost_report` and
  `usage_report/messages` grouped by `api_key_id`, MTD; map key ids to
  labels in a const), **subs** (hand-entered via the page), plus the
  cost-escape rules (§4).
- IAM: `ce:GetCostAndUsage`, `ce:GetCostForecast`, `ec2:DescribeAddresses`,
  `ec2:DescribeInstances`, `cloudwatch:GetMetricStatistics` (idle check).
- Frontend: Ops tab, `OpsSection.jsx` with the Today grid (cost escapes
  filled, the other three panels rendering their empty state), the Costs
  section, the Sources footer. Charts as inline SVG drawn from data like
  the concept; no chart library.
- Cost of running it: Cost Explorer ~4 calls/day ≈ $1.20/month. Everything
  else free tier.

### Phase B: TestFlight, bugs, beta site

- **testflight**: `GET /v1/apps/6822128892/builds` (sort `-uploadedDate`,
  include `preReleaseVersion,buildBetaDetail`), `betaGroups`, `betaTesters`
  (with `betaTesterMetrics`/`betaBuildUsages` for installs, sessions,
  crashes per build and per tester; 7-day and 14-day windows), build
  expiry = uploadedDate + 90 d. Cadence 1 h.
- **feedback**: `GET /v1/apps/{id}/betaFeedbackScreenshotSubmissions` and
  `betaFeedbackCrashSubmissions`, include build, tester, device, OS; crash
  log via the relationship link, stored as text in `data`. Cadence 1 h.
  Verify the field names against the current ASC OpenAPI spec first; these
  endpoints were added in 2025 and the concept guessed their shape.
- **beta**: GitHub issues in `motab619/beta-feedback` by label (`bug`,
  `test-results`, `activity-log`, `tester-account`). Parse the JSON in the
  HTML comment of results and activity issues exactly as
  `~/develop/plateau-beta/lib/results.ts` and `lib/activity.ts` write it.
  Cadence 15 min.
- **repos**: open issue counts and last push for every non-archived repo
  from `GET /user/repos`; the Apps cards pick from them by name. Cadence 1 h.
- Frontend: Apps cards, App Store Connect section, Bugs section (merged
  list with source chips and filter), Today bugs panel.

### Phase C: sites and visitors

- **sites**: HEAD request per site with a 5 s timeout, status and latency,
  last deploy from CloudFront `GetDistribution` last-modified and Amplify
  `ListJobs`. The site list is a const with owner and hosting.
- **visitors**: daily unique client IPs for 30 days from CloudFront
  standard logs in `pn-client-site-logs-*` and the lygl bucket (us-west-2;
  the S3 client already uses `followRegionRedirects` in monthly-ops),
  after the same bot filter the health reports use. The filter lives in
  `functions/monthly-ops/report.mjs`; SAM packages each `CodeUri` alone,
  so copy the filter functions into `functions/ops-collect/botfilter.mjs`
  with a header comment naming the source, rather than building a Layer
  for one module. Amplify (beta site) from CloudWatch `Requests`.
  Cloudflare (Michelle) later, when the token exists. Cadence daily.
- IAM: reuse the log-bucket allowlist pattern from `MonthlyOpsFunction`.

### Phase D: security

- **inventory**, nightly:
  - Lambda runtimes from `lambda:ListFunctions` in us-east-1 and us-west-2
    (covers office, eliza, fileshare, storykit, ai-analysis without
    reading any repo).
  - Package manifests from GitHub Contents API: `package-lock.json`,
    `pubspec.lock`, `requirements.txt`, `docker-compose*.yml`, `Dockerfile`
    per repo. Parse to `{ ecosystem, name, version }` (npm, Pub, PyPI;
    Docker images as `{ image, tag }`).
  - Trails box: `ssm:ListInventoryEntries` (`AWS:Application`) and
    `ssm:DescribeInstancePatchStates`. Needs the SSM agent registered
    with an instance profile on `i-03d9786e973b77ed4`; until then the row
    shows "no inventory" rather than failing.
- **advisories**, nightly:
  - GitHub Dependabot alerts per repo (`GET /repos/{r}/dependabot/alerts?state=open`).
  - OSV `POST https://api.osv.dev/v1/querybatch` for every manifest entry
    (chunks of 1000), then `GET /v1/vulns/{id}` for matched ids to get
    severity and fixed versions.
  - Runtime support dates from `https://endoflife.date/api/aws-lambda.json`,
    `nodejs.json`, `python.json`, `postgresql.json`, `ubuntu.json`,
    `nextjs.json`. AWS Health was in the concept but its API needs a
    Business support plan; endoflife.date covers the deprecation dates.
  - CISA KEV (`known_exploited_vulnerabilities.json`) to flag matches.
  - Severity normalised to critical/high/moderate/info; each advisory gets
    the stable id from §2 so `check#` items survive refetches.
- **posture**, daily: `iam:GenerateCredentialReport`/`GetCredentialReport`
  (root MFA, access key ages), `ec2:DescribeSecurityGroups` (0.0.0.0/0 on
  22), `guardduty:ListDetectors` + `GetFindingsStatistics`,
  `cloudtrail:DescribeTrails` + `GetTrailStatus`,
  `s3:GetAccountPublicAccessBlock`, `acm:ListCertificates` +
  `DescribeCertificate` (expiry), SSM parameter `LastModifiedDate` for the
  dashboard's own key ages.
- Frontend: Security section (inventory search box, advisories with Mark
  checked, posture list), Today security panel.

### Phase E: App Store after launch (not before submission)

`analyticsReportRequests` (ONGOING) and the report instance CSVs,
`salesReports` SUBSCRIPTION and SUBSCRIPTION_EVENT, `customerReviews`,
`appStoreVersions` state. Replaces the greyed tiles. The ASC key needs
Sales and Finance access for the reports; the fastlane key is Admin, which
covers it.

## 4. Computed on read: Today and the escapes

Pure functions in `functions/ops-summary/rank.mjs`, unit-tested with
`node --test` (the repo has no tests yet; keep these pure and separate so
they can be).

- **Top bugs**: open items from `feedback` (crash first), failed test cases
  from `beta`, open `bug` issues. Score = severity (crash 3, failed test 2,
  report 1) then build recency then age. Four shown.
- **Top security**: advisories without a `check#` item, severity then
  KEV-listed first, then posture warnings. Four shown.
- **Top cost escapes**, each a rule with a dollar figure:
  1. Elastic IP not associated with a running instance (`DescribeAddresses`): $3.60/mo.
  2. EC2 instance with 7-day average CPU under 2 %: its MTD cost.
  3. Anthropic forecast (MTD ÷ day-of-month × days) above 50 % of the $10 budget: the overage.
  4. Any service whose MTD is 1.5× its 3-month average and at least $1 over.
  5. Usage types containing `EarlyDelete`, `Retrieval`, `Requests-Tier` above $0.50.
  6. Cost Explorer calls this month over 5 per day, from the `meta#ce-calls` counter.
  Header total = the sum of items already on the bill (not forecasts).
- **Top development needs**: `pn-projects` milestones not done and due
  within 14 days; GitHub issues labelled `next`; derived items: a crash
  bug, a high advisory, an escape above $2/mo each produce one need that
  links to its source. Ranked by due date, then by how many other lists
  the item clears.

## 5. Frontend notes

- `OpsSection.jsx` fetches `/ops-summary` once on mount and on Refresh,
  the same loading/error shape as `HqSection.jsx`. Set the auth token
  during render, never in an effect (the HQ "Failed to fetch" lesson in
  `CLAUDE.md`).
- Per-panel header shows `fetched_at` and a stale marker when `error` is
  set; a Refresh button per panel calls `POST /ops/refresh` with the panel
  name and then re-reads.
- Styles go into `index.css` under an `/* ---- Ops ---- */` block using
  the concept's class names (`.top`, `.toplist`, `.tile`, `.src`, `.sev-*`,
  `.spark`). The tokens already match.
- Tab order becomes
  `['HQ','Invoices','Proposals','Expenses','Time','Projects','Clients','Jim','Ops']`.

## 6. Decisions for Andy before Phase B and D

1. **App Store Connect key.** Reuse the fastlane key (Admin role) or
   create a second key with App Manager + Sales for the dashboard? Reuse
   is one less secret; a second key limits what a leaked dashboard key
   can do. Recommendation: second key, App Manager role, since Admin can
   change pricing.
2. **GitHub token.** A fine-grained token scoped to the repos above with
   Issues read, Contents read, Dependabot alerts read. Enable Dependabot
   alerts on every repo first (Settings → Security on each).
3. **Trails box.** Attach an instance profile with `AmazonSSMManagedInstanceCore`
   and confirm the agent is running, or the host inventory stays empty.
   Also fixes the "SSH open to the world" finding later, since Session
   Manager replaces the open port.
4. **Claude plan amount** and renewal dates for the subscriptions panel.
5. **Anthropic Admin key.** Create it in the console (Organization →
   Admin keys), not a workspace key.

### Answers so far (2026-10-26)

- **5, Anthropic Admin key: done.** The Console org was converted from
  individual to team (needed for Admin keys). Key "office ops dashboard",
  one-year expiry, stored at SSM `/office-plateaunerd/anthropic-admin-key`
  (version 1, us-east-1). Still to check: that office receipts, office AI
  commentary and the Mesh ai-analysis Lambda each use their own API key,
  so the cost report splits by use.
- **4, subscriptions:** Claude Max 5x, $100.00 monthly, next bill
  13 Nov 2026. Domains need no manual row: Route 53 `list-domains` gives
  expiry and auto-renew for all eight (next due plateaunerd.com and
  theplateaunerd.com 2 Apr 2027, lcpoatrails.org 6 Mar 2027); add that
  call to the collector's `aws` source. lindibooks.org is registered
  elsewhere (Lindi's), manual row if wanted. Apple Developer Program: $99.00 yearly,
  renews 21 Jul 2027. Decision 4 is complete.
- **1, App Store Connect key: done.** New team key "office ops dashboard",
  key id GGV8V5U5V9, App Manager access (not Admin). Stored in SSM
  us-east-1: `/office-plateaunerd/asc-private-key` (SecureString, the
  .p8 contents), `/office-plateaunerd/asc-key-id`,
  `/office-plateaunerd/asc-issuer-id`. The .p8 file is kept at
  `~/.config/plateaunerd/`. Phase E will need Sales and Finance access,
  which can't be added to an existing key: create a second key then.
- **2, GitHub token: done.** Fine-grained token "office ops dashboard",
  one-year expiry, **All repositories** (decided over a fixed list so new
  repos are covered automatically), read-only Contents, Issues and
  Dependabot alerts. Stored at SSM `/office-plateaunerd/github-token`
  (version 1). Dependabot alerts enabled on all 15 non-archived repos on
  2026-10-26. Consequence for the collector: list repos with
  `GET /user/repos` (owner motab619), skip archived, and inventory every
  one; the Apps cards stay a hand-picked const.
- **3, trails box SSM: done 2026-10-26.** IAM role and instance profile
  `pn-trails-ssm` (policy `AmazonSSMManagedInstanceCore`, tagged
  `Project=lcpoa-trails`) associated with `i-03d9786e973b77ed4` (Ubuntu
  24.04, t3.small, us-east-1). Undo: disassociate the profile, delete the
  profile and role. The agent needed `sudo snap restart amazon-ssm-agent`
  to pick up the identity; it then showed Online (agent 3.3.4793.0).
  Two State Manager associations were then created on the instance:
  `pn-trails-inventory` (`AWS-GatherSoftwareInventory`, every 30 min,
  id 05d56304-a399-4b8c-9bed-defdf50e1611) and `pn-trails-patch-scan`
  (`AWS-RunPatchBaseline`, `Operation=Scan`, daily 11:00 UTC, id
  9f844e8a-d5e7-4ac2-ae08-cb2c78a0aea1; scan only, installs nothing).
  First run 2026-10-26: 695 installed packages (openssl
  3.0.13-0ubuntu3.16, docker-ce 29.3.0), patch state Missing 1
  (libbrotli1 security, optional), Installed 57, **InstalledPendingReboot
  172**: the box has taken updates but not rebooted, so the posture panel
  should show "reboot pending" as a warning, not just the missing count.
  Collector reads: `ListInventoryEntries` (AWS:Application, paginated,
  50 per page) and `DescribeInstancePatchStates` /
  `DescribeInstancePatches` (State=Missing). Real posture facts found while doing it, which differ
  from the concept's sample data: SSH (port 22) is already restricted to
  47.144.0.0/16, not open to the world; there are no unattached Elastic
  IPs. The posture rules stay as written; those two will simply report OK.

## 7. Verification per phase

- `sam build && sam deploy`, then `aws lambda invoke --function-name
  pn-office-ops-collect --payload '{"panel":"aws"}' out.json` and read the
  `panel#aws` item.
- `curl` `/ops-summary` with a Cognito ID token from the browser dev tools,
  check `today` and `panels.*.fetched_at`.
- `npm run dev` on the frontend, open the Ops tab; then the S3 sync and
  invalidation, and confirm the new `assets/index-*.js` hash in the page
  source before judging the deploy.
- Before merging Phase D: run the inventory against the real repos and
  confirm "PHP" returns nothing and "openssl" returns the trails box.

## 8. Effort

| Phase | New code | Rough size |
|---|---|---|
| A | table, 2 Lambdas, tab, Costs, Today shell | 1 day |
| B | ASC client, GitHub client, Apps + ASC + Bugs sections | 1–2 days |
| C | health, visitors, sparklines | half a day |
| D | inventory, OSV, Dependabot, posture, Security section | 1–2 days |
| E | App Store reports | half a day, after submission |
