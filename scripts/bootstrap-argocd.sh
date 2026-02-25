#!/usr/bin/env bash
set -euo pipefail

DEPLOY_ENV="${DEPLOY_ENV:-dev}"
KUBE_CONTEXT="${KUBE_CONTEXT:-}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
ARGO_RELEASE_NAME="${ARGO_RELEASE_NAME:-argocd}"
ARGO_HELM_REPO_NAME="${ARGO_HELM_REPO_NAME:-argo}"
ARGO_HELM_REPO_URL="${ARGO_HELM_REPO_URL:-https://argoproj.github.io/argo-helm}"
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-7.7.0}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-300s}"
SKIP_INSTALL="${SKIP_INSTALL:-0}"

ROOT_FILE="clusters/${DEPLOY_ENV}/root.yaml"
PROJECT_FILE="clusters/${DEPLOY_ENV}/projects/platform.yaml"
COMMON_VALUES_FILE="values/common/argocd.yaml"
ENV_VALUES_FILE="values/${DEPLOY_ENV}/argocd.yaml"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
require kubectl

if [[ ! -f "${ROOT_FILE}" ]]; then
  echo "Missing root app manifest: ${ROOT_FILE}" >&2
  exit 1
fi

if [[ ! -f "${PROJECT_FILE}" ]]; then
  echo "Missing AppProject manifest: ${PROJECT_FILE}" >&2
  exit 1
fi

if [[ ! -f "${COMMON_VALUES_FILE}" ]]; then
  echo "Missing values file: ${COMMON_VALUES_FILE}" >&2
  exit 1
fi

if [[ ! -f "${ENV_VALUES_FILE}" ]]; then
  echo "Missing values file: ${ENV_VALUES_FILE}" >&2
  exit 1
fi

if [[ -n "${KUBE_CONTEXT}" ]]; then
  kubectl config use-context "${KUBE_CONTEXT}" >/dev/null
fi

CURRENT_CONTEXT="$(kubectl config current-context)"
echo "Bootstrapping Argo CD for environment '${DEPLOY_ENV}' on context '${CURRENT_CONTEXT}'..."

echo "Creating namespace '${ARGO_NAMESPACE}' (if missing)..."
kubectl get ns "${ARGO_NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${ARGO_NAMESPACE}"

if [[ "${SKIP_INSTALL}" != "1" ]]; then
  require helm

  echo "Installing Argo CD chart (version ${ARGOCD_CHART_VERSION})..."
  helm repo add "${ARGO_HELM_REPO_NAME}" "${ARGO_HELM_REPO_URL}" --force-update >/dev/null
  helm repo update "${ARGO_HELM_REPO_NAME}" >/dev/null

  helm upgrade --install "${ARGO_RELEASE_NAME}" "${ARGO_HELM_REPO_NAME}/argo-cd" \
    --namespace "${ARGO_NAMESPACE}" \
    --version "${ARGOCD_CHART_VERSION}" \
    -f "${COMMON_VALUES_FILE}" \
    -f "${ENV_VALUES_FILE}" \
    --wait \
    --timeout "${ROLLOUT_TIMEOUT}"
else
  echo "Skipping Argo CD install/upgrade (SKIP_INSTALL=1)."
fi

echo "Applying AppProject + root application for '${DEPLOY_ENV}'..."
kubectl apply -n "${ARGO_NAMESPACE}" -f "${PROJECT_FILE}"
kubectl apply -n "${ARGO_NAMESPACE}" -f "${ROOT_FILE}"

echo "✅ Argo CD bootstrapped for '${DEPLOY_ENV}'."
echo "Check: kubectl -n ${ARGO_NAMESPACE} get applications"
