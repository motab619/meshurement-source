#!/usr/bin/env bash
# Meshurement website - meshurement.com.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
#
# Deploy the meshurement.com stack and upload the site.
#   site/deploy.sh          # stack (if changed) + upload + invalidate
#   site/deploy.sh --files  # upload + invalidate only
# Uses the default AWS CLI credentials (the CLIDeploy user). Everything runs in us-east-1.
set -euo pipefail

STACK=meshurement-site
REGION=us-east-1
HERE="$(cd "$(dirname "$0")" && pwd)"

if [[ "${1:-}" != "--files" ]]; then
  echo "== CloudFormation: $STACK (first run waits for ACM DNS validation and CloudFront, ~5-15 min)"
  aws cloudformation deploy \
    --region "$REGION" \
    --stack-name "$STACK" \
    --template-file "$HERE/template.yaml" \
    --no-fail-on-empty-changeset
fi

out() {
  aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}
BUCKET="$(out BucketName)"
DIST="$(out DistributionId)"

echo "== Upload to s3://$BUCKET"
# Images, CSS and icons: cache a week. HTML and text: 5 minutes, so edits show up quickly.
aws s3 sync "$HERE/public" "s3://$BUCKET" --region "$REGION" --delete \
  --exclude "*.html" --exclude "*.txt" --exclude "*.xml" \
  --cache-control "public, max-age=604800"
aws s3 sync "$HERE/public" "s3://$BUCKET" --region "$REGION" --delete \
  --exclude "*" --include "*.html" --include "*.txt" --include "*.xml" \
  --cache-control "public, max-age=300"

echo "== Invalidate CloudFront $DIST"
aws cloudfront create-invalidation --distribution-id "$DIST" --paths "/*" \
  --query "Invalidation.Id" --output text

echo "Done: https://meshurement.com"
