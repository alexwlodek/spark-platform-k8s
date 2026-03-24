# PROD GKE Phase 1

## Scope

This phase migrates only:

- Argo CD
- Spark Operator
- the minimum GCP secret plumbing required for Argo CD admin bootstrap

This phase does not migrate Kafka, MinIO, Nessie, Trino, Metabase, monitoring, or logging.

## Repo Analysis

- DEV is already environment-layered cleanly with `clusters/dev` plus `values/dev`, and PROD follows the same app-of-apps shape with `clusters/prod` plus `values/prod`.
- The generic bootstrap path in `scripts/bootstrap-argocd.sh` already works per environment and should stay the only imperative step before GitOps takeover.
- PROD already has staged GCP Secret Manager integration for External Secrets, but it currently targets more of the stack than phase 1 needs.
- PROD does not currently self-manage Argo CD from `clusters/prod/apps`; only `spark-operator` and manual security apps are present.
- `values/prod/argocd.yaml` is still AWS ALB specific and cannot be reused on GKE as-is.
- `infra/envs/prod` is still legacy AWS/EKS infrastructure and should remain untouched in this phase.
- Existing image automation is GHCR-based in `.github/workflows/spark-job-image.yml` and `.github/workflows/order-generator-image.yml`.

## Assumptions Called Out From The Repo

- Existing PROD manifests now assume GCP project ID `data-platform-prod-491113`.
- Existing PROD values already assume Argo CD hostname `argocd.prod.example.com`; replace it before public exposure.
- Existing PROD External Secrets flow expects Secret Manager secret `spark-platform-prod-argocd`.
- IDE tabs referenced `.secrets/data-platform-dev-secrets.json` and `scripts/dev-gcp-sm-seed.sh`, but neither exists in the current working tree.

## Required GCP APIs

Enable before running Terraform or bootstrap:

- `container.googleapis.com`
- `compute.googleapis.com`
- `iam.googleapis.com`
- `cloudresourcemanager.googleapis.com`
- `secretmanager.googleapis.com`

Recommended but optional in phase 1:

- `artifactregistry.googleapis.com`
- `dns.googleapis.com`

Can wait until later phases:

- `monitoring.googleapis.com`
- `logging.googleapis.com`
- `certificatemanager.googleapis.com`

Notes:

- `artifactregistry.googleapis.com` is optional in phase 1 because the repo already publishes Spark images to GHCR.
- `dns.googleapis.com` is optional if DNS stays outside Google Cloud.
- `certificatemanager.googleapis.com` can wait because phase 1 uses GKE `ManagedCertificate`, not Certificate Manager.

## Recommended Architecture

- GKE Standard, not Autopilot.
- Regional cluster with private nodes and a public control plane restricted by `master_authorized_networks`.
- One small `platform` node pool in phase 1 for Argo CD, External Secrets, ingress backends, and Spark Operator control plane.
- Workload Identity enabled from day 1.
- Default Terraform values use standard persistent disks to avoid exhausting SSD quota on fresh projects in `europe-central2`.
- GKE native external Application Load Balancer for Argo CD using:
  - static global IP
  - `ManagedCertificate`
  - `FrontendConfig` HTTPS redirect
- External Secrets mapped to a dedicated GSA with only `roles/secretmanager.secretAccessor`.
- Keep GHCR as the image source in phase 1 to avoid expanding the migration scope; add Artifact Registry when the first production Spark workloads move.

## Bootstrap Flow

1. Enable required APIs.
2. Copy `infra/envs/gcp/terraform.tfvars.example` to `infra/envs/gcp/terraform.tfvars` and adjust values if needed.
3. Run `scripts/prod-deploy.sh --all` from the repo root.
4. The script:
   - runs `terraform init`
   - runs `terraform apply`
   - configures `kubectl` against the new GKE cluster
   - seeds Secret Manager secret `spark-platform-prod-argocd`
   - bootstraps Argo CD and the prod root app
5. Argo CD reconciles:
   - `argocd`
   - `security-external-secrets`
   - `security-gcp-secretmanager`
   - `spark-operator`

The seeded payload contains:
   - `admin.password`
   - `admin.passwordMtime`
   - `server.secretkey`

## Secret Manager Payload For Argo CD

Secret name:

- `spark-platform-prod-argocd`

Required JSON payload:

```json
{
  "admin.password": "$2a$10$replace-with-bcrypt-hash",
  "admin.passwordMtime": "2026-03-23T00:00:00Z",
  "server.secretkey": "replace-with-32-plus-random-characters"
}
```

The `server.secretkey` must be present in Secret Manager because the ExternalSecret owns `argocd-secret` and should not remove the bootstrap key after reconciliation.

## Files Added Or Changed In This Phase

Added:

- `infra/envs/gcp/providers.tf`
- `infra/envs/gcp/variables.tf`
- `infra/envs/gcp/main.tf`
- `infra/envs/gcp/outputs.tf`
- `infra/envs/gcp/terraform.tfvars.example`
- `scripts/prod-deploy.sh`
- `clusters/prod/apps/argocd.yaml`
- `clusters/prod/argocd/frontendconfig.yaml`
- `clusters/prod/argocd/managed-certificate.yaml`
- `clusters/prod/security/gcp-secretmanager-phase1/clustersecretstore.yaml`
- `clusters/prod/security/gcp-secretmanager-phase1/externalsecret-argocd-admin.yaml`

Modified:

- `values/prod/argocd.yaml`
- `values/prod/spark-operator.yaml`
- `clusters/prod/apps/security-external-secrets.yaml`
- `clusters/prod/apps/security-gcp-secretmanager.yaml`
- `clusters/prod/projects/platform.yaml`

## Validation Commands

Enable required APIs:

```bash
gcloud services enable \
  container.googleapis.com \
  compute.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  secretmanager.googleapis.com \
  --project data-platform-prod-491113
```

Provision infrastructure:

```bash
cp infra/envs/gcp/terraform.tfvars.example infra/envs/gcp/terraform.tfvars
terraform -chdir=infra/envs/gcp init
terraform -chdir=infra/envs/gcp plan
terraform -chdir=infra/envs/gcp apply
```

Phased one-command deploy:

```bash
ARGOCD_ADMIN_PASSWORD='replace-with-strong-password' scripts/prod-deploy.sh --all
```

Supported overrides for `scripts/prod-deploy.sh`, `scripts/prod-up.sh`, and `scripts/prod-argocd-secret-seed.sh`:

- `PROJECT_ID`
- `REGION`
- `CLUSTER_NAME`
- `TERRAFORM_GCP_DIR`
- `AUTO_APPROVE`
- `ARGOCD_SECRET_NAME`
- `ARGOCD_ADMIN_PASSWORD`
- `ARGOCD_ADMIN_BCRYPT_HASH`
- `ARGOCD_ADMIN_PASSWORD_MTIME`
- `ARGOCD_SERVER_SECRETKEY`

Optional split modes if you want resumable phases:

```bash
scripts/prod-deploy.sh --infra
ARGOCD_ADMIN_PASSWORD='replace-with-strong-password' scripts/prod-deploy.sh --bootstrap
```

Optional lower-level steps if you want them fully manual:

```bash
gcloud container clusters get-credentials data-platform-prod --region europe-central2 --project data-platform-prod-491113
ARGOCD_ADMIN_PASSWORD='replace-with-strong-password' scripts/prod-argocd-secret-seed.sh
scripts/prod-bootstrap-argocd.sh
```

Validate phase 1:

```bash
kubectl -n argocd get applications
kubectl -n external-secrets get pods
kubectl -n argocd get ingress
kubectl -n argocd get managedcertificate
kubectl -n argocd get externalsecret
kubectl -n spark-operator get pods
kubectl get crd sparkapplications.sparkoperator.k8s.io
```

## Validation Checklist

- Argo CD app syncs cleanly from `clusters/prod/apps`.
- `security-external-secrets` becomes `Healthy` and `Synced`.
- `argocd-secret` exists and contains `admin.password`, `admin.passwordMtime`, and `server.secretkey`.
- `ManagedCertificate` becomes `Active`.
- Argo CD URL resolves to the reserved static IP and serves HTTPS.
- Spark Operator controller and webhook are `Ready`.
- No non-phase-1 apps exist in `clusters/prod/apps`.
