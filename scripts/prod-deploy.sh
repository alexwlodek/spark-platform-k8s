#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/validate-env.sh
source "${SCRIPT_DIR}/lib/validate-env.sh"
# shellcheck source=lib/terraform.sh
source "${SCRIPT_DIR}/lib/terraform.sh"

MODE="all"
AUTO_APPROVE="${AUTO_APPROVE:-1}"
ENV_NAME="prod"
ENV_FILE=""

usage() {
  cat <<'EOF'
Usage:
  ./scripts/prod-deploy.sh [--network | --gke | --platform | --infra | --bootstrap | --all] [--manual-approve] [--env-file local/prod.env.sh]

Modes:
  --network      Apply only infra/envs/prod/00-network
  --gke          Apply only infra/envs/prod/10-gke
  --platform     Apply only infra/envs/prod/20-shared-services
  --infra        Apply all Terraform stages in order
  --bootstrap    Fetch credentials and bootstrap Argo CD on the prod cluster
  --all          Run infra first, then bootstrap (default)

Options:
  --auto-approve Explicitly enable automatic Terraform apply confirmation (default)
  --manual-approve Require manual confirmation during Terraform apply
  --env-file     Override the default env file (local/prod.env.sh)
  -h, --help     Show this help

Notes:
  scripts/prod-deploy.sh is kept as a compatibility wrapper.
  The preferred entrypoints are:
    ./scripts/prod-up.sh --env prod
    ./scripts/prod-destroy.sh --env prod
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --network)
        MODE="network"
        shift
        ;;
      --gke)
        MODE="gke"
        shift
        ;;
      --platform)
        MODE="platform"
        shift
        ;;
      --infra)
        MODE="infra"
        shift
        ;;
      --bootstrap)
        MODE="bootstrap"
        shift
        ;;
      --all)
        MODE="all"
        shift
        ;;
      --auto-approve)
        AUTO_APPROVE="1"
        shift
        ;;
      --manual-approve)
        AUTO_APPROVE="0"
        shift
        ;;
      --env-file)
        [[ $# -ge 2 ]] || die "Missing value for --env-file"
        ENV_FILE="$2"
        shift 2
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

run_stage() {
  local stage_name="$1"
  terraform_init_apply_dir "$(prod_stage_dir "${ENV_NAME}" "${stage_name}")" "${AUTO_APPROVE}"
}

run_bootstrap() {
  validate_prod_env
  log "Setting active gcloud project to ${GCP_PROJECT_ID}"
  gcloud config set project "${GCP_PROJECT_ID}" >/dev/null

  log "Fetching credentials for GKE cluster ${GKE_CLUSTER_NAME}"
  gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
    --region "${GCP_REGION}" \
    --project "${GCP_PROJECT_ID}" >/dev/null

  exec "${SCRIPT_DIR}/bootstrap-argocd.sh" --env "${ENV_NAME}" --context "${KUBE_CONTEXT}"
}

parse_args "$@"

ENV_FILE="${ENV_FILE:-$(default_env_file "${ENV_NAME}")}"

log "Loading environment from ${ENV_FILE}"
load_env_file "${ENV_FILE}"
apply_prod_env_defaults
export_prod_terraform_vars

case "${MODE}" in
  network)
    validate_prod_destroy_env
    run_stage "00-network"
    ;;
  gke)
    validate_prod_destroy_env
    run_stage "10-gke"
    ;;
  platform)
    validate_prod_destroy_env
    run_stage "20-shared-services"
    ;;
  infra)
    validate_prod_destroy_env
    run_stage "00-network"
    run_stage "10-gke"
    run_stage "20-shared-services"
    ;;
  bootstrap)
    run_bootstrap
    ;;
  all)
    if [[ "${AUTO_APPROVE}" == "1" ]]; then
      exec "${SCRIPT_DIR}/prod-up.sh" --env "${ENV_NAME}" --auto-approve
    fi
    exec "${SCRIPT_DIR}/prod-up.sh" --env "${ENV_NAME}"
    ;;
esac

printf '\n'
log "Completed prod-deploy mode: ${MODE}"
