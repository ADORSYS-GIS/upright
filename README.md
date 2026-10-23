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

That command installs gems, prepares the primary, persistent, and queue databases, and starts the Solid Queue worker beside the web process.

When the log shows `Listening on http://0.0.0.0:3000`:

| Surface | URL | Access |
| --- | --- | --- |
| Admin UI | http://app.upright.localhost:3000 | `admin` / `ADMIN_PASSWORD` (default `admin`) |
| London site | http://lon.upright.localhost:3000 | same session |
| Prometheus | http://127.0.0.1:9091 | local only |
| Alertmanager | http://127.0.0.1:9093 | local only |

Stop the stack with `docker compose down`.

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

Add these properties to the existing AWS secret `datev-wallet-secrets` in `eu-central-1`. The chart copies them into the namespace through `datev-secret-store`. All four must be present or the app will not start.

| Property | Value |
| --- | --- |
| `UPRIGHT_RAILS_MASTER_KEY` | The single line in `config/master.key`. This decrypts `config/credentials.yml.enc`. |
| `UPRIGHT_ADMIN_PASSWORD` | Password for the `admin` user. |
| `UPRIGHT_PROMETHEUS_OTLP_TOKEN` | One shared machine token, generated once with `openssl rand -hex 64`. Every pod uses this same value. People sign in with the admin password. |
| `UPRIGHT_DISCORD_WEBHOOK_URL` | Webhook URL for the Discord alerts channel. |

The namespace also needs a pull secret named `ghcr-pull-secret` so the cluster can pull the image from GHCR.

Active probes are listed in `probes/http_probes.yml`. The file ships with no live check. Add a target before expecting alerts.
