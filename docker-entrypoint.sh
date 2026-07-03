#!/bin/bash
set -euo pipefail

: "${ANVIL_APP_GIT_URL:?Set ANVIL_APP_GIT_URL to your Anvil app git remote, from Clone with Git}"
: "${ANVIL_SSH_KEY_B64:?Set ANVIL_SSH_KEY_B64 to the base64-encoded read-only SSH private key}"
: "${ANVIL_APP_BRANCH:=}"
: "${PORT:=3030}"

APP_DIR=/apps/MainApp
APP_USER=anvil

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

# --- Dependencies -----------------------------------------------------------
# The app depends on other Anvil apps. Anvil's git server won't serve third-party
# dependency apps to this key, but the popular ones are public on GitHub. Map each
# dependency's Anvil app_id to its GitHub repo here; the pinned version tag and
# package name are read automatically from the main app's anvil.yaml, so bumping a
# dependency version in the Anvil editor needs no change here. Add a line only when
# the app gains a brand-new dependency.
declare -A DEP_REPOS=(
  [3PIDO5P3H4VPEMPL]="https://github.com/anvil-works/routing.git"
  [TGQCF3WT6FVL2EM2]="https://github.com/anvilistas/tabulator.git"
)

DEP_ARGS=()
YAML="$APP_DIR/anvil.yaml"
for app_id in "${!DEP_REPOS[@]}"; do
  repo="${DEP_REPOS[$app_id]}"
  pkg=$(grep "app_id: $app_id" "$YAML" | grep -oE 'package_name: [A-Za-z0-9_]+' | awk '{print $2}')
  tag=$(grep -A1 "app_id: $app_id" "$YAML" | grep -oE 'version_tag: [^}]+' | head -1 | awk '{print $2}')
  pkg="${pkg:-$app_id}"
  dep_dir="/apps/$pkg"
  echo "Fetching dependency ${pkg} from ${repo} (tag: ${tag:-<default>})"
  rm -rf "$dep_dir"
  if [[ -n "$tag" ]]; then
    git clone --depth 1 --branch "$tag" "$repo" "$dep_dir"
  else
    git clone --depth 1 "$repo" "$dep_dir"
  fi
  DEP_ARGS+=(--dep-id "$app_id=$pkg")
done

# Railway restarts containers with SIGKILL, so the bundled Postgres never shuts down
# cleanly and leaves a stale postmaster.pid on the volume. On the next boot Anvil tries
# to "shut down [the] orphaned DB" and crashes. A fresh container never has a live
# Postgres, so removing the stale lock lets Postgres do a normal crash-recovery instead.
rm -f /anvil-data/db/postmaster.pid

# The bundled Postgres refuses to run as root, and Railway mounts the volume as root.
# Give the unprivileged app user ownership of the app + data dirs, then drop privileges.
chown -R "$APP_USER":"$APP_USER" /apps /anvil-data

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

export HOME=/anvil-data
exec setpriv --reuid="$APP_USER" --regid="$APP_USER" --init-groups \
  anvil-app-server \
  --app "$APP_DIR" \
  --data-dir /anvil-data \
  --port "$PORT" \
  --ip 0.0.0.0 \
  --disable-tls \
  --auto-migrate \
  "${DEP_ARGS[@]}" \
  "${ORIGIN_ARGS[@]}" \
  "${SECRET_ARGS[@]}" \
  "$@"
