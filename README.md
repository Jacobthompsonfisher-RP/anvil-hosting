# anvil-hosting

Runs the open-source [Anvil App Server](https://github.com/anvil-works/anvil-runtime) on Railway,
serving an app built in the anvil.works cloud editor. The app's source is *not* baked into the Docker
image — the container clones it fresh from **Anvil's own private git remote** every time it
(re)starts, so the app stays private (no GitHub mirror, no Anvil Business plan needed) and app content
and server infrastructure update independently:

- **App content updates**: `.github/workflows/sync-app.yml` polls the Anvil git remote every 5 minutes
  (`git ls-remote`). If there's a new commit, it tells Railway to restart the service
  (`railway redeploy`, no image rebuild) — the entrypoint re-clones the latest app source on boot.
- **Server updates**: `.github/workflows/bump-anvil-server.yml` checks PyPI daily for new
  `anvil-app-server` releases, bumps the pinned version in `Dockerfile`, and triggers a full rebuild
  (`railway up`) so the server itself stays current.

This hosting repo contains **no app code and no secrets**, so it is kept **public** (unlimited free
GitHub Actions minutes). Your Anvil app source never leaves Anvil's servers.

## One-time setup

### 1. Get your Anvil app's git remote
In the Anvil editor: **Version History → (dropdown) → Clone with Git**. Copy the **git remote URL**
(looks like `ssh://…@anvil.works/…`). Note the branch name shown too (often `master`).

### 2. Authorize the deploy SSH key with Anvil
An `ed25519` keypair has been generated for this deployment. Add the **public** key to your Anvil
account: in the *Clone with Git* dialog click **"add your SSH public key to Anvil"** (Account
Settings → SSH keys), and paste the contents of `anvil_deploy_key.pub`. The **private** key is only
ever stored as a Railway variable and a GitHub Actions secret (never committed).

### 3. Create the Railway project
```
railway login
railway init          # creates a new project, run from this directory
railway volume add --mount-path /anvil-data
```

### 4. Set Railway service variables
Via the Railway dashboard or `railway variables --set KEY=VALUE`:

| Variable | Value |
|---|---|
| `ANVIL_APP_GIT_URL` | the `ssh://…@anvil.works/…` remote from step 1 |
| `ANVIL_APP_BRANCH` | `master` (or whatever branch Anvil uses); leave unset to use the default |
| `ANVIL_SSH_KEY_B64` | base64 of the private key: `base64 -w0 anvil_deploy_key` |
| `ANVIL_SECRET_<NAME>` | any app secret your `server_code` reads via `anvil.secrets.get_secret("<NAME>")` |

`PORT` and `RAILWAY_PUBLIC_DOMAIN` are provided by Railway automatically.

Then first deploy + public URL:
```
railway up            # build + deploy
railway domain        # generate a *.up.railway.app URL
```

### 5. Create a Railway token for CI
Railway dashboard → Project Settings → Tokens → create a **project token**. Then in this repo:
```
gh secret set RAILWAY_TOKEN                              # paste the Railway project token
gh secret set ANVIL_SSH_KEY_B64 < anvil_deploy_key.b64  # base64 private key, from file
gh variable set RAILWAY_PROJECT_ID --body "<project id, from `railway status --json`>"
gh variable set RAILWAY_SERVICE      --body "<service name>"
gh variable set RAILWAY_ENVIRONMENT  --body "production"
gh variable set ANVIL_APP_GIT_URL    --body "ssh://…@anvil.works/…"
gh variable set ANVIL_APP_BRANCH     --body "master"
```

### 6. Push this repo to GitHub (public)
```
gh repo create <you>/anvil-hosting --source=. --public --push
```

Once these are set, editing the app in the Anvil cloud editor is the only step left in the loop —
the poller and Railway take care of the rest.
