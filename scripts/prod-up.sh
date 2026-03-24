#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=prod-gcp-env.sh
source "${SCRIPT_DIR}/prod-gcp-env.sh"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require gcloud

echo "Configuring kubectl context for GKE cluster '${CLUSTER_NAME}'..."
gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}" >/dev/null

"${SCRIPT_DIR}/prod-argocd-secret-seed.sh"

PROJECT_ID="${PROJECT_ID}" \
REGION="${REGION}" \
CLUSTER_NAME="${CLUSTER_NAME}" \
"${SCRIPT_DIR}/prod-bootstrap-argocd.sh"

echo
echo "✅ PROD phase-1 bootstrap ready."
echo "Check:"
echo "  - kubectl -n argocd get applications"
echo "  - kubectl -n argocd get ingress"
echo "  - kubectl -n spark-operator get pods"
