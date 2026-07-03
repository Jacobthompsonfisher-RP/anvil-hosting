# anvil-hosting

Runs the open-source [Anvil App Server](https://github.com/anvil-works/anvil-runtime) on Railway,
serving an app built in the anvil.works cloud editor. The app's source is **not** baked into the
Docker image — the container clones it fresh from **Anvil's own private git remote** on every
(re)start, so the app stays private (no GitHub mirror, no Anvil Business plan required) and app
content, dependencies, and server infrastructure all update independently.

**Live:** https://anvil-app-production-a30f.up.railway.app (app: *SEIU Event Sign In Form*)

## How it's wired

```
Anvil editor ──auto git push──▶ Anvil private git remote (ssh://…@anvil.works:2222/…)
                                          │
        sync-app.yml (polls every 5 min, git ls-remote)
                                          │ new commit?
                                          ▼
                              railway redeploy  ──▶ container restarts
                                                     └─ entrypoint clones app + deps, boots server
GitHub repo (this) ──push to master──▶ Railway (watch paths) ──▶ image rebuild
```

- **App content updates** — `.github/workflows/sync-app.yml` polls the Anvil git remote every 5 min.
  On a new commit it runs `railway redeploy` (fast restart, no image rebuild); the entrypoint
  re-clones the latest app source on boot. State is tracked in `state/last-app-sha.txt`, which is
  **not** a Railway watch path, so recording it never triggers a rebuild.
- **Server updates** — `.github/workflows/bump-anvil-server.yml` checks PyPI daily; a new
  `anvil-app-server` release bumps the pin in `Dockerfile` and pushes. Because `Dockerfile` is a
  Railway watch path, that push auto-rebuilds. (The pin defaults to `latest`, so rebuilds already
  track the newest server; the workflow only matters once you pin a concrete version.)
- **Infra changes** — editing `Dockerfile` / `docker-entrypoint.sh` / `railway.json` and pushing to
  `master` auto-rebuilds via Railway's GitHub integration (watch paths).

This hosting repo holds **no app code and no secrets**, so it is **public** (unlimited free GitHub
Actions minutes). Your Anvil app source never leaves Anvil's servers.

## Dependencies

The app depends on other Anvil apps. Anvil's git server won't serve third-party dependency apps to
the deploy key, but the popular ones are public on GitHub. The entrypoint maps each dependency's
Anvil `app_id` to a GitHub repo in `DEP_REPOS`, then reads the pinned `version_tag` and `package_name`
straight from the app's `anvil.yaml` — so **bumping a dependency version in the Anvil editor needs no
change here**. Only a brand-new dependency requires adding one line to `DEP_REPOS`.

Currently mapped:

| Dependency | Anvil app_id | GitHub repo |
|---|---|---|
| routing | `3PIDO5P3H4VPEMPL` | https://github.com/anvil-works/routing |
| tabulator | `TGQCF3WT6FVL2EM2` | https://github.com/anvilistas/tabulator |

## Runtime configuration (Railway service variables)

| Variable | Value |
|---|---|
| `ANVIL_APP_GIT_URL` | the `ssh://…@anvil.works:2222/…` remote (Clone with Git) |
| `ANVIL_APP_BRANCH` | `master` (leave unset to use the remote default) |
| `ANVIL_SSH_KEY_B64` | base64 of the read-only deploy key: `base64 -w0 anvil_deploy_key` |
| `ANVIL_SECRET_<NAME>` | passed to the app as Anvil secret `<NAME>` (read via `anvil.secrets.get_secret`) |

`PORT` and `RAILWAY_PUBLIC_DOMAIN` are provided by Railway. The app serves on port **8080**; the
Railway domain targets that port.

## GitHub Actions configuration (already set)

Secrets: `RAILWAY_TOKEN` (Railway project token), `ANVIL_SSH_KEY_B64` (base64 deploy key).
Variables: `RAILWAY_PROJECT_ID`, `RAILWAY_SERVICE`, `RAILWAY_ENVIRONMENT`, `ANVIL_APP_GIT_URL`,
`ANVIL_APP_BRANCH`.

## The one step that stays manual

Editing the app in the Anvil cloud editor is the only thing you do — everything downstream is
automatic. Note a `railway redeploy` restarts the container, so there's ~30–60s where the app is
briefly unavailable (container restart + Postgres crash-recovery) before it serves again.

## Operational notes

- **Deploy key** is `ed25519`, read-only, added to your Anvil account's SSH keys. It is account-wide
  (can read any of your Anvil apps). To revoke, delete it from Anvil → Account → SSH Keys. The private
  half lives only in the Railway variable and the GitHub secret; `anvil_deploy_key*` are git-ignored.
- **Persistence**: the bundled Postgres and uploaded files live on the Railway volume at `/anvil-data`.
- **Stale DB lock**: Railway stops containers with SIGKILL, so Postgres never shuts down cleanly; the
  entrypoint removes the leftover `postmaster.pid` on boot so the DB crash-recovers instead of failing.
