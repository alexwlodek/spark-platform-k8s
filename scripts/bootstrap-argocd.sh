#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DEPLOY_ENV="${DEPLOY_ENV:-dev}"
KUBE_CONTEXT="${KUBE_CONTEXT:-}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
ARGO_RELEASE_NAME="${ARGO_RELEASE_NAME:-argocd}"
ARGO_HELM_REPO_NAME="${ARGO_HELM_REPO_NAME:-argo}"
ARGO_HELM_REPO_URL="${ARGO_HELM_REPO_URL:-https://argoproj.github.io/argo-helm}"
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-7.7.0}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-300s}"
SKIP_INSTALL="${SKIP_INSTALL:-0}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/bootstrap-argocd.sh --env <name> [--context <kubectl-context>] [--namespace <name>] [--skip-install]

Options:
  --env <name>        Deployment environment directory under clusters/<env>
  --context <name>    kubectl context to use before bootstrapping
  --namespace <name>  Argo CD namespace (default: argocd)
  --skip-install      Skip the Helm install/upgrade and only apply bootstrap manifests
  -h, --help          Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env)
        [[ $# -ge 2 ]] || die "Missing value for --env"
        DEPLOY_ENV="$2"
        shift 2
        ;;
      --context)
        [[ $# -ge 2 ]] || die "Missing value for --context"
        KUBE_CONTEXT="$2"
        shift 2
        ;;
      --namespace)
        [[ $# -ge 2 ]] || die "Missing value for --namespace"
        ARGO_NAMESPACE="$2"
        shift 2
        ;;
      --skip-install)
        SKIP_INSTALL="1"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

ensure_bootstrap_argocd_secret() {
  local bootstrap_secret_name="argocd-secret"
  local bootstrap_secret_key

  if kubectl -n "${ARGO_NAMESPACE}" get secret "${bootstrap_secret_name}" >/dev/null 2>&1; then
    return 0
  fi

  log "Creating bootstrap ${ARGO_NAMESPACE}/${bootstrap_secret_name} (server.secretkey only)"
  bootstrap_secret_key="$(head -c 32 /dev/urandom | base64 | tr -d '\r\n')"

  kubectl -n "${ARGO_NAMESPACE}" create secret generic "${bootstrap_secret_name}" \
    --from-literal=server.secretkey="${bootstrap_secret_key}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

seed_prod_bootstrap_inputs() {
  log "Seeding prod bootstrap secrets in GCP Secret Manager"
  "${SCRIPT_DIR}/prod-cloudflare-secret-seed.sh"
  "${SCRIPT_DIR}/prod-grafana-secret-seed.sh"

  APPLY_K8S_SECRET=1 \
  ARGO_NAMESPACE="${ARGO_NAMESPACE}" \
  "${SCRIPT_DIR}/prod-argocd-secret-seed.sh"
}

wait_for_argocd_rollout() {
  log "Waiting for Argo CD control plane to become ready"
  kubectl rollout status -n "${ARGO_NAMESPACE}" "statefulset/${ARGO_RELEASE_NAME}-application-controller" --timeout="${ROLLOUT_TIMEOUT}"
  kubectl rollout status -n "${ARGO_NAMESPACE}" "deployment/${ARGO_RELEASE_NAME}-repo-server" --timeout="${ROLLOUT_TIMEOUT}"
  kubectl rollout status -n "${ARGO_NAMESPACE}" "deployment/${ARGO_RELEASE_NAME}-server" --timeout="${ROLLOUT_TIMEOUT}"

  if kubectl get deployment -n "${ARGO_NAMESPACE}" "${ARGO_RELEASE_NAME}-dex-server" >/dev/null 2>&1; then
    kubectl rollout status -n "${ARGO_NAMESPACE}" "deployment/${ARGO_RELEASE_NAME}-dex-server" --timeout="${ROLLOUT_TIMEOUT}"
  fi
}

parse_args "$@"

need_cmd kubectl

if [[ "${DEPLOY_ENV}" == "prod" && -z "${GCP_PROJECT_ID:-${PROJECT_ID:-}}" ]]; then
  DEFAULT_PROD_ENV_FILE="$(default_env_file prod)"
  if [[ -f "${DEFAULT_PROD_ENV_FILE}" ]]; then
    log "Loading prod environment from ${DEFAULT_PROD_ENV_FILE}"
    load_env_file "${DEFAULT_PROD_ENV_FILE}"
  fi
fi

ROOT_FILE="$(repo_root)/clusters/${DEPLOY_ENV}/root.yaml"
PROJECT_FILE="$(repo_root)/clusters/${DEPLOY_ENV}/projects/platform.yaml"
COMMON_VALUES_FILE="$(repo_root)/values/common/argocd.yaml"
ENV_VALUES_FILE="$(repo_root)/values/${DEPLOY_ENV}/argocd.yaml"

[[ -f "${ROOT_FILE}" ]] || die "Missing root app manifest: ${ROOT_FILE}"
[[ -f "${PROJECT_FILE}" ]] || die "Missing AppProject manifest: ${PROJECT_FILE}"
[[ -f "${COMMON_VALUES_FILE}" ]] || die "Missing values file: ${COMMON_VALUES_FILE}"
[[ -f "${ENV_VALUES_FILE}" ]] || die "Missing values file: ${ENV_VALUES_FILE}"

if [[ -n "${KUBE_CONTEXT}" ]]; then
  log "Switching kubectl context to ${KUBE_CONTEXT}"
  kubectl config use-context "${KUBE_CONTEXT}" >/dev/null
fi

if [[ "${DEPLOY_ENV}" == "prod" ]]; then
  apply_prod_env_defaults
  seed_prod_bootstrap_inputs
fi

CURRENT_CONTEXT="$(kubectl config current-context)"
log "Bootstrapping Argo CD for ${DEPLOY_ENV} on context ${CURRENT_CONTEXT}"

log "Ensuring namespace ${ARGO_NAMESPACE} exists"
kubectl get ns "${ARGO_NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${ARGO_NAMESPACE}" >/dev/null

if [[ "${SKIP_INSTALL}" != "1" ]]; then
  need_cmd helm

  log "Installing or upgrading Argo CD ${ARGOCD_CHART_VERSION}"
  helm repo add "${ARGO_HELM_REPO_NAME}" "${ARGO_HELM_REPO_URL}" --force-update >/dev/null
  helm repo update "${ARGO_HELM_REPO_NAME}" >/dev/null

  helm upgrade --install "${ARGO_RELEASE_NAME}" "${ARGO_HELM_REPO_NAME}/argo-cd" \
    --namespace "${ARGO_NAMESPACE}" \
    --version "${ARGOCD_CHART_VERSION}" \
    -f "${COMMON_VALUES_FILE}" \
    -f "${ENV_VALUES_FILE}" \
    --timeout "${ROLLOUT_TIMEOUT}"
else
  log "Skipping Argo CD install/upgrade because --skip-install was passed"
fi

log "Waiting for Argo CD CRDs"
kubectl wait --for=condition=Established --timeout="${ROLLOUT_TIMEOUT}" crd/appprojects.argoproj.io crd/applications.argoproj.io

ensure_bootstrap_argocd_secret

log "Applying AppProject and root application for ${DEPLOY_ENV}"
kubectl apply -n "${ARGO_NAMESPACE}" -f "${PROJECT_FILE}" >/dev/null
kubectl apply -n "${ARGO_NAMESPACE}" -f "${ROOT_FILE}" >/dev/null

wait_for_argocd_rollout

log "Argo CD bootstrap complete for ${DEPLOY_ENV}"
printf 'Check: kubectl -n %s get applications\n' "${ARGO_NAMESPACE}"
