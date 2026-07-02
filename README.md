# anvil-hosting

Runs the open-source [Anvil App Server](https://github.com/anvil-works/anvil-runtime) on Railway,
serving an app built in the anvil.works cloud editor. The app's source is *not* baked into the
Docker image — the container fetches it fresh from GitHub every time it (re)starts, so app content
and server infrastructure update independently:

- **App content updates**: `.github/workflows/sync-app.yml` polls the Anvil app's GitHub repo every
  5 minutes. If there's a new commit, it tells Railway to restart the service (`railway redeploy`,
  no image rebuild) — the entrypoint script re-fetches the latest app source on boot.
- **Server updates**: `.github/workflows/bump-anvil-server.yml` checks PyPI daily for new
  `anvil-app-server` releases, bumps the pinned version in `Dockerfile`, and triggers a full rebuild
  (`railway up`) so the server itself stays current.

## One-time setup

### 1. Connect your Anvil app to a *private* GitHub repo
In the Anvil editor: **Version History → Save app to GitHub**, choose **Private** (requires an Anvil
Business plan or higher). Note the repo as `owner/name`, e.g. `you/my-anvil-app`.

### 1b. Create a read-only token for the app repo
GitHub → **Settings → Developer settings → Fine-grained personal access tokens → Generate new**:
- **Repository access**: Only select repositories → your Anvil app repo.
- **Permissions**: Repository permissions → **Contents: Read-only**.
- Copy the token. It's used in two places: the Railway service (`GITHUB_TOKEN`) so the container can
  fetch the app, and this hosting repo's Actions (`APP_REPO_TOKEN`) so the poller can see new commits.

### 2. Create the Railway project
```
railway login
railway init          # creates a new project, run from this directory
railway up             # first manual build+deploy to make sure it works
railway domain         # generates a *.up.railway.app public URL
railway volume add --mount-path /anvil-data
```

### 3. Set Railway service environment variables
In the Railway dashboard (or `railway variables --set KEY=VALUE`), set on the service:

| Variable | Value |
|---|---|
| `ANVIL_APP_REPO` | your app repo as `owner/name` from step 1 |
| `ANVIL_APP_BRANCH` | `main` (or whatever branch Anvil pushes to) |
| `GITHUB_TOKEN` | the read-only fine-grained token from step 1b |
| `ANVIL_SECRET_<NAME>` | any app secret your `server_code` reads via `anvil.secrets.get_secret("<NAME>")` |

`PORT` and `RAILWAY_PUBLIC_DOMAIN` are already provided by Railway automatically.

### 4. Create a Railway token for CI
Railway dashboard → Project Settings → Tokens → create a **project token**. Then, in this repo on
GitHub:
```
gh secret set RAILWAY_TOKEN          # paste the Railway project token when prompted
gh secret set APP_REPO_TOKEN         # paste the read-only fine-grained token from step 1b
gh variable set RAILWAY_PROJECT_ID --body "<project id, from `railway status --json`>"
gh variable set RAILWAY_SERVICE      --body "<service name>"
gh variable set RAILWAY_ENVIRONMENT  --body "production"
gh variable set ANVIL_APP_REPO       --body "<you>/<app-name>"
gh variable set ANVIL_APP_BRANCH     --body "main"
```

### 5. Push this repo to GitHub
```
gh repo create <you>/anvil-hosting --source=. --public --push
```

Once these are set, editing the app in the Anvil cloud editor is the only step left in the loop —
GitHub Actions and Railway take care of the rest.
