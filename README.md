# GitOps Data Platform

GitOps-managed Kubernetes platform project with a fully reproducible local `kind` environment and a production-oriented GKE foundation. It demonstrates environment layering, platform services, observability, and example streaming/data workloads without claiming finished production scope.

## Project overview

This repository models a small cloud-native data platform across two environments:

- `dev` is a local `kind` cluster bootstrapped with Argo CD and a fully local platform/data path.
- `prod` is a GKE-oriented target environment with staged Terraform, GitOps bootstrap, managed storage/database foundations, and selected platform services.

The project is strongest as a platform engineering portfolio piece: it shows how infrastructure, Kubernetes add-ons, data services, and sample workloads can be composed and operated through GitOps with clear environment boundaries.

## Architecture summary

- Control plane: Argo CD `AppProject` plus app-of-apps from `clusters/<env>/root.yaml`
- Configuration model: reusable local charts in `charts/`, shared defaults in `values/common`, and environment overlays in `values/dev` and `values/prod`
- Local dev data path: `order-generator` -> Kafka -> Spark Structured Streaming -> Iceberg/Nessie -> Trino -> Metabase
- Local observability: kube-prometheus-stack, Grafana, Fluent Bit, Elasticsearch, Kibana, plus drills under `tests/`
- Production-oriented foundation: Terraform stages for network, GKE, and shared services; External Secrets plus GCP Secret Manager; cert-manager; shared public Gateway; prod overlays for Nessie and Trino on managed GCP services
- Current boundary: prod values for the streaming pipeline exist, but `streaming-pipeline` is not currently part of the prod root application set because a managed Kafka endpoint is not defined in the repository

The sections below are the current recruiter-facing source of truth for the repository scope and architecture.

## Tech stack

- Platform and GitOps: Kubernetes, Argo CD, Helm, kind
- Cloud and infrastructure: Terraform, GKE, VPC networking, Cloud NAT, Cloud SQL, GCS, Secret Manager, Cloudflare DNS
- Security and exposure: Workload Identity, External Secrets Operator, cert-manager, Gateway API
- Data platform components: Apache Kafka, Spark Operator, Spark Structured Streaming, Apache Iceberg, Project Nessie, Trino, Metabase
- Observability: kube-prometheus-stack, Prometheus, Grafana, Fluent Bit, Elasticsearch, Kibana
- Application/runtime code: Python, PySpark, JSON Schema, GitHub Actions for container image builds

## What is currently implemented

### Already implemented

- One-command local bootstrap with `scripts/dev-up.sh`
- Argo CD-managed environment layering with separate `dev` and `prod` roots
- Local dev platform services for monitoring, logging, Kafka, MinIO, Nessie, in-cluster PostgreSQL, Trino, Metabase, and Spark Operator
- Example workloads in `dev`: `order-generator` and a Spark Structured Streaming job writing Bronze/Silver/Gold-style analytical tables
- Drill and validation assets under `tests/` for logging, alerting, and streaming replay/idempotency checks
- Production-oriented Terraform foundations in `infra/envs/prod/00-network`, `10-gke`, and `20-shared-services`
- Production GitOps foundations for Argo CD, External Secrets, cert-manager, public ingress via Gateway API, monitoring, logging, Spark Operator, Nessie, and Trino
- GitHub Actions workflows that build container images for the two example workloads

### Partially implemented

- Prod storage/query path is defined through overlays for GCS, Cloud SQL, Nessie, and Trino, but the full streaming workload is not enabled in the prod root app set
- `values/prod/streaming-pipeline.yaml` exists and is GCS/Nessie-oriented, but there is no `clusters/prod/apps/streaming-pipeline.yaml`
- `values/prod/bi-metabase.yaml` exists, but `bi-metabase` is not deployed from `clusters/prod/root.yaml`

### Not confirmed from the repository

- A managed Kafka implementation for prod
- A production-ready external database backing for Metabase
- Evidence in the repo that the full prod environment has been exercised end to end beyond bootstrap and deployment automation

## Current project status

This is best presented as a production-oriented platform portfolio project, not as a finished production system.

- `dev` is the most complete environment and demonstrates the end-to-end local platform flow
- `prod` demonstrates infrastructure design, secret management, public exposure, and managed-service adaptation patterns
- Feature parity between `dev` and `prod` is intentionally incomplete and should be stated explicitly
- This README is the main recruiter-facing entry point and focuses on the currently verifiable scope

## Local development flow

1. Run `scripts/dev-up.sh` to create the `kind` cluster, install ingress-nginx, apply local dev secrets, and bootstrap Argo CD.
2. Run `scripts/dev-ui-links.sh` to get the local ingress URLs for Argo CD, Grafana, Prometheus, Kibana, and Metabase.
3. Let Argo CD reconcile the `dev` root application set from `clusters/dev/apps`.
4. Use `tests/README.md` and the drill folders under `tests/` to exercise observability and streaming validation paths.

The dev flow is locally reproducible. The repo applies dev secrets directly into Kubernetes via `scripts/dev-secrets-apply.sh`, so local bootstrap does not depend on a cloud secret backend.

## Production-oriented foundation

The production side of the repository is built around a staged infrastructure model and GitOps bootstrap rather than a single monolithic script.

- `00-network`: VPC, subnet ranges, Cloud NAT, reserved public IP, Private Service Access, optional Cloudflare DNS records
- `10-gke`: GKE cluster, node pools, service accounts, Workload Identity plumbing
- `20-shared-services`: GCS lake bucket, Cloud SQL for Nessie metadata, runtime service accounts, Secret Manager payloads
- `scripts/prod-up.sh --env prod`: staged apply and bootstrap entrypoint
- `scripts/prod-destroy.sh --env prod`: reverse-order teardown entrypoint
- `clusters/prod/apps/*`: GitOps-managed platform services layered on top of the cluster foundation

This foundation is production-oriented, but the repository does not yet prove a full production data platform rollout with managed Kafka and full workload parity.

## Repository structure

```text
apps/       Example workloads: event producer and Spark streaming job
charts/     Local Helm charts for platform and data services
clusters/   Argo CD projects, root apps, and per-environment application sets
infra/      Terraform modules and staged prod environment roots
local/      Local env examples for operator-driven bootstrap
scripts/    Dev/prod bootstrap and helper entrypoints
tests/      Drill and validation assets for observability and streaming
values/     Shared and environment-specific Helm values
```

## Key engineering areas demonstrated

- GitOps environment layering with `clusters/<env>` and `values/<env>` separation
- Platform composition through a mix of local Helm charts and selected upstream charts
- Staged Terraform design that keeps infrastructure boundaries explicit
- Cloud adaptation through overlays instead of environment-specific template branching
- Secret flow design for local bootstrap versus production secret backends
- Observability and operational drills, not just happy-path deployment
- Example workload engineering with schemas, structured logs, metrics, and downstream analytical storage

## Next planned improvements

Based on the current repository state, the highest-value next improvements are:

- Add a managed Kafka or externally supplied Kafka configuration path so the streaming pipeline can be promoted to prod
- Decide whether Metabase belongs in prod scope and, if so, back it with an external database rather than a dev-style local state pattern
- Add lightweight validation automation for Helm rendering, Terraform validation, and shell scripts
- Add a small set of recruiter-facing screenshots for Argo CD, Grafana, Kibana, and Metabase after the README and repo structure are stabilized
