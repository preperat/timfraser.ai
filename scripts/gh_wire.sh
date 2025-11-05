#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# Load .env (expects GITHUB_TOKEN, optional GITHUB_USER)
if [ -f .env ]; then
  # Load .env in a shell-safe way
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "ERROR: GITHUB_TOKEN not found in .env" >&2
  exit 1
fi

REPO_NAME="timfraser.ai"
API="https://api.github.com"
AUTH_HEADER="Authorization: token ${GITHUB_TOKEN}"
UA_HEADER="User-Agent: gh-wire-script"

# Discover username if not supplied
if [ -z "${GITHUB_USER:-}" ]; then
  GITHUB_USER=$(curl -fsS -H "$AUTH_HEADER" -H "$UA_HEADER" "$API/user" | python3 -c 'import sys, json; print(json.load(sys.stdin)["login"])')
fi
export GITHUB_USER

REPO_API="$API/repos/${GITHUB_USER}/${REPO_NAME}"

# Create repo if it does not exist
if ! curl -fsS -H "$AUTH_HEADER" -H "$UA_HEADER" "$REPO_API" >/dev/null 2>&1; then
  echo "Creating repo ${GITHUB_USER}/${REPO_NAME}"
  curl -fsS -X POST -H "$AUTH_HEADER" -H "$UA_HEADER" \
    -d "{\"name\":\"${REPO_NAME}\",\"private\":false}" \
    "$API/user/repos" >/dev/null
else
  echo "Repo exists: ${GITHUB_USER}/${REPO_NAME}"
fi

# Initialize git on master and push
if [ ! -d .git ]; then
  git init
fi

git checkout -B master

git add .
if ! git diff --cached --quiet; then
  git commit -m "chore: initial infra + site"
fi

git remote remove origin 2>/dev/null || true
 git remote add origin "https://github.com/${GITHUB_USER}/${REPO_NAME}.git"

# Use askpass to avoid exposing token
ASKPASS_FILE=".git-askpass"
cat > "$ASKPASS_FILE" <<'SH'
#!/usr/bin/env bash
case "$1" in
  Username*) echo "x-access-token" ;;
  Password*) echo "$GITHUB_TOKEN" ;;
esac
SH
chmod 700 "$ASKPASS_FILE"
GIT_ASKPASS="$PWD/$ASKPASS_FILE" git -c credential.helper= push -u origin master
rm -f "$ASKPASS_FILE"

# Set GitHub Actions secrets using repository public key
# Requires pynacl for sealed box encryption
python3 - <<'PY'
import base64, json, os, subprocess, sys
import urllib.request

GITHUB_TOKEN=os.environ['GITHUB_TOKEN']
GITHUB_USER=os.environ['GITHUB_USER']
REPO_NAME='timfraser.ai'
API='https://api.github.com'
headers={'Authorization': f'token {GITHUB_TOKEN}', 'User-Agent':'gh-wire-script'}

def gh_get(path):
    req=urllib.request.Request(API+path, headers=headers)
    with urllib.request.urlopen(req) as r:
        return json.load(r)

def gh_put(path, data):
    req=urllib.request.Request(API+path, data=json.dumps(data).encode(), headers={**headers,'Content-Type':'application/json'}, method='PUT')
    with urllib.request.urlopen(req) as r:
        return json.load(r) if r.length else None

# Fetch repo public key
pk=gh_get(f'/repos/{GITHUB_USER}/{REPO_NAME}/actions/secrets/public-key')
key_id=pk['key_id']
key=base64.b64decode(pk['key'])

# Gather AWS secrets from local profile if available
AWS_PROFILE=os.environ.get('AWS_PROFILE','tef-DevOps')
try:
    access_key=subprocess.check_output(['aws','configure','get','aws_access_key_id','--profile',AWS_PROFILE]).decode().strip()
    secret_key=subprocess.check_output(['aws','configure','get','aws_secret_access_key','--profile',AWS_PROFILE]).decode().strip()
except Exception as e:
    print('WARNING: Could not read AWS credentials from profile; skipping AWS secrets. Add them manually in repo settings.')
    access_key=secret_key=''

region=os.environ.get('AWS_REGION','ap-southeast-2')
s3_bucket='timfraser-ai-site-prod'

# Encrypt via NaCl sealed box
try:
    from nacl import public, encoding, exceptions
except Exception:
    # install pynacl if missing
    import subprocess
    subprocess.check_call([sys.executable,'-m','pip','install','--user','pynacl'])
    from nacl import public, encoding, exceptions

pubkey=public.PublicKey(key)
box=public.SealedBox(pubkey)

def enc(v:str):
    if not v:
        return None
    return base64.b64encode(box.encrypt(v.encode())).decode()

secrets=[
    ('AWS_REGION', region),
    ('S3_BUCKET', s3_bucket),
]
if access_key and secret_key:
    secrets += [
        ('AWS_ACCESS_KEY_ID', access_key),
        ('AWS_SECRET_ACCESS_KEY', secret_key),
    ]

for name, value in secrets:
    ev = enc(value)
    if not ev:
        continue
    gh_put(f'/repos/{GITHUB_USER}/{REPO_NAME}/actions/secrets/{name}', {
        'encrypted_value': ev,
        'key_id': key_id
    })
    print(f'Set secret: {name}')
PY
