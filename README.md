# Upright

Rails host application for [Upright](https://github.com/basecamp/upright), the synthetic monitoring engine. This repository holds our application, probes, and the Helm chart used to run it on EKS. The engine itself is the `upright` gem from RubyGems.

Update the engine with `bundle update upright`. Within the current Gemfile constraint that stays on 0.4.x. Moving to a new minor version follows [UPGRADING.md](https://github.com/basecamp/upright/blob/main/UPGRADING.md).

## Local development

Docker is required.

```bash
cp .env.example .env
docker compose up -d
docker compose logs -f app
```

Set `DISCORD_WEBHOOK_URL` in the copied `.env` before `docker compose up`. That file is gitignored. Alertmanager exits when the variable is unset.

That command installs gems, prepares the primary, persistent, and queue databases, and starts the Solid Queue worker beside the web process.

When the log shows `Listening on http://0.0.0.0:3000`, open a host under `upright.localhost`. The engine allows that name and its subdomains. `http://localhost:3000` is rejected.

Upright uses `app.<base-hostname>` for the admin UI and `<site-code>.<base-hostname>` for that site's probe results. The local base hostname is `upright.localhost`. `lon` is the site code configured in `config/sites.yml` for London, the location where probes run. It is the current site code, not a fixed Upright hostname. Another site uses its own code as the subdomain.

Signed out, both app URLs redirect to the sign-in page at http://app.upright.localhost:3000/session/new. That redirect is the expected result. Sign in as `admin` with `ADMIN_PASSWORD` (default `admin`). The same session works on both hosts.

| URL | Role | Signed out | Signed in |
| --- | --- | --- | --- |
| http://app.upright.localhost:3000 | Admin UI (`app.<base-hostname>`) | Sign-in page | Sites, the admin UI |
| http://lon.upright.localhost:3000 | Probe results for site code `lon` | Sign-in page | Probe results for London |

Docker Compose also publishes the monitoring UIs on localhost:

| Surface | URL | Access |
| --- | --- | --- |
| Prometheus | http://127.0.0.1:9091 | local only |
| Alertmanager | http://127.0.0.1:9093 | local only |

Stop the stack with `docker compose down`.

Run the test suite in the app container. `bin/rails test` uses the test databases under `storage/`.

```bash
docker compose exec app bin/rails test
```

## Production

Pushing `main` to [ADORSYS-GIS/upright](https://github.com/ADORSYS-GIS/upright) builds and publishes `ghcr.io/adorsys-gis/upright/upright`. The chart in `charts/upright` installs that image into the `datev-wallet` namespace.

```bash
helm upgrade --install upright ./charts/upright \
  --namespace datev-wallet
```

One Pod runs the web process and the probe jobs from the same image. Both mount a persistent volume at `/rails/storage`, so SQLite data survives a restart. Prometheus and Alertmanager run beside the app. Ingress publishes:

- https://app.eudi-adorsys.com — admin sign-in
- https://lon.eudi-adorsys.com — London site page

TLS uses the existing wildcard secret `eudi-adorsys-tls`. Settings live in `charts/upright/values.yaml`.

### Releases

The chart migrates on each deploy. Its `db-prepare` init container runs `./bin/rails db:prepare` before the web container starts. That container uses the production image, so `RAILS_ENV` is `production`, and it mounts the persistent volume at `/rails/storage`. The web process does not migrate when it starts.

`db:prepare` migrates the primary database, the Upright persistent database, and the production queue, cache, and cable databases.

Running `bin/rails db:prepare` from a local checkout uses the development databases under `storage/`. It does not use the production databases or the cluster volume. A separate release step has to run that command in the production image with `RAILS_ENV=production`, the volume mounted at `/rails/storage`, and the same environment and secrets as the `db-prepare` init container.

### Secrets

Add these properties to the existing AWS secret `datev-wallet-secrets` in `eu-central-1`. The chart copies each AWS property into a container environment variable through `datev-secret-store`. The running containers read those environment names. All four must be present or the app will not start.

| AWS property | Container environment | Value |
| --- | --- | --- |
| `UPRIGHT_RAILS_MASTER_KEY` | `RAILS_MASTER_KEY` | The single line in `config/master.key`. This decrypts `config/credentials.yml.enc`. |
| `UPRIGHT_ADMIN_PASSWORD` | `ADMIN_PASSWORD` | Password for the `admin` user. |
| `UPRIGHT_PROMETHEUS_OTLP_TOKEN` | `PROMETHEUS_OTLP_TOKEN` | One shared machine token, generated once with `openssl rand -hex 64`. Every pod uses this same value. People sign in with the admin password. |
| `UPRIGHT_DISCORD_WEBHOOK_URL` | `DISCORD_WEBHOOK_URL` | Webhook URL for the Discord alerts channel. |

Local development reads `ADMIN_PASSWORD` from `.env`, which defaults to `admin`. Deployment maps `UPRIGHT_ADMIN_PASSWORD` to `ADMIN_PASSWORD`. There is no production default. If `ADMIN_PASSWORD` is unset, sign-in has no credential, so the local password is never used in production.

The namespace also needs a pull secret named `ghcr-pull-secret` so the cluster can pull the image from GHCR.

Active probes are listed in `probes/http_probes.yml`. The file ships with no live check. Add a target before expecting alerts.
