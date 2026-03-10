#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-data-platform-prod}"
DEPLOY_ENV="${DEPLOY_ENV:-prod}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
KUBE_CONTEXT="${KUBE_CONTEXT:-${CLUSTER_NAME}}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEPLOY_ENV="${DEPLOY_ENV}" \
ARGO_NAMESPACE="${ARGO_NAMESPACE}" \
KUBE_CONTEXT="${KUBE_CONTEXT}" \
"${SCRIPT_DIR}/bootstrap-argocd.sh"
