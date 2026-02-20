# Tests and Drills

This folder contains non-GitOps test/drill assets for DEV practice.

## Available drills

- `observability/bad-image-drill`:
  - Deploys SparkApplication with invalid image tag
  - Adds a dedicated PrometheusRule
  - Lets you practice alert verification and cleanup
- `observability/logging-smoke`:
  - Emits synthetic logs from a pod in `apps`
  - Verifies indexing in Elasticsearch
  - Lets you practice EFK log pipeline checks
