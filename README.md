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

## CI/CD for Spark image

Workflow: `.github/workflows/spark-job-image.yml` (GHCR)

Flow:

1. Build and push image to GitHub Container Registry (`ghcr.io`) with immutable tag `sha-<12 chars>`.
2. Create PR that updates `values/dev/demo-apps.yaml` with new `image.repository` and `image.tag`.
3. Merge PR and let Argo CD auto-sync apply new image.
