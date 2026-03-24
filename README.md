# spark-platform-k8s

## Environments

Current setup:

- `dev` cluster on kind (`data-platform-dev`): `clusters/dev` + `values/dev`
- `prod` target environment (`data-platform-prod`): `clusters/prod` + `values/prod`
- shared values: `values/common`

`infra/envs/prod` is still a legacy AWS/EKS template set and is not the forward target. Production secrets have already been moved to the GCP Secret Manager flow described below.

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
DEPLOY_ENV=dev KUBE_CONTEXT=kind-data-platform-dev scripts/bootstrap-argocd.sh
DEPLOY_ENV=prod KUBE_CONTEXT=gke_data-platform-prod-491113_europe-central2_data-platform-prod scripts/bootstrap-argocd.sh
```

Wrappers:

- `scripts/dev-bootstrap-argocd.sh`
- `scripts/prod-deploy.sh` (`--infra`, `--bootstrap`, `--all`)
- `scripts/prod-bootstrap-argocd.sh`
- `scripts/prod-up.sh` (GKE phase-1: get credentials + seed Argo CD secret in Secret Manager + bootstrap Argo CD)

By default bootstrap installs Argo CD via pinned Helm chart version (`7.7.0`) and then applies:

- `clusters/<env>/projects/platform.yaml`
- `clusters/<env>/root.yaml`

## PROD infrastructure templates (legacy AWS/EKS)

Terraform for production infrastructure lives in:

- `infra/envs/prod`

This stack is still AWS-specific legacy scaffolding and will be replaced in later phases of the GCP migration. Today it creates:

- VPC (3 AZ)
- EKS cluster `data-platform-prod`
- IRSA roles (`aws-load-balancer-controller`, `external-secrets`, `ebs-csi`)
- EBS CSI addon
- AWS Load Balancer Controller

Suggested flow:

```bash
cp infra/envs/prod/terraform.tfvars.example infra/envs/prod/terraform.tfvars
terraform -chdir=infra/envs/prod init
terraform -chdir=infra/envs/prod plan
terraform -chdir=infra/envs/prod apply

# configure kubectl context (see terraform output too)
aws eks update-kubeconfig --region eu-central-1 --name data-platform-prod --alias data-platform-prod

# bootstrap Argo CD on prod cluster
scripts/prod-bootstrap-argocd.sh
```

Phase-1 production root app ships with `argocd`, `security-external-secrets`, `security-gcp-secretmanager`, and `spark-operator`.
The phased GKE production entrypoint is:

```bash
ARGOCD_ADMIN_PASSWORD='replace-with-strong-password' scripts/prod-deploy.sh --all
```

You can also split it explicitly:

```bash
scripts/prod-deploy.sh --infra
ARGOCD_ADMIN_PASSWORD='replace-with-strong-password' scripts/prod-deploy.sh --bootstrap
```

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

## Streaming pipeline (GitOps, DEV)

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
- checkpointing and Parquet sink to MinIO (`s3a://streaming-lake/...`)
- Prometheus metrics export (`inputRowsPerSecond`, `processedRowsPerSecond`, batch duration, lag, failures)

## Secret flow

DEV uses local Kubernetes Secrets created by `scripts/dev-secrets-apply.sh`.
PROD is prepared for `External Secrets Operator + GCP Secret Manager`.

Charts prepared for injected secrets (`existingSecret` support):

- `charts/storage-minio` -> `auth.existingSecret` (`root-user`, `root-password`)
- `charts/storage-nessie` -> `database.existingSecret` (`db-username`, `db-password`)
- `charts/storage-nessie-db` -> `auth.existingSecret` (`database`, `username`, `password`, `postgres-password`)

Recommended next step before SSO:

1. Move remaining in-values credentials (`values/common/streaming-pipeline.yaml`, `values/common/bi-trino.yaml`) to Kubernetes Secrets.
2. Bind Spark/Trino runtime config to those Secrets (no plaintext access keys in Git).
3. After secret flow is stable, enable OIDC SSO for Argo CD and UI tools.

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
- `clusters/prod/security/gcp-secretmanager/*`
- `values/prod/external-secrets.yaml`

Production auth model:

- External Secrets uses GKE Workload Identity via the `external-secrets` service account annotation in `values/prod/external-secrets.yaml`.
- `values/prod/argocd.yaml` disables chart-managed secret creation; `scripts/bootstrap-argocd.sh` seeds `argocd-secret` with `server.secretkey` until the `ExternalSecret` reconciles.

Defaults used by production `ExternalSecret` manifests:

- `spark-platform-prod-argocd`
- `spark-platform-prod-monitoring-grafana`
- `spark-platform-prod-storage-minio`
- `spark-platform-prod-storage-nessie`
- `spark-platform-prod-storage-nessie-db`

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
