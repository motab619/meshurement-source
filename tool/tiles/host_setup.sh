#!/usr/bin/env bash
# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
#
# One-shot hosting setup for the PMTiles: private S3 bucket + CloudFront
# distribution with Origin Access Control, in us-west-2. Re-runnable: each
# step is skipped when the resource already exists. Writes the ids to
# $MESH_TILES_DIR/host.env for upload.sh.
#
# Privacy by construction: no S3 access logging and no CloudFront standard
# logging are enabled, so the tile server keeps no record of who viewed
# which map area (the privacy policy says so).
#
#   bash tool/tiles/host_setup.sh            # bucket plateaunerd-mesh-tiles
#   BUCKET=my-bucket bash tool/tiles/host_setup.sh
set -euo pipefail
export AWS_REGION=us-west-2
BUCKET="${BUCKET:-plateaunerd-mesh-tiles}"
MESH_TILES_DIR="${MESH_TILES_DIR:-$HOME/mesh-tiles}"
ENV_FILE="$MESH_TILES_DIR/host.env"
mkdir -p "$MESH_TILES_DIR"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "account $ACCOUNT_ID, bucket $BUCKET"

# 1. Private bucket.
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "bucket exists"
else
  aws s3api create-bucket --bucket "$BUCKET" --region us-west-2 \
    --create-bucket-configuration LocationConstraint=us-west-2 >/dev/null
  echo "bucket created"
fi
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# 2. Origin Access Control (reuse by name).
OAC_ID=$(aws cloudfront list-origin-access-controls \
  --query "OriginAccessControlList.Items[?Name=='mesh-tiles-oac'].Id | [0]" --output text)
if [ -z "$OAC_ID" ] || [ "$OAC_ID" = "None" ]; then
  OAC_ID=$(aws cloudfront create-origin-access-control \
    --origin-access-control-config \
    Name=mesh-tiles-oac,SigningProtocol=sigv4,SigningBehavior=always,OriginAccessControlOriginType=s3 \
    --query OriginAccessControl.Id --output text)
  echo "OAC created $OAC_ID"
else
  echo "OAC exists $OAC_ID"
fi

# 3. Distribution (reuse by comment).
COMMENT="Meshurement map tiles (PMTiles)"
DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='$COMMENT'].Id | [0]" --output text 2>/dev/null || true)
if [ -z "$DIST_ID" ] || [ "$DIST_ID" = "None" ]; then
  cat > /tmp/mesh-tiles-dist.json <<JSON
{
  "CallerReference": "mesh-tiles-$(date +%s)",
  "Comment": "$COMMENT",
  "Enabled": true,
  "HttpVersion": "http2and3",
  "PriceClass": "PriceClass_100",
  "Logging": { "Enabled": false, "IncludeCookies": false, "Bucket": "", "Prefix": "" },
  "Origins": { "Quantity": 1, "Items": [{
    "Id": "s3-mesh-tiles",
    "DomainName": "$BUCKET.s3.us-west-2.amazonaws.com",
    "OriginAccessControlId": "$OAC_ID",
    "S3OriginConfig": { "OriginAccessIdentity": "" }
  }]},
  "DefaultCacheBehavior": {
    "TargetOriginId": "s3-mesh-tiles",
    "ViewerProtocolPolicy": "https-only",
    "AllowedMethods": { "Quantity": 2, "Items": ["GET", "HEAD"],
      "CachedMethods": { "Quantity": 2, "Items": ["GET", "HEAD"] } },
    "Compress": false,
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
    "ResponseHeadersPolicyId": "60669652-455b-4ae9-85a4-c4c02393f86c"
  }
}
JSON
  DIST_ID=$(aws cloudfront create-distribution \
    --distribution-config file:///tmp/mesh-tiles-dist.json \
    --query Distribution.Id --output text)
  echo "distribution created $DIST_ID"
else
  echo "distribution exists $DIST_ID"
fi
DOMAIN=$(aws cloudfront get-distribution --id "$DIST_ID" \
  --query Distribution.DomainName --output text)

# 4. Only this distribution may read the bucket.
cat > /tmp/mesh-tiles-policy.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "CloudFrontOAC",
    "Effect": "Allow",
    "Principal": { "Service": "cloudfront.amazonaws.com" },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::$BUCKET/*",
    "Condition": { "StringEquals": {
      "AWS:SourceArn": "arn:aws:cloudfront::$ACCOUNT_ID:distribution/$DIST_ID" } }
  }]
}
JSON
aws s3api put-bucket-policy --bucket "$BUCKET" --policy file:///tmp/mesh-tiles-policy.json

cat > "$ENV_FILE" <<EOF
BUCKET=$BUCKET
DIST_ID=$DIST_ID
DOMAIN=$DOMAIN
EOF
echo
echo "tiles host: https://$DOMAIN  (saved to $ENV_FILE)"
echo "next: bash tool/tiles/upload.sh socal v1"
