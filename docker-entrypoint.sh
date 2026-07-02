#!/bin/bash
set -euo pipefail

: "${ANVIL_APP_GIT_URL:?Set ANVIL_APP_GIT_URL to your Anvil app's git remote (from Clone with Git)}"
: "${ANVIL_SSH_KEY_B64:?Set ANVIL_SSH_KEY_B64 to the base64-encoded read-only SSH private key}"
: "${ANVIL_APP_BRANCH:=}"
: "${PORT:=3030}"

APP_DIR=/apps/MainApp

# Install the SSH key used to read the app from Anvil's private git remote.
SSH_DIR=/tmp/anvil-ssh
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
printf '%s' "$ANVIL_SSH_KEY_B64" | base64 -d > "$SSH_DIR/id"
chmod 600 "$SSH_DIR/id"
export GIT_SSH_COMMAND="ssh -i $SSH_DIR/id -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$SSH_DIR/known_hosts"

echo "Fetching Anvil app source from ${ANVIL_APP_GIT_URL} (branch: ${ANVIL_APP_BRANCH:-<default>})"
rm -rf "$APP_DIR"
if [[ -n "$ANVIL_APP_BRANCH" ]]; then
  git clone --depth 1 --branch "$ANVIL_APP_BRANCH" "$ANVIL_APP_GIT_URL" "$APP_DIR"
else
  git clone --depth 1 "$ANVIL_APP_GIT_URL" "$APP_DIR"
fi

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
