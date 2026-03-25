#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_GCP_ROOT_DIR="${TERRAFORM_GCP_ROOT_DIR:-${REPO_ROOT}/infra/envs/gcp}"
TERRAFORM_GCP_NETWORK_DIR="${TERRAFORM_GCP_NETWORK_DIR:-${TERRAFORM_GCP_ROOT_DIR}/network}"
TERRAFORM_GCP_GKE_DIR="${TERRAFORM_GCP_GKE_DIR:-${TERRAFORM_GCP_ROOT_DIR}/gke}"
TERRAFORM_GCP_PLATFORM_DIR="${TERRAFORM_GCP_PLATFORM_DIR:-${TERRAFORM_GCP_ROOT_DIR}/platform}"

MODE="all"
AUTO_APPROVE="${AUTO_APPROVE:-0}"

usage() {
  cat <<'EOF'
Usage:
  scripts/prod-deploy.sh [--network | --gke | --platform | --infra | --bootstrap | --all] [--auto-approve]

Modes:
  --network      Run Terraform init + apply for shared production network resources
  --gke          Run Terraform init + apply for the production GKE cluster
  --platform     Run Terraform init + apply for production managed data services
  --infra        Run network first, then GKE, then managed data services
  --bootstrap    Configure kube context, seed Argo CD secret, bootstrap Argo CD
  --all          Run infra first, then bootstrap (default)

Options:
  --auto-approve Pass -auto-approve to terraform apply
  -h, --help     Show this help

Useful env overrides:
  TERRAFORM_GCP_ROOT_DIR
  TERRAFORM_GCP_NETWORK_DIR
  TERRAFORM_GCP_GKE_DIR
  TERRAFORM_GCP_PLATFORM_DIR
  PROJECT_ID
  REGION
  CLUSTER_NAME
  AUTO_APPROVE=1
  ARGOCD_ADMIN_PASSWORD
  ARGOCD_ADMIN_BCRYPT_HASH
  GRAFANA_ADMIN_USER
  GRAFANA_ADMIN_PASSWORD
  CLOUDFLARE_API_TOKEN
EOF
}

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing dependency: $1" >&2
    exit 1
  }
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --infra)
        MODE="infra"
        ;;
      --network)
        MODE="network"
        ;;
      --gke)
        MODE="gke"
        ;;
      --platform)
        MODE="platform"
        ;;
      --bootstrap)
        MODE="bootstrap"
        ;;
      --all)
        MODE="all"
        ;;
      --auto-approve)
        AUTO_APPROVE="1"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        echo >&2
        usage >&2
        exit 1
        ;;
    esac
    shift
  done
}

run_terraform_stack() {
  local stack_name="$1"
  local terraform_dir="$2"

  require terraform

  if [[ ! -d "${terraform_dir}" ]]; then
    echo "Missing Terraform directory for ${stack_name}: ${terraform_dir}" >&2
    exit 1
  fi

  echo "Running Terraform init for ${stack_name} in ${terraform_dir}..."
  terraform -chdir="${terraform_dir}" init

  echo "Applying ${stack_name}..."
  if [[ "${AUTO_APPROVE}" == "1" ]]; then
    terraform -chdir="${terraform_dir}" apply -auto-approve
  else
    terraform -chdir="${terraform_dir}" apply
  fi
}

run_network() {
  run_terraform_stack "PROD network stack" "${TERRAFORM_GCP_NETWORK_DIR}"
}

run_gke() {
  run_terraform_stack "PROD GKE stack" "${TERRAFORM_GCP_GKE_DIR}"
}

run_platform() {
  run_terraform_stack "PROD managed platform services stack" "${TERRAFORM_GCP_PLATFORM_DIR}"
}

run_infra() {
  run_network
  run_gke
  run_platform
}

run_bootstrap() {
  echo "Bootstrapping Argo CD and production platform apps on GKE..."
  "${SCRIPT_DIR}/prod-up.sh"
}

parse_args "$@"

case "${MODE}" in
  network)
    run_network
    ;;
  gke)
    run_gke
    ;;
  platform)
    run_platform
    ;;
  infra)
    run_infra
    ;;
  bootstrap)
    run_bootstrap
    ;;
  all)
    run_infra
    run_bootstrap
    ;;
esac

echo
echo "Completed PROD deploy mode: ${MODE}"
