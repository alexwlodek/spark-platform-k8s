# Tests and Drills

This folder contains non-GitOps test/drill assets for DEV practice.

## Available drills

- `streaming/replay-idempotency`:
  - Freezes the `order-generator` safely under Argo CD
  - Runs two Kafka replay passes from `earliest` into dedicated `_replay` Iceberg tables
  - Verifies pass1 vs pass2 snapshot equality and checks for duplicate `event_id`
  - Restores the generator and leaves CSV artifacts in `/tmp`
- `observability/bad-image-drill`:
  - Deploys SparkApplication with invalid image tag
  - Adds a dedicated PrometheusRule
  - Lets you practice alert verification and cleanup
- `observability/logging-smoke`:
  - Emits synthetic logs from a pod in `apps`
  - Verifies indexing in Elasticsearch
  - Lets you practice EFK log pipeline checks
  - The order-generator logs are also duplicated into `order-generator-*` with a dedicated Kibana dashboard
