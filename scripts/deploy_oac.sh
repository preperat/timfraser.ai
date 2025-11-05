#!/usr/bin/env bash
set -euo pipefail

export AWS_REGION=ap-southeast-2
export AWS_PROFILE=tef-DevOps
bucket="timfraser-ai-site-prod"

aws --version >/dev/null
aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null

echo "Syncing site content to s3://$bucket/ (private objects)"
aws s3 sync public/ "s3://$bucket/" \
  --delete \
  --acl private \
  --cache-control "max-age=300,public" \
  --profile "$AWS_PROFILE"

echo "Ensuring CloudFront Origin Access Control (OAC) exists..."
OAC_ID=$(aws cloudfront list-origin-access-controls \
  --query "OriginAccessControlList.Items[?Name=='timfraser-ai-oac'].Id | [0]" \
  --output text)

if [ "$OAC_ID" = "None" ] || [ -z "$OAC_ID" ]; then
  echo "Creating OAC timfraser-ai-oac..."
  OAC_ID=$(aws cloudfront create-origin-access-control \
    --origin-access-control-config '{
      "Name":"timfraser-ai-oac",
      "Description":"OAC for timfraser-ai-site-prod",
      "SigningProtocol":"sigv4",
      "SigningBehavior":"always",
      "OriginAccessControlOriginType":"s3"
    }' \
    --query 'OriginAccessControl.Id' --output text)
  echo "Created OAC: $OAC_ID"
else
  echo "Found existing OAC: $OAC_ID"
fi

DISTCFG="distribution-config.json"
cat > "$DISTCFG" <<JSON
{
  "CallerReference": "timfraser-ai-$(date +%s)",
  "Comment": "timfraser.ai static site",
  "Enabled": true,
  "Origins": {
    "Items": [
      {
        "Id": "s3-origin",
        "DomainName": "${bucket}.s3.${AWS_REGION}.amazonaws.com",
        "OriginAccessControlId": "${OAC_ID}",
        "S3OriginConfig": { "OriginAccessIdentity": "" }
      }
    ],
    "Quantity": 1
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "s3-origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": { "Items": ["GET", "HEAD"], "Quantity": 2 },
    "Compress": true,
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6"
  },
  "DefaultRootObject": "index.html",
  "PriceClass": "PriceClass_200",
  "ViewerCertificate": { "CloudFrontDefaultCertificate": true }
}
JSON

aws cloudfront create-distribution --distribution-config file://"$DISTCFG" > cf-create-out.json
if [ ! -s cf-create-out.json ]; then
  echo "ERROR: create-distribution did not return output. See CLI error above." >&2
  exit 4
fi
CF_DIST_ID=$(python3 - <<'PY'
import sys, json
j=json.load(open('cf-create-out.json'))
print(j["Distribution"]["Id"]) 
PY
)
CF_DOMAIN=$(python3 - <<'PY'
import sys, json
j=json.load(open('cf-create-out.json'))
print(j["Distribution"]["DomainName"]) 
PY
)

echo "Created CloudFront distribution: $CF_DIST_ID"
[ -n "${CF_DOMAIN:-}" ] && echo "Domain: https://$CF_DOMAIN"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile "$AWS_PROFILE")
cat > oac-bucket-policy.json <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServiceGetObjectOAC",
      "Effect": "Allow",
      "Principal": { "Service": "cloudfront.amazonaws.com" },
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::${bucket}/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${CF_DIST_ID}"
        }
      }
    }
  ]
}
POLICY

aws s3api put-bucket-policy \
  --bucket "$bucket" \
  --policy file://oac-bucket-policy.json \
  --profile "$AWS_PROFILE"

echo "All set. Distribution will take a few minutes to deploy."
[ -n "${CF_DOMAIN:-}" ] && echo "Test URL: https://${CF_DOMAIN}"


