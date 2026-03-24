Production GCP infrastructure is split into two Terraform stacks:

- `infra/envs/gcp/network`
- `infra/envs/gcp/gke`

Apply `network` first, then `gke`.
