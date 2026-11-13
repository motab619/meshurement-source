<!--
  Meshurement website - meshurement.com.
  Copyright (C) 2026 Andy Brunker (Plateau Nerd)
  SPDX-License-Identifier: GPL-3.0-or-later
  Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
-->
# meshurement.com

Static website for the app (landing, `/privacy`, `/support`). Plain HTML and CSS, no build step, no web fonts, no third-party requests.

- `public/`: what gets uploaded. Clean URLs (`/privacy`) map to `privacy/index.html` in a CloudFront Function.
- `template.yaml`: CloudFormation stack `meshurement-site` in us-east-1: private S3 bucket, CloudFront with Origin Access Control, ACM certificate (DNS-validated in hosted zone `Z0237707UGAMH4TWL4IA`), Route 53 A/AAAA aliases, a function that 301s `www` to the apex. The typo domain `meshurment.com` (zone `Z0181900TLOQVJYBGVSL`, plus `www`) has its own small distribution whose function 301s every request to `https://meshurement.com`, keeping the path. No WAF, no logs.
- `deploy.sh`: deploys the stack, syncs `public/` (HTML 5 min cache, assets 1 week) and invalidates CloudFront. `deploy.sh --files` skips the stack.
- `art/`: Andy's source artwork (icon, wordmark splash). `scripts/make_images.py` makes the web sizes, favicons and the Open Graph card:
  `/Applications/Xcode.app/Contents/Developer/usr/bin/python3 site/scripts/make_images.py site/art/icon.webp site/art/splash.webp site/public`

Local preview: `python3 -m http.server 4310 --directory site/public`.

Rules for the copy: plain sentences, no em-dashes. "Meshtastic" only as factual compatibility ("works with Meshtastic® radios"), never as branding, and every page footer carries the trademark notice.

The GitHub source link points at the public `motab619/meshurement-source` (release snapshots, 2026-11-13); the development repo `motab619/meshurement` stays private.
