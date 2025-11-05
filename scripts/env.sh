#!/usr/bin/env bash

# Non-secret defaults aligned with docs/infra-runbook.md v1.5
export AWS_PROFILE="${AWS_PROFILE:-tef-DevOps}"
export AWS_REGION="${AWS_REGION:-ap-southeast-2}"
export S3_BUCKET="${S3_BUCKET:-timfraser-ai-site-prod}"
export CLOUDFRONT_DISTRIBUTION_ID="${CLOUDFRONT_DISTRIBUTION_ID:-E1E824G2NW4BJJ}"
