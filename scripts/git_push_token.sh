#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# Load token from .env without exporting globally
set +u
[ -f .env ] && . ./.env || true
set -u

: "${GITHUB_TOKEN:?GITHUB_TOKEN not set in .env}"
GITHUB_USER="${GITHUB_USER:-preperat}"
REPO_URL="https://github.com/${GITHUB_USER}/timfraser.ai.git"

# Disable macOS Keychain helper for this repo to avoid prompts/errors
git config credential.helper ""

# Ephemeral askpass script so token is not stored in config or history
ASKPASS_FILE=".git-askpass"
cat > "$ASKPASS_FILE" <<'SH'
#!/usr/bin/env bash
case "$1" in
  *Username*) echo "x-access-token" ;;
  *Password*) echo "$GITHUB_TOKEN" ;;
  *) echo "" ;;
esac
SH
chmod 700 "$ASKPASS_FILE"

GIT_ASKPASS="$PWD/$ASKPASS_FILE" git -c credential.helper= push -u "$REPO_URL" master:master

rm -f "$ASKPASS_FILE"
echo "Pushed to $REPO_URL using token from .env"


