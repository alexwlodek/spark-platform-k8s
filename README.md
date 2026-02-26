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

## Argo CD bootstrap (generic)

`scripts/bootstrap-argocd.sh` supports environment/context selection:

```bash
DEPLOY_ENV=dev KUBE_CONTEXT=kind-spark-dev scripts/bootstrap-argocd.sh
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
scripts/dev-kibana-ui.sh
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
- `streaming-minio` (S3-compatible object storage for checkpoints + Parquet)
- `streaming-pipeline` (orders generator + Spark Structured Streaming + alerts + dashboard)

Main assets:

- generator code: `apps/order-generator/generator.py`
- streaming Spark code: `apps/spark-job/streaming_job.py`
- charts: `charts/streaming-kafka`, `charts/streaming-minio`, `charts/streaming-pipeline`
- Argo apps: `clusters/dev/apps/streaming-*.yaml`
- values:
  - common: `values/common/streaming-*.yaml`
  - dev: `values/dev/streaming-*.yaml`
  - prod placeholders: `values/prod/streaming-*.yaml`

Spark job performs:

- Kafka ingest (`orders` topic)
- event-time windowing + watermark
- aggregations (`events`, `revenue`)
- checkpointing and Parquet sink to MinIO (`s3a://streaming-lake/...`)
- Prometheus metrics export (`inputRowsPerSecond`, `processedRowsPerSecond`, batch duration, lag, failures)

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
