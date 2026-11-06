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

Upright uses `app.<base-hostname>` for the admin UI and `<site-code>.<base-hostname>` for that site's probe results. The local base hostname is `upright.localhost`. `fra` is the site code configured in `config/sites.yml` for Frankfurt, the location where probes run. It is the current site code, not a fixed Upright hostname. Another site uses its own code as the subdomain.

Signed out, both app URLs redirect to the sign-in page at http://app.upright.localhost:3000/session/new. That redirect is the expected result. Sign in as `admin` with `ADMIN_PASSWORD` (default `admin`). The same session works on both hosts.

| URL | Role | Signed out | Signed in |
| --- | --- | --- | --- |
| http://app.upright.localhost:3000 | Admin UI (`app.<base-hostname>`) | Sign-in page | Sites, the admin UI |
| http://fra.upright.localhost:3000 | Probe results for site code `fra` | Sign-in page | Probe results for Frankfurt |

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

Compose does not install Chromium. This builds the same browser-enabled image that CI publishes, then checks that Playwright can launch Chromium as uid 1000:

```bash
docker build --build-arg INSTALL_PLAYWRIGHT=1 -t upright:browser .
docker run --rm --user 1000:1000 --shm-size=1g --security-opt seccomp=docker/seccomp_profile.json upright:browser ./bin/check-chromium
```

`docker/seccomp_profile.json` is the Playwright 1.59.1 seccomp profile. It is Docker's default profile plus permission for `clone`, `setns`, and `unshare`, which the Chromium sandbox needs in order to create a user namespace. The command prints `chromium-ok` when the browser starts. A missing browser or a launch failure exits non-zero.

## Production

Pushing `main` to [ADORSYS-GIS/upright](https://github.com/ADORSYS-GIS/upright) builds `ghcr.io/adorsys-gis/upright/upright` with Chromium and publishes the commit SHA. The workflow summary records the image digest, `ghcr.io/adorsys-gis/upright/upright@sha256:...`. The workflow does not publish a `latest` tag.

The chart pins that digest on `defaultContainerOptions.image`, so the web container, the jobs container, and the `db-prepare` init container use `repository:tag@digest`. The pin in `charts/upright/values.yaml` is the image published from the browser-capable build (`sha-3774812f19b3e49467a7821a1e261e67c9189622`). Bump the digest (and the matching SHA tag) after a new `main` publish.

```bash
helm dependency update ./charts/upright
helm upgrade --install upright ./charts/upright \
  --namespace datev-wallet \
  --values ./charts/upright/values-probes.yaml
```

Helm loads the chart’s default `values.yaml` automatically and merges `values-probes.yaml`. Probe lists live in that file so they can grow without cluttering the rest of the deployment values. Changing a probe still updates the ConfigMap and rolls the Pod through the checksum already set in `values.yaml`.

To override the pin without editing values:

```bash
helm upgrade --install upright ./charts/upright \
  --namespace datev-wallet \
  --values ./charts/upright/values-probes.yaml \
  --set app-template.controllers.main.defaultContainerOptions.image.tag=sha-<commit> \
  --set app-template.controllers.main.defaultContainerOptions.image.digest=sha256:<hex>
```

One Pod runs the web process and the probe jobs from the same image. Both mount a persistent volume at `/rails/storage` on the `high-performance` StorageClass, so SQLite data survives a restart. The chart does not ship Prometheus or Alertmanager. A ServiceMonitor on port `9394` and a PrometheusRule, both labeled `release: kube-prometheus-stack`, are selected by the cluster Prometheus. Alerts go to the shared `platform-webhook` receiver. Ingress publishes:

- https://app.upright.eudi-adorsys.com — admin sign-in
- https://fra.upright.eudi-adorsys.com — Frankfurt site page

TLS uses the secret `upright-eudi-adorsys-tls`, issued by `letsencrypt-prod` for those two hosts. Settings live in `charts/upright/values.yaml`.

### Releases

The chart migrates on each deploy. Its `db-prepare` init container runs `./bin/rails db:prepare` before the web container starts. That container uses the production image, so `RAILS_ENV` is `production`, and it mounts the persistent volume at `/rails/storage`. The web process does not migrate when it starts.

`db:prepare` migrates the primary database, the Upright persistent database, and the production queue, cache, and cable databases.

Running `bin/rails db:prepare` from a local checkout uses the development databases under `storage/`. It does not use the production databases or the cluster volume. A separate release step has to run that command in the production image with `RAILS_ENV=production`, the volume mounted at `/rails/storage`, and the same environment and secrets as the `db-prepare` init container.

### Secrets

Add these properties to the existing AWS secret `datev-wallet-secrets` in `eu-central-1`. The chart creates an Upright-owned namespaced `SecretStore` and copies each AWS property into a container environment variable. The running containers read those environment names. All three must be present or the app will not start.

| AWS property | Container environment | Value |
| --- | --- | --- |
| `UPRIGHT_RAILS_MASTER_KEY` | `RAILS_MASTER_KEY` | The single line in `config/master.key`. This decrypts `config/credentials.yml.enc`. |
| `UPRIGHT_ADMIN_PASSWORD` | `ADMIN_PASSWORD` | Password for the `admin` user. |
| `UPRIGHT_PROMETHEUS_OTLP_TOKEN` | `PROMETHEUS_OTLP_TOKEN` | One shared machine token, generated once with `openssl rand -hex 64`. Every pod uses this same value. People sign in with the admin password. |

Local development reads `ADMIN_PASSWORD` from `.env`, which defaults to `admin`. Deployment maps `UPRIGHT_ADMIN_PASSWORD` to `ADMIN_PASSWORD`. There is no production default. If `ADMIN_PASSWORD` is unset, sign-in has no credential, so the local password is never used in production.

The namespace also needs a pull secret named `ghcr-pull-secret` so the cluster can pull the image from GHCR.

Probe YAML files are mounted from chart ConfigMaps at `/rails/probes/<file>`. The payloads are in `charts/upright/values-probes.yaml`. The base release ships with no live target. Add a target before expecting application alerts.

### SQLite backup and restore

The app PVC uses StorageClass `high-performance`. That class has reclaim policy `Delete`, so deleting the claim deletes the volume. The chart sets `retain: true` on the claim so a Helm uninstall keeps the PVC object. Treat the volume as production data only after a restore has been practised.

For an EBS snapshot, stop the single Upright Pod first so SQLite is quiescent, then snapshot the EBS volume backing the `upright` claim. Run this from an AWS-authenticated Bash shell with `kubectl` access. The recovery trap is installed before scaling down; `set -euo pipefail` makes the block fail fast, and a failure restores Upright instead of leaving it offline or taking a snapshot before a confirmed stop.

```bash
set -euo pipefail
trap 'kubectl scale -n datev-wallet deploy/upright --replicas=1' EXIT
kubectl scale -n datev-wallet deploy/upright --replicas=0
kubectl wait -n datev-wallet --for=delete pod -l app.kubernetes.io/name=upright --timeout=120s
PV=$(kubectl get pvc upright -n datev-wallet -o jsonpath='{.spec.volumeName}')
VOLUME_ID=$(kubectl get pv "$PV" -o jsonpath='{.spec.csi.volumeHandle}')
: "${PV:?resolved PVC has no bound volume}"
: "${VOLUME_ID:?resolved PV has no CSI volume handle}"
aws ec2 create-snapshot \
  --volume-id "$VOLUME_ID" \
  --description "Upright datev-wallet SQLite backup" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=upright-datev-wallet}]'
kubectl scale -n datev-wallet deploy/upright --replicas=1
trap - EXIT
```

Wait for the snapshot to reach `completed` in the EC2 console or with `aws ec2 describe-snapshots`. To restore from an EBS snapshot, create a replacement EBS volume from that snapshot in the EKS node's Availability Zone and restore it through a PV/PVC before starting Upright. The tar backup below is the documented in-place restore path.

Backup, with the release name `upright` in `datev-wallet` (stop the app first so SQLite is quiescent):

```bash
set -euo pipefail
trap 'kubectl scale -n datev-wallet deploy/upright --replicas=1' EXIT
kubectl scale -n datev-wallet deploy/upright --replicas=0
kubectl wait -n datev-wallet --for=delete pod -l app.kubernetes.io/name=upright --timeout=120s
kubectl run -n datev-wallet upright-backup --rm -i --restart=Never \
  --image=busybox:1.36 --overrides='{"spec":{"containers":[{"name":"backup","image":"busybox:1.36","command":["sh","-c","tar -C /rails/storage -czf - ."],"volumeMounts":[{"name":"storage","mountPath":"/rails/storage"}]}],"volumes":[{"name":"storage","persistentVolumeClaim":{"claimName":"upright"}}]}}' \
  > upright-storage-$(date -u +%Y%m%dT%H%M%SZ).tgz
kubectl scale -n datev-wallet deploy/upright --replicas=1
trap - EXIT
```

In-place restore into the existing `upright` PVC (app stopped). This clears `/rails/storage` before extracting the archive so the restored SQLite databases are not mixed with partial or stale files. A restore failure leaves Upright scaled to zero; fix the issue and rerun the restore before starting the app.

```bash
set -euo pipefail
kubectl scale -n datev-wallet deploy/upright --replicas=0
kubectl wait -n datev-wallet --for=delete pod -l app.kubernetes.io/name=upright --timeout=120s
kubectl run -n datev-wallet upright-restore --rm -i --restart=Never \
  --image=busybox:1.36 --overrides='{"spec":{"containers":[{"name":"restore","image":"busybox:1.36","command":["sh","-c","find /rails/storage -mindepth 1 -delete && tar -C /rails/storage -xzf -"],"volumeMounts":[{"name":"storage","mountPath":"/rails/storage"}]}],"volumes":[{"name":"storage","persistentVolumeClaim":{"claimName":"upright"}}]}}' \
  < upright-storage-YYYYMMDDTHHMMSSZ.tgz
kubectl scale -n datev-wallet deploy/upright --replicas=1
```
