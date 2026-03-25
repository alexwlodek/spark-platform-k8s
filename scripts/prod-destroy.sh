#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/validate-env.sh
source "${SCRIPT_DIR}/lib/validate-env.sh"
# shellcheck source=lib/terraform.sh
source "${SCRIPT_DIR}/lib/terraform.sh"

ENV_NAME=""
ENV_FILE=""
FORCE="0"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/prod-destroy.sh --env prod [--env-file local/prod.env.sh] [--force]

Options:
  --env <name>        Environment to destroy (currently only: prod)
  --env-file <path>   Override the default local env file path
  --force             Skip the interactive confirmation prompt
  -h, --help          Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env)
        [[ $# -ge 2 ]] || die "Missing value for --env"
        ENV_NAME="$2"
        shift 2
        ;;
      --env-file)
        [[ $# -ge 2 ]] || die "Missing value for --env-file"
        ENV_FILE="$2"
        shift 2
        ;;
      --force)
        FORCE="1"
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

cluster_exists() {
  gcloud container clusters describe "${GKE_CLUSTER_NAME}" \
    --region "${GCP_REGION}" \
    --project "${GCP_PROJECT_ID}" >/dev/null 2>&1
}

cleanup_argocd_bootstrap() {
  local root_file
  local project_file

  root_file="$(repo_root)/clusters/${ENV_NAME}/root.yaml"
  project_file="$(repo_root)/clusters/${ENV_NAME}/projects/platform.yaml"

  if ! cluster_exists; then
    warn "GKE cluster ${GKE_CLUSTER_NAME} is not reachable, skipping in-cluster Argo CD cleanup"
    return 0
  fi

  log "Fetching credentials for in-cluster cleanup"
  gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
    --region "${GCP_REGION}" \
    --project "${GCP_PROJECT_ID}" >/dev/null

  if [[ -n "${KUBE_CONTEXT:-}" ]]; then
    kubectl config use-context "${KUBE_CONTEXT}" >/dev/null 2>&1 || true
  fi

  if [[ -f "${root_file}" ]]; then
    log "Removing root Argo CD application"
    kubectl delete -n "${ARGO_NAMESPACE}" -f "${root_file}" --ignore-not-found >/dev/null 2>&1 || warn "Unable to delete ${root_file}"
  fi

  if [[ -f "${project_file}" ]]; then
    log "Removing platform AppProject"
    kubectl delete -n "${ARGO_NAMESPACE}" -f "${project_file}" --ignore-not-found >/dev/null 2>&1 || warn "Unable to delete ${project_file}"
  fi

  if helm -n "${ARGO_NAMESPACE}" status "${ARGO_RELEASE_NAME}" >/dev/null 2>&1; then
    log "Uninstalling Argo CD Helm release ${ARGO_RELEASE_NAME}"
    helm -n "${ARGO_NAMESPACE}" uninstall "${ARGO_RELEASE_NAME}" >/dev/null 2>&1 || warn "Unable to uninstall Argo CD cleanly"
  fi
}

parse_args "$@"

[[ -n "${ENV_NAME}" ]] || die "Use --env prod"
[[ "${ENV_NAME}" == "prod" ]] || die "Only --env prod is currently supported"

ENV_FILE="${ENV_FILE:-$(default_env_file "${ENV_NAME}")}"

log "Loading environment from ${ENV_FILE}"
load_env_file "${ENV_FILE}"
validate_prod_destroy_env
export_prod_terraform_vars

NETWORK_DIR="$(prod_stage_dir "${ENV_NAME}" "00-network")"
GKE_DIR="$(prod_stage_dir "${ENV_NAME}" "10-gke")"
SHARED_SERVICES_DIR="$(prod_stage_dir "${ENV_NAME}" "20-shared-services")"

if [[ "${FORCE}" != "1" ]]; then
  printf 'Environment: %s\n' "${ENV_NAME}"
  printf 'Project: %s\n' "${GCP_PROJECT_ID}"
  printf 'Cluster: %s\n' "${GKE_CLUSTER_NAME}"
  printf 'Stages: 20-shared-services -> 10-gke -> 00-network\n'
  confirm_or_die "Destroy the production infrastructure and bootstrap resources?"
fi

log "Setting active gcloud project to ${GCP_PROJECT_ID}"
gcloud config set project "${GCP_PROJECT_ID}" >/dev/null

cleanup_argocd_bootstrap

export TF_VAR_lake_bucket_force_destroy="true"

log "Destroying staged Terraform for ${ENV_NAME} in reverse order"
terraform_destroy_dir "${SHARED_SERVICES_DIR}" "1"
terraform_destroy_dir "${GKE_DIR}" "1"
terraform_destroy_dir "${NETWORK_DIR}" "1"

printf '\n'
log "Production infrastructure destroy completed"
