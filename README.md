# spark-platform-k8s

## DEV bootstrap

```bash
scripts/dev-up.sh
```

This creates a kind cluster, installs ingress-nginx and bootstraps Argo CD with app-of-apps.

### Kind image cache (GHCR)

`scripts/dev-kind-up.sh` preloads selected images into kind nodes from local Docker cache:

- `ghcr.io/kubeflow/spark-operator/controller:2.4.0`
- `ghcr.io/alexwlodek/spark-demo-job:latest`

This avoids image pulls from inside kind nodes (helpful when node DNS/network to `ghcr.io` is flaky).

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

- `bad-image-drill`: broken Spark image + dedicated PrometheusRule (alert practice)
- `logging-smoke`: synthetic app logs + Elasticsearch verification (log pipeline practice)

## Central logging (EFK-lite)

DEV stack uses:

- Elasticsearch (Bitnami chart)
- Kibana (Bitnami chart)
- Fluent Bit (DaemonSet log collector)

Argo applications:

- `logging-elasticsearch`
- `logging-kibana`
- `logging-fluent-bit`

Quick access:

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

## CI/CD for Spark image

Workflow: `.github/workflows/spark-job-image.yml` (GHCR)

Flow:

1. Build and push image to GitHub Container Registry (`ghcr.io`) with immutable tag `sha-<12 chars>`.
2. Create PR that updates `values/dev/demo-apps.yaml` with new `image.repository` and `image.tag`.
3. Merge PR -> Argo CD auto-sync applies new image (full GitOps).

Optional GitHub repository variables:

- `GHCR_IMAGE_REPOSITORY` (path without registry, example: `my-org/spark-demo-job`)

If `GHCR_IMAGE_REPOSITORY` is not set, workflow uses:

- `<github-owner-lowercase>/spark-demo-job`

Note:

- For kind/dev, make the GHCR package public, or configure image pull secret and set `spark.imagePullSecrets`.

Recommended branch protection:

- Require PR review for `main`
- Restrict direct pushes to `main`
