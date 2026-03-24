# PROD GKE Public Access

## Goal

Expose production platform UIs on GKE through one shared public entry point with:

- one reserved static IP
- clean hostnames
- Cloudflare DNS
- cert-manager wildcard TLS
- GitOps-managed routing

## Final shape

Infrastructure is split so the static IP survives cluster replacement:

- `infra/envs/gcp/network`
  - VPC
  - subnet + secondary ranges
  - Cloud NAT
  - reserved global public IP
  - optional Cloudflare DNS records
- `infra/envs/gcp/gke`
  - GKE cluster
  - platform node pool
  - Workload Identity service accounts

GitOps then layers public access on top:

- `security-external-secrets`
- `security-gcp-secretmanager`
- `security-cert-manager`
- `monitoring`
- `logging-*`
- `platform-public-gateway`

## Why Gateway API instead of one Ingress

The original phase-1 setup used a single GKE Ingress only for Argo CD.

For the shared production entry point, Argo CD, Grafana, and Kibana live in different namespaces:

- `argocd`
- `monitoring`
- `logging`

A single Kubernetes `Ingress` resource cannot directly route to Services across multiple namespaces. Instead of adding a proxy workaround, the repo now uses the GKE Gateway controller for the shared public entry point. That keeps:

- one static public IP
- one GKE-managed L7 entry point
- clean per-namespace ownership through `HTTPRoute`
- GitOps reconciliation in Argo CD

## Public endpoints

Default host layout:

- `argocd.prod.alexwlodek.com`
- `grafana.prod.alexwlodek.com`
- `kibana.prod.alexwlodek.com`

These are configured in:

- `infra/envs/gcp/network/terraform.tfvars`
- `values/prod/public-gateway.yaml`
- `values/prod/argocd.yaml`
- `values/prod/monitoring.yaml`

Replace `alexwlodek.com` before applying production changes.

## Terraform flow

Apply network first:

```bash
cp infra/envs/gcp/network/terraform.tfvars.example infra/envs/gcp/network/terraform.tfvars
terraform -chdir=infra/envs/gcp/network init
terraform -chdir=infra/envs/gcp/network apply
```

Then apply GKE:

```bash
cp infra/envs/gcp/gke/terraform.tfvars.example infra/envs/gcp/gke/terraform.tfvars
terraform -chdir=infra/envs/gcp/gke init
terraform -chdir=infra/envs/gcp/gke apply
```

The reserved public IP is created in the `network` stack with `prevent_destroy = true`, so deleting or recreating the cluster does not release the IP.

If `cloudflare_zone_id` is set in the `network` stack and a Cloudflare API token is present in the Terraform environment, Terraform also creates DNS records pointing all public hosts to the shared static IP.

## TLS flow

TLS is managed by cert-manager with Cloudflare DNS-01:

1. `scripts/prod-cloudflare-secret-seed.sh` stores the Cloudflare API token in GCP Secret Manager.
2. External Secrets projects that token into the `cert-manager` namespace as `cloudflare-api-token`.
3. `ClusterIssuer/letsencrypt-cloudflare-prod` uses that token for DNS-01.
4. `Certificate/prod-wildcard` issues `*.prod.alexwlodek.com`.
5. The shared Gateway terminates TLS with the generated secret.

Secret Manager payload for the Cloudflare token must be:

```json
{
  "api-token": "replace-with-cloudflare-api-token"
}
```

Recommended Cloudflare token permissions:

- `Zone / DNS / Edit`
- `Zone / Zone / Read`

Scope it only to the production zone.

## Bootstrap flow

One command:

```bash
ARGOCD_ADMIN_PASSWORD='replace-with-strong-password' \
CLOUDFLARE_API_TOKEN='replace-with-cloudflare-token' \
scripts/prod-deploy.sh --all
```

This performs:

1. `network` Terraform apply
2. `gke` Terraform apply
3. GKE credential setup
4. Secret Manager seed for Cloudflare token
5. Secret Manager + bootstrap Kubernetes seed for Argo CD admin secret
6. Argo CD bootstrap
7. GitOps reconciliation for cert-manager, monitoring, logging, and the shared Gateway

## Validation

Terraform outputs:

```bash
terraform -chdir=infra/envs/gcp/network output public_gateway_ip_address
terraform -chdir=infra/envs/gcp/network output public_hosts
terraform -chdir=infra/envs/gcp/gke output get_credentials_command
```

Kubernetes checks:

```bash
kubectl get gateway -A
kubectl get httproute -A
kubectl -n gateway-system get certificate
kubectl -n cert-manager get pods
kubectl -n monitoring get pods
kubectl -n logging get pods
kubectl -n argocd get applications
```

Expected result:

- one reserved public IP managed outside the cluster stack
- one shared public Gateway
- separate routes for Argo CD, Grafana, and Kibana
- wildcard TLS issued through Cloudflare DNS-01
- Cloudflare acting only as DNS and ACME validation
- all public exposure resources reconciled by Argo CD
