#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-spark-dev}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
ARGOCD_INSTALL_URL="${ARGOCD_INSTALL_URL:-https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-240s}"

ARGO_SERVER_REQ_CPU="${ARGO_SERVER_REQ_CPU:-200m}"
ARGO_SERVER_REQ_MEM="${ARGO_SERVER_REQ_MEM:-256Mi}"
ARGO_SERVER_LIM_CPU="${ARGO_SERVER_LIM_CPU:-1}"
ARGO_SERVER_LIM_MEM="${ARGO_SERVER_LIM_MEM:-1Gi}"

ARGO_CONTROLLER_REQ_CPU="${ARGO_CONTROLLER_REQ_CPU:-300m}"
ARGO_CONTROLLER_REQ_MEM="${ARGO_CONTROLLER_REQ_MEM:-512Mi}"
ARGO_CONTROLLER_LIM_CPU="${ARGO_CONTROLLER_LIM_CPU:-2}"
ARGO_CONTROLLER_LIM_MEM="${ARGO_CONTROLLER_LIM_MEM:-2Gi}"

ARGO_REPOSERVER_REQ_CPU="${ARGO_REPOSERVER_REQ_CPU:-300m}"
ARGO_REPOSERVER_REQ_MEM="${ARGO_REPOSERVER_REQ_MEM:-512Mi}"
ARGO_REPOSERVER_LIM_CPU="${ARGO_REPOSERVER_LIM_CPU:-2}"
ARGO_REPOSERVER_LIM_MEM="${ARGO_REPOSERVER_LIM_MEM:-2Gi}"

ARGO_APPSET_REQ_CPU="${ARGO_APPSET_REQ_CPU:-100m}"
ARGO_APPSET_REQ_MEM="${ARGO_APPSET_REQ_MEM:-256Mi}"
ARGO_APPSET_LIM_CPU="${ARGO_APPSET_LIM_CPU:-500m}"
ARGO_APPSET_LIM_MEM="${ARGO_APPSET_LIM_MEM:-512Mi}"

ARGO_REDIS_REQ_CPU="${ARGO_REDIS_REQ_CPU:-100m}"
ARGO_REDIS_REQ_MEM="${ARGO_REDIS_REQ_MEM:-128Mi}"
ARGO_REDIS_LIM_CPU="${ARGO_REDIS_LIM_CPU:-300m}"
ARGO_REDIS_LIM_MEM="${ARGO_REDIS_LIM_MEM:-256Mi}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require kubectl

kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

echo "Creating namespace '${ARGO_NAMESPACE}' (if missing)..."
kubectl get ns "${ARGO_NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${ARGO_NAMESPACE}"

echo "Downloading Argo CD install manifest..."
TMP_DIR="$(mktemp -d)"
INSTALL="${TMP_DIR}/install.yaml"
curl -fsSL "${ARGOCD_INSTALL_URL}" -o "${INSTALL}"

echo "Installing Argo CD CRDs (server-side apply)..."
# Apply only CRDs first, server-side (avoids huge last-applied annotation limit)
kubectl apply --server-side -f <(awk 'BEGIN{RS="---\n"} /kind: CustomResourceDefinition/{print "---\n"$0}' "${INSTALL}")

echo "Installing the rest of Argo CD (normal apply)..."
kubectl apply -n "${ARGO_NAMESPACE}" -f <(awk 'BEGIN{RS="---\n"} $0 !~ /kind: CustomResourceDefinition/{print "---\n"$0}' "${INSTALL}")

echo "Setting Argo CD resources for DEV..."
patch_if_exists() {
  local obj="$1"
  local patch="$2"
  if kubectl -n "${ARGO_NAMESPACE}" get "${obj}" >/dev/null 2>&1; then
    kubectl -n "${ARGO_NAMESPACE}" patch "${obj}" --type merge -p "${patch}" >/dev/null
  fi
}

patch_resources() {
  local obj="$1"
  local container="$2"
  local req_cpu="$3"
  local req_mem="$4"
  local lim_cpu="$5"
  local lim_mem="$6"
  local patch
  patch="$(printf '{"spec":{"template":{"spec":{"containers":[{"name":"%s","resources":{"requests":{"cpu":"%s","memory":"%s"},"limits":{"cpu":"%s","memory":"%s"}}}]}}}}' \
    "${container}" "${req_cpu}" "${req_mem}" "${lim_cpu}" "${lim_mem}")"
  patch_if_exists "${obj}" "${patch}"
}

patch_resources "statefulset/argocd-application-controller" "argocd-application-controller" \
  "${ARGO_CONTROLLER_REQ_CPU}" "${ARGO_CONTROLLER_REQ_MEM}" "${ARGO_CONTROLLER_LIM_CPU}" "${ARGO_CONTROLLER_LIM_MEM}"
patch_resources "deployment/argocd-repo-server" "argocd-repo-server" \
  "${ARGO_REPOSERVER_REQ_CPU}" "${ARGO_REPOSERVER_REQ_MEM}" "${ARGO_REPOSERVER_LIM_CPU}" "${ARGO_REPOSERVER_LIM_MEM}"
patch_resources "deployment/argocd-server" "argocd-server" \
  "${ARGO_SERVER_REQ_CPU}" "${ARGO_SERVER_REQ_MEM}" "${ARGO_SERVER_LIM_CPU}" "${ARGO_SERVER_LIM_MEM}"
patch_resources "deployment/argocd-applicationset-controller" "argocd-applicationset-controller" \
  "${ARGO_APPSET_REQ_CPU}" "${ARGO_APPSET_REQ_MEM}" "${ARGO_APPSET_LIM_CPU}" "${ARGO_APPSET_LIM_MEM}"
patch_resources "deployment/argocd-redis" "redis" \
  "${ARGO_REDIS_REQ_CPU}" "${ARGO_REDIS_REQ_MEM}" "${ARGO_REDIS_LIM_CPU}" "${ARGO_REDIS_LIM_MEM}"

echo "Waiting for Argo CD API server..."
kubectl -n "${ARGO_NAMESPACE}" rollout status deployment/argocd-server --timeout="${ROLLOUT_TIMEOUT}"
kubectl -n "${ARGO_NAMESPACE}" rollout status statefulset/argocd-application-controller --timeout="${ROLLOUT_TIMEOUT}"
kubectl -n "${ARGO_NAMESPACE}" rollout status deployment/argocd-repo-server --timeout="${ROLLOUT_TIMEOUT}"
kubectl -n "${ARGO_NAMESPACE}" rollout status deployment/argocd-applicationset-controller --timeout="${ROLLOUT_TIMEOUT}"
kubectl -n "${ARGO_NAMESPACE}" rollout status deployment/argocd-redis --timeout="${ROLLOUT_TIMEOUT}"

echo "Applying AppProject + root application..."
kubectl apply -n "${ARGO_NAMESPACE}" -f clusters/dev/projects/platform.yaml
kubectl apply -n "${ARGO_NAMESPACE}" -f clusters/dev/root.yaml

echo "✅ Argo CD bootstrapped and root app applied."
echo "Check:"
echo "  kubectl -n argocd get applications"
