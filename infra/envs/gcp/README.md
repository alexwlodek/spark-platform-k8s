Production GCP infrastructure is split into three Terraform stacks:

- `infra/envs/gcp/network`
- `infra/envs/gcp/gke`
- `infra/envs/gcp/platform`

Apply `network` first, then `gke`, then `platform`.

Notes for `infra/envs/gcp/platform`:

- PostgreSQL 16+ can default to Cloud SQL Enterprise Plus if the edition is not set explicitly.
- This repo pins `cloud_sql_edition = "ENTERPRISE"` so the example custom tier `db-custom-1-3840` remains valid.
- If you switch to `cloud_sql_edition = "ENTERPRISE_PLUS"`, also switch `cloud_sql_tier` to a predefined tier such as `db-perf-optimized-N-2`.
