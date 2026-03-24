#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=prod-gcp-env.sh
source "${SCRIPT_DIR}/prod-gcp-env.sh"

DEPLOY_ENV="${DEPLOY_ENV:-prod}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"

DEPLOY_ENV="${DEPLOY_ENV}" \
ARGO_NAMESPACE="${ARGO_NAMESPACE}" \
KUBE_CONTEXT="${KUBE_CONTEXT}" \
"${SCRIPT_DIR}/bootstrap-argocd.sh"
