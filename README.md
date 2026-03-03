# spark-platform-k8s

## Environments

Current setup:

- `dev` cluster on kind: `clusters/dev` + `values/dev`
- shared values: `values/common`

GitOps uses app-of-apps (`root.yaml`) and in-cluster destination (`https://kubernetes.default.svc`).

## DEV bootstrap (kind)

```bash
scripts/dev-up.sh
```

This creates a kind cluster, installs ingress-nginx and bootstraps Argo CD with app-of-apps.

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
```

Wrappers:

- `scripts/dev-bootstrap-argocd.sh`

By default bootstrap installs Argo CD via pinned Helm chart version (`7.7.0`) and then applies:

- `clusters/<env>/projects/platform.yaml`
- `clusters/<env>/root.yaml`

## Kind image cache (GHCR)

`scripts/dev-kind-up.sh` preloads selected images into kind nodes from local Docker cache:

- `ghcr.io/kubeflow/spark-operator/controller:2.4.0`
- `ghcr.io/alexwlodek/spark-demo-job:latest`
- `ghcr.io/alexwlodek/order-generator:latest`

Tuning:

- `KIND_PRELOAD_PULL_MISSING=1` (default): pulls missing images to local Docker cache, then loads them into kind
- `KIND_PRELOAD_IMAGES="image1:tag image2:tag"`: override preload list
- `KIND_PRELOAD_IMAGES=""`: disable preload cache
- `KIND_FIX_NODE_DNS=1` (default): rewrites `/etc/resolv.conf` on all kind nodes
- `KIND_NODE_DNS_SERVERS="1.1.1.1 8.8.8.8"`: DNS servers used by node-level image pulls

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
  - prod placeholders: `values/prod/streaming-*.yaml`, `values/prod/storage-*.yaml`, `values/prod/bi-*.yaml`

Spark job performs:

- Kafka ingest (`orders` topic)
- event-time windowing + watermark
- aggregations (`events`, `revenue`)
- checkpointing and Parquet sink to MinIO (`s3a://streaming-lake/...`)
- Prometheus metrics export (`inputRowsPerSecond`, `processedRowsPerSecond`, batch duration, lag, failures)

## Security hardening (phase 1)

Baseline for secret management in DEV:

- Argo app: `clusters/dev/apps/security-external-secrets.yaml`
- values: `values/common/external-secrets.yaml`, `values/dev/external-secrets.yaml`
- Helm source: `https://charts.external-secrets.io` (chart `external-secrets`, `targetRevision: 1.3.2`)

Charts prepared for external secret injection (`existingSecret` support):

- `charts/storage-minio` -> `auth.existingSecret` (`root-user`, `root-password`)
- `charts/storage-nessie` -> `database.existingSecret` (`db-username`, `db-password`)
- `charts/storage-nessie-db` -> `auth.existingSecret` (`database`, `username`, `password`, `postgres-password`)

Recommended next step before SSO:

1. Move remaining in-values credentials (`values/common/streaming-pipeline.yaml`, `values/common/bi-trino.yaml`) to Kubernetes Secrets.
2. Bind Spark/Trino runtime config to those Secrets (no plaintext access keys in Git).
3. After secret flow is stable, enable OIDC SSO for Argo CD and UI tools.

## AWS Secrets Manager on DEV (kind)

Argo apps and manifests:

- `clusters/dev/apps/security-external-secrets.yaml`
- `clusters/dev/apps/security-aws-secretsmanager.yaml`
- `clusters/dev/security/aws-secretsmanager/*`

DEV storage apps use externalized credentials via:

- `values/dev/storage-minio.yaml` -> `auth.existingSecret: platform-minio-creds`
- `values/dev/storage-nessie.yaml` -> `database.existingSecret: platform-nessie-creds`
- `values/dev/storage-nessie-db.yaml` -> `auth.existingSecret: platform-nessie-db-creds`

Local bootstrap for kind:

```bash
# 1) Seed example secrets in AWS Secrets Manager
scripts/dev-aws-sm-seed.sh

# 2) Provide AWS credentials to ESO in-cluster
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
# optional for temporary STS credentials
export AWS_SESSION_TOKEN=...
scripts/dev-aws-sm-auth.sh
```

Defaults used by `ExternalSecret` manifests:

- `/spark-platform/dev/storage-minio`
- `/spark-platform/dev/storage-nessie`
- `/spark-platform/dev/storage-nessie-db`

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
