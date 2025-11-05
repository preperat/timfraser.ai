# timfraser.ai — Working Notes & Decisions

**Version:** v1.5 — 2025-11-05 (AEST)

---

**Changelog**

* v1.5: Removed `aws configure set ...` to avoid persistent profile edits. All commands now use **session-only** `export AWS_PROFILE=tef-DevOps` + `--profile tef-DevOps`. Added **Cursor Terminal notes** about command history and environment isolation.
* v1.4: Updated all CLI examples to explicitly use AWS CloudShell and the `--profile tef-DevOps` flag for clarity and consistency. Cleaned duplicate command blocks and verified syntax.
* v1.3: Updated all terminal commands to AWS CloudShell CLI flow (no local keys). Added region export, SSH key setup for GitHub from CloudShell, and clarified S3 create-bucket for ap-southeast-2.
* v1.2: Added end-to-end S3 + GitHub Actions runbook, bucket policy JSON, GitHub workflow YAML, and local bootstrap commands. Added security note to rotate the pasted GitHub token and store secrets only in GH Actions.
* v1.1: Added Build & Deploy setup plan (S3 + GitHub Actions), initial repo checklist, and TODOs.
* v1.0: Initial consolidated draft.

---

## Decisions & Status (TL;DR)

- Delivery: Use CloudFront + Origin Access Control (OAC) in front of a private S3 bucket. S3 Block Public Access remains ON; no public bucket policy or S3 Website hosting required.
- Repo layout: Static site lives at the repo root (`public/`, `.github/`, `scripts/`, `docs/`).
- Credentials: Prefer session env vars and GitHub Actions secrets. Avoid persistent `aws configure` writes.
- Current status: OAC created, CloudFront distribution provisioned, bucket policy grants CloudFront service read access via `AWS:SourceArn`. Workflow invalidates CloudFront after sync.

---

## Build & Deploy — Setup (S3 + GitHub Actions)

This repo is already wired. Pushing to `master` deploys the `public/` folder to S3 and invalidates CloudFront.

### S3/CloudFront

- S3 bucket: `timfraser-ai-site-prod` (private; Block Public Access ON)
- CloudFront distribution: `E1E824G2NW4BJJ` (OAC to S3)

### GitHub repo
Branch: `master`. Pushing commits triggers deployment.

### D) GitHub Actions Secrets

Configure in repo → **Settings → Secrets and variables → Actions**

```
AWS_ACCESS_KEY_ID = ***
AWS_SECRET_ACCESS_KEY = ***
AWS_REGION = ap-southeast-2
S3_BUCKET = timfraser-ai-site-prod
CLOUDFRONT_DISTRIBUTION_ID = E1E824G2NW4BJJ
```

### Workflow `.github/workflows/deploy-to-s3.yml`

```yaml
name: Deploy to S3 (static site)

on:
  push:
    branches: [ master ]

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    env:
      AWS_REGION: ${{ secrets.AWS_REGION }}
      S3_BUCKET: ${{ secrets.S3_BUCKET }}
      CLOUDFRONT_DISTRIBUTION_ID: ${{ secrets.CLOUDFRONT_DISTRIBUTION_ID }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Resolve config
        run: |
          echo "EFFECTIVE_S3_BUCKET=${S3_BUCKET:-timfraser-ai-site-prod}" >> $GITHUB_ENV
          echo "EFFECTIVE_CF_DIST_ID=${CLOUDFRONT_DISTRIBUTION_ID:-E1E824G2NW4BJJ}" >> $GITHUB_ENV

      - name: Sync public/ to S3
        run: |
          aws s3 sync public/ s3://${EFFECTIVE_S3_BUCKET}/ \
            --delete \
            --cache-control max-age=300,public

      - name: Invalidate CloudFront cache
        run: |
          aws cloudfront create-invalidation \
            --distribution-id "$EFFECTIVE_CF_DIST_ID" \
            --paths '/*'
```

### Notes

* No public S3 access or website hosting is used; all traffic goes via CloudFront + OAC.
* Keep credentials in GitHub Actions secrets; `.env` is for local convenience and is gitignored.

### G) Smoke Test

After pushing to `master`, verify that GitHub Actions runs and that the CloudFront domain (from the console or script output) serves `index.html`.

---

## How to deploy

1. Edit files under `public/`.
2. Commit to `master` and push (token or SSH).
3. Wait for Actions to complete, then hard-refresh CloudFront: `https://d31bibapqxst6.cloudfront.net`.


