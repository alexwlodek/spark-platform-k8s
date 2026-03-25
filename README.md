# spark-platform-k8s

## Environments

Current setup:

- `dev` cluster on kind (`data-platform-dev`): `clusters/dev` + `values/dev`
- `prod` target environment (`data-platform-prod`): `clusters/prod` + `values/prod`
- shared values: `values/common`

Production infrastructure is staged so each layer has its own Terraform root and state boundary:

- `infra/envs/prod/00-network`
- `infra/envs/prod/10-gke`
- `infra/envs/prod/20-shared-services`

Reusable Terraform code lives under:

- `infra/modules/network`
- `infra/modules/gke`
- `infra/modules/shared-services`

GitOps uses app-of-apps (`root.yaml`) and in-cluster destination (`https://kubernetes.default.svc`).

## DEV bootstrap (kind)

```bash
scripts/dev-up.sh
```

This creates a kind cluster, installs ingress-nginx, applies local DEV Kubernetes Secrets, and bootstraps Argo CD with app-of-apps.
`scripts/dev-up.sh` now runs `scripts/dev-secrets-apply.sh` before Argo CD bootstrap so `dev` stays fully local and does not depend on any cloud secret backend.

Default kind Kubernetes image is `kindest/node:v1.34.2` (override via `KIND_IMAGE=...`).
If you already have an older cluster, recreate it with `KIND_DELETE_EXISTING=1 scripts/dev-up.sh`.

DEV UI access now uses ingress hosts (no manual `kubectl port-forward` needed):

```bash
scripts/dev-ui-links.sh
```

Hosts:

- `http://argocd.127.0.0.1.nip.io:8080`
- `http://grafana.127.0.0.1.nip.io:8080`
- `http://prometheus.127.0.0.1.nip.io:8080`
- `http://kibana.127.0.0.1.nip.io:8080`
- `http://metabase.127.0.0.1.nip.io:8080`

## Argo CD bootstrap (generic)

`scripts/bootstrap-argocd.sh` supports environment/context selection:

```bash
./scripts/bootstrap-argocd.sh --env dev --context kind-data-platform-dev
./scripts/bootstrap-argocd.sh --env prod --context gke_data-platform-prod-491113_europe-central2_data-platform-prod
```

Wrappers:

- `scripts/dev-bootstrap-argocd.sh`
- `scripts/prod-up.sh`
- `scripts/prod-destroy.sh`

By default bootstrap installs Argo CD via pinned Helm chart version (`7.7.0`) and then applies:

- `clusters/<env>/projects/platform.yaml`
- `clusters/<env>/root.yaml`

## PROD GCP infrastructure

Production bootstrap is driven by a local env file plus two operator entrypoints:

- `local/prod.env.example`
- `local/prod.env.sh` (gitignored)
- `scripts/prod-up.sh`
- `scripts/prod-destroy.sh`
- `scripts/bootstrap-argocd.sh`

### Prerequisites

- `terraform`
- `gcloud`
- `kubectl`
- `helm`
- `jq`
- `curl`
- `openssl`
- authenticated `gcloud` access to the target project

### Why the infra is staged

The production stack is intentionally not a single Terraform root. The stages keep the workflow readable, keep blast radius smaller, and make destroy order explicit:

1. `00-network` provisions the VPC, subnet, Cloud NAT, reserved public IP, optional Cloudflare DNS records, and Private Service Access for Cloud SQL.
2. `10-gke` provisions the production GKE cluster, node pools, Workload Identity plumbing, and cluster-level service accounts.
3. `20-shared-services` provisions the managed data plane resources used by prod workloads:
   - GCS bucket
   - Cloud SQL for PostgreSQL
   - runtime GSAs and Workload Identity bindings
   - Secret Manager payload for Nessie DB credentials

### Local env file

Create the local env file once and keep the real values out of git:

```bash
cp local/prod.env.example local/prod.env.sh
```

Fill in at least:

- `GCP_PROJECT_ID`
- `GCP_REGION`
- `GCP_ZONES`
- `GKE_CLUSTER_NAME`
- `ARGOCD_ADMIN_PASSWORD` or `ARGOCD_ADMIN_BCRYPT_HASH`
- `GRAFANA_ADMIN_PASSWORD`
- `CLOUDFLARE_API_TOKEN`

The env file is also the source of truth for environment-specific sensitive values used during bootstrap. `scripts/prod-up.sh` validates the file before it runs any expensive Terraform or cluster operations.

### Provision

Run the full production bootstrap with one command:

```bash
./scripts/prod-up.sh --env prod
```

What it does:

- loads `local/prod.env.sh`
- validates required variables and tooling
- applies Terraform in order: `00-network` -> `10-gke` -> `20-shared-services`
- fetches GKE credentials with `gcloud container clusters get-credentials`
- seeds bootstrap secrets into GCP Secret Manager
- installs or upgrades Argo CD
- applies the prod `AppProject` and root app
- waits for the key External Secrets, gateway, certificate, and public Argo CD endpoint to become ready

`--auto-approve` is available if you want Terraform applies to skip the interactive confirmation prompt.

The production root app ships the shared public access path plus the managed data services that are safe to run on GKE today:

- `argocd`
- `security-external-secrets`
- `security-gcp-secretmanager`
- `security-cert-manager`
- `monitoring`
- `logging-elasticsearch`
- `logging-kibana`
- `logging-fluent-bit`
- `platform-public-gateway`
- `spark-operator`
- `storage-nessie`
- `bi-trino`

### Destroy

Destroy runs in the reverse order and asks for confirmation unless you pass `--force`:

```bash
./scripts/prod-destroy.sh --env prod
```

Force mode is available for unattended teardown:

```bash
./scripts/prod-destroy.sh --env prod --force
```

The destroy flow:

- loads and validates the local env file
- performs best-effort Argo CD cleanup while the cluster still exists
- destroys `20-shared-services` -> `10-gke` -> `00-network`

Notes:

- `prod-destroy.sh` enables bucket `force_destroy` during teardown so the lake bucket does not block destroy when it contains objects.
- Some committed prod manifests still assume the portfolio repo's current naming conventions and project-specific values. If you change derived names such as the bucket, Cloud SQL instance, or runtime GSA identities, keep those committed prod values aligned with your env file.

Details are documented in `docs/prod-gke-public-access.md`. Managed-service mapping and migration rationale live in `docs/prod-gcp-managed-services-migration.md`.

## Kind image cache (GHCR)

`scripts/dev-kind-up.sh` preloads selected images into kind nodes from local Docker cache:

- `ghcr.io/kubeflow/spark-operator/controller:2.4.0`
- `ghcr.io/alexwlodek/spark-demo-job:latest`
- `ghcr.io/alexwlodek/order-generator:latest`

Tuning:

- `KIND_PRELOAD_PULL_MISSING=1` (default): pulls missing images to local Docker cache, then loads them into kind
- `KIND_PRELOAD_IMAGES="image1:tag image2:tag"`: override preload list
- `KIND_PRELOAD_IMAGES=""`: disable preload cache
- `KIND_FIX_NODE_DNS=0` (default): keep kind node DNS as-is; set to `1` only if node-level pulls have DNS issues
- `KIND_FIX_NODE_DNS_FORCE=0` (default): on `kindest/node:v1.34+`, DNS rewrite is skipped unless force is explicitly set to `1`
- `KIND_NODE_DNS_SERVERS="1.1.1.1 8.8.8.8"`: DNS servers used by node-level image pulls
- `KIND_WAIT_NODES_TIMEOUT=300s`: timeout for all nodes to become `Ready`
- `INGRESS_WAIT_TIMEOUT=240s`: timeout for ingress admission secret creation

## Observability drills

Dedicated drill assets are in:

- `tests/observability/bad-image-drill`
- `tests/observability/logging-smoke`

## Central logging (EFK-lite)

Stack uses:

- Elasticsearch (Bitnami chart)
- Kibana (Bitnami chart)
- Fluent Bit (DaemonSet log collector)

Argo applications:

- `logging-elasticsearch`
- `logging-kibana`
- `logging-fluent-bit`

Quick access (dev):

```bash
scripts/dev-ui-links.sh
```

## Spark demo job (GitOps)

`demo-apps` deploys a `SparkApplication` from `charts/demo-app`.

- chart: `charts/demo-app`
- job code: `apps/spark-job/job.py`
- image build source: `apps/spark-job/Dockerfile`
- values consumed by Argo: `values/common/demo-apps.yaml` + `values/dev/demo-apps.yaml`

`spark-operator` is configured to run jobs in namespaces:

- `apps`
- `spark-operator`

## Streaming pipeline (GitOps, DEV reference)

DEV stack adds production-like near-real-time path:

- `streaming-kafka` (single-node Kafka in-cluster)
- `storage-minio` (S3-compatible object storage for checkpoints + Parquet)
- `storage-nessie-db` (PostgreSQL metadata backend for Nessie)
- `storage-nessie` (Iceberg catalog service)
- `bi-trino` (single-node SQL engine for ad-hoc querying and BI connectivity)
- `bi-metabase` (BI UI connected to Trino for dashboards and ad-hoc analysis)
- `streaming-pipeline` (orders generator + Spark Structured Streaming + alerts + dashboard)

Main assets:

- generator code: `apps/order-generator/generator.py`
- streaming Spark code: `apps/spark-job/streaming_job.py`
- charts: `charts/streaming-kafka`, `charts/storage-minio`, `charts/storage-nessie-db`, `charts/storage-nessie`, `charts/bi-trino`, `charts/bi-metabase`, `charts/streaming-pipeline`
- Argo apps:
  - `clusters/dev/apps/streaming-kafka.yaml`
  - `clusters/dev/apps/storage-minio.yaml`
  - `clusters/dev/apps/storage-nessie-db.yaml`
  - `clusters/dev/apps/storage-nessie.yaml`
  - `clusters/dev/apps/bi-trino.yaml`
  - `clusters/dev/apps/bi-metabase.yaml`
  - `clusters/dev/apps/streaming-pipeline.yaml`
- values:
  - common: `values/common/streaming-*.yaml`, `values/common/storage-*.yaml`, `values/common/bi-*.yaml`
  - dev: `values/dev/streaming-*.yaml`, `values/dev/storage-*.yaml`, `values/dev/bi-*.yaml`
  - prod overrides: `values/prod/streaming-*.yaml`, `values/prod/storage-*.yaml`, `values/prod/bi-*.yaml`

Spark job performs:

- Kafka ingest (`orders` topic)
- event-time windowing + watermark
- aggregations (`events`, `revenue`)
- checkpointing and Parquet sink to object storage
- Prometheus metrics export (`inputRowsPerSecond`, `processedRowsPerSecond`, batch duration, lag, failures)

## DEV vs PROD data services

- DEV keeps local stateful components for a fully self-contained kind environment:
  - `streaming-kafka`
  - `storage-minio`
  - `storage-nessie-db`
  - `bi-metabase` with local PVC storage
- PROD now uses managed GCP backends where the repo already has a clean contract:
  - MinIO -> GCS
  - Nessie PostgreSQL -> Cloud SQL for PostgreSQL
  - object-store credentials -> Workload Identity
  - in-cluster secret backend integration -> External Secrets + GCP Secret Manager
- `storage-nessie` and `bi-trino` are now part of the prod root app set.
- `streaming-pipeline` prod values are prepared for GCS, but the app is intentionally not enrolled in the prod root until a real managed Kafka endpoint is provided.
- `streaming-kafka`, `storage-minio`, and `storage-nessie-db` remain DEV-only.

## Secret flow

DEV uses local Kubernetes Secrets created by `scripts/dev-secrets-apply.sh`.
PROD is prepared for `External Secrets Operator + GCP Secret Manager`.

Charts prepared for injected secrets (`existingSecret` support):

- `charts/storage-minio` -> `auth.existingSecret` (`root-user`, `root-password`)
- `charts/storage-nessie` -> `database.existingSecret` (`db-username`, `db-password`)
- `charts/storage-nessie-db` -> `auth.existingSecret` (`database`, `username`, `password`, `postgres-password`)

Current PROD runtime secret model:

1. External Secrets syncs control-plane and app credentials from GCP Secret Manager.
2. Nessie gets DB credentials from Secret Manager, while Cloud SQL connectivity is handled through Workload Identity plus the Cloud SQL proxy sidecar.
3. Spark and Trino use Workload Identity for GCS and no longer need S3-style static credentials in prod.

## Local secrets on DEV (kind)

DEV apps consume Kubernetes Secrets via:

- `values/dev/storage-minio.yaml` -> `auth.existingSecret: platform-minio-creds`
- `values/dev/storage-nessie.yaml` -> `database.existingSecret: platform-nessie-creds`
- `values/dev/storage-nessie-db.yaml` -> `auth.existingSecret: platform-nessie-db-creds`
- `values/dev/monitoring.yaml` -> `grafana.admin.existingSecret: platform-grafana-admin`

Local bootstrap:

```bash
scripts/dev-secrets-apply.sh
```

Environment overrides accepted by the script:

- `MINIO_ROOT_USER`
- `MINIO_ROOT_PASSWORD`
- `NESSIE_DB_NAME`
- `NESSIE_DB_USER`
- `NESSIE_DB_PASSWORD`
- `NESSIE_DB_POSTGRES_PASSWORD`
- `GRAFANA_ADMIN_USER`
- `GRAFANA_ADMIN_PASSWORD`

## GCP Secret Manager on PROD (GKE target)

Production manifests live in:

- `clusters/prod/apps/security-external-secrets.yaml`
- `clusters/prod/apps/security-gcp-secretmanager.yaml`
- `clusters/prod/apps/security-cert-manager.yaml`
- `clusters/prod/security/gcp-secretmanager/*`
- `values/prod/external-secrets.yaml`

Production auth model:

- External Secrets uses GKE Workload Identity via the `external-secrets` service account annotation in `values/prod/external-secrets.yaml`.
- `values/prod/argocd.yaml` disables chart-managed secret creation; `scripts/bootstrap-argocd.sh` seeds `argocd-secret` with `server.secretkey` until the `ExternalSecret` reconciles.
- `scripts/prod-cloudflare-secret-seed.sh` seeds the Cloudflare API token used by cert-manager DNS-01 and stores it in GCP Secret Manager for External Secrets to project into Kubernetes.
- `scripts/prod-grafana-secret-seed.sh` ensures Grafana admin credentials exist in GCP Secret Manager before the monitoring chart syncs; on first bootstrap it reuses any existing payload or generates a password automatically.

Defaults used by production `ExternalSecret` manifests:

- `spark-platform-prod-argocd`
- `spark-platform-prod-cert-manager-cloudflare`
- `spark-platform-prod-monitoring-grafana`
- `spark-platform-prod-storage-nessie`

## CI/CD for Spark image

Workflow: `.github/workflows/spark-job-image.yml` (GHCR)

Flow:

1. Build and push image to GitHub Container Registry (`ghcr.io`) with immutable tag `sha-<12 chars>`.
2. Push floating tags (`main`, `latest`) for quick DEV rollout.

## CI/CD for generator image

Workflow: `.github/workflows/order-generator-image.yml` (GHCR)

Flow:

1. Build and push generator image to GHCR with immutable tag `sha-<12 chars>`.
2. Auto-update `values/dev/streaming-generator-image.yaml` in `main`.
3. Argo CD auto-sync rolls out new generator tag in DEV.
