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
- Current status: OAC created, CloudFront distribution provisioned, bucket policy grants CloudFront service read access via `AWS:SourceArn`.

---

## Build & Deploy — Setup Plan (S3 + GitHub Actions)

### A) CloudShell Environment Setup

> Open **AWS CloudShell** in **ap-southeast-2 (Sydney)**. Use **session-only** environment variables; do **not** persist config.

```bash
export AWS_REGION=ap-southeast-2
export AWS_PROFILE=tef-DevOps
# No aws configure writes; we pass --profile explicitly per command
```

### B) Create S3 Bucket (no public access)

```bash
aws s3api create-bucket \
  --bucket timfraser-ai-site-prod \
  --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION" \
  --profile "$AWS_PROFILE"
```

Notes:
- Keep S3 Block Public Access ON (default). We serve via CloudFront + OAC, not S3 Website.
- Run `bash scripts/deploy_oac.sh` to create/update the CloudFront distribution and attach the OAC bucket policy.

### C) GitHub Repo & Bootstrap (CloudShell)

Generate SSH key, add to GitHub, then bootstrap the repo:

```bash
git config --global user.name "Tim Fraser"
git config --global user.email "you@example.com"
ssh-keygen -t ed25519 -C "you@example.com" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub
```

Add the printed public key to GitHub → **Settings → SSH and GPG keys → New SSH key**.

Then:

```bash
mkdir timfraser-ai-site && cd timfraser-ai-site
printf "# timfraser.ai
" > README.md
printf "node_modules
.DS_Store
.next
out
" > .gitignore
mkdir public && printf "<!doctype html><meta charset=\"utf-8\"><title>timfraser.ai</title><h1>timfraser.ai</h1>" > public/index.html

git init && git branch -M main
git remote add origin git@github.com:<your-username>/timfraser-ai-site.git
git add . && git commit -m "chore: bootstrap" && git push -u origin main
```

### D) GitHub Actions Secrets

Configure in repo → **Settings → Secrets and variables → Actions**

```
AWS_ACCESS_KEY_ID = ***
AWS_SECRET_ACCESS_KEY = ***
AWS_REGION = ap-southeast-2
S3_BUCKET = timfraser-ai-site-prod
```

### E) Workflow `.github/workflows/deploy-to-s3.yml`

```yaml
name: Deploy to S3 (static site)

on:
  push:
    branches: [ main ]

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Sync public/ to S3
        run: |
          aws s3 sync public/ s3://${{ secrets.S3_BUCKET }}/ \
            --delete \
            --cache-control max-age=300,public
```

### F) Cursor Terminal notes

* Using a dedicated profile (`tef-DevOps`) keeps **recorded commands** consistent in Cursor’s terminal history.
* Prefer **env vars + `--profile` per command** over persistent `aws configure` writes.
* If you later use multiple profiles from Cursor, add per-project `.envrc` (direnv) or a `scripts/alias.sh` with `AWS_PROFILE` exports.

### G) Smoke Test

After pushing to `main`, verify that GitHub Actions runs and that the CloudFront domain (from the console or script output) serves `index.html`.

---

## Cursor IDE Handover

**Goal:** move this deployment workflow into your Cursor IDE environment.

**Steps:**

1. **Create folder** `/Users/tef/Library/CloudStorage/GoogleDrive-admin@addabattery.com.au/Shared drives/Projects/timfraser.ai` and open it in Cursor.
2. **Connect to GitHub:**

   ```bash
   git clone git@github.com:<your-username>/timfraser-ai-site.git
   cd timfraser-ai-site
   ```
3. **Ensure AWS credentials** are available in your Cursor terminal session:

   ```bash
   export AWS_PROFILE=tef-DevOps
   export AWS_REGION=ap-southeast-2
   ```
4. **Run CloudShell CLI equivalents** directly in Cursor’s integrated terminal or through VSCode tasks:

   * Create / verify the S3 bucket
   * Apply CloudFront + OAC configuration (from earlier runbook)
   * Push first commit → confirm GitHub Actions triggers deployment
5. **Verify deployment:** once Actions complete, open the CloudFront domain (or S3 endpoint) to confirm content loads.
6. **Commit this document** (`Timfraser.md`) to the repo as `/docs/infra-runbook.md` for ongoing reference.

**Notes for Cursor:**

* Cursor automatically tracks command history; commands run here will appear under `AWS_PROFILE=tef-DevOps` context.
* You can create a `.env` file with:

  ```bash
  AWS_PROFILE=tef-DevOps
  AWS_REGION=ap-southeast-2
  ```

  and Cursor will load it per workspace.
* When switching between projects, verify the active profile with:

  ```bash
  aws sts get-caller-identity --profile tef-DevOps
  ```


