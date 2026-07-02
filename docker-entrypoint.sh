#!/bin/bash
set -euo pipefail

: "${ANVIL_APP_REPO:?Set ANVIL_APP_REPO to your Anvil app's GitHub repo as owner/name}"
: "${ANVIL_APP_BRANCH:=main}"
: "${GITHUB_TOKEN:?Set GITHUB_TOKEN to a read-only token for the private app repo}"
: "${PORT:=3030}"

APP_DIR=/apps/MainApp

echo "Fetching Anvil app source from ${ANVIL_APP_REPO} (branch: ${ANVIL_APP_BRANCH})"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
# GitHub tarball API works for private repos with a token, and needs no git in the image.
TARBALL_URL="https://api.github.com/repos/${ANVIL_APP_REPO}/tarball/${ANVIL_APP_BRANCH}"
wget -qO- \
  --header="Authorization: Bearer ${GITHUB_TOKEN}" \
  --header="Accept: application/vnd.github+json" \
  "$TARBALL_URL" | tar xz -C "$APP_DIR" --strip-components=1

ORIGIN_ARGS=()
if [[ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]]; then
  ORIGIN_ARGS=(--origin "https://${RAILWAY_PUBLIC_DOMAIN}")
fi

# Any env var named ANVIL_SECRET_<NAME> is passed through as an Anvil app secret <NAME>.
SECRET_ARGS=()
while IFS='=' read -r name value; do
  [[ "$name" == ANVIL_SECRET_* ]] || continue
  secret_name="${name#ANVIL_SECRET_}"
  SECRET_ARGS+=(--secret "${secret_name}=${value}")
done < <(env)

exec anvil-app-server \
  --app "$APP_DIR" \
  --data-dir /anvil-data \
  --port "$PORT" \
  --ip 0.0.0.0 \
  --disable-tls \
  --auto-migrate \
  "${ORIGIN_ARGS[@]}" \
  "${SECRET_ARGS[@]}" \
  "$@"
