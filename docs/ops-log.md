## [2025-11-06 01:52 +07] Session: CURSOR
Context:
- Codex batch applied; syncing on branch infra/codex-sync-20251106-0148.

Decisions:
- Keep S3 private behind CloudFront OAC.
- PR-first into master.

Files changed (summary):
- .github/workflows/deploy-to-s3.yml
- .cursorrules
- .github/pull_request_template.md
- .vscode/tasks.json
- scripts/env.sh

Commands applied:
- none (file edits)

Next actions:
1) Review PR diffs.
2) Merge to master if checks pass.
3) Confirm CloudFront serves updated site.

