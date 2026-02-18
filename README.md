# spark-platform-k8s

## DEV bootstrap

```bash
scripts/dev-up.sh
```

This creates a kind cluster, installs ingress-nginx and bootstraps Argo CD with app-of-apps.

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
