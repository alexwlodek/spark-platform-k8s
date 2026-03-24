#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=prod-gcp-env.sh
source "${SCRIPT_DIR}/prod-gcp-env.sh"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
validate_identifier() {
  local name="$1"
  local value="$2"

  if [[ ! "${value}" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
    echo "Invalid ${name}: '${value}'" >&2
    echo "Set ${name} explicitly or run terraform apply first." >&2
    exit 1
  fi
}

require gcloud
require kubectl

validate_identifier PROJECT_ID "${PROJECT_ID}"
validate_identifier REGION "${REGION}"
validate_identifier CLUSTER_NAME "${CLUSTER_NAME}"

POST_BOOTSTRAP_WAIT_SECONDS="${POST_BOOTSTRAP_WAIT_SECONDS:-600}"

wait_for_deployment_ready() {
  local namespace="$1"
  local deployment="$2"
  local deadline=$((SECONDS + POST_BOOTSTRAP_WAIT_SECONDS))

  echo "Waiting for deployment ${namespace}/${deployment}..."
  while (( SECONDS < deadline )); do
    if kubectl -n "${namespace}" rollout status "deployment/${deployment}" --timeout=5s >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done

  echo "Timed out waiting for deployment ${namespace}/${deployment}" >&2
  return 1
}

wait_for_clustersecretstore_ready() {
  local name="$1"
  local deadline=$((SECONDS + POST_BOOTSTRAP_WAIT_SECONDS))
  local ready=""

  echo "Waiting for ClusterSecretStore ${name}..."
  while (( SECONDS < deadline )); do
    ready="$(kubectl get clustersecretstore "${name}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    if [[ "${ready}" == "True" ]]; then
      return 0
    fi
    sleep 5
  done

  echo "Timed out waiting for ClusterSecretStore ${name}" >&2
  return 1
}

wait_for_externalsecret_ready() {
  local namespace="$1"
  local name="$2"
  local deadline=$((SECONDS + POST_BOOTSTRAP_WAIT_SECONDS))
  local ready=""

  echo "Waiting for ExternalSecret ${namespace}/${name}..."
  while (( SECONDS < deadline )); do
    ready="$(kubectl -n "${namespace}" get externalsecret "${name}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    if [[ "${ready}" == "True" ]]; then
      return 0
    fi
    sleep 5
  done

  echo "Timed out waiting for ExternalSecret ${namespace}/${name}" >&2
  return 1
}

wait_for_secret_keys() {
  local namespace="$1"
  local name="$2"
  local deadline=$((SECONDS + POST_BOOTSTRAP_WAIT_SECONDS))
  local admin_password=""
  local admin_password_mtime=""
  local server_secretkey=""

  echo "Waiting for secret ${namespace}/${name} to contain Argo CD auth data..."
  while (( SECONDS < deadline )); do
    admin_password="$(kubectl -n "${namespace}" get secret "${name}" -o jsonpath='{.data.admin\.password}' 2>/dev/null || true)"
    admin_password_mtime="$(kubectl -n "${namespace}" get secret "${name}" -o jsonpath='{.data.admin\.passwordMtime}' 2>/dev/null || true)"
    server_secretkey="$(kubectl -n "${namespace}" get secret "${name}" -o jsonpath='{.data.server\.secretkey}' 2>/dev/null || true)"

    if [[ -n "${admin_password}" && -n "${admin_password_mtime}" && -n "${server_secretkey}" ]]; then
      return 0
    fi

    sleep 5
  done

  echo "Timed out waiting for secret ${namespace}/${name}" >&2
  return 1
}

echo "Setting active gcloud project to '${PROJECT_ID}'..."
gcloud config set project "${PROJECT_ID}" >/dev/null

echo "Configuring kubectl context for GKE cluster '${CLUSTER_NAME}'..."
gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}" >/dev/null

APPLY_K8S_SECRET=1 \
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}" \
"${SCRIPT_DIR}/prod-argocd-secret-seed.sh"

PROJECT_ID="${PROJECT_ID}" \
REGION="${REGION}" \
CLUSTER_NAME="${CLUSTER_NAME}" \
"${SCRIPT_DIR}/prod-bootstrap-argocd.sh"

wait_for_deployment_ready external-secrets external-secrets
wait_for_clustersecretstore_ready gcp-secretmanager
wait_for_externalsecret_ready argocd argocd-admin-credentials
wait_for_secret_keys argocd argocd-secret

kubectl -n argocd delete secret argocd-initial-admin-secret --ignore-not-found >/dev/null 2>&1 || true

echo
echo "✅ PROD phase-1 bootstrap ready."
echo "Check:"
echo "  - kubectl -n argocd get applications"
echo "  - kubectl -n argocd get ingress"
echo "  - kubectl -n spark-operator get pods"
