Production GCP infrastructure is split into three Terraform stacks:

- `infra/envs/gcp/network`
- `infra/envs/gcp/gke`
- `infra/envs/gcp/platform`

Apply `network` first, then `gke`, then `platform`.
