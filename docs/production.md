# Production deployment with Kamal

OpenTrack deploys to **https://track.tamayotchi.com** using Kamal 2, on the same
`home-server` as `tama_track`. `config/deploy.yml` configures:

- Service `open-track`, image `ghcr.io/tamayotchi/open-track`, amd64.
- SSH as `root` using `~/.ssh/id_home_server`.
- Port 4000 behind the existing Kamal proxy; no direct published application port.
- SQLite at `/app/storage/open_track.db`, persisted in `open-track_storage`.
- The existing shared R2 bucket `tama-track` and existing OpenRouter key.
- Public images at `https://images.tamayotchi.com` via an R2 custom domain.

This creates a **new database**, not a migration/import of tama_track's accounts
or photos. Never reuse `tama-track_storage`; the database schemas differ.
Keep this SQLite deployment on one host. Back up the database before schema changes;
rolling an image back does not roll its database schema back.

## Secrets

`.kamal/secrets` contains only 1Password lookup commands. It uses the same account
(`instaleap-llc.1password.com`) and item (`SERVER/TAMA_TRACK`) as tama_track:

- `KAMAL_REGISTRY_PASSWORD` — GHCR credential with permission to push the new image.
- `SECRET_KEY_BASE` — Phoenix signing secret.
- `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` — existing R2 access.
- `FOOD_AI_API_KEY` — existing OpenRouter credential (and its shared spending limit).

OpenTrack also requires `TOKEN_SIGNING_SECRET`. The Kamal secret alias
`TOKEN_SIGNING_SECRET:SECRET_KEY_BASE` supplies the existing signing key without
requiring a new 1Password field. This intentionally shares signing material;
rotating it affects both applications, and invalidates OpenTrack sessions/tokens.
For future isolation, create a dedicated stable token key, fetch it in
`.kamal/secrets`, and replace the alias with `TOKEN_SIGNING_SECRET`.

No plaintext secrets are committed or needed during image compilation. Local
`.env` files are not used by Kamal and are excluded from Docker builds.
Do not paste output from `kamal secrets print` or `kamal config` into logs/issues:
those commands can expose resolved values.

The shared R2 credentials grant access to the same bucket as tama_track. This
is not storage isolation: do not run bucket-wide cleanup or apply new lifecycle
rules without considering both apps. Existing development uploads may share
this bucket too. The public custom domain exposes **all objects in this shared
bucket** to anyone who knows their URLs.

## Public image delivery

`config/deploy.yml` sets the non-secret `R2_PUBLIC_BASE_URL` to
`https://images.tamayotchi.com`. The domain connects directly to `tama-track` in
Cloudflare, with minimum TLS 1.2. Keep the authenticated S3 endpoint and R2
credentials unchanged; the public endpoint serves reads only.

Before deploying, ensure domain ownership and TLS are active and configure the
image-host-only Cache Rule described in [Cloudflare R2](../README.md#cloudflare-r2).
It explicitly caches extensionless keys for one day at the edge and in browsers,
without changing caching on the application hostname. Wrangler can connect the
R2 domain, but its OAuth token may lack Cache Rules permissions; API automation
requires a token scoped to this zone with **Cache Rules: Edit**.

Verify a known image returns 200 and repeat the request to check for
`CF-Cache-Status: HIT` and a one-day browser cache lifetime. Replacements use new
keys. To remove deleted images promptly from shared caches, purge their public
URLs in Cloudflare; this is not automatic, and browser-cached copies remain until
expiry. No migration or re-upload of existing objects is required.

## HTTPS and routing prerequisites

The configuration mirrors tama_track's `ssl: false`: **TLS must terminate at the
existing external HTTPS proxy/tunnel**. Before deploying:

1. Add `track.tamayotchi.com` to the same DNS/proxy/tunnel setup used by
   `tama-track.tamayotchi.com`, routing it to the home server's Kamal proxy.
2. Preserve the `Host: track.tamayotchi.com` header for Kamal routing and LiveView
   origin checks. Support WebSocket upgrades and forward `X-Forwarded-Proto: https`.
3. Enforce HTTPS at that trusted edge and prevent public access that bypasses it.
   Forwarded headers must be set/overwritten by the trusted proxy, not trusted
   from arbitrary clients. Do not expose the app's port 4000 or Erlang distribution.

DNS/TLS/tunnel changes are not performed by this repository. If you instead want
Kamal to issue certificates directly, configure `proxy.ssl: true` and review
forwarded-header trust for that topology; DNS must point to the server and port
443 must be reachable for certificate issuance.

## Deploy

Install Docker with Buildx, Kamal 2 (configuration validated with 2.10.1), and the
1Password CLI. Authenticate to the configured 1Password account, ensure the SSH
host alias resolves, and confirm the GHCR credential can publish `open-track`.

Commit the deployment files and app changes first: Kamal builds from the Git
checkout, so uncommitted files are not included in its default build.

```sh
# First deployment of this service; uses the existing shared Kamal proxy.
kamal setup

# Subsequent deployments
kamal deploy

# Operations
kamal logs
kamal shell
kamal console
```

Do not remove/reboot the shared proxy just to add this application; that can
interrupt tama_track and other hosted services.

The generated Phoenix `Dockerfile` builds assets and an Elixir release without
production secrets. The container runs as `nobody`; the storage directory is
created with matching ownership so a new named volume is writable. The release's
`bin/server` enables Phoenix. `OpenTrack.Application` already runs pending SQLite
migrations before Oban and the endpoint start, so no second migration entrypoint
is needed. Kamal checks `/` for HTTP 200 before routing traffic, with a 180-second
deployment timeout.

After deployment, verify HTTPS, login/registration, a LiveView WebSocket connection,
photo upload/display, and an AI analysis. These last operations use real R2 storage
and may incur OpenRouter charges.

## Backups

The persistent Docker volume survives deployments, but **is not a backup**.
This configuration does not copy tama_track's Litestream backup role or backup
path: sharing those would risk mixing unrelated databases. Arrange SQLite-aware
backups and test restore before storing important data. Back up R2 objects as
well; database backups alone cannot restore deleted images.
